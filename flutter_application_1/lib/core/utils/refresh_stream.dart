import 'dart:async';

/// Re-evaluates time-dependent data without reconnecting to Firestore.
Stream<T> refreshStream<T>(
  Stream<T> source, {
  Duration interval = const Duration(seconds: 15),
  DateTime? Function(T)? nextRefreshAt,
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  T? latest;
  bool hasValue = false;
  DateTime? refreshDueAt;
  void schedule() {
    timer?.cancel();
    if (!hasValue ||
        controller.isClosed ||
        controller.isPaused ||
        !controller.hasListener) {
      return;
    }
    if (nextRefreshAt == null) {
      refreshDueAt = null;
      timer = Timer.periodic(interval, (_) {
        if (!controller.isClosed) controller.add(latest as T);
      });
      return;
    }
    final deadline = nextRefreshAt(latest as T);
    refreshDueAt = deadline;
    if (deadline == null) return;
    final remaining = deadline.difference(DateTime.now());
    timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      refreshDueAt = null;
      if (!controller.isClosed && !controller.isPaused) {
        controller.add(latest as T);
        scheduleMicrotask(schedule);
      }
    });
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (value) {
          latest = value;
          hasValue = true;
          controller.add(value);
          schedule();
        },
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          controller.close();
        },
      );
    },
    onPause: () {
      subscription?.pause();
      timer?.cancel();
    },
    onResume: () {
      subscription?.resume();
      // async* pauses/resumes its input around each yield. Replaying here on
      // every resume creates an endless loop through CoupleService._gated.
      // Only catch up when a scheduled opening actually elapsed while paused.
      final deadline = refreshDueAt;
      refreshDueAt = null;
      if (hasValue &&
          !controller.isClosed &&
          deadline != null &&
          !deadline.isAfter(DateTime.now())) {
        controller.add(latest as T);
      }
      schedule();
    },
    onCancel: () async {
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
