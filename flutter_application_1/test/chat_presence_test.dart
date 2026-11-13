// İlgili ekran veya kuralın otomatik sınamasıdır.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/contacts/chat_presence.dart';

void main() {
  final now = DateTime(2026, 11, 1, 23, 45);

  test('Online presence has no clock label and expires promptly', () {
    expect(
      isPresenceOnline(now.subtract(const Duration(seconds: 44)), now: now),
      isTrue,
    );
    expect(
      isPresenceOnline(now.subtract(const Duration(seconds: 45)), now: now),
      isFalse,
    );
    expect(
      isPresenceOnline(now.add(const Duration(seconds: 1)), now: now),
      isFalse,
    );
  });

  test('Last seen uses today, yesterday and dates for older activity', () {
    expect(
      formatLastSeen(DateTime(2026, 11, 1, 9, 5), now: now),
      'Bugün 09:05',
    );
    expect(formatLastSeen(DateTime(2026, 11, 1, 23, 44), now: now), 'Az önce');
    expect(
      formatLastSeen(DateTime(2026, 11, 1, 23, 15), now: now),
      '30 dk önce',
    );
    expect(
      formatLastSeen(DateTime(2026, 10, 31, 23, 10), now: now),
      'Dün 23:10',
    );
    expect(
      formatLastSeen(DateTime(2026, 10, 30, 8, 2), now: now),
      '30.10 08:02',
    );
    expect(formatLastSeen(null, now: now), isNull);
  });
}
