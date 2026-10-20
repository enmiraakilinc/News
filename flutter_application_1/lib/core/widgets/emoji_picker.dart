import 'package:flutter/material.dart';

Future<String?> chooseEmoji(
  BuildContext context, {
  String? initial,
  String title = 'Emoji seç',
}) => showDialog<String>(
  context: context,
  builder: (_) => _EmojiDialog(initial: initial, title: title),
);

class _EmojiDialog extends StatefulWidget {
  final String? initial;
  final String title;
  const _EmojiDialog({this.initial, required this.title});
  @override
  State<_EmojiDialog> createState() => _EmojiDialogState();
}

class _EmojiDialogState extends State<_EmojiDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: 1,
        style: const TextStyle(fontSize: 32),
        decoration: const InputDecoration(
          labelText: 'Emoji',
          helperText: 'Klavyeden istediğin emojiyi seç.',
        ),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Bir emoji seç.' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: const Text('Kaydet'),
      ),
    ],
  );
}
