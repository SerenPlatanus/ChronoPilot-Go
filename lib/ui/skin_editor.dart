import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controls.dart';
import 'styles.dart';

/// A local-only editor: no network, file permission, or third party parser.
class SkinEditor extends StatefulWidget {
  const SkinEditor({super.key});
  @override
  State<SkinEditor> createState() => _SkinEditorState();
}

class _SkinEditorState extends State<SkinEditor> {
  final editor = TextEditingController();
  String? error;
  bool initialized = false, saving = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      final controller = StyleScope.maybeOf(context)!;
      if (controller.customCss != null) {
        editor.text = controller.customCss!;
      } else {
        _template();
      }
    }
  }

  Future<void> _template() async {
    final css = await rootBundle.loadString(PilotStyle.defaultStyle.asset);
    if (mounted) {
      setState(() {
        editor.text = css.replaceFirst(
          '--style-id: default;',
          '--style-id: custom;',
        );
        error = null;
      });
    }
  }

  Future<void> _apply() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await StyleScope.maybeOf(context)!.applyCustom(editor.text);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '皮肤保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('自定义皮肤'),
      actions: [
        PilotControl(
          className: 'skin-copy',
          kind: 'icon-button',
          child: IconButton(
            tooltip: '复制 CSS',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: editor.text));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('CSS 已复制')));
              }
            },
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('skin-css-editor'),
                controller: editor,
                expands: true,
                minLines: null,
                maxLines: null,
                maxLength: 65536,
                textAlignVertical: TextAlignVertical.top,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  labelText: 'CSS（标识为 custom）',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                PilotControl(
                  className: 'skin-reset',
                  kind: 'secondary-button',
                  child: OutlinedButton(
                    onPressed: saving ? null : _template,
                    child: const Text('载入默认模板'),
                  ),
                ),
                PilotControl(
                  className: 'skin-apply',
                  kind: 'primary-button',
                  child: FilledButton(
                    onPressed: saving ? null : _apply,
                    child: Text(saving ? '保存中' : '保存并应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
