import 'dart:typed_data';
import 'package:flutter/material.dart';

class MediaNamesScreen extends StatefulWidget {
  final List<String> names;
  final Uint8List? photo;
  final bool splitVideo;
  const MediaNamesScreen({
    super.key,
    required this.names,
    this.photo,
    this.splitVideo = true,
  });
  @override
  State<MediaNamesScreen> createState() => _MediaNamesScreenState();
}

class _MediaNamesScreenState extends State<MediaNamesScreen> {
  late final _names = widget.names
      .map((n) => TextEditingController(text: n))
      .toList();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Göndermeden önce')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.photo != null)
            Image.memory(
              widget.photo!,
              height: 160,
              fit: BoxFit.contain,
              cacheWidth: 640,
            ),
          if (_names.length > 1)
            Text(
              widget.splitVideo
                  ? 'Video ${_names.length} parçaya ayrıldı. Her parçaya ayrı isim verebilirsin.'
                  : '${_names.length} ek seçildi. Tek onayla sırayla gönderilecek.',
            ),
          ExpansionTile(
            initiallyExpanded: _names.length > 1,
            title: const Text('İsim ekle veya değiştir'),
            children: [
              for (var i = 0; i < _names.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _names[i],
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: _names.length == 1
                          ? 'İsim'
                          : widget.splitVideo
                          ? '${i + 1}. parçanın ismi'
                          : '${i + 1}. ekin ismi',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Bir isim yaz.'
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  _names.map((c) => c.text.trim()).toList(),
                );
              }
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    ),
  );
}
