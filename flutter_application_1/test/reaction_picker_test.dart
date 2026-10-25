import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';

void main() {
  testWidgets(
    'Reactions open from action and personalized emoji list survives reopening',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      String? reacted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageBubble(
                mine: false,
                text: 'Merhaba',
                time: '12:00',
                onReact: (emoji) => reacted = emoji,
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Merhaba'));
      await tester.pumpAndSettle();
      // The supplied design now exposes personalized quick reactions above
      // the selected message, while the full editor remains a separate action.
      expect(find.text('❤️'), findsOneWidget);
      await tester.tap(find.text('İfade bırak'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emojileri düzenle'));
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(InputChip, '❤️');
      await tester.tap(
        find.descendant(of: chip, matching: find.byTooltip('Listeden çıkar')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emoji ekle (en fazla 12)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '🥰');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🥰'));
      await tester.pumpAndSettle();
      expect(reacted, '🥰');
      await tester.longPress(find.text('Merhaba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İfade bırak'));
      await tester.pumpAndSettle();
      expect(find.text('🥰'), findsOneWidget);
      expect(find.text('❤️'), findsNothing);
    },
  );
}
