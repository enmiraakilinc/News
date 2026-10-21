import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/calls/call_ringtone.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  var mode = 'sound';
  var name = 'Telefon sesi';
  setUp(() {
    calls = [];
    mode = 'sound';
    name = 'Telefon sesi';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      CallRingtone.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'setMode') mode = call.arguments['mode'] as String;
        if (call.method == 'pickFile') name = 'Kendi sesim';
        return {'mode': mode, 'name': name};
      },
    );
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      CallRingtone.channel,
      null,
    ),
  );
  testWidgets(
    'Shared voice/video mode persists when panel is reopened and stays independent of alarm',
    (tester) async {
      Widget panel() => const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CallRingtoneSettings()),
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arama zil sesi ve titreşim'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yalnızca titreşim').last);
      await tester.pumpAndSettle();
      expect(mode, 'vibrate');
      expect(calls.where((c) => c.method == 'setMode').single.arguments, {
        'mode': 'vibrate',
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      expect(find.textContaining('Titreşim ·'), findsOneWidget);
      expect(
        calls.every((c) => !c.method.toLowerCase().contains('alarm')),
        isTrue,
      );
    },
  );
  testWidgets(
    'System picker, personal file, preview and stop are separate actions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CallRingtoneSettings()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arama zil sesi ve titreşim'));
      await tester.pumpAndSettle();
      for (final text in [
        'Telefonun zil seslerinden seç',
        'Kendi ses dosyamı seç',
        '5 saniye dene',
        'Durdur',
      ]) {
        await tester.ensureVisible(find.text(text));
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }
      expect(
        calls.map((c) => c.method),
        containsAllInOrder([
          'get',
          'pickSystem',
          'pickFile',
          'preview',
          'stop',
        ]),
      );
      expect(find.textContaining('Kendi sesim'), findsWidgets);
    },
  );
  test(
    'Ring and stop keep the call identity so an old screen cannot silence a newer call',
    () async {
      await CallRingtone.ring('a' * 20);
      await CallRingtone.stop('a' * 20);
      expect(calls.map((c) => c.method), ['ring', 'stop']);
      expect(calls.every((c) => c.arguments['id'] == 'a' * 20), isTrue);
    },
  );
}
