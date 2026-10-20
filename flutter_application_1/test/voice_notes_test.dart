import 'dart:async';
import 'package:flutter_application_1/core/security/microphone_session.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_application_1/features/reminders/reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_application_1/features/voice_notes/voice_notes_screen.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_application_1/features/news/news_notes.dart';

class FakeRecorder extends RecordPlatform {
  final calls = <String>[];
  String? path;
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    this.path = path;
    File(path).writeAsBytesSync([1, 2, 3]);
    calls.add('start');
  }

  @override
  Future<String?> stop(String recorderId) async {
    calls.add('stop');
    return path;
  }

  @override
  Future<void> pause(String recorderId) async {
    calls.add('pause');
  }

  @override
  Future<void> resume(String recorderId) async {
    calls.add('resume');
  }

  @override
  Future<void> cancel(String recorderId) async {
    calls.add('cancel');
  }

  @override
  Future<void> dispose(String recorderId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGlobalAudio extends GlobalAudioplayersPlatformInterface {
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FakeAudio extends AudioplayersPlatformInterface {
  final events = StreamController<AudioEvent>.broadcast();
  final calls = <String>[];
  int position = 0;
  @override
  Stream<AudioEvent> getEventStream(String playerId) => events.stream;
  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    calls.add('source');
    events.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
    events.add(
      const AudioEvent(
        eventType: AudioEventType.duration,
        duration: Duration(seconds: 30),
      ),
    );
  }

  @override
  Future<void> seek(String playerId, Duration position) async {
    this.position = position.inMilliseconds;
    calls.add('seek');
    events.add(const AudioEvent(eventType: AudioEventType.seekComplete));
  }

  @override
  Future<int?> getDuration(String playerId) async => 30000;
  @override
  Future<int?> getCurrentPosition(String playerId) async => position;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return Future<void>.value();
  }
}

class FakePaths extends PathProviderPlatform {
  final String path;
  FakePaths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRecorder recorder;
  late FakeAudio audio;
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('voice_note_test');
    final oldRecorder = RecordPlatform.instance;
    final oldAudio = AudioplayersPlatformInterface.instance;
    final oldGlobal = GlobalAudioplayersPlatformInterface.instance;
    final oldPaths = PathProviderPlatform.instance;
    recorder = FakeRecorder();
    audio = FakeAudio();
    RecordPlatform.instance = recorder;
    AudioplayersPlatformInterface.instance = audio;
    GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudio();
    PathProviderPlatform.instance = FakePaths(dir.path);
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MicrophoneSession.channel, (call) async {
          if (call.method == 'prepare') {
            return {'drawerHidden': true, 'supported': true};
          }
          return null;
        });

    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MicrophoneSession.channel, null);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await audio.events.close();
      RecordPlatform.instance = oldRecorder;
      AudioplayersPlatformInterface.instance = oldAudio;
      GlobalAudioplayersPlatformInterface.instance = oldGlobal;
      PathProviderPlatform.instance = oldPaths;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }
  }

  testWidgets(
    'Voice recording continues across screen lock and stays a draft until confirmed',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: VoiceNotesScreen(sendMessage: (_, _) async {})),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Kaydet'));
      expect(recorder.calls, ['start']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));
      expect(recorder.calls, ['start']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tap(tester, find.textContaining('Bitir'));
      expect(recorder.calls, ['start', 'stop']);
      expect(find.text('Ön dinleme'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
    },
  );

  testWidgets(
    'Record pauses/resumes; preview and seek happen before explicit save',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceNotesScreen()));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Kaydet'));
      await tap(tester, find.text('Kaydı duraklat'));
      expect(recorder.calls, ['start', 'pause']);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Bitir  00:00'), findsOneWidget);
      await tap(tester, find.text('Kayda devam et'));
      expect(recorder.calls.last, 'resume');
      await tap(tester, find.textContaining('Bitir'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('voice_notes_v1'), isNull);
      expect(find.text('Ön dinleme'), findsOneWidget);
      await tap(tester, find.text('Ön dinleme'));
      expect(audio.calls, contains('source'));
      expect(find.byType(Slider), findsOneWidget);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(15000);
      await tester.pump();
      expect(audio.position, 15000);
      await tap(tester, find.text('Dinlemeyi duraklat'));
      expect(audio.calls.last, contains('pause'));
      await tap(tester, find.text('Onayla ve kaydet'));
      await tester.enterText(find.byType(TextField), 'Test notu');
      await tap(tester, find.text('Kaydet'));
      expect(prefs.getString('voice_notes_v1'), contains('Test notu'));
      expect(find.text('Ön dinleme'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
      }
    },
  );
  testWidgets(
    'Restart discards draft and starts a new recording without saving',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceNotesScreen()));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Kaydet'));
      await tap(tester, find.textContaining('Bitir'));
      final first = recorder.path!;
      await tap(tester, find.text('Yeniden çek'));
      expect(recorder.calls.where((v) => v == 'start').length, 2);
      expect(File(first).existsSync(), isFalse);
      await tap(tester, find.textContaining('Bitir'));
      await tap(tester, find.text('Vazgeç'));
      expect(find.text('Ön dinleme'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString('voice_notes_v1'),
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
      }
    },
  );
  test('All chat attachments expire at 48 hours', () {
    final created = DateTime.utc(2026, 10, 13);
    expect(
      chatAttachmentExpired(
        'video',
        created,
        created.add(const Duration(hours: 60)),
      ),
      isTrue,
    );
    expect(
      chatAttachmentExpired(
        'file',
        created,
        created.add(const Duration(hours: 60)),
      ),
      isTrue,
    );
    expect(
      chatAttachmentExpired(
        'photo',
        created,
        created.add(const Duration(hours: 60)),
      ),
      isTrue,
    );
    expect(
      chatAttachmentExpired(
        'video',
        created,
        created.add(const Duration(hours: 72)),
      ),
      isTrue,
    );
  });
  testWidgets(
    'News voice note persists privately after explicit confirmation and can be deleted',
    (tester) async {
      final cancelled = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ReminderService.channel,
        (call) async {
          if (call.method == 'cancel') {
            cancelled.add((call.arguments as Map)['id'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ReminderService.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NewsNotes(article: 1))),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Sesli not'));
      expect(find.text('Kendime sesli not'), findsOneWidget);
      await tap(tester, find.text('Kaydet'));
      await tap(tester, find.textContaining('Bitir'));
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'personal_media_notes',
        ),
        isNull,
      );
      await tap(tester, find.text('Notu kaydet'));
      await tester.enterText(find.byType(TextField), 'Haber için düşüncem');
      await tap(tester, find.text('Kaydet'));
      expect(find.text('Haber için düşüncem'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('personal_media_notes'), hasLength(1));
      final noteId =
          (jsonDecode(prefs.getStringList('personal_media_notes')!.single)
              as Map)['id'];
      expect(prefs.getString('voice_notes_v1'), isNull);
      expect(Directory('${dir.path}/news_notes').listSync(), hasLength(1));
      await tap(tester, find.byTooltip('Notu sil'));
      expect(prefs.getStringList('personal_media_notes'), isEmpty);
      expect(cancelled, [noteId]);
      expect(Directory('${dir.path}/news_notes').listSync(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
      }
    },
  );
  testWidgets(
    'Chat voice preview survives send failure and retries the same recording',
    (tester) async {
      var attempts = 0;
      bool? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open chat voice'),
                onPressed: () async {
                  sent = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VoiceNotesScreen(
                        sendMessage: (path, title) async {
                          expect(File(path).existsSync(), isTrue);
                          attempts++;
                          if (attempts == 1) {
                            throw Exception(
                              'Gönderilemedi. İnternetini kontrol et.',
                            );
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Open chat voice'));
      await tap(tester, find.text('Kaydet'));
      expect(
        recorder.calls,
        contains('start'),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '),
      );
      await tap(tester, find.textContaining('Bitir'));
      await tap(tester, find.text('Onayla ve gönder'));
      await tap(tester, find.text('Kaydet'));
      expect(attempts, 1);
      expect(find.text('Ön dinleme'), findsOneWidget);
      expect(sent, isNull);
      await tap(tester, find.text('Onayla ve gönder'));
      await tap(tester, find.text('Kaydet'));
      expect(attempts, 2);
      expect(sent, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString('voice_notes_v1'),
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
      }
    },
  );
}
