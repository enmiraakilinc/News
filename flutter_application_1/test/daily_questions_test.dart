import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/features/questions/question_screen.dart';

void main() {
  test(
    'Question schedule starts on the selected question and never repeats',
    () {
      expect(kSorular.length, 104);
      expect(
        kSorular.first,
        'Çocukken doğru sandığın ama sonradan değişen bir fikrin neydi?',
      );
      expect(kSorular.toSet(), hasLength(kSorular.length));

      expect(questionIndexForDate(DateTime(2026, 11, 6)), isNull);
      expect(questionIndexForDate(DateTime(2026, 11, 7)), 0);
      expect(questionIndexForDate(DateTime(2026, 11, 8)), 1);
      expect(questionIndexForDate(DateTime(2027, 2, 18)), 103);
      expect(questionIndexForDate(DateTime(2027, 2, 19)), isNull);
    },
  );

  test(
    'Question schedule ignores time-of-day and advances by calendar day',
    () {
      expect(questionIndexForDate(DateTime(2026, 11, 8, 23, 59)), 1);
      expect(questionIndexForDate(DateTime(2026, 11, 9, 0, 1)), 2);
    },
  );
}
