import 'package:flutter/material.dart';
import 'styles.dart';

class StylePicker extends StatefulWidget {
  const StylePicker({super.key});
  @override
  State<StylePicker> createState() => _StylePickerState();
}

class _StylePickerState extends State<StylePicker> {
  String? error;
  @override
  Widget build(BuildContext context) {
    final controller = StyleScope.maybeOf(context),
        v = PilotVisuals.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller != null) ...[
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Brightness>(
              segments: const [
                ButtonSegment(
                  value: Brightness.light,
                  label: Text('浅色'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: Brightness.dark,
                  label: Text('深色'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {controller.brightness},
              onSelectionChanged: controller.saving
                  ? null
                  : (values) async {
                      setState(() => error = null);
                      try {
                        await controller.selectBrightness(values.single);
                      } catch (_) {
                        if (mounted) setState(() => error = '明暗模式未能保存，请重试');
                      }
                    },
            ),
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 20),
        ],
        for (final style in PilotStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              button: true,
              selected: controller?.selected == style,
              label: style.label,
              child: Material(
                color: controller?.selected == style
                    ? v.stage.withValues(alpha: .24)
                    : v.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: controller?.selected == style ? v.accent : v.line,
                    width: controller?.selected == style ? 1.5 : 1,
                  ),
                ),
                child: InkWell(
                  key: ValueKey('style-${style.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: controller == null || controller.saving
                      ? null
                      : () async {
                          setState(() => error = null);
                          try {
                            await controller.select(style);
                          } catch (_) {
                            if (mounted) setState(() => error = '主题未能保存，请重试');
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ExcludeSemantics(
                          child: Container(
                            width: 52,
                            height: 64,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: v.dark
                                  ? const Color(0xff152326)
                                  : style == PilotStyle.cassetteFuture
                                  ? const Color(0xffe9e3d4)
                                  : const Color(0xfff6faf8),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: v.line),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  height: 23,
                                  decoration: BoxDecoration(
                                    color: v.dark
                                        ? const Color(0xff67d8d2)
                                        : style == PilotStyle.cassetteFuture
                                        ? const Color(0xffd6b981)
                                        : const Color(0xffdcefe9),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  height: 5,
                                  color: v.dark
                                      ? const Color(0xffabf58c)
                                      : style == PilotStyle.cassetteFuture
                                      ? const Color(0xff272d27)
                                      : const Color(0xff176b61),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  height: 5,
                                  color: const Color(0xffd4d5ce),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                style.label,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                style.description,
                                style: TextStyle(
                                  color: v.muted,
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          controller?.selected == style
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: controller?.selected == style
                              ? v.accent
                              : v.muted,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
