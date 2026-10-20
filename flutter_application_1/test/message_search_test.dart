import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/utils/search_text.dart';
import 'package:flutter_application_1/features/chat/search/message_search.dart';
import 'package:flutter_application_1/features/media/message_content.dart';

void main() {
  test(
    'Search handles Turkish letters and does not search attachment binary payloads',
    () {
      expect(searchText('IŞIK İÇİN ÇÖZÜM'), searchText('ışık için çözüm'));
      final message = SearchMessage(
        '1',
        attachmentPrefix +
            jsonEncode({
              'name': 'Ödev.pdf',
              'bytes': 'private-unsearchable-content',
            }),
        DateTime.now(),
        true,
      );
      expect(message.searchable, contains('odev.pdf'));
      expect(
        message.searchable,
        isNot(contains('private-unsearchable-content')),
      );
    },
  );
  test('Future and malformed locked messages stay outside search', () {
    final now = DateTime(2026, 10, 17);
    expect(
      searchableMessageOpen(
        {
          'scheduled': true,
          'openAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
        },
        'openAt',
        now,
      ),
      false,
    );
    expect(searchableMessageOpen({'scheduled': true}, 'openAt', now), false);
    expect(searchableMessageOpen({'scheduled': false}, 'openAt', now), true);
    expect(
      searchableMessageOpen(
        {'openDate': Timestamp.fromDate(now.subtract(const Duration(days: 1)))},
        'openDate',
        now,
      ),
      true,
    );
  });
  testWidgets(
    'Typing filters loaded messages; older pages load only when requested',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pager = _Pages();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(source: 'chat/test', pager: pager),
        ),
      );
      await tester.pumpAndSettle();
      expect(pager.calls, 1);
      await tester.enterText(find.byType(TextField), 'cozum');
      await tester.pump();
      expect(find.text('Yeni çözüm'), findsOneWidget);
      expect(find.text('Eski çözüm'), findsNothing);
      expect(pager.calls, 1);
      await tester.tap(find.text('Daha eski 100 mesajda da ara'));
      await tester.pumpAndSettle();
      expect(find.text('Eski çözüm'), findsOneWidget);
      expect(pager.calls, 2);
      expect(find.text('Daha eski 100 mesajda da ara'), findsNothing);
    },
  );
}

class _Pages extends MessageSearchPager {
  _Pages() : super('chat/test');
  int calls = 0;
  @override
  Future<void> next() async {
    calls++;
    scanned += 100;
    messages.add(
      SearchMessage(
        '$calls',
        calls == 1 ? 'Yeni çözüm' : 'Eski çözüm',
        DateTime(2026, 10, 17),
        false,
      ),
    );
    done = calls == 2;
  }
}
