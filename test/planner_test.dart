import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/planner/agent_tools.dart';
import 'package:celechron/planner/chat_controller.dart';
import 'package:celechron/services/agent/deepseek_client.dart';

PlannerRepository repository() =>
    PlannerRepository(scope: 'test', writer: (_) async {});
final tomorrow = DateTime.now().add(const Duration(days: 1));
Map<String, dynamic> proposal({
  String? parent,
  DateTime? start,
  int minutes = 30,
}) => {
  'summary': '计划',
  'operations': [
    {
      'action': 'add',
      'title': '学习',
      'start': timestamp(start ?? tomorrow),
      'end': timestamp((start ?? tomorrow).add(Duration(minutes: minutes))),
      if (parent != null) 'parentId': parent,
    },
  ],
};
void main() {
  test('失败事务不发布数据，后续事务仍可完成', () async {
    var fail = true;
    final r = PlannerRepository(
      scope: 'a',
      writer: (_) async {
        if (fail) throw Exception('disk');
      },
    );
    await expectLater(
      r.saveItem(const Item(id: 'a', categoryId: 'task', title: '作业')),
      throwsException,
    );
    expect(r.items, isEmpty);
    fail = false;
    await r.saveItem(const Item(id: 'a', categoryId: 'task', title: '作业'));
    expect(r.items, hasLength(1));
  });
  test('学校同步保留完成状态和用户用时，失败保留数据', () async {
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
      r.items.single.patch({'completed': true, 'estimatedMinutes': 40}),
    );
    await r.mergeSchool('homework', [
      item.patch({'title': 'B'}),
    ], fresh: true);
    expect(r.items.single.title, 'B');
    expect(r.items.single.completed, isTrue);
    expect(r.items.single.estimatedMinutes, 40);
    await r.mergeSchool('homework', [], fresh: false, error: 'offline');
    expect(r.items, hasLength(1));
  });
  test('方案不会直接写入，确认只能应用一次', () async {
    final r = repository();
    final tools = PlannerTools(r);
    final draft = tools.draft(proposal());
    expect(r.items, isEmpty);
    await tools.apply(draft);
    expect(r.items, hasLength(1));
    await expectLater(tools.apply(draft), throwsFormatException);
    expect(r.items, hasLength(1));
  });
  test('缺少用户预计用时拒绝排程，且不得超额', () async {
    final r = repository();
    await r.saveItem(
      Item(
        id: 'hw',
        categoryId: 'homework',
        title: 'A',
        deadline: tomorrow.add(const Duration(hours: 2)),
      ),
    );
    final tools = PlannerTools(r);
    expect(() => tools.draft(proposal(parent: 'hw')), throwsFormatException);
    await r.saveItem(r.items.single.patch({'estimatedMinutes': 20}));
    expect(() => tools.draft(proposal(parent: 'hw')), throwsFormatException);
    expect(
      tools.draft(proposal(parent: 'hw', minutes: 20)),
      contains('draftId'),
    );
  });
  test('拒绝课程冲突、截止后安排和过期方案', () async {
    final r = repository();
    await r.saveItem(
      Item(
        id: 'course',
        categoryId: 'course',
        title: '课',
        origin: 'school',
        start: tomorrow,
        end: tomorrow.add(const Duration(hours: 1)),
      ),
    );
    final tools = PlannerTools(r);
    expect(() => tools.draft(proposal()), throwsFormatException);
    final draft = tools.draft(
      proposal(start: tomorrow.add(const Duration(hours: 2))),
    );
    await r.saveItem(const Item(id: 'other', categoryId: 'task', title: '新任务'));
    await expectLater(tools.apply(draft), throwsFormatException);
    await r.saveItem(
      Item(
        id: 'hw',
        categoryId: 'homework',
        title: 'B',
        estimatedMinutes: 30,
        deadline: tomorrow,
      ),
    );
    expect(
      () => tools.draft(
        proposal(parent: 'hw', start: tomorrow.add(const Duration(hours: 3))),
      ),
      throwsFormatException,
    );
  });
  test('不会删除学校事项，完成任务清理其未来时间块', () async {
    final r = repository();
    await r.saveItem(
      const Item(
        id: 'hw',
        categoryId: 'homework',
        title: 'A',
        origin: 'school',
        estimatedMinutes: 30,
      ),
    );
    final tools = PlannerTools(r);
    await tools.apply(tools.draft(proposal(parent: 'hw')));
    await expectLater(r.removeItem('hw'), throwsFormatException);
    await r.saveItem(r.find('hw')!.patch({'completed': true}));
    expect(r.items, hasLength(1));
  });
  test('并发确认原子去重', () async {
    final r = repository();
    final tools = PlannerTools(r);
    final draft = tools.draft(proposal());
    final results = await Future.wait([
      tools.apply(draft).then((_) => true).catchError((_) => false),
      tools.apply(draft).then((_) => true).catchError((_) => false),
    ]);
    expect(results.where((e) => e), hasLength(1));
    expect(r.items, hasLength(1));
  });
  test('上下文不含历史已结束课程，包含逾期任务和未知分类', () async {
    final r = repository();
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
        categoryId: 'homework',
        title: '逾期',
        deadline: DateTime(2020),
      ),
    );
    await r.saveItem(const Item(id: 'new', categoryId: 'lab', title: '实验'));
    final data = PlannerTools(r).context();
    expect((data['items'] as List).map((e) => e['id']), ['late', 'new']);
    expect(ItemCategory.of('lab').id, 'lab');
  });
  test('Agent使用工具产生草稿并保存会话；不会自行写入', () async {
    final r = repository();
    final client = FakeClient();
    final chat = PlannerChat(r, client: client);
    final id = await chat.create();
    await chat.send(id, '安排学习', 'test-key', 'test-model');
    expect(r.items, isEmpty);
    final session = chat.session(id)!;
    expect(session['messages'], hasLength(2));
    expect(session['messages'][1]['draft'], isNotNull);
    expect(jsonEncode(client.messages).contains('test-key'), isFalse);
    final other = await chat.create();
    expect(chat.session(other)!['messages'], isEmpty);
    expect(chat.session(id)!['messages'], hasLength(2));
    chat.dispose();
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
              'arguments': jsonEncode(proposal()),
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
