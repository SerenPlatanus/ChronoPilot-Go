import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'item.dart';
import 'repository.dart';
import 'school_sync.dart';
import 'agent_tools.dart';
import 'chat_controller.dart';
import 'mcp_server.dart';
import 'editor.dart';
import 'chat_page.dart';
import 'features.dart';

const secureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

class PlannerApp extends StatefulWidget {
  final PlannerRepository? repository;
  const PlannerApp({super.key, this.repository});
  @override
  State<PlannerApp> createState() => _PlannerAppState();
}

class _PlannerAppState extends State<PlannerApp> with WidgetsBindingObserver {
  PlannerRepository? repo;
  SchoolSync? sync;
  PlannerChat? chat;
  PlannerMcpServer? mcp;
  String username = '', password = '', apiKey = '', model = 'deepseek-flash';
  String? failure;
  int tab = 0;
  String category = '', subject = '';
  bool showCompleted = false, refreshing = false;
  DateTime day = DateTime.now();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.repository != null) {
      repo = widget.repository;
      sync = SchoolSync(repo!, '', '');
      chat = PlannerChat(repo!);
      mcp = PlannerMcpServer(PlannerTools(repo!));
      repo!.addListener(changed);
    } else {
      unawaited(load());
    }
  }

  Future<void> load() async {
    try {
      username = await secureStore.read(key: 'planner_username') ?? '';
      password = await secureStore.read(key: 'planner_password') ?? '';
      apiKey = await secureStore.read(key: 'planner_deepseek_key') ?? '';
      model = await secureStore.read(key: 'planner_model') ?? 'deepseek-flash';
      final r = await PlannerRepository.open(
        username.isEmpty ? 'local' : username,
      );
      if (!mounted) {
        r.dispose();
        return;
      }
      repo = r;
      sync = SchoolSync(r, username, password);
      chat = PlannerChat(r);
      mcp = PlannerMcpServer(PlannerTools(r));
      r.addListener(changed);
      setState(() {});
      unawaited(refresh());
    } catch (_) {
      if (mounted) setState(() => failure = '无法读取本地数据。为避免覆盖原数据，初始化已停止。');
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> refresh({bool force = false}) async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      await sync?.refresh(force: force, interactive: force);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(mcp?.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sync?.dispose();
    chat?.dispose();
    unawaited(mcp?.stop());
    repo?.removeListener(changed);
    repo?.dispose();
    super.dispose();
  }

  Future<void> settings() async {
    final accountChanged = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlannerSettings(
          repo: repo!,
          mcp: mcp!,
          username: username,
          password: password,
          apiKey: apiKey,
          model: model,
        ),
      ),
    );
    if (!mounted) return;
    if (accountChanged == true) {
      sync?.dispose();
      chat?.dispose();
      await mcp?.stop();
      repo?.removeListener(changed);
      repo?.dispose();
      setState(() {
        repo = null;
        category = '';
        subject = '';
      });
      await load();
    } else {
      apiKey = await secureStore.read(key: 'planner_deepseek_key') ?? '';
      model = await secureStore.read(key: 'planner_model') ?? 'deepseek-flash';
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (repo == null) {
      return Scaffold(
        body: Center(
          child: failure == null
              ? const CircularProgressIndicator()
              : Text(failure!),
        ),
      );
    }
    final r = repo!;
    final now = DateTime.now();
    final subjects =
        r.items
            .map((e) => e.subject)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (!subjects.contains(subject)) subject = '';
    final filtered = r.items.where(
      (e) =>
          (category.isEmpty || category == e.categoryId) &&
          (subject.isEmpty || subject == e.subject),
    );
    final items = filtered
        .where(
          (e) => tab == 0
              ? e.upcoming(now)
              : tab == 1
              ? e.timed &&
                    e.start!.isBefore(
                      DateTime(day.year, day.month, day.day + 1),
                    ) &&
                    e.end!.isAfter(DateTime(day.year, day.month, day.day))
              : e.categoryId != 'course' && (showCompleted || !e.completed),
        )
        .toList();
    final errors = r.syncStatus.values
        .whereType<Map>()
        .where((e) => e['error'] != null)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(['接下来', '课表与日程', '事项', 'Agent'][tab]),
        actions: [
          if (refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: () => refresh(force: true),
              icon: const Icon(Icons.sync),
              tooltip: '更新学校数据',
            ),
          IconButton(
            onPressed: settings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
          ),
        ],
      ),
      body: tab == 3
          ? PlannerChatPage(
              key: ValueKey(r.scope),
              chat: chat!,
              apiKey: apiKey,
              model: model,
              beforeSend: () => refresh(),
            )
          : Column(
              children: [
                if (username.isEmpty)
                  ListTile(
                    dense: true,
                    title: const Text('当前为本地模式，可在设置中连接本科生账号'),
                    onTap: settings,
                  ),
                if (errors > 0)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('部分学校数据未更新，正在使用本地记录'),
                    subtitle: const Text('在设置查看数据来源和更新时间'),
                    onTap: settings,
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('全部类别'),
                        selected: category.isEmpty,
                        onSelected: (_) => setState(() => category = ''),
                      ),
                      for (final c in ItemCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(c.label),
                            selected: category == c.id,
                            onSelected: (_) => setState(() => category = c.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: subject,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('全部学科'),
                            ),
                            ...subjects.map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => subject = v!),
                        ),
                      ),
                      if (tab == 2)
                        FilterChip(
                          label: const Text('含已完成'),
                          selected: showCompleted,
                          onSelected: (v) => setState(() => showCompleted = v),
                        ),
                    ],
                  ),
                ),
                if (tab == 1)
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => setState(
                              () => day = day.subtract(const Duration(days: 7)),
                            ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => day = DateTime.now()),
                            child: Text('${day.year}年${day.month}月 · 回到今天'),
                          ),
                          IconButton(
                            onPressed: () => setState(
                              () => day = day.add(const Duration(days: 7)),
                            ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      Row(
                        children: List.generate(7, (i) {
                          final d = DateTime(
                            day.year,
                            day.month,
                            day.day - day.weekday + 1 + i,
                          );
                          return Expanded(
                            child: InkWell(
                              onTap: () => setState(() => day = d),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                color: d.day == day.day
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : null,
                                child: Column(
                                  children: [
                                    Text('一二三四五六日'[i]),
                                    Text('${d.day}'),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => refresh(force: true),
                    child: items.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(40),
                                child: Text('暂无符合条件的事项。添加任务，或连接学校账号后同步。'),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            padding: const EdgeInsets.only(bottom: 88),
                            itemBuilder: (context, index) =>
                                ItemTile(item: items[index], repo: r),
                          ),
                  ),
                ),
              ],
            ),
      floatingActionButton: tab == 3
          ? null
          : FloatingActionButton(
              onPressed: () => editItem(context, r),
              tooltip: '添加事项',
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.schedule), label: '接下来'),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week),
            label: '课表',
          ),
          NavigationDestination(icon: Icon(Icons.checklist), label: '事项'),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'Agent',
          ),
        ],
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  final Item item;
  final PlannerRepository repo;
  const ItemTile({super.key, required this.item, required this.repo});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    child: ListTile(
      onTap: () => editItem(context, repo, item),
      title: Text(
        item.title,
        style: TextStyle(
          decoration: item.completed ? TextDecoration.lineThrough : null,
        ),
      ),
      leading: Text(item.category.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.subject.isNotEmpty && item.subject != item.title)
            Text(item.subject),
          if (item.timed)
            Text('${localTime(item.start!)} – ${localTime(item.end!)}'),
          if (item.deadline != null) Text('截止 ${localTime(item.deadline!)}'),
          if (item.location.isNotEmpty) Text(item.location),
          if (item.category.workload)
            Text(
              item.estimatedMinutes == null
                  ? '预计用时待填写'
                  : '预计 ${item.estimatedMinutes} 分钟',
            ),
          CountdownView(item: item),
        ],
      ),
      trailing: item.categoryId == 'course'
          ? null
          : Checkbox(
              value: item.completed,
              onChanged: (v) async {
                try {
                  await repo.saveItem(item.patch({'completed': v}));
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('事项已更新，请重试')));
                  }
                }
              },
            ),
    ),
  );
}

class CountdownView extends StatefulWidget {
  final Item item;
  const CountdownView({super.key, required this.item});
  @override
  State<CountdownView> createState() => _CountdownViewState();
}

class _CountdownViewState extends State<CountdownView>
    with WidgetsBindingObserver {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  void start() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      start();
    } else {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          countdown(item, now),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        if (item.timed && !now.isBefore(item.start!) && now.isBefore(item.end!))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(
              value:
                  now.difference(item.start!).inMilliseconds /
                  item.end!.difference(item.start!).inMilliseconds,
            ),
          ),
      ],
    );
  }
}

class PlannerSettings extends StatefulWidget {
  final PlannerRepository repo;
  final PlannerMcpServer mcp;
  final String username, password, apiKey, model;
  const PlannerSettings({
    super.key,
    required this.repo,
    required this.mcp,
    required this.username,
    required this.password,
    required this.apiKey,
    required this.model,
  });
  @override
  State<PlannerSettings> createState() => _PlannerSettingsState();
}

class _PlannerSettingsState extends State<PlannerSettings> {
  late final user = TextEditingController(text: widget.username),
      pass = TextEditingController(text: widget.password),
      keyField = TextEditingController(text: widget.apiKey),
      modelField = TextEditingController(text: widget.model),
      preferences = TextEditingController(text: widget.repo.preferences);
  String? error;
  bool saving = false;
  @override
  void dispose() {
    for (final c in [user, pass, keyField, modelField, preferences]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      if (user.text.trim().isNotEmpty && !user.text.trim().startsWith('3')) {
        throw const FormatException('当前仅支持本科生账号');
      }
      if (user.text.trim().isNotEmpty && pass.text.isEmpty) {
        throw const FormatException('请填写统一认证密码');
      }
      for (final e in {
        'planner_username': user.text.trim(),
        'planner_password': pass.text,
        'planner_deepseek_key': keyField.text.trim(),
        'planner_model': modelField.text.trim().isEmpty
            ? 'deepseek-flash'
            : modelField.text.trim(),
      }.entries) {
        await secureStore.write(key: e.key, value: e.value);
      }
      await widget.repo.setPreferences(preferences.text);
      if (mounted) {
        Navigator.pop(
          context,
          user.text.trim() != widget.username || pass.text != widget.password,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message.toString() : '保存设置失败',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '本科生账号',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        TextField(
          controller: user,
          decoration: const InputDecoration(labelText: '学号（留空使用本地模式）'),
        ),
        TextField(
          controller: pass,
          obscureText: true,
          decoration: const InputDecoration(labelText: '统一认证密码'),
        ),
        const SizedBox(height: 24),
        const Text(
          'DeepSeek',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Agent 接入暂未启用。可先保存模型配置；启用后发送对话会将日程、任务、备注和偏好发送至 DeepSeek。API Key 保存在本机安全存储中。',
        ),
        TextField(
          controller: keyField,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '自己的 API Key'),
        ),
        TextField(
          controller: modelField,
          decoration: const InputDecoration(labelText: '模型 ID'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: preferences,
          maxLength: 6000,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '长期偏好（仅你明确填写的内容）',
            hintText: '例如：23点前休息，下午适合集中学习',
          ),
        ),
        TextButton(
          onPressed: () => preferences.clear(),
          child: const Text('清空长期偏好（保存后生效）'),
        ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('保存设置'),
        ),
        const Divider(height: 40),
        const Text(
          '学校数据状态',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (widget.repo.syncStatus.isEmpty) const Text('尚未同步'),
        for (final e in widget.repo.syncStatus.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.key),
            subtitle: Text(
              '最近成功：${e.value['updatedAt'] ?? '无'}\n${e.value['error'] ?? '已更新'}',
            ),
          ),
        const Divider(height: 40),
        const Text(
          'MCP 服务器',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text('仅在前台运行，离开 App 后停止。授权客户端可读取日程并提交方案；写入仍需你在 App 中确认。'),
        FilledButton.tonal(
          onPressed: !mcpExecutionEnabled
              ? null
              : () async {
                  try {
                    if (widget.mcp.running) {
                      await widget.mcp.stop();
                    } else {
                      await widget.mcp.start();
                    }
                    if (mounted) setState(() {});
                  } catch (_) {
                    if (mounted) setState(() => error = 'MCP 启动失败，端口可能已占用');
                  }
                },
          child: Text(
            !mcpExecutionEnabled
                ? 'MCP 接入开发已暂停'
                : widget.mcp.running
                ? '停止 MCP'
                : '启动 MCP',
          ),
        ),
        if (widget.mcp.running) ...[
          SelectableText('http://127.0.0.1:${widget.mcp.port}/mcp'),
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: widget.mcp.token!)),
            child: const Text('复制本次 Bearer 令牌'),
          ),
        ],
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: const JsonEncoder.withIndent(
                  '  ',
                ).convert(PlannerTools(widget.repo).context()),
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('日程 JSON 已复制')));
            }
          },
          child: const Text('复制当前日程 JSON'),
        ),
      ],
    ),
  );
}
