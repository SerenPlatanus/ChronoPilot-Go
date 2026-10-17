import 'package:flutter/material.dart';
import 'styles.dart';

/// A named, independently skinnable control. CSS rules cascade in this order:
/// .cp-button, .cp-{kind}, .cp-{className}. Geometry never changes hit targets.
class PilotControl extends StatelessWidget {
  final String className;
  final String kind;
  final Widget child;
  const PilotControl({
    super.key,
    required this.className,
    required this.kind,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), v = PilotVisuals.of(context);
    final rules = v.tokens?.controls ?? const <String, Map<String, String>>{};
    final properties = <String, String>{
      ...?rules['button'],
      ...?rules[kind],
      ...?rules[className],
    };
    if (properties.isEmpty) return child;
    Color color(String name) => switch (name) {
      'ink' => v.ink,
      'line' => v.line,
      'accent' => v.accent,
      'paper' => v.paper,
      'surface' => v.surface,
      'stage' => v.stage,
      'screen' => v.screen,
      'danger' => theme.colorScheme.error,
      'on-accent' => theme.colorScheme.onPrimary,
      _ => Colors.transparent,
    };
    final radius = double.tryParse(properties['radius'] ?? '24') ?? 24;
    final width = double.tryParse(properties['border-width'] ?? '0') ?? 0;
    final side = BorderSide(
      color: color(properties['border-color'] ?? 'line'),
      width: width,
      style: width == 0 ? BorderStyle.none : BorderStyle.solid,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final style = ButtonStyle(
      animationDuration: Duration.zero,
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      shape: WidgetStatePropertyAll(shape),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? side.copyWith(color: side.color.withValues(alpha: .3))
            : side,
      ),
      backgroundColor: properties.containsKey('fill')
          ? WidgetStateProperty.resolveWith(
              (states) => color(properties['fill']!).withValues(
                alpha: states.contains(WidgetState.disabled) ? .12 : 1,
              ),
            )
          : null,
      foregroundColor: properties.containsKey('foreground')
          ? WidgetStateProperty.resolveWith(
              (states) => color(properties['foreground']!).withValues(
                alpha: states.contains(WidgetState.disabled) ? .38 : 1,
              ),
            )
          : null,
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)
            ? v.accent.withValues(alpha: .15)
            : null,
      ),
    );
    // Explicit inherited component themes also work inside AppBar/ButtonBar,
    // whose local overrides take precedence over ThemeData fields.
    return switch (kind) {
      'primary-button' => FilledButtonTheme(
        data: FilledButtonThemeData(
          style: FilledButtonTheme.of(context).style?.merge(style) ?? style,
        ),
        child: child,
      ),
      'secondary-button' => OutlinedButtonTheme(
        data: OutlinedButtonThemeData(
          style: OutlinedButtonTheme.of(context).style?.merge(style) ?? style,
        ),
        child: child,
      ),
      'text-button' => TextButtonTheme(
        data: TextButtonThemeData(
          style: TextButtonTheme.of(context).style?.merge(style) ?? style,
        ),
        child: child,
      ),
      'filter-button' => ChipTheme(
        data: ChipTheme.of(context).copyWith(shape: shape, side: side),
        child: child,
      ),
      'segment-button' => SegmentedButtonTheme(
        data: SegmentedButtonThemeData(
          style: SegmentedButtonTheme.of(context).style?.merge(style) ?? style,
        ),
        child: child,
      ),
      'add-button' => Theme(
        data: theme.copyWith(
          floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
            shape: shape.copyWith(side: side),
            backgroundColor: properties.containsKey('fill')
                ? color(properties['fill']!)
                : null,
            foregroundColor: properties.containsKey('foreground')
                ? color(properties['foreground']!)
                : null,
          ),
        ),
        child: child,
      ),
      _ => Padding(
        padding: const EdgeInsets.all(2),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButtonTheme.of(context).style?.merge(style) ?? style,
          ),
          child: child,
        ),
      ),
    };
  }
}
