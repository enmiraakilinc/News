import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../pair/couple_service.dart';
import '../../core/utils/search_text.dart';
import '../media/audio_file_types.dart';

class LessonFolder {
  final String id, title;
  final bool pinned;
  final String? color;
  const LessonFolder(this.id, this.title, {this.pinned = false, this.color});
}

class LessonNote {
  final String id, kind, text;
  final String? image;
  final String? albumId;
  final int videoChunks;
  final String audioExtension;
  final DateTime created;
  final bool pinned;
  const LessonNote({
    required this.id,
    required this.kind,
    required this.text,
    this.image,
    this.albumId,
    this.videoChunks = 0,
    this.audioExtension = 'm4a',
    required this.created,
    this.pinned = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'text': text,
    if (image != null) 'image': image,
    if (albumId != null) 'albumId': albumId,
    if (kind == 'video' || kind == 'audio') 'videoChunks': videoChunks,
    if (kind == 'audio') 'audioExtension': audioExtension,
    'created': created.toIso8601String(),
    'pinned': pinned,
  };
  factory LessonNote.fromJson(Map<String, dynamic> d) => LessonNote(
    id: d['id'] as String,
    kind: d['kind'] as String,
    text: d['text'] as String,
    image: d['image'] as String?,
    albumId: d['albumId'] as String?,
    videoChunks: (d['videoChunks'] as num?)?.toInt() ?? 0,
    audioExtension: d['audioExtension'] as String? ?? 'm4a',
    created: DateTime.parse(d['created'] as String),
    pinned: d['pinned'] == true,
  );
}

abstract class CourseRepository {
  bool get shared;
  Stream<List<LessonFolder>> folders({String? parent});
  Stream<List<LessonNote>> notes(String course);
  Future<void> create(String title, {String? parent});
  Future<void> add(String course, LessonNote note);
  Future<void> removeNote(String course, String note);
  Future<void> removeCourse(String course);
  Future<void> pinFolder(String id, bool pinned);
  Future<void> pinNote(String course, String note, bool pinned);
  Future<void> colorFolder(String id, String? color) =>
      Future.error(UnsupportedError('Klasör rengi değiştirilemiyor.'));
  Future<void> editText(String course, String note, String text) =>
      Future.error(UnsupportedError('Not düzenlenemiyor.'));
  Future<List<CourseSearchHit>> search(
    String query, {
    LessonFolder? root,
  }) async {
    final term = searchText(query.trim());
    if (term.isEmpty) return [];
    final pending = root == null ? [...await folders().first] : [root];
    final visited = <String>{};
    final results = <CourseSearchHit>[];
    while (pending.isNotEmpty) {
      final folder = pending.removeLast();
      if (!visited.add(folder.id)) continue;
      if (searchText(folder.title).contains(term)) {
        results.add(CourseSearchHit(folder));
      }
      for (final note in await notes(folder.id).first) {
        if (searchText(note.text).contains(term)) {
          results.add(CourseSearchHit(folder, note));
        }
      }
      pending.addAll(await folders(parent: folder.id).first);
    }
    return results;
  }
}

class CourseSearchHit {
  final LessonFolder folder;
  final LessonNote? note;
  CourseSearchHit(this.folder, [this.note]);
}

class LocalCourseRepository extends CourseRepository {
  final String owner;
  final Directory? root;
  LocalCourseRepository(this.owner, {this.root});
  Future<File> imageFile(String id) async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw Exception('Geçersiz görsel.');
    }
    return File('${(await directory()).path}/$id.jpg');
  }

  @override
  bool get shared => false;
  Future<Directory> directory() async {
    final app = root ?? await getApplicationSupportDirectory();
    final account = sha256.convert(utf8.encode(owner)).toString();
    return Directory(
      '${app.path}/personal_courses/$account',
    ).create(recursive: true);
  }

  Future<Map<String, dynamic>> _read() async {
    final file = File('${(await directory()).path}/courses.json');
    if (!await file.exists()) return {};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final target = File('${(await directory()).path}/courses.json');
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename(target.path);
  }

  @override
  Stream<List<LessonFolder>> folders({String? parent}) async* {
    final data = await _read();
    yield data.entries
        .where((e) => (e.value as Map)['parent'] == parent)
        .map(
          (e) => LessonFolder(
            e.key,
            (e.value as Map)['title'] as String,
            pinned: (e.value as Map)['pinned'] == true,
            color: (e.value as Map)['color'] as String?,
          ),
        )
        .toList();
  }

  @override
  Stream<List<LessonNote>> notes(String course) async* {
    final data = await _read();
    final row = data[course] as Map?;
    yield ((row?['notes'] as List?) ?? [])
        .map((e) => LessonNote.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> create(String title, {String? parent}) async {
    if (title.trim().isEmpty || title.length > 100) {
      throw Exception('Ders adı 1–100 karakter olmalı.');
    }
    final data = await _read();
    if (parent != null && !data.containsKey(parent)) {
      throw Exception('Üst klasör bulunamadı.');
    }
    data[const Uuid().v4()] = {
      'title': title.trim(),
      'notes': [],
      'parent': parent,
    };
    await _write(data);
  }

  @override
  Future<void> add(String course, LessonNote note) async {
    final data = await _read();
    final row = data[course] as Map?;
    if (row == null) throw Exception('Ders klasörü bulunamadı.');
    (row['notes'] as List).add(note.toJson());
    await _write(data);
  }

  @override
  Future<void> pinFolder(String id, bool pinned) async {
    final data = await _read();
    final folder = data[id] as Map?;
    if (folder == null) throw Exception('Klasör bulunamadı.');
    folder['pinned'] = pinned;
    await _write(data);
  }

  @override
  Future<void> colorFolder(String id, String? color) async {
    final data = await _read();
    final folder = data[id] as Map?;
    if (folder == null) throw Exception('Klasör bulunamadı.');
    folder['color'] = color;
    await _write(data);
  }

  @override
  Future<void> editText(String course, String note, String text) async {
    if (text.length > 50000) {
      throw Exception('Not en fazla 50.000 karakter olabilir.');
    }
    final data = await _read();
    final rows = ((data[course] as Map?)?['notes'] as List?) ?? [];
    final matches = rows.where((row) => (row as Map)['id'] == note);
    if (matches.isEmpty) throw Exception('Not bulunamadı.');
    (matches.first as Map)['text'] = text;
    await _write(data);
  }

  @override
  Future<void> pinNote(String course, String note, bool pinned) async {
    final data = await _read();
    final rows = ((data[course] as Map?)?['notes'] as List?) ?? [];
    final matches = rows.where((row) => (row as Map)['id'] == note);
    if (matches.isEmpty) throw Exception('Not bulunamadı.');
    (matches.first as Map)['pinned'] = pinned;
    await _write(data);
  }

  Future<Uint8List> exportBackup() async => compute(_personalBackup, {
    'data': await _read(),
    'directory': (await directory()).path,
  });

  @override
  Future<void> removeNote(String course, String note) async {
    final data = await _read();
    final row = data[course] as Map?;
    if (row == null) return;
    final old = (row['notes'] as List)
        .where((e) => (e as Map)['id'] == note)
        .toList();
    (row['notes'] as List).removeWhere((e) => (e as Map)['id'] == note);
    await _write(data);
    for (final entry in old) {
      if (['video', 'audio'].contains((entry as Map)['kind']) &&
          RegExp(r'^[a-f0-9-]{36}$').hasMatch(note)) {
        final ext = entry['kind'] == 'audio'
            ? AudioFileTypes.extension(
                'file.${entry['audioExtension'] ?? 'm4a'}',
              )
            : 'mp4';
        final video = File('${(await directory()).path}/$note.$ext');
        if (await video.exists()) await video.delete();
      }
      final image = entry['image'];
      if (image is String) {
        final file = await imageFile(image);
        if (await file.exists()) await file.delete();
      }
    }
  }

  @override
  Future<void> removeCourse(String course) async {
    final data = await _read();
    final ids = <String>{course};
    bool changed;
    do {
      changed = false;
      for (final entry in data.entries) {
        if (ids.contains((entry.value as Map)['parent']) &&
            ids.add(entry.key)) {
          changed = true;
        }
      }
    } while (changed);
    final removed = [for (final id in ids) data.remove(id) as Map?];
    await _write(data);
    for (final old in removed) {
      for (final note in (old?['notes'] as List?) ?? []) {
        if (['video', 'audio'].contains((note as Map)['kind']) &&
            RegExp(r'^[a-f0-9-]{36}$').hasMatch(note['id'] as String)) {
          final ext = note['kind'] == 'audio'
              ? AudioFileTypes.extension(
                  'file.${note['audioExtension'] ?? 'm4a'}',
                )
              : 'mp4';
          final video = File('${(await directory()).path}/${note['id']}.$ext');
          if (await video.exists()) await video.delete();
        }
        final image = note['image'];
        if (image is String) {
          final file = await imageFile(image);
          if (await file.exists()) await file.delete();
        }
      }
    }
  }
}

class SharedCourseRepository extends CourseRepository {
  final String coupleId, secret;
  SharedCourseRepository(this.coupleId, this.secret);
  @override
  bool get shared => true;
  CollectionReference<Map<String, dynamic>> get _courses => FirebaseFirestore
      .instance
      .collection('couples')
      .doc(coupleId)
      .collection('courses');
  String _seal(String text) => CoupleService.encodePrivateText(text, secret);
  String _open(String text) => CoupleService.decodePrivateText(text, secret);
  @override
  Stream<List<LessonFolder>> folders({String? parent}) async* {
    await CoupleService.ensureReady();
    yield* _courses
        .orderBy('createdAt')
        .snapshots()
        .map(
          (s) => s.docs
              .where((d) => d.data()['parent'] == parent)
              .map(
                (d) => LessonFolder(
                  d.id,
                  _open(d.data()['titleCipher'] as String),
                  pinned: d.data()['pinned'] == true,
                  color: d.data()['color'] as String?,
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<List<LessonNote>> notes(String course) async* {
    await CoupleService.ensureReady();
    yield* _courses
        .doc(course)
        .collection('entries')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => LessonNote.fromJson(
                  jsonDecode(_open(d.data()['cipher'] as String))
                      as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  @override
  Future<void> create(String title, {String? parent}) async {
    if (title.trim().isEmpty || title.length > 100) {
      throw Exception('Ders adı 1–100 karakter olmalı.');
    }
    await CoupleService.ensureReady();
    final ref = _courses.doc();
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      if (parent != null) {
        final folder = await transaction.get(_courses.doc(parent));
        if (!folder.exists || folder.data()?['deleting'] == true) {
          throw Exception('Üst klasör silinmiş veya siliniyor.');
        }
      }
      transaction.set(ref, {
        'owner': CoupleService.uid,
        'titleCipher': _seal(title.trim()),
        'createdAt': FieldValue.serverTimestamp(),
        'parent': parent,
      });
    });
  }

  @override
  Future<void> add(String course, LessonNote note) async {
    await CoupleService.ensureReady();
    final cipher = _seal(jsonEncode(note.toJson()));
    if (utf8.encode(cipher).length > 1000000) {
      throw Exception(
        'Görsel ve açıklama birlikte çok büyük. Açıklamayı kısalt veya daha küçük bir görsel seç.',
      );
    }
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final parent = await transaction.get(_courses.doc(course));
      if (!parent.exists || parent.data()?['deleting'] == true) {
        throw Exception('Ders klasörü silinmiş veya siliniyor.');
      }
      transaction.set(_courses.doc(course).collection('entries').doc(note.id), {
        'owner': CoupleService.uid,
        'cipher': cipher,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> removeNote(String course, String note) async {
    await CoupleService.ensureReady();
    final entry = _courses.doc(course).collection('entries').doc(note);
    await _deleteCourseVideoChunks(entry);
    await entry.delete();
  }

  @override
  Future<void> pinFolder(String id, bool pinned) async {
    await CoupleService.ensureReady();
    await _courses.doc(id).update({'pinned': pinned});
  }

  @override
  Future<void> pinNote(String course, String note, bool pinned) async {
    await CoupleService.ensureReady();
    final ref = _courses.doc(course).collection('entries').doc(note);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw Exception('Not bulunamadı.');
      final data =
          jsonDecode(_open(snapshot.data()!['cipher'] as String))
              as Map<String, dynamic>;
      data['pinned'] = pinned;
      final cipher = _seal(jsonEncode(data));
      if (utf8.encode(cipher).length > 1000000) {
        throw Exception('Bu not çok büyük; sabitlenemedi.');
      }
      transaction.update(ref, {'cipher': cipher});
    });
  }

  @override
  Future<void> colorFolder(String id, String? color) async {
    await CoupleService.ensureReady();
    await _courses.doc(id).update({'color': color});
  }

  @override
  Future<void> editText(String course, String note, String text) async {
    if (text.length > 50000) {
      throw Exception('Not en fazla 50.000 karakter olabilir.');
    }
    await CoupleService.ensureReady();
    final ref = _courses.doc(course).collection('entries').doc(note);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw Exception('Not bulunamadı.');
      final data =
          jsonDecode(_open(snapshot.data()!['cipher'] as String))
              as Map<String, dynamic>;
      data['text'] = text;
      final cipher = _seal(jsonEncode(data));
      if (utf8.encode(cipher).length > 1000000) {
        throw Exception('Not çok büyük. Metni biraz kısalt.');
      }
      transaction.update(ref, {'cipher': cipher});
    });
  }

  @override
  Future<void> removeCourse(String course) async {
    await CoupleService.ensureReady();
    // Paginate so a large course never exceeds a Firestore batch limit.
    final ref = _courses.doc(course);
    await ref.update({'deleting': true});
    // Mark the parent first: no new direct children can race this deletion.
    final children = await _courses.where('parent', isEqualTo: course).get();
    for (final child in children.docs) {
      await removeCourse(child.id);
    }
    while (true) {
      final entries = await ref.collection('entries').limit(100).get();
      if (entries.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final entry in entries.docs) {
        await _deleteCourseVideoChunks(entry.reference);
        batch.delete(entry.reference);
      }
      await batch.commit();
    }
    await ref.delete();
  }
}

Future<void> _deleteCourseVideoChunks(
  DocumentReference<Map<String, dynamic>> entry,
) async {
  final chunks = await entry.collection('chunks').get();
  if (chunks.docs.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  for (final chunk in chunks.docs) {
    batch.delete(chunk.reference);
  }
  await batch.commit();
}

Uint8List _personalBackup(Map<String, dynamic> input) {
  final data = input['data'] as Map<String, dynamic>;
  final photos = <String, String>{};
  var size = 0;
  for (final folder in data.values) {
    for (final note in ((folder as Map)['notes'] as List?) ?? []) {
      final image = (note as Map)['image'];
      if (image is! String || photos.containsKey(image)) continue;
      if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(image)) {
        throw Exception('Yedekte geçersiz görsel kaydı var.');
      }
      final file = File('${input['directory']}/$image.jpg');
      if (!file.existsSync()) {
        throw Exception(
          'Bir notun görseli bulunamadı; eksiksiz yedek oluşturulamadı.',
        );
      }
      size += file.lengthSync();
      if (size > 50 * 1024 * 1024) {
        throw Exception(
          'Görseller toplamda 50 MB sınırını aştı. Yedek çok büyük.',
        );
      }
      photos[image] = base64Encode(file.readAsBytesSync());
    }
  }
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'neural-personal-courses',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'folders': data,
        'images': photos,
      }),
    ),
  );
}
