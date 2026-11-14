// lib/features/calendar/schedule_store.dart — the schedule page's data: ONE GET /me/calendar per range,
// cached (D-085).
//
//   CalendarStore.instance
//     cached(scope, s, e)   the newest fetched chunk holding [s, e) (served at once, even when stale)
//     fetch(api, …)         GET /me/calendar?…&detail=true (a department: /depts/{id}); two pages asking the same range
//                           share one request; a wider chunk replaces the narrower ones it covers
//     fresh(chunk)          younger than [ttl] and not marked stale by a live event
//     weekly(path)          a personal course's weekly appointments (GET /student|teacher/schedules), 15 min,
//                           never throws (a failure shows none: it must never fail the page)
//     patch(fn)             an optimistic change (an answer) applied to every cached chunk
//     changes               bumps when a live event says the calendar changed: open pages reload their range
//
// Live events (no timer): `calendar_updated` (meetings), `meeting_live` / `session_live` (a room opened / closed) and
// `attention_changed` about a timetable change or an exam timetable mark every chunk stale; listened only while a
// page is bound (bind / release).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/calendar/schedule_logic.dart';

/// `attention_changed.related_type` values that move something on the schedule.
const calRelatedTypes = {'org_schedule_occurrence', 'org_exam_schedule', 'org_timetable', 'org_schedule', 'meeting'};

/// True when [e] means the schedule may have changed.
bool calEventTouchesSchedule(LiveEvent e) {
  if (e.type == LiveEvents.calendarUpdated || e.type == LiveEvents.meetingLive || e.type == LiveEvents.sessionLive) return true;
  if (e.type != LiveEvents.attentionChanged) return false;
  return calRelatedTypes.contains(e.relatedType);
}

class CalendarStore {
  CalendarStore({LiveEvents? bus}) : _bus = bus ?? LiveEvents.instance;

  static final CalendarStore instance = CalendarStore();

  static const ttl = Duration(minutes: 3);
  static const weeklyTtl = Duration(minutes: 15);
  static const _maxChunks = 12;

  final LiveEvents _bus;
  final _chunks = <CalChunk>[];
  final _inflight = <String, Future<CalChunk>>{};

  /// Bumps when the cached data went stale because of a live event (pages listening reload).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  @visibleForTesting
  List<CalChunk> get chunks => List.unmodifiable(_chunks);

  // ── live events ──────────────────────────────────────────────────────────
  StreamSubscription<LiveEvent>? _sub;
  int _bound = 0;
  Timer? _debounce;

  void bind() {
    if (_bound++ > 0) return;
    _sub = _bus.listen({LiveEvents.calendarUpdated, LiveEvents.meetingLive, LiveEvents.sessionLive, LiveEvents.attentionChanged}, (e) {
      if (calEventTouchesSchedule(e)) invalidate();
    });
  }

  void release() {
    if (_bound == 0 || --_bound > 0) return;
    _sub?.cancel();
    _sub = null;
    _debounce?.cancel();
  }

  /// Marks every chunk stale and tells the open pages (a burst of events → one reload).
  void invalidate() {
    for (final c in _chunks) {
      c.stale = true;
    }
    _weeklyAt = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => changes.value++);
  }

  /// Signed out / another account: nothing of the previous person may be drawn.
  void clear() {
    _chunks.clear();
    _inflight.clear();
    _weekly = null;
    _weeklyAt = null;
    _weeklyPath = null;
  }

  // ── the feed ─────────────────────────────────────────────────────────────
  CalChunk? cached(String scope, DateTime s, DateTime e) => calCovering(_chunks, scope, s, e);

  bool fresh(CalChunk c, {DateTime? now}) => !c.stale && (now ?? DateTime.now()).difference(c.fetchedAt) < ttl;

  Future<CalChunk> fetch(CalendarApi api, {required String scope, required DateTime start, required DateTime end, int? orgId, int? deptId}) {
    final s = start.toUtc(), e = end.toUtc();
    final key = '$scope|${s.toIso8601String()}|${e.toIso8601String()}';
    return _inflight[key] ??= () async {
      try {
        final r = await api.feed(s.toIso8601String(), e.toIso8601String(), orgId: orgId, deptId: deptId, detail: deptId == null);
        final m = r is Map ? r : const {};
        final chunk = CalChunk(
          scope: scope,
          start: s,
          end: e,
          events: CalEvent.listFrom(r),
          pauses: CalPause.listFrom(r),
          pending: (m['pending_invites'] as num?)?.toInt() ?? 0,
          fetchedAt: DateTime.now(),
        );
        _chunks.removeWhere((x) => x.scope == scope && !x.start.isBefore(s) && !x.end.isAfter(e));
        _chunks.add(chunk);
        while (_chunks.length > _maxChunks) {
          _chunks.removeAt(0);
        }
        return chunk;
      } finally {
        _inflight.remove(key);
      }
    }();
  }

  /// An optimistic change (my answer to an invitation / a change) in every cached chunk.
  void patch(CalEvent Function(CalEvent e) fn) {
    for (var i = 0; i < _chunks.length; i++) {
      final c = _chunks[i];
      final next = CalChunk(
        scope: c.scope,
        start: c.start,
        end: c.end,
        events: [for (final e in c.events) fn(e)],
        pauses: c.pauses,
        pending: c.pending,
        fetchedAt: c.fetchedAt,
      )..stale = c.stale;
      _chunks[i] = next;
    }
  }

  // ── weekly appointments of personal courses ──────────────────────────────
  List<CalWeeklySlot>? _weekly;
  DateTime? _weeklyAt;
  String? _weeklyPath;
  Future<List<CalWeeklySlot>>? _weeklyInflight;

  /// The cached appointments of [path] (null when never loaded).
  List<CalWeeklySlot>? weeklyCached(String path) => _weeklyPath == path ? _weekly : null;

  Future<List<CalWeeklySlot>> weekly(String path, {bool force = false, Future<dynamic> Function(String path)? get}) {
    final fresh = _weeklyPath == path && _weekly != null && _weeklyAt != null && DateTime.now().difference(_weeklyAt!) < weeklyTtl;
    if (fresh && !force) return Future.value(_weekly);
    return _weeklyInflight ??= () async {
      // typed: a bare const [] would make the closure a Future<List<dynamic>>
      try {
        final r = await (get ?? (p) => ApiClient().get(p))(path).timeout(calTimeout);
        _weekly = calWeeklySlotsFrom(r);
        _weeklyAt = DateTime.now();
        _weeklyPath = path;
      } catch (_) {
        // a failure here never fails the page: keep what we had (or nothing)
        if (_weeklyPath != path) {
          _weekly = const <CalWeeklySlot>[];
          _weeklyPath = path;
        }
      } finally {
        _weeklyInflight = null;
      }
      return _weekly ?? const <CalWeeklySlot>[];
    }();
  }
}
