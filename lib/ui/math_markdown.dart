import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'styles.dart';

/// Markdown's code/escape parsers still own code spans and escaped dollars.
/// Match only closed delimiters; incomplete inline formulas remain plain text.
class InlineMathSyntax extends md.InlineSyntax {
  InlineMathSyntax()
    : super(r'\\\(([\s\S]+?)\\\)|\$(?!\$)(?=\S)([^\n$]*?\S)\$(?![\d$])');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math-inline', match[1] ?? match[2]!));
    return true;
  }
}

class DisplayMathSyntax extends md.BlockSyntax {
  const DisplayMathSyntax();
  @override
  RegExp get pattern => RegExp(r'^[ ]{0,3}(\$\$|\\\[)');
  @override
  md.Node parse(md.BlockParser parser) {
    final original = <String>[];
    final first = parser.current.content;
    final match = pattern.firstMatch(first)!;
    final close = match[1] == r'$$' ? r'$$' : r'\]';
    var line = first.substring(match.end);
    final tex = <String>[];
    while (true) {
      original.add(parser.current.content);
      final index = line.lastIndexOf(close);
      if (index >= 0 && line.substring(index + close.length).trim().isEmpty) {
        tex.add(line.substring(0, index));
        parser.advance();
        return md.Element.text('math-display', tex.join('\n').trim());
      }
      tex.add(line);
      parser.advance();
      if (parser.isDone) return md.Element.text('p', original.join('\n'));
      line = parser.current.content;
    }
  }
}

class MathElementBuilder extends MarkdownElementBuilder {
  final bool display;
  MathElementBuilder({this.display = false});
  @override
  bool isBlockElement() => display;
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent, v = PilotVisuals.of(context);
    final size = MediaQuery.textScalerOf(context).scale(display ? 17 : 15);
    final formula = Semantics(
      label: tex,
      child: Math.tex(
        tex,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: TextStyle(color: v.ink, fontSize: size),
        onErrorFallback: (_) => Text(
          tex,
          style: TextStyle(
            color: v.ink,
            fontFamily: 'monospace',
            fontSize: size,
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: display ? 12 : 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 72).clamp(80, 960),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: formula,
        ),
      ),
    );
  }
}
