import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/features/questions/question_screen.dart';

void main() {
  test('Question pool keeps today answered and has no exact duplicates', () {
    final today = DateTime(2026, 11, 1);
    final dayIndex = today.difference(DateTime(today.year, 1, 1)).inDays;
    expect(kSorular.length, 207);
    expect(
      kSorular[dayIndex % kSorular.length],
      'Bir şeyden korkuyorsan, o ne?',
    );
    expect(kSorular.toSet(), hasLength(kSorular.length));
  });
}
