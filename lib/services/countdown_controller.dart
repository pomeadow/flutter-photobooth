import 'dart:async';

import 'package:flutter/foundation.dart';

/// Second-by-second countdown driving the camera screen.
///
/// Port of py-photobooth `components/countdown_timer.py`, same timeline:
/// `start(n)` → [onTick] `n` immediately, then `n-1 … 1` once per second,
/// then [onFinished] at `n` seconds. A tick of 0 is never sent.
///
/// Also a [ChangeNotifier], so the timer badge can rebuild from [remaining]
/// with a `ListenableBuilder` instead of wiring callbacks.
class CountdownController extends ChangeNotifier {
  CountdownController({this.onTick, this.onFinished});

  /// Called with each remaining-seconds value, starting with `n`.
  /// The camera screen starts the sleigh bells on tick 4.
  void Function(int remaining)? onTick;

  /// Called once when the countdown reaches zero (not when [stop]ped).
  VoidCallback? onFinished;

  Timer? _timer;
  int? _remaining;

  /// Seconds left: `n … 1` while running, `0` once finished, `null` when idle
  /// or stopped. (Python's `remaining_seconds` never updated — fixed.)
  int? get remaining => _remaining;

  bool get isRunning => _timer?.isActive ?? false;

  /// True after reaching zero, until the next [start] or [stop].
  bool get isFinished => _remaining == 0;

  /// Starts (or restarts) counting down from [seconds]. Restarting simply
  /// replaces the current countdown.
  void start(int seconds) {
    assert(seconds > 0, 'countdown must be at least 1 second');
    _timer?.cancel();
    _remaining = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    onTick?.call(seconds);
  }

  /// Cancels without calling [onFinished]. Safe to call when idle.
  void stop() {
    if (_timer == null && _remaining == null) return;
    _timer?.cancel();
    _timer = null;
    _remaining = null;
    notifyListeners();
  }

  void _tick() {
    final next = _remaining! - 1;
    _remaining = next;
    if (next > 0) {
      notifyListeners();
      onTick?.call(next);
      return;
    }
    _timer?.cancel();
    _timer = null;
    notifyListeners();
    onFinished?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
