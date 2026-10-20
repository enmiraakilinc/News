import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/features/study/course_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_application_1/features/study/course_note_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/study/course_repository.dart';
import 'package:flutter_application_1/features/study/course_screen.dart';
import 'package:flutter_application_1/features/study/course_folder_color.dart';
import 'package:flutter_application_1/features/pair/couple_service.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('neural_courses_test_');
  });
  tearDown(() async {
    if (root.absolute.path.startsWith(Directory.systemTemp.absolute.path) &&
        root.path.contains('neural_courses_test_')) {
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'Announcement editing saves the existing note and keeps its position',
    (tester) async {
      final repo = _EditableCourseRepository(
        LessonNote(
          id: 'announcement',
          kind: 'announcement',
          text: 'Sınav pazartesi',
          created: DateTime(2026, 10, 18),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CourseNotesScreen(
            repository: repo,
            folder: const LessonFolder('course', 'Ders'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Önemli duyuru!'), findsOneWidget);
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Sınav pazartesi'),
        'Sınav salı',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Sınav salı'), findsOneWidget);
      expect(find.text('Sınav pazartesi'), findsNothing);
      expect(repo.edited?.id, 'announcement');
      expect(repo.edited?.created, DateTime(2026, 10, 18));
    },
  );
  testWidgets(
    'Folder palette saves the chosen color and refreshes its folder',
    (tester) async {
      final repo = _EditableCourseRepository(
        LessonNote(id: 'n', kind: 'text', text: '', created: DateTime(2026)),
      );
      var refreshed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseFolderColorButton(
              repository: repo,
              folder: const LessonFolder('folder', 'Ders'),
              onChanged: () => refreshed = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Klasör rengini değiştir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeşil'));
      await tester.pumpAndSettle();
      expect(repo.savedColor, 'Yeşil');
      expect(refreshed, isTrue);
    },
  );
  test(
    'Folder colors and edited note text survive reopening without moving or losing media',
    () async {
      final repo = LocalCourseRepository('colors-edit', root: root);
      await repo.create('Ders');
      final folder = (await repo.folders().first).single;
      await repo.create('Konu', parent: folder.id);
      final topic = (await repo.folders(parent: folder.id).first).single;
      await repo.colorFolder(folder.id, 'Mavi');
      await repo.colorFolder(topic.id, 'Sarı');
      final created = DateTime(2026, 10, 18);
      await repo.add(
        topic.id,
        LessonNote(
          id: 'first',
          kind: 'image',
          text: 'Eski açıklama',
          image: 'photo-id',
          albumId: 'album',
          created: created,
          pinned: true,
        ),
      );
      await repo.add(
        topic.id,
        LessonNote(
          id: 'second',
          kind: 'code',
          text: 'second',
          created: created.add(const Duration(minutes: 1)),
        ),
      );
      await repo.editText(topic.id, 'first', 'Yeni açıklama');
      final reopened = LocalCourseRepository('colors-edit', root: root);
      expect((await reopened.folders().first).single.color, 'Mavi');
      expect(
        (await reopened.folders(parent: folder.id).first).single.color,
        'Sarı',
      );
      final notes = await reopened.notes(topic.id).first;
      expect(notes.map((n) => n.id), ['first', 'second']);
      expect(notes.first.text, 'Yeni açıklama');
      expect(notes.first.created, created);
      expect(notes.first.image, 'photo-id');
      expect(notes.first.albumId, 'album');
      expect(notes.first.pinned, isTrue);
      await reopened.colorFolder(folder.id, null);
      expect((await reopened.folders().first).single.color, isNull);
    },
  );
  testWidgets(
    'Topics are visible directly inside the course and open in one tap',
    (tester) async {
      final repo = _TopicCourseRepository();
      const parent = LessonFolder('course', 'Program yapısı');
      await tester.pumpWidget(
        MaterialApp(
          home: CourseNotesScreen(repository: repo, folder: parent),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Tokenizer'), findsOneWidget);
      expect(find.text('Konu klasörleri'), findsNothing);
      await tester.tap(find.text('Tokenizer'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Tokenizer'), findsOneWidget);
    },
  );
  test(
    'Personal course videos preserve bytes, expire after a week and are removed with their folder',
    () async {
      final repo = LocalCourseRepository('alice', root: root);
      await repo.create('Ders');
      final folder = (await repo.folders().first).single;
      final source = File('${root.path}/source.mp4');
      await source.writeAsBytes([1, 2, 3, 4]);
      const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      final chunks = await CourseVideo.save(
        repo,
        folder.id,
        id,
        XFile(source.path),
      );
      final note = LessonNote(
        id: id,
        kind: 'video',
        text: 'Video',
        created: DateTime.now(),
        videoChunks: chunks,
      );
      await repo.add(folder.id, note);
      final reloaded = (await repo.notes(folder.id).first).single;
      final video = await CourseVideo.load(
        repo,
        folder.id,
        reloaded,
        File('${root.path}/unused.mp4'),
      );
      expect(await video.readAsBytes(), [1, 2, 3, 4]);
      await expectLater(
        CourseVideo.load(
          repo,
          folder.id,
          LessonNote(
            id: id,
            kind: 'video',
            text: '',
            created: DateTime.now().subtract(const Duration(days: 8)),
          ),
          File('${root.path}/unused.mp4'),
        ),
        throwsException,
      );
      await repo.removeCourse(folder.id);
      expect(await video.exists(), isFalse);
      expect(await source.exists(), isTrue);
    },
  );
  testWidgets(
    'Note links open only on tap and preserve the full selectable text',
    (tester) async {
      Uri? opened;
      const text = 'Ders: https://example.com/tokenizer).';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseNoteText(
              text,
              openLink: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
        ),
      );
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.textSpan!.toPlainText(), text);
      expect(opened, isNull);
      final link = selectable.textSpan!.children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.recognizer != null);
      (link.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(opened.toString(), 'https://example.com/tokenizer');
    },
  );
  test(
    'Photo album identity persists without changing legacy image notes',
    () async {
      final repo = LocalCourseRepository('alice', root: root);
      await repo.create('Ders');
      final folder = (await repo.folders().first).single;
      for (var i = 0; i < 2; i++) {
        await repo.add(
          folder.id,
          LessonNote(
            id: 'album-photo-$i',
            kind: 'image',
            text: i == 0 ? 'Ders görselleri' : '',
            image: null,
            albumId: 'selection-1',
            created: DateTime(2026, 10, 17, 12, i),
          ),
        );
      }
      final reloaded = await LocalCourseRepository(
        'alice',
        root: root,
      ).notes(folder.id).first;
      expect(reloaded.map((note) => note.albumId), everyElement('selection-1'));
      final legacy = reloaded.first.toJson()..remove('albumId');
      expect(LessonNote.fromJson(legacy).albumId, isNull);
    },
  );
  test(
    'Personal courses persist code exactly and stay separate for different accounts',
    () async {
      final repo = LocalCourseRepository('alice', root: root);
      await repo.create('Program yapısı');
      final folder = (await repo.folders().first).single;
      const code =
          'public class Main {\n  // Türkçe açıklama\n  int x = 1;\n}\n';
      await repo.add(
        folder.id,
        LessonNote(
          id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          kind: 'code',
          text: code,
          created: DateTime(2026, 10, 17),
        ),
      );
      final reload = LocalCourseRepository('alice', root: root);
      expect((await reload.notes(folder.id).first).single.text, code);
      expect(
        await LocalCourseRepository('bob', root: root).folders().first,
        isEmpty,
      );
      expect(await reload.folders().first, hasLength(1));
    },
  );
  test(
    'Deleting personal notes removes their owned image without removing other courses',
    () async {
      final repo = LocalCourseRepository('alice', root: root);
      await repo.create('Ders A');
      await repo.create('Ders B');
      final folders = await repo.folders().first;
      const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      final image = await repo.imageFile(id);
      await image.writeAsBytes([1, 2, 3]);
      await repo.add(
        folders[0].id,
        LessonNote(
          id: id,
          kind: 'image',
          text: 'Duyuru',
          image: id,
          created: DateTime.now(),
        ),
      );
      await repo.removeNote(folders[0].id, id);
      expect(await image.exists(), isFalse);
      expect(await repo.notes(folders[0].id).first, isEmpty);
      await expectLater(repo.imageFile('../outside'), throwsException);
      await repo.removeCourse(folders[0].id);
      expect((await repo.folders().first).single.title, 'Ders B');
    },
  );
  test(
    'Nested topics persist, preserve old roots and delete only their own subtree',
    () async {
      final repo = LocalCourseRepository('alice', root: root);
      await repo.create('Program yapısı ve anlamı');
      await repo.create('Diğer ders');
      final roots = await repo.folders().first;
      final course = roots.first;
      await repo.create('Tokenizer', parent: course.id);
      await repo.create('Parse', parent: course.id);
      final topics = await repo.folders(parent: course.id).first;
      await repo.create('Token türleri', parent: topics.first.id);
      final nested = (await repo.folders(parent: topics.first.id).first).single;
      const imageId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      final image = await repo.imageFile(imageId);
      await image.writeAsBytes([1, 2]);
      await repo.add(
        nested.id,
        LessonNote(
          id: imageId,
          kind: 'image',
          text: 'Not',
          image: imageId,
          created: DateTime.now(),
        ),
      );
      final reload = LocalCourseRepository('alice', root: root);
      expect(await reload.folders().first, hasLength(2));
      expect(
        (await reload.folders(parent: course.id).first).map((e) => e.title),
        ['Tokenizer', 'Parse'],
      );
      expect((await reload.notes(nested.id).first).single.text, 'Not');
      await expectLater(
        repo.create('Yetim konu', parent: 'missing'),
        throwsException,
      );
      await repo.removeCourse(topics.first.id);
      expect(await image.exists(), isFalse);
      expect(await repo.folders(parent: topics.first.id).first, isEmpty);
      expect(
        (await repo.folders(parent: course.id).first).single.title,
        'Parse',
      );
      await repo.removeCourse(course.id);
      expect((await repo.folders().first).single.title, 'Diğer ders');
      expect(await repo.folders(parent: course.id).first, isEmpty);
    },
  );
  test(
    'Search includes nested topics and backup preserves images and pins',
    () async {
      final repo = LocalCourseRepository('alice', root: root);
      await repo.create('Program Yapısı');
      final folder = (await repo.folders().first).single;
      await repo.create('Tokenizer', parent: folder.id);
      final topic = (await repo.folders(parent: folder.id).first).single;
      const id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
      await (await repo.imageFile(id)).writeAsBytes([7, 8, 9]);
      await repo.add(
        topic.id,
        LessonNote(
          id: id,
          kind: 'image',
          text: 'Türkçe çözüm ve kod',
          image: id,
          created: DateTime.now(),
        ),
      );
      await repo.pinFolder(folder.id, true);
      await repo.pinNote(topic.id, id, true);
      final reload = LocalCourseRepository('alice', root: root);
      expect((await reload.folders().first).single.pinned, true);
      expect((await reload.notes(topic.id).first).single.pinned, true);
      expect(
        (await reload.search('program yapisi')).single.folder.id,
        folder.id,
      );
      expect((await reload.search('turkce cozum')).single.note!.id, id);
      final backup =
          jsonDecode(utf8.decode(await reload.exportBackup())) as Map;
      expect(backup['format'], 'neural-personal-courses');
      expect((backup['folders'] as Map)[topic.id]['parent'], folder.id);
      expect(base64Decode((backup['images'] as Map)[id]), [7, 8, 9]);
      expect((backup['folders'] as Map)[folder.id]['pinned'], true);
    },
  );
  test(
    'Shared text and folder titles use the existing pair cipher rather than plain storage',
    () {
      const text = 'Program yapısı dersinin notları';
      final sealed = CoupleService.encodePrivateText(text, 'test-only-key');
      expect(sealed, isNot(contains(text)));
      expect(CoupleService.decodePrivateText(sealed, 'test-only-key'), text);
    },
  );
  testWidgets('Course code is selectable and copies the unmodified source', (
    tester,
  ) async {
    final repo = LocalCourseRepository('alice', root: root);
    const text = 'if (true) {\n  print("Merhaba");\n}\n';
    final folder = await tester.runAsync<LessonFolder>(() async {
      await repo.create('Ders');
      final folder = (await repo.folders().first).single;
      await repo.add(
        folder.id,
        LessonNote(
          id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          kind: 'code',
          text: text,
          created: DateTime.now(),
        ),
      );
      return folder;
    });
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CourseNotesScreen(
          repository: _ReadOnlyCourseRepository(
            LessonNote(
              id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              kind: 'code',
              text: text,
              created: DateTime.now(),
            ),
          ),
          folder: folder!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    await tester.tap(find.text('Kopyala'));
    await tester.pumpAndSettle();
    expect(copied, text);
    await tester.tap(find.byTooltip('Konu klasörlerini yönet'));
    await tester.pumpAndSettle();
    expect(find.text('Ders • Konular'), findsOneWidget);
    expect(find.text('Yeni konu klasörü'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
  });
}

class _ReadOnlyCourseRepository extends CourseRepository {
  final LessonNote note;
  _ReadOnlyCourseRepository(this.note);
  @override
  bool get shared => false;
  @override
  Stream<List<LessonNote>> notes(String course) => Stream.value([note]);
  @override
  Stream<List<LessonFolder>> folders({String? parent}) => Stream.value([]);
  @override
  Future<void> create(String title, {String? parent}) =>
      throw UnimplementedError();
  @override
  Future<void> add(String course, LessonNote note) =>
      throw UnimplementedError();
  @override
  Future<void> removeNote(String course, String note) =>
      throw UnimplementedError();
  @override
  Future<void> removeCourse(String course) => throw UnimplementedError();
  @override
  Future<void> pinFolder(String id, bool pinned) => throw UnimplementedError();
  @override
  Future<void> pinNote(String course, String note, bool pinned) =>
      throw UnimplementedError();
}

class _EditableCourseRepository extends _ReadOnlyCourseRepository {
  _EditableCourseRepository(super.note);
  LessonNote? edited;
  String? savedColor;
  @override
  Stream<List<LessonNote>> notes(String course) =>
      Stream.value([edited ?? note]);
  @override
  Future<void> editText(String course, String id, String text) async {
    edited = LessonNote.fromJson({...note.toJson(), 'text': text});
  }

  @override
  Future<void> colorFolder(String id, String? color) async {
    savedColor = color;
  }
}

class _TopicCourseRepository extends _ReadOnlyCourseRepository {
  _TopicCourseRepository()
    : super(
        LessonNote(
          id: 'note',
          kind: 'text',
          text: 'Ders notu',
          created: DateTime(2026),
        ),
      );
  @override
  Stream<List<LessonFolder>> folders({String? parent}) => Stream.value(
    parent == 'course' ? [const LessonFolder('topic', 'Tokenizer')] : [],
  );
}
