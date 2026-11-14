// lib/features/calendar/schedule_logic.dart — the pure part of the one schedule page (D-085).
//
//   CalCat / calCatOf          the four kinds the page filters by: classes · exams · live sessions · meetings
//   CalFilters                 hidden kinds + hidden organizations, remembered on the device (encode / decode)
//   calOrgsOf                  the organizations the events come from (0 = personal), for the per-org chips
//   calAgenda                  the agenda: today pinned, then the days that hold something, the "now" line's place
//   calIsOver / calComing /    what has finished (its time passed, or a meeting that was closed: D-321), what is still
//   calPast                    to come, and the finished ones by day, newest first (the Scheduled meetings tab)
//   calJoinable / calIsLive    when an event shows Join, and when it is live (the home's live rooms + the clock)
//   calWeeklySlotsFrom /       a personal course's weekly appointments (GET /student|teacher/schedules) expanded to
//   calWeeklyEvents            dated `course_weekly` events in the range, minus the dates a dated session covers
//   calWhen                    "Now · 20 min left" · "In 45 min" · "Ended" (null for another day)
//   calIcs                     the shown events as an iCalendar file (UTC instants; opens in Google / Apple / Outlook)
//   CalChunk / calCovering     the feed cache: one fetched range per scope, any later range inside it is served
//
// Unit-tested in test/ui/schedule_logic_test.dart. No Flutter widgets here, only values.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/org/org_schedule_ical.dart' show icsEscape, icsFold;
import 'package:flutter_education_app/features/calendar/calendar_models.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Kinds
// ═════════════════════════════════════════════════════════════════════════════

enum CalCat { classes, exams, live, meetings }

CalCat calCatOf(CalEvent e) => switch (e.source) {
      'exam' => CalCat.exams,
      'course_session' || 'course_weekly' => CalCat.live,
      'meeting' => CalCat.meetings,
      _ => CalCat.classes,
    };

String calCatLabel(CalCat c) => switch (c) {
      CalCat.classes => t('المحاضرات', 'Classes'),
      CalCat.exams => t('الامتحانات', 'Exams'),
      CalCat.live => t('البث المباشر', 'Live'),
      CalCat.meetings => t('الاجتماعات', 'Meetings'),
    };

IconData calCatIcon(CalCat c) => switch (c) {
      CalCat.classes => Icons.class_rounded,
      CalCat.exams => Icons.edit_note_rounded,
      CalCat.live => Icons.sensors_rounded,
      CalCat.meetings => Icons.groups_2_rounded,
    };

Color calCatColor(ThemeConfigProvider c, CalCat k) => switch (k) {
      CalCat.classes => calSourceColor(c, 'timetable'),
      CalCat.exams => calSourceColor(c, 'exam'),
      CalCat.live => calSourceColor(c, 'course_session'),
      CalCat.meetings => calSourceColor(c, 'meeting'),
    };

Map<CalCat, int> calCountsByCat(Iterable<CalEvent> events) {
  final out = <CalCat, int>{};
  for (final e in events) {
    if (e.cancelled) continue;
    out[calCatOf(e)] = (out[calCatOf(e)] ?? 0) + 1;
  }
  return out;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Filters (remembered on the device)
// ═════════════════════════════════════════════════════════════════════════════

const calFiltersPrefKey = 'calendar.filters.v1';

/// The tab and the grid the page was last on, remembered on the device: `<view>|<grid view>`.
const calViewPrefKey = 'calendar.view.v1';

/// [view] = the page's view (`agenda` is the Scheduled meetings tab), [grid] = the one the Calendar tab goes back to.
String calViewEncode(CalView view, CalView? grid) => '${view.name}|${grid?.name ?? ''}';

/// Anything unreadable gives (null, null): the page then opens on its default for the width.
(CalView?, CalView?) calViewDecode(String? raw) {
  if (raw == null || raw.isEmpty) return (null, null);
  final names = {for (final v in CalView.values) v.name: v};
  final p = raw.split('|');
  final grid = p.length > 1 ? names[p[1]] : null;
  return (names[p[0]], grid == CalView.agenda ? null : grid);
}

class CalFilters {
  const CalFilters({this.hiddenCats = const {}, this.hiddenOrgs = const {}});

  final Set<CalCat> hiddenCats;

  /// Organization ids whose events are hidden; 0 = my personal events (no organization).
  final Set<int> hiddenOrgs;

  bool get any => hiddenCats.isNotEmpty || hiddenOrgs.isNotEmpty;

  bool shows(CalEvent e) => !hiddenCats.contains(calCatOf(e)) && !hiddenOrgs.contains(e.orgId ?? 0);

  List<CalEvent> apply(Iterable<CalEvent> events) => [for (final e in events) if (shows(e)) e];

  CalFilters toggleCat(CalCat c) => CalFilters(
        hiddenCats: hiddenCats.contains(c) ? ({...hiddenCats}..remove(c)) : {...hiddenCats, c},
        hiddenOrgs: hiddenOrgs,
      );

  CalFilters toggleOrg(int id) => CalFilters(
        hiddenCats: hiddenCats,
        hiddenOrgs: hiddenOrgs.contains(id) ? ({...hiddenOrgs}..remove(id)) : {...hiddenOrgs, id},
      );

  String encode() => jsonEncode({
        'cats': [for (final c in hiddenCats) c.name],
        'orgs': [...hiddenOrgs],
      });

  /// Anything unreadable (an older format, a removed kind) is dropped: the page then shows everything.
  static CalFilters decode(String? raw) {
    if (raw == null || raw.isEmpty) return const CalFilters();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const CalFilters();
      final names = {for (final c in CalCat.values) c.name: c};
      return CalFilters(
        hiddenCats: {
          if (m['cats'] is List)
            for (final x in m['cats'] as List)
              if (names[x] != null) names[x]!,
        },
        hiddenOrgs: {
          if (m['orgs'] is List)
            for (final x in m['orgs'] as List)
              if (x is int) x,
        },
      );
    } catch (_) {
      return const CalFilters();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CalFilters &&
      other.hiddenCats.length == hiddenCats.length &&
      other.hiddenCats.containsAll(hiddenCats) &&
      other.hiddenOrgs.length == hiddenOrgs.length &&
      other.hiddenOrgs.containsAll(hiddenOrgs);

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(hiddenCats), Object.hashAllUnordered(hiddenOrgs));
}

class CalOrgOption {
  const CalOrgOption(this.id, this.name);

  /// 0 = personal (events without an organization).
  final int id;
  final String name;
}

/// The organizations of [events], personal first, then by name. Only worth chips with two or more.
List<CalOrgOption> calOrgsOf(Iterable<CalEvent> events) {
  final names = <int, String>{};
  var personal = false;
  for (final e in events) {
    if (e.orgId == null) {
      personal = true;
    } else {
      final n = (e.orgName ?? '').trim();
      if (n.isNotEmpty || !names.containsKey(e.orgId)) names[e.orgId!] = n.isEmpty ? (names[e.orgId] ?? '#${e.orgId}') : n;
    }
  }
  final orgs = [for (final x in names.entries) CalOrgOption(x.key, x.value)]..sort((a, b) => a.name.compareTo(b.name));
  return [if (personal) CalOrgOption(0, t('شخصي', 'Personal')), ...orgs];
}

// ═════════════════════════════════════════════════════════════════════════════
//  Agenda
// ═════════════════════════════════════════════════════════════════════════════

class CalAgendaDay {
  const CalAgendaDay({required this.day, required this.events, this.today = false, this.nowAt, this.pauses = const []});
  final DateTime day; // wall day
  final List<CalEvent> events;
  final bool today;

  /// Today only: the index in [events] the "now" line goes before (== events.length: after the last one).
  final int? nowAt;

  /// Exam windows that pause the weekly classes on this day (shown once, on their first day in the range).
  final List<CalPause> pauses;
}

/// The agenda over [days] days from [from] (wall): today is always there (pinned, even when free), every other day
/// only when it holds an event or the first day of an exam-window pause. [nowWall] places the "now" line: before the
/// first event of today that has not started yet.
List<CalAgendaDay> calAgenda(
  Iterable<CalEvent> events, {
  required DateTime from,
  required int days,
  required DateTime nowWall,
  List<CalPause> pauses = const [],
}) {
  final today = calDay(nowWall);
  final first = calDay(from);
  final out = <CalAgendaDay>[];
  for (var i = 0; i < days; i++) {
    final d = DateTime(first.year, first.month, first.day + i);
    final evs = calEventsOnDay(events, d);
    final starting = [for (final p in pauses) if (p.covers(d) && (calDay(p.start) == d || d == first)) p];
    final isToday = d == today;
    if (evs.isEmpty && !isToday && starting.isEmpty) continue;
    int? nowAt;
    if (isToday) {
      nowAt = evs.length;
      for (var k = 0; k < evs.length; k++) {
        if (evs[k].wallStart.isAfter(nowWall)) {
          nowAt = k;
          break;
        }
      }
    }
    out.add(CalAgendaDay(day: d, events: evs, today: isToday, nowAt: nowAt, pauses: starting));
  }
  return out;
}

/// How many events the agenda lists, cancelled dates left out (an event over midnight counts on each day).
int calAgendaCount(List<CalAgendaDay> days) => days.fold(0, (n, d) => n + d.events.where((e) => !e.cancelled).length);

/// Finished: a meeting that was closed, whatever its scheduled end says, or any event whose time has passed. A room
/// still open past its scheduled end is not finished.
bool calIsOver(CalEvent e, DateTime nowUtc, {Set<String> liveKeys = const {}}) =>
    e.ended || (!e.end.isAfter(nowUtc) && !calIsLive(e, nowUtc, liveKeys: liveKeys));

/// What is still to come (live rooms included), in the order given.
List<CalEvent> calComing(Iterable<CalEvent> events, DateTime nowUtc, {Set<String> liveKeys = const {}}) =>
    [for (final e in events) if (!calIsOver(e, nowUtc, liveKeys: liveKeys)) e];

/// The finished events by the day they were scheduled on, the newest day and the latest event first. A cancelled date
/// is left out here (it never happened); the grid still draws it.
List<CalAgendaDay> calPast(Iterable<CalEvent> events, {required DateTime nowUtc, required DateTime nowWall, Set<String> liveKeys = const {}}) {
  final byDay = <DateTime, List<CalEvent>>{};
  for (final e in events) {
    if (e.cancelled || !calIsOver(e, nowUtc, liveKeys: liveKeys)) continue;
    (byDay[calDay(e.wallStart)] ??= []).add(e);
  }
  final today = calDay(nowWall);
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days) CalAgendaDay(day: d, today: d == today, events: byDay[d]!..sort((a, b) => b.start.compareTo(a.start))),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
//  Live / join
// ═════════════════════════════════════════════════════════════════════════════

/// How early Join shows before an online meeting / online class starts.
const calJoinEarly = Duration(minutes: 10);

String calLiveKeyMeeting(int id) => 'meeting:$id';
String calLiveKeySession(int id) => 'session:$id';
String calLiveKeyCourse(int id) => 'course:$id';

bool calRunning(CalEvent e, DateTime nowUtc) => !e.ended && !e.start.isAfter(nowUtc) && e.end.isAfter(nowUtc);

/// Live right now: a room the home knows is open ([liveKeys]: `meeting:<id>` · `session:<id>` · `course:<courseId>`),
/// or a running online class / meeting. A closed meeting never is, even when a stale live key still names it.
bool calIsLive(CalEvent e, DateTime nowUtc, {Set<String> liveKeys = const {}}) {
  if (e.cancelled || e.declined || e.ended) return false;
  if (e.meetingId != null && liveKeys.contains(calLiveKeyMeeting(e.meetingId!))) return true;
  if (e.sessionId != null && liveKeys.contains(calLiveKeySession(e.sessionId!))) return true;
  if (e.source == 'course_weekly' && e.courseId != null && liveKeys.contains(calLiveKeyCourse(e.courseId!))) return true;
  return false;
}

/// Join shows: a live room, or an online meeting / online class from [calJoinEarly] before its start to its end.
bool calJoinable(CalEvent e, DateTime nowUtc, {Set<String> liveKeys = const {}}) {
  if (e.cancelled || e.declined || e.ended) return false;
  if (calIsLive(e, nowUtc, liveKeys: liveKeys)) return true;
  final window = !e.start.subtract(calJoinEarly).isAfter(nowUtc) && e.end.isAfter(nowUtc);
  if (!window) return false;
  if (e.isMeeting) return e.mode == 'online';
  if (e.source == 'timetable') return (e.change?.online ?? false) && (e.change?.onlineUrl ?? '').isNotEmpty;
  return false;
}

/// "Now · 20 min left" · "In 45 min" · "In 3 h" (same day) · "Ended" (today) · null for another day.
String? calWhen(CalEvent e, DateTime nowUtc, {DateTime Function(DateTime)? toWall}) {
  if (e.cancelled) return null;
  if (e.ended) return t('انتهى', 'Ended');
  final w = toWall ?? (DateTime d) => d;
  if (calRunning(e, nowUtc)) {
    final left = e.end.difference(nowUtc).inMinutes;
    return left < 60 ? t('الآن · متبقٍ $left د', 'Now · $left min left') : t('جارٍ الآن', 'Happening now');
  }
  final sameDay = calDay(w(e.start)) == calDay(w(nowUtc));
  if (!sameDay) return null;
  if (!e.end.isAfter(nowUtc)) return t('انتهى', 'Ended');
  final m = e.start.difference(nowUtc).inMinutes;
  if (m < 1) return t('يبدأ الآن', 'Starting now');
  if (m < 60) return t('بعد $m د', 'In $m min');
  final h = (m / 60).floor();
  final r = m % 60;
  return r == 0 || h >= 3 ? t('بعد $h س', 'In $h h') : t('بعد $h س $r د', 'In $h h $r min');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Weekly course appointments (personal courses)
// ═════════════════════════════════════════════════════════════════════════════

class CalWeeklySlot {
  const CalWeeklySlot({required this.scheduleId, required this.courseId, required this.courseName, required this.day, required this.start, required this.end});
  final int scheduleId, courseId;
  final String courseName;

  /// monday … sunday
  final String day;

  /// "HH:MM" wall clock (as the course page shows it).
  final String start, end;
}

const _weekdays = {'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7};

int? _minutes(String hhmm) {
  final p = hhmm.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// `all_courses[].schedules[]` of GET /student|teacher/schedules (anything unreadable is skipped).
List<CalWeeklySlot> calWeeklySlotsFrom(dynamic body) {
  final out = <CalWeeklySlot>[];
  if (body is! Map || body['all_courses'] is! List) return out;
  for (final g in body['all_courses'] as List) {
    if (g is! Map || g['schedules'] is! List) continue;
    for (final s in g['schedules'] as List) {
      if (s is! Map) continue;
      final day = '${s['day'] ?? ''}'.toLowerCase();
      final a = '${s['start_time'] ?? ''}', b = '${s['end_time'] ?? ''}';
      if (!_weekdays.containsKey(day) || _minutes(a) == null || _minutes(b) == null) continue;
      final cid = s['course_id'] ?? g['course_id'];
      final name = '${s['course_name'] ?? g['course_name'] ?? ''}'.trim();
      out.add(CalWeeklySlot(
        scheduleId: s['schedule_id'] is num ? (s['schedule_id'] as num).toInt() : 0,
        courseId: cid is num ? cid.toInt() : int.tryParse('$cid') ?? 0,
        courseName: name,
        day: day,
        start: a,
        end: b,
      ));
    }
  }
  return out;
}

/// The weekly appointments as dated events on the wall days [from, to) ([toUtc] = AppTime.fromZone). A date a
/// dated course session of the same course already covers (overlapping) is left out.
List<CalEvent> calWeeklyEvents(
  List<CalWeeklySlot> slots, {
  required DateTime from,
  required DateTime to,
  Iterable<CalEvent> existing = const [],
  required DateTime Function(DateTime wall) toUtc,
}) {
  final sessions = [for (final e in existing) if (e.source == 'course_session') e];
  final out = <CalEvent>[];
  for (var d = calDay(from); d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
    for (final s in slots) {
      if (_weekdays[s.day] != d.weekday) continue;
      final a = _minutes(s.start)!, b = _minutes(s.end)!;
      final ws = DateTime(d.year, d.month, d.day, a ~/ 60, a % 60);
      final we = b > a ? DateTime(d.year, d.month, d.day, b ~/ 60, b % 60) : ws.add(const Duration(hours: 1));
      final us = toUtc(ws).toUtc(), ue = toUtc(we).toUtc();
      if (sessions.any((x) => x.courseId == s.courseId && x.start.isBefore(ue) && us.isBefore(x.end))) continue;
      out.add(CalEvent(
        id: 'weekly:${s.scheduleId}:${d.year}-${d.month}-${d.day}',
        source: 'course_weekly',
        title: s.courseName.isEmpty ? t('موعد المقرر', 'Course appointment') : s.courseName,
        start: us,
        end: ue,
        courseId: s.courseId,
        mode: 'online',
        kind: 'lecture',
      ));
    }
  }
  return out;
}

// ═════════════════════════════════════════════════════════════════════════════
//  .ics
// ═════════════════════════════════════════════════════════════════════════════

String _utcStamp(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// The events (cancelled dates left out) as one VCALENDAR, CRLF lines folded at 75 octets.
String calIcs(Iterable<CalEvent> events, {required String name, DateTime? stamp}) {
  final now = _utcStamp(stamp ?? DateTime.now());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//NextBrain//Schedule//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${icsEscape(name)}',
  ];
  for (final e in events) {
    if (e.cancelled) continue;
    final desc = [
      calSourceLabel(e.source),
      if ((e.subtitle ?? '').isNotEmpty) e.subtitle!,
      if ((e.orgName ?? '').isNotEmpty) e.orgName!,
    ].join(' · ');
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${icsEscape(e.id)}@nextbrain.site',
      'DTSTAMP:$now',
      'DTSTART:${_utcStamp(e.start)}',
      'DTEND:${_utcStamp(e.end)}',
      'SUMMARY:${icsEscape(e.title)}',
      if ((e.location ?? '').isNotEmpty) 'LOCATION:${icsEscape(e.location!)}',
      'DESCRIPTION:${icsEscape(desc)}',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(icsFold).join('\r\n')}\r\n';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Feed cache
// ═════════════════════════════════════════════════════════════════════════════

/// One fetched range of GET /me/calendar for a scope (`me` · `org:<id>` · `dept:<id>`).
class CalChunk {
  CalChunk({
    required this.scope,
    required this.start,
    required this.end,
    required this.events,
    this.pauses = const [],
    this.pending = 0,
    required this.fetchedAt,
  });

  final String scope;
  final DateTime start, end; // UTC
  final List<CalEvent> events;
  final List<CalPause> pauses;
  final int pending;
  final DateTime fetchedAt;

  /// Set when a live event says the calendar changed: still drawn at once, then fetched again.
  bool stale = false;
}

/// The newest chunk of [scope] that holds the whole UTC range [s, e), or null.
CalChunk? calCovering(List<CalChunk> chunks, String scope, DateTime s, DateTime e) {
  CalChunk? best;
  for (final c in chunks) {
    if (c.scope != scope || c.start.isAfter(s) || c.end.isBefore(e)) continue;
    if (best == null || c.fetchedAt.isAfter(best.fetchedAt)) best = c;
  }
  return best;
}

/// The events of [events] that touch the UTC range [s, e).
List<CalEvent> calSlice(Iterable<CalEvent> events, DateTime s, DateTime e) =>
    [for (final x in events) if (x.start.isBefore(e) && x.end.isAfter(s)) x];
