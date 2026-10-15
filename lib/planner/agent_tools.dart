import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'item.dart';
import 'repository.dart';

/// Shared, deliberately narrow capabilities for the in-app agent and MCP.
class PlannerTools {
  final PlannerRepository repo;
  PlannerTools(this.repo);
  String fingerprint(List<Item> items) =>
      stableId(jsonEncode(items.map((e) => e.toJson()).toList()));
  Map<String, dynamic> context() {
    final now = DateTime.now();
    final until = now.add(const Duration(days: 31));
    final items = repo.items
        .where(
          (e) =>
              !e.completed &&
              (e.sortTime == null || e.sortTime!.isBefore(until)) &&
              (e.end == null || e.end!.isAfter(now)),
        )
        .toList();
    return {
      'now': now.toIso8601String(),
      'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
      'windowEnd': timestamp(until),
      'preferences': repo.preferences,
      'sync': repo.syncStatus,
      'items': items.map((e) => e.toJson()).toList(),
      'instruction': '预计用时为 null 时必须询问用户填写，不得猜测。学校数据可能缓存，请检查 sync。',
    };
  }

  static const definitions = <Map<String, dynamic>>[
    {
      'name': 'get_schedule_context',
      'description': '读取当前时间、未来31天课表、考试、任务、截止日期、用户填写的预计用时及同步状态。',
      'inputSchema': {
        'type': 'object',
        'properties': {},
        'additionalProperties': false,
      },
    },
    {
      'name': 'propose_schedule',
      'description': '提交待确认的日程变更。只允许添加固定时间块或修改/删除本地固定日程。不会直接写入日程。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'summary': {'type': 'string'},
          'operations': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 40,
            'items': {
              'type': 'object',
              'properties': {
                'action': {
                  'type': 'string',
                  'enum': ['add', 'update', 'delete'],
                },
                'id': {'type': 'string', 'description': '修改或删除的现有事项ID'},
                'title': {'type': 'string'},
                'subject': {'type': 'string'},
                'start': {'type': 'string', 'description': 'ISO8601，必须带时区偏移'},
                'end': {'type': 'string', 'description': 'ISO8601，必须带时区偏移'},
                'parentId': {
                  'type': 'string',
                  'description': '安排作业/任务时必须关联其ID，且用户已填写预计用时',
                },
              },
              'required': ['action'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['summary', 'operations'],
        'additionalProperties': false,
      },
    },
  ];
  Map<String, dynamic> draft(Map<String, dynamic> args) {
    final result = {
      ...args,
      'draftId': const Uuid().v4(),
      'baseline': fingerprint(repo.items),
      'createdAt': timestamp(DateTime.now()),
    };
    // Allocate stable IDs before preview, so confirmation is idempotent.
    result['operations'] = (args['operations'] as List)
        .map(
          (e) => {
            ...Map<String, dynamic>.from(e as Map),
            if (e['action'] == 'add') 'id': const Uuid().v4(),
          },
        )
        .toList();
    validate(result, repo.items);
    return result;
  }

  List<Item> validate(Map<String, dynamic> draft, List<Item> current) {
    if (draft['baseline'] != fingerprint(current)) {
      throw const FormatException('事项已变化，请让 Agent 重新生成方案');
    }
    final operations = draft['operations'] as List;
    if (operations.isEmpty || operations.length > 40) {
      throw const FormatException('每次安排1–40项');
    }
    final next = {for (final i in current) i.id: i};
    final changed = <String>{};
    final now = DateTime.now();
    for (final raw in operations) {
      final op = Map<String, dynamic>.from(raw as Map);
      final id = op['id'] as String;
      if (!changed.add(id)) throw const FormatException('同一事项不能重复修改');
      final old = next[id];
      final action = op['action'];
      if (action != 'add' &&
          (old == null || old.school || old.categoryId != 'event')) {
        throw const FormatException('只能修改或删除本地固定日程');
      }
      if (action == 'delete') {
        next.remove(id);
        continue;
      }
      if (action != 'add' && action != 'update') {
        throw const FormatException('未知操作');
      }
      if (action == 'add' && old != null) throw const FormatException('事项ID重复');
      final data = <String, dynamic>{
        if (old != null) ...old.toJson(),
        ...op,
        'id': id,
        'categoryId': 'event',
        'origin': 'agent',
        'revision': old == null ? 0 : old.revision + 1,
      };
      for (final field in ['start', 'end']) {
        final rawDate = data[field];
        if (rawDate is! String ||
            !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(rawDate)) {
          throw const FormatException('时间必须包含时区');
        }
      }
      final item = Item.fromJson(data);
      item.validate();
      if (!item.timed ||
          item.start!.isBefore(now) ||
          item.end!.isAfter(now.add(const Duration(days: 31)))) {
        throw const FormatException('只能安排未来31天内的时间段');
      }
      if (item.parentId != null) {
        final parent = next[item.parentId];
        if (parent == null || parent.completed) {
          throw const FormatException('关联任务不存在或已完成');
        }
        if (parent.estimatedMinutes == null) {
          throw const FormatException('请先由用户填写关联事项的预计用时');
        }
        if (parent.deadline != null && item.end!.isAfter(parent.deadline!)) {
          throw const FormatException('安排晚于任务截止时间');
        }
      }
      next[id] = item;
    }
    for (final id in changed) {
      final item = next[id];
      if (item == null) continue;
      for (final other in next.values) {
        if (other.id != id && !other.completed && item.overlaps(other)) {
          throw FormatException('「${item.title}」与「${other.title}」时间冲突');
        }
      }
    }
    final allocated = <String, int>{};
    for (final item in next.values.where(
      (e) =>
          e.parentId != null && e.timed && !e.completed && e.end!.isAfter(now),
    )) {
      allocated.update(
        item.parentId!,
        (n) => n + item.end!.difference(item.start!).inMinutes,
        ifAbsent: () => item.end!.difference(item.start!).inMinutes,
      );
    }
    for (final id in allocated.keys) {
      final parent = next[id];
      if (parent?.estimatedMinutes != null &&
          allocated[id]! > parent!.estimatedMinutes!) {
        throw FormatException('「${parent.title}」安排总时长超过用户填写的预计用时');
      }
    }
    return next.values.toList();
  }

  Future<void> apply(Map<String, dynamic> draft) => repo.transaction((state) {
    final applied = List<String>.from(state['appliedDrafts'] as List? ?? []);
    if (applied.contains(draft['draftId'])) {
      throw const FormatException('此方案已经应用');
    }
    final current =
        (state['items'] as List)
            .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort(
            (a, b) => (a.sortTime ?? DateTime(9999)).compareTo(
              b.sortTime ?? DateTime(9999),
            ),
          );
    final next = validate(draft, current);
    state['items'] = next.map((e) => e.toJson()).toList();
    applied.add(draft['draftId'] as String);
    state['appliedDrafts'] = applied;
  });
  Future<Map<String, dynamic>> saveMcpDraft(Map<String, dynamic> args) async {
    final plan = draft(args);
    await repo.saveSession({
      'id': const Uuid().v4(),
      'title': 'MCP 日程方案',
      'messages': [
        {
          'role': 'assistant',
          'content': args['summary'] ?? '待确认方案',
          'draft': plan,
        },
      ],
    });
    return {
      'status': 'pending_confirmation',
      'draftId': plan['draftId'],
      'message': '已放入 App 的 Agent 会话，用户点击确认后才会写入。',
    };
  }
}
