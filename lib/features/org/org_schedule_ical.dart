// lib/features/org/org_schedule_ical.dart — a weekly timetable as an iCalendar (.ics) file, built in the app.
//
//   timetableIcs   pure: one VEVENT per session block with a weekly RRULE (from the term's first day to its last;
//                  without dates: the coming week, repeating for 16 weeks). Floating local times, no timezone
//                  (the organization's wall clock, exactly as the grid shows it). Opens in Google / Apple / Outlook.
library;

import 'dart:convert';

import 'org_schedule_versions.dart' show TimetableNames;

const _byDay = {'saturday': 'SA', 'sunday': 'SU', 'monday': 'MO', 'tuesday': 'TU', 'wednesday': 'WE', 'thursday': 'TH', 'friday': 'FR'};
const _weekday = {'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7};

String _two(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime d, String hhmm) => '${d.year}${_two(d.month)}${_two(d.day)}T${hhmm.replaceAll(':', '').padRight(4, '0').substring(0, 4)}00';
String _date(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';

/// iCal text escaping (RFC 5545): backslash, comma, semicolon, newline.
String icsEscape(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

/// Lines longer than 75 octets are folded with CRLF + space.
String icsFold(String line) {
  final b = utf8.encode(line);
  if (b.length <= 75) return line;
  final out = StringBuffer();
  var start = 0;
  var first = true;
  while (start < line.length) {
    var end = start;
    var size = 0;
    while (end < line.length) {
      final n = utf8.encode(line[end]).length;
      if (size + n > (first ? 75 : 74)) break;
      size += n;
      end++;
    }
    out.write(first ? line.substring(start, end) : '\r\n ${line.substring(start, end)}');
    first = false;
    start = end;
  }
  return out.toString();
}

/// Sessions grouped by block → events. [periods]: {id, start_time, end_time, order}. [from]/[to]: the term's
/// first and last day (the series starts on the first matching weekday on/after [from] and ends at [to]).
String timetableIcs(
  List<Map<String, dynamic>> slots,
  TimetableNames names,
  List<Map<String, dynamic>> periods, {
  required String calendarName,
  DateTime? from,
  DateTime? to,
  DateTime? now,
  String Function(Object? kind)? kindLabel,
}) {
  final per = {for (final p in periods) '${p['id']}': p};
  final order = {for (final p in periods) '${p['id']}': int.tryParse('${p['order']}') ?? 0};
  final blocks = <String, List<Map<String, dynamic>>>{};
  for (final s in slots) {
    blocks.putIfAbsent('${s['block_id'] ?? 'slot-${s['id']}'}|${s['course_id']}|${s['day']}', () => []).add(s);
  }
  final start0 = from ?? (now ?? DateTime.now());
  final anchor = DateTime(start0.year, start0.month, start0.day);
  final stamp = now ?? DateTime.now();
  final out = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\n')
    ..write('VERSION:2.0\r\n')
    ..write('PRODID:-//NextBrain//Timetable//EN\r\n')
    ..write('CALSCALE:GREGORIAN\r\n')
    ..write('METHOD:PUBLISH\r\n')
    ..write('${icsFold('X-WR-CALNAME:${icsEscape(calendarName)}')}\r\n');
  final keys = blocks.keys.toList()..sort();
  var n = 0;
  for (final k in keys) {
    final bl = blocks[k]!..sort((a, b) => (order['${a['period_id']}'] ?? 0).compareTo(order['${b['period_id']}'] ?? 0));
    final s = bl.first;
    final day = '${s['day']}';
    final wd = _weekday[day];
    if (wd == null) continue;
    final first = per['${bl.first['period_id']}'], last = per['${bl.last['period_id']}'];
    if (first == null || last == null) continue;
    var d = anchor;
    while (d.weekday != wd) {
      d = d.add(const Duration(days: 1));
    }
    final kind = kindLabel?.call(s['kind']) ?? '${s['kind'] ?? 'lecture'}';
    final summary = '${names.course(s['course_id'])} · $kind${s['group_no'] == null ? '' : ' ${s['group_no']}'}';
    final who = [names.person(s['teacher_id']), names.person(s['assistant_id'])].where((x) => x.isNotEmpty).join(', ');
    final until = to == null ? null : DateTime(to.year, to.month, to.day);
    final rrule = until != null ? 'FREQ=WEEKLY;BYDAY=${_byDay[day]};UNTIL=${_date(until)}T235959' : 'FREQ=WEEKLY;BYDAY=${_byDay[day]};COUNT=16';
    n++;
    out
      ..write('BEGIN:VEVENT\r\n')
      ..write('UID:tt-${s['id'] ?? n}-${_date(d)}@nextbrain.site\r\n')
      ..write('DTSTAMP:${_stamp(DateTime(stamp.year, stamp.month, stamp.day), '${_two(stamp.hour)}:${_two(stamp.minute)}')}Z\r\n')
      ..write('DTSTART:${_stamp(d, '${first['start_time']}')}\r\n')
      ..write('DTEND:${_stamp(d, '${last['end_time']}')}\r\n')
      ..write('RRULE:$rrule\r\n')
      ..write('${icsFold('SUMMARY:${icsEscape(summary)}')}\r\n');
    if (s['room_id'] != null) out.write('${icsFold('LOCATION:${icsEscape(names.room(s['room_id']))}')}\r\n');
    if (who.isNotEmpty) out.write('${icsFold('DESCRIPTION:${icsEscape(who)}')}\r\n');
    out.write('END:VEVENT\r\n');
  }
  out.write('END:VCALENDAR\r\n');
  return out.toString();
}
