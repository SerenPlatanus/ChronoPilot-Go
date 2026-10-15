import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'item.dart';
import 'data_api.dart';

Future<void> editItem(
  BuildContext context,
  PlannerDataApi repo, [
  Item? item,
]) => Navigator.of(context).push(
  MaterialPageRoute<void>(
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item == null ? '添加事项' : '编辑事项')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (locked) const Text('学校同步事项：时间与名称随学校数据更新，可编辑备注、预计用时和完成状态。'),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: '类别'),
          items: ItemCategory.values
              .where((e) => e.id != 'course' || locked)
              .map((e) => DropdownMenuItem(value: e.id, child: Text(e.label)))
              .toList(),
          onChanged: locked ? null : (v) => setState(() => category = v!),
        ),
        TextField(
          controller: title,
          readOnly: locked,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        TextField(
          controller: subject,
          readOnly: locked,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '学科（用于筛选）'),
        ),
        TextField(
          controller: location,
          readOnly: locked,
          maxLength: 200,
          decoration: const InputDecoration(labelText: '地点'),
        ),
        for (final field in ['开始', '结束', '截止'])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('$field时间'),
            subtitle: Text(
              (switch (field) {
                        '开始' => start,
                        '结束' => end,
                        _ => deadline,
                      }) ==
                      null
                  ? '未设置'
                  : localTime(
                      (switch (field) {
                        '开始' => start,
                        '结束' => end,
                        _ => deadline,
                      })!,
                    ),
            ),
            trailing: locked
                ? null
                : IconButton(
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
          ),
        TextField(
          controller: duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '预计用时（分钟，由你填写，可留空）',
            helperText: 'Agent 不会猜测；安排作业前需填写。',
          ),
        ),
        TextField(
          controller: notes,
          maxLength: 3000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? '保存中…' : '保存'),
        ),
        if (widget.item != null && !locked)
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除事项？'),
                        content: const Text('关联的未来 Agent 时间块也会删除。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await widget.repo.removeItem(widget.item!.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
            child: const Text('删除事项'),
          ),
      ],
    ),
  );
}
