import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/emoji_picker.dart';
import '../pair/couple_service.dart';

Future<String?> chooseReaction(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReactionPicker(),
    );

class _ReactionPicker extends StatefulWidget {
  const _ReactionPicker();
  @override
  State<_ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<_ReactionPicker> {
  late final _key = 'reaction_favorites_${CoupleService.uid ?? 'local'}';
  List<String>? _emojis;
  bool _editing = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _emojis =
              prefs.getStringList(_key) ?? ['❤️', '😂', '👍', '😮', '😢', '🙏'];
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Emoji listen açılamadı. Yeniden dene.');
      }
    }
  }

  Future<void> _save(List<String> values) async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(_key, values)) throw Exception();
      if (mounted) {
        setState(() {
          _emojis = values;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Emoji listesi kaydedilemedi. Yeniden dene.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    final emoji = await chooseEmoji(context);
    if (!mounted || emoji == null || _emojis!.contains(emoji)) return;
    await _save([..._emojis!, emoji]);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'İfade bırak',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_emojis == null && _error == null)
            const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_emojis == null && _error != null)
            TextButton(onPressed: _load, child: const Text('Yeniden dene')),
          if (_emojis != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final emoji in _emojis!)
                  _editing
                      ? InputChip(
                          label: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                          deleteButtonTooltipMessage: 'Listeden çıkar',
                          onDeleted: _saving
                              ? null
                              : () => _save(
                                  _emojis!.where((e) => e != emoji).toList(),
                                ),
                        )
                      : TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context, emoji),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
              ],
            ),
            if (_editing) ...[
              const Text('Sık kullandığın emojileri ekle veya listeden çıkar.'),
              TextButton.icon(
                onPressed: _saving || _emojis!.length >= 12 ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Emoji ekle (en fazla 12)'),
              ),
            ] else
              TextButton.icon(
                onPressed: () async {
                  final emoji = await chooseEmoji(context);
                  if (context.mounted && emoji != null) {
                    Navigator.pop(context, emoji);
                  }
                },
                icon: const Icon(Icons.keyboard),
                label: const Text('Klavyeden emoji seç'),
              ),
            TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(() => _editing = !_editing),
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
              label: Text(_editing ? 'Tamam' : 'Emojileri düzenle'),
            ),
          ],
        ],
      ),
    ),
  );
}
