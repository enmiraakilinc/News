import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/startup/startup_gate.dart';

void main() {
  testWidgets('Slow initialization draws loading and then the home page', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          initialize: () => pending.future,
          child: const Text('Ana sayfa'),
        ),
      ),
    );
    expect(find.text('Yükleniyor…'), findsOneWidget);
    expect(find.text('Ana sayfa'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ana sayfa'), findsOneWidget);
  });

  testWidgets('Plugin failure offers retry instead of a blank page', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          initialize: () async {
            if (++attempts == 1) throw StateError('plugin');
          },
          child: const Text('Ana sayfa'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Başlatma tamamlanamadı.'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Ana sayfa'), findsOneWidget);
  });

  testWidgets('A stalled plugin times out and allows continuing', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          initialize: () => pending.future,
          timeout: const Duration(seconds: 1),
          child: const Text('Ana sayfa'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bildirimler olmadan devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Ana sayfa'), findsOneWidget);
    pending.complete();
    await tester.pump();
  });
}
