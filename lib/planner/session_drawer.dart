import '../ui/controls.dart';
import 'package:flutter/material.dart';
import '../ui/styles.dart';

class SessionDrawer extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final String? selected;
  final bool busy;
  final ValueChanged<String> onSelected;
  final void Function(String, String) onManage;
  final VoidCallback onNew;
  const SessionDrawer({
    super.key,
    required this.sessions,
    required this.selected,
    required this.busy,
    required this.onSelected,
    required this.onManage,
    required this.onNew,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context),
        now = DateUtils.dateOnly(DateTime.now());
    final ordered = sessions.indexed.toList()
      ..sort((a, b) {
        final ad = DateTime.tryParse(
              a.$2['updatedAt'] as String? ??
                  a.$2['createdAt'] as String? ??
                  '',
            ),
            bd = DateTime.tryParse(
              b.$2['updatedAt'] as String? ??
                  b.$2['createdAt'] as String? ??
                  '',
            );
        return ad == null
            ? (bd == null ? a.$1.compareTo(b.$1) : 1)
            : bd == null
            ? -1
            : bd.compareTo(ad);
      });
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final entry in ordered) {
      final s = entry.$2;
      final date = DateTime.tryParse(
        s['updatedAt'] as String? ?? s['createdAt'] as String? ?? '',
      )?.toLocal();
      final days = date == null
          ? null
          : now.difference(DateUtils.dateOnly(date)).inDays;
      final label = days == null
          ? '历史会话'
          : days <= 0
          ? '今天'
          : days == 1
          ? '昨天'
          : days < 7
          ? '最近七天'
          : '更早';
      groups.putIfAbsent(label, () => []).add(s);
    }
    final entries = <Object>[];
    for (final group in groups.entries) {
      entries.add(group.key);
      entries.addAll(group.value);
    }
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * .84).clamp(240, 360),
      backgroundColor: v.decoration('drawer').color,
      shape: v.shape('drawer'),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '历史对话',
                      style: TextStyle(
                        color: v.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PilotControl(
                    className: 'history-close',
                    kind: 'icon-button',
                    child: IconButton(
                      tooltip: '关闭对话列表',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PilotControl(
                className: 'history-new',
                kind: 'secondary-button',
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onNew,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('新对话'),
                ),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('暂无历史对话', style: TextStyle(color: v.muted)),
                    )
                  : ListView.builder(
                      key: const ValueKey('session-history-list'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                            child: Text(
                              entry,
                              style: TextStyle(color: v.muted, fontSize: 13),
                            ),
                          );
                        }
                        final s = entry as Map<String, dynamic>;
                        return ListTile(
                          key: ValueKey('session-${s['id']}'),
                          selected: s['id'] == selected,
                          selectedTileColor: v.accent.withValues(alpha: .12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          title: Text(
                            s['title'] as String? ?? '新对话',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: v.ink, fontSize: 16),
                          ),
                          contentPadding: const EdgeInsets.only(
                            left: 12,
                            right: 0,
                          ),
                          onTap: () => onSelected(s['id'] as String),
                          trailing: PilotControl(
                            className: 'history-menu',
                            kind: 'menu-button',
                            child: PopupMenuButton<String>(
                              tooltip: '会话操作',
                              enabled: !busy,
                              icon: Icon(Icons.more_horiz, color: v.muted),
                              onSelected: (action) =>
                                  onManage(s['id'] as String, action),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除会话'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
