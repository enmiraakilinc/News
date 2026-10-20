import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/features/media/media_names_screen.dart';
import 'package:flutter_application_1/features/media/message_content.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_application_1/core/utils/user_errors.dart';

void main() {
  testWidgets('Each video part keeps its own edited name', (tester) async {
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await Navigator.push<List<String>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const MediaNamesScreen(names: ['Part 1', 'Part 2']),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Sabah – part 1');
    await tester.enterText(find.byType(TextFormField).at(1), 'Sabah – part 2');
    await tester.tap(find.text('Gönder'));
    await tester.pumpAndSettle();
    expect(result, ['Sabah – part 1', 'Sabah – part 2']);
  });
  testWidgets(
    'Photo thumbnail loads automatically, original only on tap, preview expires',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6rJQAAAAASUVORK5CYII=',
      );
      var originals = 0;
      final captures = <String>[];
      const channel = MethodChannel('app/secure_screen');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captures.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final text =
          mediaPrefix +
          jsonEncode({
            'id': 'abcdefghijklmnopqrst',
            'kind': 'photo',
            'name': 'Hatıra',
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: MessageContent(
                text: text,
                previewLoader: (_) async => MediaPreview(
                  png,
                  DateTime.now().add(const Duration(seconds: 5)),
                ),
                mediaLoader: (_) async {
                  originals++;
                  return png;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(originals, 0);
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(originals, 1);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(captures, ['enable']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(Image), findsNothing);
    },
  );
  test('Firebase errors explain action without leaking technical message', () {
    final message = userError(
      FirebaseException(
        plugin: 'firestore',
        code: 'permission-denied',
        message: 'secret internal document path',
      ),
    );
    expect(message, contains('erişilemiyor'));
    expect(message, isNot(contains('permission-denied')));
    expect(message, isNot(contains('secret')));
  });
  test(
    'Common action failures give readable guidance without paths or technical details',
    () {
      expect(
        userError(
          const FileSystemException('OS error 28', r'C:\private\photo.jpg'),
        ),
        contains('boş alan'),
      );
      expect(
        userError(const FormatException('raw base64 payload')),
        isNot(contains('base64')),
      );
      expect(
        userError(TimeoutException('internal request')),
        contains('İnternetini'),
      );
      expect(
        userError(
          PlatformException(
            code: 'camera_access_denied',
            message: 'native stack trace',
          ),
        ),
        contains('izin'),
      );
      expect(
        userError(
          FirebaseException(
            plugin: 'auth',
            code: 'wrong-password',
            message: 'internal',
          ),
        ),
        contains('şifreni'),
      );
      expect(
        userError(
          Exception(r'C:\private\credentials.json'),
          fallback: 'Yeniden dene.',
        ),
        'Yeniden dene.',
      );
      expect(
        userError(Exception('Fotoğraf en fazla 20 MB olabilir.')),
        'Fotoğraf en fazla 20 MB olabilir.',
      );
    },
  );
}
