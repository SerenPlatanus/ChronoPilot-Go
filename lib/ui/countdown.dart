import 'dart:async';
import 'package:flutter/material.dart';
import '../planner/item.dart';
import 'styles.dart';

class CountdownView extends StatefulWidget {
  final Item item;
  final bool screen;
  const CountdownView({super.key, required this.item, this.screen = false});
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
    final item = widget.item, now = DateTime.now();
    final v = PilotVisuals.of(context);
    final color = widget.screen
        ? item.countdownTarget(now)?.isBefore(now) == true
              ? v.signalRed
              : item.timed && !now.isBefore(item.start!)
              ? v.signal
              : v.signalYellow
        : Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          countdown(item, now),
          style: instrumentText(color: color, size: widget.screen ? 14 : 12),
        ),
        if (item.timed && !now.isBefore(item.start!) && now.isBefore(item.end!))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              color: color,
              backgroundColor: widget.screen
                  ? v.signal.withValues(alpha: .16)
                  : null,
              minHeight: 3,
              borderRadius: BorderRadius.circular(3),
              value:
                  now.difference(item.start!).inMilliseconds /
                  item.end!.difference(item.start!).inMilliseconds,
            ),
          ),
      ],
    );
  }
}
