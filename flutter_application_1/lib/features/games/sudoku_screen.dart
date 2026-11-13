// Sudoku ekranıdır.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_league_service.dart';
import '../contacts/chat_presence.dart';

class SudokuPuzzle {
  final List<int> solution;
  final List<int> clues;
  SudokuPuzzle(this.solution, this.clues);
  static int solutions(List<int> board, {int limit = 2}) {
    final cell = board.indexOf(0);
    if (cell < 0) return 1;
    var count = 0;
    for (var n = 1; n <= 9; n++) {
      if (!allowed(board, cell, n)) continue;
      board[cell] = n;
      count += solutions(board, limit: limit - count);
      board[cell] = 0;
      if (count >= limit) break;
    }
    return count;
  }

  static bool allowed(List<int> board, int cell, int n) {
    final row = cell ~/ 9, col = cell % 9;
    for (var i = 0; i < 81; i++) {
      if (i == cell) continue;
      if ((i ~/ 9 == row ||
              i % 9 == col ||
              (i ~/ 27 == row ~/ 3 && i % 9 ~/ 3 == col ~/ 3)) &&
          board[i] == n) {
        return false;
      }
    }
    return true;
  }

  static SudokuPuzzle generate([Random? random]) {
    final rng = random ?? Random();
    final digits = List.generate(9, (i) => i + 1)..shuffle(rng);
    List<int> order() {
      final bands = [0, 1, 2]..shuffle(rng);
      return [
        for (final b in bands)
          ...([0, 1, 2]..shuffle(rng)).map((n) => b * 3 + n),
      ];
    }

    final rows = order(), cols = order();
    final solved = [
      for (final r in rows)
        for (final c in cols) digits[(r * 3 + r ~/ 3 + c) % 9],
    ];
    final clues = List<int>.of(solved);
    final cells = List.generate(81, (i) => i)..shuffle(rng);
    var removed = 0;
    for (final cell in cells) {
      final n = clues[cell];
      clues[cell] = 0;
      if (solutions(List.of(clues)) != 1) {
        clues[cell] = n;
      } else {
        removed++;
      }
      if (removed == 40) break;
    }
    return SudokuPuzzle(solved, clues);
  }
}

class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key});
  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen> {
  SudokuPuzzle? _puzzle;
  List<int> _board = [];
  final Map<int, Set<int>> _candidates = {};
  final Map<int, Set<int>> _invalidCandidates = {};
  int? _selected;
  bool _candidateMode = false;
  bool _drawingMode = false;
  bool _completionPromptShown = false;
  bool _leagueScoreSubmitted = false;
  DateTime _startedAt = DateTime.now();
  final List<List<Offset>> _drawingStrokes = [];
  final Set<int> _incorrectCells = {};
  Future<void> _saving = Future.value();
  @override
  void initState() {
    super.initState();
    ChatPresence.setActivity('Sudoku');
    _load();
  }

  @override
  void dispose() {
    if (ChatPresence.activity.value == 'Sudoku') {
      ChatPresence.setActivity(null);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final d = jsonDecode(prefs.getString('sudoku_game') ?? '') as Map;
      final solution = List<int>.from(d['solution']),
          clues = List<int>.from(d['clues']),
          board = List<int>.from(d['board']);
      if ([
        solution,
        clues,
        board,
      ].any((b) => b.length != 81 || b.any((n) => n < 0 || n > 9))) {
        throw const FormatException();
      }
      if (mounted) {
        setState(() {
          _puzzle = SudokuPuzzle(solution, clues);
          _board = board;
          final startedAt = d['startedAt'];
          _startedAt = startedAt is int
              ? DateTime.fromMillisecondsSinceEpoch(startedAt)
              : DateTime.now();
          _leagueScoreSubmitted = List.generate(
            81,
            (i) => board[i] == solution[i],
          ).every((solved) => solved);
          _candidates
            ..clear()
            ..addAll(_readCandidates(d['candidates']));
          _drawingStrokes
            ..clear()
            ..addAll(_readDrawingStrokes(d['drawings']));
        });
      }
    } catch (_) {
      _newGame();
    }
  }

  void _newGame() {
    final puzzle = SudokuPuzzle.generate();
    if (!mounted) return;
    setState(() {
      _puzzle = puzzle;
      _board = List.of(puzzle.clues);
      _candidates.clear();
      _invalidCandidates.clear();
      _incorrectCells.clear();
      _selected = null;
      _candidateMode = false;
      _drawingMode = false;
      _completionPromptShown = false;
      _leagueScoreSubmitted = false;
      _startedAt = DateTime.now();
      _drawingStrokes.clear();
    });
    _save();
  }

  Map<int, Set<int>> _readCandidates(Object? value) {
    if (value is! Map) return {};
    final result = <int, Set<int>>{};
    for (final entry in value.entries) {
      final cell = int.tryParse(entry.key.toString());
      final values = entry.value;
      if (cell == null ||
          cell < 0 ||
          cell >= 81 ||
          _puzzle!.clues[cell] != 0 ||
          values is! List) {
        continue;
      }
      final candidates = values.whereType<int>().where((n) => n >= 1 && n <= 9);
      if (candidates.isNotEmpty) result[cell] = candidates.toSet();
    }
    return result;
  }

  List<List<Offset>> _readDrawingStrokes(Object? value) {
    if (value is! List) return [];
    final strokes = <List<Offset>>[];
    for (final item in value) {
      if (item is! List) continue;
      final stroke = <Offset>[];
      for (final point in item) {
        if (point is! Map ||
            point['x'] is! num ||
            point['y'] is! num) {
          continue;
        }
        final x = (point['x'] as num).toDouble();
        final y = (point['y'] as num).toDouble();
        if (x.isFinite &&
            y.isFinite &&
            x >= 0 &&
            x <= 1 &&
            y >= 0 &&
            y <= 1) {
          stroke.add(Offset(x, y));
        }
      }
      if (stroke.isNotEmpty) strokes.add(stroke);
    }
    return strokes;
  }

  void _save() {
    final data = jsonEncode({
      'solution': _puzzle!.solution,
      'clues': _puzzle!.clues,
      'board': List.of(_board),
      'startedAt': _startedAt.millisecondsSinceEpoch,
      'candidates': {
        for (final entry in _candidates.entries)
          '${entry.key}': entry.value.toList()..sort(),
      },
      'drawings': [
        for (final stroke in _drawingStrokes)
          [
            for (final point in stroke) {'x': point.dx, 'y': point.dy},
          ],
      ],
    });
    _saving = _saving.catchError((_) {}).then((_) async {
      await (await SharedPreferences.getInstance()).setString(
        'sudoku_game',
        data,
      );
    });
  }

  void _put(int n) {
    final cell = _selected;
    if (cell == null || _puzzle!.clues[cell] != 0) return;
    if (_candidateMode) {
      if (_board[cell] != 0) return;
      setState(() {
        if (n == 0) {
          _candidates.remove(cell);
          _invalidCandidates.remove(cell);
        } else {
          final candidates = _candidates.putIfAbsent(cell, () => <int>{});
          if (!candidates.add(n)) candidates.remove(n);
          if (candidates.isEmpty) _candidates.remove(cell);
          _invalidCandidates.remove(cell);
        }
      });
      _save();
      return;
    }
    setState(() {
      _board[cell] = n;
      _candidates.remove(cell);
      _invalidCandidates.clear();
      _incorrectCells.clear();
    });
    _save();
    if (_isSolved) {
      if (!_leagueScoreSubmitted) {
        _leagueScoreSubmitted = true;
        unawaited(_recordLeagueScore());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCompletionPrompt();
      });
    }
  }

  bool get _isSolved =>
      _puzzle != null &&
      List.generate(
        81,
        (i) => _board[i] == _puzzle!.solution[i],
      ).every((solved) => solved);

  String? _conflictDescription(int cell) {
    final number = _board[cell];
    if (number == 0) return null;
    final row = cell ~/ 9, column = cell % 9;
    final conflicts = <String>{
      if (List.generate(9, (i) => i).any(
        (i) => i != column && _board[row * 9 + i] == number,
      ))
        'satır ${row + 1}',
      if (List.generate(9, (i) => i).any(
        (i) => i != row && _board[i * 9 + column] == number,
      ))
        'sütun ${column + 1}',
      if (List.generate(81, (i) => i).any(
        (i) =>
            i != cell &&
            i ~/ 27 == row ~/ 3 &&
            i % 9 ~/ 3 == column ~/ 3 &&
            _board[i] == number,
      ))
        '3×3 kutu',
    };
    if (conflicts.isEmpty) return null;
    return '$number sayısı ${conflicts.join(' ve ')} ile çakışıyor.';
  }

  String? get _selectedConflict =>
      _selected == null ? null : _conflictDescription(_selected!);

  Future<void> _recordLeagueScore() async {
    final seconds = DateTime.now().difference(_startedAt).inSeconds.clamp(
      1,
      999999,
    );
    try {
      await GameLeagueService.recordBestScore(
        game: 'sudoku',
        score: 1000000 - seconds,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lig puanı kaydedilemedi: $error')),
        );
      }
    }
  }

  void _checkCandidates() {
    _invalidCandidates
      ..clear()
      ..addAll({
        for (final entry in _candidates.entries)
          if (entry.value.any(
            (number) => !SudokuPuzzle.allowed(_board, entry.key, number),
          ))
            entry.key: entry.value
                .where(
                  (number) => !SudokuPuzzle.allowed(_board, entry.key, number),
                )
                .toSet(),
      });
    setState(() {});
    final invalidCount = _invalidCandidates.values.fold<int>(
      0,
      (count, numbers) => count + numbers.length,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          invalidCount == 0
              ? 'Aday notlarında çakışma yok.'
              : '$invalidCount aday mevcut sayılarla çakışıyor.',
        ),
      ),
    );
  }

  void _checkPuzzle() {
    final incorrect = <int>{};
    for (var cell = 0; cell < _board.length; cell++) {
      if (_board[cell] != 0 &&
          (_board[cell] != _puzzle!.solution[cell] ||
              !SudokuPuzzle.allowed(_board, cell, _board[cell]))) {
        incorrect.add(cell);
      }
    }
    setState(() {
      _incorrectCells
        ..clear()
        ..addAll(incorrect);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          incorrect.isEmpty
              ? 'Yerleştirilen sayılar doğru.'
              : '${incorrect.length} hücredeki sayı yanlış; kırmızı hücreleri gözden geçir.',
        ),
      ),
    );
  }

  Future<void> _restartCurrentPuzzle() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulmacayı baştan başlat?'),
        content: const Text(
          'Bu bulmacadaki ilerlemen ve aday notların silinir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Baştan başlat'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _board = List.of(_puzzle!.clues);
      _candidates.clear();
      _invalidCandidates.clear();
      _incorrectCells.clear();
      _selected = null;
      _candidateMode = false;
      _drawingMode = false;
      _completionPromptShown = false;
      _leagueScoreSubmitted = false;
      _startedAt = DateTime.now();
      _drawingStrokes.clear();
    });
    _save();
  }

  Future<void> _showCompletionPrompt() async {
    if (_completionPromptShown || !_isSolved) return;
    _completionPromptShown = true;
    final another = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tebrikler!'),
        content: const Text('Sudoku tamamlandı. Yeni bir bulmaca ister misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yeni bulmaca'),
          ),
        ],
      ),
    );
    if (another == true && mounted) _newGame();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sudoku'),
      actions: [
        if (_drawingMode)
          IconButton(
            key: const ValueKey('sudoku-clear-drawing'),
            tooltip: 'Çizimleri temizle',
            icon: const Icon(Icons.delete_outline),
            onPressed: _drawingStrokes.isEmpty
                ? null
                : () {
                    setState(_drawingStrokes.clear);
                    _save();
                  },
          ),
        IconButton(
          tooltip: 'Bu bulmacayı baştan başlat',
          icon: const Icon(Icons.restart_alt),
          onPressed: _restartCurrentPuzzle,
        ),
        IconButton(
          tooltip: 'Yeni oyun',
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Yeni oyun?'),
                content: const Text('Mevcut oyunun yerine yenisi açılır.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Vazgeç'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Yeni oyun'),
                  ),
                ],
              ),
            );
            if (yes == true && mounted) _newGame();
          },
        ),
      ],
    ),
    body: _puzzle == null
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: ListView(
              physics: _drawingMode
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Her satır, sütun ve 3×3 kutuda 1–9 birer kez bulunmalı. İlerlemen bu telefonda saklanır.',
                ),
                if (_selectedConflict != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _selectedConflict!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Aday notu çiz'),
                      selected: _candidateMode,
                      onSelected: (enabled) => setState(() {
                        _candidateMode = enabled;
                        if (enabled) _drawingMode = false;
                      }),
                    ),
                    FilterChip(
                      key: const ValueKey('sudoku-drawing-mode'),
                      label: const Text('Serbest çizim'),
                      selected: _drawingMode,
                      onSelected: (enabled) => setState(() {
                        _drawingMode = enabled;
                        if (enabled) _candidateMode = false;
                      }),
                    ),
                    OutlinedButton.icon(
                      onPressed: _checkPuzzle,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Çözümü denetle'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _checkCandidates,
                      icon: const Icon(Icons.rule_outlined),
                      label: const Text('Adayları denetle'),
                    ),
                  ],
                ),
                if (_drawingMode) ...[
                  const SizedBox(height: 4),
                  const Center(
                    child: Text(
                    'Parmağınla tahtanın üzerine not al. Çizimler saklanır; '
                    'çözüm denetimi girilen sayıları kontrol eder.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: 81,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 9,
                                ),
                            itemBuilder: (context, i) {
                              final fixed = _puzzle!.clues[i] != 0;
                              final conflict =
                                  _board[i] != 0 &&
                                  !SudokuPuzzle.allowed(_board, i, _board[i]);
                              final selected = _selected == i;
                              final selectedRow =
                                  _selected != null && _selected! ~/ 9 == i ~/ 9;
                              final selectedColumn =
                                  _selected != null && _selected! % 9 == i % 9;
                              final sameBox =
                                  _selected != null &&
                                  _selected! ~/ 27 == i ~/ 27 &&
                                  _selected! % 9 ~/ 3 == i % 9 ~/ 3;
                              final sameNumber =
                                  _selected != null &&
                                  _board[_selected!] != 0 &&
                                  _board[_selected!] == _board[i];
                              final colors = Theme.of(context).colorScheme;
                              return Semantics(
                                label:
                                    'Satır ${i ~/ 9 + 1}, sütun ${i % 9 + 1}',
                                button: true,
                                child: InkWell(
                                  key: ValueKey('sudoku-cell-$i'),
                                  onTap: _drawingMode
                                      ? null
                                      : () => setState(() => _selected = i),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color:
                                          _incorrectCells.contains(i) || conflict
                                          ? colors.errorContainer
                                          : selected
                                          ? colors.primaryContainer
                                          : selectedRow ||
                                                selectedColumn ||
                                                sameBox ||
                                                sameNumber
                                          ? colors.surfaceContainerHighest
                                          : null,
                                      border: Border(
                                        top: BorderSide(
                                          width: i ~/ 9 % 3 == 0 ? 2 : 0.5,
                                        ),
                                        left: BorderSide(
                                          width: i % 3 == 0 ? 2 : 0.5,
                                        ),
                                        right: const BorderSide(width: 0.5),
                                        bottom: const BorderSide(width: 0.5),
                                      ),
                                    ),
                                    child: _board[i] == 0
                                        ? _buildCandidates(context, i)
                                        : Text(
                                            '${_board[i]}',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: fixed
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color:
                                                  _incorrectCells.contains(i) ||
                                                      conflict
                                                  ? colors.error
                                                  : fixed
                                                  ? null
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                            ),
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_drawingMode)
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    GestureDetector(
                                      key: const ValueKey(
                                        'sudoku-drawing-surface',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onPanStart: (details) {
                                        setState(() {
                                          _drawingStrokes.add([
                                            Offset(
                                              details.localPosition.dx /
                                                  constraints.maxWidth,
                                              details.localPosition.dy /
                                                  constraints.maxHeight,
                                            ),
                                          ]);
                                        });
                                      },
                                      onPanUpdate: (details) {
                                        setState(() {
                                          _drawingStrokes.last.add(
                                            Offset(
                                              details.localPosition.dx /
                                                  constraints.maxWidth,
                                              details.localPosition.dy /
                                                  constraints.maxHeight,
                                            ),
                                          );
                                        });
                                      },
                                      onPanEnd: (_) => _save(),
                                      child: CustomPaint(
                                        key: const ValueKey(
                                          'sudoku-drawing-layer',
                                        ),
                                        painter: SudokuDrawingPainter(
                                          strokes: _drawingStrokes
                                              .map(List<Offset>.of)
                                              .toList(growable: false),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.tertiary,
                                        ),
                                        size: Size.infinite,
                                      ),
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  children: [
                    for (var n = 1; n <= 9; n++)
                      OutlinedButton(
                        key: ValueKey('sudoku-number-$n'),
                        onPressed: () => _put(n),
                        child: Text('$n'),
                      ),
                    TextButton(
                      onPressed: () => _put(0),
                      child: Text(_candidateMode ? 'Adayları sil' : 'Sil'),
                    ),
                  ],
                ),
                if (_isSolved)
                  const Center(child: Text('Tebrikler! Sudoku tamamlandı.')),
              ],
            ),
          ),
  );

  Widget _buildCandidates(BuildContext context, int cell) {
    final candidates = _candidates[cell] ?? const <int>{};
    if (candidates.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.all(1),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var number = 1; number <= 9; number++)
          Center(
            child: Text(
              candidates.contains(number) ? '$number' : '',
              style: TextStyle(
                fontSize: 9,
                height: 1,
                color: _invalidCandidates[cell]?.contains(number) == true
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class SudokuDrawingPainter extends CustomPainter {
  const SudokuDrawingPainter({required this.strokes, required this.color});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      if (stroke.length == 1) {
        canvas.drawCircle(
          Offset(stroke.first.dx * size.width, stroke.first.dy * size.height),
          1.5,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SudokuDrawingPainter oldDelegate) =>
      !identical(strokes, oldDelegate.strokes) || color != oldDelegate.color;
}
