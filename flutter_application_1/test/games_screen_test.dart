import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/games/sliding_puzzle_screen.dart';
import 'package:flutter_application_1/features/games/sudoku_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Sudoku candidate notes can be entered and checked', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SudokuScreen()));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('sudoku_game')!) as Map;
    final solution = List<int>.from(saved['solution']);
    final clues = List<int>.from(saved['clues']);
    final cell = clues.indexWhere((number) => number == 0);

    await tester.tap(find.byKey(ValueKey('sudoku-cell-$cell')));
    await tester.tap(find.text('Aday notu çiz'));
    final numberButton = find.byKey(
      ValueKey('sudoku-number-${solution[cell]}'),
    );
    await tester.scrollUntilVisible(
      numberButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(numberButton);
    await tester.pumpAndSettle();

    final updated = jsonDecode(prefs.getString('sudoku_game')!) as Map;
    expect((updated['candidates'] as Map)['$cell'], contains(solution[cell]));
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adayları denetle'));
    await tester.pumpAndSettle();
    expect(find.text('Aday notlarında çakışma yok.'), findsOneWidget);
  });

  testWidgets('Sudoku can restart its current puzzle without replacing it', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SudokuScreen()));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final original = jsonDecode(prefs.getString('sudoku_game')!) as Map;
    final clues = List<int>.from(original['clues']);
    final cell = clues.indexWhere((number) => number == 0);

    await tester.tap(find.byKey(ValueKey('sudoku-cell-$cell')));
    final number = List<int>.from(original['solution'])[cell];
    final numberButton = find.byKey(ValueKey('sudoku-number-$number'));
    await tester.scrollUntilVisible(
      numberButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(numberButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bu bulmacayı baştan başlat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baştan başlat'));
    await tester.pumpAndSettle();

    final restarted = jsonDecode(prefs.getString('sudoku_game')!) as Map;
    expect(restarted['solution'], original['solution']);
    expect(restarted['board'], clues);
  });

  testWidgets('Sudoku drawing mode renders strokes and can clear them', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SudokuScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sudoku-drawing-mode')));
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('sudoku-drawing-surface'));
    await tester.ensureVisible(surface);
    final rect = tester.getRect(surface);
    await tester.dragFrom(
      rect.topLeft + const Offset(20, 20),
      const Offset(90, 75),
    );
    await tester.pumpAndSettle();

    final drawing = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('sudoku-drawing-layer')),
    );
    expect((drawing.painter as SudokuDrawingPainter).strokes, hasLength(1));
    expect(
      (drawing.painter as SudokuDrawingPainter).strokes.single.length,
      greaterThan(1),
    );

    final clear = find.byKey(const ValueKey('sudoku-clear-drawing'));
    await tester.tap(clear);
    await tester.pumpAndSettle();
    final cleared = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('sudoku-drawing-layer')),
    );
    expect((cleared.painter as SudokuDrawingPainter).strokes, isEmpty);
  });

  testWidgets('Completing Sudoku offers to start another puzzle', (
    tester,
  ) async {
    final solution = <int>[
      5,
      3,
      4,
      6,
      7,
      8,
      9,
      1,
      2,
      6,
      7,
      2,
      1,
      9,
      5,
      3,
      4,
      8,
      1,
      9,
      8,
      3,
      4,
      2,
      5,
      6,
      7,
      8,
      5,
      9,
      7,
      6,
      1,
      4,
      2,
      3,
      4,
      2,
      6,
      8,
      5,
      3,
      7,
      9,
      1,
      7,
      1,
      3,
      9,
      2,
      4,
      8,
      5,
      6,
      9,
      6,
      1,
      5,
      3,
      7,
      2,
      8,
      4,
      2,
      8,
      7,
      4,
      1,
      9,
      6,
      3,
      5,
      3,
      4,
      5,
      2,
      8,
      6,
      1,
      7,
      9,
    ];
    final clues = List<int>.of(solution)..[0] = 0;
    SharedPreferences.setMockInitialValues({
      'sudoku_game': jsonEncode({
        'solution': solution,
        'clues': clues,
        'board': clues,
      }),
    });
    await tester.pumpWidget(const MaterialApp(home: SudokuScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sudoku-cell-0')));
    final five = find.byKey(const ValueKey('sudoku-number-5'));
    await tester.scrollUntilVisible(
      five,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(five);
    await tester.pumpAndSettle();

    expect(
      find.text('Sudoku tamamlandı. Yeni bir bulmaca ister misin?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
  });

  testWidgets('15-tile puzzle presents a playable 4×4 board', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SlidingPuzzleScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Hamle: 0'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.bySemanticsLabel('Boş kare'), findsOneWidget);
  });
}
