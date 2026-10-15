import 'package:flutter/material.dart';
import 'chat_controller.dart';
import 'draft_card.dart';
import 'features.dart';

class PlannerChatPage extends StatefulWidget {
  final PlannerChat chat;
  final String apiKey, model;
  final Future<void> Function() beforeSend;
  const PlannerChatPage({
    super.key,
    required this.chat,
    required this.apiKey,
    required this.model,
    required this.beforeSend,
  });
  @override
  State<PlannerChatPage> createState() => _PlannerChatPageState();
}

class _PlannerChatPageState extends State<PlannerChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  int _lastCount = -1;
  String? _lastSession;
  String? selected;
  bool sending = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.chat.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chat.removeListener(update);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!agentExecutionEnabled ||
        sending ||
        widget.chat.busy ||
        input.text.trim().isEmpty) {
      return;
    }
    final text = input.text.trim();
    if (text.length > 12000) {
      setState(() => error = '消息过长，请控制在12000字以内');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      if (widget.apiKey.trim().isEmpty) {
        setState(() => error = '请先在设置填写自己的 DeepSeek API Key');
        return;
      }
      selected ??= await widget.chat.create();
      if (!mounted) return;
      input.clear();
      await widget.chat.send(selected!, text, widget.apiKey, widget.model);
    } catch (_) {
      if (mounted) setState(() => error = '无法完成请求，请重试');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.chat.repo.sessions;
    if (selected != null && !sessions.any((e) => e['id'] == selected)) {
      selected = null;
    }
    selected ??= widget.chat.activeSession;
    selected ??= sessions.firstOrNull?['id'] as String?;
    final current = selected == null ? null : widget.chat.session(selected!);
    final messages = current?['messages'] as List? ?? [];
    if (_lastCount != messages.length || _lastSession != selected) {
      _lastCount = messages.length;
      _lastSession = selected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
    final busy = sending || widget.chat.busy;
    return Column(
      children: [
        if (!agentExecutionEnabled)
          const ListTile(
            leading: Icon(Icons.pause_circle_outline),
            title: Text('Agent 接入开发已暂停'),
            subtitle: Text('会话与设置框架已保留，当前不发送模型请求。'),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: selected,
                  isExpanded: true,
                  hint: const Text('选择会话'),
                  items: sessions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(
                            s['title'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => selected = v),
                ),
              ),
              IconButton(
                tooltip: '新会话',
                onPressed: busy
                    ? null
                    : () async {
                        final id = await widget.chat.create();
                        if (mounted) setState(() => selected = id);
                      },
                icon: const Icon(Icons.add_comment_outlined),
              ),
              PopupMenuButton<String>(
                enabled: !busy && selected != null,
                onSelected: (action) async {
                  if (action == 'delete') {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除整个会话？'),
                        content: const Text('历史消息和未确认方案将删除，已写入的日程会保留。'),
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
                      await widget.chat.repo.deleteSession(selected!);
                    }
                  } else {
                    final controller = TextEditingController(
                      text: current?['title'] as String?,
                    );
                    final name = await showDialog<String>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('重命名会话'),
                        content: TextField(
                          controller: controller,
                          maxLength: 60,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(c, controller.text.trim()),
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    );
                    controller.dispose();
                    if (name != null && name.isNotEmpty && current != null) {
                      await widget.chat.repo.renameSession(selected!, name);
                    }
                  }
                  if (mounted) setState(() {});
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除会话')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '告诉我你想安排什么。\n我会读取课表和任务，先给方案，由你确认。\n作业预计用时请先在事项页填写。',
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final message = messages[i] as Map;
                    final draft = message['draft'];
                    return Card(
                      color: message['role'] == 'user'
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['role'] == 'user' ? '你' : 'Agent',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(message['content'] as String? ?? ''),
                            if (draft is Map)
                              DraftCard(
                                key: ValueKey(draft['draftId']),
                                tools: widget.chat.tools,
                                draft: Map<String, dynamic>.from(draft),
                                sessionId: selected!,
                                status:
                                    message['draftStatus'] as String? ??
                                    (message['applied'] == true
                                        ? 'applied'
                                        : null),
                                busy: busy,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (busy) ...[
          const LinearProgressIndicator(),
          TextButton.icon(
            onPressed: widget.chat.cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('取消本次请求'),
          ),
        ],
        if (!busy &&
            widget.chat.error != null &&
            selected != null &&
            messages.isNotEmpty &&
            messages.last['role'] == 'user')
          TextButton(
            onPressed: () =>
                widget.chat.retry(selected!, widget.apiKey, widget.model),
            child: const Text('重试上一条（不重复保存消息）'),
          ),
        if (error != null || widget.chat.error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error ?? widget.chat.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '例如：安排这周的作业',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: !agentExecutionEnabled || busy ? null : send,
                  icon: const Icon(Icons.send),
                  tooltip: '发送',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
