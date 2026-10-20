import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_application_1/features/chat/chat_service.dart';
import 'package:flutter_application_1/features/chat/chat_unread.dart';
import 'package:flutter_application_1/features/contacts/contact_names.dart';
import 'package:flutter_application_1/features/pair/couple_service.dart';
import 'package:flutter_application_1/core/notifications/notif_prefs.dart';
import 'package:flutter_application_1/features/location/offline_location_map.dart';
import 'package:flutter_application_1/features/contacts/profile_avatar.dart';

class _NoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('Offline map attempted a network request');
  }
}

void main() {
  test(
    'Batched media decryption preserves encrypted chunk order and bytes',
    () async {
      final originals = [
        for (var i = 0; i < 16; i++)
          Uint8List.fromList(List.filled(1024 + i, i)),
      ];
      final encoded = [
        for (final bytes in originals)
          transformMediaChunk({'bytes': bytes, 'secret': 'test-word'}),
      ];
      final decoded = await compute(decodeMediaBatch, {
        'chunks': encoded,
        'secret': 'test-word',
      });
      expect(decoded, originals);
      expect(
        decodeMediaBatch({
          'chunks': [
            for (final bytes in originals) {'bytes': bytes},
          ],
          'secret': null,
        }),
        originals,
      );
    },
  );
  test('20 MiB private attachment round trips across every chunk', () async {
    final original = Uint8List.fromList(
      List.generate(maxChatMediaBytes, (i) => i % 251),
    );
    final decoded = BytesBuilder(copy: false);
    var chunks = 0;
    for (var offset = 0; offset < original.length; offset += mediaChunkBytes) {
      final end = offset + mediaChunkBytes;
      final part = Uint8List.sublistView(
        original,
        offset,
        end > original.length ? original.length : end,
      );
      final encoded = await compute(transformMediaChunk, {
        'bytes': part,
        'secret': 'test-word',
      });
      expect(
        (encoded['bytes'] as Uint8List).length,
        lessThanOrEqualTo(mediaChunkBytes + 16),
      );
      expect(encoded['bytes'], isNot(equals(part)));
      final result = await compute(transformMediaChunk, {
        ...encoded,
        'secret': 'test-word',
        'decrypt': true,
      });
      decoded.add(result['bytes'] as Uint8List);
      chunks++;
    }
    expect(chunks, 46);
    expect(decoded.takeBytes(), original);
  });

  test(
    'Media rejects an oversized file before connecting to Firebase',
    () async {
      await expectLater(
        ChatMedia.upload(
          Uint8List(maxChatFileBytes + 1),
          'test.bin',
          'file',
          chatId: 'test',
        ),
        throwsException,
      );
    },
  );

  test(
    'Aliases belong to this device and reload without stale names',
    () async {
      SharedPreferences.setMockInitialValues({});
      await ContactNames.load();
      await ContactNames.save('direct_pair', 'Selin');
      expect(ContactNames.name('direct_pair', 'Shared name'), 'Selin');
      SharedPreferences.setMockInitialValues({
        'contact_alias_direct_pair': 'Ahmet',
      });
      await ContactNames.load();
      expect(ContactNames.name('direct_pair', 'Shared name'), 'Ahmet');
      SharedPreferences.setMockInitialValues({});
      await ContactNames.load();
      expect(ContactNames.hasAlias('direct_pair'), isFalse);
    },
  );

  test(
    'Unread count excludes own, read, and future messages; immediate ignores clock skew',
    () {
      ChatMessage message(
        String id, {
        String sender = 'peer',
        List<String> readBy = const [],
        bool scheduled = true,
        DateTime? time,
      }) => ChatMessage(
        id: id,
        sender: sender,
        text: 'Hi',
        sentAt: DateTime.now(),
        openAt: time ?? DateTime.now().subtract(const Duration(minutes: 1)),
        readBy: readBy,
        scheduled: scheduled,
      );
      final future = DateTime.now().add(const Duration(days: 1));
      expect(
        unreadMessageCount([
          message('new'),
          message('mine', sender: 'me'),
          message('read', readBy: ['me']),
          message('future', time: future),
          message('immediate', time: future, scheduled: false),
        ], userId: 'me'),
        2,
      );
    },
  );

  test(
    'Invite codes accept pasted spacing and hyphens without dropping digits',
    () {
      expect(ChatService.normalizeInviteCode(' 0123-4567\n'), '01234567');
      expect(ChatService.normalizeInviteCode('01 23 45 67'), '01234567');
      expect(ChatService.normalizeInviteCode('abc'), 'abc');
    },
  );

  testWidgets(
    'Chat-only account can edit its notification text without pairing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => editNotifText(ctx, kNotifChats),
                child: const Text('Ayar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ayar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yeni haber var');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kNotifChats.templateKey), 'Yeni haber var');
      expect(prefs.getString('couple_id'), isNull);
    },
  );

  testWidgets('Profile photo expands on tap and avatar updates from the stream', (
    tester,
  ) async {
    final source = StreamController<ChatProfile?>.broadcast(sync: true);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(userId: 'synthetic', profiles: source.stream),
        ),
      ),
    );
    source.add(ChatProfile(name: 'Ada', photo: png));
    await tester.pump();
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    source.add(ChatProfile(name: 'Ada', emoji: '🌸'));
    await tester.pumpAndSettle();
    expect(find.text('🌸'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => source.close());
  });

  testWidgets('Bundled map displays the point without tiles or HTTP requests', (
    tester,
  ) async {
    final network = _NoNetwork();
    final old = HttpOverrides.current;
    HttpOverrides.global = network;
    addTearDown(() => HttpOverrides.global = old);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineLocationMap(
            latitude: 41,
            longitude: 29,
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.byIcon(Icons.location_pin), findsOneWidget);
    expect(network.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test('Letter decoder keeps unreadable and valid text separate', () async {
    final result = await compute(decodeLetterBatch, {
      'secret': 'test',
      'ciphers': {'broken': 'invalid'},
    });
    expect(result['broken'], isNull);
  });
}
