// lib/features/self_learning/sl_store.dart — ONE copy of `GET /api/v1/me/self-learning` for the app (D-1602): the
// Quran tab's section, the Nahw tab's section and the daily learning page all read it, so opening both tabs costs one
// request. A load within [fresh] of the last one is skipped unless forced (the page forces on open, a pull refreshes).
// "Got it" and an answered review update the copy at once, so the other section never shows them again.
library;

import 'package:flutter/foundation.dart';

import 'sl_api.dart';
import 'sl_models.dart';

class SlStore extends ChangeNotifier {
  SlStore({SlApi? api}) : api = api ?? SlApi();

  static SlStore instance = SlStore();

  final SlApi api;

  static const fresh = Duration(minutes: 2);

  SlState? _state;
  String? _error;
  DateTime? _loadedAt;
  Future<void>? _inflight;
  bool _saving = false;
  final Set<int> _seenBusy = {};

  SlState? get state => _state;
  String? get error => _error;
  bool get loading => _inflight != null;
  bool get saving => _saving;
  bool seenBusy(int id) => _seenBusy.contains(id);

  Future<void> load({bool force = false}) {
    final at = _loadedAt;
    if (!force && _state != null && at != null && DateTime.now().difference(at) < fresh) return Future.value();
    return _inflight ??= _load().whenComplete(() => _inflight = null);
  }

  Future<void> _load() async {
    _error = null;
    notifyListeners();
    try {
      _state = await api.me();
      _loadedAt = DateTime.now();
    } catch (e) {
      _error = slErrorText(e);
    }
    _inflight = null;
    notifyListeners();
  }

  /// "Got it": the lesson leaves today's list and counts as learned. Null = done, else the error text.
  Future<String?> gotIt(SlItem item) async {
    if (_seenBusy.contains(item.id)) return null;
    _seenBusy.add(item.id);
    notifyListeners();
    try {
      await api.seen(item.id);
      final s = _state;
      if (s != null) {
        final p = s.progress;
        _state = s.copyWith(
          lessons: [for (final l in s.lessons) if (l.id != item.id) l],
          progress: SlProgress(learned: p.learned + 1, due: p.due, streakDays: p.streakDays, perSubject: {
            ...p.perSubject,
            item.subject: () {
              final o = p.perSubject[item.subject] ?? const SlSubjectProgress();
              return SlSubjectProgress(learned: o.learned + 1, due: o.due, total: o.total);
            }(),
          }),
        );
      }
      return null;
    } catch (e) {
      return slErrorText(e);
    } finally {
      _seenBusy.remove(item.id);
      notifyListeners();
    }
  }

  /// A review was answered (and moved past): it leaves today's list; a right answer is one less due.
  void reviewed(SlItem item, {required bool right}) {
    final s = _state;
    if (s == null) return;
    final p = s.progress;
    final o = p.perSubject[item.subject] ?? const SlSubjectProgress();
    _state = s.copyWith(
      reviews: [for (final r in s.reviews) if (r.id != item.id) r],
      progress: right
          ? SlProgress(
              learned: p.learned,
              due: (p.due - 1).clamp(0, 1 << 30),
              streakDays: p.streakDays,
              perSubject: {...p.perSubject, item.subject: SlSubjectProgress(learned: o.learned, due: (o.due - 1).clamp(0, 1 << 30), total: o.total)},
            )
          : p,
    );
    notifyListeners();
  }

  /// The student's on / off and subjects. Null = saved, else the error text.
  Future<String?> setPrefs({required bool enabled, required List<String> subjects}) async {
    _saving = true;
    notifyListeners();
    try {
      final r = await api.update(enabled: enabled, subjects: subjects);
      // the PUT's answer is trusted for the prefs only; today's items for the new choice come with a fresh read
      final s = _state;
      if (s != null) _state = s.copyWith(enabled: r.enabled, subjects: r.subjects.isEmpty ? subjects : r.subjects);
      _saving = false;
      _inflight = null;
      load(force: true);
      return null;
    } catch (e) {
      return slErrorText(e);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  void reset() {
    _state = null;
    _error = null;
    _loadedAt = null;
    _inflight = null;
    _seenBusy.clear();
  }
}
