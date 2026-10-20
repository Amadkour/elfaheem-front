// ticking_counter.dart
//
// A small, reusable, self-contained one-second ticking counter.
//
// WHY THIS EXISTS
// ─────────────────────────────────────────────────────────────────────────
// A recurring pattern across this app's live-session screens was:
//
//   Timer? _timer;
//   int _elapsed = 0;
//   _timer = Timer.periodic(const Duration(seconds: 1), (_) {
//     setState(() => _elapsed++);
//   });
//
// `setState()` there rebuilds the *entire* enclosing State — every second,
// for as long as the timer runs. On a screen with a large build method
// (video grid, controls, participant list, etc.) that means a full rebuild
// of everything just to tick a small badge or countdown.
//
// `TickingCounter` wraps the Timer + counter in a `ValueNotifier<int>`
// instead. Only widgets that explicitly listen to it (via
// `ValueListenableBuilder` or `ListenableBuilder`) redraw on each tick —
// nothing else in the tree is touched. It also supports counting down with
// an `onZero` callback, so it covers both "elapsed time" clocks and
// countdown timers with the same class.
//
// USAGE
// ─────────────────────────────────────────────────────────────────────────
//   // Count up (e.g. "session elapsed" / "recording elapsed"):
//   final clock = TickingCounter();
//   clock.start();
//   ...
//   ValueListenableBuilder<int>(
//     valueListenable: clock.notifier,
//     builder: (context, seconds, _) => Text(formatElapsed(seconds)),
//   );
//
//   // Count down (e.g. a quiz timer), firing a callback at zero:
//   final quizClock = TickingCounter(
//     step: -1,
//     onZero: () => submitQuiz(autoSubmit: true),
//   );
//   quizClock.reset(durationSeconds);
//   quizClock.start();
//
// Always call `dispose()` from the owning State's `dispose()`.

import 'dart:async';
import 'package:flutter/foundation.dart';

class TickingCounter {
  TickingCounter({int initial = 0, this.step = 1, this.onZero})
      : assert(step != 0, 'step must be non-zero'),
        notifier = ValueNotifier<int>(initial);

  /// The live value. Listen to this directly with `ValueListenableBuilder`
  /// or `ListenableBuilder` — never with `setState`/`context.watch` on the
  /// whole page.
  final ValueNotifier<int> notifier;

  /// +1 to count up (elapsed-time clocks), -1 to count down (countdowns).
  final int step;

  /// For countdowns (`step < 0`): called exactly once, the tick the value
  /// would otherwise go to zero or below. The timer stops itself first, so
  /// it's safe to call [start] again from inside this callback (e.g. to
  /// restart a new round).
  final VoidCallback? onZero;

  Timer? _timer;
  bool _disposed = false;

  int get value => notifier.value;
  set value(int v) => notifier.value = v;

  bool get isRunning => _timer != null;

  /// Starts ticking once a second. No-op if already running or disposed.
  void start() {
    if (_timer != null || _disposed) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      final next = notifier.value + step;
      if (step < 0 && next <= 0) {
        notifier.value = 0;
        stop();
        onZero?.call();
        return;
      }
      notifier.value = next;
    });
  }

  /// Stops ticking without resetting [value]. Safe to call when not running.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sets [value] directly (e.g. seeding a countdown's starting duration, or
  /// zeroing an elapsed-time clock on a fresh recording run).
  void reset(int to) => notifier.value = to;

  /// Stops the timer and disposes the underlying notifier. Call from the
  /// owning State's `dispose()`. The counter can't be started again after.
  void dispose() {
    stop();
    _disposed = true;
    notifier.dispose();
  }
}
