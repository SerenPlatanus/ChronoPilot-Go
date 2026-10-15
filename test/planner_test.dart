import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/planner/agent_tools.dart';
import 'package:celechron/planner/chat_controller.dart';
import 'package:celechron/services/agent/deepseek_client.dart';

final now = DateTime.now();
final tomorrow = DateTime(now.year, now.month, now.day + 1, 14);
PlannerRepository repository() =>
    PlannerRepository(scope: 'test', writer: (_) async {});
Future<PlannerRepository> prepared({int? minutes = 60}) async {
  final r = repository();
  await r.saveItem(
    Item(
      id: 'hw',
      categoryId: 'homework',
      title: '线性代数',
      subject: '数学',
      estimatedMinutes: minutes,
      deadline: tomorrow.add(const Duration(hours: 5)),
    ),
  );
  return r;
}

Map<String, dynamic> proposal({
  String parent = 'hw',
  DateTime? start,
  int minutes = 30,
}) => {
  'summary': '学习安排',
  'operations': [
    {
      'action': 'add',
      'parentId': parent,
      'title': '做作业',
      'start': timestamp(start ?? tomorrow),
      'end': timestamp((start ?? tomorrow).add(Duration(minutes: minutes))),
    },
  ],
};
Future<String> storeDraft(
  PlannerRepository r,
  Map<String, dynamic> draft,
) async {
  await r.saveSession({
    'id': 's',
    'title': '规划',
    'messages': [
      {'role': 'assistant', 'content': '待确认', 'draft': draft},
    ],
  });
  return 's';
}

void main() {
  test('写入失败不发布数据，后续事务可恢复', () async {
    var fail = true;
    final r = PlannerRepository(
      scope: 'a',
      writer: (_) async {
        if (fail) throw Exception('disk');
      },
    );
    await expectLater(
      r.saveItem(const Item(id: 'a', categoryId: 'task', title: '任务')),
      throwsException,
    );
    expect(r.items, isEmpty);
    fail = false;
    await r.saveItem(const Item(id: 'a', categoryId: 'task', title: '任务'));
    expect(r.items, hasLength(1));
  });
  test('学校同步保留用户字段，无变化同步不改变版本', () async {
    final r = repository();
    const item = Item(
      id: 'school',
      categoryId: 'homework',
      title: 'A',
      origin: 'school',
      sourceKey: 'homework',
    );
    await r.mergeSchool('homework', [item], fresh: true);
    await r.saveItem(
      r.items.single.patch({'estimatedMinutes': 40, 'notes': '我的备注'}),
    );
    final version = r.items.single.revision;
    await r.mergeSchool('homework', [item], fresh: true);
    expect(r.items.single.revision, version);
    await r.mergeSchool('homework', [
      item.patch({'title': 'B'}),
    ], fresh: true);
    expect(r.items.single.revision, version + 1);
    expect(r.items.single.estimatedMinutes, 40);
    expect(r.items.single.notes, '我的备注');
    await r.mergeSchool('homework', [], fresh: false, error: 'offline');
    expect(r.items, hasLength(1));
    await expectLater(
      r.saveItem(r.items.single.patch({'title': '禁止'})),
      throwsFormatException,
    );
  });
  test('草稿不写入，确认原子更新事项与消息状态，并防重复', () async {
    final r = await prepared();
    final t = PlannerTools(r);
    final plan = t.draft(proposal());
    await storeDraft(r, plan);
    expect(r.items, hasLength(1));
    await t.apply(plan, sessionId: 's');
    expect(r.items, hasLength(2));
    expect(r.sessions.single['messages'][0]['draftStatus'], 'applied');
    await expectLater(t.apply(plan, sessionId: 's'), throwsFormatException);
  });
  test('并发确认仅一次成功', () async {
    final r = await prepared();
    final t = PlannerTools(r);
    final p = t.draft(proposal());
    await storeDraft(r, p);
    final results = await Future.wait(
      List.generate(
        2,
        (_) => t
            .apply(p, sessionId: 's')
            .then((_) => true)
            .catchError((_) => false),
      ),
    );
    expect(results.where((x) => x), hasLength(1));
    expect(r.items, hasLength(2));
  });
  test('不能猜用时、超额排程、伪装成无关联固定日程', () async {
    final r = await prepared(minutes: null);
    final t = PlannerTools(r);
    expect(() => t.draft(proposal()), throwsFormatException);
    await r.saveItem(r.find('hw')!.patch({'estimatedMinutes': 20}));
    expect(() => t.draft(proposal()), throwsFormatException);
    final noParent = proposal();
    (noParent['operations'] as List).first.remove('parentId');
    expect(() => t.draft(noParent), throwsFormatException);
    expect(t.draft(proposal(minutes: 20)), contains('changes'));
  });
  test('拒绝冲突，含标为已完成的固定时段', () async {
    final r = await prepared();
    await r.saveItem(
      Item(
        id: 'c',
        categoryId: 'course',
        title: '课',
        origin: 'school',
        start: tomorrow,
        end: tomorrow.add(const Duration(hours: 1)),
        completed: true,
      ),
    );
    expect(() => PlannerTools(r).draft(proposal()), throwsFormatException);
  });
  test('考试复习必须在考试开始前结束', () async {
    final r = repository();
    await r.saveItem(
      Item(
        id: 'exam',
        categoryId: 'exam',
        title: '考试',
        estimatedMinutes: 60,
        start: tomorrow,
        end: tomorrow.add(const Duration(hours: 1)),
      ),
    );
    final t = PlannerTools(r);
    expect(
      () => t.draft(
        proposal(parent: 'exam', start: tomorrow.add(const Duration(hours: 2))),
      ),
      throwsFormatException,
    );
    expect(
      t.draft(
        proposal(
          parent: 'exam',
          start: tomorrow.subtract(const Duration(hours: 1)),
        ),
      ),
      contains('draftId'),
    );
  });
  test('总时长包含过去已完成时间块，避免每次重新分配整个用时', () async {
    final r = await prepared(minutes: 30);
    await r.saveItem(
      Item(
        id: 'old',
        categoryId: 'event',
        title: '已学习',
        origin: 'agent',
        parentId: 'hw',
        completed: true,
        start: tomorrow.subtract(const Duration(days: 2)),
        end: tomorrow
            .subtract(const Duration(days: 2))
            .add(const Duration(minutes: 20)),
      ),
    );
    expect(
      () => PlannerTools(r).draft(proposal(minutes: 20)),
      throwsFormatException,
    );
  });
  test('数据、偏好变化使草稿失效；同步时间戳不影响草稿', () async {
    final r = await prepared();
    final t = PlannerTools(r);
    final p = t.draft(proposal());
    await r.mergeSchool('courses', [], fresh: true);
    expect(t.validate(p, r.items), hasLength(2));
    await r.setPreferences('23点休息');
    await expectLater(t.apply(p), throwsFormatException);
  });
  test('后续对话、放弃、删除会话均禁止应用旧草稿', () async {
    final r = await prepared();
    final t = PlannerTools(r);
    final p = t.draft(proposal());
    await storeDraft(r, p);
    await r.appendMessages('s', [
      {'role': 'user', 'content': '换一下'},
    ], supersedeDrafts: true);
    await expectLater(t.apply(p, sessionId: 's'), throwsFormatException);
    await r.deleteSession('s');
    await expectLater(t.apply(p, sessionId: 's'), throwsFormatException);
    await storeDraft(r, p);
    await r.dismissDraft('s', p['draftId'] as String);
    await expectLater(t.apply(p, sessionId: 's'), throwsFormatException);
  });
  test('后续调整提供前后对照，不能修改手动日程', () async {
    final r = await prepared();
    final t = PlannerTools(r);
    await t.apply(t.draft(proposal()));
    final block = r.items.firstWhere((i) => i.origin == 'agent');
    final p = t.draft({
      'summary': '改时间',
      'operations': [
        {
          'action': 'update',
          'id': block.id,
          'start': timestamp(tomorrow.add(const Duration(hours: 1))),
          'end': timestamp(tomorrow.add(const Duration(hours: 1, minutes: 30))),
        },
      ],
    });
    expect(p['changes'][0]['before']['start'], timestamp(tomorrow));
    await t.apply(p);
    expect(r.find(block.id)!.start, tomorrow.add(const Duration(hours: 1)));
    await r.saveItem(
      Item(
        id: 'manual',
        categoryId: 'event',
        title: '约会',
        start: tomorrow,
        end: tomorrow.add(const Duration(minutes: 30)),
      ),
    );
    expect(
      () => t.draft({
        'summary': '删除',
        'operations': [
          {'action': 'delete', 'id': 'manual'},
        ],
      }),
      throwsFormatException,
    );
  });
  test('拒绝未知字段，任意版本写入与复活已删除事项', () async {
    final r = await prepared();
    final p = proposal();
    p['operations'][0]['estimatedMinutes'] = '100';
    expect(() => PlannerTools(r).draft(p), throwsFormatException);
    final old = r.items.single;
    await r.removeItem(old.id);
    await expectLater(
      r.saveItem(old.patch({'title': '复活'})),
      throwsFormatException,
    );
  });
  test('完成任务清理其未来时间块', () async {
    final r = await prepared();
    final t = PlannerTools(r);
    await t.apply(t.draft(proposal()));
    await r.saveItem(r.find('hw')!.patch({'completed': true}));
    expect(r.items, hasLength(1));
  });
  test('上下文包含逾期任务，不含过去课程与账号', () async {
    final r = await prepared();
    await r.saveItem(
      Item(
        id: 'old',
        categoryId: 'course',
        title: '历史',
        start: DateTime(2020),
        end: DateTime(2020, 1, 1, 1),
      ),
    );
    await r.saveItem(
      Item(
        id: 'late',
        categoryId: 'task',
        title: '逾期',
        deadline: DateTime(2020),
      ),
    );
    final data = PlannerTools(r).context();
    expect((data['items'] as List).map((e) => e['id']), contains('late'));
    expect((data['items'] as List).map((e) => e['id']), isNot(contains('old')));
    expect(data.containsKey('scope'), isFalse);
  });
  test('Agent 工具草稿持久化，会话隔离，历史包含方案状态', () async {
    final r = await prepared();
    final c = FakeClient();
    var refreshed = 0;
    final chat = PlannerChat(
      r,
      client: c,
      refreshContext: () async {
        refreshed++;
      },
    );
    final id = await chat.create();
    await chat.send(id, '安排作业', 'key', 'model');
    expect(refreshed, 1);
    expect(r.items, hasLength(1));
    expect(chat.session(id)!['messages'][1]['draft'], isNotNull);
    final other = await chat.create();
    expect(chat.session(other)!['messages'], isEmpty);
    await chat.send(id, '说明一下', 'key', 'model');
    expect(jsonEncode(c.messages), contains('方案记录'));
    expect(chat.session(id)!['messages'][1]['draftStatus'], 'superseded');
    chat.dispose();
  });
  test('取消中止等待，不保存迟到响应；重试不重复用户消息', () async {
    final r = await prepared();
    final client = DelayedClient();
    final chat = PlannerChat(r, client: client);
    final id = await chat.create();
    final sending = chat.send(id, '安排', 'key', 'model');
    await client.started.future;
    chat.cancel();
    await sending;
    expect(chat.busy, isFalse);
    expect(chat.session(id)!['messages'], hasLength(1));
    client.response.complete({'role': 'assistant', 'content': '迟到消息'});
    await Future<void>.delayed(Duration.zero);
    expect(chat.session(id)!['messages'], hasLength(1));
    client.immediate = true;
    await chat.retry(id, 'key', 'model');
    expect(chat.session(id)!['messages'], hasLength(2));
    chat.dispose();
  });
  test('请求期间删除会话，不重新创建已删除内容', () async {
    final r = await prepared();
    final client = DelayedClient();
    final chat = PlannerChat(r, client: client);
    final id = await chat.create();
    final sending = chat.send(id, '安排', 'key', 'model');
    await client.started.future;
    await r.deleteSession(id);
    client.response.complete({'role': 'assistant', 'content': '回复'});
    await sending;
    expect(r.sessions, isEmpty);
    chat.dispose();
  });
  test('持久化快照重新打开保留多个会话与应用状态', () async {
    Map<String, dynamic>? saved;
    final r = PlannerRepository(
      scope: 'a',
      writer: (s) async {
        saved = jsonDecode(jsonEncode(s));
      },
    );
    await r.saveSession({'id': 'a', 'title': 'A', 'messages': []});
    await r.saveSession({'id': 'b', 'title': 'B', 'messages': []});
    await r.renameSession('a', '新名称');
    final reopened = PlannerRepository(
      scope: 'a',
      writer: (_) async {},
      initial: saved,
    );
    expect(reopened.sessions, hasLength(2));
    expect(reopened.sessions.last['title'], '新名称');
  });
}

class FakeClient implements AgentCompletionClient {
  int count = 0;
  List<Map<String, dynamic>> messages = [];
  @override
  Future<Map<String, dynamic>> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    this.messages = messages;
    if (count++ == 0) {
      return {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'call1',
            'type': 'function',
            'function': {
              'name': 'propose_schedule',
              'arguments': jsonEncode({
                ...proposal(),
                'contextVersion': jsonDecode(
                  (messages[0]['content'] as String).split('当前数据 JSON：\n').last,
                )['contextVersion'],
              }),
            },
          },
        ],
      };
    }
    return {'role': 'assistant', 'content': '方案待确认'};
  }

  @override
  void cancel() {}
}

class DelayedClient implements AgentCompletionClient {
  final started = Completer<void>();
  final response = Completer<Map<String, dynamic>>();
  bool immediate = false;
  @override
  Future<Map<String, dynamic>> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) {
    if (!started.isCompleted) started.complete();
    return immediate
        ? Future.value({'role': 'assistant', 'content': '重试回复'})
        : response.future;
  }

  @override
  void cancel() {}
}
