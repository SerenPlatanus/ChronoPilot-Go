import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/main.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/ui/styles.dart';
import 'package:celechron/ui/backdrop_settings.dart';
import 'package:celechron/ui/background_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<PilotStyle, StyleTokens> palettes;
  setUpAll(() async {
    palettes = await StyleController.loadPalettes();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperFiles.channel, null);
  });

  test('背景偏好序列化、异常值回退与边界', () {
    const settings = BackdropSettings(
      kind: BackdropKind.wallpaper,
      filePath: '/private/wallpapers/a.jpg',
      panelOpacity: .8,
      veilOpacity: .4,
    );
    final loaded = BackdropSettings.decode(settings.encode());
    expect(loaded.kind, settings.kind);
    expect(loaded.filePath, settings.filePath);
    expect(loaded.panelOpacity, .8);
    expect(BackdropSettings.decode('invalid').kind, BackdropKind.theme);
    expect(
      BackdropSettings.decode('{"kind":"wallpaper"}').kind,
      BackdropKind.theme,
    );
    expect(BackdropSettings.decode('{"panelOpacity":-2}').panelOpacity, .35);
  });

  test('取消选择不改变背景，不清除旧图片', () async {
    final removed = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperFiles.channel, (call) async {
          if (call.method == 'deleteWallpaper') {
            removed.add(call.arguments['path'] as String);
          }
          return null;
        });
    const old = BackdropSettings(
      kind: BackdropKind.wallpaper,
      filePath: '/private/wallpapers/old.jpg',
      panelOpacity: .8,
    );
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      backdrop: old,
    );
    expect(await controller.importWallpaper(), isFalse);
    expect(controller.backdrop.filePath, old.filePath);
    expect(removed, isEmpty);
    expect(controller.saving, isFalse);
  });

  test('导入保存成功后才删除旧壁纸；失败保留旧图并清理新图', () async {
    final removed = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperFiles.channel, (call) async {
          if (call.method == 'pickWallpaper') {
            return '/private/wallpapers/new.jpg';
          }
          removed.add(call.arguments['path'] as String);
          return true;
        });
    String? saved;
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      backdrop: const BackdropSettings(filePath: '/private/wallpapers/old.jpg'),
      backdropWriter: (value) async {
        saved = value;
      },
    );
    expect(await controller.importWallpaper(), isTrue);
    expect(
      BackdropSettings.decode(saved).filePath,
      '/private/wallpapers/new.jpg',
    );
    expect(controller.backdrop.panelOpacity, .9);
    expect(removed, ['/private/wallpapers/old.jpg']);
    removed.clear();
    final failing = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      backdrop: const BackdropSettings(filePath: '/private/wallpapers/old.jpg'),
      backdropWriter: (_) async => throw StateError('write failed'),
    );
    await expectLater(failing.importWallpaper(), throwsStateError);
    expect(failing.backdrop.filePath, '/private/wallpapers/old.jpg');
    expect(removed, ['/private/wallpapers/new.jpg']);
  });

  test('移除壁纸保存纯色回退后再清理文件', () async {
    final removed = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperFiles.channel, (call) async {
          removed.add(call.arguments['path'] as String);
          return true;
        });
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      backdrop: const BackdropSettings(
        kind: BackdropKind.wallpaper,
        filePath: '/private/wallpapers/a.jpg',
        panelOpacity: .8,
      ),
    );
    await controller.removeWallpaper();
    expect(controller.backdrop.filePath, isNull);
    expect(controller.backdrop.panelOpacity, 1);
    expect(controller.backdrop.kind, BackdropKind.theme);
    expect(removed, ['/private/wallpapers/a.jpg']);
  });

  test('全局与 CSS 的不透明度只作用于背景，文字和边框保持清晰', () async {
    final css = await rootBundle.loadString(PilotStyle.custom.asset);
    final tokens = StyleTokens.fromCss(
      PilotStyle.custom,
      '$css\n.cp-item-card { --opacity: 0.5; }',
    );
    final theme = themeFor(
      tokens,
      panelOpacity: .8,
      transparentBackground: true,
    );
    final v = theme.extension<PilotVisuals>()!;
    expect(v.decoration('item-card').color!.a, closeTo(.4, .001));
    expect(v.ink.a, 1);
    expect((v.decoration('item-card').border! as Border).top.color.a, 1);
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(
      () => StyleTokens.fromCss(
        PilotStyle.custom,
        '$css\n.cp-card { --opacity: 1.1; }',
      ),
      throwsFormatException,
    );
  });

  testWidgets('背景设置可打开；只在松手时保存透明度，关闭页面不影响任务', (tester) async {
    final writes = <String>[];
    final controller = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
      backdropWriter: (value) async {
        writes.add(value);
      },
    );
    final repo = PlannerRepository(scope: 'wallpaper-ui', writer: (_) async {});
    await repo.saveItem(
      const Item(id: 'todo', categoryId: 'task', title: '已有任务'),
    );
    await tester.pumpWidget(
      ChronoPilotRoot(styles: controller, repository: repo),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('背景与透明度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('背景与透明度'));
    await tester.pumpAndSettle();
    expect(find.byType(BackgroundSettingsPage), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('panel-opacity-slider')),
    );
    slider.onChanged!(.7);
    await tester.pump();
    expect(writes, isEmpty);
    expect(controller.backdrop.panelOpacity, 1);
    slider.onChangeEnd!(.7);
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(controller.backdrop.panelOpacity, .7);
    expect(repo.find('todo'), isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
