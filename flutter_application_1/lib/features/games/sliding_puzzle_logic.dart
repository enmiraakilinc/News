List<int>? slidePuzzleTile(List<int> tiles, int tileIndex) {
  if (tiles.length != 16 || tileIndex < 0 || tileIndex >= tiles.length) {
    return null;
  }
  final emptyIndex = tiles.indexOf(0);
  if (emptyIndex < 0 || tileIndex == emptyIndex) return null;
  final sameRow = tileIndex ~/ 4 == emptyIndex ~/ 4;
  final sameColumn = tileIndex % 4 == emptyIndex % 4;
  if (!sameRow && !sameColumn) return null;

  final step = sameRow ? 1 : 4;
  final moved = List<int>.of(tiles);
  if (tileIndex < emptyIndex) {
    for (var index = emptyIndex; index > tileIndex; index -= step) {
      moved[index] = moved[index - step];
    }
  } else {
    for (var index = emptyIndex; index < tileIndex; index += step) {
      moved[index] = moved[index + step];
    }
  }
  moved[tileIndex] = 0;
  return moved;
}
