import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';
import 'package:flutter_application_1/features/starred/starred_messages.dart';

void main() {
  testWidgets(
    'Star and unstar update only the personal reference and reflect stream changes',
    (tester) async {
      final updates = <(String, bool)>[];
      final changes = StreamController<Set<String>>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageStarsScope(
            sourceKey: 'chat/test',
            stream: changes.stream,
            update: (id, value) async {
              updates.add((id, value));
              changes.add(value ? {id} : {});
            },
            child: const Scaffold(
              body: MessageBubble(
                mine: false,
                text: 'A message',
                time: '10:30',
                starMessageId: 'one',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.longPress(find.text('A message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yıldızla'));
      await tester.pumpAndSettle();
      expect(updates, [('one', true)]);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('A message'), findsOneWidget);
      await tester.longPress(find.text('A message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yıldızı kaldır'));
      await tester.pumpAndSettle();
      expect(updates, [('one', true), ('one', false)]);
      expect(find.byIcon(Icons.star), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
  test('References are separated by conversation and private space', () {
    expect(
      MessageStars.referenceId('chat/a', 'one'),
      isNot(MessageStars.referenceId('chat/b', 'one')),
    );
    expect(
      MessageStars.referenceId('chat/a', 'one'),
      isNot(MessageStars.referenceId('couple/a', 'one')),
    );
    expect(
      MessageStars.referenceId('chat/a', 'one'),
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
  });
}
