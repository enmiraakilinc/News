import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/delivery_status.dart';

void main() {
  test('Editing preserves both delivered and read receipts', () {
    expect(
      chatDeliveryStatus(pending: false, mine: true, edited: true, read: false),
      '✓ İletildi · düzenlendi',
    );
    expect(
      chatDeliveryStatus(pending: false, mine: true, edited: true, read: true),
      '✓✓ Okundu · düzenlendi',
    );
    expect(
      chatDeliveryStatus(pending: false, mine: false, edited: true, read: true),
      'düzenlendi',
    );
    expect(
      chatDeliveryStatus(pending: true, mine: true, edited: true, read: true),
      'Gönderiliyor…',
    );
  });
}
