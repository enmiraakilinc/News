import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/counter/counter_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Sayaç widget seçenekleri içermez', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CounterPage(onChanged: () async {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Başlangıç tarihi seç'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Widgetlar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Sayaç başlığı değişir ve başlangıç tarihi korunur', (
    tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 10);
    SharedPreferences.setMockInitialValues({
      'counter_start': start.toIso8601String(),
      'counter_title': 'Eski başlık',
    });
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CounterPage(
          onChanged: () async {
            changes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    await tester.tap(find.text('Başlığı özelleştir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Yeni başlık');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni başlık'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('counter_title'), 'Yeni başlık');
    expect(prefs.getString('counter_start'), start.toIso8601String());
    expect(changes, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
