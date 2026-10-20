import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/utils/refresh_stream.dart';

void main() {
  test(
    'A paused async generator must not replay unchanged chat snapshots',
    () async {
      final source = StreamController<int>();
      Stream<int> gated() async* {
        await for (final value in refreshStream<int>(
          source.stream,
          nextRefreshAt: (_) => null,
        ).timeout(const Duration(seconds: 25), onTimeout: (_) {})) {
          yield value;
        }
      }

      final values = <int>[];
      // Bound the stream so the previous feedback loop cannot hang the test.
      final subscription = gated().take(6).listen(values.add);
      source.add(7);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        expect(values, [7]);
      } finally {
        await source.close();
        await subscription.cancel();
      }
    },
  );

  test('Resuming after a scheduled opening refreshes exactly once', () async {
    final source = StreamController<int>();
    final opening = DateTime.now().add(const Duration(milliseconds: 80));
    final values = <int>[];
    final subscription = refreshStream<int>(
      source.stream,
      nextRefreshAt: (_) => opening.isAfter(DateTime.now()) ? opening : null,
    ).listen(values.add);
    source.add(9);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    subscription.pause();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(values, [9]);
    subscription.resume();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(values, [9, 9]);
    await source.close();
    await subscription.cancel();
  });
}
