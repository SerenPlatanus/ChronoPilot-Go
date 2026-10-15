import 'dart:convert';
import 'package:crypto/crypto.dart';

class ItemCategory {
  final String id;
  final String label;
  final bool workload;
  const ItemCategory(this.id, this.label, {this.workload = false});
  static const values = [
    ItemCategory('course', '课程'),
    ItemCategory('homework', '作业', workload: true),
    ItemCategory('exam', '考试'),
    ItemCategory('task', '个人任务', workload: true),
    ItemCategory('event', '固定日程'),
  ];
  static ItemCategory of(String id) =>
      values.firstWhere((c) => c.id == id, orElse: () => ItemCategory(id, id));
}

/// Immutable, versioned common record. Category IDs are extensible strings.
class Item {
  final String id,
      categoryId,
      title,
      subject,
      notes,
      location,
      origin,
      sourceKey;
  final DateTime? start, end, deadline;
  final bool completed;
  final int? estimatedMinutes;
  final String? parentId;
  final int revision;
  const Item({
    required this.id,
    required this.categoryId,
    required this.title,
    this.subject = '',
    this.notes = '',
    this.location = '',
    this.origin = 'manual',
    this.sourceKey = '',
    this.start,
    this.end,
    this.deadline,
    this.completed = false,
    this.estimatedMinutes,
    this.parentId,
    this.revision = 0,
  });
  ItemCategory get category => ItemCategory.of(categoryId);
  bool get school => origin == 'school';
  bool get timed => start != null && end != null;
  DateTime? get sortTime => start ?? deadline;
  DateTime? countdownTarget(DateTime now) =>
      start != null && now.isBefore(start!) ? start : end ?? deadline ?? start;
  bool upcoming(DateTime now) =>
      !completed && (end ?? deadline ?? start)?.isBefore(now) != true;
  bool overlaps(Item other) =>
      timed &&
      other.timed &&
      start!.isBefore(other.end!) &&
      end!.isAfter(other.start!);
  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'title': title,
    'subject': subject,
    'notes': notes,
    'location': location,
    'origin': origin,
    'sourceKey': sourceKey,
    'start': start?.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(),
    'deadline': deadline?.toUtc().toIso8601String(),
    'completed': completed,
    'estimatedMinutes': estimatedMinutes,
    'parentId': parentId,
    'revision': revision,
  };
  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: j['id'] as String,
    categoryId: j['categoryId'] as String,
    title: j['title'] as String,
    subject: (j['subject'] as String? ?? '').trim(),
    notes: j['notes'] as String? ?? '',
    location: j['location'] as String? ?? '',
    origin: j['origin'] as String? ?? 'manual',
    sourceKey: j['sourceKey'] as String? ?? '',
    start: _date(j['start']),
    end: _date(j['end']),
    deadline: _date(j['deadline']),
    completed: j['completed'] == true,
    estimatedMinutes: j['estimatedMinutes'] as int?,
    parentId: j['parentId'] as String?,
    revision: j['revision'] as int? ?? 0,
  );
  Item patch(Map<String, dynamic> changes) => Item.fromJson({
    ...toJson(),
    ...changes,
    'id': id,
    'revision': revision + 1,
  });
  void validate() {
    if (title.trim().isEmpty || title.length > 120 || categoryId.isEmpty) {
      throw const FormatException('请填写事项名称（不超过120字）');
    }
    if (subject.length > 100 || notes.length > 3000 || location.length > 200) {
      throw const FormatException('学科、备注或地点过长');
    }
    if ((start == null) != (end == null) || (timed && !end!.isAfter(start!))) {
      throw const FormatException('请提供有效的开始和结束时间');
    }
    if (estimatedMinutes != null &&
        (estimatedMinutes! < 1 || estimatedMinutes! > 43200)) {
      throw const FormatException('预计用时需为1–43200分钟');
    }
  }

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}

String stableId(String key) =>
    sha256.convert(utf8.encode(key)).toString().substring(0, 24);
String timestamp(DateTime value) => value.toUtc().toIso8601String();
String localTime(DateTime t) {
  t = t.toLocal();
  return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String countdown(Item item, DateTime now) {
  if (item.completed) return '已完成';
  final target = item.countdownTarget(now);
  if (target == null) return '未设置时间';
  final d = target.difference(now);
  if (d.isNegative) return item.timed ? '已结束' : '已过期';
  final label = item.timed && !now.isBefore(item.start!)
      ? '距结束'
      : item.start != null
      ? '距开始'
      : '距截止';
  return '$label ${d.inDays > 0 ? '${d.inDays}天 ' : ''}'
      '${d.inHours % 24}时${d.inMinutes % 60}分${d.inSeconds % 60}秒';
}
