import 'package:flutter/material.dart';
import 'agent_tools.dart';
import 'item.dart';
import '../ui/components.dart';
import '../ui/styles.dart';

class DraftCard extends StatefulWidget {
  final PlannerTools tools;
  final Map<String, dynamic> draft;
  final String sessionId;
  final String? status;
  final bool busy;
  const DraftCard({
    super.key,
    required this.tools,
    required this.draft,
    required this.sessionId,
    this.status,
    this.busy = false,
  });
  @override
  State<DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<DraftCard> {
  bool saving = false;
  String? error;
  String describe(dynamic data) {
    if (data is! Map) return '';
    final item = Item.fromJson(Map<String, dynamic>.from(data));
    return '${item.title}\n${item.start == null ? '未设置时间' : localTime(item.start!)} — ${item.end == null ? '' : localTime(item.end!)}';
  }

  @override
  Widget build(BuildContext context) {
    String? invalid;
    if (widget.status == null) {
      try {
        widget.tools.validate(widget.draft, widget.tools.repo.items);
      } catch (e) {
        invalid = e is FormatException
            ? e.message.toString()
            : '旧方案格式不兼容，请重新生成';
      }
    }
    final statusText = switch (widget.status) {
      'applied' => '已写入日程',
      'superseded' => '已被后续对话替代',
      'dismissed' => '已放弃',
      _ => invalid ?? '待你确认，尚未写入',
    };
    final disabled =
        saving || widget.busy || widget.status != null || invalid != null;
    final v = PilotVisuals.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SurfacePanel(
        padding: const EdgeInsets.all(14),
        color: v.cassette
            ? (v.dark ? v.screen : const Color(0xffe9dfc9))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日程方案', style: instrumentText(color: v.accent, size: 11)),
            const SizedBox(height: 10),
            Text(
              widget.draft['summary'] as String? ?? '日程方案',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final change in widget.draft['changes'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(switch (change['action']) {
                  'add' => '新增时间块',
                  'delete' => '删除时间块',
                  _ => '调整时间块',
                }),
                subtitle: Text(
                  [
                    if (change['before'] != null)
                      '原：${describe(change['before'])}',
                    if (change['after'] != null)
                      '新：${describe(change['after'])}',
                  ].join('\n'),
                ),
              ),
            const SizedBox(height: 8),
            SignalBadge(
              label: statusText,
              icon: widget.status == 'applied'
                  ? Icons.check_circle_outline
                  : invalid != null
                  ? Icons.warning_amber
                  : Icons.pending_outlined,
            ),
            const SizedBox(height: 12),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: disabled
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await widget.tools.apply(
                              widget.draft,
                              sessionId: widget.sessionId,
                            );
                          } catch (e) {
                            if (mounted) {
                              setState(
                                () => error = e is FormatException
                                    ? e.message.toString()
                                    : '保存失败，未写入，请重试',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  child: Text(saving ? '保存中…' : '确认并写入日程'),
                ),
                if (widget.status == null)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () async {
                            try {
                              await widget.tools.repo.dismissDraft(
                                widget.sessionId,
                                widget.draft['draftId'] as String,
                              );
                            } catch (_) {
                              if (mounted) setState(() => error = '操作失败，请重试');
                            }
                          },
                    child: const Text('放弃方案'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
