import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'backdrop_settings.dart';

enum PilotStyle {
  defaultStyle('default', '默认主题', '原版布局 · 蓝色强调'),
  testAlpha('test_alpha', '测试主题alpha', '纸面质感 · 荧光仪表'),
  testBeta('test_beta', '测试主题beta', '冷灰层次 · 清晰细线'),
  custom('custom', '自定义主题', '自行编辑 CSS');

  final String id, label, description;
  const PilotStyle(this.id, this.label, this.description);
  String get asset =>
      'assets/styles/${this == defaultStyle ? 'default_style' : id}.css';
  static PilotStyle parse(String? id) => switch (id) {
    'cassette_future' => testAlpha,
    'swiss' => testBeta,
    _ => values.firstWhere((v) => v.id == id, orElse: () => defaultStyle),
  };
}

/// Interprets root tokens and the restricted .cp-* control classes only.
/// The same source files provide a usable CSS reference for future Web views.
@immutable
class StyleTokens {
  final PilotStyle style;
  final Map<String, String> values;
  final Map<String, Map<String, String>> controls;
  const StyleTokens(this.style, this.values, [this.controls = const {}]);
  factory StyleTokens.fromCss(PilotStyle style, String css) {
    if (css.length > 65536) throw const FormatException('皮肤 CSS 超过长度上限');
    css = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final blocks = <(String, String)>[];
    var cursor = 0;
    final pattern = RegExp(r'([^{}]+)\{([^{}]*)\}');
    for (final block in pattern.allMatches(css)) {
      if (css.substring(cursor, block.start).trim().isNotEmpty) {
        throw const FormatException('不支持嵌套、媒体查询或不完整规则');
      }
      blocks.add((block[1]!.trim(), block[2]!));
      cursor = block.end;
    }
    if (css.substring(cursor).trim().isNotEmpty) {
      throw const FormatException('CSS 规则不完整');
    }
    final roots = blocks.where((b) => b.$1 == ':root').toList();
    if (roots.length != 1) throw const FormatException('需要且只能有一个普通 :root');
    final root = roots.single.$2;
    final values = {
      for (final m in RegExp(r'--([a-z-]+)\s*:\s*([^;]+);').allMatches(root))
        m[1]!: m[2]!.trim(),
    };
    if (values['style-id'] != style.id) throw const FormatException('主题标识不匹配');
    final controls = <String, Map<String, String>>{};
    for (final rule in blocks.where((b) => b.$1 != ':root')) {
      final selector = RegExp(r'^\.cp-([a-z-]+)$').firstMatch(rule.$1);
      if (selector == null) throw FormatException('不支持的选择器：${rule.$1}');
      final declarations = <String, String>{};
      for (final declaration
          in rule.$2
              .split(';')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)) {
        final entry = RegExp(
          r'^--([a-z-]+)\s*:\s*(.+)$',
        ).firstMatch(declaration);
        if (entry == null) throw const FormatException('控件只支持 --radius 等自定义属性');
        final key = entry[1]!, value = entry[2]!.trim();
        if (key == 'radius' || key == 'border-width' || key == 'opacity') {
          final n = double.tryParse(value);
          final max = key == 'radius'
              ? 28
              : key == 'opacity'
              ? 1
              : 4;
          if (n == null || !n.isFinite || n < 0 || n > max) {
            throw FormatException('无效控件尺寸：$key');
          }
        } else if (key == 'border-color' ||
            key == 'fill' ||
            key == 'foreground') {
          if (![
            'ink',
            'line',
            'accent',
            'paper',
            'surface',
            'stage',
            'screen',
            'danger',
            'on-accent',
            'calendar-surface',
            'navigation-surface',
            'transparent',
          ].contains(value)) {
            throw FormatException('无效控件颜色引用：$value');
          }
        } else {
          throw FormatException('不支持的控件属性：$key');
        }
        declarations[key] = value;
      }
      controls[selector[1]!] = Map.unmodifiable(declarations);
    }
    final result = StyleTokens(
      style,
      Map.unmodifiable(values),
      Map.unmodifiable(controls),
    );
    result.color('seed');
    for (final prefix in ['', 'dark-']) {
      for (final name in [
        'paper',
        'surface',
        'ink',
        'muted',
        'line',
        'accent',
        'stage',
        'screen',
        'signal',
        'signal-red',
        'signal-yellow',
        'danger',
      ]) {
        result.color('$prefix$name');
      }
    }
    for (final prefix in ['', 'dark-']) {
      for (final key in ['calendar-surface', 'navigation-surface']) {
        if (values.containsKey('$prefix$key')) result.color('$prefix$key');
      }
    }
    for (final key in ['radius-card', 'radius-glass', 'space-unit']) {
      result.number(key);
    }
    if (values.containsKey('border-card') && result.number('border-card') > 4) {
      throw const FormatException('卡片边框不能超过 4');
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
    if (n == null || !n.isFinite || n < 0 || n > 100) {
      throw FormatException('无效主题尺寸：$key');
    }
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
  String? customCss;
  BackdropSettings backdrop;
  final Future<void> Function(String)? backdropWriter;
  final Future<void> Function(String)? customWriter;
  final Map<(PilotStyle, Brightness), ThemeData> _themes = {};
  StyleController({
    required this.palettes,
    required this.writer,
    PilotStyle selected = PilotStyle.defaultStyle,
    Brightness brightness = Brightness.light,
    this.brightnessWriter,
    this.customWriter,
    this.customCss,
    this.backdrop = const BackdropSettings(),
    this.backdropWriter,
  }) : _selected = selected,
       _brightness = brightness;
  PilotStyle get selected => _selected;
  Brightness get brightness => _brightness;
  static Future<StyleController> load() async {
    final palettes = await loadPalettes();
    final box = await Hive.openBox<String>('ui_preferences_v1');
    final customCss = box.get('custom-css');
    if (customCss != null) {
      try {
        palettes[PilotStyle.custom] = StyleTokens.fromCss(
          PilotStyle.custom,
          customCss,
        );
      } on FormatException {
        /* Keep the safe bundled template. */
      }
    }
    return StyleController(
      palettes: palettes,
      customCss: customCss,
      backdrop: BackdropSettings.decode(box.get('backdrop')),
      backdropWriter: (value) => box.put('backdrop', value),
      customWriter: (css) => box.put('custom-css', css),
      writer: (id) => box.put('style', id),
      selected: PilotStyle.parse(box.get('style')),
      brightness: box.get('brightness') == 'dark'
          ? Brightness.dark
          : Brightness.light,
      brightnessWriter: (id) => box.put('brightness', id),
    );
  }

  static Future<Map<PilotStyle, StyleTokens>> loadPalettes() async =>
      Map.fromEntries(
        await Future.wait(
          PilotStyle.values.map(
            (style) async => MapEntry(
              style,
              StyleTokens.fromCss(
                style,
                await rootBundle.loadString(style.asset),
              ),
            ),
          ),
        ),
      );
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

  Future<void> applyCustom(String css) async {
    if (saving) return;
    if (css.length > 65536) throw const FormatException('皮肤文件最多 64 KiB 字符');
    final tokens = StyleTokens.fromCss(PilotStyle.custom, css);
    // Validate both appearances before changing any persisted selection.
    themeFor(tokens, brightness: Brightness.light);
    themeFor(tokens, brightness: Brightness.dark);
    saving = true;
    notifyListeners();
    try {
      await customWriter?.call(css);
      await writer(PilotStyle.custom.id);
      palettes[PilotStyle.custom] = tokens;
      customCss = css;
      _themes.removeWhere((key, _) => key.$1 == PilotStyle.custom);
      _selected = PilotStyle.custom;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> setBackdrop(BackdropSettings next) async {
    if (saving) return;
    if (!next.panelOpacity.isFinite ||
        next.panelOpacity < .35 ||
        next.panelOpacity > 1 ||
        !next.veilOpacity.isFinite ||
        next.veilOpacity < 0 ||
        next.veilOpacity > 1) {
      throw const FormatException('背景参数无效');
    }
    saving = true;
    notifyListeners();
    try {
      await backdropWriter?.call(next.encode());
      backdrop = next;
      _themes.clear();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> importWallpaper() async {
    if (saving) return false;
    saving = true;
    notifyListeners();
    String? imported;
    final old = backdrop.filePath;
    try {
      imported = await WallpaperFiles.pick();
      if (imported == null) return false;
      final next = backdrop.copyWith(
        kind: BackdropKind.wallpaper,
        filePath: imported,
        panelOpacity: backdrop.panelOpacity == 1 ? .9 : backdrop.panelOpacity,
      );
      await backdropWriter?.call(next.encode());
      backdrop = next;
      _themes.clear();
      if (old != null && old != imported) {
        try {
          await WallpaperFiles.remove(old);
        } catch (_) {
          /* New wallpaper is already safely saved. */
        }
      }
      return true;
    } catch (_) {
      if (imported != null) {
        try {
          await WallpaperFiles.remove(imported);
        } catch (_) {}
      }
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> removeWallpaper() async {
    final old = backdrop.filePath;
    await setBackdrop(
      backdrop.copyWith(
        clearFile: true,
        kind: backdrop.kind == BackdropKind.wallpaper
            ? BackdropKind.theme
            : backdrop.kind,
        panelOpacity: 1,
      ),
    );
    if (old != null && backdrop.filePath == null) {
      try {
        await WallpaperFiles.remove(old);
      } catch (_) {}
    }
  }

  ThemeData get theme => _themes.putIfAbsent(
    (_selected, _brightness),
    () => themeFor(
      palettes[_selected]!,
      brightness: _brightness,
      panelOpacity: backdrop.panelOpacity,
      transparentBackground: true,
    ),
  );
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
  final bool alpha;
  final bool dark;
  final Color paper, surface, ink, muted, line, accent, stage, screen, signal;
  final Color signalRed, signalYellow;
  final double radius;
  final double borderWidth;
  final double panelOpacity;
  final StyleTokens? tokens;
  const PilotVisuals({
    required this.alpha,
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
    this.borderWidth = 1,
    this.panelOpacity = 1,
    this.tokens,
  });
  static PilotVisuals of(BuildContext context) =>
      Theme.of(context).extension<PilotVisuals>() ??
      const PilotVisuals(
        alpha: false,
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
  Color namedColor(String name) => switch (name) {
    'ink' => ink,
    'line' => line,
    'accent' => accent,
    'paper' => paper,
    'surface' => surface,
    'stage' => stage,
    'screen' => screen,
    'danger' => tokens?.color(dark ? 'dark-danger' : 'danger') ?? signalRed,
    'on-accent' => dark ? screen : Colors.white,
    'calendar-surface' => _regionColor('calendar-surface', .07),
    'navigation-surface' => _regionColor('navigation-surface', .12),
    _ => Colors.transparent,
  };

  Color _regionColor(String name, double alpha) {
    final key = dark ? 'dark-$name' : name;
    return tokens?.values.containsKey(key) == true
        ? tokens!.color(key)
        : Color.alphaBlend(ink.withValues(alpha: alpha), surface);
  }

  Color layerColor(Color color, {double opacity = 1}) =>
      color.withValues(alpha: (color.a * panelOpacity * opacity).clamp(0, 1));

  BoxDecoration decoration(
    String className, {
    double? defaultRadius,
    double? defaultWidth,
    Color? fill,
  }) {
    final rules = <String, String>{
      ...?tokens?.controls['panel'],
      ...?tokens?.controls[className],
    };
    final width =
        double.tryParse(rules['border-width'] ?? '') ??
        defaultWidth ??
        borderWidth;
    return BoxDecoration(
      color: layerColor(
        rules.containsKey('fill')
            ? namedColor(rules['fill']!)
            : fill ?? surface,
        opacity: double.tryParse(rules['opacity'] ?? '') ?? 1,
      ),
      borderRadius: BorderRadius.circular(
        double.tryParse(rules['radius'] ?? '') ?? defaultRadius ?? radius,
      ),
      border: Border.all(
        width: width,
        style: width == 0 ? BorderStyle.none : BorderStyle.solid,
        color: rules.containsKey('border-color')
            ? namedColor(rules['border-color']!)
            : borderWidth > 1
            ? ink
            : line,
      ),
    );
  }

  RoundedRectangleBorder shape(String className, {double? defaultRadius}) {
    final d = decoration(className, defaultRadius: defaultRadius);
    return RoundedRectangleBorder(
      borderRadius: d.borderRadius!,
      side: (d.border! as Border).top,
    );
  }

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
ThemeData themeFor(
  StyleTokens t, {
  Brightness brightness = Brightness.light,
  double panelOpacity = 1,
  bool transparentBackground = false,
}) {
  final dark = brightness == Brightness.dark;
  Color color(String name) => t.color(dark ? 'dark-$name' : name);
  final alpha = t.style == PilotStyle.testAlpha;
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: t.color('seed'),
    brightness: brightness,
  );
  final visuals = PilotVisuals(
    alpha: alpha,
    panelOpacity: panelOpacity,
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
    borderWidth: double.tryParse(t.values['border-card'] ?? '1') ?? 1,
    tokens: t,
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
  final field = visuals.decoration('field', defaultRadius: 8);
  final border = OutlineInputBorder(
    borderRadius: field.borderRadius! as BorderRadius,
    borderSide: (field.border! as Border).top,
  );
  return base.copyWith(
    colorScheme: scheme,
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ImmediatePageTransitions(),
        TargetPlatform.linux: ImmediatePageTransitions(),
        TargetPlatform.iOS: ImmediatePageTransitions(),
      },
    ),
    scaffoldBackgroundColor: transparentBackground
        ? Colors.transparent
        : visuals.paper,
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
      backgroundColor: visuals.decoration('appbar', fill: visuals.paper).color,
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
        borderRadius: BorderRadius.circular(
          t.style == PilotStyle.testBeta ? 2 : 8,
        ),
        side: BorderSide(
          color: visuals.borderWidth > 1 ? visuals.ink : visuals.line,
          width: visuals.borderWidth,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field.color,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: visuals.accent,
          width: visuals.borderWidth > 1.5 ? visuals.borderWidth : 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.all(16),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: visuals.layerColor(visuals.paper),
      selectedColor: visuals.layerColor(visuals.stage),
      showCheckmark: false,
      labelStyle: base.textTheme.labelLarge!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.ideographic,
        color: visuals.ink,
        fontSize: 13,
      ),
      side: BorderSide(
        color: visuals.borderWidth > 1 ? visuals.ink : visuals.line,
        width: visuals.borderWidth,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          t.style == PilotStyle.testBeta ? 2 : 24,
        ),
      ),
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
      backgroundColor: visuals.decoration('dialog').color,
      shape: visuals.shape('dialog', defaultRadius: 24),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: visuals.decoration('dialog').color,
      shape: visuals.shape('dialog', defaultRadius: 24),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: visuals.accent,
      linearTrackColor: visuals.line,
    ),
  );
}

/// Keep routes and back navigation instantaneous, including nested editors.
class ImmediatePageTransitions extends PageTransitionsBuilder {
  const ImmediatePageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class PilotPageRoute<T> extends MaterialPageRoute<T> {
  PilotPageRoute({required super.builder});
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
}
