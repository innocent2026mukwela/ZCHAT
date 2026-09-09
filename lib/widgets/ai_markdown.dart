import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Renders AI (Claude) output as markdown with the app's dark theme.
///
/// The AI system prompt instructs Claude to use **bold**, `## headings` and
/// `- bullets`; without a markdown renderer those show up as literal symbols.
/// Use this anywhere AI-generated text is displayed.
class AiMarkdown extends StatelessWidget {
  final String data;
  final Color color;
  final double fontSize;
  final double height;

  const AiMarkdown(
    this.data, {
    super.key,
    this.color = Colors.white,
    this.fontSize = 14,
    this.height = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    return GptMarkdown(
      data.trim(),
      style: TextStyle(color: color, fontSize: fontSize, height: height),
    );
  }
}
