import 'item.dart';

/// Academic half-years follow the school's partition, rather than subject names.
/// Existing caches need no migration: course partitions already carry this key.
String academicTerm(DateTime date) {
  final autumn = date.month >= 9 || date.month == 1;
  final year = date.month >= 9 ? date.year : date.year - 1;
  return '$year:${autumn ? 1 : 2}';
}

String? itemTerm(Item item) {
  final partition = RegExp(
    r'^courses:(\d{4}):([12])$',
  ).firstMatch(item.sourceKey);
  if (partition != null) return '${partition[1]}:${partition[2]}';
  final date = item.start ?? item.deadline;
  return date == null ? null : academicTerm(date);
}

String termLabel(String key) {
  if (key == 'all') return '全部学期';
  if (key == 'undated') return '未归属学期';
  final parts = key.split(':');
  final year = int.parse(parts[0]);
  return '${year % 100}-${(year + 1) % 100}${parts[1] == '1' ? '秋冬' : '春夏'}';
}

bool inTerm(Item item, String term) =>
    term == 'all' ||
    (!item.school && item.categoryId != 'course') ||
    (term == 'undated' ? itemTerm(item) == null : itemTerm(item) == term);
