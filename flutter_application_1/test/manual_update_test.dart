import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/updates/update_check_tile.dart';
import 'package:flutter_application_1/features/updates/update_service.dart';

void main() {
  test('Public GitHub releases provide a verified, unauthenticated update', () {
    final update = publicGithubUpdate({
      'tag_name': 'v1.16.6',
      'draft': false,
      'prerelease': false,
      'body': 'Build code: 2087\nSohbet bildirimleri artık anında iletilir.',
      'assets': [
        {
          'name': 'Neural-Haber-1.16.6-arm64.apk',
          'browser_download_url':
              'https://github.com/enmiraakilinc/News/releases/download/v1.16.6/Neural-Haber-1.16.6-arm64.apk',
          'digest': 'sha256:${'a' * 64}',
        },
      ],
    }, currentCode: 2086);

    expect(update?.code, 2087);
    expect(update?.name, '1.16.6');
    expect(update?.authenticated, isFalse);
    expect(update?.sha256, 'a' * 64);
    expect(update?.notes, 'Sohbet bildirimleri artık anında iletilir.');
  });

  test(
    'Public GitHub update rejects untrusted assets and unversioned builds',
    () {
      final release = {
        'tag_name': 'v1.16.6',
        'draft': false,
        'prerelease': false,
        'body': 'Build code: 2087',
        'assets': [
          {
            'name': 'Neural-Haber-1.16.6-arm64.apk',
            'browser_download_url':
                'https://attacker.example/Neural-Haber-1.16.6-arm64.apk',
            'digest': 'sha256:${'a' * 64}',
          },
        ],
      };
      expect(publicGithubUpdate(release, currentCode: 2086), isNull);
      expect(
        publicGithubUpdate({...release, 'body': ''}, currentCode: 2086),
        isNull,
      );
      expect(publicGithubUpdate(release, currentCode: 2087), isNull);
    },
  );

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
