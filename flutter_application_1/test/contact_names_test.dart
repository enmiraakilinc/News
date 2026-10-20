import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/contacts/contact_names.dart';

void main() {
  testWidgets('Posni adı değiştirilebilir ve yeniden yüklenince korunur', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'contact_alias_letters_partner': 'Posni',
    });
    await ContactNames.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  ContactNames.rename(context, ContactNames.posniId, 'Posni'),
              child: const Text('Adı değiştir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Adı değiştir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Arkadaşım');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await ContactNames.load();
    expect(ContactNames.name(ContactNames.posniId, 'Posni'), 'Arkadaşım');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'contact_alias_letters_partner',
      ),
      'Arkadaşım',
    );
  });
}
