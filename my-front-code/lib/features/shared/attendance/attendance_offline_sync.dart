/// features/attendance/attendance_offline_sync.dart
///
/// Keeps the phone READY for offline check-in, and settles whatever is still open when the
/// phone comes back online.
///
///   • [warm]        online  -> store the signing key + this lesson's open window locally
///   • [onReconnect] back online -> re-send saved requests (same request_id => idempotent) and
///                   refresh every cached window
///
/// Called from the student's action button (each time a lesson card is shown online) and from
/// [TopRouteObserver] when the connectivity state flips.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'attendance_crypto.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';
import 'attendance_store.dart';

class FlushedAttendance {
  const FlushedAttendance(this.pending, this.result);
  final PendingAttendance pending;
  final AttendanceResult result;
}

class AttendanceOfflineSync {
  AttendanceOfflineSync._();
  static final AttendanceOfflineSync instance = AttendanceOfflineSync._();

  final _repo = AttendanceRepository();
  final _store = AttendanceStore.instance;

  bool _flushing = false;
  final Map<int, DateTime> _lastWarm = {};
  static const _warmEvery = Duration(minutes: 2);

  /// Online only. Stores the key and (if open) the window of [sessionId]. Returns the window.
  Future<OpenWindow?> warm({int? sessionId, int? courseId, bool force = false}) async {
    try {
      await _store.saveKey(await _repo.fetchKey());
      await _store.touchOnline();
    } on ApiException {
      return null; // offline / signed out: nothing to store
    } catch (_) {
      return null;
    }
    final lookup = sessionId ?? (courseId == null ? null : -courseId);
    if (lookup == null) return null;

    final last = _lastWarm[lookup];
    if (!force && last != null && DateTime.now().difference(last) < _warmEvery) {
      return sessionId != null ? _store.window(sessionId) : _store.windowForCourse(courseId!);
    }
    _lastWarm[lookup] = DateTime.now();
    try {
      final w = await _repo.openWindow(sessionId: sessionId, courseId: courseId);
      await _store.saveWindow(w);
      return w;
    } on ApiException catch (e) {
      // No open window right now (404) is a normal answer: forget a stale cached one.
      if (courseId != null && (e.isNotFound || e.code == 'no_open_attendance')) {
        await _store.removeCourseWindows(courseId);
      }
      return null;
    }
  }

  /// Online: store every enrolled course (+ lessons) so the offline Attendance tab can list them.
  Future<void> warmCourses() async {
    try {
      await _store.saveCourses(await _repo.myLessons());
      await _store.touchOnline();
    } catch (_) {/* offline / signed out: keep what we already have */}
  }

  /// Re-sends saved requests; returns the ones the server answered with a VERIFIED signature.
  Future<List<FlushedAttendance>> flushPending() async {
    if (_flushing) return const [];
    _flushing = true;
    final done = <FlushedAttendance>[];
    try {
      final key = await _store.readKey();
      if (key == null) return done;
      for (final p in await _store.pending()) {
        try {
          final r = AttendanceResult.fromJson(await _repo.submit(p.toSubmitBody()));
          final ok = r.requestId == p.requestId &&
              r.studentId == p.studentId &&
              r.attendanceSessionId == p.attendanceSessionId &&
              verifyResult(
                studentKey: key.key,
                requestId: r.requestId,
                status: r.status,
                confirmedAt: r.confirmedAt,
                signature: r.serverSignature,
              );
          if (ok) {
            await _store.removePending(p.requestId);
            done.add(FlushedAttendance(p, r));
          }
        } on ApiException catch (e) {
          // a definite server "no" ends the retries; a network problem keeps the request
          if (!(e.isNetwork || e.isTimeout)) await _store.removePending(p.requestId);
        } catch (_) {}
      }
    } finally {
      _flushing = false;
    }
    return done;
  }

  /// The phone just got its connection back.
  Future<void> onReconnect() async {
    try {
      await warmCourses();
      final flushed = await flushPending();
      if (flushed.isNotEmpty) debugPrint('attendance: settled ${flushed.length} saved request(s)');
      for (final id in await _store.cachedSessionIds()) {
        await warm(sessionId: id, force: true);
      }
    } catch (e) {
      debugPrint('attendance reconnect sync failed: $e');
    }
  }
}
