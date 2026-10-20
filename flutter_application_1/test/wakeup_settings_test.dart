import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/wakeup/wakeup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Device identity persists; wake permission differs for each source and phone',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = await WakeupService.deviceId();
      expect(first, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(await WakeupService.deviceId(), first);
      expect(
        WakeupService.permissionId('chat/one', first),
        isNot(WakeupService.permissionId('chat/two', first)),
      );
      expect(
        WakeupService.permissionId('chat/one', first),
        isNot(WakeupService.permissionId('chat/one', 'b' * 32)),
      );
    },
  );
  testWidgets('Wake starts disabled until backend and consent are loaded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WakeupSettings(sourceKey: 'chat/one')),
      ),
    );
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
