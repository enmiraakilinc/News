import 'dart:math';

const blockBlastBoardSize = 10;

class BlockShape {
  final List<int> cells;
  const BlockShape(this.cells);

  int get rows => cells.map((cell) => cell ~/ 10).reduce(_max) + 1;
  int get columns => cells.map((cell) => cell % 10).reduce(_max) + 1;
}

int _max(int first, int second) => first > second ? first : second;

const _availableShapes = <BlockShape>[
  BlockShape([0]),
  BlockShape([0, 1, 10, 11]),
  BlockShape([0, 10, 11]),
  BlockShape([0, 1, 2]),
  BlockShape([0, 10, 20]),
  BlockShape([0, 1, 2, 11]),
  BlockShape([0, 1]),
  BlockShape([0, 1, 11, 12]),
  BlockShape([0, 1, 2, 10, 11, 12, 20, 21, 22]),
];

List<BlockShape?> _randomPieces(Random random) {
  final shapes = List<BlockShape>.of(_availableShapes)..shuffle(random);
  return shapes.take(3).cast<BlockShape?>().toList(growable: false);
}

class BlockBlastState {
  final List<bool> cells;
  final List<BlockShape?> pieces;
  final int score;
  final int round;
  final bool gameOver;
  final List<int> clearedCells;

  const BlockBlastState({
    required this.cells,
    required this.pieces,
    required this.score,
    required this.round,
    required this.gameOver,
    this.clearedCells = const [],
  });

  factory BlockBlastState.newGame([Random? random]) => BlockBlastState(
    cells: List<bool>.filled(blockBlastBoardSize * blockBlastBoardSize, false),
    pieces: _randomPieces(random ?? Random()),
    score: 0,
    round: 0,
    gameOver: false,
  );
}

bool canPlaceBlock(
  BlockBlastState state,
  BlockShape shape,
  int row,
  int column,
) {
  if (row < 0 ||
      column < 0 ||
      row + shape.rows > blockBlastBoardSize ||
      column + shape.columns > blockBlastBoardSize) {
    return false;
  }
  return shape.cells.every((cell) {
    final target =
        (row + cell ~/ 10) * blockBlastBoardSize + column + cell % 10;
    return !state.cells[target];
  });
}

BlockBlastState? placeBlock(
  BlockBlastState state,
  int pieceIndex,
  int row,
  int column, [
  Random? random,
]
) {
  if (state.gameOver || pieceIndex < 0 || pieceIndex >= state.pieces.length) {
    return null;
  }
  final shape = state.pieces[pieceIndex];
  if (shape == null || !canPlaceBlock(state, shape, row, column)) return null;

  final cells = List<bool>.of(state.cells);
  for (final cell in shape.cells) {
    cells[(row + cell ~/ 10) * blockBlastBoardSize + column + cell % 10] = true;
  }
  final fullRows = <int>[
    for (var r = 0; r < blockBlastBoardSize; r++)
      if (List<bool>.generate(
        blockBlastBoardSize,
        (c) => cells[r * blockBlastBoardSize + c],
      ).every((filled) => filled))
        r,
  ];
  final fullColumns = <int>[
    for (var c = 0; c < blockBlastBoardSize; c++)
      if (List<bool>.generate(
        blockBlastBoardSize,
        (r) => cells[r * blockBlastBoardSize + c],
      ).every((filled) => filled))
        c,
  ];
  final clearedCells = <int>{
    for (var r = 0; r < blockBlastBoardSize; r++)
      if (fullRows.contains(r))
        for (var c = 0; c < blockBlastBoardSize; c++)
          r * blockBlastBoardSize + c,
    for (var c = 0; c < blockBlastBoardSize; c++)
      if (fullColumns.contains(c))
        for (var r = 0; r < blockBlastBoardSize; r++)
          r * blockBlastBoardSize + c,
  };
  for (var r = 0; r < blockBlastBoardSize; r++) {
    for (var c = 0; c < blockBlastBoardSize; c++) {
      if (clearedCells.contains(r * blockBlastBoardSize + c)) {
        cells[r * blockBlastBoardSize + c] = false;
      }
    }
  }

  var pieces = List<BlockShape?>.of(state.pieces)..[pieceIndex] = null;
  var round = state.round;
  if (pieces.every((piece) => piece == null)) {
    round++;
    pieces = _randomPieces(random ?? Random());
  }
  final nextState = BlockBlastState(
    cells: cells,
    pieces: pieces,
    score:
        state.score +
        shape.cells.length +
        (fullRows.length + fullColumns.length) * 10,
    round: round,
    gameOver: false,
    clearedCells: clearedCells.toList(growable: false),
  );
  final hasAnyMove = nextState.pieces.whereType<BlockShape>().any(
    (piece) => _hasAvailablePosition(nextState, piece),
  );
  return BlockBlastState(
    cells: nextState.cells,
    pieces: nextState.pieces,
    score: nextState.score,
    round: nextState.round,
    gameOver: !hasAnyMove,
    clearedCells: nextState.clearedCells,
  );
}

bool _hasAvailablePosition(BlockBlastState state, BlockShape shape) {
  for (var row = 0; row <= blockBlastBoardSize - shape.rows; row++) {
    for (
      var column = 0;
      column <= blockBlastBoardSize - shape.columns;
      column++
    ) {
      if (canPlaceBlock(state, shape, row, column)) return true;
    }
  }
  return false;
}
