import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'item.dart';
import 'data_api.dart';

typedef SnapshotWriter = Future<void> Function(Map<String, dynamic> data);

/// One serialized snapshot per account; no nested mutable Rx objects.
class PlannerRepository extends ChangeNotifier implements PlannerDataApi {
  Map<String, dynamic> _state;
  final SnapshotWriter writer;
  Future<void> _tail = Future.value();
  List<Item> _items = [];
  final String scope;
  bool _closed = false;
  PlannerRepository({
    required this.scope,
    required this.writer,
    Map<String, dynamic>? initial,
  }) : _state =
           initial ??
           {
             'schemaVersion': 1,
             'items': [],
             'preferences': '',
             'sync': {},
             'sessions': [],
           } {
    _rebuild();
  }
  static Future<PlannerRepository> open(String scope) async {
    final box = await Hive.openBox<String>('planner_v1_${stableId(scope)}');
    final raw = box.get('snapshot');
    // Never silently overwrite an unreadable snapshot.
    final initial = raw == null
        ? null
        : jsonDecode(raw) as Map<String, dynamic>;
    return PlannerRepository(
      scope: scope,
      initial: initial,
      writer: (data) => box.put('snapshot', jsonEncode(data)),
    );
  }

  /// Local-only bootstrap pointer: no credentials or network on the first frame.
  static Future<PlannerRepository> openLastAccount() async {
    final box = await Hive.openBox<String>('planner_bootstrap_v1');
    return open(box.get('last_scope') ?? 'local');
  }

  static Future<void> rememberAccount(String scope) async {
    final box = await Hive.openBox<String>('planner_bootstrap_v1');
    await box.put('last_scope', scope);
  }

  void _rebuild() {
    _items =
        (List.from(_state['items'] as List? ?? [])
            .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort(
            (a, b) => (a.sortTime ?? DateTime(9999)).compareTo(
              b.sortTime ?? DateTime(9999),
            ),
          ));
  }

  @override
  List<Item> get items => List.unmodifiable(_items);
  @override
  String get preferences => _state['preferences'] as String? ?? '';
  @override
  Map<String, dynamic> get syncStatus =>
      Map<String, dynamic>.from(_state['sync'] as Map? ?? {});
  @override
  List<Map<String, dynamic>> get sessions =>
      (jsonDecode(jsonEncode(_state['sessions'] ?? [])) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Item? find(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> transaction(void Function(Map<String, dynamic> state) edit) {
    if (_closed) return Future.error(StateError("数据仓库已关闭"));
    final result = _tail.then((_) async {
      final next = jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
      edit(next);
      await writer(next);
      _state = next;
      _rebuild();
      if (!_closed) notifyListeners();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> saveItem(Item item) {
    item.validate();
    return transaction((state) {
      final list = state['items'] as List;
      final index = list.indexWhere((e) => e['id'] == item.id);
      if (index >= 0 && list[index]['revision'] != item.revision - 1) {
        throw const FormatException('事项已更新，请重新打开编辑');
      }
      if (index < 0 && item.revision != 0) {
        throw const FormatException('事项已删除，请重新创建');
      }
      if (index >= 0 && list[index]['origin'] == 'school') {
        final old = Map<String, dynamic>.from(list[index] as Map);
        final changed = item.toJson();
        for (final key in old.keys.where(
          (k) => ![
            'notes',
            'estimatedMinutes',
            'completed',
            'revision',
          ].contains(k),
        )) {
          if (old[key] != changed[key]) {
            throw const FormatException('学校事项的基本信息由学校同步维护');
          }
        }
      }
      if (index < 0) {
        list.add(item.toJson());
      } else {
        list[index] = item.toJson();
      }
      if (item.completed) _removePendingChildren(list, item.id);
    });
  }

  @override
  Future<void> removeItem(String id) => transaction((state) {
    final list = state['items'] as List;
    final item = list.where((e) => e['id'] == id).firstOrNull;
    if (item != null && item['origin'] == 'school') {
      throw const FormatException('学校事项请在来源系统修改，可在这里标记完成');
    }
    list.removeWhere((e) => e['id'] == id);
    _removePendingChildren(list, id);
  });
  static void _removePendingChildren(List list, String id) {
    list.removeWhere(
      (e) =>
          e['parentId'] == id &&
          e['origin'] == 'agent' &&
          e['start'] != null &&
          DateTime.parse(e['start'] as String).isAfter(DateTime.now()),
    );
  }

  Future<void> mergeSchool(
    String partition,
    List<Item> incoming, {
    required bool fresh,
    String? error,
  }) => transaction((state) {
    final sync = state['sync'] as Map;
    sync[partition] = {
      'checkedAt': timestamp(DateTime.now()),
      'updatedAt': fresh
          ? timestamp(DateTime.now())
          : (sync[partition] as Map?)?['updatedAt'],
      'error': error,
    };
    if (!fresh) return;
    final list = state['items'] as List;
    final previous = {
      for (final e in list.where((e) => e['sourceKey'] == partition))
        e['id']: e,
    };
    list.removeWhere((e) => e['sourceKey'] == partition);
    final incomingIds = incoming.map((e) => e.id).toSet();
    for (final old in previous.keys) {
      if (!incomingIds.contains(old)) {
        _removePendingChildren(list, old as String);
        if (previous[old]['completed'] == true) list.add(previous[old]);
      }
    }
    for (final item in incoming) {
      final old = previous[item.id];
      final merged = <String, dynamic>{
        ...item.toJson(),
        if (old != null) ...{
          'completed': old['completed'],
          'estimatedMinutes': old['estimatedMinutes'],
          'notes': old['notes'],
          'revision': old['revision'] ?? 0,
        },
      };
      if (old != null && jsonEncode(merged) != jsonEncode(old)) {
        merged['revision'] = (old['revision'] as int? ?? 0) + 1;
      }
      list.add(merged);
    }
  });
  @override
  Future<void> setPreferences(String value) => transaction((s) {
    if (value.length > 6000) throw const FormatException('偏好最多6000字');
    s['preferences'] = value;
  });
  @override
  Future<void> saveSession(Map<String, dynamic> session) =>
      transaction((state) {
        final sessions = state['sessions'] as List;
        final index = sessions.indexWhere((e) => e['id'] == session['id']);
        if (index < 0) {
          sessions.insert(0, {
            ...session,
            'createdAt': session['createdAt'] ?? timestamp(DateTime.now()),
            'updatedAt': session['updatedAt'] ?? timestamp(DateTime.now()),
          });
        } else {
          sessions[index] = session;
        }
      });
  @override
  Future<void> deleteSession(String id) => transaction((state) {
    (state['sessions'] as List).removeWhere((e) => e['id'] == id);
  });
  Future<void> appendMessages(
    String id,
    List<Map<String, dynamic>> messages, {
    String? initialTitle,
    bool supersedeDrafts = false,
  }) => transaction((state) {
    final session = (state['sessions'] as List)
        .where((s) => s['id'] == id)
        .firstOrNull;
    if (session == null) throw const FormatException('会话已删除');
    final history = session['messages'] as List;
    if (history.isEmpty && initialTitle != null) {
      session['title'] = initialTitle;
    }
    if (supersedeDrafts) {
      for (final m in history) {
        if (m['draft'] != null &&
            m['draftStatus'] == null &&
            m['applied'] != true) {
          m['draftStatus'] = 'superseded';
        }
      }
    }
    history.addAll(messages);
    session['updatedAt'] = timestamp(DateTime.now());
  });
  Future<void> renameSession(String id, String title) => transaction((state) {
    if (title.trim().isEmpty || title.length > 60) {
      throw const FormatException('会话名称需为1–60字');
    }
    final session = (state['sessions'] as List)
        .where((s) => s['id'] == id)
        .firstOrNull;
    if (session == null) throw const FormatException('会话已删除');
    session['title'] = title.trim();
  });
  Future<void> dismissDraft(String sessionId, String draftId) =>
      transaction((state) {
        final session = (state['sessions'] as List)
            .where((s) => s['id'] == sessionId)
            .firstOrNull;
        if (session == null) return;
        for (final m in session['messages'] as List) {
          if (m['draft']?['draftId'] == draftId && m['draftStatus'] == null) {
            m['draftStatus'] = 'dismissed';
          }
        }
      });
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
