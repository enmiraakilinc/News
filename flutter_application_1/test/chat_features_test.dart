import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_application_1/features/contacts/contact_details_screen.dart';
import 'package:flutter_application_1/features/contacts/profile_avatar.dart';
import 'package:flutter_application_1/features/calls/voice_call.dart';
import 'package:flutter_application_1/core/notifications/notif_prefs.dart';
import 'package:flutter_application_1/features/updates/update_service.dart';

void main() {
  testWidgets(
    'Call listener leaves the first frame responsive while Firebase bootstrap is pending',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: VoiceCallInbox(
            navigator: GlobalKey<NavigatorState>(),
            bootstrap: () => pending.future,
            child: const Text('Ready'),
          ),
        ),
      );
      expect(find.text('Ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Updater selects the small matching ABI APK and preserves the universal fallback',
    () {
      final data = <String, dynamic>{
        'url': 'https://example.com/universal.apk',
        'urlsByAbi': {
          'arm64-v8a': 'https://example.com/arm64.apk',
          'bad': 'file:///invalid.apk',
        },
      };
      expect(
        updateUrlForAbi(data, 'arm64-v8a'),
        'https://example.com/arm64.apk',
      );
      expect(
        updateUrlForAbi(data, 'x86_64'),
        'https://example.com/universal.apk',
      );
      expect(updateUrlForAbi(data, 'bad'), 'https://example.com/universal.apk');
      expect(updateUrlForAbi(data, null), 'https://example.com/universal.apk');
    },
  );
  testWidgets(
    'Avatar dropdown targets the saved contact without crowding the narrow header',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: const ContactChatHeader(
                contactId: 'defne-chat',
                fallbackName: 'Defne',
                sourceKey: 'chat/defne-chat',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Defne'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Yıldızlı mesajlar'), findsNothing);
      await tester.tap(find.byType(ContactAvatar));
      await tester.pumpAndSettle();
      expect(find.text('Yıldızlı mesajlar'), findsOneWidget);
      expect(find.text('Karşı tarafın beni kaydettiği isim'), findsOneWidget);
      await tester.tap(find.text('Profil resmi / emoji ekle'));
      await tester.pumpAndSettle();
      expect(find.text('Emoji kullan'), findsOneWidget);
      expect(find.text('Profil fotoğrafı seç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Media cache evicts least recently used content, rejects oversized and expired content',
    () {
      final cache = MediaMemoryCache(maxBytes: 6);
      MediaPreview item(int size, {bool expired = false}) => MediaPreview(
        Uint8List(size),
        DateTime.now().add(Duration(seconds: expired ? -1 : 60)),
      );
      cache.put('first', item(3));
      cache.put('second', item(3));
      expect(cache.get('first'), isNotNull);
      cache.put('third', item(3));
      expect(cache.get('second'), isNull);
      expect(cache.get('first'), isNotNull);
      cache.put('oversized', item(7));
      expect(cache.get('oversized'), isNull);
      cache.put('expired', item(1, expired: true));
      expect(cache.get('expired'), isNull);
      cache.clear();
      expect(cache.get('first'), isNull);
    },
  );
  test('Call duration keeps increasing beyond fifteen minutes', () {
    final start = DateTime(2026, 10, 15);
    expect(
      voiceCallElapsed(start, start.add(const Duration(hours: 2))),
      const Duration(hours: 2),
    );
    expect(
      voiceCallElapsed(start, start.subtract(const Duration(hours: 1))),
      Duration.zero,
    );
  });
  test(
    'Chat notification preference overrides the legacy general setting independently',
    () async {
      SharedPreferences.setMockInitialValues({
        kPushBarKey: true,
        kChatNotificationsKey: false,
      });
      expect(await chatNotificationsEnabled(), isFalse);
      SharedPreferences.setMockInitialValues({
        kPushBarKey: false,
        kChatNotificationsKey: true,
      });
      expect(await chatNotificationsEnabled(), isTrue);
      SharedPreferences.setMockInitialValues({kPushBarKey: true});
      expect(await chatNotificationsEnabled(), isTrue);
    },
  );
}
