import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celechron/main.dart';
import 'package:celechron/planner/chat_page.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/planner/settings_page.dart';
import 'package:celechron/ui/styles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<PilotStyle, StyleTokens> palettes;
  late Directory directory;
  setUpAll(() async {
    palettes = await StyleController.loadPalettes();
    directory = await Directory.systemTemp.createTemp(
      'chronopilot-navigation-',
    );
    Hive.init(directory.path);
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<PlannerRepository> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = (await tester.runAsync(() async {
      final repo = await PlannerRepository.open('local');
      await PlannerRepository.rememberAccount('local');
      if (repo.find('kept') == null) {
        await repo.saveItem(
          const Item(id: 'kept', categoryId: 'task', title: '已有任务'),
        );
      }
      return repo;
    }))!;
    final styles = StyleController(
      palettes: Map.of(palettes),
      writer: (_) async {},
    );
    addTearDown(styles.dispose);
    await tester.pumpWidget(ChronoPilotRoot(styles: styles, repository: repo));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('五栏导航：设置独立，设置表单和 Agent 输入在来回切换后保留', (tester) async {
    final repo = await mount(tester);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .items
          .length,
      5,
    );
    expect(find.byType(PlannerSettings), findsNothing);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.byTooltip('设置'), findsNothing);
    await tester.enterText(find.byType(TextField), '尚未发送的安排');
    final chatState = tester.state(find.byType(PlannerChatPage));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    final settingsState = tester.state(find.byType(PlannerSettings));
    await tester.scrollUntilVisible(
      field('自己的 API Key'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('planner-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(field('自己的 API Key'), 'test-key');
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PlannerChatPage)), same(chatState));
    expect(find.text('尚未发送的安排'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PlannerSettings)), same(settingsState));
    expect(
      tester.widget<TextField>(field('自己的 API Key')).controller!.text,
      'test-key',
    );
    expect(repo.find('kept'), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('保存不弹出根路由，新模型配置传给已有聊天页', (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    final chatState = tester.state(find.byType(PlannerChatPage));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      field('自己的 API Key'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('planner-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(field('自己的 API Key'), 'local-test-key');
    await tester.scrollUntilVisible(
      field('模型 ID'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('planner-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(field('模型 ID'), 'local-test-model');
    await tester.runAsync(() async {
      await tester.tap(find.text('保存设置'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(PlannerSettings), findsOneWidget);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      4,
    );
    expect(find.text('设置已保存'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    final page = tester.widget<PlannerChatPage>(find.byType(PlannerChatPage));
    expect(page.apiKey, 'local-test-key');
    expect(page.model, 'local-test-model');
    expect(tester.state(find.byType(PlannerChatPage)), same(chatState));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('连接配置变化后重建设置数据源，仍留在第五栏并保留本地事项', (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final oldState = tester.state(find.byType(PlannerSettings));
    await tester.scrollUntilVisible(
      field('统一认证密码'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('planner-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // Local mode with changed credentials exercises reload without school requests.
    await tester.enterText(field('统一认证密码'), 'local-only-test');
    await tester.runAsync(() async {
      await tester.tap(find.text('保存设置'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final settings = tester.widget<PlannerSettings>(
      find.byType(PlannerSettings),
    );
    expect(settings.password, 'local-only-test');
    expect(settings.repo.find('kept'), isNotNull);
    expect(tester.state(find.byType(PlannerSettings)), isNot(same(oldState)));
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      4,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
