import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';
import 'package:flutter_application_1/features/pair/couple_service.dart';

void main() {
  testWidgets(
    'Three messages send before acknowledgments, with no duplicate tap or lost draft',
    (tester) async {
      final texts = <String>[];
      final deliveries = <Completer<void>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ChatComposer(
              onSend: (text, _) {
                texts.add(text);
                final delivery = Completer<void>();
                deliveries.add(delivery);
                return delivery.future;
              },
            ),
          ),
        ),
      );
      for (final text in ['One', 'Two', 'Three']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.byTooltip('Gönder'));
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(tester.testTextInput.isVisible, isTrue);
      }
      await tester.tap(find.byTooltip('Gönder'));
      expect(texts, ['One', 'Two', 'Three']);
      await tester.enterText(find.byType(TextField), 'Next draft');
      deliveries[2].complete();
      deliveries[0].completeError(Exception('Rejected'));
      deliveries[1].complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Next draft',
      );
      expect(find.text('Gönderilemedi'), findsOneWidget);
      expect(find.text('One'), findsOneWidget);
      await tester.tap(find.text('Tekrar gönder'));
      await tester.pump();
      expect(texts, ['One', 'Two', 'Three', 'One']);
      deliveries.last.complete();
      await tester.pumpAndSettle();
      expect(find.text('Gönderilemedi'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Next draft',
      );
    },
  );

  testWidgets('Retry keeps the original reply handler after composer rebuild', (
    tester,
  ) async {
    String reply = 'original';
    final attempts = <String>[];
    final first = Completer<void>();
    Widget composer() {
      final capturedReply = reply;
      return MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatComposer(
            onSend: (_, _) {
              attempts.add(capturedReply);
              return attempts.length == 1 ? first.future : Future.value();
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(composer());
    await tester.enterText(find.byType(TextField), 'Reply');
    await tester.tap(find.byTooltip('Gönder'));
    reply = 'different';
    await tester.pumpWidget(composer());
    first.completeError(Exception('Rejected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekrar gönder'));
    await tester.pumpAndSettle();
    expect(attempts, ['original', 'original']);
  });

  test(
    'Letter cache decodes only changes and clears on secret change or removal',
    () async {
      final batches = <Map<String, String>>[];
      final cache = LetterDecodeCache(
        worker: (payload) async {
          final batch = Map<String, String>.from(payload['ciphers'] as Map);
          batches.add(batch);
          return batch.map(
            (id, value) => MapEntry(id, '${payload['secret']}:$value'),
          );
        },
      );
      expect(await cache.decode('a', {'1': 'old'}), {'1': 'a:old'});
      await cache.decode('a', {'1': 'old'}); // Receipt/reaction-only snapshot.
      expect(batches.length, 1);
      await cache.decode('a', {'1': 'old', '2': 'new'});
      expect(batches.last, {'2': 'new'});
      expect(await cache.decode('a', {'2': 'edited'}), {'2': 'a:edited'});
      expect(await cache.decode('b', {'2': 'edited'}), {'2': 'b:edited'});
      expect(batches.length, 4);
      expect(await cache.decode('b', {}), isEmpty);
    },
  );
}
