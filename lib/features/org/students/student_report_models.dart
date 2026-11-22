// lib/features/org/students/student_report_models.dart — plain parse classes and pure rules of the Students report
// (student lifecycle phase 7, contract §9). No widgets, no network.
//
//   StudentReport        GET /org/orgs/{org}/students/status-report?from=&to= — `at_to` counts, the window's
//                        movements (by dimension, by via, by decision), undone, top reasons, open recommendations,
//                        per programme and per level
//   ReportCounts         the Counts block (total · enrolment · standing · flags · attention · movements)
//   ReportGroup          one programme / level row (its label + Counts)
//   ReportKeyCount       a `{key, count, label_ar, label_en}` decision row (the label falls back to decisionLabel)
//   ReportTerm           one row of GET …/academic/terms (the period picker's "This term" / "This year")
//   ReportPeriod         the chosen window: last 30 days · this term · this year · custom → `{from, to}` (YYYY-MM-DD)
//   reportBars(…)        a Counts map → labelled, ordered, non-zero rows for a bar list
//
// Every parser is lenient: a missing key gives a default. `from` / `to` / `generated_at` are naive UTC (orgParseUtc).
library;

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr;
import '../org_v3.dart' show orgParseUtc;
import 'student_status_models.dart' show decisionLabel, anyReasonLabel, parseYmd, ymd;
import 'students_models.dart';

/// `{key: n}` with int values; anything unreadable is dropped.
Map<String, int> _counts(dynamic v) => {for (final e in asMap(v).entries) e.key: asInt(e.value)};

class ReportCounts {
  const ReportCounts({
    this.total = 0,
    this.enrolment = const {},
    this.standing = const {},
    this.flags = const {},
    this.attention = 0,
    this.movements = 0,
  });

  final int total, attention, movements;
  final Map<String, int> enrolment, standing, flags;

  factory ReportCounts.fromJson(dynamic j) {
    final m = asMap(j);
    return ReportCounts(
      total: asInt(m['total']),
      enrolment: _counts(m['enrolment']),
      standing: _counts(m['standing']),
      flags: _counts(m['flags']),
      attention: asInt(m['attention']),
      movements: asInt(m['movements']),
    );
  }

  int enrol(String status) => enrolment[status] ?? 0;

  /// Studying now (`enrolled`).
  int get studying => enrol('enrolled');

  /// Paused: suspended, postponed, suspended for discipline.
  int get paused => enrolPaused.fold(0, (a, k) => a + enrol(k));

  /// Left for good: withdrawn, cancelled, dismissed, transferred out, graduated, deceased.
  int get left => enrolFinal.fold(0, (a, k) => a + enrol(k));
}

class ReportGroup {
  const ReportGroup({this.key, this.code, this.labelAr = '', this.labelEn = '', this.counts = const ReportCounts()});

  /// The programme id / level key; null = students with none.
  final String? key;
  final String? code;
  final String labelAr, labelEn;
  final ReportCounts counts;

  bool get isNone => key == null;

  factory ReportGroup.programme(Map<String, dynamic> m) {
    final p = m['program'] is Map ? asMap(m['program']) : null;
    final id = p == null ? 0 : asInt(p['id']);
    final code = p == null ? '' : asStr(p['code']).trim();
    return ReportGroup(
      key: id > 0 ? '$id' : null,
      code: code.isEmpty ? null : code,
      labelAr: p == null ? '' : asStr(p['name_ar']).trim(),
      labelEn: p == null ? '' : asStr(p['name_en']).trim(),
      counts: ReportCounts.fromJson(m),
    );
  }

  factory ReportGroup.level(Map<String, dynamic> m) {
    final key = asStr(m['level']).trim();
    return ReportGroup(
      key: key.isEmpty ? null : key,
      labelAr: asStr(m['label_ar']).trim(),
      labelEn: asStr(m['label_en']).trim(),
      counts: ReportCounts.fromJson(m),
    );
  }

  /// The name in the app language (the other language when empty); [none] for the "no programme / level" row.
  String label(String none) {
    if (isNone) return none;
    final s = t(labelAr, labelEn).trim();
    if (s.isNotEmpty) return s;
    final o = t(labelEn, labelAr).trim();
    return o.isNotEmpty ? o : (code ?? key ?? none);
  }
}

class ReportKeyCount {
  const ReportKeyCount({required this.key, this.count = 0, this.labelAr = '', this.labelEn = ''});
  final String key;
  final int count;
  final String labelAr, labelEn;

  factory ReportKeyCount.fromJson(Map<String, dynamic> m) => ReportKeyCount(
        key: asStr(m['key']).trim(),
        count: asInt(m['count']),
        labelAr: asStr(m['label_ar']).trim(),
        labelEn: asStr(m['label_en']).trim(),
      );

  /// The server's label (it echoes the key when it has none), else the app's own decision label.
  String get label {
    final s = t(labelAr, labelEn).trim();
    if (s.isNotEmpty && s != key) return s;
    if (key.isEmpty) return t('غير محدد', 'Not stated');
    return switch (key) {
      'enrolment' => t('تغيير القيد', 'Enrolment change'),
      'standing' => t('تغيير الوضع الأكاديمي', 'Standing change'),
      'flag' => t('علامة', 'Mark'),
      _ => decisionLabel(key),
    };
  }
}

/// The ways a change happens (`by_via`), in the order the report shows them.
const reportVias = ['auto', 'manual', 'request', 'undo', 'system'];

String reportViaLabel(String via) => switch (via) {
      'auto' => t('تلقائياً بالقواعد', 'Automatically by the rules'),
      'manual' => t('يدوياً من الموظفين', 'By staff, by hand'),
      'request' => t('بطلب من الطالب', 'From a student request'),
      'undo' => t('تراجع عن قرار', 'Undone'),
      'system' => t('من النظام', 'By the system'),
      _ => via,
    };

class StudentReport {
  const StudentReport({
    this.from,
    this.to,
    this.generatedAt,
    this.atTo = const ReportCounts(),
    this.movementsTotal = 0,
    this.byDimension = const {},
    this.byVia = const {},
    this.byDecision = const [],
    this.undone = 0,
    this.topReasons = const [],
    this.pendingTotal = 0,
    this.pendingByKind = const {},
    this.pendingByDecision = const [],
    this.byProgramme = const [],
    this.byLevel = const [],
  });

  final DateTime? from, to, generatedAt;
  final ReportCounts atTo;
  final int movementsTotal, undone, pendingTotal;
  final Map<String, int> byDimension, byVia, pendingByKind;
  final List<ReportKeyCount> byDecision, pendingByDecision;

  /// `(code, count)`, most first.
  /// [label] is the server's text in the app's language ('' on an older server: [reportReasonLabel] of the code).
  final List<({String code, int count, String label})> topReasons;
  final List<ReportGroup> byProgramme, byLevel;

  factory StudentReport.fromJson(dynamic j) {
    final m = asMap(j);
    final mv = asMap(m['movements']);
    final pd = asMap(m['pending']);
    return StudentReport(
      from: orgParseUtc(m['from']),
      to: orgParseUtc(m['to']),
      generatedAt: orgParseUtc(m['generated_at']),
      atTo: ReportCounts.fromJson(m['at_to']),
      movementsTotal: asInt(mv['total']),
      byDimension: _counts(mv['by_dimension']),
      byVia: _counts(mv['by_via']),
      byDecision: [for (final r in asMapList(mv['by_decision'])) ReportKeyCount.fromJson(r)],
      undone: asInt(m['undone']),
      topReasons: [
        for (final r in asMapList(m['top_reasons']))
          if (asStr(r['code']).trim().isNotEmpty) (code: asStr(r['code']).trim(), count: asInt(r['count']), label: _bilingual(r['label_ar'], r['label_en'])),
      ],
      pendingTotal: asInt(pd['total']),
      pendingByKind: _counts(pd['by_kind']),
      pendingByDecision: [for (final r in asMapList(pd['by_decision'])) ReportKeyCount.fromJson(r)],
      byProgramme: [for (final r in asMapList(m['by_programme'])) ReportGroup.programme(r)],
      byLevel: [for (final r in asMapList(m['by_level'])) ReportGroup.level(r)],
    );
  }

  /// No students at all (the page shows its empty state).
  bool get isEmpty => atTo.total == 0 && movementsTotal == 0 && pendingTotal == 0;

  /// `by_via` in [reportVias] order with the non-zero ones only (an unknown via goes last).
  List<({String via, int count})> get vias => [
        for (final v in reportVias)
          if ((byVia[v] ?? 0) > 0) (via: v, count: byVia[v]!),
        for (final e in byVia.entries)
          if (!reportVias.contains(e.key) && e.value > 0) (via: e.key, count: e.value),
      ];
}

/// The label of a reason code (a dismissal reason or a status reason).
String reportReasonLabel(String code) => anyReasonLabel(code);

/// The server's two labels in the app's language, the other one when that is empty ('' when both are).
String _bilingual(dynamic ar, dynamic en) {
  final a = asStr(ar).trim(), e = asStr(en).trim();
  return t(a.isNotEmpty ? a : e, e.isNotEmpty ? e : a);
}

/// One labelled bar.
typedef ReportBar = ({String key, String label, int count});

/// [counts] in [order] (then any key the app does not know), labelled with [label]; zero rows dropped unless
/// [keepZero].
List<ReportBar> reportBars(Map<String, int> counts, List<String> order, String Function(String) label, {bool keepZero = false}) => [
      for (final k in order)
        if (keepZero || (counts[k] ?? 0) > 0) (key: k, label: label(k), count: counts[k] ?? 0),
      for (final e in counts.entries)
        if (!order.contains(e.key) && (keepZero || e.value > 0)) (key: e.key, label: label(e.key), count: e.value),
    ];

// ═════════════════════════════════════════════════════════════════════════════
//  The period
// ═════════════════════════════════════════════════════════════════════════════

class ReportTerm {
  const ReportTerm({required this.id, this.yearLabel = '', this.kind = '', this.labelAr = '', this.labelEn = '', this.start, this.end, this.status = ''});
  final int id;
  final String yearLabel, kind, labelAr, labelEn;
  final DateTime? start, end;

  /// `upcoming` · `current` · `finished`.
  final String status;

  factory ReportTerm.fromJson(Map<String, dynamic> m) => ReportTerm(
        id: asInt(m['id']),
        yearLabel: asStr(m['year_label']).trim(),
        kind: asStr(m['kind']).trim(),
        labelAr: asStr(m['label_ar']).trim(),
        labelEn: asStr(m['label_en']).trim(),
        start: parseYmd(m['start_date']),
        end: parseYmd(m['end_date']),
        status: asStr(m['status']).trim(),
      );

  static List<ReportTerm> listOf(dynamic j) => [
        for (final r in asMapList(asMap(j)['items']))
          if (parseYmd(r['start_date']) != null && parseYmd(r['end_date']) != null) ReportTerm.fromJson(r),
      ];

  String get label {
    final name = t(labelAr, labelEn).trim();
    return yearLabel.isEmpty ? name : '$name $yearLabel';
  }
}

enum ReportPeriodKind { days30, term, year, custom }

class ReportPeriod {
  const ReportPeriod(this.kind, this.from, this.to, {this.termLabel});
  final ReportPeriodKind kind;

  /// Calendar dates, both included.
  final DateTime from, to;

  /// The term's / year's name ("First term 2025/2026") when the period is one.
  final String? termLabel;

  Map<String, String> toQuery() => {'from': ymd(from), 'to': ymd(to)};

  @override
  bool operator ==(Object other) => other is ReportPeriod && other.kind == kind && ymd(other.from) == ymd(from) && ymd(other.to) == ymd(to);

  @override
  int get hashCode => Object.hash(kind, ymd(from), ymd(to));
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

/// The last 30 days up to [today].
ReportPeriod last30Days(DateTime today) {
  final to = _day(today);
  return ReportPeriod(ReportPeriodKind.days30, to.subtract(const Duration(days: 30)), to);
}

/// The term running on [today], else the latest one that already started; null when the organization has none.
/// The end is never after [today].
ReportPeriod? termPeriod(List<ReportTerm> terms, DateTime today) {
  final d = _day(today);
  final started = [for (final x in terms) if (!x.start!.isAfter(d)) x]..sort((a, b) => b.start!.compareTo(a.start!));
  if (started.isEmpty) return null;
  final cur = started.firstWhere((x) => !x.end!.isBefore(d), orElse: () => started.first);
  return ReportPeriod(ReportPeriodKind.term, cur.start!, _min(cur.end!, d), termLabel: cur.label);
}

/// The academic year of the term [termPeriod] picks (every term with its year label); without terms, the academic
/// year that starts on 1 September. The end is never after [today].
ReportPeriod yearPeriod(List<ReportTerm> terms, DateTime today) {
  final d = _day(today);
  final started = [for (final x in terms) if (!x.start!.isAfter(d)) x]..sort((a, b) => b.start!.compareTo(a.start!));
  if (started.isNotEmpty) {
    final cur = started.firstWhere((x) => !x.end!.isBefore(d), orElse: () => started.first);
    final same = [for (final x in terms) if (x.yearLabel == cur.yearLabel) x];
    var from = cur.start!, to = cur.end!;
    for (final x in same) {
      if (x.start!.isBefore(from)) from = x.start!;
      if (x.end!.isAfter(to)) to = x.end!;
    }
    return ReportPeriod(ReportPeriodKind.year, from, _min(to, d), termLabel: cur.yearLabel.isEmpty ? null : cur.yearLabel);
  }
  final y = d.month >= 9 ? d.year : d.year - 1;
  return ReportPeriod(ReportPeriodKind.year, DateTime(y, 9, 1), d, termLabel: '$y/${y + 1}');
}

/// A custom window: the dates in order, the end never after [today].
ReportPeriod customPeriod(DateTime a, DateTime b, DateTime today) {
  final x = _day(a), y = _day(b), d = _day(today);
  final from = x.isAfter(y) ? y : x, to = x.isAfter(y) ? x : y;
  return ReportPeriod(ReportPeriodKind.custom, _min(from, d), _min(to, d));
}

/// The name of a period kind in the picker.
String reportPeriodName(ReportPeriodKind k) => switch (k) {
      ReportPeriodKind.days30 => t('آخر 30 يوماً', 'Last 30 days'),
      ReportPeriodKind.term => t('هذا الفصل', 'This term'),
      ReportPeriodKind.year => t('هذا العام', 'This year'),
      ReportPeriodKind.custom => t('فترة أخرى', 'Custom'),
    };
