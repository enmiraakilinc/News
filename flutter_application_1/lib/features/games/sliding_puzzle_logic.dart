List<int>? slidePuzzleTile(List<int> tiles, int tileIndex) {
  if (tiles.length != 16 || tileIndex < 0 || tileIndex >= tiles.length) {
    return null;
  }
  final emptyIndex = tiles.indexOf(0);
  if (emptyIndex < 0 || tileIndex == emptyIndex) return null;
  final sameRow = tileIndex ~/ 4 == emptyIndex ~/ 4;
  final sameColumn = tileIndex % 4 == emptyIndex % 4;
  if (!sameRow && !sameColumn) return null;

  final moved = List<int>.of(tiles);
  if (tileIndex < emptyIndex) {
    for (var index = emptyIndex; index > tileIndex; index--) {
      moved[index] = moved[index - 1];
    }
  } else {
    for (var index = emptyIndex; index < tileIndex; index++) {
      moved[index] = moved[index + 1];
    }
  }
  moved[tileIndex] = 0;
  return moved;
}
