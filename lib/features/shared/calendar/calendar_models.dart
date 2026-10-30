// lib/features/shared/calendar/calendar_models.dart — the smart calendar: event model + pure layout logic.
//
//   GET /api/v1/me/calendar?start=&end=&org_id=&detail=true   merged events (meeting · timetable · extra · exam ·
//                                                       course_session); detail: one-date changes (`change`, cancelled
//                                                       dates kept with `cancelled`) + `pauses` (exam windows)
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

/// The views of the schedule page: agenda (phone default) · day · week (desktop default) · month.
enum CalView { agenda, day, week, month }

/// How many days the agenda shows from its first day (it grows by the same amount with "Show more").
const calAgendaDays = 14;

/// `course_weekly` is the app's own source: a personal course's weekly appointment (GET /student|teacher/schedules)
/// expanded to dates (schedule_logic.dart calWeeklyEvents).
const calSources = ['meeting', 'timetable', 'extra', 'exam', 'course_session', 'course_weekly'];

/// The one-date change of a timetable session (GET /me/calendar?detail=true `change`): substitute · online /
/// offline · cancelled, with the students' answers. An older server sends only `change_id` + `mode`.
class CalChange {
  const CalChange({
    required this.id,
    this.mode,
    this.onlineUrl,
    this.cancelled = false,
    this.substitute = false,
    this.note,
    this.myResponse,
    this.canRespond = false,
    this.canEdit = false,
    this.accept = 0,
    this.reject = 0,
  });

  final int id;
  final String? mode, onlineUrl, note, myResponse;
  final bool cancelled, substitute, canRespond, canEdit;
  final int accept, reject;

  bool get online => mode == 'online';

  static CalChange? fromJson(dynamic v, {int? changeId, String? mode}) {
    if (v is Map) {
      final id = _int(v['id']);
      if (id == null) return null;
      final r = v['responses'] is Map ? v['responses'] as Map : const {};
      return CalChange(
        id: id,
        mode: v['mode']?.toString(),
        onlineUrl: v['online_url']?.toString(),
        cancelled: v['cancelled'] == true,
        substitute: v['substitute'] == true,
        note: v['note']?.toString(),
        myResponse: v['my_response']?.toString(),
        canRespond: v['can_respond'] == true,
        canEdit: v['can_edit'] == true,
        accept: _int(r['accept']) ?? 0,
        reject: _int(r['reject']) ?? 0,
      );
    }
    // an older server: only the id and the mode it applied
    return changeId == null ? null : CalChange(id: changeId, mode: mode);
  }

  /// The change after I answered [decision] (the counts follow at once, before the reload).
  CalChange answered(String decision) => CalChange(
        id: id,
        mode: mode,
        onlineUrl: onlineUrl,
        cancelled: cancelled,
        substitute: substitute,
        note: note,
        myResponse: decision,
        canRespond: canRespond,
        canEdit: canEdit,
        accept: accept + (decision == 'accept' ? 1 : 0) - (myResponse == 'accept' ? 1 : 0),
        reject: reject + (decision == 'reject' ? 1 : 0) - (myResponse == 'reject' ? 1 : 0),
      );
}

/// A published exam window that pauses an organization's weekly classes (`pauses[]`, dates inclusive).
class CalPause {
  const CalPause({required this.start, required this.end, required this.name, this.orgId, this.orgName, this.kind, this.id});
  final DateTime start, end; // wall days
  final String name;
  final String? orgName, kind;
  final int? orgId, id;

  bool covers(DateTime day) {
    final d = calDay(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// `pauses[]` of a feed answer, one per organization + window (each timetable of a term repeats it).
  static List<CalPause> listFrom(dynamic r) {
    final out = <CalPause>[];
    final seen = <String>{};
    if (r is! Map || r['pauses'] is! List) return out;
    for (final x in r['pauses'] as List) {
      if (x is! Map) continue;
      final a = DateTime.tryParse('${x['start_date'] ?? ''}'), b = DateTime.tryParse('${x['end_date'] ?? ''}');
      if (a == null || b == null) continue;
      if (!seen.add('${x['org_id']}|${x['exam_schedule_id']}|${x['start_date']}')) continue;
      final org = x['org'] is Map ? x['org'] as Map : const {};
      final orgName = AppConfig.lang == 'ar' ? (org['name_ar'] ?? org['name_en']) : (org['name_en'] ?? org['name_ar']);
      out.add(CalPause(
        start: calDay(a),
        end: calDay(b),
        name: '${x['name'] ?? ''}'.trim(),
        orgId: _int(x['org_id']),
        orgName: orgName?.toString(),
        kind: x['kind']?.toString(),
        id: _int(x['exam_schedule_id']),
      ));
    }
    return out;
  }
}

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
    this.cancelled = false,
    this.change,
    this.slotId,
  });

  final String id, source, title;
  final DateTime start, end; // UTC
  final String? subtitle, location, mode, myStatus, kind, color, orgName;
  final int? orgId, deptId, courseId, meetingId;
  final bool isOwner, editable;
  final Map<String, int> counts;

  /// A timetable date the staff cancelled (only with `detail=true`): shown struck through, never joined.
  final bool cancelled;

  /// The one-date change of a timetable session (null when the date runs as the timetable says).
  final CalChange? change;
  final int? slotId;

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
      cancelled: j['cancelled'] == true,
      change: CalChange.fromJson(j['change'], changeId: _int(j['change_id']), mode: j['mode']?.toString()),
      slotId: _int(j['slot_id']),
    );
  }

  static List<CalEvent> listFrom(dynamic r) => [
        if (r is Map && r['items'] is List)
          for (final x in r['items'] as List)
            if (x is Map) CalEvent.fromJson(Map<String, dynamic>.from(x)),
      ].whereType<CalEvent>().toList();

  CalEvent moved(DateTime s, DateTime e) => copyWith(start: s, end: e);

  CalEvent copyWith({DateTime? start, DateTime? end, String? myStatus, CalChange? change}) => CalEvent(
        id: id, source: source, title: title, start: start ?? this.start, end: end ?? this.end, subtitle: subtitle,
        orgId: orgId, deptId: deptId, courseId: courseId, meetingId: meetingId, location: location, mode: mode,
        myStatus: myStatus ?? this.myStatus, kind: kind, color: color, orgName: orgName, isOwner: isOwner,
        editable: editable, counts: counts, cancelled: cancelled, change: change ?? this.change, slotId: slotId);

  /// The course session's id (`session:<id>`), null for every other source.
  int? get sessionId => source == 'course_session' && id.startsWith('session:') ? int.tryParse(id.substring(8)) : null;

  DateTime get wallStart => AppTime.toZone(start);
  DateTime get wallEnd => AppTime.toZone(end);
  Duration get duration => end.difference(start);
  bool get declined => myStatus == 'declined';
  bool get isMeeting => source == 'meeting';
  bool get online => mode == 'online' || (change?.online ?? false);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Days, ranges and layout (wall clock)
// ═════════════════════════════════════════════════════════════════════════════

DateTime calDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Arabic weeks start on Saturday, English ones on Monday.
int calWeekStart([String? lang]) => (lang ?? AppConfig.lang) == 'ar' ? DateTime.saturday : DateTime.monday;

DateTime _startOfWeek(DateTime d, int weekStart) => calDay(d).subtract(Duration(days: (d.weekday - weekStart + 7) % 7));

/// The rolling week (D-101): 7 days from [from], the window's first day.
List<DateTime> calWeekDays(DateTime from) {
  final s = calDay(from);
  return [for (var i = 0; i < 7; i++) DateTime(s.year, s.month, s.day + i)];
}

/// Where the rolling week starts once [focus] is shown: the focused day is the SECOND column (yesterday · today ·
/// tomorrow … when the page opens). The window on screen ([current]) is kept while [focus] stays inside it, so a tap
/// on the phone's day strip or on a day header never moves the columns under the finger.
DateTime calWeekFrom(DateTime focus, {DateTime? current}) {
  final f = calDay(focus);
  if (current != null) {
    final c = calDay(current);
    if (!f.isBefore(c) && f.isBefore(DateTime(c.year, c.month, c.day + 7))) return c;
  }
  return DateTime(f.year, f.month, f.day - 1);
}

/// The days a view shows: 1 · the rolling 7 ([weekFrom], else [anchor] as the second column) · the 6×7 month
/// grid (a real month, from [weekStart]).
List<DateTime> calVisibleDays(CalView v, DateTime anchor, {int? weekStart, DateTime? weekFrom}) {
  final ws = weekStart ?? calWeekStart();
  switch (v) {
    case CalView.agenda:
      final a = calDay(anchor);
      return [for (var i = 0; i < calAgendaDays; i++) DateTime(a.year, a.month, a.day + i)];
    case CalView.day:
      return [calDay(anchor)];
    case CalView.week:
      return calWeekDays(weekFrom ?? calWeekFrom(anchor));
    case CalView.month:
      final s = _startOfWeek(DateTime(anchor.year, anchor.month), ws);
      return [for (var i = 0; i < 42; i++) DateTime(s.year, s.month, s.day + i)];
  }
}

/// UTC [start, end) to fetch for a view ([toUtc] = AppTime.fromZone in the app). The day view fetches its rolling
/// week ([weekFrom]) and the agenda starts the day before its first day, so switching day ↔ week ↔ agenda finds the
/// days already in the cache; [agendaDays] = how many days the agenda shows now.
(DateTime, DateTime) calFetchRange(CalView v, DateTime anchor,
    {int? weekStart, DateTime Function(DateTime)? toUtc, int agendaDays = calAgendaDays, DateTime? weekFrom}) {
  final ws = weekStart ?? calWeekStart();
  final f = toUtc ?? AppTime.fromZone;
  if (v == CalView.agenda) {
    final a = calDay(anchor);
    final n = agendaDays < 6 ? 6 : agendaDays;
    return (f(DateTime(a.year, a.month, a.day - 1)), f(DateTime(a.year, a.month, a.day + n)));
  }
  final days = calVisibleDays(v == CalView.day ? CalView.week : v, anchor, weekStart: ws, weekFrom: weekFrom);
  final last = days.last;
  return (f(days.first), f(DateTime(last.year, last.month, last.day + 1)));
}

DateTime calShift(CalView v, DateTime anchor, int dir) => switch (v) {
      CalView.agenda => DateTime(anchor.year, anchor.month, anchor.day + 7 * dir),
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

/// The minute of the day the time grid scrolls to (D-101): the first appointment still running or still to come in
/// the shown [days] (a class in progress counts as next); else now, when today is shown; else the earliest
/// appointment shown (a past week); else 8:00. Cancelled and declined ones are skipped.
int calFocusMinute(Iterable<CalEvent> events, List<DateTime> days, DateTime nowWall) {
  int? earliest;
  for (final d in days) {
    final placed = calLayoutDay(events, d).where((p) => !p.event.cancelled && !p.event.declined).toList()
      ..sort((x, y) => x.top.compareTo(y.top));
    for (final p in placed) {
      if (p.event.wallEnd.isAfter(nowWall)) return p.top;
      if (earliest == null || p.top < earliest) earliest = p.top;
    }
  }
  final today = calDay(nowWall);
  if (days.any((d) => calDay(d) == today)) return nowWall.hour * 60 + nowWall.minute;
  return earliest ?? 8 * 60;
}

/// The grid's scroll offset that puts [minute]'s hour row on the 5th row of a tall grid (≥ 11 hour rows: a desktop
/// window), the 3rd on a phone (≥ 7 rows), the 2nd on a very short one — about a third of the way down, with the
/// hours before it in view; 10 px higher so the top row's hour label is not cut; never past either end.
double calFocusOffset(int minute, {required double hourHeight, required double viewport, required double maxExtent}) {
  final rows = viewport / hourHeight;
  final above = rows >= 11 ? 4 : (rows >= 7 ? 2 : 1);
  final top = ((minute ~/ 60) - above) * hourHeight - 10;
  return top.clamp(0.0, maxExtent < 0 ? 0.0 : maxExtent).toDouble();
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
      'course_weekly' => t('مواعيد المقررات', 'Course appointments'),
      _ => s,
    };

IconData calSourceIcon(String s) => switch (s) {
      'meeting' => Icons.groups_2_rounded,
      'timetable' => Icons.class_rounded,
      'extra' => Icons.event_note_rounded,
      'exam' => Icons.edit_note_rounded,
      'course_session' || 'course_weekly' => Icons.sensors_rounded,
      _ => Icons.event_rounded,
    };

/// One colour per kind of event, derived from the live theme (D-085): classes = primary (a lab leans to success),
/// exams = danger, live sessions = purple, meetings = gold (a private one = warning), special periods between
/// primary and purple.
Color calSourceColor(ThemeConfigProvider c, String source, {String? kind}) => switch (source) {
      'meeting' => kind == 'private' ? c.warning : c.accent2,
      'timetable' => kind == 'lab' ? Color.lerp(c.primary, c.success, 0.6)! : c.primary,
      'extra' => Color.lerp(c.primary, c.purple, 0.5)!,
      'exam' => c.danger,
      'course_session' || 'course_weekly' => c.purple,
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

String calTitleFor(CalView v, DateTime anchor, {DateTime? weekFrom}) {
  final days = calVisibleDays(v, anchor, weekFrom: weekFrom);
  String fmt(DateTime d, String p) => AppTime.date(AppTime.fromZone(DateTime(d.year, d.month, d.day, 12)), pattern: p);
  return switch (v) {
    CalView.day => fmt(anchor, 'EEEE d MMMM y'),
    CalView.month || CalView.agenda => fmt(DateTime(anchor.year, anchor.month, 15), 'MMMM y'),
    CalView.week => days.first.month == days.last.month
        ? '${fmt(days.first, 'd')} – ${fmt(days.last, 'd MMMM y')}'
        : '${fmt(days.first, 'd MMM')} – ${fmt(days.last, 'd MMM y')}',
  };
}

// ── The meeting form's request (live-rooms-spec §7 – §8) ─────────────────────

/// Why the form's title blocks saving: required in person, optional online (the server then names the meeting
/// after its start date and time). Null = fine.
String? calMeetingTitleError(String title, String mode) =>
    mode != 'online' && title.trim().isEmpty ? t('اكتب عنوان الاجتماع', 'Give the meeting a title') : null;

/// POST …/meetings body. A blank title is left out (online only — offline is stopped by [calMeetingTitleError]);
/// a student's meeting is always online and private (an empty audience), whatever the form held.
Map<String, dynamic> calMeetingBody({
  required String title,
  String notes = '',
  required String startsAt,
  required String endsAt,
  required String mode,
  String location = '',
  int? orgId,
  int? deptId,
  required Map<String, dynamic> audience,
  required Map<String, dynamic> emptyAudience,
  bool student = false,
  bool force = false,
}) {
  final m = student ? 'online' : mode;
  return {
    if (title.trim().isNotEmpty) 'title': title.trim(),
    if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    'starts_at': startsAt,
    'ends_at': endsAt,
    'mode': m,
    if (m == 'offline' && location.trim().isNotEmpty) 'location': location.trim(),
    'org_id': ?orgId,
    'dept_id': ?deptId,
    'audience': student ? emptyAudience : audience,
    'force': force,
  };
}
