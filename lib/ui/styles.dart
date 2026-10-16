import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

enum PilotStyle {
  defaultStyle('default', '默认主题', '原版布局 · 蓝色强调'),
  cassetteFuture('cassette_future', '磁带未来主题', '纸面质感 · 荧光仪表');

  final String id, label, description;
  const PilotStyle(this.id, this.label, this.description);
  String get asset =>
      'assets/styles/${this == defaultStyle ? 'default_style' : 'cassette_future'}.css';
  static PilotStyle parse(String? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => defaultStyle);
}

/// Only :root custom properties are interpreted, never arbitrary CSS/script.
/// The same source files provide a usable CSS reference for future Web views.
@immutable
class StyleTokens {
  final PilotStyle style;
  final Map<String, String> values;
  const StyleTokens(this.style, this.values);
  factory StyleTokens.fromCss(PilotStyle style, String css) {
    final root = RegExp(r':root\s*\{([^}]+)\}').firstMatch(css);
    if (root == null) throw const FormatException('主题缺少 :root');
    final values = {
      for (final m in RegExp(
        r'--([a-z-]+)\s*:\s*([^;]+);',
      ).allMatches(root[1]!))
        m[1]!: m[2]!.trim(),
    };
    if (values['style-id'] != style.id) throw const FormatException('主题标识不匹配');
    final result = StyleTokens(style, Map.unmodifiable(values));
    for (final key in [
      'seed',
      'paper',
      'surface',
      'ink',
      'muted',
      'line',
      'accent',
      'stage',
      'screen',
      'signal',
      'danger',
    ]) {
      result.color(key);
    }
    for (final key in ['radius-card', 'radius-glass', 'space-unit']) {
      result.number(key);
    }
    return result;
  }
  Color color(String key) {
    final v = values[key];
    if (v == null || !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(v)) {
      throw FormatException('无效主题颜色：$key');
    }
    return Color(0xff000000 | int.parse(v.substring(1), radix: 16));
  }

  double number(String key) {
    final n = double.tryParse(values[key] ?? '');
    if (n == null || n < 0 || n > 100) throw FormatException('无效主题尺寸：$key');
    return n;
  }
}

class StyleController extends ChangeNotifier {
  final Map<PilotStyle, StyleTokens> palettes;
  final Future<void> Function(String) writer;
  PilotStyle _selected;
  Brightness _brightness;
  final Future<void> Function(String)? brightnessWriter;
  bool saving = false;
  StyleController({
    required this.palettes,
    required this.writer,
    PilotStyle selected = PilotStyle.defaultStyle,
    Brightness brightness = Brightness.light,
    this.brightnessWriter,
  }) : _selected = selected,
       _brightness = brightness;
  PilotStyle get selected => _selected;
  Brightness get brightness => _brightness;
  static Future<StyleController> load() async {
    final palettes = await loadPalettes();
    final box = await Hive.openBox<String>('ui_preferences_v1');
    return StyleController(
      palettes: palettes,
      writer: (id) => box.put('style', id),
      selected: PilotStyle.parse(box.get('style')),
      brightness: box.get('brightness') == 'dark'
          ? Brightness.dark
          : Brightness.light,
      brightnessWriter: (id) => box.put('brightness', id),
    );
  }

  static Future<Map<PilotStyle, StyleTokens>> loadPalettes() async => {
    for (final style in PilotStyle.values)
      style: StyleTokens.fromCss(
        style,
        await rootBundle.loadString(style.asset),
      ),
  };
  Future<void> select(PilotStyle style) async {
    if (saving || style == _selected) return;
    saving = true;
    notifyListeners();
    try {
      await writer(style.id);
      _selected = style;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> selectBrightness(Brightness value) async {
    if (saving || value == _brightness) return;
    saving = true;
    notifyListeners();
    try {
      await brightnessWriter?.call(value.name);
      _brightness = value;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  ThemeData get theme =>
      themeFor(palettes[_selected]!, brightness: _brightness);
}

class StyleScope extends InheritedNotifier<StyleController> {
  const StyleScope({
    super.key,
    required StyleController controller,
    required super.child,
  }) : super(notifier: controller);
  static StyleController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StyleScope>()?.notifier;
}

@immutable
class PilotVisuals extends ThemeExtension<PilotVisuals> {
  final bool cassette;
  final bool dark;
  final Color paper, surface, ink, muted, line, accent, stage, screen, signal;
  final Color signalRed, signalYellow;
  final double radius;
  const PilotVisuals({
    required this.cassette,
    this.dark = false,
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.stage,
    required this.screen,
    required this.signal,
    this.signalRed = const Color(0xffff695d),
    this.signalYellow = const Color(0xfff4ed71),
    required this.radius,
  });
  static PilotVisuals of(BuildContext context) =>
      Theme.of(context).extension<PilotVisuals>() ??
      const PilotVisuals(
        cassette: false,
        paper: Color(0xfff6faf8),
        surface: Colors.white,
        ink: Color(0xff18201e),
        muted: Color(0xff56635f),
        line: Color(0xffd4deda),
        accent: Color(0xff176b61),
        stage: Color(0xffdcefe9),
        screen: Color(0xff183d36),
        signal: Color(0xffc3eedb),
        radius: 12,
      );
  @override
  PilotVisuals copyWith() => this;
  @override
  PilotVisuals lerp(covariant PilotVisuals? other, double t) =>
      other == null || t < .5 ? this : other;
}

TextStyle instrumentText({
  double size = 12,
  Color? color,
  FontWeight weight = FontWeight.w500,
}) => TextStyle(
  fontFamily: 'monospace',
  fontSize: size,
  color: color,
  fontWeight: weight,
  fontFeatures: const [FontFeature.tabularFigures()],
  letterSpacing: .4,
);
ThemeData themeFor(StyleTokens t, {Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  Color color(String name) => t.color(dark ? 'dark-$name' : name);
  final cassette = t.style == PilotStyle.cassetteFuture;
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: t.color('seed'),
    brightness: brightness,
  );
  final visuals = PilotVisuals(
    cassette: cassette,
    dark: dark,
    paper: color('paper'),
    surface: color('surface'),
    ink: color('ink'),
    muted: color('muted'),
    line: color('line'),
    accent: color('accent'),
    stage: color('stage'),
    screen: color('screen'),
    signal: color('signal'),
    signalRed: color('signal-red'),
    signalYellow: color('signal-yellow'),
    radius: t.number('radius-card'),
  );

  final scheme = base.colorScheme.copyWith(
    primary: visuals.accent,
    onPrimary: dark ? visuals.screen : Colors.white,
    secondary: visuals.ink,
    onSecondary: dark ? visuals.paper : Colors.white,
    surface: visuals.paper,
    onSurface: visuals.ink,
    onSurfaceVariant: visuals.muted,
    outline: visuals.muted,
    outlineVariant: visuals.line,
    primaryContainer: visuals.stage,
    onPrimaryContainer: visuals.ink,
    secondaryContainer: visuals.stage,
    onSecondaryContainer: visuals.ink,
    error: color('danger'),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: visuals.line),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: visuals.paper,
    extensions: [visuals],
    textTheme: base.textTheme
        .apply(bodyColor: visuals.ink, displayColor: visuals.ink)
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge!.copyWith(
            inherit: false,
            textBaseline: TextBaseline.ideographic,
            fontSize: 34,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: visuals.ink,
          ),
          titleLarge: base.textTheme.titleLarge!.copyWith(
            inherit: false,
            textBaseline: TextBaseline.ideographic,
            fontSize: 23,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: visuals.ink,
          ),
          bodyMedium: base.textTheme.bodyMedium!.copyWith(
            inherit: false,
            textBaseline: TextBaseline.ideographic,
            fontSize: 14,
            height: 1.6,
            color: visuals.ink,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: visuals.paper,
      foregroundColor: visuals.ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.ideographic,
        color: visuals.ink,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      toolbarHeight: 64,
    ),
    cardTheme: CardThemeData(
      color: visuals.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: visuals.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: visuals.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: visuals.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(16),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: visuals.paper,
      selectedColor: visuals.stage,
      showCheckmark: false,
      labelStyle: base.textTheme.labelLarge!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.ideographic,
        color: visuals.ink,
        fontSize: 13,
      ),
      side: BorderSide(color: visuals.line),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: dark ? visuals.accent : visuals.ink,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => base.textTheme.labelMedium!.copyWith(
          inherit: false,
          textBaseline: TextBaseline.ideographic,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: visuals.ink,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? visuals.paper
              : visuals.muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? visuals.accent : visuals.ink,
        foregroundColor: dark ? visuals.screen : Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: base.textTheme.labelLarge!.copyWith(
          inherit: false,
          textBaseline: TextBaseline.ideographic,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? visuals.accent : visuals.ink,
      foregroundColor: dark ? visuals.screen : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(
      color: visuals.line,
      space: 24,
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: visuals.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: visuals.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: visuals.accent,
      linearTrackColor: visuals.line,
    ),
  );
}
