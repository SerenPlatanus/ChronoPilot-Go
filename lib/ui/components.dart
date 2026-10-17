import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';
import '../planner/item.dart';
import 'styles.dart';
import 'controls.dart';
import 'backdrop_settings.dart';

class ContentFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ContentFrame({super.key, required this.child, this.maxWidth = 960});
  @override
  Widget build(BuildContext context) => PaperCanvas(
    child: Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  final String title, code;
  final String? description;
  const SectionHeading({
    super.key,
    required this.title,
    required this.code,
    this.description,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color:
              StyleScope.maybeOf(context)?.backdrop.kind ==
                  BackdropKind.wallpaper
              ? v.ink
              : v.muted,
        ),
      ),
    );
  }
}

class SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const SurfacePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Container(
      padding: padding,
      decoration: v.decoration('card', fill: color),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

enum SignalTone { ready, waiting, error }

class SignalBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool inverse;
  final SignalTone tone;
  const SignalBadge({
    super.key,
    required this.label,
    this.icon = Icons.circle,
    this.inverse = false,
    this.tone = SignalTone.ready,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    final color = inverse
        ? switch (tone) {
            SignalTone.ready => v.signal,
            SignalTone.waiting => v.signalYellow,
            SignalTone.error => v.signalRed,
          }
        : v.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 7 : 16, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: inverse ? color : v.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class NoticePanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const NoticePanel({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.info_outline,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: v.alpha
            ? (v.dark ? v.surface : const Color(0xffe3dccb))
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(v.radius),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, size: 20, color: v.accent),
          title: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, style: TextStyle(fontSize: 12, color: v.muted)),
          trailing: onTap == null
              ? null
              : const Icon(Icons.arrow_outward, size: 18),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
      ),
    );
  }
}

/// One compact, dismissible startup reminder. Visibility is owned by PlannerApp,
/// so tabs and subsequent sync notifications cannot recreate a dismissed hint.
class RefreshHint extends StatelessWidget {
  final VoidCallback onRefresh, onDismiss;
  const RefreshHint({
    super.key,
    required this.onRefresh,
    required this.onDismiss,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    final d = v.decoration('sync-hint', fill: v.namedColor('calendar-surface'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: const ValueKey('startup-sync-hint'),
        direction: DismissDirection.horizontal,
        resizeDuration: null,
        movementDuration: Duration.zero,
        onDismissed: (_) => onDismiss(),
        child: Material(
          color: d.color,
          shape: RoundedRectangleBorder(
            borderRadius: d.borderRadius!,
            side: (d.border! as Border).top,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(Icons.cloud_off_outlined, size: 18, color: v.accent),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onRefresh,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '学校数据未更新，点此刷新',
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: v.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              PilotControl(
                className: 'sync-hint-dismiss',
                kind: 'icon-button',
                child: IconButton(
                  tooltip: '关闭刷新提示',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 16),
                  style: const ButtonStyle(
                    side: WidgetStatePropertyAll(BorderSide.none),
                    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptySignal extends StatelessWidget {
  final String title, description;
  final IconData icon;
  final Widget? action;
  const EmptySignal({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: v.stage,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: v.ink, size: 26),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(color: v.muted, height: 1.7)),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: action),
        ],
      ),
    );
  }
}

/// Glass is limited to bounded control surfaces, never every scrolling card.
class GlassControls extends StatelessWidget {
  final Widget child;
  const GlassControls({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    if (!v.alpha) return child;
    return DecoratedBox(decoration: v.decoration('glass'), child: child);
  }
}

class PilotNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const PilotNavigation({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    final decoration = v.decoration(
      'navigation',
      fill: v.namedColor('navigation-surface'),
      defaultRadius: 0,
    );
    final side = (decoration.border! as Border).top;
    return DecoratedBox(
      key: const ValueKey('navigation-region'),
      decoration: decoration.copyWith(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
        border: Border(top: side),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: side.width),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: selected,
          onTap: onChanged,
          backgroundColor: decoration.color,
          selectedItemColor:
              v.tokens?.controls['navigation']?['foreground'] != null
              ? v.namedColor(v.tokens!.controls['navigation']!['foreground']!)
              : v.dark
              ? v.accent
              : Color.lerp(v.accent, v.ink, .3),
          unselectedItemColor: v.dark ? v.muted : v.ink.withValues(alpha: .75),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.schedule), label: '接下来'),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              label: '课表',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.checklist), label: '事项'),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              label: 'Agent',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}

/// One background beneath the Navigator; page content never repaints the grain.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    final settings =
        StyleScope.maybeOf(context)?.backdrop ?? const BackdropSettings();
    final photo =
        settings.kind == BackdropKind.wallpaper && settings.filePath != null;
    final textured =
        settings.kind == BackdropKind.paper ||
        (settings.kind == BackdropKind.theme && v.alpha);
    final decodeWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(1, 1440);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: v.paper),
                  if (textured)
                    CustomPaint(
                      painter: _PaperGrain(
                        v.paper,
                        v.ink,
                        !MediaQuery.highContrastOf(context),
                        v.dark,
                        v.accent,
                      ),
                    ),
                  if (photo)
                    Image.file(
                      File(settings.filePath!),
                      cacheWidth: decodeWidth,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => ColoredBox(color: v.paper),
                    ),
                  if (photo)
                    ColoredBox(
                      color: v.paper.withValues(alpha: settings.veilOpacity),
                    ),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Retained as the page content boundary; wallpaper lives in AppBackdrop only.
class PaperCanvas extends StatelessWidget {
  final Widget child;
  const PaperCanvas({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

class _PaperGrain extends CustomPainter {
  final Color paper, ink;
  final bool textured, dark;
  final Color accent;
  _PaperGrain(this.paper, this.ink, this.textured, this.dark, this.accent);
  static final dots = () {
    final random = math.Random(70);
    return List.generate(
      1250,
      (_) => Offset(random.nextDouble() * 160, random.nextDouble() * 160),
    );
  }();
  static final fibres = () {
    final random = math.Random(1970);
    return List.generate(48, (_) {
      final x = random.nextDouble() * 160, y = random.nextDouble() * 160;
      return [
        Offset(x, y),
        Offset(
          x + random.nextDouble() * 5 + 1,
          y + random.nextDouble() * 2 - 1,
        ),
      ];
    });
  }();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    if (!textured) return;
    if (dark) {
      final grid = Paint()
        ..color = accent.withValues(alpha: .055)
        ..strokeWidth = .5;
      for (double x = 0; x < size.width; x += 24) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final inkDots = Paint()
      ..color = ink.withValues(alpha: .18)
      ..strokeWidth = .85;
    final light = Paint()
      ..color = Colors.white.withValues(alpha: .54)
      ..strokeWidth = .8;
    final fibre = Paint()
      ..color = ink.withValues(alpha: .075)
      ..strokeWidth = .65;
    for (double y = 0; y < size.height; y += 160) {
      for (double x = 0; x < size.width; x += 160) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPoints(PointMode.points, dots, inkDots);
        canvas.translate(.7, .7);
        canvas.drawPoints(PointMode.points, dots, light);
        for (final line in fibres) {
          canvas.drawLine(line[0], line[1], fibre);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PaperGrain old) =>
      old.paper != paper ||
      old.ink != ink ||
      old.textured != textured ||
      old.dark != dark ||
      old.accent != accent;
}

class DailyOccupancyTrace extends StatelessWidget {
  final List<Item> items;
  const DailyOccupancyTrace({super.key, required this.items});
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Semantics(
      label: '当天占用时段分布，蓝线表示当前时间',
      child: Column(
        children: [
          SizedBox(
            height: 44,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _OccupancyPainter(items, DateTime.now(), v),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00:00', style: instrumentText(color: v.muted, size: 10)),
              // 中间这条最长：系统字体放大到 2.0 时三个定长标签会撑破
              // 310px 的可用宽度，这里让它单独收缩。
              Flexible(
                child: Text(
                  '今日占用时段',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: instrumentText(color: v.muted, size: 10),
                ),
              ),
              Text('24:00', style: instrumentText(color: v.muted, size: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OccupancyPainter extends CustomPainter {
  final List<Item> items;
  final DateTime now;
  final PilotVisuals v;
  _OccupancyPainter(this.items, this.now, this.v);
  @override
  void paint(Canvas canvas, Size size) {
    final day = DateTime(now.year, now.month, now.day),
        end = DateTime(now.year, now.month, now.day + 1);
    final ranges = items.where(
      (i) => i.timed && i.start!.isBefore(end) && i.end!.isAfter(day),
    );
    final path = Path()..moveTo(0, size.height - 5);
    final spans = <double>[0, 1440];
    for (final i in ranges) {
      spans.addAll([
        i.start!.difference(day).inMinutes.toDouble().clamp(0, 1440),
        i.end!.difference(day).inMinutes.toDouble().clamp(0, 1440),
      ]);
    }
    spans.sort();
    for (var n = 0; n < spans.length - 1; n++) {
      final a = spans[n], b = spans[n + 1], mid = (a + b) / 2;
      final occupied = ranges.any(
        (i) =>
            mid >= i.start!.difference(day).inMinutes &&
            mid < i.end!.difference(day).inMinutes,
      );
      final y = occupied ? 8.0 : size.height - 5;
      path.lineTo(a / 1440 * size.width, y);
      path.lineTo(b / 1440 * size.width, y);
    }
    final baseline = Paint()
      ..color = v.line
      ..strokeWidth = .5;
    for (var h = 0; h <= 24; h += 3) {
      final x = size.width * h / 24;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), baseline);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = v.signal,
    );
    final x = now.difference(day).inMinutes / 1440 * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = v.signalYellow
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(x, size.height - 5),
      2.5,
      Paint()..color = v.signalYellow,
    );
  }

  @override
  bool shouldRepaint(covariant _OccupancyPainter old) =>
      old.now.minute != now.minute || old.items != items || old.v != v;
}
