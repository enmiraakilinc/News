import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/contacts/contact_details_screen.dart';

void main() {
  testWidgets('Clear-chat action is in chat details and asks before deleting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ContactDetailsScreen(
          contactId: 'peer',
          fallbackName: 'Arkadaş',
          sourceKey: 'chat/direct',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clearAction = find.text('Sohbet içeriğini temizle');
    expect(clearAction, findsOneWidget);
    await tester.tap(clearAction);
    await tester.pumpAndSettle();
    expect(find.text('Sohbet içeriğini temizle?'), findsOneWidget);
    expect(
      find.textContaining('tüm katılımcıların cihazlarından'),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Sohbet içeriğini temizle?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear-chat action is hidden for couple conversations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ContactDetailsScreen(
          contactId: 'peer',
          fallbackName: 'Arkadaş',
          sourceKey: 'couple/pair',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sohbet içeriğini temizle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missed-call message switch is available in one-to-one details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ContactDetailsScreen(
          contactId: 'peer',
          fallbackName: 'Arkadaş',
          sourceKey: 'chat/direct',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Arama sonuçları sohbete eklenir'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Arama sonuçları sohbete eklenir'), findsOneWidget);
    expect(find.text('Cevapsız arama mesajı gönder'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
