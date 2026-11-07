import 'dart:math';

const blockBlastBoardSize = 8;
const blockBlastPaletteSize = 6;

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
  final List<int> cellColors;
  final List<BlockShape?> pieces;
  final List<int> pieceColors;
  final int score;
  final int round;
  final bool gameOver;
  final List<int> clearedCells;
  final List<int> clearedColors;

  const BlockBlastState({
    required this.cells,
    required this.pieces,
    required this.score,
    required this.round,
    required this.gameOver,
    this.clearedCells = const [],
    this.cellColors = const [],
    this.pieceColors = const [],
    this.clearedColors = const [],
  });

  factory BlockBlastState.newGame([Random? random]) {
    final rng = random ?? Random();
    return BlockBlastState(
      cells: List<bool>.filled(blockBlastBoardSize * blockBlastBoardSize, false),
      cellColors: List<int>.filled(blockBlastBoardSize * blockBlastBoardSize, 0),
      pieces: _randomPieces(rng),
      pieceColors: _randomPieceColors(rng),
      score: 0,
      round: 0,
      gameOver: false,
    );
  }
}

List<int> _randomPieceColors(Random random) =>
    (List<int>.generate(blockBlastPaletteSize, (index) => index)..shuffle(random))
        .take(3)
        .toList(growable: false);

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
  final cellColors = state.cellColors.length == state.cells.length
      ? List<int>.of(state.cellColors)
      : List<int>.filled(state.cells.length, 0);
  final pieceColor = state.pieceColors.length == state.pieces.length
      ? state.pieceColors[pieceIndex]
      : 0;
  for (final cell in shape.cells) {
    final target =
        (row + cell ~/ 10) * blockBlastBoardSize + column + cell % 10;
    cells[target] = true;
    cellColors[target] = pieceColor;
  }
  final clearedColors = List<int>.of(cellColors);
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
        final index = r * blockBlastBoardSize + c;
        cells[index] = false;
        cellColors[index] = 0;
      }
    }
  }

  var pieces = List<BlockShape?>.of(state.pieces)..[pieceIndex] = null;
  var pieceColors = state.pieceColors.length == state.pieces.length
      ? List<int>.of(state.pieceColors)
      : List<int>.filled(state.pieces.length, 0);
  var round = state.round;
  if (pieces.every((piece) => piece == null)) {
    round++;
    pieces = _randomPieces(random ?? Random());
    pieceColors = _randomPieceColors(random ?? Random());
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
    cellColors: cellColors,
    pieceColors: pieceColors,
    clearedColors: clearedColors,
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
    cellColors: nextState.cellColors,
    pieceColors: nextState.pieceColors,
    clearedColors: nextState.clearedColors,
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
