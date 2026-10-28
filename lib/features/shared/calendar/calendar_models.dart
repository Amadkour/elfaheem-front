// lib/features/shared/calendar/calendar_models.dart — the smart calendar: event model + pure layout logic.
//
//   GET /api/v1/me/calendar?start=&end=&org_id=        merged events (meeting · timetable · extra · exam · course_session)
//   GET /api/v1/me/calendar/depts/{id}?start=&end=     a department's meetings
//
// Times arrive as naive UTC; everything on screen is the wall clock of AppTime's zone (platform / organization).
// Pure (unit-tested): CalEvent.fromJson, calVisibleDays, calFetchRange, calEventsOnDay, calLayoutDay, calConflicts,
// calSnap, calWeekStart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';

import '../../admin/admin_common.dart' show t;

enum CalView { day, week, month }

const calSources = ['meeting', 'timetable', 'extra', 'exam', 'course_session'];

DateTime? _utc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

int? _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');

class CalEvent {
  const CalEvent({
    required this.id,
    required this.source,
    required this.title,
    required this.start,
    required this.end,
    this.subtitle,
    this.orgId,
    this.deptId,
    this.courseId,
    this.meetingId,
    this.location,
    this.mode,
    this.myStatus,
    this.kind,
    this.color,
    this.orgName,
    this.isOwner = false,
    this.editable = false,
    this.counts = const {},
  });

  final String id, source, title;
  final DateTime start, end; // UTC
  final String? subtitle, location, mode, myStatus, kind, color, orgName;
  final int? orgId, deptId, courseId, meetingId;
  final bool isOwner, editable;
  final Map<String, int> counts;

  static CalEvent? fromJson(Map<String, dynamic> j) {
    final s = _utc(j['starts_at']), e = _utc(j['ends_at']);
    if (s == null || e == null) return null;
    final org = j['org'] is Map ? j['org'] as Map : const {};
    final orgName = AppConfig.lang == 'ar' ? (org['name_ar'] ?? org['name_en']) : (org['name_en'] ?? org['name_ar']);
    return CalEvent(
      id: '${j['id']}',
      source: '${j['source'] ?? 'meeting'}',
      title: '${j['title'] ?? ''}'.trim().isEmpty ? t('بدون عنوان', 'Untitled') : '${j['title']}',
      start: s,
      end: e.isAfter(s) ? e : s.add(const Duration(minutes: 30)),
      subtitle: j['subtitle']?.toString(),
      orgId: _int(j['org_id']),
      deptId: _int(j['dept_id']),
      courseId: _int(j['course_id']),
      meetingId: _int(j['meeting_id']),
      location: j['location']?.toString(),
      mode: j['mode']?.toString(),
      myStatus: j['my_status']?.toString(),
      kind: j['kind']?.toString(),
      color: j['color']?.toString(),
      orgName: orgName?.toString(),
      isOwner: j['is_owner'] == true,
      editable: j['editable'] == true,
      counts: {
        if (j['counts'] is Map)
          for (final e in (j['counts'] as Map).entries) '${e.key}': _int(e.value) ?? 0,
      },
    );
  }

  static List<CalEvent> listFrom(dynamic r) => [
        if (r is Map && r['items'] is List)
          for (final x in r['items'] as List)
            if (x is Map) CalEvent.fromJson(Map<String, dynamic>.from(x)),
      ].whereType<CalEvent>().toList();

  CalEvent moved(DateTime s, DateTime e) => CalEvent(
        id: id, source: source, title: title, start: s, end: e, subtitle: subtitle, orgId: orgId, deptId: deptId,
        courseId: courseId, meetingId: meetingId, location: location, mode: mode, myStatus: myStatus, kind: kind,
        color: color, orgName: orgName, isOwner: isOwner, editable: editable, counts: counts);

  DateTime get wallStart => AppTime.toZone(start);
  DateTime get wallEnd => AppTime.toZone(end);
  Duration get duration => end.difference(start);
  bool get declined => myStatus == 'declined';
  bool get isMeeting => source == 'meeting';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Days, ranges and layout (wall clock)
// ═════════════════════════════════════════════════════════════════════════════

DateTime calDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Arabic weeks start on Saturday, English ones on Monday.
int calWeekStart([String? lang]) => (lang ?? AppConfig.lang) == 'ar' ? DateTime.saturday : DateTime.monday;

DateTime _startOfWeek(DateTime d, int weekStart) => calDay(d).subtract(Duration(days: (d.weekday - weekStart + 7) % 7));

/// The days a view shows: 1 · 7 · the 6×7 month grid.
List<DateTime> calVisibleDays(CalView v, DateTime anchor, {int? weekStart}) {
  final ws = weekStart ?? calWeekStart();
  switch (v) {
    case CalView.day:
      return [calDay(anchor)];
    case CalView.week:
      final s = _startOfWeek(anchor, ws);
      return [for (var i = 0; i < 7; i++) DateTime(s.year, s.month, s.day + i)];
    case CalView.month:
      final s = _startOfWeek(DateTime(anchor.year, anchor.month), ws);
      return [for (var i = 0; i < 42; i++) DateTime(s.year, s.month, s.day + i)];
  }
}

/// UTC [start, end) to fetch for a view ([toUtc] = AppTime.fromZone in the app).
(DateTime, DateTime) calFetchRange(CalView v, DateTime anchor, {int? weekStart, DateTime Function(DateTime)? toUtc}) {
  final days = calVisibleDays(v, anchor, weekStart: weekStart);
  final f = toUtc ?? AppTime.fromZone;
  final last = days.last;
  return (f(days.first), f(DateTime(last.year, last.month, last.day + 1)));
}

DateTime calShift(CalView v, DateTime anchor, int dir) => switch (v) {
      CalView.day => DateTime(anchor.year, anchor.month, anchor.day + dir),
      CalView.week => DateTime(anchor.year, anchor.month, anchor.day + 7 * dir),
      CalView.month => DateTime(anchor.year, anchor.month + dir, 1),
    };

/// Events touching wall day [day], by start.
List<CalEvent> calEventsOnDay(Iterable<CalEvent> events, DateTime day) {
  final a = calDay(day), b = DateTime(day.year, day.month, day.day + 1);
  final out = [for (final e in events) if (e.wallStart.isBefore(b) && e.wallEnd.isAfter(a)) e];
  out.sort((x, y) => x.start.compareTo(y.start));
  return out;
}

class CalPlaced {
  const CalPlaced(this.event, this.top, this.bottom, this.col, this.cols);
  final CalEvent event;
  final int top, bottom; // minutes after midnight, clamped to the day
  final int col, cols;
}

/// Side-by-side columns for overlapping events of one day (Outlook style): each cluster of overlapping events
/// shares its width; an event takes the first free column.
List<CalPlaced> calLayoutDay(Iterable<CalEvent> events, DateTime day) {
  final a = calDay(day);
  final rows = <(CalEvent, int, int)>[];
  for (final e in calEventsOnDay(events, day)) {
    final top = e.wallStart.isBefore(a) ? 0 : e.wallStart.difference(a).inMinutes;
    final bot = e.wallEnd.difference(a).inMinutes.clamp(top + 15, 1440);
    rows.add((e, top.clamp(0, 1425), bot));
  }
  rows.sort((x, y) => x.$2 != y.$2 ? x.$2.compareTo(y.$2) : y.$3.compareTo(x.$3));
  final out = <CalPlaced>[];
  var cluster = <(CalEvent, int, int, int)>[];
  var clusterEnd = -1;
  void flush() {
    final n = cluster.fold<int>(0, (m, r) => r.$4 + 1 > m ? r.$4 + 1 : m);
    out.addAll([for (final r in cluster) CalPlaced(r.$1, r.$2, r.$3, r.$4, n)]);
    cluster = [];
  }

  for (final r in rows) {
    if (r.$2 >= clusterEnd && cluster.isNotEmpty) flush();
    final used = {for (final c in cluster) if (c.$3 > r.$2) c.$4};
    var col = 0;
    while (used.contains(col)) {
      col++;
    }
    cluster.add((r.$1, r.$2, r.$3, col));
    if (r.$3 > clusterEnd) clusterEnd = r.$3;
  }
  if (cluster.isNotEmpty) flush();
  return out;
}

/// Other events of mine that [s, e) (UTC) would overlap — the instant check while dragging. Declined ones don't count.
List<CalEvent> calConflicts(Iterable<CalEvent> events, CalEvent moving, DateTime s, DateTime e) => [
      for (final x in events)
        if (x.id != moving.id && !x.declined && x.start.isBefore(e) && s.isBefore(x.end)) x,
    ];

/// Pixel offset in a day column → minutes after midnight, snapped to [step].
int calSnap(double dy, double hourHeight, {int step = 15}) {
  final m = (dy / hourHeight * 60).round();
  return ((m / step).round() * step).clamp(0, 1440 - step);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels and colours
// ═════════════════════════════════════════════════════════════════════════════

String calSourceLabel(String s) => switch (s) {
      'meeting' => t('اجتماعات', 'Meetings'),
      'timetable' => t('الجدول الدراسي', 'Timetable'),
      'extra' => t('فترات خاصة', 'Special periods'),
      'exam' => t('امتحانات', 'Exams'),
      'course_session' => t('جلسات المقررات', 'Course sessions'),
      _ => s,
    };

IconData calSourceIcon(String s) => switch (s) {
      'meeting' => Icons.groups_2_rounded,
      'timetable' => Icons.view_week_rounded,
      'extra' => Icons.event_note_rounded,
      'exam' => Icons.assignment_rounded,
      'course_session' => Icons.live_tv_rounded,
      _ => Icons.event_rounded,
    };

/// One colour per source (private meetings get the accent so "just me" stands out).
Color calSourceColor(ThemeConfigProvider c, String source, {String? kind}) => switch (source) {
      'meeting' => kind == 'private' ? c.accent : c.primary,
      'timetable' => kind == 'lab' ? c.accent2 : Color.lerp(c.primary, c.accent2, 0.45)!,
      'extra' => c.warning,
      'exam' => c.danger,
      'course_session' => c.purple,
      _ => c.textMedium,
    };

Color calEventColor(ThemeConfigProvider c, CalEvent e) => calSourceColor(c, e.source, kind: e.kind);

String calStatusLabel(String? s) => switch (s) {
      'accepted' => t('مقبول', 'Accepted'),
      'declined' => t('معتذر', 'Declined'),
      'proposed' => t('اقترح موعداً', 'Proposed a time'),
      'pending' => t('بانتظار الرد', 'Pending'),
      'owner' => t('المنظّم', 'Organizer'),
      _ => '',
    };

IconData calStatusIcon(String? s) => switch (s) {
      'accepted' => Icons.check_circle_rounded,
      'declined' => Icons.cancel_rounded,
      'proposed' => Icons.schedule_send_rounded,
      'owner' => Icons.star_rounded,
      _ => Icons.hourglass_top_rounded,
    };

Color calStatusColor(ThemeConfigProvider c, String? s) => switch (s) {
      'accepted' => c.success,
      'declined' => c.danger,
      'proposed' => c.purple,
      'owner' => c.primary,
      _ => c.warning,
    };

String calTitleFor(CalView v, DateTime anchor) {
  final days = calVisibleDays(v, anchor);
  String fmt(DateTime d, String p) => AppTime.date(AppTime.fromZone(DateTime(d.year, d.month, d.day, 12)), pattern: p);
  return switch (v) {
    CalView.day => fmt(anchor, 'EEEE d MMMM y'),
    CalView.month => fmt(DateTime(anchor.year, anchor.month, 15), 'MMMM y'),
    CalView.week => days.first.month == days.last.month
        ? '${fmt(days.first, 'd')} – ${fmt(days.last, 'd MMMM y')}'
        : '${fmt(days.first, 'd MMM')} – ${fmt(days.last, 'd MMM y')}',
  };
}
