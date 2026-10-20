import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/account/chat_account.dart';

void main() {
  test('Personal codes accept pasted formatting but reject invite codes', () {
    const code = '01234567-89abcdef-01234567-89abcdef';
    expect(ChatAccount.displayCode('  ${code.toUpperCase()}\n'), code);
    expect(
      ChatAccount.emailForCode(code),
      '0123456789abcdef0123456789abcdef@accounts.neural.invalid',
    );
    expect(() => ChatAccount.normalizeCode('12345678'), throwsFormatException);
    expect(() => ChatAccount.normalizeCode('g' * 32), throwsFormatException);
    expect(() => ChatAccount.normalizeCode('a' * 33), throwsFormatException);
  });
  test(
    'Generated account identifiers are independent and passwords validated',
    () {
      final codes = List.generate(100, (_) => ChatAccount.newCode());
      expect(codes.toSet().length, 100);
      for (final code in codes) {
        expect(ChatAccount.normalizeCode(code).length, 32);
      }
      expect(
        () => ChatAccount.validatePassword('short'),
        throwsFormatException,
      );
      expect(
        () => ChatAccount.validatePassword('a' * 129),
        throwsFormatException,
      );
      ChatAccount.validatePassword('example-passphrase');
    },
  );
}
