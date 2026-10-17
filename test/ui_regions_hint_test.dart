import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/main.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/ui/styles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<PilotStyle, StyleTokens> palettes;
  setUpAll(() async {
    palettes = await StyleController.loadPalettes();
  });

  Future<PlannerRepository> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final repo = PlannerRepository(scope: 'hint-test', writer: (_) async {});
    await repo.saveItem(
      Item(
        id: 'hw',
        categoryId: 'homework',
        title: '待办作业',
        subject: '操作系统',
        deadline: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    await repo.mergeSchool('courses', [], fresh: false, error: 'offline');
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
    );
    await tester.pumpWidget(
      ChronoPilotRoot(styles: controller, repository: repo),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  for (final method in ['close', 'left', 'right', 'refresh']) {
    testWidgets('$method 关闭刷新提示后，切页和同步失败均不重现', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = await mount(tester);
      final hint = find.byKey(const ValueKey('startup-sync-hint'));
      expect(hint, findsOneWidget);
      if (method == 'close') {
        await tester.tap(find.byTooltip('关闭刷新提示'));
      } else if (method == 'refresh') {
        await tester.tap(find.byTooltip('更新学校数据'));
      } else {
        await tester.drag(hint, Offset(method == 'left' ? -380 : 380, 0));
      }
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      final panel = tester.widget<Container>(
        find.byKey(const ValueKey('calendar-panel')),
      );
      final nav = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(
        (panel.decoration! as BoxDecoration).color,
        palettes[PilotStyle.defaultStyle]!.color('calendar-surface'),
      );
      expect(
        nav.backgroundColor,
        palettes[PilotStyle.defaultStyle]!.color('navigation-surface'),
      );
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await repo.mergeSchool(
        'courses',
        [],
        fresh: false,
        error: 'still offline',
      );
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('同步成功自动收起；重新启动后可重新提醒', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = await mount(tester);
    final hint = find.byKey(const ValueKey('startup-sync-hint'));
    expect(hint, findsOneWidget);
    await repo.mergeSchool('courses', [], fresh: true);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await repo.mergeSchool('courses', [], fresh: false, error: 'later error');
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    expect(hint, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('离开首页即结束本次提醒，返回首页不重复显示', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    final hint = find.byKey(const ValueKey('startup-sync-hint'));
    expect(hint, findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await tester.tap(find.byIcon(Icons.schedule));
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('旧自定义 CSS 未定义分区颜色时仍能解析，提供区分底色', () async {
    final css = (await rootBundle.loadString(PilotStyle.custom.asset))
        .replaceAll(
          RegExp(
            r'--(?:dark-)?(?:calendar|navigation)-surface:\s*#[0-9A-Fa-f]{6};',
          ),
          '',
        );
    final tokens = StyleTokens.fromCss(PilotStyle.custom, css);
    for (final brightness in Brightness.values) {
      final v = themeFor(
        tokens,
        brightness: brightness,
      ).extension<PilotVisuals>()!;
      expect(v.namedColor('calendar-surface'), isNot(v.paper));
      expect(v.namedColor('navigation-surface'), isNot(v.paper));
    }
  });
}
