import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/agent_tools.dart';
import 'package:celechron/planner/draft_card.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';

void main() {
  Future<PlannerRepository> seed() async {
    final r = PlannerRepository(scope: 'test', writer: (_) async {});
    await r.saveItem(
      const Item(
        id: 'task',
        categoryId: 'task',
        title: '读书',
        estimatedMinutes: 60,
      ),
    );
    return r;
  }

  Map<String, dynamic> args(PlannerTools tools) {
    final d = DateTime.now();
    final start = DateTime(d.year, d.month, d.day + 1, 10);
    return {
      'summary': '明天读书',
      'contextVersion': tools.contextVersion,
      'operations': [
        {
          'action': 'add',
          'parentId': 'task',
          'title': '读书',
          'start': timestamp(start),
          'end': timestamp(start.add(const Duration(minutes: 30))),
        },
      ],
    };
  }

  test('模型和 MCP 必须提交已读取的数据版本', () async {
    final r = await seed(), tools = PlannerTools(await seed());
    final t = PlannerTools(r), a = args(PlannerTools(r));
    await r.setPreferences('早上不学习');
    expect(() => t.draft(a, fromTool: true), throwsFormatException);
    final noVersion = args(t)..remove('contextVersion');
    expect(() => t.draft(noVersion, fromTool: true), throwsFormatException);
    expect(tools.draft(args(tools), fromTool: true), contains('draftId'));
  });
  test('单次持久化失败不能出现日程成功但会话未成功', () async {
    Map<String, dynamic>? disk;
    bool fail = false;
    final r = PlannerRepository(
      scope: 'x',
      writer: (value) async {
        if (fail) throw Exception('disk');
        disk = jsonDecode(jsonEncode(value));
      },
    );
    await r.saveItem(
      const Item(
        id: 'task',
        categoryId: 'task',
        title: '读书',
        estimatedMinutes: 60,
      ),
    );
    final t = PlannerTools(r), p = PlannerTools(r).draft(args(PlannerTools(r)));
    await r.saveSession({
      'id': 's',
      'title': '测试',
      'messages': [
        {'role': 'assistant', 'content': '待确认', 'draft': p},
      ],
    });
    fail = true;
    await expectLater(t.apply(p, sessionId: 's'), throwsException);
    expect(r.items, hasLength(1));
    expect(disk!['items'], hasLength(1));
    expect(r.sessions.single['messages'][0]['applied'], isNull);
    fail = false;
    await t.apply(p, sessionId: 's');
    expect(disk!['items'], hasLength(2));
    expect(disk!['sessions'][0]['messages'][0]['draftStatus'], 'applied');
  });
  testWidgets('方案卡显示前后对照，确认后显示已写入', (tester) async {
    final r = await seed();
    final t = PlannerTools(r);
    final p = t.draft(args(t));
    await r.saveSession({
      'id': 's',
      'title': '测试',
      'messages': [
        {'role': 'assistant', 'content': '待确认', 'draft': p},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: r,
            builder: (_, __) => DraftCard(
              tools: t,
              draft: p,
              sessionId: 's',
              status:
                  r.sessions.single['messages'][0]['draftStatus'] as String?,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('新增时间块'), findsOneWidget);
    await tester.tap(find.text('确认并写入日程'));
    await tester.pumpAndSettle();
    expect(find.text('已写入日程'), findsOneWidget);
    expect(r.items, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    r.dispose();
  });
}
