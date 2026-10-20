import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/reminders/reminder_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'A missing exact-alarm grant opens the specific permission page without scheduling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
      const wake = MethodChannel('app/wakeup');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        plugin,
        (_) async => true,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        wake,
        (_) async => true,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ReminderService.channel,
        (call) async {
          calls.add(call.method);
          return call.method == 'canSchedule' ? false : null;
        },
      );
      addTearDown(() {
        for (final channel in [plugin, wake, ReminderService.channel]) {
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ReminderService.pick(
                  context,
                  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                ),
                child: const Text('Kur'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Kur'));
      await tester.pumpAndSettle();
      expect(find.text('Alarm zamanlama izni'), findsOneWidget);
      await tester.tap(find.text('İzni aç'));
      await tester.pumpAndSettle();
      expect(calls, ['canSchedule', 'settings']);
    },
  );
}
