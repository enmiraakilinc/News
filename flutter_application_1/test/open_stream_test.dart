import 'dart:async';

import 'package:flutter_application_1/core/utils/open_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'A stalled listen reports the delay and still delivers the next event',
    () async {
      final source = StreamController<int>();
      final values = <int>[];
      final errors = <Object>[];
      final subscription = openStreamAfter<int>(
        () async {},
        () => source.stream,
        stall: const Duration(milliseconds: 40),
        message: 'gecikti',
      ).listen(values.add, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(errors.single, isA<TimeoutException>());
      source.add(3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(values, [3]);
      await subscription.cancel();
      await source.close();
    },
  );

  test('Cached value is shown before the live stream emits', () async {
    final source = StreamController<String>();
    final values = <String>[];
    final subscription = openStreamAfter<String>(
      () async {},
      () => source.stream,
      initial: 'önceki',
    ).listen(values.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(values, ['önceki']);
    source.add('yeni');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(values, ['önceki', 'yeni']);
    await subscription.cancel();
    await source.close();
  });
}
