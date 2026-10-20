import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/starred/starred_messages.dart';
import '../../features/chat/chat_downloads.dart';
import '../../features/chat/message_selection.dart';

class ThemeSelection extends ValueNotifier<String> {
  ThemeSelection(super.value);
  void refresh() => notifyListeners();
}

class ChatThemes {
  static final selected = ThemeSelection('pastel');
  static int? accent;
  static double roundness = 24;
  static Future<void>? _loading;
  static final Map<String, ThemeData> _cache = {};
  static const names = {
    'dark': 'Karanlık',
    'light': 'Açık',
    'blue': 'Gece mavisi',
    'purple': 'Mor',
    'pastel': 'Pastel mavi • Krem',
    'mist': 'Sis • Adaçayı',
    'moon': 'Ay ışığı',
    'rose': 'Pudra',
    'love': 'Love',
    'orange': 'Turuncu',
  };
  static Future<void> load() => _loading ??= _load();
  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    accent = null;
    roundness = 24;
    final saved = prefs.getString('neural_chat_theme');
    if (names.containsKey(saved)) selected.value = saved!;
    selected.refresh();
  }

  static Future<void> choose(String value) async {
    selected.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('neural_chat_theme', value);
  }

  static ThemeData theme(String value) {
    final key = '$value:$accent:$roundness';
    return _cache.putIfAbsent(key, () => _buildTheme(value));
  }

  static ThemeData _buildTheme(String value) {
    final seed = value == 'love'
        ? const Color(0xff420303)
        : value == 'orange'
        ? const Color(0xfffc9803)
        : accent != null
        ? Color(accent!)
        : value == 'pastel'
        ? const Color(0xff83abc5)
        : value == 'mist'
        ? const Color(0xff6e9697)
        : value == 'moon'
        ? const Color(0xff9c86ed)
        : value == 'rose'
        ? const Color(0xffc68b9d)
        : value == 'blue'
        ? const Color(0xff608dcc)
        : value == 'purple'
        ? const Color(0xffab79cc)
        : const Color(0xff479c86);
    var scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: ['light', 'pastel', 'mist', 'rose'].contains(value)
          ? Brightness.light
          : Brightness.dark,
    );
    if (value == 'love') {
      scheme = scheme.copyWith(
        primary: const Color(0xffff7979),
        onPrimary: const Color(0xff3b0905),
        primaryContainer: const Color(0xff420303),
        onPrimaryContainer: const Color(0xffffe4df),
        surface: const Color(0xff201817),
        onSurface: const Color(0xfff7e5e1),
        surfaceContainer: const Color(0xff420303),
      );
    }
    if (value == 'orange') {
      scheme = scheme.copyWith(
        primary: const Color(0xfffc9803),
        onPrimary: const Color(0xff402000),
        primaryContainer: const Color(0xfffc9803),
        onPrimaryContainer: Colors.black,
        surface: const Color(0xff211911),
        onSurface: const Color(0xffffeadb),
        surfaceContainer: const Color(0xff3b2314),
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: value == 'pastel'
          ? const Color(0xfffaf6ed)
          : scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundness),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundness),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: value == 'orange'
            ? scheme.primaryContainer
            : scheme.surfaceContainer,
        foregroundColor: value == 'orange'
            ? scheme.onPrimaryContainer
            : scheme.onSurface,
      ),
    );
  }
}

class ChatScaffold extends StatefulWidget {
  final String? starsSource;
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  const ChatScaffold({
    super.key,
    this.starsSource,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.backgroundColor,
  });
  @override
  State<ChatScaffold> createState() => _ChatScaffoldState();
}

class _ChatScaffoldState extends State<ChatScaffold> {
  @override
  void initState() {
    super.initState();
    ChatThemes.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: ChatThemes.selected,
    builder: (_, value, child) => Theme(
      data: ChatThemes.theme(value),
      child: _withStars(
        Scaffold(
          // The composer already reserves the keyboard inset below itself.
          resizeToAvoidBottomInset: widget.bottomNavigationBar == null,
          appBar: widget.appBar,
          body: widget.starsSource == null
              ? widget.body
              : LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .35,
                        ),
                        child: ChatDownloadRequests(
                          key: ValueKey(widget.starsSource),
                          sourceKey: widget.starsSource!,
                        ),
                      ),
                      Expanded(child: widget.body ?? const SizedBox.shrink()),
                    ],
                  ),
                ),
          bottomNavigationBar: widget.bottomNavigationBar,
        ),
      ),
    ),
  );
  Widget _withStars(Widget child) => widget.starsSource == null
      ? child
      : MessageStarsScope(
          key: ValueKey(widget.starsSource),
          sourceKey: widget.starsSource!,
          child: MessageSelectionScope(
            key: ValueKey(widget.starsSource),
            child: child,
          ),
        );
}

class ChatThemeButton extends StatelessWidget {
  const ChatThemeButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Sohbet teması',
    icon: const Icon(Icons.palette_outlined),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Sohbet teması'),
        children: [
          ...ChatThemes.names.entries.map(
            (entry) => SimpleDialogOption(
              onPressed: () {
                ChatThemes.choose(entry.key);
                Navigator.pop(ctx);
              },
              child: Text(
                '${ChatThemes.selected.value == entry.key ? '✓ ' : ''}${entry.value}',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
