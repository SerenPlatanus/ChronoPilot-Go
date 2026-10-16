import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/semester_filter.dart';
import 'package:celechron/ui/course_color.dart';
import 'package:celechron/ui/planner_calendar.dart';
import 'package:celechron/ui/agent_markdown.dart';

void main() {
  test('学年跨年、春夏归属与学校分区优先，未定日期不伪造学期', () {
    expect(academicTerm(DateTime(2026, 10)), '2026:1');
    expect(academicTerm(DateTime(2027, 1)), '2026:1');
    expect(academicTerm(DateTime(2027, 3)), '2026:2');
    expect(academicTerm(DateTime(2026, 8)), '2025:2');
    const course = Item(
      id: 'c',
      categoryId: 'course',
      title: '物理',
      origin: 'school',
      sourceKey: 'courses:2024:2',
    );
    expect(itemTerm(course), '2024:2');
    expect(inTerm(course, '2026:1'), false);
    expect(
      itemTerm(
        const Item(
          id: 'h',
          categoryId: 'homework',
          title: '待公布',
          origin: 'school',
        ),
      ),
      isNull,
    );
    expect(
      inTerm(
        const Item(
          id: 'h',
          categoryId: 'homework',
          title: '待公布',
          origin: 'school',
        ),
        'undated',
      ),
      true,
    );
  });
  test('同学科作业与课程保持同色；跨午夜日程在两天可见', () {
    final course = Item(
      id: 'c',
      categoryId: 'course',
      title: '课程',
      subject: '操作系统',
      start: DateTime(2026, 10, 15, 23),
      end: DateTime(2026, 10, 16, 1),
    );
    const homework = Item(
      id: 'h',
      categoryId: 'homework',
      title: '作业',
      subject: '操作系统',
    );
    expect(courseColor(course), courseColor(homework));
    expect(onDay([course], DateTime(2026, 10, 16)), hasLength(1));
    expect(onDay([course], DateTime(2026, 10, 17)), isEmpty);
  });
  testWidgets('月历可收起、选日期和翻月', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerCalendar(
            day: DateTime(2026, 10, 15),
            items: const [],
            onChanged: (d) => selected = d,
            onTimetable: () {},
          ),
        ),
      ),
    );
    expect(find.text('31'), findsOneWidget);
    await tester.tap(find.text('27'));
    expect(selected, DateTime(2026, 10, 27));
    await tester.tap(find.byTooltip('下个月'));
    expect(selected, DateTime(2026, 11));
    await tester.tap(find.byTooltip('收起月历'));
    await tester.pumpAndSettle();
    expect(find.text('31'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('大课表同屏七列，短课块、并发课程和放大模式可操作', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = List.generate(
      3,
      (i) => Item(
        id: 'c$i',
        categoryId: 'course',
        title: '很长的课程名称测试',
        location: '玉泉教4-201',
        start: DateTime(2026, 10, 15, 8, i * 5),
        end: DateTime(2026, 10, 15, 8, 20 + i * 5),
      ),
    );
    Item? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: LargeTimetable(
          items: items,
          initialDay: DateTime(2026, 10, 15),
          onTap: (i) => selected = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('日 18'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find
          .ancestor(
            of: find.text('很长的课程名称测试').first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(selected, isNotNull);
    await tester.tap(find.byTooltip('切换课表缩放'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('Markdown ${dark ? '深色' : '浅色'} 标题列表表格代码可选中且无横向溢出', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data =
          '# 计划\n\n**重点**与 `inline`\n\n- 第一项\n- 第二项\n\n| 事项 | 时长 |\n| --- | --- |\n| 作业 | 30分钟 |\n\n```json\n${'long_code_' * 50}\n```';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AgentMarkdown(data: data),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.selectable, true);
      expect(find.byType(Table), findsOneWidget);
      expect(find.byTooltip('复制消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
