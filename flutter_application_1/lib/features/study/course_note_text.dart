import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Selectable notes with explicit, user-initiated HTTP(S) links.
class CourseNoteText extends StatefulWidget {
  const CourseNoteText(this.text, {super.key, this.openLink});
  final String text;
  final Future<bool> Function(Uri)? openLink;
  @override
  State<CourseNoteText> createState() => _CourseNoteTextState();
}

class _CourseNoteTextState extends State<CourseNoteText> {
  final _recognizers = <TapGestureRecognizer>[];
  List<InlineSpan> _spans = [];
  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(CourseNoteText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parse();
  }

  void _parse() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in RegExp(
      r'(?:https?://|www\.)[^\s<>]+',
      caseSensitive: false,
    ).allMatches(widget.text)) {
      var link = match.group(0)!;
      while (link.endsWith('.') ||
          link.endsWith(',') ||
          link.endsWith(';') ||
          (link.endsWith(')') &&
              ')'.allMatches(link).length > '('.allMatches(link).length)) {
        link = link.substring(0, link.length - 1);
      }
      if (match.start > offset) {
        spans.add(TextSpan(text: widget.text.substring(offset, match.start)));
      }
      final uri = Uri.tryParse(
        link.toLowerCase().startsWith('www.') ? 'https://$link' : link,
      );
      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          try {
            if (uri == null || uri.host.isEmpty) throw const FormatException();
            final opened =
                await (widget.openLink?.call(uri) ??
                    launchUrl(uri, mode: LaunchMode.externalApplication));
            if (!opened) throw const FormatException();
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Bağlantı açılamadı. Adresi kontrol edip yeniden dene.',
                  ),
                ),
              );
            }
          }
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: link,
          recognizer: recognizer,
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
      );
      offset = match.start + link.length;
    }
    if (offset < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(offset)));
    }
    _spans = spans;
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectableText.rich(
    TextSpan(children: _spans),
    style: const TextStyle(height: 1.5),
  );
}
