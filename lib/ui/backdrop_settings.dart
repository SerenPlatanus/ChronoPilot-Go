import 'dart:convert';
import 'package:flutter/services.dart';

enum BackdropKind { theme, plain, paper, wallpaper }

/// Local UI settings, deliberately separate from planner/Agent data snapshots.
class BackdropSettings {
  final BackdropKind kind;
  final String? filePath;
  final double panelOpacity, veilOpacity;
  const BackdropSettings({
    this.kind = BackdropKind.theme,
    this.filePath,
    this.panelOpacity = 1,
    this.veilOpacity = .7,
  });
  BackdropSettings copyWith({
    BackdropKind? kind,
    String? filePath,
    double? panelOpacity,
    double? veilOpacity,
    bool clearFile = false,
  }) => BackdropSettings(
    kind: kind ?? this.kind,
    filePath: clearFile ? null : filePath ?? this.filePath,
    panelOpacity: panelOpacity ?? this.panelOpacity,
    veilOpacity: veilOpacity ?? this.veilOpacity,
  );
  String encode() => jsonEncode({
    'kind': kind.name,
    'path': filePath,
    'panelOpacity': panelOpacity,
    'veilOpacity': veilOpacity,
  });
  static BackdropSettings decode(String? raw) {
    try {
      if (raw == null) return const BackdropSettings();
      final data = jsonDecode(raw) as Map;
      double bounded(String key, double fallback, double min) {
        final value = data[key];
        return value is num && value.isFinite
            ? value.toDouble().clamp(min, 1)
            : fallback;
      }

      final kind = BackdropKind.values.firstWhere(
        (v) => v.name == data['kind'],
        orElse: () => BackdropKind.theme,
      );
      final path = data['path'] is String ? data['path'] as String : null;
      return BackdropSettings(
        kind: kind == BackdropKind.wallpaper && path == null
            ? BackdropKind.theme
            : kind,
        filePath: path,
        panelOpacity: bounded('panelOpacity', 1, .35),
        veilOpacity: bounded('veilOpacity', .7, 0),
      );
    } catch (_) {
      return const BackdropSettings();
    }
  }
}

class WallpaperFiles {
  static const channel = MethodChannel('app.chronopilot.go/wallpaper');
  static Future<String?> pick() =>
      channel.invokeMethod<String>('pickWallpaper');
  static Future<void> remove(String path) async {
    await channel.invokeMethod<bool>('deleteWallpaper', {'path': path});
  }
}
