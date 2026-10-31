// lib/features/org/insights/org_insights.dart
//
// The organization dashboard's Insights (D-103, spec docs/backend/org-dashboard-spec.md §4) — the PURE part, unit-tested
// in test/org/org_insights_test.dart against real server captures (test/fixtures/payloads/org_insights*.json):
//
//   OrgInsights.fromJson     GET /api/v1/org/orgs/{id}/insights, read defensively (a missing key never throws)
//   orgInsightCards          the metrics worth a card: available WITH a value, fixed order, at most 4
//   orgInsightFigure         the big figure ("82%", "1.2K")
//   orgInsightChange         the change against the previous period in plain words ("5 points lower", "4 more")
//   orgInsightSummary        ONE sentence per metric, Arabic and English, written here from the numbers
//   orgSuggestionText        a suggestion's sentence; orgSuggestionAction its one button; orgInsightTarget its jump
//   OrgPeriodChoice          This term · Last term · Last 30 days · Custom: the query it sends, the form it is saved in
//   orgPeriodLine            "2 Oct – 31 Oct 2026 · compared with 2 Sep – 1 Oct"
//
// Wording rules (the owner's: plain language, never "delta"): a percentage changes by POINTS ("5 points lower than
// the previous term"), a count by "more" / "fewer"; a change that rounds to zero is "about the same"; without an
// earlier figure the sentence says what the figure covers instead (sessions, students enrolled now, graded share,
// the oldest waiting item). Arabic counts follow the number agreement rules (1 · 2 · 3–10 · 11+, arCount).
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

String? _str(Object? v) => v == null ? null : '$v';

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// "2026-10-31" (or a full ISO instant) → that calendar day, as a UTC date.
DateTime? orgInsightDay(Object? v) {
  if (v == null) return null;
  final s = '$v';
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

/// Where a suggestion's button goes: a section / sub-page of the org shell, or an entity (kind + id).
class OrgInsightLink {
  const OrgInsightLink({this.section = '', this.sub, this.deptId, this.kind, this.id});

  final String section;
  final String? sub;
  final int? deptId;

  /// `org_term` · `org_schedule` (or null).
  final String? kind;
  final int? id;

  factory OrgInsightLink.fromJson(Object? j) {
    final m = _map(j);
    return OrgInsightLink(
      section: _str(m['section']) ?? '',
      sub: _str(m['sub']),
      deptId: _int(m['dept_id']),
      kind: _str(m['kind']),
      id: _int(m['id']),
    );
  }
}

class OrgInsightPoint {
  const OrgInsightPoint(this.date, this.value);
  final DateTime date;

  /// null = nothing measured that day (no session took attendance).
  final double? value;
}

class OrgInsightMetric {
  const OrgInsightMetric({
    required this.key,
    this.available = false,
    this.value,
    this.unit = 'count',
    this.previous,
    this.series = const [],
    this.sessions,
    this.total,
    this.runs,
    this.coverage,
    this.parts = const {},
    this.oldestDays,
  });

  /// attendance · enrollment · completion · grades · pending.
  final String key;
  final bool available;
  final double? value;

  /// percent · count · score (a score is a mean percentage).
  final String unit;
  final double? previous;
  final List<OrgInsightPoint> series;

  /// attendance: sessions that took attendance in the window.
  final int? sessions;

  /// enrollment: active enrollments now (`value` = NEW enrollments in the window).
  final int? total;

  /// completion: finished course runs counted.
  final int? runs;

  /// grades: % of registrations graded.
  final double? coverage;

  /// pending: count per attention key.
  final Map<String, int> parts;

  /// pending: age of the oldest waiting item.
  final int? oldestDays;

  /// Drawn only when the server measured it AND has a figure (never a fake zero).
  bool get shown => available && value != null;
  bool get isPercent => unit == 'percent' || unit == 'score';

  /// Up is good for every metric but the waiting queue.
  bool get upIsGood => key != 'pending';

  /// The measured points (days without data left out), in date order.
  List<OrgInsightPoint> get points => [for (final p in series) if (p.value != null) p];

  factory OrgInsightMetric.fromJson(Map<String, dynamic> m) {
    final parts = <String, int>{};
    _map(m['parts']).forEach((k, v) {
      final n = _int(v);
      if (n != null) parts[k] = n;
    });
    return OrgInsightMetric(
      key: _str(m['key']) ?? '',
      available: m['available'] == true,
      value: _num(m['value']),
      unit: _str(m['unit']) ?? 'count',
      previous: _num(m['previous']),
      series: [
        for (final p in _maps(m['series']))
          if (orgInsightDay(p['date']) != null) OrgInsightPoint(orgInsightDay(p['date'])!, _num(p['value'])),
      ]..sort((a, b) => a.date.compareTo(b.date)),
      sessions: _int(m['sessions']),
      total: _int(m['total']),
      runs: _int(m['runs']),
      coverage: _num(m['coverage']),
      parts: parts,
      oldestDays: _int(m['oldest_days']),
    );
  }
}

class OrgInsightTerm {
  const OrgInsightTerm({required this.id, this.labelAr = '', this.labelEn = '', this.status = ''});
  final int id;
  final String labelAr, labelEn;

  /// current · finished · upcoming.
  final String status;

  String get label => _t(labelAr.isNotEmpty ? labelAr : labelEn, labelEn.isNotEmpty ? labelEn : labelAr);
}

class OrgInsightPeriod {
  const OrgInsightPeriod({
    this.termId,
    this.labelAr = '',
    this.labelEn = '',
    this.from,
    this.to,
    this.previousFrom,
    this.previousTo,
    this.granularity = 'day',
  });

  final int? termId;
  final String labelAr, labelEn;
  final DateTime? from, to, previousFrom, previousTo;

  /// day · week (the series' step).
  final String granularity;

  /// Days in the window (inclusive), 0 when unknown.
  int get days => from == null || to == null ? 0 : to!.difference(from!).inDays + 1;

  factory OrgInsightPeriod.fromJson(Object? j) {
    final m = _map(j);
    return OrgInsightPeriod(
      termId: _int(m['term_id']),
      labelAr: _str(m['label_ar']) ?? '',
      labelEn: _str(m['label_en']) ?? '',
      from: orgInsightDay(m['from']),
      to: orgInsightDay(m['to']),
      previousFrom: orgInsightDay(m['previous_from']),
      previousTo: orgInsightDay(m['previous_to']),
      granularity: _str(m['granularity']) ?? 'day',
    );
  }
}

class OrgInsightSuggestion {
  const OrgInsightSuggestion({
    required this.key,
    this.severity = 'watch',
    this.metric,
    this.value,
    this.previous,
    this.oldestDays,
    this.termId,
    this.link = const OrgInsightLink(),
  });

  /// attendance_drop · low_completion · pending_backlog · grades_missing · unplaced_sessions · …
  final String key;

  /// risk · watch.
  final String severity;
  final String? metric;
  final double? value, previous;
  final int? oldestDays, termId;
  final OrgInsightLink link;

  bool get isRisk => severity == 'risk';

  factory OrgInsightSuggestion.fromJson(Map<String, dynamic> m) => OrgInsightSuggestion(
        key: _str(m['key']) ?? '',
        severity: _str(m['severity']) ?? 'watch',
        metric: _str(m['metric']),
        value: _num(m['value']),
        previous: _num(m['previous']),
        oldestDays: _int(m['oldest_days']),
        termId: _int(m['term_id']),
        link: OrgInsightLink.fromJson(m['link']),
      );
}

class OrgInsights {
  const OrgInsights({
    this.period = const OrgInsightPeriod(),
    this.orgWide = true,
    this.deptIds = const [],
    this.terms = const [],
    this.metrics = const [],
    this.suggestions = const [],
    this.generatedAt,
  });

  final OrgInsightPeriod period;

  /// false = the figures cover only [deptIds] (a department-scoped viewer).
  final bool orgWide;
  final List<int> deptIds;

  /// The organization's terms, newest first (the server's order).
  final List<OrgInsightTerm> terms;
  final List<OrgInsightMetric> metrics;
  final List<OrgInsightSuggestion> suggestions;
  final DateTime? generatedAt;

  OrgInsightMetric? metric(String key) {
    for (final m in metrics) {
      if (m.key == key) return m;
    }
    return null;
  }

  OrgInsightTerm? term(int? id) {
    if (id == null) return null;
    for (final x in terms) {
      if (x.id == id) return x;
    }
    return null;
  }

  factory OrgInsights.fromJson(Object? j) {
    final m = _map(j);
    final scope = _map(m['scope']);
    return OrgInsights(
      period: OrgInsightPeriod.fromJson(m['period']),
      orgWide: scope['org_wide'] != false,
      deptIds: [for (final x in (scope['dept_ids'] is List ? scope['dept_ids'] as List : const [])) ?_int(x)],
      terms: [
        for (final x in _maps(m['terms']))
          if (_int(x['id']) != null)
            OrgInsightTerm(
              id: _int(x['id'])!,
              labelAr: _str(x['label_ar']) ?? '',
              labelEn: _str(x['label_en']) ?? '',
              status: _str(x['status']) ?? '',
            ),
      ],
      metrics: [for (final x in _maps(m['metrics'])) OrgInsightMetric.fromJson(x)],
      suggestions: [
        for (final x in _maps(m['suggestions']))
          if ((_str(x['key']) ?? '').isNotEmpty) OrgInsightSuggestion.fromJson(x),
      ]..sort((a, b) => (a.isRisk ? 0 : 1).compareTo(b.isRisk ? 0 : 1)),
      generatedAt: DateTime.tryParse(_str(m['generated_at']) ?? ''),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Which cards, which figures
// ═════════════════════════════════════════════════════════════════════════════

/// The card order; the first four that have a figure are drawn.
const orgInsightOrder = ['attendance', 'enrollment', 'completion', 'grades', 'pending'];
const orgInsightMaxCards = 4;

List<OrgInsightMetric> orgInsightCards(OrgInsights d) {
  final out = <OrgInsightMetric>[];
  for (final k in orgInsightOrder) {
    final m = d.metric(k);
    if (m != null && m.shown) out.add(m);
    if (out.length == orgInsightMaxCards) break;
  }
  return out;
}

String orgInsightLabel(String key) => switch (key) {
      'attendance' => _t('الحضور', 'Attendance'),
      'enrollment' => _t('التسجيلات الجديدة', 'New enrollments'),
      'completion' => _t('نسبة النجاح', 'Pass rate'),
      'grades' => _t('متوسط الدرجات', 'Average grade'),
      'pending' => _t('بانتظار القرار', 'Waiting for a decision'),
      _ => key,
    };

/// 82.4 → "82" · 7.25 → "7.3" · 1284 → "1.3K".
String orgInsightNumber(double v, {bool percent = false}) {
  final a = v.abs();
  if (!percent && a >= 1000) {
    final (x, s) = a >= 1e6 ? (a / 1e6, 'M') : (a / 1e3, 'K');
    final txt = x >= 10 ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
    return '${v < 0 ? '-' : ''}${txt.endsWith('.0') ? txt.substring(0, txt.length - 2) : txt}$s';
  }
  if (a >= 10 || v == v.roundToDouble()) return v.round().toString();
  final txt = v.toStringAsFixed(1);
  return txt.endsWith('.0') ? txt.substring(0, txt.length - 2) : txt;
}

/// The card's big figure.
String orgInsightFigure(OrgInsightMetric m) {
  final v = m.value;
  if (v == null) return '—';
  return m.isPercent ? '${orgInsightNumber(v, percent: true)}%' : orgInsightNumber(v);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Arabic number agreement
// ═════════════════════════════════════════════════════════════════════════════

/// [n] with its noun: 1 → [one] · 2 → [two] · 3–10 → "n [few]" · 11+ → "n [many]" (101 → many, 103 → few).
String arCount(int n, {required String one, required String two, required String few, required String many}) {
  if (n == 1) return one;
  if (n == 2) return two;
  final r = n % 100;
  if (r >= 3 && r <= 10) return '$n $few';
  return '$n $many';
}

/// "منذ يوم" · "منذ يومين" · "منذ 5 أيام" · "منذ 12 يومًا".
String arSinceDays(int n) => n == 1
    ? 'منذ يوم'
    : n == 2
        ? 'منذ يومين'
        : 'منذ ${arCount(n, one: '', two: '', few: 'أيام', many: 'يومًا')}';

String _enPlural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

// ═════════════════════════════════════════════════════════════════════════════
//  Change and summary sentences
// ═════════════════════════════════════════════════════════════════════════════

/// What the figures are compared with: "the previous term" · "the previous 30 days" · "the previous period".
String orgInsightCompared(OrgInsightPeriod p) {
  if (p.termId != null) return _t('الفصل السابق', 'the previous term');
  final n = p.days;
  if (n == 1) return _t('اليوم السابق', 'the day before');
  if (n == 2) return _t('اليومين السابقين', 'the previous 2 days');
  if (n > 2 && n <= 120) return _t('الأيام الـ$n السابقة', 'the previous $n days');
  return _t('الفترة السابقة', 'the previous period');
}

/// The change against the previous period. [direction]: 1 up · -1 down · 0 about the same. [good]: null when the
/// direction says nothing (no change).
class OrgInsightChange {
  const OrgInsightChange({required this.amount, required this.direction, required this.text, required this.short, this.good});

  /// Points for a percentage, items for a count (absolute, rounded).
  final int amount;
  final int direction;

  /// "5 points lower" · "4 more" · "About the same" (no comparison noun: the caller adds it).
  final String text;

  /// The card's pill next to its arrow: "5 points" · "4" · "Same".
  final String short;
  final bool? good;
}

OrgInsightChange? orgInsightChange(OrgInsightMetric m) {
  final v = m.value, p = m.previous;
  if (v == null || p == null) return null;
  final diff = (v - p).round();
  final n = diff.abs();
  final dir = diff == 0 ? 0 : (diff > 0 ? 1 : -1);
  final good = dir == 0 ? null : ((dir > 0) == m.upIsGood);
  if (dir == 0) {
    return OrgInsightChange(amount: 0, direction: 0, text: _t('كما هي تقريبًا', 'About the same'), short: _t('ثابت', 'Same'));
  }
  final String text, short;
  if (m.isPercent) {
    final ar = n == 1 ? 'بنقطة واحدة' : (n == 2 ? 'بنقطتين' : 'بـ${arCount(n, one: '', two: '', few: 'نقاط', many: 'نقطة')}');
    text = _t('${dir > 0 ? 'أعلى' : 'أقل'} $ar', '${_enPlural(n, 'point', 'points')} ${dir > 0 ? 'higher' : 'lower'}');
    short = _t(arCount(n, one: 'نقطة واحدة', two: 'نقطتان', few: 'نقاط', many: 'نقطة'), _enPlural(n, 'point', 'points'));
  } else {
    text = _t('${dir > 0 ? 'أكثر' : 'أقل'} بـ$n', '$n ${dir > 0 ? 'more' : 'fewer'}');
    short = '$n';
  }
  return OrgInsightChange(amount: n, direction: dir, text: text, short: short, good: good);
}

/// "5 points lower than the previous term" · "about the same as the previous 30 days" — or null without a previous.
String? orgInsightChangeSentence(OrgInsightMetric m, OrgInsightPeriod p) {
  final c = orgInsightChange(m);
  if (c == null) return null;
  final vs = orgInsightCompared(p);
  if (c.direction == 0) return _t('كما كانت تقريبًا في $vs', 'about the same as $vs');
  return _t('${c.text} من $vs', '${c.text} than $vs');
}

/// ONE plain sentence for a metric card (ends with a full stop).
String orgInsightSummary(OrgInsightMetric m, OrgInsightPeriod p) {
  final v = m.value ?? 0;
  final fig = orgInsightFigure(m);
  final change = orgInsightChangeSentence(m, p);
  switch (m.key) {
    case 'attendance':
      if (change != null) return _t('نسبة الحضور $fig، $change.', 'Attendance is $fig, $change.');
      final s = m.sessions ?? 0;
      if (s > 0) {
        return _t('نسبة الحضور $fig في ${arCount(s, one: 'جلسة واحدة', two: 'جلستين', few: 'جلسات', many: 'جلسة')}.',
            'Attendance is $fig across ${_enPlural(s, 'session', 'sessions')}.');
      }
      return _t('نسبة الحضور $fig في هذه الفترة.', 'Attendance is $fig in this period.');
    case 'enrollment':
      final n = v.round();
      final total = m.total;
      final now = total == null ? null : _t('المسجّلون الآن: $total', '$total ${total == 1 ? 'student is' : 'students are'} enrolled now');
      if (n == 0 && change == null) {
        return _t('لا تسجيلات جديدة في هذه الفترة${now == null ? '' : '؛ $now'}.',
            'No new enrollments in this period${now == null ? '' : '; $now'}.');
      }
      final head = _t('التسجيلات الجديدة: $fig', n == 1 ? '1 new enrollment' : '$fig new enrollments');
      if (change != null) return '$head${_t('، ', ', ')}$change.';
      return '$head${now == null ? '' : '; $now'}.';
    case 'completion':
      if (change != null) return _t('نسبة النجاح $fig، $change.', '$fig of students passed, $change.');
      final r = m.runs ?? 0;
      if (r > 0) {
        return _t('نسبة النجاح $fig (المقررات المنتهية: $r).',
            '$fig of students passed, across ${_enPlural(r, 'finished course', 'finished courses')}.');
      }
      return _t('نسبة النجاح $fig.', '$fig of students passed.');
    case 'grades':
      if (change != null) return _t('متوسط الدرجات $fig، $change.', 'The average grade is $fig, $change.');
      final cov = m.coverage;
      if (cov != null && cov < 99.5) {
        final c = '${orgInsightNumber(cov, percent: true)}%';
        return _t('متوسط الدرجات $fig؛ رُصد $c من الدرجات حتى الآن.', 'The average grade is $fig; $c of grades are in so far.');
      }
      return _t('متوسط الدرجات $fig.', 'The average grade is $fig.');
    case 'pending':
      final n = v.round();
      if (n == 0) return _t('لا شيء ينتظر قرارًا الآن.', 'Nothing is waiting for a decision.');
      final age = m.oldestDays ?? 0;
      final head = _t('بانتظار القرار: $n', n == 1 ? '1 item is waiting for a decision' : '$n items are waiting for a decision');
      if (age >= 1) {
        return '$head${_t('، أقدمها ${arSinceDays(age)}', '; the oldest for ${_enPlural(age, 'day', 'days')}')}.';
      }
      return '$head.';
    default:
      return change == null ? '${orgInsightLabel(m.key)}: $fig.' : '${orgInsightLabel(m.key)}: $fig${_t('، ', ', ')}$change.';
  }
}

/// A point for the touch read-out: ("Mon 12 Oct", "78%") · ("Week of 12 Oct", "3"). The figure is drawn left to
/// right on its own ("78%" after an Arabic date too, like the card's big figure).
(String, String) orgInsightPointParts(OrgInsightPoint pt, OrgInsightMetric m, {String granularity = 'day'}) {
  final v = pt.value;
  final fig = v == null ? '—' : (m.isPercent ? '${orgInsightNumber(v, percent: true)}%' : orgInsightNumber(v));
  final noon = DateTime.utc(pt.date.year, pt.date.month, pt.date.day, 12);
  final day = granularity == 'week'
      ? _t('أسبوع ${AppTime.date(noon, pattern: 'd MMM')}', 'Week of ${AppTime.date(noon, pattern: 'd MMM')}')
      : AppTime.date(noon, pattern: 'EEE d MMM');
  return (day, fig);
}

/// The same as one line: "Mon 12 Oct · 78%".
String orgInsightPointLabel(OrgInsightPoint pt, OrgInsightMetric m, {String granularity = 'day'}) {
  final (day, fig) = orgInsightPointParts(pt, m, granularity: granularity);
  return '$day · $fig';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Suggestions
// ═════════════════════════════════════════════════════════════════════════════

String _pct(double? v) => v == null ? '' : '${orgInsightNumber(v, percent: true)}%';

/// The suggestion's sentence, written from its key and numbers.
String orgSuggestionText(OrgInsightSuggestion s, OrgInsights d) {
  final n = (s.value ?? 0).round();
  switch (s.key) {
    case 'attendance_drop':
      final prev = s.previous;
      if (prev != null && s.value != null && prev > s.value!) {
        return _t('انخفض الحضور إلى ${_pct(s.value)} بعد أن كان ${_pct(prev)} — راجع المقررات التي يغيب طلابها.',
            'Attendance fell to ${_pct(s.value)} from ${_pct(prev)} — see which courses are losing students.');
      }
      return _t('نسبة الحضور ${_pct(s.value)} فقط — راجع المقررات التي يغيب طلابها.',
          'Attendance is only ${_pct(s.value)} — see which courses are losing students.');
    case 'low_completion':
      return _t('نسبة النجاح ${_pct(s.value)} فقط — راجع المقررات الأضعف نتيجة.',
          'Only ${_pct(s.value)} of students passed — look at the courses with the weakest results.');
    case 'pending_backlog':
      final age = s.oldestDays ?? 0;
      return _t(
          'عدد ما ينتظر قرارك: $n${age >= 1 ? '، أقدمه ${arSinceDays(age)}' : ''}.',
          '${n == 1 ? '1 item is' : '$n items are'} waiting for a decision${age >= 1 ? ', the oldest for ${_enPlural(age, 'day', 'days')}' : ''}.');
    case 'grades_missing':
      final term = d.term(s.termId ?? s.link.id)?.label;
      final ar = arCount(n, one: 'مقرر واحد', two: 'مقررين', few: 'مقررات', many: 'مقررًا');
      return term == null
          ? _t('لم تُرصد درجات $ar بعد انتهاء الفصل.', 'Grades are still missing for ${_enPlural(n, 'course', 'courses')} after the term ended.')
          : _t('لم تُرصد درجات $ar في $term.', 'Grades are still missing for ${_enPlural(n, 'course', 'courses')} in $term.');
    case 'unplaced_sessions':
      return _t('${arCount(n, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة')} بلا مكان في الجدول بعد.',
          '${n == 1 ? '1 session still has' : '$n sessions still have'} no place in the timetable.');
    default:
      return _t('هناك ما يحتاج مراجعتك هنا.', 'Something here needs a look.');
  }
}

/// The suggestion's one button.
String orgSuggestionAction(OrgInsightSuggestion s) {
  switch (s.key) {
    case 'attendance_drop':
    case 'low_completion':
      return _t('راجع المقررات', 'Review courses');
    case 'grades_missing':
      return _t('تابع الدرجات', 'Follow up grades');
    case 'unplaced_sessions':
      return _t('افتح الجدول', 'Open timetable');
    case 'pending_backlog':
      return switch (s.link.sub) {
        'join_requests' || 'unit_requests' || 'forms' || 'program_choices' => _t('راجع الطلبات', 'Review requests'),
        'complaints' => _t('افتح الشكاوى', 'Open complaints'),
        'governance' => _t('افتح المعاملات', 'Open items'),
        'votes' => _t('صوّت الآن', 'Vote now'),
        _ => _t('راجعها الآن', 'Review now'),
      };
    default:
      return _t('افتح', 'Open');
  }
}

/// A link → the org shell's (section, sub) for OrgTabs.go / orgJump; null when it names nothing to open.
/// `org_schedule` + id opens that timetable (`('timetable', 'open:ID')`, the Timetable section's deep-link form).
(String, String?)? orgInsightTarget(OrgInsightLink l) {
  if (l.kind == 'org_schedule' && l.id != null) return ('timetable', 'open:${l.id}');
  if (l.section.isEmpty) return null;
  return (l.section, l.sub);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Period choice
// ═════════════════════════════════════════════════════════════════════════════

enum OrgPeriodKind { thisTerm, lastTerm, last30, custom }

String orgPeriodKindLabel(OrgPeriodKind k) => switch (k) {
      OrgPeriodKind.thisTerm => _t('هذا الفصل', 'This term'),
      OrgPeriodKind.lastTerm => _t('الفصل الماضي', 'Last term'),
      OrgPeriodKind.last30 => _t('آخر 30 يومًا', 'Last 30 days'),
      OrgPeriodKind.custom => _t('فترة مخصصة', 'Custom'),
    };

/// The running term (status `current`).
OrgInsightTerm? orgCurrentTerm(List<OrgInsightTerm> terms) {
  for (final x in terms) {
    if (x.status == 'current') return x;
  }
  return null;
}

/// The latest finished term (the server lists terms newest first).
OrgInsightTerm? orgLastTerm(List<OrgInsightTerm> terms) {
  for (final x in terms) {
    if (x.status == 'finished') return x;
  }
  return null;
}

/// The chips the terms allow: This term only with a running term, Last term only with a finished one.
List<OrgPeriodKind> orgPeriodKinds(List<OrgInsightTerm> terms) => [
      if (orgCurrentTerm(terms) != null) OrgPeriodKind.thisTerm,
      if (orgLastTerm(terms) != null) OrgPeriodKind.lastTerm,
      OrgPeriodKind.last30,
      OrgPeriodKind.custom,
    ];

/// The longest custom range the server accepts (422 range_too_long beyond).
const orgInsightMaxRangeDays = 731;

class OrgPeriodChoice {
  const OrgPeriodChoice(this.kind, {this.from, this.to});

  final OrgPeriodKind kind;

  /// Custom only (calendar days).
  final DateTime? from, to;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The query of GET …/insights; null when the choice cannot be sent with these terms (a saved "This term" while
  /// no term runs) — the caller then asks for the server's default.
  Map<String, String>? query(List<OrgInsightTerm> terms, DateTime today) {
    switch (kind) {
      case OrgPeriodKind.thisTerm:
        final x = orgCurrentTerm(terms);
        return x == null ? null : {'term_id': '${x.id}'};
      case OrgPeriodKind.lastTerm:
        final x = orgLastTerm(terms);
        return x == null ? null : {'term_id': '${x.id}'};
      case OrgPeriodKind.last30:
        final end = DateTime.utc(today.year, today.month, today.day);
        return {'date_from': _iso(end.subtract(const Duration(days: 29))), 'date_to': _iso(end)};
      case OrgPeriodKind.custom:
        if (from == null || to == null) return null;
        return {'date_from': _iso(from!), 'date_to': _iso(to!)};
    }
  }

  /// The saved form (one per organization on the device).
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (from != null) 'from': _iso(from!),
        if (to != null) 'to': _iso(to!),
      };

  static OrgPeriodChoice? fromJson(Object? j) {
    final m = _map(j);
    OrgPeriodKind? kind;
    for (final k in OrgPeriodKind.values) {
      if (k.name == m['kind']) kind = k;
    }
    if (kind == null) return null;
    final from = orgInsightDay(m['from']), to = orgInsightDay(m['to']);
    if (kind == OrgPeriodKind.custom && (from == null || to == null || from.isAfter(to))) return null;
    return OrgPeriodChoice(kind, from: from, to: to);
  }

  @override
  bool operator ==(Object other) =>
      other is OrgPeriodChoice && other.kind == kind && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);
}

/// The selected chip for an answer: what was asked, else what the server's default turned out to be.
OrgPeriodKind? orgPeriodKindOf(OrgInsights d, OrgPeriodChoice? asked) {
  if (asked != null) return asked.kind;
  final id = d.period.termId;
  if (id == null) return OrgPeriodKind.last30;
  if (orgCurrentTerm(d.terms)?.id == id) return OrgPeriodKind.thisTerm;
  if (orgLastTerm(d.terms)?.id == id) return OrgPeriodKind.lastTerm;
  return null;
}

String _span(DateTime a, DateTime b) {
  DateTime noon(DateTime d) => DateTime.utc(d.year, d.month, d.day, 12);
  final sameYear = a.year == b.year;
  final left = AppTime.date(noon(a), pattern: sameYear ? 'd MMM' : 'd MMM y');
  final right = AppTime.date(noon(b), pattern: 'd MMM y');
  return '$left – $right';
}

/// "2 Oct – 31 Oct 2026" — a range of calendar days.
String orgRangeLabel(DateTime from, DateTime to) => _span(from, to);

/// The line under the chips: "2 Oct – 31 Oct 2026 · compared with 2 Sep – 1 Oct 2026".
String orgPeriodLine(OrgInsightPeriod p) {
  if (p.from == null || p.to == null) return '';
  final now = _span(p.from!, p.to!);
  if (p.previousFrom == null || p.previousTo == null) return now;
  return '$now · ${_t('مقارنةً بـ', 'compared with')} ${_span(p.previousFrom!, p.previousTo!)}';
}
