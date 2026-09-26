import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:url_launcher/url_launcher.dart';
class ClickableText extends StatelessWidget {
  const ClickableText({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final regex = RegExp(r'https?://[^\s]+');
    final matches = regex.allMatches(text);
    final spans = <TextSpan>[];
    var start = 0;

    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }

      String? url = match.group(0);
      spans.add(
        TextSpan(
          text: url,
          style: context.colors.caption.copyWith(
            height: 1.8,
            color: Colors.orange,
            decoration: TextDecoration.underline,
            decorationColor: Colors.orangeAccent,
            decorationThickness: 2
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(Uri.parse(url!)),
        ),
      );

      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return Text.rich(
      TextSpan(
        style: context.colors.caption.copyWith(height: 1.6),
        children: spans,
      ),
    );
  }
}
