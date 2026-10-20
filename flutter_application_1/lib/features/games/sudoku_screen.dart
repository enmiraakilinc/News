import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int? _selected;
  Future<void> _saving = Future.value();
  @override
  void initState() {
    super.initState();
    _load();
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
      _selected = null;
    });
    _save();
  }

  void _save() {
    final data = jsonEncode({
      'solution': _puzzle!.solution,
      'clues': _puzzle!.clues,
      'board': List.of(_board),
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
    setState(() => _board[cell] = n);
    _save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sudoku'),
      actions: [
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
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Her satır, sütun ve 3×3 kutuda 1–9 birer kez bulunmalı. İlerlemen bu telefonda saklanır.',
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GridView.builder(
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
                          return Semantics(
                            label: 'Satır ${i ~/ 9 + 1}, sütun ${i % 9 + 1}',
                            button: true,
                            child: InkWell(
                              onTap: () => setState(() => _selected = i),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _selected == i
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
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
                                child: Text(
                                  _board[i] == 0 ? '' : '${_board[i]}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: fixed
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: conflict
                                        ? Colors.red
                                        : fixed
                                        ? null
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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
                        onPressed: () => _put(n),
                        child: Text('$n'),
                      ),
                    TextButton(
                      onPressed: () => _put(0),
                      child: const Text('Sil'),
                    ),
                  ],
                ),
                if (_board.every((n) => n != 0) &&
                    List.generate(
                      81,
                      (i) => SudokuPuzzle.allowed(_board, i, _board[i]),
                    ).every((ok) => ok))
                  const Center(child: Text('Tebrikler! Sudoku tamamlandı.')),
              ],
            ),
          ),
  );
}
