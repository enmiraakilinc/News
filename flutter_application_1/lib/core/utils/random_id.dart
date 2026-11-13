import 'dart:math';

/// Güvenli rastgele onaltılık kimlik. [bytes] kadar bayt üretir.
String randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
