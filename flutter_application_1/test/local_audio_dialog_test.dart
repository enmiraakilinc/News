import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_application_1/features/media/local_audio_dialog.dart';
import 'voice_notes_test.dart' show FakeAudio, FakeGlobalAudio;

void main() {
  late FakeAudio audio;
  setUp(() {
    final previous = AudioplayersPlatformInterface.instance;
    final global = GlobalAudioplayersPlatformInterface.instance;
    audio = FakeAudio();
    AudioplayersPlatformInterface.instance = audio;
    GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudio();
    addTearDown(() async {
      await audio.events.close();
      AudioplayersPlatformInterface.instance = previous;
      GlobalAudioplayersPlatformInterface.instance = global;
    });
  });
  testWidgets(
    'Course audio offers external opening only after explicit confirmation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalAudioDialog(
              file: File('lesson.m4a'),
              title: 'Ders kaydı',
              allowExternal: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Birlikte aç'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('kendi kopyasını saklayabilir'),
        findsOneWidget,
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.text('Ders kaydı'), findsOneWidget);
      expect(find.text('Birlikte aç'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'Other private note players keep external export disabled by default',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalAudioDialog(file: File('note.m4a'), title: 'Not'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Birlikte aç'), findsNothing);
      expect(find.byTooltip('Oynat'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
