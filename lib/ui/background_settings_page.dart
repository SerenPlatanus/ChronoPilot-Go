import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'backdrop_settings.dart';
import 'controls.dart';
import 'styles.dart';

String backdropLabel(BackdropKind kind) => switch (kind) {
  BackdropKind.theme => '跟随主题',
  BackdropKind.plain => '纯色',
  BackdropKind.paper => '纸面纹理',
  BackdropKind.wallpaper => '自定义壁纸',
};

class BackgroundSettingsPage extends StatefulWidget {
  const BackgroundSettingsPage({super.key});
  @override
  State<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends State<BackgroundSettingsPage> {
  double? panelDraft, veilDraft;
  String? error;
  Future<void> perform(Future<void> Function() action) async {
    setState(() => error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformException
              ? e.message ?? '导入壁纸失败'
              : '操作未完成，请稍后重试',
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = StyleScope.maybeOf(context)!,
        settings = controller.backdrop;
    final v = PilotVisuals.of(context),
        opacity = panelDraft ?? settings.panelOpacity,
        veil = veilDraft ?? settings.veilOpacity;
    final busy = controller.saving;
    return Scaffold(
      appBar: AppBar(title: const Text('背景与透明度')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<BackdropKind>(
            key: ValueKey(settings.kind),
            initialValue: settings.kind,
            decoration: const InputDecoration(labelText: '背景'),
            items: [
              for (final kind in BackdropKind.values)
                DropdownMenuItem(value: kind, child: Text(backdropLabel(kind))),
            ],
            onChanged: busy
                ? null
                : (kind) => perform(() async {
                    if (kind == null) return;
                    if (kind == BackdropKind.wallpaper &&
                        settings.filePath == null) {
                      await controller.importWallpaper();
                    } else {
                      await controller.setBackdrop(
                        settings.copyWith(kind: kind),
                      );
                    }
                  }),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              PilotControl(
                className: 'wallpaper-import',
                kind: 'primary-button',
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => perform(() async {
                          await controller.importWallpaper();
                        }),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(busy ? '处理中' : '导入壁纸'),
                ),
              ),
              if (settings.filePath != null)
                PilotControl(
                  className: 'wallpaper-remove',
                  kind: 'text-button',
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => perform(controller.removeWallpaper),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('移除壁纸'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Slider drags update this local preview; only release writes and rebuilds the app theme.
          ClipRRect(
            borderRadius: BorderRadius.circular(v.radius),
            child: SizedBox(
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (settings.kind == BackdropKind.wallpaper &&
                      settings.filePath != null)
                    Image.file(
                      File(settings.filePath!),
                      cacheWidth: 700,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(color: v.paper),
                    )
                  else
                    ColoredBox(
                      color: settings.kind == BackdropKind.paper
                          ? v.namedColor('calendar-surface')
                          : v.paper,
                    ),
                  if (settings.kind == BackdropKind.wallpaper)
                    ColoredBox(color: v.paper.withValues(alpha: veil)),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: v.surface.withValues(alpha: opacity),
                        borderRadius: BorderRadius.circular(v.radius),
                        border: Border.all(color: v.line),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: v.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '日程面板预览',
                              style: TextStyle(
                                color: v.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('面板不透明度  ${(opacity * 100).round()}%'),
          Slider(
            key: const ValueKey('panel-opacity-slider'),
            value: opacity,
            min: .35,
            max: 1,
            divisions: 65,
            onChanged: busy
                ? null
                : (value) => setState(() => panelDraft = value),
            onChangeEnd: busy
                ? null
                : (value) async {
                    await perform(
                      () => controller.setBackdrop(
                        controller.backdrop.copyWith(panelOpacity: value),
                      ),
                    );
                    if (mounted) setState(() => panelDraft = null);
                  },
          ),
          if (settings.kind == BackdropKind.wallpaper) ...[
            Text('背景柔化遮罩  ${(veil * 100).round()}%'),
            Slider(
              key: const ValueKey('wallpaper-veil-slider'),
              value: veil,
              min: 0,
              max: 1,
              divisions: 100,
              onChanged: busy
                  ? null
                  : (value) => setState(() => veilDraft = value),
              onChangeEnd: busy
                  ? null
                  : (value) async {
                      await perform(
                        () => controller.setBackdrop(
                          controller.backdrop.copyWith(veilOpacity: value),
                        ),
                      );
                      if (mounted) setState(() => veilDraft = null);
                    },
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
