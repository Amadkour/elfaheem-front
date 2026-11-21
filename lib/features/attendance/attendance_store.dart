/// features/attendance/attendance_store.dart
///
/// Local persistence for offline attendance:
///   • the signing key (flutter_secure_storage — it is a secret)
///   • open-window cache per lesson and the pending-request queue (shared_preferences)
///
/// Call [AttendanceStore.clear] on logout so the next account never reuses the key.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/features/attendance/attendance_models.dart';

class AttendanceStore {
  AttendanceStore._();
  static final AttendanceStore instance = AttendanceStore._();

  static const _kKey = 'attendance_student_key_v1';
  static const _kPending = 'attendance_pending_v1';
  static const _kWindows = 'attendance_windows_v1';
  static const _kHelped = 'attendance_helped_v1';
  static const _kLastOnline = 'attendance_last_online_v1';
  static const _kCourses = 'attendance_courses_v1';

  /// Pending requests older than this are dropped (the code is long dead by then).
  static const _pendingMaxAge = Duration(hours: 12);

  final _secure = const FlutterSecureStorage();

  // ── key ───────────────────────────────────────────────────────────────
  Future<StudentKey?> readKey() async {
    try {
      final raw = await _secure.read(key: _kKey);
      if (raw == null || raw.isEmpty) return null;
      return StudentKey.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveKey(StudentKey k) async {
    try {
      await _secure.write(key: _kKey, value: jsonEncode(k.toJson()));
    } catch (_) {}
  }

  // ── open-window cache (lesson id -> window) ───────────────────────────
  Future<Map<String, dynamic>> _windows() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kWindows);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<OpenWindow?> window(int sessionId) async {
    final j = (await _windows())['$sessionId'];
    if (j is! Map) return null;
    final w = OpenWindow.fromJson(Map<String, dynamic>.from(j));
    return w.looksExpired ? null : w;
  }

  Future<void> saveWindow(OpenWindow w) async {
    final all = await _windows();
    all['${w.sessionId}'] = w.toJson();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWindows, jsonEncode(all));
  }

  /// The teacher closed attendance (or it ended): forget every cached window of that course so
  /// the student's button disappears, online or offline.
  Future<void> removeCourseWindows(int courseId) async {
    final all = await _windows();
    all.removeWhere((_, j) => j is Map && (j['course_id'] as num?)?.toInt() == courseId);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWindows, jsonEncode(all));
  }

  // ── courses stored for the offline "Attendance" tab ───────────────────
  List<CachedCourse> _courses = const [];

  /// Synchronous on purpose: main.dart decides the start route before the first frame.
  bool get hasCachedCourses => _courses.isNotEmpty;
  List<CachedCourse> get cachedCourses => _courses;

  /// Call once at start-up (main.dart) so [hasCachedCourses] is accurate immediately.
  Future<void> preload() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kCourses);
    if (raw == null) return;
    try {
      _courses = [
        for (final c in jsonDecode(raw) as List)
          CachedCourse.fromJson(Map<String, dynamic>.from(c as Map)),
      ];
    } catch (_) {}
  }

  Future<void> saveCourses(List<CachedCourse> l) async {
    _courses = l;
    await (await SharedPreferences.getInstance())
        .setString(_kCourses, jsonEncode([for (final c in l) c.toJson()]));
  }

  /// Newest cached open window of any lesson of [courseId].
  Future<OpenWindow?> windowForCourse(int courseId) async {
    OpenWindow? best;
    for (final j in (await _windows()).values) {
      if (j is! Map) continue;
      final w = OpenWindow.fromJson(Map<String, dynamic>.from(j));
      if (w.courseId == courseId && !w.looksExpired &&
          (best == null || w.attendanceSessionId > best.attendanceSessionId)) {
        best = w;
      }
    }
    return best;
  }

  /// Lessons whose open window is cached on this phone.
  Future<List<int>> cachedSessionIds() async =>
      (await _windows()).keys.map(int.tryParse).whereType<int>().toList();

  /// "State stored while online": when this phone last refreshed its offline data.
  Future<DateTime?> lastOnline() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_kLastOnline);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> touchOnline() async => (await SharedPreferences.getInstance())
      .setInt(_kLastOnline, DateTime.now().millisecondsSinceEpoch);

  // ── pending queue ─────────────────────────────────────────────────────
  Future<List<PendingAttendance>> pending() async {
    final p = await SharedPreferences.getInstance();
    final cutoff = DateTime.now().subtract(_pendingMaxAge).millisecondsSinceEpoch;
    return PendingAttendance.decodeList(p.getString(_kPending))
        .where((e) => e.createdAtMs >= cutoff)
        .toList();
  }

  Future<void> addPending(PendingAttendance e) async {
    final l = await pending()
      ..removeWhere((x) => x.requestId == e.requestId)
      ..add(e);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPending, PendingAttendance.encodeList(l));
    SyncStatus.instance.report(SyncStatus.attendance, l.length); // the one offline status (D-1351)
  }

  Future<void> removePending(String requestId) async {
    final l = await pending()
      ..removeWhere((x) => x.requestId == requestId);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPending, PendingAttendance.encodeList(l));
    SyncStatus.instance.report(SyncStatus.attendance, l.length);
  }

  // ── relay statistics (for the "You helped N classmates" badge) ────────
  Future<int> helped() async => (await SharedPreferences.getInstance()).getInt(_kHelped) ?? 0;

  Future<int> incrementHelped() async {
    final p = await SharedPreferences.getInstance();
    final n = (p.getInt(_kHelped) ?? 0) + 1;
    await p.setInt(_kHelped, n);
    return n;
  }

  Future<void> clear() async {
    try {
      await _secure.delete(key: _kKey);
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPending);
    await p.remove(_kWindows);
    await p.remove(_kHelped);
    await p.remove(_kLastOnline);
    await p.remove(_kCourses);
    _courses = const [];
  }
}
