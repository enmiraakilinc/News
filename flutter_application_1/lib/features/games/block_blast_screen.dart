import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'game_league_service.dart';
import 'block_blast_logic.dart';

class BlockBlastScreen extends StatefulWidget {
  const BlockBlastScreen({super.key});

  @override
  State<BlockBlastScreen> createState() => _BlockBlastScreenState();
}

class _BlockBlastScreenState extends State<BlockBlastScreen> {
  final Random _random = Random();
  late BlockBlastState _game = BlockBlastState.newGame(_random);
  int? _selectedPiece;
  int? _draggingPiece;
  int? _hoverCell;
  bool _hoverValid = false;
  Set<int> _clearingCells = {};
  Timer? _clearTimer;
  bool _gameOverScoreSubmitted = false;

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  void _place(int cellIndex, {int? pieceIndex}) {
    final selected = pieceIndex ?? _selectedPiece;
    if (selected == null || _game.gameOver) return;
    final next = placeBlock(
      _game,
      selected,
      cellIndex ~/ blockBlastBoardSize,
      cellIndex % blockBlastBoardSize,
      _random,
    );
    if (next == null) {
      setState(() {
        _draggingPiece = null;
        _hoverCell = null;
      });
      return;
    }
    _clearTimer?.cancel();
    setState(() {
      _selectedPiece = next.pieces[selected] == null ? null : selected;
      _game = next;
      _clearingCells = next.clearedCells.toSet();
      _draggingPiece = null;
      _hoverCell = null;
      _hoverValid = false;
    });
    if (next.gameOver && !_gameOverScoreSubmitted) {
      _gameOverScoreSubmitted = true;
      unawaited(_recordLeagueScore(next.score));
    }
    if (_clearingCells.isNotEmpty) {
      _clearTimer = Timer(const Duration(milliseconds: 420), () {
        if (mounted) setState(() => _clearingCells = {});
      });
    }
  }

  Set<int> _previewCells() {
    final target = _hoverCell;
    final pieceIndex = _draggingPiece;
    if (target == null || pieceIndex == null || !_hoverValid) return {};
    final shape = _game.pieces[pieceIndex];
    if (shape == null) return {};
    final row = target ~/ blockBlastBoardSize;
    final column = target % blockBlastBoardSize;
    return {
      for (final cell in shape.cells)
        (row + cell ~/ 10) * blockBlastBoardSize + column + cell % 10,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Blok Bulmacası'),
      actions: [
        IconButton(
          tooltip: 'Yeni oyun',
          onPressed: () => setState(() {
            _clearTimer?.cancel();
            _game = BlockBlastState.newGame(_random);
            _selectedPiece = null;
            _draggingPiece = null;
            _hoverCell = null;
            _clearingCells = {};
            _gameOverScoreSubmitted = false;
          }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Puan: ${_game.score}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _game.gameOver
                  ? 'Hamle kalmadı. Yeni oyunla yeniden başlayabilirsin.'
                  : 'Parçaları kutularından sürükleyip tahtaya bırak. Dolu satır ve sütunlar patlayarak temizlenir.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 480,
                    maxHeight: 480,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Builder(
                      builder: (context) {
                        final preview = _previewCells();
                        return GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: blockBlastBoardSize * blockBlastBoardSize,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: blockBlastBoardSize,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                          itemBuilder: (context, index) => DragTarget<int>(
                            onWillAcceptWithDetails: (details) =>
                                details.data >= 0 &&
                                details.data < _game.pieces.length &&
                                _game.pieces[details.data] != null,
                            onMove: (details) {
                              final shape = _game.pieces[details.data];
                              if (shape == null) return;
                              final valid = canPlaceBlock(
                                _game,
                                shape,
                                index ~/ blockBlastBoardSize,
                                index % blockBlastBoardSize,
                              );
                              if (_hoverCell != index || _hoverValid != valid) {
                                setState(() {
                                  _hoverCell = index;
                                  _hoverValid = valid;
                                });
                              }
                            },
                            onLeave: (_) {
                              if (_hoverCell == index) {
                                setState(() {
                                  _hoverCell = null;
                                  _hoverValid = false;
                                });
                              }
                            },
                            onAcceptWithDetails: (details) =>
                                _place(index, pieceIndex: details.data),
                            builder: (context, candidates, rejected) {
                              final clearing = _clearingCells.contains(index);
                              final color = _game.cells[index]
                                  ? Theme.of(context).colorScheme.primary
                                  : preview.contains(index)
                                  ? Theme.of(context).colorScheme.primary
                                  : _hoverCell == index && !_hoverValid
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest;
                              final cell = DecoratedBox(
                                decoration: BoxDecoration(
                                  color: clearing
                                      ? Colors.deepOrangeAccent
                                      : color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                              return InkWell(
                                key: ValueKey('block-blast-cell-$index'),
                                child: clearing
                                    ? TweenAnimationBuilder<double>(
                                        key: ValueKey(
                                          'block-blast-clear-${_game.round}-${_game.score}-$index',
                                        ),
                                        tween: Tween(begin: 1, end: 0),
                                        duration: const Duration(
                                          milliseconds: 380,
                                        ),
                                        builder: (context, progress, child) =>
                                            Opacity(
                                              opacity: progress,
                                              child: Transform.scale(
                                                scale: 0.65 + progress * 0.35,
                                                child: child,
                                              ),
                                            ),
                                        child: cell,
                                      )
                                    : cell,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  for (var index = 0; index < _game.pieces.length; index++)
                    Expanded(
                      child: _PieceChoice(
                        index: index,
                        shape: _game.pieces[index],
                        selected: _selectedPiece == index,
                        onTap: _game.pieces[index] == null || _game.gameOver
                            ? null
                            : () => setState(() => _selectedPiece = index),
                        onDragStarted:
                            _game.pieces[index] == null || _game.gameOver
                            ? null
                            : () => setState(() {
                                _draggingPiece = index;
                                _selectedPiece = index;
                              }),
                        onDragEnd: () {
                          if (!mounted) return;
                          setState(() {
                            _draggingPiece = null;
                            _hoverCell = null;
                            _hoverValid = false;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _recordLeagueScore(int score) async {
    try {
      await GameLeagueService.recordBestScore(
        game: 'block_blast',
        score: score,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lig puanı kaydedilemedi: $error')),
        );
      }
    }
  }
}

class _PieceChoice extends StatelessWidget {
  final int index;
  final BlockShape? shape;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const _PieceChoice({
    required this.index,
    required this.shape,
    required this.selected,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    const blockSize = 20.0;
    final rows = shape?.rows ?? 3;
    final columns = shape?.columns ?? 3;
    return Center(
      child: Draggable<int>(
        key: ValueKey('block-blast-piece-$index'),
        data: index,
        maxSimultaneousDrags: shape == null ? 0 : 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnd?.call(),
        feedback: Material(
          type: MaterialType.transparency,
          child: _pieceContainer(context, blockSize, rows, columns),
        ),
        childWhenDragging: Opacity(
          opacity: 0.25,
          child: _pieceContainer(context, blockSize, rows, columns),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: _pieceContainer(context, blockSize, rows, columns),
        ),
      ),
    );
  }

  Widget _pieceContainer(
    BuildContext context,
    double blockSize,
    int rows,
    int columns,
  ) => Container(
    width: 96,
    height: 96,
    decoration: BoxDecoration(
      border: Border.all(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: shape == null
        ? const Center(child: Icon(Icons.check, color: Colors.grey))
        : Center(
            child: SizedBox(
              width: columns * blockSize,
              height: rows * blockSize,
              child: Stack(
                children: [
                  for (final cell in shape!.cells)
                    Positioned(
                      left: (cell % 10) * blockSize,
                      top: (cell ~/ 10) * blockSize,
                      width: blockSize - 2,
                      height: blockSize - 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
  );
}
