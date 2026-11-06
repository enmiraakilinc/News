import 'package:flutter/material.dart';

import 'block_blast_logic.dart';

class BlockBlastScreen extends StatefulWidget {
  const BlockBlastScreen({super.key});

  @override
  State<BlockBlastScreen> createState() => _BlockBlastScreenState();
}

class _BlockBlastScreenState extends State<BlockBlastScreen> {
  BlockBlastState _game = BlockBlastState.newGame();
  int? _selectedPiece;

  void _place(int cellIndex) {
    if (_selectedPiece == null || _game.gameOver) return;
    final next = placeBlock(
      _game,
      _selectedPiece!,
      cellIndex ~/ blockBlastBoardSize,
      cellIndex % blockBlastBoardSize,
    );
    if (next == null) return;
    setState(() {
      _selectedPiece =
          next.round == _game.round && next.pieces[_selectedPiece!] != null
          ? _selectedPiece
          : null;
      _game = next;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Blok Bulmacası'),
      actions: [
        IconButton(
          tooltip: 'Yeni oyun',
          onPressed: () => setState(() {
            _game = BlockBlastState.newGame();
            _selectedPiece = null;
          }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
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
                : 'Bir parça seç, tahtaya yerleştir. Dolu satır ve sütunlar temizlenir.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: blockBlastBoardSize * blockBlastBoardSize,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: blockBlastBoardSize,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemBuilder: (context, index) => InkWell(
                key: ValueKey('block-blast-cell-$index'),
                onTap: () => _place(index),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _game.cells[index]
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var index = 0; index < _game.pieces.length; index++)
                Expanded(
                  child: _PieceChoice(
                    shape: _game.pieces[index],
                    selected: _selectedPiece == index,
                    onTap: _game.pieces[index] == null || _game.gameOver
                        ? null
                        : () => setState(() => _selectedPiece = index),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PieceChoice extends StatelessWidget {
  final BlockShape? shape;
  final bool selected;
  final VoidCallback? onTap;

  const _PieceChoice({
    required this.shape,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const blockSize = 20.0;
    final rows = shape?.rows ?? 3;
    final columns = shape?.columns ?? 3;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
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
        ),
      ),
    );
  }
}
