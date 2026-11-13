// Blok oyununun ekranıdır.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'block_blast_logic.dart';
import '../contacts/chat_presence.dart';

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

  @override
  void dispose() {
    _clearTimer?.cancel();
    if (ChatPresence.activity.value == 'Block Blast') {
      ChatPresence.setActivity(null);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ChatPresence.setActivity('Block Blast');
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
                  : 'Blokları sürükle, satırları ve sütunları tamamla.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 420,
                    maxHeight: 420,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff111d3a),
                        border: Border.all(color: const Color(0xff34456d)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Builder(
                          builder: (context) {
                            final preview = _previewCells();
                            final selectedPiece =
                                _draggingPiece ?? _selectedPiece;
                            final previewColor = selectedPiece == null
                                ? 0
                                : selectedPiece < _game.pieceColors.length
                                ? _game.pieceColors[selectedPiece]
                                : selectedPiece % blockBlastPalette.length;
                            return GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount:
                                  blockBlastBoardSize * blockBlastBoardSize,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: blockBlastBoardSize,
                                    mainAxisSpacing: 4,
                                    crossAxisSpacing: 4,
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
                                  if (_hoverCell != index ||
                                      _hoverValid != valid) {
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
                                  final clearing = _clearingCells.contains(
                                    index,
                                  );
                                  final color = _game.cells[index]
                                      ? Color(
                                          blockBlastPalette[_game
                                                      .cellColors
                                                      .length ==
                                                  _game.cells.length
                                              ? _game.cellColors[index]
                                              : 0],
                                        )
                                      : preview.contains(index)
                                      ? Color(
                                          blockBlastPalette[previewColor],
                                        ).withValues(alpha: 0.45)
                                      : _hoverCell == index && !_hoverValid
                                      ? const Color(0xff8e3447)
                                      : const Color(0xff1d2b4a);
                                  final clearColor = Color(
                                    blockBlastPalette[_game.cellColors.length ==
                                            _game.cells.length
                                        ? _game.cellColors[index]
                                        : index % blockBlastPalette.length],
                                  );
                                  final cell = DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: clearing ? clearColor : color,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  );
                                  return InkWell(
                                    key: ValueKey('block-blast-cell-$index'),
                                    child: clearing
                                        ? TweenAnimationBuilder<double>(
                                            key: ValueKey(
                                              'block-blast-clear-${_game.round}-${_game.score}-$index',
                                            ),
                                            tween: Tween(begin: 0, end: 1),
                                            duration: const Duration(
                                              milliseconds: 420,
                                            ),
                                            builder:
                                                (
                                                  context,
                                                  progress,
                                                  child,
                                                ) => Transform.scale(
                                                  scale: 1 + progress * .45,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: clearColor,
                                                          blurRadius:
                                                              12 *
                                                              (1 - progress),
                                                          spreadRadius:
                                                              3 *
                                                              (1 - progress),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Opacity(
                                                      opacity: 1 - progress,
                                                      child: child,
                                                    ),
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
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: Row(
                children: [
                  for (var index = 0; index < _game.pieces.length; index++)
                    Expanded(
                      child: _PieceChoice(
                        index: index,
                        shape: _game.pieces[index],
                        color: Color(
                          blockBlastPalette[index < _game.pieceColors.length
                              ? _game.pieceColors[index]
                              : index % blockBlastPalette.length],
                        ),
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

}

class _PieceChoice extends StatelessWidget {
  final int index;
  final BlockShape? shape;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const _PieceChoice({
    required this.index,
    required this.shape,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    const blockSize = 18.0;
    const lift = 72.0;
    final rows = shape?.rows ?? 3;
    final columns = shape?.columns ?? 3;
    final anchor = Offset(columns * blockSize / 2, rows * blockSize + lift);
    return Center(
      child: Draggable<int>(
        key: ValueKey('block-blast-piece-$index'),
        data: index,
        maxSimultaneousDrags: shape == null ? 0 : 1,
        dragAnchorStrategy: (_, _, _) => anchor,
        feedbackOffset: -anchor + const Offset(blockSize / 2, blockSize / 2),
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnd?.call(),
        feedback: Material(
          type: MaterialType.transparency,
          child: _piece(context, blockSize, rows, columns),
        ),
        childWhenDragging: Opacity(
          opacity: 0.25,
          child: _piece(context, blockSize, rows, columns),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: const Duration(milliseconds: 140),
            child: _piece(context, blockSize, rows, columns),
          ),
        ),
      ),
    );
  }

  Widget _piece(
    BuildContext context,
    double blockSize,
    int rows,
    int columns,
  ) => SizedBox(
    width: columns * blockSize,
    height: rows * blockSize,
    child: shape == null
        ? const Icon(Icons.check, color: Colors.white54)
        : Stack(
            children: [
              for (final cell in shape!.cells)
                Positioned(
                  left: (cell % 10) * blockSize,
                  top: (cell ~/ 10) * blockSize,
                  width: blockSize - 2,
                  height: blockSize - 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: .28),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
