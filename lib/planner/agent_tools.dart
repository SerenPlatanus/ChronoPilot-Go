import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'item.dart';
import 'repository.dart';
import 'schedule_audit.dart';

/// Shared read/propose capabilities. Applying a draft is an app-only action.
class PlannerTools {
  final PlannerRepository repo;
  final DateTime Function() clock;
  PlannerTools(this.repo, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  String fingerprint(List<Item> items) {
    final sorted = items.toList()..sort((a, b) => a.id.compareTo(b.id));
    return stableId(jsonEncode(sorted.map((e) => e.toJson()).toList()));
  }

  String get contextVersion =>
      stableId('${fingerprint(repo.items)}:${repo.preferences}');
  Map<String, dynamic> context() {
    final now = clock();
    final until = now.add(const Duration(days: 31));
    final all = repo.items
        .where(
          (e) =>
              !e.completed &&
              (e.sortTime == null || e.sortTime!.isBefore(until)) &&
              (e.end == null || e.end!.isAfter(now)),
        )
        .toList();
    // Fail clearly rather than silently omit occupied periods from model input.
    if (all.length > 1500) throw const FormatException('未来事项过多，请先整理已完成任务');
    final allocated = <String, int>{};
    for (final i in repo.items.where((e) => e.parentId != null && e.timed)) {
      allocated.update(
        i.parentId!,
        (n) => n + i.end!.difference(i.start!).inSeconds,
        ifAbsent: () => i.end!.difference(i.start!).inSeconds,
      );
    }
    return {
      'now': timestamp(now),
      'contextVersion': contextVersion,
      'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
      'localNow': now.toIso8601String(),
      'windowEnd': timestamp(until),
      'preferences': repo.preferences,
      'planningWarnings': scheduleWarnings(repo.items, now),
      'sync': repo.syncStatus,
      'items': all
          .map(
            (e) => {
              ...e.toJson(),
              if (e.estimatedMinutes != null)
                'unallocatedMinutes':
                    ((e.estimatedMinutes! * 60 - (allocated[e.id] ?? 0)) / 60)
                        .clamp(0, e.estimatedMinutes!)
                        .toDouble(),
            },
          )
          .toList(),
      'instruction':
          '只安排已有作业、个人任务或考试复习；预计用时必须用户填写。已分配时间包含过去及已完成时间块。检查同步状态；所有变更待用户确认。',
    };
  }

  static const definitions = <Map<String, dynamic>>[
    {
      'name': 'get_schedule_context',
      'description': '读取当前时间、未来31天课表、考试、任务、截止日期、用户用时、偏好与同步状态。',
      'inputSchema': {
        'type': 'object',
        'properties': {},
        'additionalProperties': false,
      },
    },
    {
      'name': 'propose_schedule',
      'description':
          '为已有作业、考试复习或个人任务提出时间块方案；必须关联已有事项。修改/删除只能针对此前 Agent 时间块。仅生成草稿，不写入日程。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'summary': {'type': 'string', 'maxLength': 1000},
          'contextVersion': {
            'type': 'string',
            'description':
                '必须原样提供最近 get_schedule_context 或注入数据中的 contextVersion',
          },
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
                'id': {
                  'type': 'string',
                  'description': 'update/delete 的现有 Agent 时间块 ID',
                },
                'title': {'type': 'string', 'maxLength': 120},
                'start': {
                  'type': 'string',
                  'description': '带 Z 或 ±HH:mm 时区的 ISO8601 时间',
                },
                'end': {
                  'type': 'string',
                  'description': '带 Z 或 ±HH:mm 时区的 ISO8601 时间',
                },
                'parentId': {
                  'type': 'string',
                  'description': 'add 必填，已存在的作业/考试/个人任务 ID；不能为该事项推测用时',
                },
              },
              'required': ['action'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['summary', 'operations', 'contextVersion'],
        'additionalProperties': false,
      },
    },
  ];
  Map<String, dynamic> draft(
    Map<String, dynamic> args, {
    bool fromTool = false,
  }) {
    if (fromTool && args['contextVersion'] != contextVersion) {
      throw const FormatException(
        '上下文已变化或缺少版本。请先调用 get_schedule_context 重新读取，再按最新数据生成方案',
      );
    }
    if (args.keys.any(
          (k) => !['summary', 'operations', 'contextVersion'].contains(k),
        ) ||
        args['summary'] is! String ||
        (args['summary'] as String).trim().isEmpty ||
        (args['summary'] as String).length > 1000 ||
        args['operations'] is! List) {
      throw const FormatException('方案需要 summary 和 operations');
    }
    final ops = <Map<String, dynamic>>[];
    for (final raw in args['operations'] as List) {
      if (raw is! Map) throw const FormatException('操作格式无效');
      final op = Map<String, dynamic>.from(raw);
      if (op.keys.any(
        (k) =>
            !['action', 'id', 'title', 'start', 'end', 'parentId'].contains(k),
      )) {
        throw const FormatException('包含不允许修改的字段');
      }
      if (op['action'] == 'add') {
        if (op.containsKey('id')) throw const FormatException('新增 ID 由应用生成');
        op['id'] = const Uuid().v4();
      }
      ops.add(op);
    }
    final result = <String, dynamic>{
      'summary': args['summary'],
      'operations': ops,
      'draftId': const Uuid().v4(),
      'baseline': fingerprint(repo.items),
      'preferencesHash': stableId(repo.preferences),
      'createdAt': timestamp(clock()),
    };
    validate(result, repo.items);
    // Store exact before/after values for review, including deletions.
    result['changes'] = ops
        .map(
          (op) => {
            'action': op['action'],
            'before': repo.find(op['id'] as String)?.toJson(),
            'after': op['action'] == 'delete'
                ? null
                : _resultItem(op, repo.items).toJson(),
          },
        )
        .toList();
    return result;
  }

  Item _resultItem(Map<String, dynamic> op, List<Item> current) {
    final old = current.where((e) => e.id == op['id']).firstOrNull;
    final parentId = op['parentId'] ?? old?.parentId;
    final parent = current.where((e) => e.id == parentId).firstOrNull;
    return Item.fromJson({
      if (old != null) ...old.toJson(),
      ...op,
      'categoryId': 'event',
      'origin': 'agent',
      'sourceKey': '',
      'subject': parent?.subject ?? '',
      'parentId': parentId,
      'revision': old == null ? 0 : old.revision + 1,
    });
  }

  List<Item> validate(Map<String, dynamic> draft, List<Item> current) {
    if (draft['baseline'] != fingerprint(current) ||
        draft['preferencesHash'] != stableId(repo.preferences)) {
      throw const FormatException('事项或偏好已变化，请重新生成方案');
    }
    final operations = draft['operations'] as List;
    if (operations.isEmpty || operations.length > 40) {
      throw const FormatException('每次安排1–40项');
    }
    final next = {for (final i in current) i.id: i};
    final changed = <String>{};
    final now = clock();
    for (final raw in operations) {
      final op = Map<String, dynamic>.from(raw as Map);
      final id = op['id'];
      if (id is! String || !changed.add(id)) {
        throw const FormatException('ID 无效或重复修改');
      }
      final action = op['action'];
      final old = next[id];
      if (action != 'add' &&
          (old == null ||
              old.origin != 'agent' ||
              old.categoryId != 'event' ||
              old.completed ||
              old.start == null ||
              !old.start!.isAfter(now))) {
        throw const FormatException('只可调整尚未开始的 Agent 时间块，不能修改课程、考试或手动固定日程');
      }
      if (action == 'delete') {
        if (op.keys.any((k) => !['action', 'id'].contains(k))) {
          throw const FormatException('删除操作只需 action/id');
        }
        next.remove(id);
        continue;
      }
      if (!['add', 'update'].contains(action)) {
        throw const FormatException('未知操作');
      }
      if (action == 'add' && old != null) throw const FormatException('ID 已存在');
      if (action == 'update' &&
          op.containsKey('parentId') &&
          op['parentId'] != old!.parentId) {
        throw const FormatException('不可更换时间块的关联事项');
      }
      final item = _resultItem(op, current);
      item.validate();
      for (final field in ['start', 'end']) {
        final value = op[field] ?? old?.toJson()[field];
        if (value is! String ||
            !RegExp(
              r'^\d{4}-\d\d-\d\dT\d\d:\d\d(:\d\d(\.\d{1,6})?)?(Z|[+-]\d\d:\d\d)$',
            ).hasMatch(value)) {
          throw const FormatException('时间必须包含明确时区');
        }
        final parts = RegExp(
          r'^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d))?',
        ).firstMatch(value)!;
        final y = int.parse(parts[1]!),
            m = int.parse(parts[2]!),
            d = int.parse(parts[3]!),
            h = int.parse(parts[4]!),
            min = int.parse(parts[5]!),
            sec = int.parse(parts[6] ?? '0');
        final date = DateTime.utc(y, m, d, h, min, sec);
        if (date.year != y ||
            date.month != m ||
            date.day != d ||
            date.hour != h ||
            date.minute != min ||
            date.second != sec) {
          throw const FormatException('日期或时间超出有效范围');
        }
      }
      if (!item.timed ||
          item.start!.isBefore(now) ||
          item.end!.isAfter(now.add(const Duration(days: 31)))) {
        throw const FormatException('只能安排未来31天内的时间段');
      }
      if (item.start!.second != 0 ||
          item.end!.second != 0 ||
          item.start!.millisecond != 0 ||
          item.end!.millisecond != 0 ||
          item.start!.microsecond != 0 ||
          item.end!.microsecond != 0) {
        throw const FormatException('请使用整分钟时间');
      }
      final parent = next[item.parentId];
      if (parent == null ||
          parent.completed ||
          !['homework', 'task', 'exam'].contains(parent.categoryId)) {
        throw const FormatException('必须关联未完成的已有作业、个人任务或考试');
      }
      if (parent.estimatedMinutes == null) {
        throw FormatException('请先在事项页填写「${parent.title}」的预计用时');
      }
      final deadline = parent.categoryId == 'exam'
          ? parent.start ?? parent.deadline
          : parent.deadline;
      if (parent.categoryId == 'exam' && deadline == null) {
        throw const FormatException('考试日期未公布，请先补充考试时间再安排复习');
      }
      if (deadline != null && item.end!.isAfter(deadline)) {
        throw const FormatException('安排晚于截止时间或考试开始');
      }
      next[id] = item;
    }
    for (final id in changed) {
      final item = next[id];
      if (item == null) continue;
      for (final other in next.values) {
        // Marking a fixed event complete does not erase its occupied time.
        if (other.id != id && item.overlaps(other)) {
          throw FormatException('「${item.title}」与「${other.title}」时间冲突');
        }
      }
    }
    final parents = changed
        .map((id) => next[id]?.parentId)
        .whereType<String>()
        .toSet();
    for (final id in parents) {
      final seconds = next.values
          .where((e) => e.parentId == id && e.timed)
          .fold<int>(0, (n, e) => n + e.end!.difference(e.start!).inSeconds);
      if (seconds > next[id]!.estimatedMinutes! * 60) {
        throw FormatException('「${next[id]!.title}」总安排超过用户预计用时（含过去/已完成时间块）');
      }
    }
    return next.values.toList();
  }

  Future<void> apply(
    Map<String, dynamic> draft, {
    String? sessionId,
  }) => repo.transaction((state) {
    final applied = List<String>.from(state['appliedDrafts'] as List? ?? []);
    if (applied.contains(draft['draftId'])) {
      throw const FormatException('此方案已经应用');
    }
    Map? message;
    if (sessionId != null) {
      final sessions = state['sessions'] as List;
      final session = sessions.where((s) => s['id'] == sessionId).firstOrNull;
      if (session == null) throw const FormatException('会话已删除');
      message =
          (session['messages'] as List)
                  .where((m) => m['draft']?['draftId'] == draft['draftId'])
                  .firstOrNull
              as Map?;
      if (message == null ||
          message['draftStatus'] != null ||
          jsonEncode(message['draft']) != jsonEncode(draft)) {
        throw const FormatException('方案已失效，请重新生成');
      }
    }
    final current = (state['items'] as List)
        .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    state['items'] = validate(draft, current).map((e) => e.toJson()).toList();
    applied.add(draft['draftId'] as String);
    state['appliedDrafts'] = applied;
    if (message != null) {
      message['applied'] = true;
      message['draftStatus'] = 'applied';
    }
  });
  Future<Map<String, dynamic>> saveMcpDraft(Map<String, dynamic> args) async {
    final plan = draft(args, fromTool: true);
    final id = const Uuid().v4();
    await repo.saveSession({
      'id': id,
      'title': 'MCP 日程方案',
      'messages': [
        {'role': 'assistant', 'content': args['summary'], 'draft': plan},
      ],
    });
    return {
      'status': 'pending_confirmation',
      'draftId': plan['draftId'],
      'sessionId': id,
      'message': '请在 App 的 Agent 会话查看并确认；尚未写入日程。',
    };
  }
}
