import 'dart:convert';
import 'dart:io';
import '../media/local_audio_dialog.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../reminders/reminder_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../media/media_viewer.dart';
import '../voice_notes/voice_notes_screen.dart';
import '../../core/utils/user_errors.dart';
import 'package:flutter/services.dart';
import '../location/offline_location_map.dart';
import '../../core/security/feature_access.dart';

class NewsNotes extends StatefulWidget {
  final int article;
  final bool audioOnly;
  const NewsNotes({super.key, required this.article, this.audioOnly = false});
  @override
  State<NewsNotes> createState() => _NewsNotesState();
}

class _NewsNotesState extends State<NewsNotes> {
  List<Map<String, dynamic>> _notes = [];
  bool _busy = false, _ready = false;
  String get _key => 'personal_media_notes';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final notes = <Map<String, dynamic>>[];
    final legacyKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('news_media_notes_'))
        .toList();
    for (final raw in [
      ...?prefs.getStringList(_key),
      for (final key in legacyKeys) ...?prefs.getStringList(key),
    ]) {
      try {
        final note = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (!notes.any((n) => jsonEncode(n) == jsonEncode(note))) {
          notes.add(note);
        }
      } catch (_) {}
    }
    final missingIds = notes.any((note) => note['id'] == null);
    for (final note in notes) {
      note['id'] ??= const Uuid().v4();
    }
    if (legacyKeys.isNotEmpty || missingIds) {
      await prefs.setStringList(_key, notes.map(jsonEncode).toList());
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
    }
    if (mounted) {
      setState(() {
        _notes = notes;
        _ready = true;
      });
    }
  }

  Future<Directory> _folder() async {
    final app = await getApplicationSupportDirectory();
    return Directory('${app.path}/news_notes').create(recursive: true);
  }

  Future<File?> _owned(String filename) async {
    if (!RegExp(r'^[0-9]+_[0-9]+\.(image|m4a)$').hasMatch(filename)) {
      return null;
    }
    return File('${(await _folder()).path}/$filename');
  }

  Future<void> _save(String source, String kind, String title) async {
    if (_notes.length >= 100) {
      throw Exception(
        'En fazla 100 not saklayabilirsin. Önce eski bir notu sil.',
      );
    }
    final file = File(source);
    if (await file.length() > 20 * 1024 * 1024) {
      throw Exception('Bu not çok büyük. En fazla 20 MB dosya seç.');
    }
    final filename =
        '${DateTime.now().microsecondsSinceEpoch}_${widget.article}.${kind == 'photo' ? 'image' : 'm4a'}';
    final saved = await file.copy('${(await _folder()).path}/$filename');
    try {
      final next = [
        ..._notes,
        {
          'id': const Uuid().v4(),
          'file': filename,
          'kind': kind,
          'title': title,
        },
      ];
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        next.map(jsonEncode).toList(),
      );
      if (mounted) setState(() => _notes = next);
    } catch (_) {
      await saved.delete();
      rethrow;
    }
  }

  Future<void> _image() async {
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (image != null) await _save(image.path, 'photo', image.name);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _textNote([Map<String, dynamic>? existing]) async {
    if (_busy || !_ready) return;
    if (existing == null && _notes.length >= 100) {
      _error(
        Exception('En fazla 100 not saklayabilirsin. Önce eski bir notu sil.'),
      );
      return;
    }
    final title = TextEditingController(
      text: existing?['title'] as String? ?? '',
    );
    final body = TextEditingController(
      text: existing?['text'] as String? ?? '',
    );
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Yeni yazılı not' : 'Notu düzenle'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: title,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Başlık (isteğe bağlı)',
                  ),
                ),
                TextFormField(
                  controller: body,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 20000,
                  decoration: const InputDecoration(
                    labelText: 'Notun',
                    hintText: 'Yazmak istediğini buraya ekle…',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Notunu yaz.'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    final heading = title.text.trim();
    final text = body.text.trim();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      title.dispose();
      body.dispose();
    });
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final firstLine = text.split('\n').first;
      final note = <String, dynamic>{
        ...?existing,
        'id': existing?['id'] ?? const Uuid().v4(),
        'kind': 'text',
        'title': heading.isNotEmpty
            ? heading
            : firstLine.substring(
                0,
                firstLine.length > 80 ? 80 : firstLine.length,
              ),
        'text': text,
      };
      final next = [..._notes];
      if (existing == null) {
        next.add(note);
      } else {
        next[next.indexOf(existing)] = note;
      }
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        next.map(jsonEncode).toList(),
      );
      if (mounted) setState(() => _notes = next);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remind(Map<String, dynamic> note) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = note['id'] as String? ?? const Uuid().v4();
      note['id'] = id;
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        _notes.map(jsonEncode).toList(),
      );
      if (mounted) await ReminderService.pick(context, id);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _audio() async {
    setState(() => _busy = true);
    try {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceNotesScreen(
            sendMessage: (path, title) => _save(path, 'audio', title),
            screenTitle: 'Kendime sesli not',
            confirmLabel: 'Notu kaydet',
          ),
        ),
      );
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userError(error))));
    }
  }

  Future<void> _location() async {
    if (_notes.length >= 100) {
      _error(Exception('Önce eski bir notu sil.'));
      return;
    }
    setState(() => _busy = true);
    const channel = MethodChannel('app/location');
    try {
      await FeatureAccess.require('location');
      final point = await channel
          .invokeMapMethod<String, dynamic>('current')
          .timeout(const Duration(seconds: 25));
      if (point == null || !mounted) return;
      final name = TextEditingController(text: 'Kaydettiğim konum');
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Konum notu'),
          content: TextField(
            controller: name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Not adı'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, name.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
      // Dialog route can retain its controller during its closing animation.
      Future<void>.delayed(const Duration(milliseconds: 350), name.dispose);
      if (title == null || title.isEmpty) return;
      final next = [
        ..._notes,
        {
          'id': const Uuid().v4(),
          'kind': 'location',
          'title': title,
          'latitude': point['latitude'],
          'longitude': point['longitude'],
        },
      ];
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        next.map(jsonEncode).toList(),
      );
      if (mounted) setState(() => _notes = next);
    } catch (error) {
      await channel.invokeMethod<void>('cancel').catchError((_) {});
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> note) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = [..._notes]..remove(note);
      if (note['id'] is String) {
        await ReminderService.cancel(note['id'] as String);
      }
      final file = note['file'] is String
          ? await _owned(note['file'] as String)
          : null;
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        next.map(jsonEncode).toList(),
      );
      if (mounted) setState(() => _notes = next);
      if (file != null && await file.exists()) await file.delete();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> note) async {
    try {
      if (note['kind'] == 'text') {
        await _textNote(note);
        return;
      }
      if (note['kind'] == 'location') {
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(note['title'] as String)),
              body: OfflineLocationMap(
                latitude: (note['latitude'] as num).toDouble(),
                longitude: (note['longitude'] as num).toDouble(),
                expiresAt: DateTime(2100),
              ),
            ),
          ),
        );
        return;
      }
      final file = await _owned(note['file'] as String);
      if (file == null || !await file.exists()) {
        throw Exception('Notun dosyası bulunamadı.');
      }
      if (note['kind'] == 'photo') {
        final bytes = await file.readAsBytes();
        if (mounted) await showPrivatePhoto(context, bytes);
      } else if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) =>
              LocalAudioDialog(file: file, title: note['title'] as String),
        );
      }
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.audioOnly ? 'Sesli Notlarım' : 'Kendime Notlar',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const Text('Yalnızca bu cihazda saklanır; başkalarına gönderilmez.'),
      Wrap(
        spacing: 12,
        children: [
          if (!widget.audioOnly)
            TextButton.icon(
              onPressed: !_ready || _busy ? null : () => _textNote(),
              icon: const Icon(Icons.edit_note),
              label: const Text('Yazılı not'),
            ),
          if (!widget.audioOnly)
            TextButton.icon(
              onPressed: !_ready || _busy ? null : _image,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Görsel not'),
            ),
          TextButton.icon(
            onPressed: !_ready || _busy ? null : _audio,
            icon: const Icon(Icons.mic_none),
            label: const Text('Sesli not'),
          ),
          if (!widget.audioOnly)
            TextButton.icon(
              onPressed: !_ready || _busy ? null : _location,
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Konum ekle'),
            ),
        ],
      ),
      const Text(
        'Not ekledikten sonra yanındaki Alarm kur ile gün ve saat seçebilirsin.',
      ),
      for (final note in _notes.where(
        (n) => !widget.audioOnly || n['kind'] == 'audio',
      ))
        ListTile(
          leading: Icon(
            note['kind'] == 'text'
                ? Icons.notes_outlined
                : note['kind'] == 'location'
                ? Icons.location_on_outlined
                : note['kind'] == 'photo'
                ? Icons.image_outlined
                : Icons.play_circle_outline,
          ),
          title: Text(
            note['title'] as String,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: note['kind'] == 'text'
              ? Text(
                  note['text'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: _busy ? null : () => _open(note),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _remind(note),
                icon: const Icon(Icons.alarm_add),
                label: const Text('Alarm kur'),
              ),
              IconButton(
                tooltip: 'Notu sil',
                onPressed: _busy ? null : () => _remove(note),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
    ],
  );
}
