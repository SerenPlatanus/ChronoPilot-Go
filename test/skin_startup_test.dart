import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celechron/main.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/planner/school_sync.dart';
import 'package:celechron/ui/styles.dart';
import 'package:celechron/ui/skin_editor.dart';
import 'package:celechron/ui/course_color.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String css;
  late Map<PilotStyle, StyleTokens> palettes;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('chronopilot-skin-');
    Hive.init(directory.path);
    palettes = await StyleController.loadPalettes();
    css = await rootBundle.loadString(PilotStyle.custom.asset);
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('自定义皮肤保存后可重建恢复，两种明暗的类轮廓一致', () async {
    final controller = await StyleController.load();
    final edited =
        '$css\n.cp-agent-send { --radius: 0; --border-width: 3; --border-color: ink; }';
    await controller.applyCustom(edited);
    await controller.selectBrightness(Brightness.dark);
    final loaded = await StyleController.load();
    expect(loaded.selected, PilotStyle.custom);
    expect(loaded.brightness, Brightness.dark);
    expect(loaded.customCss, edited);
    expect(
      loaded
          .palettes[PilotStyle.custom]!
          .controls['agent-send']!['border-width'],
      '3',
    );
    expect(identical(loaded.theme, loaded.theme), isTrue);
  });

  test('非法浅深色与超长 CSS 不会覆盖已生效皮肤', () async {
    final controller = await StyleController.load();
    final previous = controller.theme;
    final oldCss = controller.customCss;
    await expectLater(
      controller.applyCustom(
        css.replaceFirst('--dark-paper: #000000;', '--dark-paper: oops;'),
      ),
      throwsFormatException,
    );
    await expectLater(
      controller.applyCustom('$css\n.cp-agent-send { --radius: -1; }'),
      throwsFormatException,
    );
    await expectLater(
      controller.applyCustom('x' * 65537),
      throwsFormatException,
    );
    expect(controller.customCss, oldCss);
    expect(identical(controller.theme, previous), isTrue);
  });

  test('保存失败不发布新皮肤', () async {
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      customWriter: (_) async =>
          throw const FileSystemException('disk unavailable'),
    );
    await expectLater(
      controller.applyCustom(css),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.selected, PilotStyle.defaultStyle);
    expect(controller.saving, isFalse);
  });

  test('启动快照从上次账号恢复，不读取网络或密钥', () async {
    final repository = await PlannerRepository.open('cached-student');
    await repository.saveItem(
      const Item(id: 'offline-task', categoryId: 'task', title: '断网时可见的任务'),
    );
    await PlannerRepository.rememberAccount(repository.scope);
    final restored = await PlannerRepository.openLastAccount();
    expect(restored.scope, 'cached-student');
    expect(restored.find('offline-task')!.title, '断网时可见的任务');
    final sync = SchoolSync(restored, '', '');
    expect(sync.shouldRefresh, isFalse);
    expect(SchoolSync.refreshInterval, const Duration(minutes: 2));
    await sync.refresh(force: true);
    expect(restored.find('offline-task'), isNotNull);
    sync.dispose();
    restored.dispose();
    repository.dispose();
  });

  testWidgets('首帧即显示缓存任务，主题和导航不播放过场', (tester) async {
    final repo = PlannerRepository(scope: 'local', writer: (_) async {});
    await repo.saveItem(
      const Item(id: 'cached', categoryId: 'task', title: '缓存首帧任务'),
    );
    final styles = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
    );
    await tester.pumpWidget(ChronoPilotRoot(styles: styles, repository: repo));
    expect(find.text('缓存首帧任务'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final context = tester.element(find.text('缓存首帧任务'));
    expect(MediaQuery.disableAnimationsOf(context), isTrue);
    final theme = Theme.of(context);
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<ImmediatePageTransitions>(),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('CSS 编辑器拒绝错误文本，修正后保存并返回', (tester) async {
    String? saved;
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      customCss: css,
      customWriter: (value) async {
        saved = value;
      },
    );
    await tester.pumpWidget(
      StyleScope(
        controller: controller,
        child: MaterialApp(
          theme: controller.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  PilotPageRoute(builder: (_) => const SkinEditor()),
                ),
                child: const Text('编辑皮肤'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑皮肤'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('skin-css-editor')),
      ':root {}',
    );
    await tester.tap(find.text('保存并应用'));
    await tester.pumpAndSettle();
    expect(find.text('主题标识不匹配'), findsOneWidget);
    expect(controller.selected, PilotStyle.defaultStyle);
    await tester.enterText(find.byKey(const ValueKey('skin-css-editor')), css);
    await tester.tap(find.text('保存并应用'));
    await tester.pumpAndSettle();
    expect(controller.selected, PilotStyle.custom);
    expect(saved, css);
    expect(find.text('编辑皮肤'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('九色色标保持高饱和度，跨类别同学科一致', () {
    final colors = <Color>{};
    for (var n = 0; n < 100; n++) {
      final item = Item(
        id: '$n',
        categoryId: 'course',
        title: '课程$n',
        subject: '学科$n',
      );
      final color = courseColor(item);
      expect(HSVColor.fromColor(color).saturation, greaterThan(.7));
      colors.add(color);
      expect(
        courseColor(
          Item(
            id: 'hw$n',
            categoryId: 'homework',
            title: '作业',
            subject: item.subject,
          ),
        ),
        color,
      );
    }
    expect(colors.length, 9);
  });
}
