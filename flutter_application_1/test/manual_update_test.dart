import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/updates/update_check_tile.dart';
import 'package:flutter_application_1/features/updates/update_service.dart';

void main() {
  testWidgets('Manual check disables repeated taps and distinguishes failure', (
    tester,
  ) async {
    final result = Completer<UpdateInfo?>();
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateCheckTile(
            check: () {
              checks++;
              return result.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Güncellemeler'));
    await tester.pump();
    await tester.tap(find.text('Güncellemeler'));
    expect(checks, 1);
    expect(find.text('Güncelleme kontrol ediliyor…'), findsOneWidget);
    result.completeError(const UpdateCheckException('Bağlantı kurulamadı.'));
    await tester.pumpAndSettle();
    expect(find.text('Bağlantı kurulamadı.'), findsOneWidget);
    expect(find.text('Uygulaman güncel.'), findsNothing);
  });
  testWidgets('New version remains visible and opens the existing installer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final info = UpdateInfo(
      code: 2081,
      name: '1.15.2',
      url: 'https://example.com/updates/apk',
      notes: 'Kararlılık iyileştirmeleri.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UpdateCheckTile(check: () async => info)),
      ),
    );
    await tester.tap(find.text('Güncellemeler'));
    await tester.pumpAndSettle();
    expect(find.text('1.15.2 hazır. Güncellemek için dokun.'), findsOneWidget);
    await tester.tap(find.text('Güncellemeler'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni sürüm 1.15.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
