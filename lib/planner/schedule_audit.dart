import 'item.dart';

/// Recheck saved plans against changes from school sync or manual edits.
/// Never silently move a previously confirmed block.
List<String> scheduleWarnings(List<Item> items, DateTime now) {
  final byId = {for (final i in items) i.id: i};
  final warnings = <String>{};
  final blocks = items.where(
    (i) =>
        i.origin == 'agent' && i.timed && !i.completed && i.end!.isAfter(now),
  );
  for (final b in blocks) {
    final parent = byId[b.parentId];
    if (parent == null || parent.completed) {
      warnings.add('「${b.title}」关联事项已失效');
      continue;
    }
    final deadline = parent.categoryId == 'exam'
        ? parent.start ?? parent.deadline
        : parent.deadline;
    if (deadline != null && b.end!.isAfter(deadline)) {
      warnings.add('「${b.title}」晚于最新截止或考试时间');
    }
    for (final other in items) {
      if (other.id != b.id && b.overlaps(other)) {
        warnings.add('「${b.title}」与「${other.title}」冲突');
        break;
      }
    }
    final seconds = items
        .where((i) => i.parentId == parent.id && i.timed)
        .fold<int>(0, (n, i) => n + i.end!.difference(i.start!).inSeconds);
    if (parent.estimatedMinutes == null ||
        seconds > parent.estimatedMinutes! * 60) {
      warnings.add('「${parent.title}」的安排超过当前预计用时或缺少用时');
    }
  }
  return warnings.toList();
}
