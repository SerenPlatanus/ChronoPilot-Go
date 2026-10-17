import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:celechron/planner/chat_page.dart';
import 'package:celechron/planner/chat_controller.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/ui/agent_markdown.dart';
import 'package:celechron/ui/styles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<PilotStyle, StyleTokens> palettes;
  setUpAll(() async {
    palettes = await StyleController.loadPalettes();
  });
  for (final dark in [false, true]) {
    testWidgets('LaTeX 四种界定符、代码保留、无效和超长公式 ${dark ? '深色' : '浅色'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const data = r'''行内 $E=mc^2$ 与 \(\frac{a}{b}\)。

$$
\int_0^1 x^2\,dx=\frac{1}{3}
$$

\[
\sum_{i=1}^{n}i=\frac{n(n+1)}{2}
\]

`$code$` 以及转义 \$20。

```text
$not_math$
```

未闭合 $leave_alone

$\thiscommanddoesnotexist{a}$
''';
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(
            palettes[PilotStyle.defaultStyle]!,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: AgentMarkdown(data: data),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(palettes[PilotStyle.defaultStyle]!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentMarkdown(
                data: '\$\$${List.filled(100, 'x+').join()}1\$\$',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('左侧滑出历史列表，滚动并切换会话，新会话可创建', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = PlannerRepository(scope: 'drawer-test', writer: (_) async {}),
        now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      await repo.saveSession({
        'id': 's$i',
        'title': '对话 $i',
        'updatedAt': now.subtract(Duration(days: i)).toIso8601String(),
        'messages': [
          {'role': 'assistant', 'content': '消息 $i'},
        ],
      });
    }
    final chat = PlannerChat(repo);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(palettes[PilotStyle.defaultStyle]!),
        home: PlannerChatPage(
          chat: chat,
          apiKey: '',
          model: 'test',
          beforeSend: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsNothing);
    await tester.dragFrom(const Offset(1, 300), const Offset(290, 0));
    await tester.pumpAndSettle();
    expect(find.text('历史对话'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-s0')));
    await tester.pumpAndSettle();
    expect(find.text('消息 0'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '尚未发送的草稿');
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('session-s20')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('session-history-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('session-s20')));
    await tester.pumpAndSettle();
    expect(find.text('消息 20'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('session-s0')),
      -300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('session-history-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('session-s0')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '尚未发送的草稿',
    );

    await tester.tap(find.byTooltip('新会话'));
    await tester.pumpAndSettle();
    expect(repo.sessions, hasLength(31));
    expect(find.text('今天想安排什么？'), findsOneWidget);
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('会话操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '改名后的会话',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.sessions.any((s) => s['title'] == '改名后的会话'), true);
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('会话操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(repo.sessions, hasLength(30));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    chat.dispose();
  });
}
