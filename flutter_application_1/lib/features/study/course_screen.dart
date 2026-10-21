import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'course_repository.dart';
import 'course_folder_color.dart';
import 'course_search_screen.dart';
import 'course_note_text.dart';
import 'course_video.dart';
import '../media/audio_file_types.dart';
import '../media/local_audio_dialog.dart';
import '../../core/utils/search_text.dart';
import '../pair/couple_service.dart';
import '../pair/paired_gate.dart';
import '../media/image_util.dart';
import '../media/media_viewer.dart';
import '../reminders/reminder_service.dart';
import '../../core/utils/user_errors.dart';

class SharedCoursesScreen extends StatelessWidget {
  const SharedCoursesScreen({super.key});
  @override
  Widget build(BuildContext context) => PairedGate(
    title: 'Ortak Ders Notları',
    builder: (cid, secret) =>
        CourseFoldersScreen(repository: SharedCourseRepository(cid, secret)),
  );
}

class PersonalCoursesScreen extends StatefulWidget {
  const PersonalCoursesScreen({super.key});
  @override
  State<PersonalCoursesScreen> createState() => _PersonalCoursesScreenState();
}

class _PersonalCoursesScreenState extends State<PersonalCoursesScreen> {
  late Future<String> _owner = _load();
  Future<String> _load() async {
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    if (uid == null) throw Exception('Kişisel hesabın henüz hazır değil.');
    return uid;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _owner,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return CourseFoldersScreen(
          repository: LocalCourseRepository(snapshot.data!),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Ders Notlarım')),
        body: Center(
          child: snapshot.hasError
              ? TextButton(
                  onPressed: () => setState(() => _owner = _load()),
                  child: const Text('Kişisel alan açılamadı. Yeniden dene.'),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class CourseFoldersScreen extends StatefulWidget {
  final CourseRepository repository;
  final LessonFolder? parent;
  const CourseFoldersScreen({super.key, required this.repository, this.parent});
  @override
  State<CourseFoldersScreen> createState() => _CourseFoldersScreenState();
}

class _CourseFoldersScreenState extends State<CourseFoldersScreen> {
  Stream<List<LessonFolder>> _folders() =>
      widget.repository.folders(parent: widget.parent?.id);
  late Stream<List<LessonFolder>> _stream = _folders();
  bool _busy = false;
  Future<void> _create() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.parent == null ? 'Yeni ders klasörü' : 'Yeni konu klasörü',
        ),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: widget.parent == null ? 'Ders adı' : 'Konu adı',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (title == null || title.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.create(title, parent: widget.parent?.id);
      if (mounted) setState(() => _stream = _folders());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(LessonFolder folder) async {
    if (!await _confirm(
      context,
      '${folder.title} klasörü, alt klasörleri ve içindeki tüm notlar silinsin mi?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      if (!widget.repository.shared) {
        await _cancelReminders(folder.id);
      }
      await widget.repository.removeCourse(folder.id);
      if (mounted) setState(() => _stream = _folders());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelReminders(String id) async {
    for (final note in await widget.repository.notes(id).first) {
      await ReminderService.cancel(note.id);
    }
    for (final child in await widget.repository.folders(parent: id).first) {
      await _cancelReminders(child.id);
    }
  }

  Future<void> _pin(LessonFolder folder) async {
    setState(() => _busy = true);
    try {
      await widget.repository.pinFolder(folder.id, !folder.pinned);
      if (mounted) setState(() => _stream = _folders());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kişisel ders yedeği'),
        content: const Text(
          'Ders klasörlerin, notların, kodların ve görsellerin seçtiğin yere JSON dosyası olarak kaydedilecek. Bu dosya şifreli değildir; özel bir yerde sakla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dışa aktar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await (widget.repository as LocalCourseRepository)
          .exportBackup();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Ders yedeğini kaydet',
        fileName: 'ders-notlarim-${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kişisel ders yedeği kaydedildi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          tooltip: 'Ders notlarında ara',
          onPressed: _busy
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CourseSearchScreen(
                      repository: widget.repository,
                      root: widget.parent,
                    ),
                  ),
                ),
          icon: const Icon(Icons.search),
        ),
        if (!widget.repository.shared && widget.parent == null)
          IconButton(
            tooltip: 'Yedeği dışa aktar',
            onPressed: _busy ? null : _backup,
            icon: const Icon(Icons.download_outlined),
          ),
      ],
      title: Text(
        widget.parent != null
            ? '${widget.parent!.title} • Konular'
            : widget.repository.shared
            ? 'Ortak Ders Notları'
            : 'Ders Notlarım',
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy ? null : _create,
      icon: const Icon(Icons.create_new_folder_outlined),
      label: Text(widget.parent == null ? 'Yeni ders' : 'Yeni konu klasörü'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.repository.shared
                ? 'Yalnızca gizli kelimeyle eşleştiğin kişiyle paylaşılır.'
                : 'Yalnızca bu cihazdaki kişisel alanında saklanır; paylaşılmaz.',
          ),
        ),
        Expanded(
          child: StreamBuilder<List<LessonFolder>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Dersler yüklenemedi. Geri dönüp yeniden dene.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final folders = [...snapshot.data!]
                ..sort((a, b) {
                  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                  return searchText(a.title).compareTo(searchText(b.title));
                });
              if (folders.isEmpty) {
                return Center(
                  child: Text(
                    widget.parent == null
                        ? 'Yeni ders ekleyerek notlarını düzenlemeye başla.'
                        : 'Tokenizer, Parse gibi konular için klasör ekle.',
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: folders.length,
                itemBuilder: (context, i) => ListTile(
                  leading: Icon(
                    Icons.folder,
                    color: courseFolderColors[folders[i].color],
                  ),
                  title: Text(folders[i].title),
                  onTap: _busy
                      ? null
                      : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CourseNotesScreen(
                              repository: widget.repository,
                              folder: folders[i],
                            ),
                          ),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CourseFolderColorButton(
                        repository: widget.repository,
                        folder: folders[i],
                        enabled: !_busy,
                        onChanged: () => setState(() => _stream = _folders()),
                      ),
                      IconButton(
                        tooltip: folders[i].pinned
                            ? 'Sabitlemeyi kaldır'
                            : 'Klasörü sabitle',
                        onPressed: _busy ? null : () => _pin(folders[i]),
                        icon: Icon(
                          folders[i].pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dersi sil',
                        onPressed: _busy ? null : () => _remove(folders[i]),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class CourseNotesScreen extends StatefulWidget {
  final CourseRepository repository;
  final LessonFolder folder;
  final String initialQuery;
  const CourseNotesScreen({
    super.key,
    required this.repository,
    required this.folder,
    this.initialQuery = '',
  });
  @override
  State<CourseNotesScreen> createState() => _CourseNotesScreenState();
}

class _CourseNotesScreenState extends State<CourseNotesScreen> {
  final _text = TextEditingController();
  late final _query = TextEditingController(text: widget.initialQuery);
  late Stream<List<LessonNote>> _stream = widget.repository.notes(
    widget.folder.id,
  );
  bool _busy = false;
  String _kind = 'text';
  final _expandedNotes = <String>{};
  bool _showSearch = false;
  final _cleanedVideos = <String>{};

  Future<void> _sendAudio() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    LessonNote? pending;
    File? pickedCopy;
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: AudioFileTypes.mimeTypes.keys.toList(),
      );
      if (selected == null || !mounted) return;
      final size = await selected.length();
      if (size != null && (size < 1 || size > 20 * 1024 * 1024)) {
        throw Exception('Ses dosyası en fazla 20 MB olabilir.');
      }
      final cache = await getTemporaryDirectory();
      pickedCopy = File(
        '${cache.path}/course_audio_import_${const Uuid().v4()}',
      );
      final sink = pickedCopy.openWrite();
      var received = 0;
      try {
        await for (final bytes in selected.readAsByteStream()) {
          received += bytes.length;
          if (received > 20 * 1024 * 1024) {
            throw Exception('Ses dosyası en fazla 20 MB olabilir.');
          }
          sink.add(bytes);
        }
      } finally {
        await sink.close();
      }
      if (received == 0) {
        throw Exception('Ses dosyası boş veya Drive üzerinden indirilemedi.');
      }
      final ext = AudioFileTypes.extension(selected.name);
      pending = LessonNote(
        id: const Uuid().v4(),
        kind: 'audio',
        text: _text.text.trim().isEmpty ? selected.name : _text.text.trim(),
        audioExtension: ext,
        created: DateTime.now(),
      );
      final chunks = await CourseVideo.save(
        widget.repository,
        widget.folder.id,
        pending.id,
        XFile(pickedCopy.path, name: selected.name),
        kind: 'audio',
        extension: ext,
      );
      await widget.repository.add(
        widget.folder.id,
        LessonNote.fromJson({...pending.toJson(), 'videoChunks': chunks}),
      );
      pending = null;
      if (mounted) {
        setState(() {
          _text.clear();
          _stream = widget.repository.notes(widget.folder.id);
        });
      }
    } catch (error) {
      if (pending != null) {
        await CourseVideo.remove(
          widget.repository,
          widget.folder.id,
          pending,
        ).catchError((_) {});
        await widget.repository
            .removeNote(widget.folder.id, pending.id)
            .catchError((_) {});
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (pickedCopy != null && await pickedCopy.exists()) {
        await pickedCopy.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAudio(LessonNote note) async {
    if (_busy) return;
    setState(() => _busy = true);
    File? temporary;
    try {
      final directory = await Directory(
        '${(await getTemporaryDirectory()).path}/course_audio',
      ).create(recursive: true);
      temporary = File(
        '${directory.path}/${const Uuid().v4()}.${AudioFileTypes.extension('file.${note.audioExtension}')}',
      );
      final file = await CourseVideo.load(
        widget.repository,
        widget.folder.id,
        note,
        temporary,
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => LocalAudioDialog(
            file: file,
            title: note.text,
            allowExternal: true,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendVideo() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    LessonNote? pending;
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final id = const Uuid().v4();
      pending = LessonNote(
        id: id,
        kind: 'video',
        text: _text.text.trim().isEmpty ? picked.name : _text.text,
        created: DateTime.now(),
      );
      final chunks = await CourseVideo.save(
        widget.repository,
        widget.folder.id,
        id,
        picked,
      );
      await widget.repository.add(
        widget.folder.id,
        LessonNote(
          id: id,
          kind: 'video',
          text: pending.text,
          created: pending.created,
          videoChunks: chunks,
        ),
      );
      pending = null;
      if (mounted) {
        setState(() {
          _text.clear();
          _stream = widget.repository.notes(widget.folder.id);
        });
      }
    } catch (error) {
      if (pending != null) {
        await CourseVideo.remove(
          widget.repository,
          widget.folder.id,
          pending,
        ).catchError((_) {});
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openVideo(LessonNote note) async {
    if (_busy) return;
    setState(() => _busy = true);
    File? temporary;
    try {
      final directory = await Directory(
        '${(await getTemporaryDirectory()).path}/course_video',
      ).create(recursive: true);
      temporary = File('${directory.path}/${const Uuid().v4()}.mp4');
      final file = await CourseVideo.load(
        widget.repository,
        widget.folder.id,
        note,
        temporary,
      );
      if (mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => PrivateVideoScreen(file: file)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  late Stream<List<LessonFolder>> _topics = widget.repository.folders(
    parent: widget.folder.id,
  );

  Future<void> _createTopic() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni konu klasörü'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Konu adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (title == null || title.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.create(title, parent: widget.folder.id);
      if (mounted) {
        setState(
          () => _topics = widget.repository.folders(parent: widget.folder.id),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _topicFolders(AsyncSnapshot<List<LessonFolder>> snapshot) {
    final folders = [...?snapshot.data]
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return searchText(a.title).compareTo(searchText(b.title));
      });
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Konular')),
              TextButton.icon(
                onPressed: _busy ? null : _createTopic,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Konu ekle'),
              ),
            ],
          ),
          if (snapshot.hasError)
            const Text('Konular yüklenemedi. Yeniden açmayı dene.'),
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData)
            const LinearProgressIndicator(),
          for (final folder in folders)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.folder,
                color: courseFolderColors[folder.color],
              ),
              title: Text(folder.title),
              trailing: CourseFolderColorButton(
                repository: widget.repository,
                folder: folder,
                enabled: !_busy,
                onChanged: () => setState(
                  () => _topics = widget.repository.folders(
                    parent: widget.folder.id,
                  ),
                ),
              ),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => CourseNotesScreen(
                    repository: widget.repository,
                    folder: folder,
                  ),
                ),
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _send({bool image = false}) async {
    if (_busy || (!image && _text.text.trim().isEmpty)) return;
    setState(() => _busy = true);
    try {
      final body = _text.text;
      if (body.length > 50000) {
        throw Exception('Bir not en fazla 50.000 karakter olabilir.');
      }
      List<XFile> photos = [];
      if (image) {
        FocusScope.of(context).unfocus();
        photos = await ImagePicker().pickMultiImage(requestFullMetadata: false);
        if (photos.isEmpty) return;
        for (final picked in photos) {
          if (await picked.length() > 20 * 1024 * 1024) {
            throw Exception('Görsel en fazla 20 MB olabilir.');
          }
        }
      }
      var saved = 0;
      final albumId = photos.length > 1 ? const Uuid().v4() : null;
      try {
        for (var index = 0; index < (image ? photos.length : 1); index++) {
          String? photo;
          final id = const Uuid().v4();
          if (image) {
            final picked = photos[index];
            var bytes = await picked.readAsBytes();
            if (widget.repository.shared) {
              bytes = await compressToFit(bytes);
              photo = base64Encode(bytes);
            } else {
              final file = await (widget.repository as LocalCourseRepository)
                  .imageFile(id);
              await file.writeAsBytes(bytes, flush: true);
              photo = id;
            }
          }
          final note = LessonNote(
            id: id,
            kind: image ? 'image' : _kind,
            text: index == 0 ? body : '',
            image: photo,
            albumId: albumId,
            created: DateTime.now(),
          );
          try {
            await widget.repository.add(widget.folder.id, note);
          } catch (_) {
            if (photo != null && !widget.repository.shared) {
              final file = await (widget.repository as LocalCourseRepository)
                  .imageFile(id);
              if (await file.exists()) await file.delete();
            }
            rethrow;
          }
          saved++;
        }
      } finally {
        if (mounted && saved > 0) {
          _text.clear();
          setState(() => _stream = widget.repository.notes(widget.folder.id));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(LessonNote note) async {
    final controller = TextEditingController(text: note.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notu düzenle'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 12,
            maxLength: 50000,
            style: note.kind == 'code'
                ? const TextStyle(fontFamily: 'monospace')
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (text == null || text == note.text || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.editText(widget.folder.id, note.id, text);
      if (mounted) {
        setState(() => _stream = widget.repository.notes(widget.folder.id));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(LessonNote note) async {
    if (!await _confirm(context, 'Bu not silinsin mi?') || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!widget.repository.shared) {
        await ReminderService.cancel(note.id);
      }
      await widget.repository.removeNote(widget.folder.id, note.id);
      if (mounted) {
        setState(() => _stream = widget.repository.notes(widget.folder.id));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pin(LessonNote note) async {
    setState(() => _busy = true);
    try {
      await widget.repository.pinNote(widget.folder.id, note.id, !note.pinned);
      if (mounted) {
        setState(() => _stream = widget.repository.notes(widget.folder.id));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _image(LessonNote note) {
    if (widget.repository.shared) {
      final bytes = base64Decode(note.image!);
      return InkWell(
        onTap: () => showPrivatePhoto(context, bytes),
        child: Image.memory(
          bytes,
          height: 180,
          cacheWidth: 640,
          fit: BoxFit.contain,
        ),
      );
    }
    return FutureBuilder(
      future: (widget.repository as LocalCourseRepository).imageFile(
        note.image!,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 100);
        final file = snapshot.data!;
        return InkWell(
          onTap: () async {
            final bytes = await file.readAsBytes();
            if (context.mounted) await showPrivatePhoto(context, bytes);
          },
          child: Image.file(
            file,
            height: 180,
            cacheWidth: 640,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('Görsel bulunamadı.'),
          ),
        );
      },
    );
  }

  Widget _album(List<LessonNote> photos) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${photos.length} fotoğraf',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: photos.length > 4 ? 4 : photos.length,
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _image(photos[index]),
                  if (index == 3 && photos.length > 4)
                    Material(
                      color: Colors.black54,
                      child: InkWell(
                        onTap: () => _openAlbum(photos),
                        child: Center(
                          child: Text(
                            '+${photos.length - 4}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          for (final photo in photos.where((photo) => photo.text.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                photo.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          TextButton(
            onPressed: () => _openAlbum(photos),
            child: const Text('Fotoğrafları aç'),
          ),
        ],
      ),
    ),
  );

  void _openAlbum(List<LessonNote> photos) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${photos.length} fotoğraf')),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) => Column(
              children: [
                _image(photos[index]),
                if (photos[index].text.isNotEmpty)
                  CourseNoteText(photos[index].text),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _edit(photos[index]);
                          if (context.mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Açıklamayı düzenle'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await _delete(photos[index]);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Bu fotoğrafı sil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.folder.title),
      actions: [
        IconButton(
          tooltip: 'Konu klasörlerini yönet',
          icon: const Icon(Icons.folder_copy_outlined),
          onPressed: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CourseFoldersScreen(
                  repository: widget.repository,
                  parent: widget.folder,
                ),
              ),
            );
            if (mounted) {
              setState(
                () => _topics = widget.repository.folders(
                  parent: widget.folder.id,
                ),
              );
            }
          },
        ),
        IconButton(
          tooltip: 'Notlarda ara',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _query.clear();
          }),
        ),
      ],
    ),
    body: StreamBuilder<List<LessonFolder>>(
      stream: _topics,
      builder: (context, topicsSnapshot) => Column(
        children: [
          if (_showSearch || _query.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Bu klasördeki notlarda ara',
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<LessonNote>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Notlar yüklenemedi. Yeniden açmayı dene.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final notes =
                    snapshot.data!
                        .where(
                          (note) => searchText(
                            note.text,
                          ).contains(searchText(_query.text.trim())),
                        )
                        .toList()
                      ..sort((a, b) {
                        final order = a.created.compareTo(b.created);
                        return order != 0 ? order : a.id.compareTo(b.id);
                      });
                for (final note in snapshot.data!) {
                  if ((note.kind == 'video' || note.kind == 'audio') &&
                      courseVideoExpired(note) &&
                      _cleanedVideos.add(note.id)) {
                    CourseVideo.remove(
                      widget.repository,
                      widget.folder.id,
                      note,
                    ).catchError((_) {
                      _cleanedVideos.remove(note.id);
                    });
                  }
                }
                final groups = <List<LessonNote>>[];
                for (final note in notes) {
                  if (note.kind == 'image' &&
                      note.albumId != null &&
                      groups.isNotEmpty &&
                      groups.last.last.kind == 'image' &&
                      groups.last.last.albumId == note.albumId) {
                    groups.last.add(note);
                  } else {
                    groups.add([note]);
                  }
                }
                return ListView.builder(
                  reverse: false,
                  padding: const EdgeInsets.all(12),
                  itemCount: groups.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return KeyedSubtree(
                        key: const ValueKey('topics'),
                        child: _topicFolders(topicsSnapshot),
                      );
                    }
                    index--;
                    if (groups[index].length > 1) {
                      return KeyedSubtree(
                        key: ValueKey(groups[index].first.albumId),
                        child: _album(groups[index]),
                      );
                    }
                    final note = groups[index].first;
                    final long =
                        note.text.length > 700 ||
                        '\n'.allMatches(note.text).length >= 10;
                    final expanded = _expandedNotes.contains(note.id);
                    final preview = note.text.split('\n').take(10).join('\n');
                    final shown = long && !expanded
                        ? '${preview.substring(0, preview.length > 700 ? 700 : preview.length)}…'
                        : note.text;
                    return Card(
                      key: ValueKey(note.id),
                      margin: const EdgeInsets.only(bottom: 18),
                      shape: note.kind == 'announcement'
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.tertiary,
                                width: 2,
                              ),
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (note.kind == 'announcement')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.campaign,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.tertiary,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Önemli duyuru!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Text(
                              note.kind == 'code'
                                  ? 'Kod'
                                  : note.kind == 'announcement'
                                  ? 'Ders duyurusu'
                                  : note.kind == 'image'
                                  ? 'Görsel not'
                                  : 'Not',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 12),
                            if (note.kind == 'audio')
                              TextButton.icon(
                                onPressed:
                                    _busy ||
                                        courseVideoExpired(note) ||
                                        (widget.repository.shared &&
                                            note.videoChunks == 0)
                                    ? null
                                    : () => _openAudio(note),
                                icon: const Icon(Icons.headphones),
                                label: Text(
                                  courseVideoExpired(note)
                                      ? 'Ses dosyasının bir haftalık süresi doldu'
                                      : widget.repository.shared &&
                                            note.videoChunks == 0
                                      ? 'Ses yükleniyor…'
                                      : 'Sesi dinle · 1 hafta saklanır',
                                ),
                              ),
                            if (note.kind == 'video')
                              TextButton.icon(
                                onPressed:
                                    _busy ||
                                        courseVideoExpired(note) ||
                                        (widget.repository.shared &&
                                            note.videoChunks == 0)
                                    ? null
                                    : () => _openVideo(note),
                                icon: const Icon(Icons.play_circle_outline),
                                label: Text(
                                  courseVideoExpired(note)
                                      ? 'Videonun bir haftalık süresi doldu'
                                      : widget.repository.shared &&
                                            note.videoChunks == 0
                                      ? 'Video yükleniyor…'
                                      : 'Videoyu izle · 1 hafta saklanır',
                                ),
                              ),
                            if (note.image != null) _image(note),
                            if (note.image != null) const SizedBox(height: 12),
                            if (note.text.isNotEmpty)
                              note.kind == 'code'
                                  ? SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SelectableText(
                                        shown,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                      ),
                                    )
                                  : CourseNoteText(shown),
                            if (long)
                              TextButton(
                                onPressed: () => setState(() {
                                  if (expanded) {
                                    _expandedNotes.remove(note.id);
                                  } else {
                                    _expandedNotes.add(note.id);
                                  }
                                }),
                                child: Text(
                                  expanded ? 'Daha az göster' : 'Devamını oku',
                                ),
                              ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            Wrap(
                              children: [
                                TextButton.icon(
                                  onPressed: _busy ? null : () => _edit(note),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Düzenle'),
                                ),
                                IconButton(
                                  tooltip: note.pinned
                                      ? 'Sabitlemeyi kaldır'
                                      : 'Notu sabitle',
                                  onPressed: _busy ? null : () => _pin(note),
                                  icon: Icon(
                                    note.pinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                  ),
                                ),
                                if (note.text.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: note.text),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Kopyalandı.'),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.copy, size: 16),
                                    label: const Text('Kopyala'),
                                  ),
                                if (!widget.repository.shared)
                                  IconButton(
                                    tooltip: 'Hatırlatıcı kur',
                                    onPressed: _busy
                                        ? null
                                        : () => ReminderService.pick(
                                            context,
                                            note.id,
                                          ),
                                    icon: const Icon(Icons.alarm_add),
                                  ),
                                IconButton(
                                  tooltip: 'Notu sil',
                                  onPressed: _busy ? null : () => _delete(note),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<String>(
                        isDense: true,
                        value: _kind,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _kind = v!),
                        items: const [
                          DropdownMenuItem(value: 'text', child: Text('Not')),
                          DropdownMenuItem(value: 'code', child: Text('Kod')),
                          DropdownMenuItem(
                            value: 'announcement',
                            child: Text('Duyuru'),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Fotoğraflar ekle',
                        onPressed: _busy ? null : () => _send(image: true),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                      IconButton(
                        tooltip: 'Ses dosyası ekle (Drive / cihaz)',
                        onPressed: _busy ? null : _sendAudio,
                        icon: const Icon(Icons.audio_file_outlined),
                      ),
                      IconButton(
                        tooltip: 'Ders videosu ekle',
                        onPressed: _busy ? null : _sendVideo,
                        icon: const Icon(Icons.video_library_outlined),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          enabled: !_busy,
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 50000,
                          decoration: const InputDecoration(
                            hintText: 'Notunu yaz…',
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Notu ekle',
                        onPressed: _busy ? null : () => _send(),
                        icon: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Silme onayı'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    ) ==
    true;
