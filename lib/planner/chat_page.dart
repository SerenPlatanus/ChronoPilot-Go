import '../ui/controls.dart';
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

  bool historyOpen = false;
  double historyDrag = 0;
  void closeHistory() {
    if (historyOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> openHistory() async {
    if (historyOpen) return;
    historyOpen = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭对话列表',
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -150) closeHistory();
            },
            child: ListenableBuilder(
              listenable: widget.chat,
              builder: (_, __) => SessionDrawer(
                sessions: widget.chat.repo.sessions,
                selected: selected,
                busy: widget.chat.busy,
                onNew: () => newSession(closeDrawer: true),
                onSelected: selectSession,
                onManage: manageSession,
              ),
            ),
          ),
        ),
      );
    } finally {
      historyOpen = false;
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
    closeHistory();
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
      if (closeDrawer) closeHistory();
    } catch (_) {
      if (mounted) setState(() => error = '无法创建会话，请重试');
    }
  }

  Future<void> manageSession(String id, String action) async {
    closeHistory();
    final current = widget.chat.session(id);
    if (current == null) return;
    try {
      if (action == 'delete') {
        final yes = await showDialog<bool>(
          animationStyle: AnimationStyle.noAnimation,
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('删除整个会话？'),
            content: const Text('删除历史消息和未确认方案，已写入的日程保留。'),
            actions: [
              PilotControl(
                className: 'chat-delete-cancel',
                kind: 'text-button',
                child: TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消'),
                ),
              ),
              PilotControl(
                className: 'chat-delete-confirm',
                kind: 'text-button',
                child: TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('删除'),
                ),
              ),
            ],
          ),
        );
        if (yes == true) await widget.chat.repo.deleteSession(id);
      } else {
        final name = await showDialog<String>(
          animationStyle: AnimationStyle.noAnimation,
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
    return Stack(
      children: [
        Scaffold(
          key: scaffold,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 56,
            centerTitle: true,
            leading: PilotControl(
              className: 'chat-history',
              kind: 'icon-button',
              child: IconButton(
                style: const ButtonStyle(
                  side: WidgetStatePropertyAll(BorderSide.none),
                ),
                tooltip: '历史对话',
                icon: const Icon(Icons.menu),
                onPressed: openHistory,
              ),
            ),
            title: Text(
              current?['title'] as String? ?? '新对话',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            actions: [
              PilotControl(
                className: 'chat-new',
                kind: 'icon-button',
                child: IconButton(
                  style: const ButtonStyle(
                    side: WidgetStatePropertyAll(BorderSide.none),
                  ),
                  tooltip: '新会话',
                  onPressed: busy ? null : () => newSession(),
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ),
              PilotControl(
                className: 'agent-settings',
                kind: 'icon-button',
                child: IconButton(
                  style: const ButtonStyle(
                    side: WidgetStatePropertyAll(BorderSide.none),
                  ),
                  tooltip: '设置',
                  onPressed: widget.onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
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
                                            MediaQuery.sizeOf(context).width *
                                            .84,
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        12,
                                        0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: v.surface,
                                        borderRadius: BorderRadius.circular(
                                          v.tokens?.controls.isNotEmpty == true
                                              ? v.radius
                                              : 18,
                                        ),
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
                const Padding(padding: EdgeInsets.all(8), child: Text('正在生成…')),
                PilotControl(
                  className: 'agent-stop',
                  kind: 'text-button',
                  child: TextButton.icon(
                    onPressed: widget.chat.cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('取消本次请求'),
                  ),
                ),
              ],
              if (!busy &&
                  widget.chat.error != null &&
                  selected != null &&
                  messages.isNotEmpty &&
                  messages.last['role'] == 'user')
                PilotControl(
                  className: 'agent-retry',
                  kind: 'text-button',
                  child: TextButton(
                    onPressed: () => widget.chat.retry(
                      selected!,
                      widget.apiKey,
                      widget.model,
                    ),
                    child: const Text('重试上一条'),
                  ),
                ),
              if (error != null || widget.chat.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    error ?? widget.chat.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    decoration: v.decoration('composer', defaultRadius: 26),
                    clipBehavior: Clip.antiAlias,
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
                        PilotControl(
                          className: 'agent-send',
                          kind: 'icon-button',
                          child: IconButton.filled(
                            onPressed: !agentExecutionEnabled || busy
                                ? null
                                : send,
                            icon: const Icon(Icons.send),
                            tooltip: '发送',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 56,
          bottom: 0,
          width: 20,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => historyDrag = 0,
            onHorizontalDragUpdate: (details) =>
                historyDrag += details.delta.dx,
            onHorizontalDragEnd: (details) {
              if (historyDrag > 48 || (details.primaryVelocity ?? 0) > 150) {
                openHistory();
              }
            },
          ),
        ),
      ],
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
      PilotControl(
        className: 'chat-rename-cancel',
        kind: 'text-button',
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
      PilotControl(
        className: 'chat-rename-save',
        kind: 'text-button',
        child: TextButton(
          onPressed: () => Navigator.pop(context, editor.text.trim()),
          child: const Text('保存'),
        ),
      ),
    ],
  );
}
