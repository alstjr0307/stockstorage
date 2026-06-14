import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlRegex = RegExp(
  r'(https?:\/\/[^\s<>\)\]\}"　]+|www\.[^\s<>\)\]\}"　]+)',
  caseSensitive: false,
);

Future<void> openExternalUrl(String raw) async {
  var url = raw.trim();
  if (url.isEmpty) return;
  while (url.isNotEmpty && (url.endsWith('.') || url.endsWith(',') || url.endsWith(')') || url.endsWith(']') || url.endsWith('}'))) {
    url = url.substring(0, url.length - 1);
  }
  if (url.startsWith('www.')) {
    url = 'https://$url';
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final effectiveLinkStyle =
        widget.linkStyle ??
        (widget.style ?? const TextStyle()).copyWith(
          color: const Color(0xFF3B82F6),
          decoration: TextDecoration.underline,
        );

    final spans = <TextSpan>[];
    final matches = _urlRegex.allMatches(widget.text);
    var lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: widget.text.substring(lastEnd, m.start)));
      }
      final url = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openExternalUrl(url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: url, style: effectiveLinkStyle, recognizer: recognizer),
      );
      lastEnd = m.end;
    }
    if (lastEnd < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(lastEnd)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}
