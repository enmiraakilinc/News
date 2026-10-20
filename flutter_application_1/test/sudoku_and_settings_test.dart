import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/games/sudoku_screen.dart';
import 'package:flutter_application_1/core/security/feature_access.dart';
import 'package:flutter_application_1/core/notifications/notif_prefs.dart';
import 'package:flutter_application_1/features/news/news_notes.dart';
import 'package:flutter_application_1/features/account/chat_account.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Generated Sudoku has exactly one solution and consistent clues', () {
    for (var seed = 0; seed < 8; seed++) {
      final p = SudokuPuzzle.generate(Random(seed));
      expect(SudokuPuzzle.solutions(List.of(p.clues)), 1);
      expect(p.clues.where((n) => n == 0).length, greaterThanOrEqualTo(35));
      for (var i = 0; i < 81; i++) {
        expect(SudokuPuzzle.allowed(p.solution, i, p.solution[i]), isTrue);
        if (p.clues[i] != 0) expect(p.clues[i], p.solution[i]);
      }
    }
  });
  test('Disabled features fail before sensor permission requests', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feature_access_camera', false);
    expect(FeatureAccess.require('camera'), throwsA(isA<Exception>()));
    expect(await FeatureAccess.enabled('microphone'), isTrue);
  });
  test(
    'Per-feature notifications override the master without changing other features',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPushBarKey, true);
      await prefs.setBool('content_notification_timeline', false);
      expect(await contentNotificationEnabled(kNotifTimeline), isFalse);
      expect(await contentNotificationEnabled(kNotifQuestions), isTrue);
      await prefs.setBool(kPushBarKey, false);
      await prefs.setBool('content_notification_news', true);
      expect(await contentNotificationEnabled(kNotifNews), isTrue);
    },
  );
  test(
    'Short aliases preserve leading zeros and legacy code normalization',
    () {
      expect(ChatAccount.displayCode('001122334455'), '0011-2233-4455');
      expect(ChatAccount.normalizeCode('0011-2233-4455'), '001122334455');
      expect(ChatAccount.normalizeCode('a' * 32), 'a' * 32);
      expect(() => ChatAccount.normalizeCode('1234'), throwsFormatException);
    },
  );
  testWidgets(
    'Existing article notes migrate together without duplicates or deleting content',
    (tester) async {
      final a = jsonEncode({
        'file': '123_0.image',
        'kind': 'photo',
        'title': 'Eski görsel',
      });
      final b = jsonEncode({
        'file': '456_1.m4a',
        'kind': 'audio',
        'title': 'Eski ses',
      });
      SharedPreferences.setMockInitialValues({
        'news_media_notes_0': [a],
        'news_media_notes_1': [a, b],
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NewsNotes(article: 0))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eski görsel'), findsOneWidget);
      expect(find.text('Eski ses'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('personal_media_notes'), hasLength(2));
      expect(prefs.containsKey('news_media_notes_0'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NewsNotes(article: 0))),
      );
      await tester.pumpAndSettle();
      expect(prefs.getStringList('personal_media_notes'), hasLength(2));
    },
  );
}
