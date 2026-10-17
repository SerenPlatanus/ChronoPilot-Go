import '../ui/controls.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/styles.dart';
import '../ui/components.dart';
import 'repository.dart';
import 'mcp_server.dart';
import 'agent_tools.dart';
import 'features.dart';
import 'credentials.dart';
import 'item.dart';
import '../ui/style_picker.dart';

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
  void initState() {
    super.initState();
    widget.mcp.addListener(_serverChanged);
  }

  void _serverChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.mcp.removeListener(_serverChanged);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error!)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String sourceName(String key) => key.startsWith('courses:')
      ? '课表 · ${key.substring(8).replaceAll(':', ' / ')}'
      : switch (key) {
          'courses' => '教务网连接',
          'homework' => '学校作业',
          'exams' => '考试',
          _ => key,
        };
  String syncTime(dynamic value) {
    final t = DateTime.tryParse(value?.toString() ?? '');
    return t == null ? '尚未成功同步' : localTime(t);
  }

  Future<void> copyJson() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent(
            '  ',
          ).convert(PlannerTools(widget.repo).context()),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日程 JSON 已复制')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法导出日程，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ContentFrame(
        maxWidth: 760,
        child: ListView(
          key: const ValueKey('planner-settings-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const SectionHeading(title: '外观主题', code: '01 / APPEARANCE'),
            const StylePicker(),
            const SectionHeading(
              title: '本科生账号',
              code: '02 / CAMPUS CONNECTION',
              description: '留空也能使用手动事项。连接后同步课程、考试和学校作业。',
            ),
            SurfacePanel(
              child: Column(
                children: [
                  TextField(
                    controller: user,
                    decoration: const InputDecoration(
                      labelText: '学号（留空使用本地模式）',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '统一认证密码',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeading(
              title: 'DeepSeek',
              code: '03 / INTELLIGENCE',
              description: '发送对话时将日程、任务、备注和偏好发送至 DeepSeek。账号密码不进入模型上下文。',
            ),
            SurfacePanel(
              child: Column(
                children: [
                  TextField(
                    controller: keyField,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '自己的 API Key',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: modelField,
                    decoration: const InputDecoration(
                      labelText: '模型 ID',
                      prefixIcon: Icon(Icons.memory_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SignalBadge(
                    label: 'API Key 保存在本机安全存储',
                    icon: Icons.verified_user_outlined,
                  ),
                ],
              ),
            ),
            const SectionHeading(
              title: '长期偏好',
              code: '04 / YOUR RHYTHM',
              description: '只记住你明确填写的习惯；可以随时查看或清空。',
            ),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  PilotControl(
                    className: 'preferences-clear',
                    kind: 'text-button',
                    child: TextButton.icon(
                      onPressed: () => preferences.clear(),
                      icon: const Icon(Icons.clear_all),
                      label: const Text('清空长期偏好（保存后生效）'),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeading(title: '学校数据状态', code: '05 / DATA SIGNAL'),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.repo.syncStatus.isEmpty)
                    const SignalBadge(
                      label: '尚未同步 · 本地事项仍可使用',
                      icon: Icons.cloud_queue,
                    ),
                  for (final e in widget.repo.syncStatus.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sourceName(e.key),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '最近成功：${syncTime(e.value['updatedAt'])}',
                            style: TextStyle(color: v.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          SignalBadge(
                            label: e.value['error']?.toString() ?? '数据已更新',
                            icon: e.value['error'] == null
                                ? Icons.check_circle_outline
                                : Icons.cloud_off_outlined,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SectionHeading(
              title: 'MCP 服务器',
              code: '06 / LOCAL LINK',
              description: '仅在前台运行，离开 App 后停止。外部客户端只能读取日程并提交待确认方案。',
            ),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SignalBadge(
                    label: widget.mcp.running ? '本机连接 · 运行中' : '本机连接 · 已停止',
                    icon: widget.mcp.running
                        ? Icons.sensors
                        : Icons.sensors_off,
                  ),
                  const SizedBox(height: 16),
                  PilotControl(
                    className: 'mcp-toggle',
                    kind: 'primary-button',
                    child: FilledButton.tonalIcon(
                      onPressed: (!mcpExecutionEnabled || widget.mcp.starting)
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
                                if (mounted) {
                                  setState(() => error = 'MCP 启动失败，端口可能已占用');
                                }
                              }
                            },
                      icon: Icon(
                        widget.mcp.running
                            ? Icons.stop_circle_outlined
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        !mcpExecutionEnabled
                            ? 'MCP 接入开发已暂停'
                            : widget.mcp.starting
                            ? '正在启动…'
                            : widget.mcp.running
                            ? '停止 MCP'
                            : '启动 MCP',
                      ),
                    ),
                  ),
                  if (widget.mcp.running) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      'http://127.0.0.1:${widget.mcp.port}/mcp',
                      style: instrumentText(color: v.muted),
                    ),
                    PilotControl(
                      className: 'mcp-token-copy',
                      kind: 'text-button',
                      child: TextButton.icon(
                        onPressed: () async {
                          final token = widget.mcp.token;
                          if (token == null) return;
                          await Clipboard.setData(ClipboardData(text: token));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('连接令牌已复制')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('复制本次 Bearer 令牌'),
                      ),
                    ),
                  ],
                  const Divider(),
                  PilotControl(
                    className: 'context-export',
                    kind: 'secondary-button',
                    child: OutlinedButton.icon(
                      onPressed: copyJson,
                      icon: const Icon(Icons.data_object),
                      label: const Text('复制当前日程 JSON'),
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
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ContentFrame(
          maxWidth: 760,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: PilotControl(
                className: 'settings-save',
                kind: 'primary-button',
                child: FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.check),
                  label: Text(saving ? '保存中…' : '保存设置'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
