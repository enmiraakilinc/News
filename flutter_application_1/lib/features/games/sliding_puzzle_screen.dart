import 'dart:math';

import 'package:flutter/material.dart';
import 'sliding_puzzle_logic.dart';

class SlidingPuzzleScreen extends StatefulWidget {
  const SlidingPuzzleScreen({super.key});

  @override
  State<SlidingPuzzleScreen> createState() => _SlidingPuzzleScreenState();
}

class _SlidingPuzzleScreenState extends State<SlidingPuzzleScreen> {
  final Random _random = Random();
  late List<int> _tiles;
  int _moves = 0;
  bool _completionShown = false;

  @override
  void initState() {
    super.initState();
    _shuffle();
  }

  void _shuffle() {
    _tiles = List<int>.generate(16, (index) => (index + 1) % 16);
    var empty = 15;
    for (var move = 0; move < 160; move++) {
      final neighbors = <int>[
        if (empty ~/ 4 > 0) empty - 4,
        if (empty ~/ 4 < 3) empty + 4,
        if (empty % 4 > 0) empty - 1,
        if (empty % 4 < 3) empty + 1,
      ];
      final next = neighbors[_random.nextInt(neighbors.length)];
      _tiles[empty] = _tiles[next];
      _tiles[next] = 0;
      empty = next;
    }
    if (_tiles.asMap().entries.every(
      (entry) => entry.value == (entry.key + 1) % 16,
    )) {
      _tiles.swap(14, 15);
    }
    setState(() {
      _moves = 0;
      _completionShown = false;
    });
  }

  bool _isAdjacent(int index, int empty) =>
      (index ~/ 4 == empty ~/ 4 || index % 4 == empty % 4) && index != empty;

  void _move(int index) {
    final moved = slidePuzzleTile(_tiles, index);
    if (moved == null) return;
    setState(() {
      _tiles = moved;
      _moves++;
    });
    if (_tiles.asMap().entries.every(
      (entry) => entry.value == (entry.key + 1) % 16,
    )) {
      _showCompletion();
    }
  }

  Future<void> _showCompletion() async {
    if (_completionShown) return;
    _completionShown = true;
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tebrikler!'),
        content: Text('Bulmacayı $_moves hamlede tamamladın.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yeniden karıştır'),
          ),
        ],
      ),
    );
    if (again == true && mounted) _shuffle();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('15 Taş Bulmacası'),
      actions: [
        IconButton(
          tooltip: 'Yeniden karıştır',
          onPressed: _shuffle,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Taşları boş kareye kaydırarak 1’den 15’e sırala.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Center(child: Text('Hamle: $_moves')),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AspectRatio(
                aspectRatio: 1,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 16,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final tile = _tiles[index];
                    final colors = Theme.of(context).colorScheme;
                    return Semantics(
                      label: tile == 0 ? 'Boş kare' : 'Taş $tile',
                      button:
                          tile != 0 && _isAdjacent(index, _tiles.indexOf(0)),
                      child: InkWell(
                        onTap: tile == 0 ? null : () => _move(index),
                        borderRadius: BorderRadius.circular(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tile == 0
                                ? colors.surfaceContainerHighest
                                : colors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: tile == 0
                                ? null
                                : Text(
                                    '$tile',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colors.onPrimaryContainer,
                                        ),
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
        ],
      ),
    ),
  );
}

extension<T> on List<T> {
  void swap(int first, int second) {
    final value = this[first];
    this[first] = this[second];
    this[second] = value;
  }
}
