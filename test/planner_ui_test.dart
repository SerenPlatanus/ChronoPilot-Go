import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/app.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';

void main() {
  testWidgets('四个页面、添加事项和 Agent 入口能够正常显示', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = PlannerRepository(scope: 'test', writer: (_) async {});
    await repo.saveItem(
      Item(
        id: 'c',
        categoryId: 'course',
        title: '高等数学',
        subject: '数学',
        start: DateTime.now().add(const Duration(hours: 1)),
        end: DateTime.now().add(const Duration(hours: 2)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        locale: const Locale('zh', 'CN'),
        home: PlannerApp(repository: repo),
      ),
    );
    await tester.pump();
    expect(find.text('高等数学'), findsWidgets);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('课表与日程'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '线性代数练习');
    tester.binding.focusManager.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存').hitTestable(),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('item-editor-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.items.any((e) => e.title == '线性代数练习'), isTrue);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Agent 接入开发已暂停'), findsNothing);
    final send = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send),
    );
    expect(send.onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pumpAndSettle();
    expect(repo.sessions, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
