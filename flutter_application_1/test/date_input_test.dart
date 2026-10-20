import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/widgets/date_input.dart';
import 'package:flutter_application_1/features/counter/counter_page.dart';

void main() {
  test('Dates validate leap years and reject rollover', () {
    expect(parseDateInput('29022024'), DateTime(2024, 2, 29));
    expect(parseDateInput('20012026'), DateTime(2026, 1, 20));
    expect(parseDateInput('2026-10-03'), DateTime(2026, 10, 3));
    expect(parseDateInput('20261003'), DateTime(2026, 10, 3));
    expect(parseDateInput('3/1/2026'), DateTime(2026, 1, 3));
    expect(parseDateInput('29/02/2025'), isNull);
    expect(parseDateInput('31/04/2026'), isNull);
    expect(parseDateInput('01/13/2026'), isNull);
    expect(parseDateInput('123'), isNull);
  });

  test('Typing inserts separators, keeps cursor and allows backspace', () {
    const formatter = DateInputFormatter();
    TextEditingValue value(String text, [int? cursor]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor ?? text.length),
    );
    expect(formatter.formatEditUpdate(value('03'), value('031')).text, '03/1');
    expect(
      formatter.formatEditUpdate(value('03/10'), value('03/102')).text,
      '03/10/2',
    );
    final deleted = formatter.formatEditUpdate(
      value('03/10/2', 6),
      value('03/102', 5),
    );
    expect(deleted.text, '03/12');
    expect(deleted.selection.extentOffset, 4);
    final pasted = formatter.formatEditUpdate(value(''), value('3-1-2026'));
    expect(pasted.text, '03/01/2026');
    final replaced = formatter.formatEditUpdate(
      value('03/10/2026', 1),
      value('13/10/2026', 1),
    );
    expect(replaced.selection.extentOffset, 1);
  });

  testWidgets('Counter accepts digits as a date and rejects future dates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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
    await tester.tap(find.text('Başlangıç tarihi seç'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tarihi elle gir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '01012100');
    await tester.tap(find.text('Seç'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '03012020');
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '03/01/2020',
    );
    await tester.tap(find.text('Seç'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('counter_start'),
      DateTime(2020, 1, 3).toIso8601String(),
    );
    expect(changes, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
