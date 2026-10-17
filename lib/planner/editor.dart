import '../ui/styles.dart';
import '../ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'item.dart';
import 'data_api.dart';
import '../ui/components.dart';

Future<void> editItem(
  BuildContext context,
  PlannerDataApi repo, [
  Item? item,
]) => Navigator.of(context).push(
  PilotPageRoute<void>(
    builder: (_) => ItemEditor(repo: repo, item: item),
  ),
);

class ItemEditor extends StatefulWidget {
  final PlannerDataApi repo;
  final Item? item;
  const ItemEditor({super.key, required this.repo, this.item});
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  late final title = TextEditingController(text: widget.item?.title);
  late final subject = TextEditingController(text: widget.item?.subject);
  late final notes = TextEditingController(text: widget.item?.notes);
  late final location = TextEditingController(text: widget.item?.location);
  late final duration = TextEditingController(
    text: widget.item?.estimatedMinutes?.toString(),
  );
  late String category = widget.item?.categoryId ?? 'task';
  late DateTime? start = widget.item?.start,
      end = widget.item?.end,
      deadline = widget.item?.deadline;
  bool saving = false;
  String? error;
  bool get locked => widget.item?.school == true;
  Future<DateTime?> pick(DateTime? value) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value ?? now),
    );
    return time == null
        ? null
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final minutes = duration.text.trim().isEmpty
          ? null
          : int.tryParse(duration.text.trim());
      if (duration.text.trim().isNotEmpty && minutes == null) {
        throw const FormatException('预计用时请填写整数分钟');
      }
      if (!locked && category == 'event' && (start == null || end == null)) {
        throw const FormatException('固定日程需要开始和结束时间');
      }
      final changes = <String, dynamic>{
        'title': title.text.trim(),
        'subject': subject.text.trim(),
        'notes': notes.text,
        'location': location.text,
        'categoryId': category,
        'start': start == null ? null : timestamp(start!),
        'end': end == null ? null : timestamp(end!),
        'deadline': deadline == null ? null : timestamp(deadline!),
        'estimatedMinutes': minutes,
      };
      final item =
          widget.item?.patch(changes) ??
          Item.fromJson({'id': const Uuid().v4(), ...changes});
      await widget.repo.saveItem(item);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is FormatException ? e.message.toString() : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [title, subject, notes, location, duration]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget timeField(String field) {
    final value = switch (field) {
      '开始' => start,
      '结束' => end,
      _ => deadline,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(field == '截止' ? Icons.flag_outlined : Icons.access_time),
      title: Text('$field时间'),
      subtitle: Text(value == null ? '未设置' : localTime(value)),
      trailing: locked
          ? const Icon(Icons.lock_outline, size: 18)
          : PilotControl(
              className: 'item-time-clear',
              kind: 'icon-button',
              child: IconButton(
                tooltip: '清除$field时间',
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() {
                  if (field == '截止') {
                    deadline = null;
                  } else {
                    start = null;
                    end = null;
                  }
                }),
              ),
            ),
      onTap: locked
          ? null
          : () async {
              final value = await pick(switch (field) {
                '开始' => start,
                '结束' => end,
                _ => deadline,
              });
              if (value != null && mounted) {
                setState(() {
                  if (field == '开始') {
                    start = value;
                  } else if (field == '结束') {
                    end = value;
                  } else {
                    deadline = value;
                  }
                });
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item == null ? '添加事项' : '编辑事项')),
    body: ContentFrame(
      maxWidth: 760,
      child: ListView(
        key: const ValueKey('item-editor-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          if (locked)
            const NoticePanel(
              title: '学校同步事项',
              subtitle: '时间与名称随学校更新；你可以填写备注和预计用时。',
              icon: Icons.lock_outline,
            ),
          const SectionHeading(title: '事项信息', code: '01 / DETAILS'),
          SurfacePanel(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '类别'),
                  items: ItemCategory.values
                      .where((e) => e.id != 'course' || locked)
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.label)),
                      )
                      .toList(),
                  onChanged: locked
                      ? null
                      : (v) => setState(() => category = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  readOnly: locked,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subject,
                  readOnly: locked,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: '学科（用于筛选）'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: location,
                  readOnly: locked,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: '地点'),
                ),
              ],
            ),
          ),
          const SectionHeading(
            title: '时间节点',
            code: '02 / TIME MARKERS',
            description: '固定日程填写开始和结束；作业、任务可以只设截止时间。',
          ),
          SurfacePanel(
            child: Column(
              children: [
                timeField('开始'),
                const Divider(),
                timeField('结束'),
                const Divider(),
                timeField('截止'),
              ],
            ),
          ),
          const SectionHeading(
            title: '用时与备注',
            code: '03 / NOTES',
            description: '预计用时由你填写，Agent 会遵循它，不会替你猜测。',
          ),
          SurfacePanel(
            child: Column(
              children: [
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '预计用时（分钟）',
                    helperText: '可留空；安排作业或复习前需要填写。',
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: notes,
                  maxLength: 3000,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '例如：题目范围、准备材料或其他说明',
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: NoticePanel(title: error!, icon: Icons.error_outline),
            ),
          const SizedBox(height: 24),
          PilotControl(
            className: 'item-save',
            kind: 'primary-button',
            child: FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.check),
              label: Text(saving ? '保存中…' : '保存'),
            ),
          ),
          if (widget.item != null && !locked)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PilotControl(
                className: 'item-delete',
                kind: 'text-button',
                child: TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                            animationStyle: AnimationStyle.noAnimation,
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('删除事项？'),
                              content: const Text('关联的未来 Agent 时间块也会删除。'),
                              actions: [
                                PilotControl(
                                  className: 'item-delete-cancel',
                                  kind: 'text-button',
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('取消'),
                                  ),
                                ),
                                PilotControl(
                                  className: 'item-delete-confirm',
                                  kind: 'text-button',
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('删除'),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) {
                            try {
                              await widget.repo.removeItem(widget.item!.id);
                              if (context.mounted) Navigator.pop(context);
                            } catch (_) {
                              if (mounted) setState(() => error = '删除失败，请重试');
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除事项'),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
