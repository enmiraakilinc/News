import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_theme.dart';

/// Public appearance preference stays independent from the private area.
class NewsThemes {
  static final selected = ValueNotifier<String>('dark');
  static Future<void>? _loading;
  static ThemeData get current => ChatThemes.theme(selected.value);
  static Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('neural_news_theme');
    if (ChatThemes.names.containsKey(saved)) selected.value = saved!;
  }();
  static Future<void> choose(String value) async {
    if (!ChatThemes.names.containsKey(value)) return;
    selected.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('neural_news_theme', value);
  }
}

class NewsThemeScope extends StatelessWidget {
  final Widget child;
  const NewsThemeScope({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: NewsThemes.selected,
    builder: (_, _, _) => Theme(data: NewsThemes.current, child: child),
  );
}

Future<void> showNewsThemePicker(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => SimpleDialog(
    title: const Text('Tema'),
    children: [
      for (final entry in ChatThemes.names.entries)
        SimpleDialogOption(
          onPressed: () {
            NewsThemes.choose(entry.key);
            Navigator.pop(ctx);
          },
          child: Text(
            '${NewsThemes.selected.value == entry.key ? '✓ ' : ''}${entry.value}',
          ),
        ),
    ],
  ),
);
