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
    final result = _tail.then((_) async {
      final next = jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
      edit(next);
      await writer(next);
      _state = next;
      _rebuild();
      notifyListeners();
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
      }
    }
    for (final item in incoming) {
      final old = previous[item.id];
      list.add({
        ...item.toJson(),
        if (old != null) ...{
          'completed': old['completed'],
          'estimatedMinutes': old['estimatedMinutes'],
          'notes': old['notes'],
          'revision': (old['revision'] as int? ?? 0) + 1,
        },
      });
    }
  });
  @override
  Future<void> setPreferences(String value) => transaction((s) {
    s['preferences'] = value;
  });
  @override
  Future<void> saveSession(Map<String, dynamic> session) =>
      transaction((state) {
        final sessions = state['sessions'] as List;
        final index = sessions.indexWhere((e) => e['id'] == session['id']);
        if (index < 0) {
          sessions.insert(0, session);
        } else {
          sessions[index] = session;
        }
      });
  @override
  Future<void> deleteSession(String id) => transaction((state) {
    (state['sessions'] as List).removeWhere((e) => e['id'] == id);
  });
}
