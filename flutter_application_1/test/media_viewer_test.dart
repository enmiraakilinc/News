import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_application_1/features/media/media_viewer.dart';
import 'package:flutter_application_1/features/media/message_content.dart';
import 'package:flutter_application_1/features/media/video_parts.dart';
import 'package:flutter_application_1/features/media/image_util.dart';
import 'package:flutter_application_1/features/media/photo_gallery.dart';

class FakeVideo extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  final calls = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    expect(options.dataSource.sourceType, DataSourceType.file);
    calls.add('create');
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;
  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seek');
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('app/secure_screen');
  final secureCalls = <String>[];
  setUp(() {
    secureCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (call) async {
          secureCalls.add(call.method);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app/video_parts'), null);
  });

  testWidgets(
    'Video stays in protected app, pauses on background and disposes',
    (tester) async {
      final previous = VideoPlayerPlatform.instance;
      final fake = FakeVideo();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() async {
        VideoPlayerPlatform.instance = previous;
        await fake.events.close();
      });
      await tester.pumpWidget(
        MaterialApp(home: PrivateVideoScreen(file: File('clip.mp4'))),
      );
      await tester.pump();
      fake.events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(640, 360),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(secureCalls, ['enable']);
      expect(fake.calls, containsAllInOrder(['create', 'play']));
      final zoom = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(zoom.maxScale, 5);
      zoom.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.tap(find.byTooltip('Yakınlaştırmayı sıfırla'));
      await tester.pump();
      expect(zoom.transformationController!.value, Matrix4.identity());
      await tester.tap(find.byTooltip('Duraklat'));
      await tester.pump();
      expect(fake.calls.last, 'pause');
      await tester.tap(find.byTooltip('Oynat'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(fake.calls.last, 'pause');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(fake.calls.last, 'dispose');
      expect(secureCalls, isNot(contains('disable')));
    },
  );

  testWidgets(
    'Legacy screenshot without kind opens internally with capture protection',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6rJQAAAAASUVORK5CYII=',
      );
      final text =
          attachmentPrefix +
          jsonEncode({
            'name': 'Screenshot_20261017_172417_Instagram.jpg',
            'bytes': base64Encode(png),
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 220, child: MessageContent(text: text)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      expect(secureCalls, ['enable']);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    },
  );

  test('Videos selected as files still use internal viewer', () {
    expect(
      attachmentViewKind({
        'kind': 'file',
        'name': 'Screenshot_20261017_172417_Instagram.jpg ',
      }),
      'photo',
    );
    expect(
      attachmentViewKind({
        'kind': 'file',
        'name': 'Deneme',
      }, bytes: Uint8List.fromList([255, 216, 255, 224])),
      'photo',
    );
    expect(
      attachmentViewKind({
        'kind': 'file',
        'name': 'Deneme',
      }, bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
      'photo',
    );
    expect(
      attachmentViewKind({
        'kind': 'file',
        'name': 'book.pdf',
      }, bytes: Uint8List.fromList([37, 80, 68, 70])),
      'file',
    );
    expect(
      attachmentViewKind({'kind': 'file', 'name': 'holiday.MP4'}),
      'video',
    );
    expect(attachmentViewKind({'kind': 'file', 'name': 'photo.jpg'}), 'photo');
    expect(attachmentViewKind({'kind': 'file', 'name': 'book.pdf'}), 'file');
    expect(chatAttachmentLimit('file'), 80 * 1024 * 1024);
    expect(chatAttachmentLimit('video'), 100 * 1024 * 1024);
  });
  testWidgets('Pinch zoom works without invoking save consent', (tester) async {
    final bytes = File('assets/news/0.jpg').readAsBytesSync();
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivatePhotoGallery(
          items: [
            PrivatePhotoItem(
              load: () async => bytes,
              onSave: () {
                saves++;
              },
            ),
          ],
          initialIndex: 0,
          initialBytes: bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(bytes),
        tester.element(find.byType(PrivatePhotoGallery)),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(center - const Offset(20, 0));
    await second.down(center + const Offset(20, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(40, 0));
    await second.moveTo(center + const Offset(40, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(80, 0));
    await second.moveTo(center + const Offset(80, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(120, 0));
    await second.moveTo(center + const Offset(120, 0));
    await tester.pump();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(saves, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Chat gallery swipes between photos, loads only on demand and keeps capture protection',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6rJQAAAAASUVORK5CYII=',
      );
      String photo(String id) =>
          mediaPrefix +
          jsonEncode({'id': id, 'kind': 'file', 'name': 'Screenshot_$id.jpg'});
      final first = photo('aaaaaaaaaaaaaaaaaaaa');
      final second = photo('bbbbbbbbbbbbbbbbbbbb');
      final loads = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageContent(
              text: first,
              photoMessages: ['Sıradan mesaj', first, second],
              previewLoader: (_) async => null,
              mediaLoader: (id) async {
                loads.add(id);
                return png;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, isEmpty);
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(loads, ['aaaaaaaaaaaaaaaaaaaa']);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(loads, ['aaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbb']);
      await tester.drag(find.byType(PageView), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(loads.last, 'aaaaaaaaaaaaaaaaaaaa');
      expect(secureCalls, contains('enable'));
      expect(secureCalls, isNot(contains('disable')));
    },
  );
  test(
    'Photos that fit the inline storage limit retain their original bytes',
    () async {
      final jpeg = File('assets/news/0.jpg').readAsBytesSync();
      final small = Uint8List.fromList(jpeg.take(kMaxRawBytes).toList());
      expect(identical(await compressToFit(small), small), isTrue);
    },
  );

  testWidgets(
    'A real JPEG screenshot sent as a remote file opens inside the app',
    (tester) async {
      final jpeg = File('assets/news/0.jpg').readAsBytesSync();
      final text =
          mediaPrefix +
          jsonEncode({
            'id': 'abcdefghijklmnopqrst',
            'kind': 'file',
            'name': 'Screenshot_20261017_172417_Instagram.jpg',
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageContent(
              text: text,
              previewLoader: (_) async => null,
              mediaLoader: (_) async => jpeg,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(secureCalls, contains('enable'));
    },
  );

  test(
    'Unknown file names use the image decoder while ordinary documents stay files',
    () async {
      final bitmap = base64Decode(
        'Qk06AAAAAAAAADYAAAAoAAAAAQAAAAEAAAABABgAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAD/AA==',
      );
      expect(
        await attachmentIsPhoto({'kind': 'file', 'name': 'Deneme'}, bitmap),
        isTrue,
      );
      expect(
        await attachmentIsPhoto({
          'kind': 'file',
          'name': 'Deneme',
        }, Uint8List.fromList(utf8.encode('%PDF-1.7'))),
        isFalse,
      );
    },
  );

  test(
    'Videos above 100 MB split into bounded 100 MB parts and preserve the original',
    () async {
      final small = XFile.fromData(Uint8List(10), name: 'small.mp4');
      expect(await VideoParts.prepare(small), [small]);
      final dir = await Directory.systemTemp.createTemp('video_single_test');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/original.mp4');
      const channel = MethodChannel('app/video_parts');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            expect(call.method, 'split');
            expect((call.arguments as Map)['maxBytes'], 100 * 1024 * 1024);
            final paths = <String>[];
            final count = ((await source.length()) / VideoParts.partBytes)
                .ceil();
            for (var i = 0; i < count; i++) {
              final part = File('${dir.path}/part-$i.mp4');
              final handle = await part.open(mode: FileMode.write);
              await handle.truncate(VideoParts.partBytes);
              await handle.close();
              paths.add(part.path);
            }
            return paths;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final size in [
        40 * 1024 * 1024,
        100 * 1024 * 1024,
        200 * 1024 * 1024,
        300 * 1024 * 1024,
      ]) {
        final handle = await source.open(mode: FileMode.write);
        await handle.truncate(size);
        await handle.close();
        final parts = await VideoParts.prepare(XFile(source.path));
        expect(
          parts,
          hasLength(
            size <= VideoParts.partBytes ? 1 : size ~/ VideoParts.partBytes,
          ),
        );
        for (final part in parts) {
          expect(await part.length(), lessThanOrEqualTo(VideoParts.partBytes));
        }
        await VideoParts.cleanup(parts, source.path);
        expect(await source.exists(), isTrue);
        for (final part in parts) {
          expect(await File(part.path).exists(), part.path == source.path);
        }
      }
      expect(calls, 2);
    },
  );
}
