import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';
import 'package:flutter_application_1/features/chat/message_selection.dart';

void main() {
  testWidgets(
    'Select messages in any order and copy only their text chronologically',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: MessageSelectionScope(
            child: Scaffold(
              body: Column(
                children: [
                  SizedBox(height: 100),
                  MessageBubble(
                    starMessageId: 'first',
                    copyOrder: 1,
                    mine: false,
                    text: 'İlk mesaj',
                    time: '10:00',
                  ),
                  MessageBubble(
                    starMessageId: 'second',
                    copyOrder: 2,
                    mine: true,
                    text: 'İkinci mesaj',
                    time: '10:01',
                  ),
                  MessageBubble(
                    starMessageId: 'locked',
                    scheduled: true,
                    mine: false,
                    text: 'Kilitli içerik',
                    time: 'Yarın',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('İkinci mesaj'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toplu seç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İlk mesaj'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilitli içerik'));
      await tester.pumpAndSettle();
      expect(find.text('2 mesaj seçildi'), findsOneWidget);
      await tester.tap(find.text('Kopyala'));
      await tester.pumpAndSettle();
      expect(copied, 'İlk mesaj\n\nİkinci mesaj');
      expect(find.text('2 mesaj seçildi'), findsNothing);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    },
  );
}
