import 'math_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'styles.dart';

class AgentMarkdown extends StatelessWidget {
  final String data;
  const AgentMarkdown({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final v = PilotVisuals.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: data,
          selectable: true,
          inlineSyntaxes: [InlineMathSyntax()],
          blockSyntaxes: const [DisplayMathSyntax()],
          builders: {
            'math-inline': MathElementBuilder(),
            'math-display': MathElementBuilder(display: true),
          },
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(color: v.ink, fontSize: 15, height: 1.6),
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: v.ink,
              backgroundColor: v.line.withValues(alpha: .3),
            ),
            codeblockDecoration: BoxDecoration(
              color: v.paper,
              borderRadius: BorderRadius.circular(8),
            ),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: v.accent, width: 3)),
            ),
            tableBorder: TableBorder.all(color: v.line),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: v.line)),
            ),
          ),
          // Model-generated image URLs are represented as text, without loading them.
          imageBuilder: (uri, title, alt) =>
              Text(alt ?? title ?? uri.toString()),
          onTapLink: (text, href, title) {
            if (href == null) return;
            showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(text),
                content: SelectableText(href),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: href));
                      if (c.mounted) Navigator.pop(c);
                    },
                    child: const Text('复制链接'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '复制消息',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('消息已复制')));
              }
            },
          ),
        ),
      ],
    );
  }
}
