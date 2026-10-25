import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_application_1/features/media/chat_audio_player.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_application_1/features/media/media_expiry_scope.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';

class _Audio extends AudioplayersPlatformInterface {
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<int?> getDuration(String playerId) async => 0;
  @override
  Stream<AudioEvent> getEventStream(String playerId) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _GlobalAudio extends GlobalAudioplayersPlatformInterface {
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  testWidgets(
    'Audio speed can be chosen without downloading or starting a message',
    (tester) async {
      final old = AudioplayersPlatformInterface.instance,
          oldGlobal = GlobalAudioplayersPlatformInterface.instance;
      AudioplayersPlatformInterface.instance = _Audio();
      GlobalAudioplayersPlatformInterface.instance = _GlobalAudio();
      addTearDown(() {
        AudioplayersPlatformInterface.instance = old;
        GlobalAudioplayersPlatformInterface.instance = oldGlobal;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAudioPlayer(id: 'test', name: 'Sesli mesaj'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Oynatma hızı'));
      await tester.pumpAndSettle();
      expect(find.text('1.5x'), findsOneWidget);
      expect(find.text('2x'), findsOneWidget);
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(find.text('1.5x'), findsOneWidget);
      expect(find.byTooltip('Sesli mesajı dinle'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('Recipient sees the attachment expiry and live extensions', (
    tester,
  ) async {
    const id = 'abcdefghijklmnopqrst';
    final updates = StreamController<Map<String, DateTime>>();
    addTearDown(updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaExpiryScope(
            source: 'chat/test',
            dates: updates.stream,
            child: MessageBubble(
              mine: false,
              text:
                  mediaPrefix +
                  jsonEncode({'id': id, 'kind': 'video', 'name': 'Ders.mp4'}),
              time: '12:00',
            ),
          ),
        ),
      ),
    );
    updates.add({id: DateTime.now().add(const Duration(days: 2))});
    await tester.pumpAndSettle();
    final first = tester.widget<Text>(find.textContaining('Erişim:')).data;
    updates.add({id: DateTime.now().add(const Duration(days: 7))});
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.textContaining('Erişim:')).data,
      isNot(first),
    );
    expect(tester.takeException(), isNull);
  });
}
