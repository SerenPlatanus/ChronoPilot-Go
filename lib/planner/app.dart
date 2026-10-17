import '../ui/controls.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'item.dart';
import 'semester_filter.dart';
import '../ui/course_color.dart';
import '../ui/planner_calendar.dart';
import 'repository.dart';
import 'school_sync.dart';
import 'agent_tools.dart';
import 'chat_controller.dart';
import 'mcp_server.dart';
import 'editor.dart';
import 'chat_page.dart';
import 'schedule_audit.dart';
import 'credentials.dart';
import 'settings_page.dart';
import '../ui/styles.dart';
import '../ui/components.dart';
import '../ui/countdown.dart';
import '../ui/backdrop_settings.dart';

class PlannerApp extends StatefulWidget {
  final PlannerRepository? repository;
  final bool restoreAccount;
  const PlannerApp({super.key, this.repository, this.restoreAccount = false});
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
  int tab = 0, contentTab = 0;
  bool settingsVisited = false;
  String category = '', subject = '';
  String term = academicTerm(DateTime.now());
  bool showCompleted = false, refreshing = false, filtersOpen = false;
  DateTime day = DateTime.now();
  bool syncHintDismissed = false;
  Timer? _clockTick;
  void _startClock() {
    _clockTick?.cancel();
    _clockTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        unawaited(refresh());
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    if (widget.repository != null) _attach(widget.repository!);
    if (widget.repository == null || widget.restoreAccount) unawaited(load());
  }

  void _attach(PlannerRepository r) {
    repo = r;
    sync = SchoolSync(r, username, password);
    final accountSync = sync!;
    chat = PlannerChat(r, refreshContext: () => accountSync.refresh());
    mcp = PlannerMcpServer(
      PlannerTools(r),
      refreshContext: () => accountSync.refresh(),
    );
    r.addListener(changed);
  }

  Future<void> load() async {
    try {
      final credentials = await Future.wait([
        secureStore.read(key: 'planner_username'),
        secureStore.read(key: 'planner_password'),
        secureStore.read(key: 'planner_deepseek_key'),
        secureStore.read(key: 'planner_model'),
      ]);
      if (!mounted) return;
      username = credentials[0] ?? '';
      password = credentials[1] ?? '';
      apiKey = credentials[2] ?? '';
      model = credentials[3] ?? 'deepseek-flash';
      final scope = username.isEmpty ? 'local' : username;
      final r = repo?.scope == scope
          ? repo!
          : await PlannerRepository.open(scope);
      if (!mounted) {
        if (!identical(r, repo)) r.dispose();
        return;
      }
      sync?.dispose();
      chat?.dispose();
      await mcp?.stop();
      mcp?.dispose();
      if (!mounted) {
        if (!identical(r, repo)) r.dispose();
        return;
      }
      repo?.removeListener(changed);
      if (!identical(r, repo)) repo?.dispose();
      _attach(r);
      setState(() {});
      await PlannerRepository.rememberAccount(scope);
      // Cached content is already mounted; requests start after layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(refresh());
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } catch (_) {
      if (mounted) setState(() => failure = '无法读取本地数据。为避免覆盖原数据，初始化已停止。');
    }
  }

  void changed() {
    final status = repo?.syncStatus.values.whereType<Map>().toList() ?? [];
    if (status.isNotEmpty && status.every((entry) => entry['error'] == null)) {
      syncHintDismissed = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> refresh({bool force = false}) async {
    if (force && !syncHintDismissed) setState(() => syncHintDismissed = true);
    if (sync == null || (!force && !sync!.shouldRefresh)) return;
    if (refreshing) {
      await sync?.refresh(force: force, interactive: force);
      return;
    }
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
      _startClock();
      unawaited(refresh());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _clockTick?.cancel();
      chat?.cancel();
      unawaited(mcp?.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTick?.cancel();
    sync?.dispose();
    chat?.dispose();
    mcp?.dispose();
    repo?.removeListener(changed);
    repo?.dispose();
    super.dispose();
  }

  void selectTab(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (tab == 0 && value != tab) syncHintDismissed = true;
      tab = value;
      if (value == 4) {
        settingsVisited = true;
      } else {
        contentTab = value;
      }
    });
  }

  Future<void> settingsSaved(bool accountChanged) async {
    if (!mounted) return;
    if (accountChanged == true) {
      sync?.dispose();
      sync = null;
      chat?.dispose();
      chat = null;
      await mcp?.stop();
      if (!mounted) return;
      mcp?.dispose();
      mcp = null;
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (repo == null) {
      return Scaffold(
        body: Center(
          child: failure == null
              ? const Text('正在读取本地数据')
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(failure!),
                ),
        ),
      );
    }
    final r = repo!, v = PilotVisuals.of(context), now = DateTime.now();
    final warnings = scheduleWarnings(r.items, now);
    final termItems = r.items.where((e) => inTerm(e, term)).toList();
    final terms = {
      academicTerm(now),
      ...r.items.map(itemTerm).whereType<String>(),
    }.toList()..sort((a, b) => b.compareTo(a));
    final subjects =
        termItems
            .map((e) => e.subject)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (!subjects.contains(subject)) subject = '';
    final filtered = termItems.where(
      (e) =>
          (category.isEmpty || category == e.categoryId) &&
          (subject.isEmpty || subject == e.subject),
    );
    final items = filtered
        .where(
          (e) => contentTab == 0
              ? e.upcoming(now)
              : contentTab == 1
              ? onDay([e], DateTime(day.year, day.month, day.day)).isNotEmpty
              : e.categoryId != 'course' && (showCompleted || !e.completed),
        )
        .toList();
    final upcoming = items.where((e) => e.countdownTarget(now) != null).toList()
      ..sort(
        (a, b) => a.countdownTarget(now)!.compareTo(b.countdownTarget(now)!),
      );

    if (contentTab == 0) {
      final untimed = items
          .where((e) => e.countdownTarget(now) == null)
          .toList();
      items
        ..clear()
        ..addAll([...upcoming, ...untimed]);
    }
    final errors = r.syncStatus.values
        .whereType<Map>()
        .where((e) => e['error'] != null)
        .length;
    final pagePadding = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 20.0;
    return Scaffold(
      appBar: tab >= 3
          ? null
          : AppBar(
              title: Text(['接下来', '课表与日程', '事项', 'Agent'][contentTab]),
              actions: [
                if (contentTab != 3)
                  PilotControl(
                    className: 'upcoming-filter',
                    kind: 'icon-button',
                    child: IconButton(
                      tooltip: '筛选事项',
                      icon: Icon(
                        filtersOpen
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                      ),
                      onPressed: () =>
                          setState(() => filtersOpen = !filtersOpen),
                    ),
                  ),
                PilotControl(
                  className: 'school-refresh',
                  kind: 'icon-button',
                  child: IconButton(
                    onPressed: refreshing ? null : () => refresh(force: true),
                    icon: Icon(refreshing ? Icons.hourglass_top : Icons.sync),
                    tooltip: refreshing ? '正在更新学校数据' : '更新学校数据',
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: IndexedStack(
        index: tab == 4 ? 1 : 0,
        children: [
          TickerMode(
            enabled: tab != 4,
            child: ContentFrame(
              child: contentTab == 3
                  ? PlannerChatPage(
                      key: ValueKey(r.scope),
                      chat: chat!,
                      apiKey: apiKey,
                      model: model,
                      beforeSend: () => refresh(),
                    )
                  : RefreshIndicator(
                      onRefresh: () => refresh(force: true),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: pagePadding,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (contentTab == 0)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 16,
                                        bottom: 14,
                                      ),
                                      child: Text(
                                        '即将开始',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                  if (contentTab == 0)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child:
                                          StyleScope.maybeOf(
                                                context,
                                              )?.backdrop.kind ==
                                              BackdropKind.wallpaper
                                          ? Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: v.decoration(
                                                'overview',
                                              ),
                                              child: DailyOccupancyTrace(
                                                items: termItems,
                                              ),
                                            )
                                          : DailyOccupancyTrace(
                                              items: termItems,
                                            ),
                                    ),
                                  if (contentTab != 0)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (final t in [
                                            ...terms,
                                            if (r.items.any(
                                              (e) =>
                                                  e.school &&
                                                  itemTerm(e) == null,
                                            ))
                                              'undated',
                                            'all',
                                          ])
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: PilotControl(
                                                className: 'semester-filter',
                                                kind: 'filter-button',
                                                child: ChoiceChip(
                                                  label: Text(termLabel(t)),
                                                  selected: term == t,
                                                  onSelected: (_) => setState(() {
                                                    term = t;
                                                    subject = '';
                                                    final dates =
                                                        r.items
                                                            .where(
                                                              (e) =>
                                                                  inTerm(
                                                                    e,
                                                                    t,
                                                                  ) &&
                                                                  e.categoryId ==
                                                                      'course' &&
                                                                  e.start !=
                                                                      null,
                                                            )
                                                            .map(
                                                              (e) => e.start!,
                                                            )
                                                            .toList()
                                                          ..sort();
                                                    if (t !=
                                                            academicTerm(now) &&
                                                        dates.isNotEmpty) {
                                                      day = dates.first;
                                                    } else if (t ==
                                                        academicTerm(now)) {
                                                      day = now;
                                                    }
                                                  }),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (contentTab == 1)
                                    PlannerCalendar(
                                      day: day,
                                      items: filtered.toList(),
                                      onChanged: (date) =>
                                          setState(() => day = date),
                                      onTimetable: () =>
                                          Navigator.of(context).push(
                                            PilotPageRoute<void>(
                                              builder: (_) => LargeTimetable(
                                                items: filtered.toList(),
                                                initialDay: day,
                                                onTap: (item) =>
                                                    editItem(context, r, item),
                                              ),
                                            ),
                                          ),
                                    ),
                                  if (warnings.isNotEmpty)
                                    NoticePanel(
                                      title: '有 ${warnings.length} 处安排需要调整',
                                      subtitle: warnings.first,
                                      icon: Icons.warning_amber,
                                      onTap: () => showDialog<void>(
                                        animationStyle:
                                            AnimationStyle.noAnimation,
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('日程变化'),
                                          content: SingleChildScrollView(
                                            child: Text(warnings.join('\n')),
                                          ),
                                          actions: [
                                            PilotControl(
                                              className: 'sync-warning-close',
                                              kind: 'text-button',
                                              child: TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c),
                                                child: const Text('知道了'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (contentTab == 0 &&
                                      errors > 0 &&
                                      !syncHintDismissed)
                                    RefreshHint(
                                      onRefresh: () => refresh(force: true),
                                      onDismiss: () => setState(
                                        () => syncHintDismissed = true,
                                      ),
                                    ),
                                  if (filtersOpen)
                                    ExpansionTile(
                                      initiallyExpanded: true,
                                      tilePadding: EdgeInsets.zero,
                                      title: const Text('类别与学科筛选'),
                                      children: [
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              _categoryChip('', '全部类别', v),
                                              for (final c
                                                  in ItemCategory.values)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 8,
                                                      ),
                                                  child: _categoryChip(
                                                    c.id,
                                                    c.label,
                                                    v,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child:
                                                  DropdownButtonFormField<
                                                    String
                                                  >(
                                                    key: ValueKey(subject),
                                                    initialValue: subject,
                                                    isExpanded: true,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: '学科筛选',
                                                          contentPadding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 14,
                                                                vertical: 12,
                                                              ),
                                                        ),
                                                    items: [
                                                      const DropdownMenuItem(
                                                        value: '',
                                                        child: Text('全部学科'),
                                                      ),
                                                      ...subjects.map(
                                                        (s) => DropdownMenuItem(
                                                          value: s,
                                                          child: Text(
                                                            s,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    onChanged: (value) =>
                                                        setState(
                                                          () =>
                                                              subject = value!,
                                                        ),
                                                  ),
                                            ),
                                            if (contentTab == 2)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 8,
                                                ),
                                                child: PilotControl(
                                                  className: 'completed-filter',
                                                  kind: 'filter-button',
                                                  child: FilterChip(
                                                    label: const Text('含已完成'),
                                                    selected: showCompleted,
                                                    onSelected: (value) =>
                                                        setState(
                                                          () => showCompleted =
                                                              value,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),

                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 14,
                                      bottom: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            contentTab == 1
                                                ? '${day.month}月${day.day}日 · 星期${'一二三四五六日'[day.weekday - 1]}'
                                                : contentTab == 2
                                                ? '待办事项'
                                                : '后续安排',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                        Text(
                                          '${items.length} 项',
                                          style: instrumentText(
                                            color:
                                                StyleScope.maybeOf(
                                                      context,
                                                    )?.backdrop.kind ==
                                                    BackdropKind.wallpaper
                                                ? v.ink
                                                : v.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (items.isEmpty)
                            SliverPadding(
                              padding: EdgeInsets.symmetric(
                                horizontal: pagePadding,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: EmptySignal(
                                  title: contentTab == 1
                                      ? '当天没有日程'
                                      : '暂时没有符合条件的事项',
                                  description: contentTab == 1
                                      ? '换一天查看课表，或为自己添加一段安排。'
                                      : '添加任务，或调整类别与学科筛选。学校账号连接后可以同步课程和作业。',
                                  icon: contentTab == 1
                                      ? Icons.calendar_today_outlined
                                      : Icons.inventory_2_outlined,
                                  action: PilotControl(
                                    className: 'empty-add',
                                    kind: 'text-button',
                                    child: TextButton.icon(
                                      onPressed: () => editItem(context, r),
                                      icon: const Icon(Icons.add),
                                      label: const Text('添加事项'),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.symmetric(
                                horizontal: pagePadding,
                              ),
                              sliver: SliverList.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ItemTile(
                                    item: items[index],
                                    repo: r,
                                    timeline: contentTab == 1,
                                  ),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 96)),
                        ],
                      ),
                    ),
            ),
          ),
          if (settingsVisited)
            TickerMode(
              enabled: tab == 4,
              child: PlannerSettings(
                key: ObjectKey(r),
                repo: r,
                mcp: mcp!,
                username: username,
                password: password,
                apiKey: apiKey,
                model: model,
                onSaved: settingsSaved,
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: tab >= 3
          ? null
          : PilotControl(
              className: 'item-add',
              kind: 'add-button',
              child: FloatingActionButton(
                onPressed: () => editItem(context, r),
                tooltip: '添加事项',
                child: const Icon(Icons.add),
              ),
            ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : PilotNavigation(selected: tab, onChanged: selectTab),
    );
  }

  Widget _categoryChip(String id, String label, PilotVisuals v) => PilotControl(
    className: 'category-filter',
    kind: 'filter-button',
    child: ChoiceChip(
      label: Text(label),
      selected: category == id,
      labelStyle: v.alpha
          ? TextStyle(
              color: category == id
                  ? (v.dark ? v.screen : Colors.white)
                  : v.ink,
              fontSize: 13,
            )
          : null,
      selectedColor: v.alpha ? (v.dark ? v.accent : v.ink) : null,
      onSelected: (_) => setState(() => category = id),
    ),
  );
}

class ItemTile extends StatelessWidget {
  final Item item;
  final PlannerRepository repo;
  final bool timeline;
  const ItemTile({
    super.key,
    required this.item,
    required this.repo,
    this.timeline = false,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context), color = courseColor(item);
    return Material(
      color: v.decoration('item-card').color,
      shape: v.shape('item-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => editItem(context, repo, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(
                          color: v.ink.withValues(alpha: .45),
                          width: .7,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: item.completed ? v.muted : v.ink,
                        decoration: item.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (item.categoryId != 'course')
                    Checkbox(
                      semanticLabel: '完成 ${item.title}',
                      value: item.completed,
                      onChanged: (value) async {
                        try {
                          await repo.saveItem(item.patch({'completed': value}));
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('事项已更新，请重试')),
                            );
                          }
                        }
                      },
                    )
                  else
                    Icon(Icons.chevron_right, color: v.muted, size: 20),
                ],
              ),
              const SizedBox(height: 2),
              if (item.timed)
                _line(
                  v,
                  Icons.schedule,
                  '${localTime(item.start!)} – ${localTime(item.end!).split(' ').last}',
                ),
              if (item.deadline != null)
                _line(
                  v,
                  Icons.flag_outlined,
                  '截止 ${localTime(item.deadline!)}',
                ),
              if (item.location.isNotEmpty)
                _line(v, Icons.place_outlined, item.location),
              if (item.subject.isNotEmpty && item.subject != item.title)
                _line(v, Icons.book_outlined, item.subject),
              if (item.category.workload || item.categoryId == 'exam')
                _line(
                  v,
                  Icons.timelapse,
                  item.estimatedMinutes == null
                      ? '预计用时待填写'
                      : '预计 ${item.estimatedMinutes} 分钟',
                ),
              if (!timeline && item.countdownTarget(DateTime.now()) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: CountdownView(item: item),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(PilotVisuals v, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(icon, size: 16, color: v.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: v.muted, fontSize: 14, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
