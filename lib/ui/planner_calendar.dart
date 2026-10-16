import 'dart:async';
import 'package:flutter/material.dart';
import '../planner/item.dart';
import 'course_color.dart';
import 'styles.dart';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
List<Item> onDay(Iterable<Item> items, DateTime date) {
  final end = DateTime(date.year, date.month, date.day + 1);
  return items
      .where(
        (e) => e.timed
            ? e.start!.isBefore(end) && e.end!.isAfter(date)
            : e.deadline != null && sameDay(e.deadline!, date),
      )
      .toList();
}

class PlannerCalendar extends StatefulWidget {
  final DateTime day;
  final List<Item> items;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onTimetable;
  const PlannerCalendar({
    super.key,
    required this.day,
    required this.items,
    required this.onChanged,
    required this.onTimetable,
  });
  @override
  State<PlannerCalendar> createState() => _PlannerCalendarState();
}

class _PlannerCalendarState extends State<PlannerCalendar> {
  bool month = true;
  @override
  Widget build(BuildContext context) {
    final d = widget.day, v = PilotVisuals.of(context);
    final first = month
        ? DateTime(d.year, d.month, 1)
        : DateTime(d.year, d.month, d.day - d.weekday + 1);
    final begin = month
        ? first.subtract(Duration(days: first.weekday - 1))
        : first;
    final rows = month
        ? ((DateTime(d.year, d.month + 1, 0).day + first.weekday - 1) / 7)
              .ceil()
        : 1;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${d.year} 年 ${d.month} 月',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: v.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () => widget.onChanged(DateTime.now()),
              child: const Text('今天'),
            ),
            IconButton(
              tooltip: month ? '收起月历' : '展开月历',
              onPressed: () => setState(() => month = !month),
              icon: Icon(month ? Icons.expand_less : Icons.calendar_month),
            ),
            IconButton(
              tooltip: '大课表',
              onPressed: widget.onTimetable,
              icon: const Icon(Icons.calendar_view_week),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: month ? '上个月' : '上一周',
              onPressed: () => widget.onChanged(
                month
                    ? DateTime(d.year, d.month - 1, 1)
                    : d.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${d.month}月${d.day}日',
                textAlign: TextAlign.center,
                style: TextStyle(color: v.muted, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: month ? '下个月' : '下一周',
              onPressed: () => widget.onChanged(
                month
                    ? DateTime(d.year, d.month + 1, 1)
                    : d.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: List.generate(
            7,
            (i) => Expanded(
              child: Center(
                child: Text(
                  '一二三四五六日'[i],
                  style: TextStyle(color: v.muted, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
        for (var row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final date = DateTime(
                begin.year,
                begin.month,
                begin.day + row * 7 + col,
              );
              final selected = sameDay(date, d),
                  today = sameDay(date, DateTime.now());
              final colors = onDay(
                widget.items,
                DateTime(date.year, date.month, date.day),
              ).map(courseColor).toSet().take(4).toList();
              return Expanded(
                child: Semantics(
                  selected: selected,
                  label: '${date.month}月${date.day}日',
                  child: InkWell(
                    onTap: () => widget.onChanged(date),
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? v.accent
                                  : today
                                  ? v.line
                                  : Colors.transparent,
                            ),
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                fontSize: 19,
                                color: selected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : date.month != d.month
                                    ? v.muted.withValues(alpha: .5)
                                    : v.ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 5,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: colors
                                  .map(
                                    (c) => Container(
                                      width: 4,
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// Actual dated occurrences; cross-midnight blocks are clipped per day.
class LargeTimetable extends StatefulWidget {
  final List<Item> items;
  final DateTime initialDay;
  final ValueChanged<Item> onTap;
  const LargeTimetable({
    super.key,
    required this.items,
    required this.initialDay,
    required this.onTap,
  });
  @override
  State<LargeTimetable> createState() => _LargeTimetableState();
}

class _LargeTimetableState extends State<LargeTimetable> {
  late DateTime day = widget.initialDay;
  bool zoom = false;
  final scroll = ScrollController(initialScrollOffset: 420);
  Timer? clock;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context),
        monday = DateTime(day.year, day.month, day.day - day.weekday + 1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('大课表'),
        actions: [
          IconButton(
            tooltip: '切换课表缩放',
            onPressed: () => setState(() => zoom = !zoom),
            icon: Icon(zoom ? Icons.zoom_out : Icons.zoom_in),
          ),
          TextButton(
            onPressed: () => setState(() => day = DateTime.now()),
            child: const Text('今天'),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上一周',
                onPressed: () =>
                    setState(() => day = day.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${localTime(monday).split(' ').first} — ${localTime(monday.add(const Duration(days: 6))).split(' ').first}',
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一周',
                onPressed: () =>
                    setState(() => day = day.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = zoom && box.maxWidth < 700 ? 700.0 : box.maxWidth;
                final cw = (width - 42) / 7;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 42),
                            for (var i = 0; i < 7; i++)
                              SizedBox(
                                width: cw,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    '${'一二三四五六日'[i]} ${monday.add(Duration(days: i)).day}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: v.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scroll,
                            child: SizedBox(
                              height: 1440,
                              width: width,
                              child: Stack(
                                children: [
                                  for (var hour = 0; hour <= 24; hour++)
                                    Positioned(
                                      top: hour * 60.0,
                                      left: 0,
                                      right: 0,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 42,
                                            child: Text(
                                              '$hour:00',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: v.muted,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Divider(
                                              height: 1,
                                              color: v.line,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  for (var i = 0; i < 8; i++)
                                    Positioned(
                                      left: 42 + cw * i,
                                      top: 0,
                                      bottom: 0,
                                      child: VerticalDivider(
                                        width: 1,
                                        color: v.line,
                                      ),
                                    ),
                                  if (DateTime.now().isAfter(monday) &&
                                      DateTime.now().isBefore(
                                        monday.add(const Duration(days: 7)),
                                      ))
                                    Positioned(
                                      left:
                                          42 +
                                          cw * (DateTime.now().weekday - 1),
                                      width: cw,
                                      top:
                                          DateTime.now().hour * 60.0 +
                                          DateTime.now().minute,
                                      child: Container(
                                        height: 1,
                                        color: v.accent,
                                      ),
                                    ),
                                  for (var i = 0; i < 7; i++)
                                    ..._blocks(
                                      monday.add(Duration(days: i)),
                                      i,
                                      cw,
                                      v,
                                    ),
                                ],
                              ),
                            ),
                          ),
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
    );
  }

  List<Widget> _blocks(DateTime date, int column, double cw, PilotVisuals v) {
    final items = onDay(widget.items, date).where((e) => e.timed).toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    final laneOf = <String, int>{}, countOf = <String, int>{};
    var cluster = <Item>[];
    var ends = <DateTime>[];
    DateTime? clusterEnd;
    void finish() {
      for (final item in cluster) {
        countOf[item.id] = ends.length;
      }
      cluster = [];
      ends = [];
      clusterEnd = null;
    }

    for (final item in items) {
      if (clusterEnd != null && !item.start!.isBefore(clusterEnd!)) finish();
      var lane = ends.indexWhere((end) => !end.isAfter(item.start!));
      if (lane < 0) {
        lane = ends.length;
        ends.add(item.end!);
      } else {
        ends[lane] = item.end!;
      }
      laneOf[item.id] = lane;
      cluster.add(item);
      if (clusterEnd == null || item.end!.isAfter(clusterEnd!)) {
        clusterEnd = item.end;
      }
    }
    finish();
    return items.map((item) {
      final start = item.start!.difference(date).inMinutes.clamp(0, 1440),
          end = item.end!.difference(date).inMinutes.clamp(0, 1440);
      if (end <= start) return const SizedBox.shrink();
      final lanes = countOf[item.id]!, lane = laneOf[item.id]!;
      final color = courseColor(item), height = (end - start).toDouble() - 2;
      return Positioned(
        left: 42 + cw * column + (cw / lanes) * lane + 1,
        top: start.toDouble() + 1,
        width: (cw / lanes - 2).clamp(1, cw),
        height: height,
        child: Material(
          color: Color.alphaBlend(
            color.withValues(alpha: v.dark ? .28 : .24),
            v.surface,
          ),
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onTap(item),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 2)),
              ),
              padding: const EdgeInsets.all(3),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: v.ink,
                        ),
                      ),
                      if (height > 75) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: v.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}
