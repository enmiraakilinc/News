import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/updates/update_dialog.dart';
import 'package:flutter_application_1/features/updates/update_service.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Update notes are readable in $brightness theme', (
      tester,
    ) async {
      final colors = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: colors),
          home: Scaffold(
            body: UpdateDialog(
              info: UpdateInfo(
                code: 2053,
                name: '1.14.9',
                url: 'https://example.com/update.apk',
                notes: 'Genel iyileştirmeler\n• Görünüm düzenlendi.',
              ),
            ),
          ),
        ),
      );
      final title = tester.widget<Text>(find.text('Yeni sürüm 1.14.9'));
      final note = tester.widget<Text>(find.text('Görünüm düzenlendi.'));
      final heading = tester.widget<Text>(find.text('Genel iyileştirmeler'));
      expect(
        contrast(title.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(note.style!.color!, colors.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(heading.style!.color!, colors.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
