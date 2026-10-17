import 'dart:convert';
import 'package:celechron/planner/semester_filter.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/main.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/app.dart';
import 'package:celechron/planner/agent_tools.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/planner/settings_page.dart';
import 'package:celechron/ui/styles.dart';
import 'package:celechron/ui/backdrop_settings.dart';
import 'package:celechron/ui/controls.dart';

const previews = bool.fromEnvironment('UI_PREVIEWS');
Future<PlannerRepository> seed() async {
  final r = PlannerRepository(scope: 'visual-test', writer: (_) async {});
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  await r.saveItem(
    Item(
      id: 'course',
      categoryId: 'course',
      title: '高等数学 · 微分与积分',
      subject: '高等数学',
      location: '紫金港 · 东一 206',
      origin: 'school',
      start: day.add(const Duration(hours: 23)),
      end: day.add(const Duration(hours: 23, minutes: 50)),
    ),
  );
  await r.saveItem(
    Item(
      id: 'hw',
      categoryId: 'homework',
      title: '线性代数第三次作业',
      subject: '线性代数',
      estimatedMinutes: 60,
      deadline: day.add(const Duration(days: 2, hours: 23, minutes: 59)),
    ),
  );
  await r.saveItem(
    Item(
      id: 'exam',
      categoryId: 'exam',
      title: '大学物理期中考试',
      subject: '大学物理',
      estimatedMinutes: 120,
      start: day.add(const Duration(days: 4, hours: 9)),
      end: day.add(const Duration(days: 4, hours: 11)),
    ),
  );
  await r.saveItem(
    Item(
      id: 'event',
      categoryId: 'event',
      title: '与同学讨论课程项目',
      location: '图书馆 · 小组研讨室',
      start: day.add(const Duration(days: 1, hours: 16)),
      end: day.add(const Duration(days: 1, hours: 17)),
    ),
  );
  await r.saveItem(
    const Item(
      id: 'task',
      categoryId: 'task',
      title: '读完软件工程课的需求分析材料，并整理重点与疑问',
      estimatedMinutes: 45,
    ),
  );
  await r.saveItem(
    Item(
      id: 'preview-homework',
      categoryId: 'homework',
      title: '2.31, 2.36',
      subject: '计算机系统原理',
      deadline: now.add(const Duration(hours: 2)),
    ),
  );
  final monday = day.subtract(Duration(days: day.weekday - 1));
  const names = ['软件需求工程', '计算机网络', '大学物理实验', '概率论与数理统计', '操作系统', '篮球（初级）'];
  for (var weekday = 0; weekday < 5; weekday++) {
    for (var block = 0; block < 3; block++) {
      final name = names[(weekday + block) % names.length];
      final start = monday.add(
        Duration(days: weekday, hours: [8, 10, 14][block]),
      );
      await r.saveItem(
        Item(
          id: 'sample-$weekday-$block',
          categoryId: 'course',
          title: name,
          subject: name,
          origin: 'school',
          sourceKey: 'courses:${academicTerm(day)}',
          location: '玉泉教4-${201 + weekday}',
          start: start,
          end: start.add(const Duration(minutes: 95)),
        ),
      );
    }
  }
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<PilotStyle, StyleTokens> palettes;
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    palettes = await StyleController.loadPalettes();
    if (previews) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final fonts =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final family in fonts.where(
        (f) => (f['family'] as String).contains('flutter_math_fork'),
      )) {
        final loader = FontLoader(family['family'] as String);
        for (final font in family['fonts'] as List) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }

      final font = File(
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      );
      if (await font.exists()) {
        for (final family in ['Roboto', 'monospace']) {
          final loader = FontLoader(family)
            ..addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
        }
      }
    }
  });
  test('全部 CSS 都可读取；默认使用原版蓝色强调', () {
    expect(palettes.length, PilotStyle.values.length);
    expect(
      palettes[PilotStyle.testAlpha]!.color('paper'),
      const Color(0xffe9e3d4),
    );
    expect(
      themeFor(palettes[PilotStyle.defaultStyle]!).colorScheme.primary,
      const Color(0xff087ef5),
    );
    expect(
      () => StyleTokens.fromCss(
        PilotStyle.defaultStyle,
        ':root { --style-id: default; }',
      ),
      throwsFormatException,
    );
    expect(PilotStyle.parse('unknown'), PilotStyle.defaultStyle);
    expect(PilotStyle.parse('cassette_future'), PilotStyle.testAlpha);
    expect(PilotStyle.parse('swiss'), PilotStyle.testBeta);
    expect(PilotStyle.parse('constructivist'), PilotStyle.defaultStyle);
    expect(PilotStyle.values.map((v) => v.label).toList(), [
      '默认主题',
      '测试主题alpha',
      '测试主题beta',
      '自定义主题',
    ]);
  });
  test('控件规则拒绝越界尺寸和未知颜色，忽略注释', () async {
    final css = await rootBundle.loadString(PilotStyle.testAlpha.asset);
    expect(
      () => StyleTokens.fromCss(
        PilotStyle.testAlpha,
        '$css\n.cp-agent-send { --border-width: 9; }',
      ),
      throwsFormatException,
    );
    expect(
      () => StyleTokens.fromCss(
        PilotStyle.testAlpha,
        '$css\n.cp-agent-send { --fill: unknown; }',
      ),
      throwsFormatException,
    );
    expect(
      StyleTokens.fromCss(
        PilotStyle.testAlpha,
        '$css\n/* .cp-bogus { --radius: 999; } */',
      ).controls.containsKey('bogus'),
      isFalse,
    );
  });
  for (final style in [PilotStyle.testBeta]) {
    for (final brightness in Brightness.values) {
      testWidgets('${style.id} ${brightness.name} 独立按钮类、边框与操作状态生效', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: themeFor(palettes[style]!, brightness: brightness),
            home: Scaffold(
              body: Row(
                children: [
                  PilotControl(
                    className: 'agent-send',
                    kind: 'icon-button',
                    child: IconButton.filled(
                      tooltip: '发送',
                      onPressed: () => taps++,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                  const PilotControl(
                    className: 'item-save',
                    kind: 'primary-button',
                    child: FilledButton(onPressed: null, child: Text('保存')),
                  ),
                ],
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(IconButton));
        final theme = Theme.of(context),
            button = IconButtonTheme.of(context).style!;
        final side = button.side!.resolve({})!;
        expect(side.width, 1);
        // The action class overrides icon-button's ink outline with accent.
        expect(side.color, theme.colorScheme.primary);
        expect(
          (button.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(2),
        );
        expect(
          button.foregroundColor!.resolve({}),
          theme.colorScheme.onPrimary,
        );
        expect(button.overlayColor!.resolve({WidgetState.pressed}), isNotNull);
        expect(
          button.foregroundColor!.resolve({WidgetState.disabled})!.a,
          lessThan(1),
        );
        expect(
          tester.getSize(find.byType(IconButton)).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.byTooltip('发送'));
        expect(taps, 1);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      });
    }
  }
  test('主题立即持久化，失败不发布，重建恢复选择', () async {
    String? saved;
    final controller = StyleController(
      palettes: palettes,
      writer: (id) async {
        saved = id;
      },
    );
    await controller.select(PilotStyle.testAlpha);
    expect(saved, 'test_alpha');
    expect(controller.selected, PilotStyle.testAlpha);
    final reopened = StyleController(
      palettes: palettes,
      writer: (_) async {},
      selected: PilotStyle.parse(saved),
    );
    expect(reopened.selected, PilotStyle.testAlpha);
    final broken = StyleController(
      palettes: palettes,
      writer: (_) async {
        throw Exception('storage');
      },
    );
    await expectLater(broken.select(PilotStyle.testAlpha), throwsException);
    expect(broken.selected, PilotStyle.defaultStyle);
    expect(broken.saving, isFalse);
  });
  test('真实本地偏好可恢复风格与明暗，二者独立保存', () async {
    final temp = await Directory.systemTemp.createTemp('chronopilot-theme-');
    Hive.init(temp.path);
    try {
      final first = await StyleController.load();
      await first.select(PilotStyle.testAlpha);
      await first.selectBrightness(Brightness.dark);
      first.dispose();
      await Hive.box<String>('ui_preferences_v1').close();
      final reopened = await StyleController.load();
      expect(reopened.selected, PilotStyle.testAlpha);
      expect(reopened.brightness, Brightness.dark);
      await reopened.select(PilotStyle.testBeta);
      expect(reopened.brightness, Brightness.dark);
      reopened.dispose();
      await Hive.box<String>('ui_preferences_v1').close();
      final third = await StyleController.load();
      expect(third.selected, PilotStyle.testBeta);
      expect(third.brightness, Brightness.dark);
      third.dispose();
      await Hive.box<String>('ui_preferences_v1').close();
    } finally {
      await temp.delete(recursive: true);
    }
  });
  testWidgets('设置切换主题保持当前路由、表单和全部功能入口', (tester) async {
    final r = await seed();
    String? saved;
    final controller = StyleController(
      palettes: palettes,
      writer: (id) async {
        saved = id;
      },
    );
    await tester.pumpWidget(ChronoPilotRoot(styles: controller, repository: r));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(PlannerSettings));
    await tester.tap(find.byKey(const ValueKey('style-test_alpha')));
    await tester.pumpAndSettle();
    expect(saved, 'test_alpha');
    for (final style in [PilotStyle.testBeta]) {
      await tester.ensureVisible(find.byKey(ValueKey('style-${style.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('style-${style.id}')));
      await tester.pumpAndSettle();
      expect(saved, style.id);
      expect(tester.state(find.byType(PlannerSettings)), same(state));
    }
    await tester.ensureVisible(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(controller.brightness, Brightness.dark);

    expect(tester.state(find.byType(PlannerSettings)), same(state));
    final context = tester.element(find.byType(PlannerSettings));
    expect(controller.selected, PilotStyle.testBeta);
    expect(
      PilotVisuals.of(context).accent,
      palettes[PilotStyle.testBeta]!.color('dark-accent'),
    );
    await tester.scrollUntilVisible(
      find.text('MCP 服务器'),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('planner-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('MCP 服务器'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  for (final style in [PilotStyle.testBeta]) {
    for (final brightness in Brightness.values) {
      test('${style.id} ${brightness.name} 关键文字与控件对比度', () {
        final theme = themeFor(palettes[style]!, brightness: brightness),
            v = theme.extension<PilotVisuals>()!;
        final pairs = [
          ('ink/paper', v.ink, v.paper),
          ('ink/surface', v.ink, v.surface),
          ('ink/stage', v.ink, v.stage),
          ('muted/paper', v.muted, v.paper),
          ('muted/surface', v.muted, v.surface),
          ('accent/paper', v.accent, v.paper),
          ('accent/surface', v.accent, v.surface),
          (
            'onPrimary/primary',
            theme.colorScheme.onPrimary,
            theme.colorScheme.primary,
          ),
          ('danger/paper', theme.colorScheme.error, v.paper),
          ('danger/surface', theme.colorScheme.error, v.surface),
          ('signal/screen', v.signal, v.screen),
          ('warning/screen', v.signalYellow, v.screen),
          ('error/screen', v.signalRed, v.screen),
        ];
        for (final pair in pairs) {
          final a = pair.$2.computeLuminance(), b = pair.$3.computeLuminance();
          final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: pair.$1);
        }
      });
    }
  }
  for (final brightness in Brightness.values) {
    for (final style in PilotStyle.values) {
      for (final spec in [
        (const Size(320, 640), 1.0),
        (const Size(390, 844), 1.0),
        (const Size(844, 390), 1.0),
        (const Size(390, 844), 2.0),
      ]) {
        testWidgets(
          '${style.id} ${brightness.name} 页面适配 ${spec.$1} 字体 ${spec.$2}',
          (tester) async {
            tester.view.physicalSize = spec.$1;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final r = await seed();
            final controller = StyleController(
              palettes: palettes,
              writer: (_) async {},
              selected: style,
              brightness: brightness,
            );
            final app = StyleScope(
              controller: controller,
              child: MaterialApp(
                theme: controller.theme,
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(spec.$2)),
                  child: child!,
                ),
                home: PlannerApp(repository: r),
              ),
            );
            await tester.pumpWidget(app);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final icon in [
              Icons.calendar_month_outlined,
              Icons.checklist,
              Icons.auto_awesome_outlined,
            ]) {
              await tester.tap(find.byIcon(icon));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            await tester.tap(find.byIcon(Icons.settings_outlined));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
          },
        );
      }
    }
  }
  if (previews) {
    testWidgets('生成真实 Flutter 主题预览', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = await seed();
      final controller = StyleController(
        palettes: palettes,
        writer: (_) async {},
        selected: PilotStyle.testAlpha,
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ChronoPilotRoot(styles: controller, repository: r),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final path = File('docs/ui-previews/$name.png');
          await path.parent.create(recursive: true);
          await path.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot('test-alpha-today');
      await r.mergeSchool('preview-sync', [], fresh: false, error: '测试缓存状态');
      await tester.pumpAndSettle();
      await shot('test-alpha-startup-hint');
      await tester.tap(find.byTooltip('关闭刷新提示'));
      await tester.pumpAndSettle();
      await shot('test-alpha-compact-upcoming');
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      await shot('test-alpha-timetable');
      await tester.tap(find.byTooltip('大课表'));
      await tester.pumpAndSettle();
      await shot('test-alpha-large-timetable');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      await shot('test-alpha-tasks');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await shot('test-alpha-editor');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pumpAndSettle();
      await shot('test-alpha-agent');
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10);
      final plan = PlannerTools(r).draft({
        'summary': '明天上午留出30分钟完成线性代数作业。',
        'operations': [
          {
            'action': 'add',
            'parentId': 'hw',
            'title': '线性代数作业',
            'start': timestamp(start),
            'end': timestamp(start.add(const Duration(minutes: 30))),
          },
        ],
      });
      await r.saveSession({
        'id': 'sample-plan',
        'title': '明天的学习安排',
        'messages': [
          {'role': 'user', 'content': '帮我把线性代数的作业安排在明天上午。'},
          {
            'role': 'assistant',
            'content':
                '已避开课程和固定日程。\n\n**建议安排**\n\n- 先完成线性代数作业\n- 预留休息时间\n\n| 事项 | 用时 |\n| --- | --- |\n| 线性代数 | 30分钟 |',
            'draft': plan,
          },
        ],
      });
      await tester.pumpAndSettle();
      await shot('test-alpha-agent-plan');
      for (var i = 0; i < 8; i++) {
        await r.saveSession({
          'id': 'history-$i',
          'title': ['本周作业安排', '操作系统复习', '周末学习计划', '调整晚间日程'][i % 4],
          'updatedAt': DateTime.now()
              .subtract(Duration(days: i))
              .toIso8601String(),
          'messages': [],
        });
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('历史对话'));
      await tester.pumpAndSettle();
      await shot('test-alpha-agent-history');
      await tester.tap(find.byTooltip('关闭对话列表'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await shot('test-alpha-settings');
      await controller.selectBrightness(Brightness.dark);
      await tester.pumpAndSettle();
      await shot('test-alpha-dark-settings');
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await shot('test-alpha-dark-today');
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      await shot('test-alpha-dark-timetable');
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      await shot('test-alpha-dark-tasks');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await shot('test-alpha-dark-editor');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pumpAndSettle();
      await shot('test-alpha-dark-agent');
      await controller.select(PilotStyle.defaultStyle);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await shot('default-dark-today');
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      await shot('default-dark-calendar');
      await controller.selectBrightness(Brightness.light);
      await tester.pumpAndSettle();
      await shot('default-today');
      await r.saveSession({
        'id': 'math-demo',
        'title': '数学公式示例',
        'messages': [
          {'role': 'user', 'content': '给我展示一下公式排版。'},
          {
            'role': 'assistant',
            'content': r"""行内公式：$E=mc^2$，以及 \(a^2+b^2=c^2\)。

二次方程的求根公式：

\[
x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}
\]

定积分：

$$
\int_0^1 x^2\,dx=\frac{1}{3}
$$

| 形式 | 显示 |
| --- | --- |
| 求和 | $\sum_{i=1}^n i$ |
""",
          },
        ],
      });
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pumpAndSettle();
      await shot('default-agent-math');
      await tester.tap(find.byTooltip('历史对话'));
      await tester.pumpAndSettle();
      await shot('default-agent-history');

      await tester.tap(find.byTooltip('关闭对话列表'));
      await tester.pumpAndSettle();
      for (final style in [
        PilotStyle.defaultStyle,
        PilotStyle.testAlpha,
        PilotStyle.testBeta,
      ]) {
        await controller.select(style);
        for (final brightness in Brightness.values) {
          await controller.selectBrightness(brightness);
          await tester.pumpAndSettle();
          await shot('${style.id}-${brightness.name}-agent');
          await tester.tap(find.byIcon(Icons.calendar_month_outlined));
          await tester.pumpAndSettle();
          await shot('${style.id}-${brightness.name}-calendar');
          await tester.tap(find.byIcon(Icons.settings_outlined));
          await tester.pumpAndSettle();
          await shot('${style.id}-${brightness.name}-settings');
          await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
          await tester.pumpAndSettle();
        }
      }
      // A code-drawn, neutral sample wallpaper exercises the real image layer.
      late File demo;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 430, 932),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              const Offset(430, 932),
              [
                const Color(0xff90aeb5),
                const Color(0xffcfbc9e),
                const Color(0xff8da6b8),
              ],
              const [0, .5, 1],
            ),
        );
        canvas.drawCircle(
          const Offset(390, 170),
          250,
          Paint()..color = const Color(0x30ffffff),
        );
        canvas.drawCircle(
          const Offset(20, 800),
          330,
          Paint()..color = const Color(0x20405965),
        );
        final picture = recorder.endRecording();
        final bitmap = await picture.toImage(430, 932);
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        demo = File('docs/ui-previews/wallpaper-demo.png').absolute;
        await demo.writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
        picture.dispose();
        await precacheImage(
          ResizeImage(FileImage(demo), width: 430),
          boundary.currentContext!,
        );
      });
      await controller.select(PilotStyle.testAlpha);
      await controller.selectBrightness(Brightness.light);
      await controller.setBackdrop(
        BackdropSettings(
          kind: BackdropKind.wallpaper,
          filePath: demo.path,
          panelOpacity: .8,
          veilOpacity: .35,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await shot('wallpaper-upcoming');
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      await shot('wallpaper-calendar');
      await controller.selectBrightness(Brightness.dark);
      await tester.pumpAndSettle();
      await shot('wallpaper-calendar-dark');
      await controller.setBackdrop(const BackdropSettings());
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
