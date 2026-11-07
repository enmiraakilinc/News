import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/features/questions/question_screen.dart';

void main() {
  test(
    'Question schedule starts on the selected question and never repeats',
    () {
      expect(kSorular.length, 92);
      expect(
        kSorular.first,
        'Çocukken doğru sandığın ama sonradan değişen bir fikrin neydi?',
      );
      expect(kSorular.toSet(), hasLength(kSorular.length));
      for (final removedQuestion in [
        'En sevdiğin aile anın hangisi?',
        'Hiç unutamadığın bir yolculuk var mı?',
        'Küçük bir hayalin ne?',
        'Hiç kimseye anlatmadığın bir hayalin var mı?',
        'Hayatında değiştirmek istediğin bir alışkanlık var mı?',
        'En sevdiğin şarkı hangisi, neden?',
        'En sevdiğin mevsim hangisi, neden?',
        'En sevdiğin yemek hangisi, kim yapınca?',
        'En sevdiğin koku hangisi?',
        'En sevdiğin kitap hangisi?',
        'En sevdiğin dizi karakteri kim, neden?',
        'En sevdiğin oyun ya da hobin hangisi?',
      ]) {
        expect(kSorular, isNot(contains(removedQuestion)));
      }
      expect(
        kSorular,
        contains(
          'Bir yolculukta planların bozulsa, ilk neye göre karar verirsin?',
        ),
      );

      expect(questionIndexForDate(DateTime(2026, 11, 6)), isNull);
      expect(questionIndexForDate(DateTime(2026, 11, 7)), 0);
      expect(questionIndexForDate(DateTime(2026, 11, 8)), 1);
      expect(questionIndexForDate(DateTime(2027, 2, 6)), 91);
      expect(questionIndexForDate(DateTime(2027, 2, 7)), isNull);
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
