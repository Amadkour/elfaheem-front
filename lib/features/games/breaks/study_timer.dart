// lib/features/games/breaks/study_timer.dart — Games v4 T75: the pure study clock (no Flutter, a fake clock in tests).

/// Counts foreground study time. [resume] / [pause] bracket the stretches the learner is really in course content;
/// [due] turns true once the counted time reaches [limit], and [consumeDue] answers true ONCE per session.
class StudyTimer {
  StudyTimer({required this.limit, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Duration limit;
  final DateTime Function() _now;

  Duration _done = Duration.zero;
  DateTime? _since;
  bool _suggested = false;

  bool get running => _since != null;
  bool get suggested => _suggested;

  Duration get elapsed => _since == null ? _done : _done + _now().difference(_since!);

  bool get due => limit > Duration.zero && elapsed >= limit;

  void resume() => _since ??= _now();

  void pause() {
    final s = _since;
    if (s == null) return;
    _done += _now().difference(s);
    _since = null;
  }

  /// True the first time the limit has been reached; false afterwards (one break suggestion per study session).
  bool consumeDue() {
    if (_suggested || !due) return false;
    _suggested = true;
    return true;
  }
}
