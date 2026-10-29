// lib/features/teacher/home/teacher_home_extra.dart — the teacher block of GET /api/v1/me/home (Track B.5).
//
// Pure: parsed from the payload, no widgets, no network. GET /teacher/dashboard stays the main aggregate;
// this call adds what it lacks — the earnings figures, the pending counters (used when the dashboard carries
// none), the inbox preview, the unread notifications count — and an optional enrollment series when a server
// sends one (`enrollments_series`: numbers, oldest first; absent today → no sparkline is drawn).
// An older server answers a bare 404 / 405: [teacherHomeExtraMissing] tells it apart, the tiles then stay hidden.
library;

import '../../../core/api_client.dart';
import '../../../core/home/me_home.dart' show MeLiveRoom;

class TeacherHomeExtra {
  const TeacherHomeExtra({
    this.pending = const {},
    this.teachingCourses,
    this.earningsMonth,
    this.pendingPayout,
    this.inboxPreview = const [],
    this.notificationsUnread,
    this.enrollmentSeries = const [],
    this.liveNow = const [],
    this.liveNowKnown = false,
  });

  /// attendance_missing · materials_missing · grading · enrollment_requests.
  final Map<String, int> pending;
  final int? teachingCourses;

  /// Null when the server sent no `earnings` block (the hero then shows three figures, not four).
  final double? earningsMonth;
  final double? pendingPayout;

  /// The unified inbox's most urgent items (raw rows of GET /me/inbox, ≤ 5) — InboxItem(raw) draws them.
  final List<Map<String, dynamic>> inboxPreview;
  final int? notificationsUnread;

  /// Enrollments per day, oldest first; empty unless the server sends `enrollments_series`.
  final List<double> enrollmentSeries;

  /// `live_now[]`: meetings I'm invited to that are live right now (the home's "Live now" banner); my own course
  /// sessions are never in it (they have their own "Enter room" cards). [liveNowKnown] false on an older server.
  final List<MeLiveRoom> liveNow;
  final bool liveNowKnown;

  bool get hasEarnings => earningsMonth != null;

  /// The same block with [liveNow] replaced (a live event dropped / added a room before the reload answered).
  TeacherHomeExtra withLiveNow(List<MeLiveRoom> rooms) => TeacherHomeExtra(
        pending: pending,
        teachingCourses: teachingCourses,
        earningsMonth: earningsMonth,
        pendingPayout: pendingPayout,
        inboxPreview: inboxPreview,
        notificationsUnread: notificationsUnread,
        enrollmentSeries: enrollmentSeries,
        liveNow: rooms,
        liveNowKnown: liveNowKnown,
      );

  factory TeacherHomeExtra.fromJson(Map<String, dynamic> j) {
    final earnings = j['earnings'];
    double? money(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return TeacherHomeExtra(
      pending: {
        if (j['pending'] is Map)
          for (final e in (j['pending'] as Map).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0,
      },
      teachingCourses: (j['teaching_courses'] as num?)?.toInt(),
      earningsMonth: earnings is Map ? money(earnings['month']) : null,
      pendingPayout: earnings is Map ? money(earnings['pending_payout']) : null,
      inboxPreview: [
        if (j['inbox_preview'] is List)
          for (final x in j['inbox_preview'] as List)
            if (x is Map) Map<String, dynamic>.from(x),
      ],
      notificationsUnread: (j['notifications_unread'] as num?)?.toInt(),
      enrollmentSeries: [
        if (j['enrollments_series'] is List)
          for (final v in j['enrollments_series'] as List)
            if (v is num) v.toDouble(),
      ],
      liveNow: [for (final x in j['live_now'] is List ? j['live_now'] as List : const []) MeLiveRoom.fromJson(x)]
          .whereType<MeLiveRoom>()
          .toList(),
      liveNowKnown: j['live_now'] is List,
    );
  }
}

/// FastAPI's bare "Not Found" (or a 405): the route is not on this server → hide what it would feed.
bool teacherHomeExtraMissing(ApiException e) =>
    e.statusCode == 405 || (e.statusCode == 404 && ApiException.asMap(e.body)?['detail'] == 'Not Found');
