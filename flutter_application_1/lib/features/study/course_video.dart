import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../media/chat_media.dart';
import 'course_repository.dart';

const courseVideoLifetime = Duration(days: 7);
bool courseVideoExpired(LessonNote note) =>
    !note.created.add(courseVideoLifetime).isAfter(DateTime.now());

class CourseVideo {
  static DocumentReference<Map<String, dynamic>> _entry(
    SharedCourseRepository repo,
    String folder,
    String id,
  ) => FirebaseFirestore.instance
      .collection('couples')
      .doc(repo.coupleId)
      .collection('courses')
      .doc(folder)
      .collection('entries')
      .doc(id);
  static Future<File> localFile(LocalCourseRepository repo, String id) async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw Exception('Video kaydı geçersiz.');
    }
    return File('${(await repo.directory()).path}/$id.mp4');
  }

  static Future<int> save(
    CourseRepository repo,
    String folder,
    String id,
    XFile source,
  ) async {
    final size = await source.length();
    if (size < 1 || size > maxChatVideoBytes) {
      throw Exception('Ders videosu en fazla 100 MB olabilir.');
    }
    if (repo is LocalCourseRepository) {
      await File(source.path).copy((await localFile(repo, id)).path);
      return 0;
    }
    final shared = repo as SharedCourseRepository;
    // Keep an expiring parent record even if the app stops during upload.
    await shared.add(
      folder,
      LessonNote(
        id: id,
        kind: 'video',
        text: 'Video yükleniyor…',
        created: DateTime.now(),
      ),
    );
    final input = await File(source.path).open();
    var count = 0;
    try {
      while (true) {
        final bytes = await input.read(mediaChunkBytes);
        if (bytes.isEmpty) break;
        final encrypted = await compute(transformMediaChunk, {
          'bytes': bytes,
          'secret': shared.secret,
        });
        await _entry(
          shared,
          folder,
          id,
        ).collection('chunks').doc('$count').set({
          'bytes': Blob(encrypted['bytes'] as Uint8List),
          'iv': Blob(encrypted['iv'] as Uint8List),
        });
        count++;
      }
      return count;
    } catch (_) {
      final rows = await _entry(shared, folder, id).collection('chunks').get();
      for (final row in rows.docs) {
        await row.reference.delete();
      }
      await shared.removeNote(folder, id);
      rethrow;
    } finally {
      await input.close();
    }
  }

  static Future<void> remove(
    CourseRepository repo,
    String folder,
    LessonNote note,
  ) async {
    if (repo is LocalCourseRepository) {
      final file = await localFile(repo, note.id);
      if (await file.exists()) await file.delete();
    } else {
      final rows = await _entry(
        repo as SharedCourseRepository,
        folder,
        note.id,
      ).collection('chunks').get();
      for (final row in rows.docs) {
        await row.reference.delete();
      }
    }
  }

  static Future<File> load(
    CourseRepository repo,
    String folder,
    LessonNote note,
    File destination,
  ) async {
    if (courseVideoExpired(note)) {
      throw Exception('Videonun bir haftalık erişim süresi doldu.');
    }
    if (repo is LocalCourseRepository) {
      final file = await localFile(repo, note.id);
      if (!await file.exists()) throw Exception('Video artık bulunamıyor.');
      return file;
    }
    if (note.videoChunks < 1 ||
        note.videoChunks > (maxChatVideoBytes / mediaChunkBytes).ceil()) {
      throw Exception('Video kaydı geçersiz.');
    }
    final shared = repo as SharedCourseRepository;
    final output = destination.openWrite();
    try {
      for (var i = 0; i < note.videoChunks; i++) {
        final data = (await _entry(
          shared,
          folder,
          note.id,
        ).collection('chunks').doc('$i').get()).data();
        if (data == null) throw Exception('Video eksik veya silinmiş.');
        final decoded = await compute(transformMediaChunk, {
          'bytes': (data['bytes'] as Blob).bytes,
          'iv': (data['iv'] as Blob).bytes,
          'secret': shared.secret,
          'decrypt': true,
        });
        output.add(decoded['bytes'] as Uint8List);
      }
    } finally {
      await output.close();
    }
    return destination;
  }
}
