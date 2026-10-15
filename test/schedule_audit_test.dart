import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/item.dart';
import 'package:celechron/planner/schedule_audit.dart';

void main() {
  test('学校更新或用户修改造成冲突时提示，不移动原时间块', () {
    final now = DateTime(2026, 10, 15), start = DateTime(2026, 10, 16, 14);
    final items = [
      Item(
        id: 'p',
        categoryId: 'task',
        title: '作业',
        estimatedMinutes: 10,
        deadline: start,
      ),
      Item(
        id: 'b',
        categoryId: 'event',
        title: '做作业',
        origin: 'agent',
        parentId: 'p',
        start: start,
        end: start.add(const Duration(minutes: 30)),
      ),
      Item(
        id: 'c',
        categoryId: 'course',
        title: '新课程',
        start: start,
        end: start.add(const Duration(hours: 1)),
      ),
    ];
    final warnings = scheduleWarnings(items, now);
    expect(warnings, hasLength(3));
    expect(items[1].start, start);
  });
}
