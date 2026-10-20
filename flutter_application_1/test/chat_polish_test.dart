import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/theme/chat_theme.dart';
import 'package:flutter_application_1/features/questions/question_screen.dart';
import 'package:flutter_application_1/core/notifications/notif_prefs.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Question answers and empty hints remain readable in every theme',
    (tester) async {
      for (final theme in ChatThemes.names.keys) {
        final data = ChatThemes.theme(theme);
        for (final background in [
          data.colorScheme.primaryContainer,
          data.colorScheme.secondaryContainer,
        ]) {
          for (final answer in ['Cevap metni', null]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: data,
                home: Scaffold(
                  body: QuestionAnswerCard(
                    baslik: 'Başlık',
                    cevap: answer,
                    bosMetin: 'Henüz cevap yok',
                    renk: background,
                    onTap: null,
                  ),
                ),
              ),
            );
            final text = tester.widget<Text>(
              find.text(answer ?? 'Henüz cevap yok'),
            );
            final color = Color.alphaBlend(text.style!.color!, background);
            final a = color.computeLuminance(),
                b = background.computeLuminance();
            final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$theme text contrast',
            );
          }
        }
      }
    },
  );
  testWidgets(
    'Enabling asks for permission and opens direct notification settings after denial',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'content_notification_timeline': false,
      });
      final calls = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          calls.add(call.method);
          return false;
        },
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app/permissions'),
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null,
        );
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('app/permissions'),
          null,
        );
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FeatureNotificationSwitch(kind: kNotifTimeline)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('Bildirim izni gerekli'), findsOneWidget);
      await tester.tap(find.text('İzin ver'));
      await tester.pumpAndSettle();
      expect(find.text('Telefon ayarlarından aç'), findsOneWidget);
      await tester.tap(find.text('Bildirim ayarları'));
      await tester.pumpAndSettle();
      expect(calls, contains('notificationSettings'));
      expect(await contentNotificationEnabled(kNotifTimeline), isFalse);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    },
  );
  testWidgets(
    'Narrow chat composer keeps file, schedule and camera controls separate',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ChatComposer(onSend: (_, _) async {}),
          ),
        ),
      );
      expect(find.byTooltip('Ek gönder'), findsNothing);
      expect(find.byTooltip('Dosya gönder'), findsOneWidget);
      expect(find.byTooltip('Geleceğe gönder'), findsOneWidget);
      await tester.tap(find.byTooltip('Fotoğraf, video veya konum'));
      await tester.pumpAndSettle();
      expect(find.text('Galeriden fotoğraf seç'), findsOneWidget);
      expect(find.text('Galeriden video seç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
