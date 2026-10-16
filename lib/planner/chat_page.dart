import '../ui/agent_markdown.dart';
import 'package:flutter/material.dart';
import 'chat_controller.dart';
import 'draft_card.dart';
import 'features.dart';
import 'session_drawer.dart';
import '../ui/eclipse_mark.dart';
import '../ui/styles.dart';

class PlannerChatPage extends StatefulWidget {
  final PlannerChat chat;
  final String apiKey, model;
  final Future<void> Function() beforeSend;
  final VoidCallback onSettings;
  const PlannerChatPage({
    super.key,
    required this.chat,
    required this.apiKey,
    required this.model,
    required this.beforeSend,
    required this.onSettings,
  });
  @override
  State<PlannerChatPage> createState() => _PlannerChatPageState();
}

class _PlannerChatPageState extends State<PlannerChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  int _lastCount = -1, _lastStreamLength = 0;
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

  final scaffold = GlobalKey<ScaffoldState>();
  final drafts = <String, String>{};
  void selectSession(String id) {
    drafts[selected ?? "new"] = input.text;
    setState(() {
      selected = id;
      error = null;
      input.text = drafts[id] ?? "";
    });
    scaffold.currentState?.closeDrawer();
  }

  Future<void> newSession({bool closeDrawer = false}) async {
    try {
      final id = await widget.chat.create();
      if (!mounted) return;
      drafts[selected ?? "new"] = input.text;
      setState(() {
        selected = id;
        error = null;
        input.clear();
      });
      if (closeDrawer) scaffold.currentState?.closeDrawer();
    } catch (_) {
      if (mounted) setState(() => error = '无法创建会话，请重试');
    }
  }

  Future<void> manageSession(String id, String action) async {
    scaffold.currentState?.closeDrawer();
    final current = widget.chat.session(id);
    if (current == null) return;
    try {
      if (action == 'delete') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('删除整个会话？'),
            content: const Text('删除历史消息和未确认方案，已写入的日程保留。'),
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
        if (yes == true) await widget.chat.repo.deleteSession(id);
      } else {
        final name = await showDialog<String>(
          context: context,
          builder: (_) => _SessionNameDialog(
            initialName: current['title'] as String? ?? '',
          ),
        );
        if (name != null && name.isNotEmpty) {
          await widget.chat.repo.renameSession(id, name);
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = '会话操作未完成，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.chat.repo.sessions;
    if (selected != null && !sessions.any((e) => e['id'] == selected)) {
      selected = null;
    }
    selected ??= widget.chat.activeSession;
    if (selected != null && !sessions.any((e) => e['id'] == selected)) {
      selected = null;
    }
    selected ??= sessions.firstOrNull?['id'] as String?;
    final current = selected == null ? null : widget.chat.session(selected!);
    final messages = List<dynamic>.of(current?['messages'] as List? ?? []);
    if (widget.chat.busy &&
        widget.chat.activeSession == selected &&
        widget.chat.streamedText.isNotEmpty) {
      messages.add({
        'role': 'assistant',
        'content': widget.chat.streamedText,
        'streaming': true,
      });
    }
    if (_lastCount != messages.length ||
        _lastSession != selected ||
        _lastStreamLength != widget.chat.streamedText.length) {
      final follow =
          _lastSession != selected ||
          !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 120;
      _lastStreamLength = widget.chat.streamedText.length;
      _lastCount = messages.length;
      _lastSession = selected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients && follow) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
    final busy = sending || widget.chat.busy, v = PilotVisuals.of(context);
    return Scaffold(
      key: scaffold,
      backgroundColor: Colors.transparent,
      drawer: SessionDrawer(
        sessions: sessions,
        selected: selected,
        busy: busy,
        onNew: () => newSession(closeDrawer: true),
        onSelected: selectSession,
        onManage: manageSession,
      ),
      appBar: AppBar(
        toolbarHeight: 56,
        centerTitle: true,
        leading: IconButton(
          tooltip: '历史对话',
          icon: const Icon(Icons.menu),
          onPressed: () => scaffold.currentState?.openDrawer(),
        ),
        title: Text(
          current?['title'] as String? ?? '新对话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: '新会话',
            onPressed: busy ? null : () => newSession(),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: widget.onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!agentExecutionEnabled)
            const ListTile(title: Text('Agent 接入开发已暂停')),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EclipseMark(size: 60),
                          const SizedBox(height: 24),
                          Text(
                            '今天想安排什么？',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: v.ink,
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final message = messages[i] as Map,
                          draft = message['draft'],
                          user = message['role'] == 'user';
                      final content = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AgentMarkdown(
                            data: message['content'] as String? ?? '',
                          ),
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
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: user
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * .84,
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    12,
                                    0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: v.surface,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: content,
                                ),
                              )
                            : content,
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
              child: const Text('重试上一条'),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                decoration: BoxDecoration(
                  color: v.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: v.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: '发送消息',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: !agentExecutionEnabled || busy ? null : send,
                      icon: const Icon(Icons.send),
                      tooltip: '发送',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionNameDialog extends StatefulWidget {
  final String initialName;
  const _SessionNameDialog({required this.initialName});
  @override
  State<_SessionNameDialog> createState() => _SessionNameDialogState();
}

class _SessionNameDialogState extends State<_SessionNameDialog> {
  late final editor = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('重命名会话'),
    content: TextField(controller: editor, maxLength: 60, autofocus: true),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, editor.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}
