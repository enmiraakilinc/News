import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/security/microphone_session.dart';
import 'package:flutter_application_1/core/security/feature_access.dart';
import 'package:flutter_application_1/features/voice_notes/microphone_session_screen.dart';
import 'voice_notes_test.dart' show FakeRecorder;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late FakeRecorder permission;
  late RecordPlatform oldRecorder;
  String? mode;
  var hidden = true;
  var nativeSupported = true;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    mode = null;
    hidden = true;
    nativeSupported = true;
    oldRecorder = RecordPlatform.instance;
    permission = FakeRecorder();
    RecordPlatform.instance = permission;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MicrophoneSession.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'prepare') {
          return {'supported': nativeSupported, 'drawerHidden': hidden};
        }
        if (call.method == 'status') return {'mode': mode, 'silenced': false};
        if (call.method == 'requestStop') {
          mode = null;
        }
        if (call.method == 'start') {
          mode = (call.arguments as Map)['mode'] as String;
        }
        if (call.method == 'stop' && (call.arguments as Map)['mode'] == mode) {
          mode = null;
        }
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MicrophoneSession.channel,
      null,
    );
    RecordPlatform.instance = oldRecorder;
  });
  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Hold session survives screen lock and route disposal without starting file recording',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: MicrophoneSessionScreen()),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Başlat');
      expect(mode, 'hold');
      expect(permission.calls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));
      expect(mode, 'hold');
      expect(calls.where((c) => c.method == 'stop'), isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(mode, 'hold');
      expect(calls.where((c) => c.method == 'stop'), isEmpty);
      await MicrophoneSession.stop('hold');
      expect(mode, isNull);
    },
  );

  testWidgets(
    'Visible notification channel opens user settings before any microphone capture',
    (tester) async {
      hidden = false;
      await tester.pumpWidget(
        const MaterialApp(home: MicrophoneSessionScreen()),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Başlat');
      expect(find.text('Mikrofon bildirim görünümü'), findsOneWidget);
      expect(calls.where((c) => c.method == 'start'), isEmpty);
      expect(permission.calls, isEmpty);
      await tap(tester, 'Kanal ayarını aç');
      expect(calls.where((c) => c.method == 'settings'), hasLength(1));
      expect(mode, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Disabled microphone switch denies hold before permission or native start',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'feature_access_microphone': false,
      });
      await tester.pumpWidget(
        const MaterialApp(home: MicrophoneSessionScreen()),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Başlat');
      expect(mode, isNull);
      expect(calls.where((c) => c.method == 'start'), isEmpty);
      expect(permission.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Older Android retains ordinary voice recording with its required notification',
    (tester) async {
      nativeSupported = false;
      hidden = false;
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await MicrophoneSession.ensureDrawerHidden(
                  context,
                  allowLegacy: true,
                );
              },
              child: const Text('legacy'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('legacy'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'Turning off microphone usage requests stop for an active session',
    (tester) async {
      mode = 'hold';
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FeatureAccessSwitches())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Mikrofon'));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'feature_access_microphone',
        ),
        isFalse,
      );
      expect(calls.where((c) => c.method == 'requestStop'), hasLength(1));
      expect(mode, isNull);
    },
  );

  test(
    'Native stop action is forwarded to the voice recording owner',
    () async {
      var stopped = 0;
      await MicrophoneSession.start(
        'voice',
        onVoiceStop: () async {
          stopped++;
          await MicrophoneSession.stop('voice');
        },
      );
      final complete = Completer<void>();
      binding.defaultBinaryMessenger.handlePlatformMessage(
        MicrophoneSession.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('stopRequested'),
        ),
        (_) => complete.complete(),
      );
      await complete.future;
      expect(stopped, 1);
      expect(mode, isNull);
    },
  );
}
