// lib/features/calendar/recurrence/recurrence_rule.dart — the plain repeat rule of a meeting series (Learning Hub v2
// contract §4, D-1570) and its one summary sentence.
//
//   RecurrenceRule      freq · interval · weekdays · skip_weekdays · skip_dates · start / end date · time · tz;
//                       toJson / fromJson in the contract's wire shape (weekday 0 = Monday, dates "YYYY-MM-DD",
//                       times "HH:MM" wall clock in [tz])
//   describeRule        "Every day except Fri and Sat, 10:00 to 11:00, until further notice" (ar / en)
//   recurrenceWeekOrder the weekday chips' order (Saturday first in Arabic, Monday first in English)
//
// Pure Dart (no widget), so the packages wizard and the tests use it without a screen.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/plural.dart';

/// How a series repeats. A meeting that does not repeat has no rule at all (null).
enum RecurrenceFreq { daily, weekly, custom }

/// The step of a custom rule: every n days, or every n weeks on some weekdays.
enum RecurrenceUnit { days, weeks }

/// The reminder lead times the picker offers (minutes; the server takes 0..1440, default 15).
const recurrenceReminderChoices = [0, 5, 10, 15, 30, 60, 120, 1440];

/// The default reminder lead time (contract §4).
const kRecurrenceReminderDefault = 15;

/// The kill switch that hides the Repeat section (and the course's "Repeating meeting" entry).
const kRecurringFeatureKey = 'calendar.recurring';

/// The weekday chips' order on the wire scale (0 = Monday): Saturday first in Arabic, Monday first in English.
List<int> recurrenceWeekOrder([String? lang]) =>
    (lang ?? AppConfig.lang) == 'ar' ? const [5, 6, 0, 1, 2, 3, 4] : const [0, 1, 2, 3, 4, 5, 6];

/// Wire weekday (0 = Monday) of a date.
int recurrenceWeekdayOf(DateTime d) => d.weekday - 1;

String _two(int n) => n.toString().padLeft(2, '0');

/// "YYYY-MM-DD" of a calendar date.
String recurrenceDateWire(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// A "YYYY-MM-DD" (or longer ISO) string → the calendar date, null when it does not parse.
DateTime? recurrenceDateParse(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Minutes after midnight → "HH:MM".
String recurrenceTimeWire(int minutes) => '${_two(minutes ~/ 60 % 24)}:${_two(minutes % 60)}';

/// "HH:MM" → minutes after midnight, null when it does not parse.
int? recurrenceTimeParse(dynamic v) {
  final p = '${v ?? ''}'.trim().split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1].length > 2 ? p[1].substring(0, 2) : p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

class RecurrenceRule {
  const RecurrenceRule({
    required this.freq,
    this.interval = 1,
    this.weekdays = const [],
    this.skipWeekdays = const [],
    this.skipDates = const [],
    required this.startDate,
    this.endDate,
    this.count,
    this.allDay = false,
    this.startTime,
    this.endTime,
    this.tz = '',
  });

  /// A [freq] rule from [start] (its date, weekday and clock) to [end]'s clock, with no end date.
  factory RecurrenceRule.from(DateTime start, {DateTime? end, RecurrenceFreq freq = RecurrenceFreq.weekly}) {
    final day = DateTime(start.year, start.month, start.day);
    final e = end ?? start.add(const Duration(minutes: 30));
    return RecurrenceRule(
      freq: freq,
      weekdays: freq == RecurrenceFreq.daily ? const [] : [recurrenceWeekdayOf(day)],
      startDate: day,
      startTime: start.hour * 60 + start.minute,
      endTime: e.hour * 60 + e.minute,
      tz: AppTime.zoneId,
    );
  }

  final RecurrenceFreq freq;

  /// Every n days (daily / custom in days) or weeks (weekly / custom in weeks), 1..30.
  final int interval;

  /// Wire weekdays (0 = Monday) of a weekly rule, or of a custom rule in weeks. Empty on a daily rule.
  final List<int> weekdays;

  /// Weekdays dropped after the step (daily except Fri and Sat).
  final List<int> skipWeekdays;

  /// Single dates dropped (calendar dates, sorted).
  final List<DateTime> skipDates;
  final DateTime startDate;

  /// Null = no end date ("until further notice", unless [count] ends it).
  final DateTime? endDate;

  /// Ends after this many dates (skipped and cancelled ones do not count; contract C6). Null = no count.
  final int? count;

  /// Any time of the day (no from–to).
  final bool allDay;

  /// Wall-clock minutes after midnight in [tz]; null when [allDay].
  final int? startTime, endTime;

  /// The creator's AppTime zone; the wall times are in it.
  final String tz;

  /// A custom rule counts in weeks when it names weekdays, in days otherwise (D-1571).
  RecurrenceUnit get unit => freq == RecurrenceFreq.weekly || (freq == RecurrenceFreq.custom && weekdays.isNotEmpty)
      ? RecurrenceUnit.weeks
      : RecurrenceUnit.days;

  RecurrenceRule copyWith({
    RecurrenceFreq? freq,
    int? interval,
    List<int>? weekdays,
    List<int>? skipWeekdays,
    List<DateTime>? skipDates,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEnd = false,
    int? count,
    bool clearCount = false,
    bool? allDay,
    int? startTime,
    int? endTime,
    String? tz,
  }) =>
      RecurrenceRule(
        freq: freq ?? this.freq,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        skipWeekdays: skipWeekdays ?? this.skipWeekdays,
        skipDates: skipDates ?? this.skipDates,
        startDate: startDate ?? this.startDate,
        endDate: clearEnd ? null : (endDate ?? this.endDate),
        count: clearCount ? null : (count ?? this.count),
        allDay: allDay ?? this.allDay,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        tz: tz ?? this.tz,
      );

  /// The rule in the contract's wire shape. A daily rule sends no weekdays; [allDay] sends null times.
  Map<String, dynamic> toJson() {
    final days = unit == RecurrenceUnit.weeks ? (weekdays.toSet().toList()..sort()) : const <int>[];
    return {
      'freq': freq.name,
      'interval': interval.clamp(1, 30),
      'weekdays': days,
      'skip_weekdays': skipWeekdays.toSet().toList()..sort(),
      'skip_dates': [for (final d in ({for (final d in skipDates) recurrenceDateWire(d)}.toList()..sort())) d],
      'start_date': recurrenceDateWire(startDate),
      'end_date': endDate == null ? null : recurrenceDateWire(endDate!),
      'count': count,
      'all_day': allDay,
      'start_time': allDay || startTime == null ? null : recurrenceTimeWire(startTime!),
      'end_time': allDay || endTime == null ? null : recurrenceTimeWire(endTime!),
      'tz': tz.isEmpty ? AppTime.zoneId : tz,
    };
  }

  /// The rule from a server map; null when it has no usable freq or start date.
  static RecurrenceRule? fromJson(dynamic j) {
    if (j is! Map) return null;
    final freq = RecurrenceFreq.values.where((f) => f.name == '${j['freq']}').firstOrNull;
    final start = recurrenceDateParse(j['start_date']);
    if (freq == null || start == null) return null;
    List<int> days(dynamic v) => [
          if (v is List)
            for (final x in v)
              if (x is num && x >= 0 && x <= 6) x.toInt(),
        ]..sort();
    final skip = [
      if (j['skip_dates'] is List)
        for (final x in j['skip_dates'] as List) ?recurrenceDateParse(x),
    ]..sort();
    final allDay = j['all_day'] == true;
    final iv = j['interval'], cn = j['count'];
    return RecurrenceRule(
      freq: freq,
      interval: (iv is num ? iv.toInt() : int.tryParse('$iv') ?? 1).clamp(1, 30),
      weekdays: days(j['weekdays']),
      skipWeekdays: days(j['skip_weekdays']),
      skipDates: skip,
      startDate: start,
      endDate: recurrenceDateParse(j['end_date']),
      count: cn is num && cn > 0 ? cn.toInt() : null,
      allDay: allDay,
      startTime: allDay ? null : recurrenceTimeParse(j['start_time']),
      endTime: allDay ? null : recurrenceTimeParse(j['end_time']),
      tz: '${j['tz'] ?? ''}',
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The summary sentence
// ═════════════════════════════════════════════════════════════════════════════

const _dayEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _dayAr = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// The short name of a wire weekday (0 = Monday) in [lang].
String recurrenceDayName(int wire, [String? lang]) => ((lang ?? AppConfig.lang) == 'ar' ? _dayAr : _dayEn)[wire % 7];

/// "A, B and C" / "أ، ب وج".
String _join(List<String> items, bool ar) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  final head = items.sublist(0, items.length - 1).join(ar ? '، ' : ', ');
  return ar ? '$head و${items.last}' : '$head and ${items.last}';
}

/// In a sentence the days read Sunday first in Arabic ("الجمعة والسبت", "الأحد والثلاثاء"), Monday first in English.
List<String> _days(List<int> wire, String lang) {
  final order = lang == 'ar' ? const [6, 0, 1, 2, 3, 4, 5] : recurrenceWeekOrder(lang);
  final set = wire.toSet();
  return [for (final d in order) if (set.contains(d)) recurrenceDayName(d, lang)];
}

/// The rule in one sentence, in [lang] ('ar' / 'en'): step, skipped weekdays, time, end, skipped dates — e.g.
/// "Every day except Fri and Sat, 10:00 AM to 11:00 AM, until further notice". Times follow AppTime's 12h / 24h
/// setting unless [h24] says; dates are AppTime wall dates.
String describeRule(RecurrenceRule rule, String lang, {bool? h24}) {
  final prev = AppConfig.lang;
  AppConfig.lang = lang; // AppTime and countText read the open language; the sentence is built in [lang]
  try {
    return _describe(rule, lang == 'ar', h24);
  } finally {
    AppConfig.lang = prev;
  }
}

String _describe(RecurrenceRule r, bool ar, bool? h24) {
  final lang = ar ? 'ar' : 'en';
  final n = r.interval.clamp(1, 30);
  final parts = <String>[];

  // the step
  String step;
  if (r.unit == RecurrenceUnit.days) {
    step = countText(n,
        ar1: 'كل يوم', ar2: 'كل يومين', arFew: 'كل {n} أيام', arMany: 'كل {n} يومًا', en1: 'Every day', en: 'Every {n} days');
  } else {
    final every = countText(n,
        ar1: 'كل أسبوع', ar2: 'كل أسبوعين', arFew: 'كل {n} أسابيع', arMany: 'كل {n} أسبوعًا',
        en1: 'Every week', en: 'Every {n} weeks');
    final days = _days(r.weekdays.isEmpty ? [recurrenceWeekdayOf(r.startDate)] : r.weekdays, lang);
    step = ar ? '$every يوم ${_join(days, ar)}' : '$every on ${_join(days, ar)}';
  }
  final skipDays = _days(r.skipWeekdays, lang);
  if (skipDays.isNotEmpty) step = ar ? '$step ما عدا ${_join(skipDays, ar)}' : '$step except ${_join(skipDays, ar)}';
  parts.add(step);

  // the time
  if (r.allDay || r.startTime == null) {
    parts.add(ar ? 'في أي وقت' : 'any time');
  } else {
    final a = AppTime.clockMinutes(r.startTime!, h24: h24);
    final b = r.endTime == null ? null : AppTime.clockMinutes(r.endTime!, h24: h24);
    parts.add(b == null ? (ar ? 'الساعة $a' : 'at $a') : (ar ? 'من $a إلى $b' : '$a to $b'));
  }

  // the end
  if (r.count != null && r.count! > 0) {
    parts.add(countText(r.count!,
        ar1: 'لمرة واحدة', ar2: 'لمرتين', arFew: 'لـ{n} مرات', arMany: 'لـ{n} مرة', en1: 'once', en: '{n} times'));
  }
  if (r.endDate != null) {
    parts.add('${ar ? 'حتى' : 'until'} ${AppTime.wall(r.endDate!, pattern: 'd MMM y')}');
  } else if (r.count == null) {
    parts.add(ar ? 'حتى إشعار آخر' : 'until further notice');
  }

  // skipped dates: up to three by name, a count beyond
  final skip = {for (final d in r.skipDates) recurrenceDateWire(d): d}.values.toList()..sort();
  if (skip.isNotEmpty) {
    parts.add(skip.length <= 3
        ? '${ar ? 'عدا' : 'skips'} ${_join([for (final d in skip) AppTime.wall(d, pattern: 'd MMM')], ar)}'
        : countText(skip.length,
            ar1: 'عدا تاريخ واحد', ar2: 'عدا تاريخين', arFew: 'عدا {n} تواريخ', arMany: 'عدا {n} تاريخًا',
            en1: 'skips 1 date', en: 'skips {n} dates'));
  }
  return parts.join(ar ? '، ' : ', ');
}
