import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../contacts/chat_presence.dart';
import 'game_league_screen.dart';
import 'game_league_service.dart';
import 'block_blast_logic.dart';

const _blockColors = <Color>[
  Color(0xFF49D5E8),
  Color(0xFFFFC857),
  Color(0xFFB88CFF),
  Color(0xFFFF6B8A),
  Color(0xFF69D99A),
  Color(0xFFFF9566),
];

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
  Offset _dragAnchorCell = Offset.zero;
  int? _hoverCell;
  bool _hoverValid = false;
  Set<int> _clearingCells = {};
  Timer? _clearTimer;
  bool _gameOverScoreSubmitted = false;

  @override
  void dispose() {
    _clearTimer?.cancel();
    ChatPresence.clearActivity('Block Blast');
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ChatPresence.setActivity('Block Blast');
  }

  void _place(int targetRow, int targetColumn, {int? pieceIndex}) {
    final selected = pieceIndex ?? _selectedPiece;
    if (selected == null || _game.gameOver) return;
    final next = placeBlock(
      _game,
      selected,
      targetRow - _dragAnchorCell.dy.toInt(),
      targetColumn - _dragAnchorCell.dx.toInt(),
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
    final row = target ~/ blockBlastBoardSize - _dragAnchorCell.dy.toInt();
    final column = target % blockBlastBoardSize - _dragAnchorCell.dx.toInt();
    return {
      for (final cell in shape.cells)
        (row + cell ~/ 10) * blockBlastBoardSize + column + cell % 10,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0B1533),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0B1533),
      foregroundColor: Colors.white,
      title: const Text(
        'BLOCK BLAST',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.4),
      ),
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
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ScoreCard(
                    label: 'PUAN',
                    value: '${_game.score}',
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFFFFC857),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ScoreCard(
                    label: 'TUR',
                    value: '${_game.round + 1}',
                    icon: Icons.grid_view_rounded,
                    color: const Color(0xFF49D5E8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _game.gameOver
                  ? 'Hamle kalmadı. Yeni oyunla yeniden başlayabilirsin.'
                  : 'Parçayı tut, tahtada istediğin yere bırak.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB9C8E8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 480,
                    maxHeight: 480,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF142044),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF26365F)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Builder(
                          builder: (context) {
                            final preview = _previewCells();
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
                                  final row =
                                      index ~/ blockBlastBoardSize -
                                      _dragAnchorCell.dy.toInt();
                                  final column =
                                      index % blockBlastBoardSize -
                                      _dragAnchorCell.dx.toInt();
                                  final valid = canPlaceBlock(
                                    _game,
                                    shape,
                                    row,
                                    column,
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
                                onAcceptWithDetails: (details) => _place(
                                  index ~/ blockBlastBoardSize,
                                  index % blockBlastBoardSize,
                                  pieceIndex: details.data,
                                ),
                                builder: (context, candidates, rejected) {
                                  final clearing = _clearingCells.contains(
                                    index,
                                  );
                                  final previewColor = _draggingPiece == null
                                      ? _blockColors.first
                                      : _blockColors[_game.pieceColors.length ==
                                                _game.pieces.length
                                            ? _game.pieceColors[_draggingPiece!]
                                            : 0];
                                  final color = _game.cells[index]
                                      ? _blockColors[_game.cellColors.length ==
                                                _game.cells.length
                                            ? _game.cellColors[index]
                                            : 0]
                                      : preview.contains(index)
                                      ? previewColor
                                      : _hoverCell == index && !_hoverValid
                                      ? const Color(0xFFFF5F78)
                                      : const Color(0xFF26345A);
                                  final clearColor =
                                      _game.clearedColors.length ==
                                          _game.cells.length
                                      ? _blockColors[_game.clearedColors[index]]
                                      : const Color(0xFFFFC857);
                                  final cell = DecoratedBox(
                                    key: ValueKey('block-blast-cell-$index'),
                                    decoration: BoxDecoration(
                                      color: clearing ? clearColor : color,
                                      borderRadius: BorderRadius.circular(5),
                                      boxShadow:
                                          color == const Color(0xFF26345A)
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: color.withValues(
                                                  alpha: 0.28,
                                                ),
                                                blurRadius: 8,
                                              ),
                                            ],
                                    ),
                                  );
                                  return clearing
                                      ? TweenAnimationBuilder<double>(
                                          key: ValueKey(
                                            'block-blast-clear-${_game.round}-${_game.score}-$index',
                                          ),
                                          tween: Tween(begin: 1, end: 0),
                                          duration: const Duration(
                                            milliseconds: 420,
                                          ),
                                          builder: (context, progress, child) =>
                                              Opacity(
                                                opacity: progress,
                                                child: Transform.scale(
                                                  scale: 0.45 + progress * 0.55,
                                                  child: child,
                                                ),
                                              ),
                                          child: cell,
                                        )
                                      : cell;
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
            const SizedBox(height: 10),
            const Text(
              'PARÇANI SEÇ VE TAHTAYA SÜRÜKLE',
              style: TextStyle(
                color: Color(0xFF90A5D1),
                fontSize: 10,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  for (var index = 0; index < _game.pieces.length; index++)
                    Expanded(
                      child: _PieceChoice(
                        index: index,
                        shape: _game.pieces[index],
                        color:
                            _blockColors[_game.pieceColors.length ==
                                    _game.pieces.length
                                ? _game.pieceColors[index]
                                : 0],
                        selected: _selectedPiece == index,
                        onDragAnchorChanged: (anchor) {
                          _dragAnchorCell = Offset(
                            (anchor.dx / 20).floorToDouble(),
                            (anchor.dy / 20).floorToDouble(),
                          );
                        },
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB9C8E8),
                  side: const BorderSide(color: Color(0xFF34466F)),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GameLeagueScreen(),
                  ),
                ),
                icon: const Icon(Icons.emoji_events_outlined, size: 18),
                label: const Text('Oyun ligini gör'),
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
  final Color color;
  final bool selected;
  final ValueChanged<Offset> onDragAnchorChanged;
  final VoidCallback? onTap;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const _PieceChoice({
    required this.index,
    required this.shape,
    required this.color,
    required this.selected,
    required this.onDragAnchorChanged,
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
        dragAnchorStrategy: (draggable, context, position) {
          final box = context.findRenderObject()! as RenderBox;
          final local = box.globalToLocal(position);
          final shapeSize = Size(columns * blockSize, rows * blockSize);
          final shapeOffset = Offset(
            (box.size.width - shapeSize.width) / 2,
            (box.size.height - shapeSize.height) / 2,
          );
          final anchor = local - shapeOffset;
          onDragAnchorChanged(anchor);
          return anchor;
        },
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnd?.call(),
        feedback: Material(
          type: MaterialType.transparency,
          child: _pieceShape(blockSize, rows, columns),
        ),
        childWhenDragging: Opacity(
          opacity: 0.25,
          child: _pieceShape(blockSize, rows, columns),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 96,
            height: 96,
            child: Center(child: _pieceShape(blockSize, rows, columns)),
          ),
        ),
      ),
    );
  }

  Widget _pieceShape(double blockSize, int rows, int columns) => SizedBox(
    key: ValueKey('block-blast-piece-shape-$index'),
    width: columns * blockSize,
    height: rows * blockSize,
    child: shape == null
        ? const SizedBox.shrink()
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
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(
                            alpha: selected ? 0.56 : 0.28,
                          ),
                          blurRadius: selected ? 10 : 5,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ScoreCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF142044),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF26365F)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF90A5D1),
                fontSize: 9,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
