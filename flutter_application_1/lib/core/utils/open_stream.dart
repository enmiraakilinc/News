// İlk kayıt gecikince ekranı çarkta bırakmadan hatayı bildirir.
import 'dart:async';
import 'user_errors.dart';

/// [ready] bitmeden de sayacı başlatır. Süre dolunca hatayı yazıp dinlemeyi
/// kapatmaz; geç gelen kayıt ekrana yine ulaşır.
Stream<T> openStreamAfter<T>(
  Future<void> Function() ready,
  Stream<T> Function() source, {
  T? initial,
  Future<T?> Function()? cached,
  Duration readyLimit = const Duration(seconds: 20),
  Duration stall = const Duration(seconds: 25),
  String message = 'Yüklenemedi.',
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? stalled;
  var got = false;

  controller = StreamController<T>(
    onListen: () async {
      if (initial != null) {
        got = true;
        if (!controller.isClosed) controller.add(initial as T);
      } else {
        stalled = Timer(stall, () {
          if (!got && !controller.isClosed) {
            controller.addError(TimeoutException(message));
          }
        });
        if (cached != null) {
          try {
            final value = await cached().timeout(const Duration(seconds: 3));
            if (value != null && !got && !controller.isClosed) {
              got = true;
              stalled?.cancel();
              controller.add(value);
            }
          } catch (_) {}
        }
      }
      try {
        await ready().timeout(readyLimit);
      } catch (error, stack) {
        if (!got && !controller.isClosed) controller.addError(error, stack);
      }
      if (controller.isClosed) return;
      try {
        subscription = source().listen(
          (value) {
            got = true;
            stalled?.cancel();
            if (!controller.isClosed) controller.add(value);
          },
          onError: (Object error, StackTrace stack) {
            if (cached != null && got && isTransientError(error)) return;
            if (!controller.isClosed) controller.addError(error, stack);
          },
          onDone: () {
            stalled?.cancel();
            if (!controller.isClosed) controller.close();
          },
        );
      } catch (error, stack) {
        stalled?.cancel();
        if (!controller.isClosed) controller.addError(error, stack);
      }
    },
    onCancel: () async {
      stalled?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
