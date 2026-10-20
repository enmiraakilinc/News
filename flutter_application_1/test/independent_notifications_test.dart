import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/notifications/notif_prefs.dart';
import 'package:flutter_application_1/core/notifications/incoming_call_settings.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (_) async => null,
    );
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({
      kPushBarKey: true,
      'alarm_notifications_enabled': true,
    }),
  );
  test(
    'Voice and video calls inherit old preference but can be changed independently',
    () async {
      final p = await SharedPreferences.getInstance();
      await p.setBool('call_notifications_enabled', false);
      expect(await incomingCallsEnabled(), isFalse);
      expect(await incomingCallsEnabled(video: true), isFalse);
      await p.setBool('video_call_notifications_enabled', true);
      expect(await incomingCallsEnabled(), isFalse);
      expect(await incomingCallsEnabled(video: true), isTrue);
      await setAlarmOnlyPreferences();
      expect(await incomingCallsEnabled(video: true), isFalse);
    },
  );
  testWidgets('Background call notification text persists after editing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CallNotificationTextSetting())));
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Benim başlığım');
    await tester.enterText(find.byType(TextField).at(1), 'Benim yazım');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    final p = await SharedPreferences.getInstance();
    expect(p.getString('incoming_call_title'), 'Benim başlığım');
    expect(p.getString('incoming_call_body'), 'Benim yazım');
  });
  test(
    'Preference migration preserves choices and prevents the legacy master changing other features',
    () async {
      final p = await SharedPreferences.getInstance();
      await p.setBool('content_notification_timeline', false);
      await migrateNotificationPreferences();
      await p.setBool(kPushBarKey, false);
      await setChatNotifications(false);
      expect(await contentNotificationEnabled(kNotifTimeline), isFalse);
      expect(await contentNotificationEnabled(kNotifQuestions), isTrue);
      expect(await contentNotificationEnabled(kNotifLetters), isTrue);
      await migrateNotificationPreferences();
      expect(await contentNotificationEnabled(kNotifQuestions), isTrue);
    },
  );
  test(
    'Alarm-only mode disables every content source and calls without changing personal wake consents',
    () async {
      final p = await SharedPreferences.getInstance();
      await p.setBool('wakeup_disabled_example', false);
      await setAlarmOnlyPreferences();
      for (final kind in [
        kNotifChats,
        ...kAllContentNotifs,
        kNotifUpdates,
        kNotifStorage,
      ]) {
        expect(
          await contentNotificationEnabled(kind),
          isFalse,
          reason: kind.label,
        );
      }
      expect(await incomingCallsEnabled(), isFalse);
      expect(await contentNotificationEnabled(kNotifNews), isTrue);
      expect(p.getBool('alarm_notifications_enabled'), isTrue);
      expect(p.getBool('wakeup_disabled_example'), isFalse);
      expect(p.getBool('notif_active'), isFalse);
    },
  );
  testWidgets(
    'Turning off persists and stays visibly off even if notification cleanup fails',
    (tester) async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          if (call.method == 'cancel') {
            throw PlatformException(code: 'cleanup_failed');
          }
          return true;
        },
      );
      Future<void> open() => tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FeatureNotificationSwitch(kind: kNotifTimeline)),
        ),
      );
      await open();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(await contentNotificationEnabled(kNotifTimeline), isFalse);
      await tester.pumpWidget(const SizedBox());
      await open();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    },
  );
  testWidgets(
    'All feature switches are visible independently and changing memories does not alter alarms or questions',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => null,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ContentNotificationSettings()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<ContentNotif>), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'Anılar'), findsOneWidget);
      expect(
        find.widgetWithText(SwitchListTile, 'Günün Sorusu'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Anılar'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Anılar'));
      await tester.pumpAndSettle();
      expect(await contentNotificationEnabled(kNotifTimeline), isFalse);
      expect(await contentNotificationEnabled(kNotifQuestions), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'alarm_notifications_enabled',
        ),
        isTrue,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        null,
      );
    },
  );
}
