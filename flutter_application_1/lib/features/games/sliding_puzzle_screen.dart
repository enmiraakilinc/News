// Kaydırmalı bulmacanın ekranıdır.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'game_league_service.dart';
import 'sliding_puzzle_logic.dart';
import '../contacts/chat_presence.dart';

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
  bool _leagueScoreSubmitted = false;

  @override
  void initState() {
    super.initState();
    ChatPresence.setActivity('15 Taş');
    _shuffle();
  }

  @override
  void dispose() {
    if (ChatPresence.activity.value == '15 Taş') {
      ChatPresence.setActivity(null);
    }
    super.dispose();
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
      _leagueScoreSubmitted = false;
    });
  }

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
      if (!_leagueScoreSubmitted) {
        _leagueScoreSubmitted = true;
        unawaited(_recordLeagueScore());
      }
      _showCompletion();
    }
  }

  Future<void> _recordLeagueScore() async {
    try {
      await GameLeagueService.recordBestScore(
        game: 'sliding_puzzle',
        score: (10000 - _moves).clamp(1, 10000),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lig puanı kaydedilemedi: $error')),
        );
      }
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
          LayoutBuilder(
            builder: (context, constraints) {
              final board = constraints.maxWidth > 480 ? 480.0 : constraints.maxWidth - 40;
              final cell = board / 4;
              final colors = Theme.of(context).colorScheme;
              return Center(
                child: GestureDetector(
                  onPanEnd: (details) {
                    final velocity = details.velocity.pixelsPerSecond;
                    if (velocity.dx.abs() <= velocity.dy.abs()) return;
                    final empty = _tiles.indexOf(0);
                    final neighbor = empty + (velocity.dx > 0 ? -1 : 1);
                    if (neighbor >= 0 &&
                        neighbor < 16 &&
                        neighbor ~/ 4 == empty ~/ 4) {
                      _move(neighbor);
                    }
                  },
                  child: SizedBox(
                    width: board,
                    height: board,
                    child: Stack(
                      children: [
                        for (var index = 0; index < 16; index++)
                          if (_tiles[index] != 0)
                            AnimatedPositioned(
                              key: ValueKey('sliding-puzzle-tile-${_tiles[index]}'),
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              left: (index % 4) * cell + 3,
                              top: (index ~/ 4) * cell + 3,
                              width: cell - 6,
                              height: cell - 6,
                              child: Material(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () => _move(index),
                                  child: Center(
                                    child: Text(
                                      '${_tiles[index]}',
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
                            ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
