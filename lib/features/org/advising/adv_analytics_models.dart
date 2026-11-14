// lib/features/org/advising/adv_analytics_models.dart — pure models of the Academic Advising analytics (Phase 8,
// docs/advising/PHASE8.md): the director dashboard (options, overview and its sections), the advisors table, the
// drill-down's metric, the compliance report, the data health check, the analytics runs, group outreach (audience,
// preview, the sent message, its recipients, the student's own messages) and the status keys of the phase. No
// Flutter widgets: unit-tested in test/org/adv_analytics_models_test.dart.
//
// Every parser is tolerant of missing keys (an older server leaves a block out). A student count the server hides
// (the aggregate tier's small-group suppression, 1–4 students) arrives as `null` and stays `null` here — the screens
// write "fewer than 5", never 0. A rate or an average over fewer than 5 students is `null` for every tier.
library;

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t;
import 'adv_models.dart' show AdvNamed, AdvRef, advPriorities, advPriorityLabel;

// ═════════════════════════════════════════════════════════════════════════════
//  Small parsers
// ═════════════════════════════════════════════════════════════════════════════

/// The fewest students a figure may describe; below it the server answers `null`.
const advMinGroup = 5;

/// A count that may be hidden: a key present with `null` → null (fewer than 5); missing → 0 (an older server).
int? advCount(Map<String, dynamic> j, String key) {
  if (j.containsKey(key) && j[key] == null) return null;
  return asInt(j[key]);
}

/// A number that may be absent (`null` → null).
double? advNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

String? _str(dynamic v) {
  final s = asStr(v).trim();
  return s.isEmpty || s == 'null' ? null : s;
}

DateTime? _instant(dynamic v) {
  final s = asStr(v).trim();
  if (s.isEmpty || s == 'null') return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// A local date `YYYY-MM-DD` (the organization's calendar day) as a date-only value.
DateTime? advLocalDate(dynamic v) {
  final s = asStr(v).trim();
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// A date-only value as the server reads it: `YYYY-MM-DD`.
String advDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, int> _ints(dynamic v) => {for (final e in asMap(v).entries) e.key: asInt(e.value)};

/// Counts that may be hidden, key by key.
Map<String, int?> _counts(dynamic v) {
  final m = asMap(v);
  return {for (final k in m.keys) k: advCount(m, k)};
}

/// The change of [value] against [previous] in percent; null when either is unknown or [previous] is 0.
double? advDelta(num? value, num? previous) {
  if (value == null || previous == null || previous == 0) return null;
  return (value - previous) / previous.abs() * 100;
}

/// "4.2" · "12" · "" (null) — one decimal under 10, whole above.
String advFigure(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.round().toString();
  return d.abs() < 10 ? d.toStringAsFixed(1) : d.round().toString();
}

/// "83%" · "" (null).
String advRate(num? v) => v == null ? '' : '${advFigure(v)}%';

/// "4.2 h" / "4.2 س" · "" (null).
String advHours(num? v) => v == null ? '' : t('${advFigure(v)} س', '${advFigure(v)} h');

/// "3.5 d" / "3.5 ي" · "" (null).
String advDays(num? v) => v == null ? '' : t('${advFigure(v)} ي', '${advFigure(v)} d');

// ═════════════════════════════════════════════════════════════════════════════
//  Shared objects: Term, Range, Filters
// ═════════════════════════════════════════════════════════════════════════════

/// `Term = {"id","label","kind","start","end"}` (+ `current` in the options).
class AdvTerm {
  const AdvTerm({required this.id, this.label = '', this.kind = '', this.start, this.end, this.current = false});

  final int id;

  /// The academic year label (`2025/2026`).
  final String label;

  /// `term1` · `term2` · `summer`.
  final String kind;
  final DateTime? start, end;
  final bool current;

  static AdvTerm? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    final id = asInt(j['id']);
    if (id == 0) return null;
    return AdvTerm(
      id: id,
      label: asStr(j['label']).trim(),
      kind: asStr(j['kind']).trim(),
      start: advLocalDate(j['start']),
      end: advLocalDate(j['end']),
      current: asBool(j['current']),
    );
  }

  String get kindLabel => switch (kind) {
        'term1' => t('الفصل الأول', 'First term'),
        'term2' => t('الفصل الثاني', 'Second term'),
        'summer' => t('الفصل الصيفي', 'Summer term'),
        _ => kind,
      };

  /// "First term 2025/2026".
  String get title => [if (kindLabel.isNotEmpty) kindLabel, if (label.isNotEmpty) label].join(' ');

  /// A short label for a chart axis: "T1 25/26" · "ف1 25/26".
  String get short {
    final k = switch (kind) {
      'term1' => t('ف1', 'T1'),
      'term2' => t('ف2', 'T2'),
      'summer' => t('صيفي', 'Sum'),
      _ => kind,
    };
    final y = RegExp(r'(\d{2})(\d{2})\s*/\s*\d{2}(\d{2})').firstMatch(label);
    final year = y == null ? label : '${y.group(2)}/${y.group(3)}';
    return [if (k.isNotEmpty) k, if (year.isNotEmpty) year].join(' ');
  }
}

/// `Range = {"from","to","days","term","interval"}`.
class AdvRange {
  const AdvRange({this.from, this.to, this.days = 0, this.term, this.interval = 'week'});

  final DateTime? from, to;
  final int days;
  final AdvTerm? term;

  /// The series bucket: `day` · `week` · `month`.
  final String interval;

  factory AdvRange.fromJson(Map<String, dynamic> j) {
    final iv = asStr(j['interval']);
    return AdvRange(
      from: advLocalDate(j['from']),
      to: advLocalDate(j['to']),
      days: asInt(j['days']),
      term: AdvTerm.maybe(j['term']),
      interval: const ['day', 'week', 'month'].contains(iv) ? iv : 'week',
    );
  }
}

/// The dashboard's filters — the range (dates, or a term, or nothing = the current term) and who: program, level,
/// cohort, the students' current primary advisor. One sheet edits them; every analytics route and dataset reads them.
class AdvAnalyticsFilter {
  const AdvAnalyticsFilter({this.from, this.to, this.termId, this.programId, this.level, this.cohort, this.advisor});

  /// Local dates (inclusive); both or neither.
  final DateTime? from, to;

  /// A term instead of dates.
  final int? termId;
  final int? programId;
  final String? level, cohort;

  /// The students' current primary advisor.
  final AdvRef? advisor;

  AdvAnalyticsFilter copyWith({
    DateTime? Function()? from,
    DateTime? Function()? to,
    int? Function()? termId,
    int? Function()? programId,
    String? Function()? level,
    String? Function()? cohort,
    AdvRef? Function()? advisor,
  }) =>
      AdvAnalyticsFilter(
        from: from == null ? this.from : from(),
        to: to == null ? this.to : to(),
        termId: termId == null ? this.termId : termId(),
        programId: programId == null ? this.programId : programId(),
        level: level == null ? this.level : level(),
        cohort: cohort == null ? this.cohort : cohort(),
        advisor: advisor == null ? this.advisor : advisor(),
      );

  /// The range: dates (the term cleared).
  AdvAnalyticsFilter withDates(DateTime from, DateTime to) => copyWith(from: () => from, to: () => to, termId: () => null);

  /// The range: a term (null = the current term; the dates cleared).
  AdvAnalyticsFilter withTerm(int? termId) => copyWith(from: () => null, to: () => null, termId: () => termId);

  /// Who the figures are about stays; the range goes back to the current term.
  AdvAnalyticsFilter get defaultRange => withTerm(null);

  /// Program · level · cohort · advisor (a student filter: the snapshot series and satisfaction are off then).
  bool get hasStudentFilter => programId != null || level != null || cohort != null || advisor != null;

  /// A range other than the current term is chosen.
  bool get hasRange => termId != null || from != null || to != null;

  /// How many filters are on (the range counts as one).
  int get activeFilters => [programId, level, cohort, advisor].where((v) => v != null).length + (hasRange ? 1 : 0);

  /// Why the dates cannot be used (the server's `advising_bad_range` rules), null when they can.
  String? get rangeError {
    final f = from, e = to;
    if (f == null && e == null) return null;
    if (f == null || e == null) return t('اختر تاريخ البداية والنهاية', 'Choose both the start and the end date');
    if (f.isAfter(e)) return t('تاريخ البداية بعد تاريخ النهاية', 'The start date is after the end date');
    if (e.difference(f).inDays + 1 > 400) return t('المدة أطول من 400 يوم — اختر مدة أقصر', 'The range is longer than 400 days — choose a shorter one');
    return null;
  }

  /// The query string of every analytics route.
  Map<String, dynamic> toQuery() => {
        if (from != null) 'from': advDay(from!),
        if (to != null) 'to': advDay(to!),
        'term_id': ?termId,
        'program_id': ?programId,
        'level': ?level,
        'cohort': ?cohort,
        'advisor_user_id': ?advisor?.userId,
      };

  @override
  bool operator ==(Object other) =>
      other is AdvAnalyticsFilter &&
      other.from == from &&
      other.to == to &&
      other.termId == termId &&
      other.programId == programId &&
      other.level == level &&
      other.cohort == cohort &&
      other.advisor?.userId == advisor?.userId;

  @override
  int get hashCode => Object.hash(from, to, termId, programId, level, cohort, advisor?.userId);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Options
// ═════════════════════════════════════════════════════════════════════════════

/// A category as the analytics answer it (the aggregate tier folds the sensitive ones into `key: "sensitive"`).
class AdvAnCategory {
  const AdvAnCategory({this.id, this.key = '', this.nameAr = '', this.nameEn = '', this.sensitive = false});

  /// null for the folded sensitive row.
  final int? id;
  final String key, nameAr, nameEn;
  final bool sensitive;

  factory AdvAnCategory.fromJson(Map<String, dynamic> j) => AdvAnCategory(
        id: j['id'] == null ? null : asInt(j['id']),
        key: asStr(j['key']).trim(),
        nameAr: asStr(j['name_ar']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        sensitive: asBool(j['sensitive']),
      );

  /// The folded row of the aggregate tier.
  bool get folded => key == 'sensitive' && id == null;

  String get name {
    if (folded && nameAr.isEmpty && nameEn.isEmpty) return t('تصنيفات حساسة', 'Sensitive categories');
    final s = t(nameAr, nameEn);
    return s.isNotEmpty ? s : (nameAr.isNotEmpty ? nameAr : (nameEn.isNotEmpty ? nameEn : key));
  }
}

/// A band of the GPA distribution: `b0`–`b5` · `none`, from / to on the organization's scale.
class AdvGpaBand {
  const AdvGpaBand({required this.key, this.from, this.to, this.students = 0});
  final String key;
  final double? from, to;

  /// null = fewer than 5 (aggregate tier).
  final int? students;

  factory AdvGpaBand.fromJson(Map<String, dynamic> j) =>
      AdvGpaBand(key: asStr(j['key']), from: advNum(j['from']), to: advNum(j['to']), students: advCount(j, 'students'));

  /// "2.50 – 3.00" · "No CGPA yet".
  String get label {
    if (key == 'none' || (from == null && to == null)) return t('بلا معدل بعد', 'No CGPA yet');
    String f(double? v) => v == null ? '' : v.toStringAsFixed(2);
    return '${f(from)} – ${f(to)}';
  }

  /// The short axis label: "2.5" (the band's lower edge) · "—".
  String get short {
    if (key == 'none' || from == null) return '—';
    return advFigure(from);
  }
}

/// A drill-down metric the server knows (`GET /analytics/options` `metrics`).
class AdvMetricInfo {
  const AdvMetricInfo({required this.key, this.labelAr = '', this.labelEn = '', this.needsKey = false, this.needsTerm = false});
  final String key, labelAr, labelEn;
  final bool needsKey, needsTerm;

  factory AdvMetricInfo.fromJson(Map<String, dynamic> j) => AdvMetricInfo(
        key: asStr(j['key']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        needsKey: asBool(j['needs_key']),
        needsTerm: asBool(j['needs_term']),
      );

  String get label {
    final s = t(labelAr, labelEn);
    return s.isNotEmpty ? s : advMetricLabel(key);
  }
}

/// `GET /analytics/options`.
class AdvAnalyticsOptions {
  const AdvAnalyticsOptions({
    this.terms = const [],
    this.programs = const [],
    this.levels = const [],
    this.cohorts = const [],
    this.advisors = const [],
    this.categories = const [],
    this.gpaBands = const [],
    this.probationBelow,
    this.scaleMax = 4,
    this.metrics = const [],
    this.tier,
  });

  /// The newest 12, `current` marked.
  final List<AdvTerm> terms;
  final List<AdvNamed> programs;
  final List<String> levels, cohorts;

  /// Manage only (empty for the aggregate tier).
  final List<AdvRef> advisors;
  final List<AdvAnCategory> categories;
  final List<AdvGpaBand> gpaBands;
  final double? probationBelow;
  final double scaleMax;
  final List<AdvMetricInfo> metrics;

  /// `manage` · `aggregate` (null: an older server).
  final String? tier;

  factory AdvAnalyticsOptions.fromJson(Map<String, dynamic> j) => AdvAnalyticsOptions(
        terms: [for (final m in asMapList(j['terms'])) ?AdvTerm.maybe(m)],
        programs: [for (final m in asMapList(j['programs'])) AdvNamed.fromJson(m)],
        levels: [for (final v in (j['levels'] as List? ?? const [])) if (v != null && '$v'.isNotEmpty) '$v'],
        cohorts: [for (final v in (j['cohorts'] as List? ?? const [])) if (v != null && '$v'.isNotEmpty) '$v'],
        advisors: [for (final m in asMapList(j['advisors'])) ?AdvRef.maybe(m)],
        categories: [for (final m in asMapList(j['categories'])) AdvAnCategory.fromJson(m)],
        gpaBands: [for (final m in asMapList(j['gpa_bands'])) AdvGpaBand.fromJson(m)],
        probationBelow: advNum(j['probation_below']),
        scaleMax: advNum(j['scale_max']) ?? 4,
        metrics: [for (final m in asMapList(j['metrics'])) AdvMetricInfo.fromJson(m)],
        tier: _str(j['tier']),
      );

  bool get manage => tier == 'manage';

  AdvTerm? get currentTerm => terms.where((x) => x.current).firstOrNull;

  AdvTerm? term(int? id) => id == null ? null : terms.where((x) => x.id == id).firstOrNull;

  String? programName(int? id) => id == null ? null : programs.where((p) => p.id == id).firstOrNull?.name;

  /// The label of a drill metric: the server's, else the app's.
  String metricLabel(String key) => metrics.where((m) => m.key == key).firstOrNull?.label ?? advMetricLabel(key);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

/// The drill metrics (PHASE8 `GET /analytics/students`).
String advMetricLabel(String key) => switch (key) {
      'all' => t('كل الطلاب', 'All students'),
      'unassigned' => t('بلا مرشد', 'Without an advisor'),
      'advisor_away' => t('مرشدهم غائب', 'Advisor away'),
      'advisor' => t('طلاب مرشد', 'An advisor\'s students'),
      'risk_band' => t('مستوى الخطر', 'Risk level'),
      'priority' => t('أعلى تنبيه مفتوح', 'Highest open alert'),
      'category' => t('تصنيف التنبيه', 'Alert category'),
      'gpa_band' => t('شريحة المعدل', 'CGPA band'),
      'no_contact' => t('بلا تواصل هذا الفصل', 'No contact this term'),
      'met' => t('حضروا لقاءً', 'Had a meeting'),
      'no_show' => t('تغيبوا عن لقاء', 'Missed a meeting'),
      'booked' => t('لهم لقاء قادم', 'Have a meeting booked'),
      'alerted' => t('صدر لهم تنبيه', 'Got an alert'),
      'complaint' => t('قدّموا شكوى', 'Opened a complaint'),
      'awaiting_reply' => t('ينتظرون رداً', 'Waiting for a reply'),
      'request_stage' => t('طلبات في مرحلة', 'Requests at a stage'),
      'graduation' => t('التخرج', 'Graduation'),
      'supported' => t('تلقّوا دعماً', 'Supported'),
      'not_supported' => t('لم يتلقوا دعماً', 'Not supported'),
      'at_risk_supported' => t('معرّضون للخطر وتلقّوا دعماً', 'At risk, supported'),
      'at_risk_not_supported' => t('معرّضون للخطر بلا دعم', 'At risk, not supported'),
      'not_retained' => t('لم يستمروا', 'Not retained'),
      'unowned_flag' => t('تنبيهات بلا مسؤول', 'Alerts without an owner'),
      'stuck_request' => t('طلبات متوقفة', 'Stuck requests'),
      'stale_stats' => t('بيانات قديمة', 'Out-of-date figures'),
      'missing_program' => t('بلا برنامج', 'Without a program'),
      'outreach' => t('مستلمو رسالة', 'Message recipients'),
      _ => key,
    };

const advRiskBandKeys = ['high', 'medium', 'low', 'none'];

/// Risk bands of PHASE8 (`high` ≥ 60 · `medium` 30–59 · `low` 1–29 · `none` 0).
String advRiskBandName(String key) => switch (key) {
      'high' => t('خطر مرتفع', 'High risk'),
      'medium' => t('خطر متوسط', 'Medium risk'),
      'low' => t('خطر منخفض', 'Low risk'),
      'none' => t('بلا خطر', 'No risk'),
      _ => key,
    };

const advLoadBuckets = ['empty', 'under_50', '50_79', '80_99', 'full', 'over'];

String advLoadBucketLabel(String key) => switch (key) {
      'empty' => t('بلا طلاب', 'No students'),
      'under_50' => t('أقل من 50%', 'Under 50%'),
      '50_79' => '50–79%',
      '80_99' => '80–99%',
      'full' => t('مكتمل', 'Full'),
      'over' => t('فوق الحد', 'Over the maximum'),
      _ => key,
    };

const advRequestStages = ['submitted', 'needs_info', 'in_review', 'at_department_council', 'at_faculty_council'];

String advRequestStageLabel(String key) => switch (key) {
      'submitted' => t('مُرسلة', 'Submitted'),
      'needs_info' => t('تنتظر معلومات', 'Needs information'),
      'in_review' => t('قيد المراجعة', 'In review'),
      'at_department_council' => t('مجلس القسم', 'Department council'),
      'at_faculty_council' => t('مجلس الكلية', 'Faculty council'),
      'approved' => t('مقبولة', 'Approved'),
      'rejected' => t('مرفوضة', 'Rejected'),
      'withdrawn' => t('مسحوبة', 'Withdrawn'),
      'closed' => t('مغلقة', 'Closed'),
      'handled' => t('عولجت', 'Handled'),
      'declined' => t('اعتُذر عنها', 'Declined'),
      _ => key,
    };

/// Response-time buckets.
const advResponseBuckets = ['lt_1h', 'h1_4', 'h4_24', 'd1_3', 'gt_3d'];

String advResponseBucketLabel(String key) => switch (key) {
      'lt_1h' => t('أقل من ساعة', 'Under 1 h'),
      'h1_4' => t('1–4 ساعات', '1–4 h'),
      'h4_24' => t('4–24 ساعة', '4–24 h'),
      'd1_3' => t('1–3 أيام', '1–3 days'),
      'gt_3d' => t('أكثر من 3 أيام', 'Over 3 days'),
      _ => key,
    };

const advMeetingModes = ['in_person', 'video', 'phone', 'chat'];

// ═════════════════════════════════════════════════════════════════════════════
//  Overview
// ═════════════════════════════════════════════════════════════════════════════

/// One KPI: its value in the range and in the same-length range before it.
class AdvKpi {
  const AdvKpi({this.value, this.previous});
  final double? value, previous;

  factory AdvKpi.fromJson(dynamic v) {
    if (v is num) return AdvKpi(value: v.toDouble());
    final j = asMap(v);
    return AdvKpi(value: advNum(j['value']), previous: advNum(j['previous']));
  }

  double? get delta => advDelta(value, previous);
}

/// The eight KPIs of the top row, in order.
const advKpiKeys = ['students', 'unassigned', 'at_risk', 'meetings_completed', 'no_show_rate', 'avg_response_hours', 'alerts', 'complaints_open'];

String advKpiLabel(String key) => switch (key) {
      'students' => t('الطلاب', 'Students'),
      'unassigned' => t('بلا مرشد', 'Without an advisor'),
      'at_risk' => t('معرّضون للخطر', 'At risk'),
      'meetings_completed' => t('لقاءات تمت', 'Meetings held'),
      'no_show_rate' => t('نسبة الغياب عن اللقاءات', 'No-show rate'),
      'avg_response_hours' => t('متوسط زمن الرد', 'Average reply time'),
      'alerts' => t('تنبيهات صدرت', 'Alerts raised'),
      'complaints_open' => t('شكاوى مفتوحة', 'Open complaints'),
      _ => key,
    };

/// A higher value is good news for [key] (the delta's colour).
bool advKpiUpIsGood(String key) => key == 'students' || key == 'meetings_completed';

/// The KPI's figure as shown ("" = unknown).
String advKpiValue(String key, double? v) => switch (key) {
      'no_show_rate' => advRate(v),
      'avg_response_hours' => advHours(v),
      _ => v == null ? '' : advFigure(v),
    };

class AdvViewer {
  const AdvViewer({this.tier = 'manage', this.drill = true, this.minGroup = advMinGroup});
  final String tier;
  final bool drill;
  final int minGroup;

  factory AdvViewer.fromJson(Map<String, dynamic> j) {
    final tier = asStr(j['tier']);
    return AdvViewer(
      tier: tier.isEmpty ? 'manage' : tier,
      drill: j.containsKey('drill') ? asBool(j['drill']) : tier != 'aggregate',
      minGroup: asInt(j['min_group'], advMinGroup),
    );
  }

  bool get aggregate => tier == 'aggregate';
}

class AdvStudentsSection {
  const AdvStudentsSection({this.total = 0, this.assigned = 0, this.unassigned = 0, this.advisorAway = 0, this.noContactTerm, this.graduated = 0});
  final int total, assigned, unassigned, advisorAway, graduated;
  final int? noContactTerm;

  factory AdvStudentsSection.fromJson(Map<String, dynamic> j) => AdvStudentsSection(
        total: asInt(j['total']),
        assigned: asInt(j['assigned']),
        unassigned: asInt(j['unassigned']),
        advisorAway: asInt(j['advisor_away']),
        noContactTerm: advCount(j, 'no_contact_term'),
        graduated: asInt(j['graduated']),
      );
}

class AdvLoadTop {
  const AdvLoadTop({required this.userId, this.name = '', this.load = 0, this.maxLoad = 0, this.loadPct, this.warn = false, this.over = false});
  final int userId, load, maxLoad;
  final String name;
  final double? loadPct;
  final bool warn, over;

  factory AdvLoadTop.fromJson(Map<String, dynamic> j) => AdvLoadTop(
        userId: asInt(j['user_id']),
        name: asStr(j['name']).trim(),
        load: asInt(j['load']),
        maxLoad: asInt(j['max_load']),
        loadPct: advNum(j['load_pct']),
        warn: asBool(j['warn']),
        over: asBool(j['over']),
      );

  String get shown => name.isEmpty ? '#$userId' : name;
}

class AdvLoadSection {
  const AdvLoadSection({
    this.advisors = 0,
    this.activeAdvisors = 0,
    this.avg,
    this.max = 0,
    this.over = 0,
    this.warn = 0,
    this.capacityLeft = 0,
    this.distribution = const {},
    this.top = const [],
  });

  final int advisors, activeAdvisors, max, over, warn, capacityLeft;
  final double? avg;

  /// Bucket key → advisors (in [advLoadBuckets] order when shown).
  final Map<String, int> distribution;
  final List<AdvLoadTop> top;

  factory AdvLoadSection.fromJson(Map<String, dynamic> j) => AdvLoadSection(
        advisors: asInt(j['advisors']),
        activeAdvisors: asInt(j['active_advisors']),
        avg: advNum(j['avg']),
        max: asInt(j['max']),
        over: asInt(j['over']),
        warn: asInt(j['warn']),
        capacityLeft: asInt(j['capacity_left']),
        distribution: {for (final m in asMapList(j['distribution'])) asStr(m['key']): asInt(m['advisors'])},
        top: [for (final m in asMapList(j['top'])) AdvLoadTop.fromJson(m)],
      );
}

class AdvCategoryStat {
  const AdvCategoryStat({required this.category, this.students = 0, this.flags = 0, this.byPriority = const {}});
  final AdvAnCategory category;
  final int? students, flags;
  final Map<String, int?> byPriority;

  factory AdvCategoryStat.fromJson(Map<String, dynamic> j) => AdvCategoryStat(
        category: AdvAnCategory.fromJson(asMap(j['category'])),
        students: advCount(j, 'students'),
        flags: advCount(j, 'flags'),
        byPriority: _counts(j['by_priority']),
      );
}

class AdvStrugglingSection {
  const AdvStrugglingSection({this.riskBands = const {}, this.byPriority = const {}, this.byCategory = const []});

  /// `high` · `medium` · `low` · `none` → students (null = fewer than 5).
  final Map<String, int?> riskBands;

  /// Students by their highest open alert.
  final Map<String, int?> byPriority;
  final List<AdvCategoryStat> byCategory;

  factory AdvStrugglingSection.fromJson(Map<String, dynamic> j) => AdvStrugglingSection(
        riskBands: _counts(j['risk_bands']),
        byPriority: _counts(j['by_priority']),
        byCategory: [for (final m in asMapList(j['by_category'])) AdvCategoryStat.fromJson(m)],
      );

  /// At risk = high + medium; null when either part is hidden.
  int? get atRisk {
    final h = riskBands['high'], m = riskBands['medium'];
    if (!riskBands.containsKey('high') && !riskBands.containsKey('medium')) return 0;
    return h == null || m == null ? null : h + m;
  }
}

class AdvRiskPoint {
  const AdvRiskPoint({this.date, this.atRisk, this.high, this.avgScore, this.alerts = 0, this.opened = 0, this.resolved = 0});
  final DateTime? date;
  final int? atRisk, high;
  final double? avgScore;
  final int alerts, opened, resolved;

  factory AdvRiskPoint.fromJson(Map<String, dynamic> j) => AdvRiskPoint(
        date: advLocalDate(j['date']),
        atRisk: j['at_risk'] == null ? null : asInt(j['at_risk']),
        high: j['high'] == null ? null : asInt(j['high']),
        avgScore: advNum(j['avg_score']),
        alerts: asInt(j['alerts']),
        opened: asInt(j['opened']),
        resolved: asInt(j['resolved']),
      );
}

class AdvGpaTermPoint {
  const AdvGpaTermPoint({this.term, this.students = 0, this.avgTermGpa, this.belowLine});
  final AdvTerm? term;
  final int students;
  final double? avgTermGpa;
  final int? belowLine;

  factory AdvGpaTermPoint.fromJson(Map<String, dynamic> j) =>
      AdvGpaTermPoint(term: AdvTerm.maybe(j['term']), students: asInt(j['students']), avgTermGpa: advNum(j['avg_term_gpa']), belowLine: advCount(j, 'below_line'));
}

class AdvGpaSection {
  const AdvGpaSection({this.scaleMax = 4, this.probationBelow, this.avgCgpa, this.noGpa, this.distribution = const [], this.trend = const []});
  final double scaleMax;
  final double? probationBelow, avgCgpa;
  final int? noGpa;
  final List<AdvGpaBand> distribution;

  /// ≤ 8 terms, oldest first.
  final List<AdvGpaTermPoint> trend;

  factory AdvGpaSection.fromJson(Map<String, dynamic> j) => AdvGpaSection(
        scaleMax: advNum(j['scale_max']) ?? 4,
        probationBelow: advNum(j['probation_below']),
        avgCgpa: advNum(j['avg_cgpa']),
        noGpa: advCount(j, 'no_gpa'),
        distribution: [for (final m in asMapList(j['distribution'])) AdvGpaBand.fromJson(m)],
        trend: [for (final m in asMapList(j['trend'])) AdvGpaTermPoint.fromJson(m)],
      );
}

/// One bucket of a dated series: its date and named counts.
class AdvSeriesPoint {
  const AdvSeriesPoint({this.date, this.values = const {}, this.avgHours});
  final DateTime? date;
  final Map<String, int> values;

  /// The response series' average (null = no reply, or fewer than 5).
  final double? avgHours;

  factory AdvSeriesPoint.fromJson(Map<String, dynamic> j) => AdvSeriesPoint(
        date: advLocalDate(j['date']),
        values: {
          for (final e in j.entries)
            if (e.key != 'date' && e.key != 'avg_hours' && e.value is num) e.key: asInt(e.value),
        },
        avgHours: advNum(j['avg_hours']),
      );

  int of(String key) => values[key] ?? 0;
}

class AdvMeetingsSection {
  const AdvMeetingsSection({
    this.booked = 0,
    this.completed = 0,
    this.noShow = 0,
    this.cancelled = 0,
    this.lateCancelled = 0,
    this.upcoming = 0,
    this.studentsMet,
    this.completionRate,
    this.noShowRate,
    this.byMode = const {},
    this.points = const [],
  });

  final int booked, completed, noShow, cancelled, lateCancelled, upcoming;
  final int? studentsMet;
  final double? completionRate, noShowRate;
  final Map<String, int> byMode;
  final List<AdvSeriesPoint> points;

  factory AdvMeetingsSection.fromJson(Map<String, dynamic> j) => AdvMeetingsSection(
        booked: asInt(j['booked']),
        completed: asInt(j['completed']),
        noShow: asInt(j['no_show']),
        cancelled: asInt(j['cancelled']),
        lateCancelled: asInt(j['late_cancelled']),
        upcoming: asInt(j['upcoming']),
        studentsMet: advCount(j, 'students_met'),
        completionRate: advNum(j['completion_rate']),
        noShowRate: advNum(j['no_show_rate']),
        byMode: _ints(j['by_mode']),
        points: [for (final m in asMapList(j['points'])) AdvSeriesPoint.fromJson(m)],
      );

  int get total => completed + noShow + cancelled;
}

class AdvResponseSection {
  const AdvResponseSection({this.replies = 0, this.avgHours, this.slaMetPct, this.awaitingReply = 0, this.buckets = const {}, this.points = const []});
  final int replies, awaitingReply;
  final double? avgHours, slaMetPct;
  final Map<String, int> buckets;
  final List<AdvSeriesPoint> points;

  factory AdvResponseSection.fromJson(Map<String, dynamic> j) => AdvResponseSection(
        replies: asInt(j['replies']),
        avgHours: advNum(j['avg_hours']),
        slaMetPct: advNum(j['sla_met_pct']),
        awaitingReply: asInt(j['awaiting_reply']),
        buckets: _ints(j['buckets']),
        points: [for (final m in asMapList(j['points'])) AdvSeriesPoint.fromJson(m)],
      );
}

class AdvComplaintsSection {
  const AdvComplaintsSection({this.opened = 0, this.closed = 0, this.openNow = 0, this.escalated = 0, this.aboutAdvisor = 0, this.avgResolutionHours, this.points = const []});
  final int opened, closed, openNow, escalated, aboutAdvisor;
  final double? avgResolutionHours;
  final List<AdvSeriesPoint> points;

  factory AdvComplaintsSection.fromJson(Map<String, dynamic> j) => AdvComplaintsSection(
        opened: asInt(j['opened']),
        closed: asInt(j['closed']),
        openNow: asInt(j['open_now']),
        escalated: asInt(j['escalated']),
        aboutAdvisor: asInt(j['about_advisor']),
        avgResolutionHours: advNum(j['avg_resolution_hours']),
        points: [for (final m in asMapList(j['points'])) AdvSeriesPoint.fromJson(m)],
      );
}

class AdvRequestType {
  const AdvRequestType({required this.supportType, this.labelAr = '', this.labelEn = '', this.count = 0});
  final String supportType, labelAr, labelEn;
  final int count;

  factory AdvRequestType.fromJson(Map<String, dynamic> j) => AdvRequestType(
        supportType: asStr(j['support_type']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        count: asInt(j['count']),
      );

  String get label {
    final s = t(labelAr, labelEn);
    return s.isNotEmpty ? s : supportType;
  }
}

class AdvRequestsSection {
  const AdvRequestsSection({
    this.open = const {},
    this.referralsOpen = 0,
    this.overdue = 0,
    this.decided = const {},
    this.referralsDecided = const {},
    this.approvalRate,
    this.avgDecisionDays,
    this.byType = const [],
  });

  /// Stage → open requests.
  final Map<String, int> open;
  final int referralsOpen, overdue;
  final Map<String, int> decided, referralsDecided;
  final double? approvalRate, avgDecisionDays;
  final List<AdvRequestType> byType;

  factory AdvRequestsSection.fromJson(Map<String, dynamic> j) => AdvRequestsSection(
        open: _ints(j['open']),
        referralsOpen: asInt(j['referrals_open']),
        overdue: asInt(j['overdue']),
        decided: _ints(j['decided']),
        referralsDecided: _ints(j['referrals_decided']),
        approvalRate: advNum(j['approval_rate']),
        avgDecisionDays: advNum(j['avg_decision_days']),
        byType: [for (final m in asMapList(j['by_type'])) AdvRequestType.fromJson(m)],
      );

  int get openTotal => open.values.fold(0, (a, b) => a + b);
  int get decidedTotal => decided.values.fold(0, (a, b) => a + b);
}

class AdvActivitySection {
  const AdvActivitySection({this.windowDays = 14, this.advisors = 0, this.active = 0, this.inactive = 0, this.actions = const {}});
  final int windowDays, advisors, active, inactive;

  /// `meetings` · `replies` · `notes` · `alerts_resolved`.
  final Map<String, int> actions;

  factory AdvActivitySection.fromJson(Map<String, dynamic> j) => AdvActivitySection(
        windowDays: asInt(j['window_days'], 14),
        advisors: asInt(j['advisors']),
        active: asInt(j['active']),
        inactive: asInt(j['inactive']),
        actions: _ints(j['actions']),
      );
}

/// An average over a group (`{"n","avg"}`; `avg` null under 5).
class AdvGroupAvg {
  const AdvGroupAvg({this.n = 0, this.avg});
  final int n;
  final double? avg;
  factory AdvGroupAvg.fromJson(dynamic v) {
    final j = asMap(v);
    return AdvGroupAvg(n: asInt(j['n']), avg: advNum(j['avg']));
  }
}

/// Retention of a group (`{"n","retained","rate"}`).
class AdvRetention {
  const AdvRetention({this.n = 0, this.retained, this.rate});
  final int n;
  final int? retained;
  final double? rate;
  factory AdvRetention.fromJson(dynamic v) {
    final j = asMap(v);
    return AdvRetention(n: asInt(j['n']), retained: advCount(j, 'retained'), rate: advNum(j['rate']));
  }
}

/// Student success outcomes of a term (#10).
class AdvOutcomes {
  const AdvOutcomes({
    this.term,
    this.asOf,
    this.enrolled = 0,
    this.supported,
    this.atRisk,
    this.atRiskSupported,
    this.meetingsHeld = 0,
    this.alertsResolved = 0,
    this.plansCompleted = 0,
    this.plansMet = 0,
    this.gpaChange = const {},
    this.retention = const {},
  });

  final AdvTerm? term;

  /// When the term rows were computed (null before the first daily run).
  final DateTime? asOf;
  final int enrolled, meetingsHeld, alertsResolved, plansCompleted, plansMet;
  final int? supported, atRisk, atRiskSupported;

  /// `supported` · `not_supported` · `at_risk_supported` · `at_risk_not_supported`.
  final Map<String, AdvGroupAvg> gpaChange;

  /// `all` · `supported` · `at_risk_supported` · `at_risk_not_supported`.
  final Map<String, AdvRetention> retention;

  factory AdvOutcomes.fromJson(Map<String, dynamic> j) => AdvOutcomes(
        term: AdvTerm.maybe(j['term']),
        asOf: _instant(j['as_of']),
        enrolled: asInt(j['enrolled']),
        supported: advCount(j, 'supported'),
        atRisk: advCount(j, 'at_risk'),
        atRiskSupported: advCount(j, 'at_risk_supported'),
        meetingsHeld: asInt(j['meetings_held']),
        alertsResolved: asInt(j['alerts_resolved']),
        plansCompleted: asInt(j['plans_completed']),
        plansMet: asInt(j['plans_met']),
        gpaChange: {for (final e in asMap(j['gpa_change']).entries) e.key: AdvGroupAvg.fromJson(e.value)},
        retention: {for (final e in asMap(j['retention']).entries) e.key: AdvRetention.fromJson(e.value)},
      );

  /// No daily run has covered a term yet.
  bool get pending => asOf == null;
}

/// The outcome groups, in order (drill metrics of the same name).
const advOutcomeGroups = ['supported', 'not_supported', 'at_risk_supported', 'at_risk_not_supported'];

class AdvSatisfaction {
  const AdvSatisfaction({this.count = 0, this.average, this.hidden = false});
  final int count;
  final double? average;

  /// Fewer than 5 answers: the average is not shown.
  final bool hidden;

  static AdvSatisfaction? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return AdvSatisfaction(count: asInt(j['count']), average: advNum(j['average']), hidden: asBool(j['hidden']));
  }
}

/// The overview's health line (manage only).
class AdvHealthSummary {
  const AdvHealthSummary({this.checkedAt, this.issues = 0, this.critical = 0});
  final DateTime? checkedAt;
  final int issues, critical;

  static AdvHealthSummary? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return AdvHealthSummary(checkedAt: _instant(j['checked_at']), issues: asInt(j['issues']), critical: asInt(j['critical']));
  }
}

/// `GET /analytics/overview`.
class AdvOverview {
  const AdvOverview({
    this.generatedAt,
    this.computedAt,
    this.range = const AdvRange(),
    this.viewer = const AdvViewer(),
    this.stateSeries = true,
    this.kpis = const {},
    this.students = const AdvStudentsSection(),
    this.load = const AdvLoadSection(),
    this.struggling = const AdvStrugglingSection(),
    this.riskTrend = const [],
    this.gpa = const AdvGpaSection(),
    this.meetings = const AdvMeetingsSection(),
    this.response = const AdvResponseSection(),
    this.complaints = const AdvComplaintsSection(),
    this.requests = const AdvRequestsSection(),
    this.activity = const AdvActivitySection(),
    this.outcomes = const AdvOutcomes(),
    this.satisfaction,
    this.health,
  });

  final DateTime? generatedAt;

  /// When the figures were computed: the default view is a copy the server refreshes every 10 minutes, so this can
  /// be minutes old. null from an older server (then [generatedAt]).
  final DateTime? computedAt;
  final AdvRange range;
  final AdvViewer viewer;

  /// false when a student filter is on: the snapshot series (at risk over time) is off.
  final bool stateSeries;
  final Map<String, AdvKpi> kpis;
  final AdvStudentsSection students;
  final AdvLoadSection load;
  final AdvStrugglingSection struggling;
  final List<AdvRiskPoint> riskTrend;
  final AdvGpaSection gpa;
  final AdvMeetingsSection meetings;
  final AdvResponseSection response;
  final AdvComplaintsSection complaints;
  final AdvRequestsSection requests;
  final AdvActivitySection activity;
  final AdvOutcomes outcomes;

  /// null with a student filter (cannot honour it) or from an older server.
  final AdvSatisfaction? satisfaction;

  /// Manage only.
  final AdvHealthSummary? health;

  factory AdvOverview.fromJson(Map<String, dynamic> j) => AdvOverview(
        generatedAt: _instant(j['generated_at']),
        computedAt: _instant(j['computed_at']),
        range: AdvRange.fromJson(asMap(j['range'])),
        viewer: AdvViewer.fromJson(asMap(j['viewer'])),
        stateSeries: j.containsKey('state_series') ? asBool(j['state_series']) : true,
        kpis: {for (final e in asMap(j['kpis']).entries) e.key: AdvKpi.fromJson(e.value)},
        students: AdvStudentsSection.fromJson(asMap(j['students'])),
        load: AdvLoadSection.fromJson(asMap(j['load'])),
        struggling: AdvStrugglingSection.fromJson(asMap(j['struggling'])),
        riskTrend: [for (final m in asMapList(asMap(j['risk_trend'])['points'])) AdvRiskPoint.fromJson(m)],
        gpa: AdvGpaSection.fromJson(asMap(j['gpa'])),
        meetings: AdvMeetingsSection.fromJson(asMap(j['meetings'])),
        response: AdvResponseSection.fromJson(asMap(j['response'])),
        complaints: AdvComplaintsSection.fromJson(asMap(j['complaints'])),
        requests: AdvRequestsSection.fromJson(asMap(j['requests'])),
        activity: AdvActivitySection.fromJson(asMap(j['activity'])),
        outcomes: AdvOutcomes.fromJson(asMap(j['outcomes'])),
        satisfaction: AdvSatisfaction.maybe(j['satisfaction']),
        health: AdvHealthSummary.maybe(j['health']),
      );

  AdvKpi kpi(String key) => kpis[key] ?? const AdvKpi();

  /// What "Updated …" shows.
  DateTime? get updatedAt => computedAt ?? generatedAt;

  /// Nobody to describe yet (no student in the scope).
  bool get empty => students.total == 0 && (kpi('students').value ?? 0) == 0;
}

/// A date of a series bucket as a short axis label: a day / week start "3 Nov", a month "Nov".
String advBucketLabel(DateTime? d, String interval) {
  if (d == null) return '';
  const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const ar = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  final m = t(ar[d.month - 1], en[d.month - 1]);
  return interval == 'month' ? m : '${d.day} $m';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Advisors table
// ═════════════════════════════════════════════════════════════════════════════

const advAdvisorStatSorts = ['load', 'name', 'risk', 'no_contact', 'meetings', 'response', 'activity'];

String advAdvisorStatSortLabel(String s) => switch (s) {
      'name' => t('الاسم', 'Name'),
      'risk' => t('الأكثر طلاباً في خطر', 'Most students at risk'),
      'no_contact' => t('الأكثر بلا تواصل', 'Most without contact'),
      'meetings' => t('الأكثر لقاءات', 'Most meetings'),
      'response' => t('الأبطأ رداً', 'Slowest replies'),
      'activity' => t('الأقل نشاطاً', 'Least active'),
      _ => t('الأعلى حملاً', 'Highest load'),
    };

/// One advisor's row (`GET /analytics/advisors`).
class AdvAdvisorStat {
  const AdvAdvisorStat({
    required this.userId,
    this.name = '',
    this.status = 'available',
    this.away = false,
    this.load = 0,
    this.maxLoad = 0,
    this.loadPct,
    this.warn = false,
    this.over = false,
    this.atRisk = 0,
    this.highRisk = 0,
    this.noContactTerm = 0,
    this.meetingsCompleted = 0,
    this.noShow = 0,
    this.cancelled = 0,
    this.noShowRate,
    this.replies = 0,
    this.avgResponseHours,
    this.slaMetPct,
    this.notes = 0,
    this.alertsResolved = 0,
    this.lastActiveAt,
    this.active = false,
    this.satisfaction,
  });

  final int userId;
  final String name, status;
  final bool away, warn, over, active;
  final int load, maxLoad;
  final double? loadPct;

  /// Their current primary advisees (null = fewer than 5, aggregate tier).
  final int? atRisk, highRisk, noContactTerm;
  final int meetingsCompleted, noShow, cancelled, replies, notes, alertsResolved;
  final double? noShowRate, avgResponseHours, slaMetPct;
  final DateTime? lastActiveAt;
  final AdvSatisfaction? satisfaction;

  factory AdvAdvisorStat.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['students']);
    final m = asMap(j['meetings']);
    return AdvAdvisorStat(
      userId: asInt(j['user_id']),
      name: asStr(j['name']).trim(),
      status: asStr(j['status'], 'available'),
      away: asBool(j['away']),
      load: asInt(j['load']),
      maxLoad: asInt(j['max_load']),
      loadPct: advNum(j['load_pct']),
      warn: asBool(j['warn']),
      over: asBool(j['over']),
      atRisk: advCount(s, 'at_risk'),
      highRisk: advCount(s, 'high_risk'),
      noContactTerm: advCount(s, 'no_contact_term'),
      meetingsCompleted: asInt(m['completed']),
      noShow: asInt(m['no_show']),
      cancelled: asInt(m['cancelled']),
      noShowRate: advNum(m['no_show_rate']),
      replies: asInt(j['replies']),
      avgResponseHours: advNum(j['avg_response_hours']),
      slaMetPct: advNum(j['sla_met_pct']),
      notes: asInt(j['notes']),
      alertsResolved: asInt(j['alerts_resolved']),
      lastActiveAt: _instant(j['last_active_at']),
      active: asBool(j['active']),
      satisfaction: AdvSatisfaction.maybe(j['satisfaction']),
    );
  }

  String get shown => name.isEmpty ? '#$userId' : name;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Drill-down
// ═════════════════════════════════════════════════════════════════════════════

/// What a drill list shows: a metric, the value it needs (a band, a category id, an advisor id …) and, for an
/// outreach, the recipients' state.
class AdvDrill {
  const AdvDrill({required this.metric, this.key, this.state, this.label});
  final String metric;
  final String? key, state;

  /// The screen's title when the caller knows a better one ("High risk", "Dr. Huda's students").
  final String? label;

  Map<String, dynamic> toQuery() => {'metric': metric, 'key': ?key, 'state': ?state};

  @override
  bool operator ==(Object other) => other is AdvDrill && other.metric == metric && other.key == key && other.state == state;

  @override
  int get hashCode => Object.hash(metric, key, state);
}

/// The `metric` block of a drill page: `{"key","value","label_ar","label_en"}`.
class AdvDrillMetric {
  const AdvDrillMetric({this.key = '', this.value, this.labelAr = '', this.labelEn = ''});
  final String key;
  final String? value;
  final String labelAr, labelEn;

  factory AdvDrillMetric.fromJson(Map<String, dynamic> j) =>
      AdvDrillMetric(key: asStr(j['key']), value: _str(j['value']), labelAr: asStr(j['label_ar']).trim(), labelEn: asStr(j['label_en']).trim());

  String? get label {
    final s = t(labelAr, labelEn);
    return s.isEmpty ? null : s;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Compliance (#25)
// ═════════════════════════════════════════════════════════════════════════════

class AdvComplianceRow {
  const AdvComplianceRow({
    this.userId,
    this.name = '',
    this.advisees = 0,
    this.contacted = 0,
    this.coveragePct,
    this.contacts = 0,
    this.contactsPerStudent,
    this.meetingsCompleted = 0,
    this.noShows = 0,
    this.noShowRate,
    this.alerts = 0,
    this.alertsResolved = 0,
    this.avgResolutionDays,
    this.avgFirstContactDays,
    this.replies = 0,
    this.avgResponseHours,
    this.atRisk = 0,
    this.atRiskContacted = 0,
    this.supportedGpaChange,
    this.retainedPct,
    this.meetsTarget,
  });

  /// null = the organization's total row.
  final int? userId;
  final String name;

  /// Student counts (null = fewer than 5, aggregate tier).
  final int? advisees, contacted, atRisk, atRiskContacted;
  final int contacts, meetingsCompleted, noShows, alerts, alertsResolved, replies;
  final double? coveragePct, contactsPerStudent, noShowRate, avgResolutionDays, avgFirstContactDays, avgResponseHours, supportedGpaChange, retainedPct;

  /// null = cannot be judged (hidden figures, no advisees).
  final bool? meetsTarget;

  factory AdvComplianceRow.fromJson(Map<String, dynamic> j) => AdvComplianceRow(
        userId: j['user_id'] == null ? null : asInt(j['user_id']),
        name: asStr(j['name']).trim(),
        advisees: advCount(j, 'advisees'),
        contacted: advCount(j, 'contacted'),
        coveragePct: advNum(j['coverage_pct']),
        contacts: asInt(j['contacts']),
        contactsPerStudent: advNum(j['contacts_per_student']),
        meetingsCompleted: asInt(j['meetings_completed']),
        noShows: asInt(j['no_shows']),
        noShowRate: advNum(j['no_show_rate']),
        alerts: asInt(j['alerts']),
        alertsResolved: asInt(j['alerts_resolved']),
        avgResolutionDays: advNum(j['avg_resolution_days']),
        avgFirstContactDays: advNum(j['avg_first_contact_days']),
        replies: asInt(j['replies']),
        avgResponseHours: advNum(j['avg_response_hours']),
        atRisk: advCount(j, 'at_risk'),
        atRiskContacted: advCount(j, 'at_risk_contacted'),
        supportedGpaChange: advNum(j['supported_gpa_change']),
        retainedPct: advNum(j['retained_pct']),
        meetsTarget: j['meets_target'] is bool ? j['meets_target'] as bool : null,
      );

  bool get total => userId == null;

  String get shown => total ? t('المؤسسة كلها', 'Whole organization') : (name.isEmpty ? '#$userId' : name);
}

/// `GET /analytics/compliance`.
class AdvCompliance {
  const AdvCompliance({this.term, this.asOf, this.pending = false, this.targetCoveragePct = 80, this.targetMinContacts = 1, this.total, this.advisors = const []});
  final AdvTerm? term;
  final DateTime? asOf;

  /// No daily run has covered the term yet.
  final bool pending;
  final double targetCoveragePct;
  final double targetMinContacts;
  final AdvComplianceRow? total;
  final List<AdvComplianceRow> advisors;

  factory AdvCompliance.fromJson(Map<String, dynamic> j) {
    final tg = asMap(j['targets']);
    final total = j['total'];
    return AdvCompliance(
      term: AdvTerm.maybe(j['term']),
      asOf: _instant(j['as_of']),
      pending: asBool(j['pending']),
      targetCoveragePct: advNum(tg['coverage_pct']) ?? 80,
      targetMinContacts: advNum(tg['min_contacts']) ?? 1,
      total: total is Map ? AdvComplianceRow.fromJson(asMap(total)) : null,
      advisors: [for (final m in asMapList(j['advisors'])) AdvComplianceRow.fromJson(m)],
    );
  }

  int get meeting => advisors.where((a) => a.meetsTarget == true).length;
  int get missing => advisors.where((a) => a.meetsTarget == false).length;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Health check (#26)
// ═════════════════════════════════════════════════════════════════════════════

const advSeverities = ['critical', 'warning', 'info', 'ok'];

/// critical 3 · warning 2 · info 1 · ok 0.
int advSeverityRank(String s) => switch (s) {
      'critical' => 3,
      'warning' => 2,
      'info' => 1,
      _ => 0,
    };

String advSeverityLabel(String s) => switch (s) {
      'critical' => t('حرج', 'Critical'),
      'warning' => t('تحذير', 'Warning'),
      'info' => t('للعلم', 'Info'),
      _ => t('سليم', 'OK'),
    };

class AdvHealthSample {
  const AdvHealthSample({required this.userId, this.name = '', this.value});
  final int userId;
  final String name;
  final num? value;

  factory AdvHealthSample.fromJson(Map<String, dynamic> j) =>
      AdvHealthSample(userId: asInt(j['user_id']), name: asStr(j['name']).trim(), value: j['value'] is num ? j['value'] as num : advNum(j['value']));

  String get shown => name.isEmpty ? '#$userId' : name;
}

class AdvHealthItem {
  const AdvHealthItem({
    required this.key,
    this.severity = 'ok',
    this.count = 0,
    this.labelAr = '',
    this.labelEn = '',
    this.hintAr = '',
    this.hintEn = '',
    this.drill,
    this.action,
    this.sample = const [],
  });

  final String key, severity;
  final int count;
  final String labelAr, labelEn, hintAr, hintEn;
  final AdvDrill? drill;

  /// `distribute` · `rebalance` · `reassign` · `open_alerts` · `open_requests` · `open_threads` · `open_handovers` ·
  /// `open_advisors` · null.
  final String? action;
  final List<AdvHealthSample> sample;

  factory AdvHealthItem.fromJson(Map<String, dynamic> j) {
    final d = j['drill'];
    final dm = asMap(d);
    final metric = asStr(dm['metric']);
    final sev = asStr(j['severity']);
    return AdvHealthItem(
      key: asStr(j['key']),
      severity: advSeverities.contains(sev) ? sev : 'ok',
      count: asInt(j['count']),
      labelAr: asStr(j['label_ar']).trim(),
      labelEn: asStr(j['label_en']).trim(),
      hintAr: asStr(j['hint_ar']).trim(),
      hintEn: asStr(j['hint_en']).trim(),
      drill: d is Map && metric.isNotEmpty ? AdvDrill(metric: metric, key: _str(dm['key'])) : null,
      action: _str(j['action']),
      sample: [for (final m in asMapList(j['sample'])) AdvHealthSample.fromJson(m)],
    );
  }

  bool get ok => severity == 'ok';

  String get label {
    final s = t(labelAr, labelEn);
    return s.isNotEmpty ? s : advHealthKeyLabel(key);
  }

  String? get hint {
    final s = t(hintAr, hintEn);
    return s.isEmpty ? null : s;
  }
}

/// The app's own name of a health item (the server sends its label; this is the fallback).
String advHealthKeyLabel(String key) => switch (key) {
      'unassigned_students' => t('طلاب بلا مرشد', 'Students without an advisor'),
      'advisor_away_students' => t('طلاب مرشدهم غائب', 'Students whose advisor is away'),
      'advisors_over_capacity' => t('مرشدون فوق الحد الأقصى', 'Advisors over their maximum'),
      'orphaned_flags' => t('تنبيهات لطلاب غادروا', 'Alerts of students who left'),
      'unowned_flags' => t('تنبيهات بلا مسؤول', 'Alerts without an owner'),
      'stuck_requests' => t('طلبات متوقفة', 'Stuck requests'),
      'stale_stats' => t('بيانات قديمة', 'Out-of-date figures'),
      'overdue_threads' => t('محادثات متأخرة الرد', 'Conversations overdue for a reply'),
      'pending_handovers' => t('ملفات تسليم لم تُستلم', 'Handovers not acknowledged'),
      'advisors_without_hours' => t('مرشدون بلا ساعات مكتبية', 'Advisors without office hours'),
      'students_without_program' => t('طلاب بلا برنامج', 'Students without a program'),
      _ => key,
    };

class AdvHealth {
  const AdvHealth({this.checkedAt, this.trigger, this.issues = 0, this.critical = 0, this.items = const [], this.previous});
  final DateTime? checkedAt;

  /// `tick` · `manual` · null (never checked).
  final String? trigger;
  final int issues, critical;
  final List<AdvHealthItem> items;
  final AdvHealthSummary? previous;

  factory AdvHealth.fromJson(Map<String, dynamic> j) => AdvHealth(
        checkedAt: _instant(j['checked_at']),
        trigger: _str(j['trigger']),
        issues: asInt(j['issues']),
        critical: asInt(j['critical']),
        items: [for (final m in asMapList(j['items'])) AdvHealthItem.fromJson(m)],
        previous: AdvHealthSummary.maybe(j['previous']),
      );

  bool get neverChecked => checkedAt == null;

  /// The items that need attention, worst first (then the larger count).
  List<AdvHealthItem> get problems {
    final out = [for (final i in items) if (!i.ok) i];
    out.sort((a, b) {
      final s = advSeverityRank(b.severity).compareTo(advSeverityRank(a.severity));
      return s != 0 ? s : b.count.compareTo(a.count);
    });
    return out;
  }

  /// Fewer issues than the previous check (null: nothing to compare).
  int? get change => previous == null ? null : issues - previous!.issues;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Analytics runs
// ═════════════════════════════════════════════════════════════════════════════

class AdvAnalyticsRun {
  const AdvAnalyticsRun({
    required this.id,
    this.kind = 'daily',
    this.trigger = 'tick',
    this.status = 'running',
    this.actor,
    this.counts = const {},
    this.error,
    this.startedAt,
    this.finishedAt,
    this.durationMs,
  });

  final int id;

  /// `daily` · `health`.
  final String kind;

  /// `tick` · `manual`.
  final String trigger;

  /// `running` · `done` · `failed`.
  final String status;
  final AdvRef? actor;
  final Map<String, int> counts;
  final String? error;
  final DateTime? startedAt, finishedAt;
  final int? durationMs;

  factory AdvAnalyticsRun.fromJson(Map<String, dynamic> j) => AdvAnalyticsRun(
        id: asInt(j['id']),
        kind: asStr(j['kind'], 'daily'),
        trigger: asStr(j['trigger'], 'tick'),
        status: asStr(j['status'], 'running'),
        actor: AdvRef.maybe(j['actor']),
        counts: _ints(j['counts']),
        error: _str(j['error']),
        startedAt: _instant(j['started_at']),
        finishedAt: _instant(j['finished_at']),
        durationMs: j['duration_ms'] == null ? null : asInt(j['duration_ms']),
      );

  bool get running => status == 'running';
  bool get failed => status == 'failed';
}

String advAnalyticsRunStatusLabel(String s) => switch (s) {
      'running' => t('يعمل', 'Running'),
      'done' => t('اكتمل', 'Done'),
      'failed' => t('تعذّر', 'Failed'),
      _ => s,
    };

String advAnalyticsRunKindLabel(String k) => switch (k) {
      'health' => t('فحص البيانات', 'Data check'),
      _ => t('تحديث الأرقام اليومي', 'Daily figures'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Outreach (#19)
// ═════════════════════════════════════════════════════════════════════════════

/// The longest subject / body the server takes.
const advOutreachSubjectMax = 200;
const advOutreachBodyMax = 5000;

/// The most recipients one message may have.
const advOutreachMaxRecipients = 5000;

/// What the server replaces per recipient (plain text, nothing else is expanded).
const advOutreachPlaceholders = ['{student_name}', '{advisor_name}', '{org_name}'];

String advPlaceholderLabel(String token) => switch (token) {
      '{student_name}' => t('اسم الطالب', 'Student name'),
      '{advisor_name}' => t('اسم المرشد', 'Advisor name'),
      '{org_name}' => t('اسم المؤسسة', 'Organization name'),
      _ => token,
    };

/// The audience of an outreach: the drill-down grammar (metric + key + the filters), or explicit member ids.
class AdvAudience {
  const AdvAudience({
    this.metric = 'all',
    this.key,
    this.state,
    this.programId,
    this.level,
    this.cohort,
    this.advisorUserId,
    this.categoryId,
    this.priority,
    this.from,
    this.to,
    this.termId,
    this.q,
    this.memberIds,
  });

  final String metric;
  final String? key, state, level, cohort, priority, q;
  final int? programId, advisorUserId, categoryId, termId;
  final DateTime? from, to;

  /// An explicit list (≤ 5 000); null = the metric decides.
  final List<int>? memberIds;

  /// The audience of a drill list: its metric and the dashboard's filters (+ the list's search).
  factory AdvAudience.of(AdvDrill drill, AdvAnalyticsFilter filter, {String? q}) => AdvAudience(
        metric: drill.metric,
        key: drill.key,
        state: drill.state,
        programId: filter.programId,
        level: filter.level,
        cohort: filter.cohort,
        advisorUserId: filter.advisor?.userId,
        from: filter.from,
        to: filter.to,
        termId: filter.termId,
        q: (q ?? '').trim().isEmpty ? null : q!.trim(),
      );

  /// Exactly these students.
  factory AdvAudience.members(List<int> ids) => AdvAudience(memberIds: ids.toSet().toList());

  factory AdvAudience.fromJson(Map<String, dynamic> j) => AdvAudience(
        metric: asStr(j['metric'], 'all'),
        key: _str(j['key']),
        state: _str(j['state']),
        programId: j['program_id'] == null ? null : asInt(j['program_id']),
        level: _str(j['level']),
        cohort: _str(j['cohort']),
        advisorUserId: j['advisor_user_id'] == null ? null : asInt(j['advisor_user_id']),
        categoryId: j['category_id'] == null ? null : asInt(j['category_id']),
        priority: _str(j['priority']),
        from: advLocalDate(j['from']),
        to: advLocalDate(j['to']),
        termId: j['term_id'] == null ? null : asInt(j['term_id']),
        q: _str(j['q']),
        memberIds: j['member_ids'] is List ? [for (final v in j['member_ids'] as List) asInt(v)] : null,
      );

  bool get explicit => memberIds != null;

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'key': ?key,
        'state': ?state,
        'program_id': ?programId,
        'level': ?level,
        'cohort': ?cohort,
        'advisor_user_id': ?advisorUserId,
        'category_id': ?categoryId,
        'priority': ?priority,
        if (from != null) 'from': advDay(from!),
        if (to != null) 'to': advDay(to!),
        'term_id': ?termId,
        'q': ?q,
        if (memberIds != null) 'member_ids': memberIds,
      };
}

/// The audiences an advisor (and a director) may pick without a chart: (metric, key, label).
List<(String, String?, String)> advAudiencePresets() => [
      ('all', null, t('كل طلابي', 'All my students')),
      ('risk_band', 'high', advRiskBandName('high')),
      ('risk_band', 'medium', advRiskBandName('medium')),
      ('priority', 'urgent', t('لهم تنبيه عاجل', 'With an urgent alert')),
      ('priority', 'high', t('لهم تنبيه مرتفع', 'With a high alert')),
      ('no_contact', null, advMetricLabel('no_contact')),
      ('no_show', null, advMetricLabel('no_show')),
      ('booked', null, advMetricLabel('booked')),
    ];

/// `POST /outreach/preview`.
class AdvOutreachPreview {
  const AdvOutreachPreview({this.count = 0, this.audienceHash = '', this.outOfScope = 0, this.capped = 0, this.sample = const [], this.labelAr = '', this.labelEn = ''});
  final int count, outOfScope, capped;
  final String audienceHash;
  final List<AdvOutreachSample> sample;
  final String labelAr, labelEn;

  factory AdvOutreachPreview.fromJson(Map<String, dynamic> j) {
    final ex = asMap(j['excluded']);
    final l = asMap(j['label']);
    return AdvOutreachPreview(
      count: asInt(j['count']),
      audienceHash: asStr(j['audience_hash']),
      outOfScope: asInt(ex['out_of_scope']),
      capped: asInt(ex['capped']),
      sample: [for (final m in asMapList(j['sample'])) AdvOutreachSample.fromJson(m)],
      labelAr: asStr(l['ar']).trim(),
      labelEn: asStr(l['en']).trim(),
    );
  }

  String get label => t(labelAr, labelEn).isNotEmpty ? t(labelAr, labelEn) : (labelAr.isNotEmpty ? labelAr : labelEn);

  bool get tooLarge => count > advOutreachMaxRecipients;
}

class AdvOutreachSample {
  const AdvOutreachSample({required this.memberId, this.name = '', this.code});
  final int memberId;
  final String name;
  final String? code;

  factory AdvOutreachSample.fromJson(Map<String, dynamic> j) => AdvOutreachSample(memberId: asInt(j['member_id']), name: asStr(j['name']).trim(), code: _str(j['code']));

  String get shown => name.isEmpty ? '#$memberId' : name;
}

/// An outreach template (Phase 5 `GET /templates?kind=outreach`).
class AdvOutreachTemplate {
  const AdvOutreachTemplate({required this.id, this.key = '', this.nameAr = '', this.nameEn = '', this.bodyAr = '', this.bodyEn = '', this.system = false, this.active = true});
  final int id;
  final String key, nameAr, nameEn, bodyAr, bodyEn;
  final bool system, active;

  factory AdvOutreachTemplate.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']).trim();
    return AdvOutreachTemplate(
      id: asInt(j['id']),
      key: asStr(j['key']),
      nameAr: asStr(j['name_ar']).trim().isEmpty ? name : asStr(j['name_ar']).trim(),
      nameEn: asStr(j['name_en']).trim(),
      bodyAr: asStr(j['body_ar']),
      bodyEn: asStr(j['body_en']),
      system: asBool(j['system']),
      active: j.containsKey('active') ? asBool(j['active'], true) : true,
    );
  }

  String get name {
    final s = t(nameAr, nameEn);
    return s.isNotEmpty ? s : (nameAr.isNotEmpty ? nameAr : (nameEn.isNotEmpty ? nameEn : '#$id'));
  }

  /// The body in the app's language, else the other one.
  String get body {
    final s = t(bodyAr, bodyEn);
    return s.trim().isNotEmpty ? s : (bodyAr.trim().isNotEmpty ? bodyAr : bodyEn);
  }
}

/// The composer's values.
class AdvOutreachDraft {
  const AdvOutreachDraft({this.subject = '', this.body = '', this.templateId, this.email = false, required this.clientId});
  final String subject, body;
  final int? templateId;
  final bool email;

  /// One per draft: a retried send answers the message already made.
  final String clientId;

  AdvOutreachDraft copyWith({String? subject, String? body, int? Function()? templateId, bool? email}) => AdvOutreachDraft(
        subject: subject ?? this.subject,
        body: body ?? this.body,
        templateId: templateId == null ? this.templateId : templateId(),
        email: email ?? this.email,
        clientId: clientId,
      );

  /// Why it cannot be sent (bilingual), null when it can.
  String? get error {
    if (subject.trim().isEmpty) return t('اكتب عنوان الرسالة', 'Write the subject');
    if (subject.trim().length > advOutreachSubjectMax) return t('العنوان أطول من $advOutreachSubjectMax حرف', 'The subject is longer than $advOutreachSubjectMax characters');
    if (body.trim().isEmpty) return t('اكتب نص الرسالة', 'Write the message');
    if (body.trim().length > advOutreachBodyMax) return t('النص أطول من $advOutreachBodyMax حرف', 'The message is longer than $advOutreachBodyMax characters');
    return null;
  }

  Map<String, dynamic> toJson(AdvAudience audience, String audienceHash) => {
        'audience': audience.toJson(),
        'audience_hash': audienceHash,
        'subject': subject.trim(),
        'body': body.trim(),
        'template_id': templateId,
        'email': email,
        'client_id': clientId,
      };
}

/// [text] with [token] put at [at] (the cursor), spaced from its neighbours; answers the text and the new cursor.
(String, int) advInsertToken(String text, String token, int at) {
  final i = at < 0 || at > text.length ? text.length : at;
  final before = text.substring(0, i), after = text.substring(i);
  final pre = before.isEmpty || before.endsWith(' ') || before.endsWith('\n') ? '' : ' ';
  final post = after.isEmpty || after.startsWith(' ') || after.startsWith('\n') ? '' : ' ';
  final out = '$before$pre$token$post$after';
  return (out, before.length + pre.length + token.length);
}

/// The placeholders [values] holds put into [text] by plain replacement (what the server does per recipient).
String advFillPlaceholders(String text, Map<String, String> values) {
  var out = text;
  for (final e in values.entries) {
    out = out.replaceAll(e.key, e.value);
  }
  return out;
}

const advOutreachStatuses = ['queued', 'sending', 'sent', 'failed'];

String advOutreachStatusLabel(String s) => switch (s) {
      'queued' => t('في الانتظار', 'Queued'),
      'sending' => t('يُرسل', 'Sending'),
      'sent' => t('أُرسلت', 'Sent'),
      'failed' => t('تعذّر الإرسال', 'Failed'),
      _ => s,
    };

/// A sent (or sending) group message.
class AdvOutreach {
  const AdvOutreach({
    required this.id,
    this.subject = '',
    this.sender,
    this.labelAr = '',
    this.labelEn = '',
    this.status = 'queued',
    this.email = false,
    this.createdAt,
    this.finishedAt,
    this.recipients = 0,
    this.delivered = 0,
    this.pushed = 0,
    this.read = 0,
    this.failed = 0,
    this.capped = 0,
    this.outOfScope = 0,
    this.readRate,
    this.body,
    this.audience,
    this.templateId,
  });

  final int id;
  final String subject;
  final AdvRef? sender;
  final String labelAr, labelEn;
  final String status;
  final bool email;
  final DateTime? createdAt, finishedAt;
  final int recipients, delivered, pushed, read, failed, capped, outOfScope;
  final double? readRate;

  /// The detail only (`GET /outreach/{id}`).
  final String? body;
  final AdvAudience? audience;
  final int? templateId;

  factory AdvOutreach.fromJson(Map<String, dynamic> j) {
    final c = asMap(j['counts']);
    final l = asMap(j['label']);
    final a = j['audience'];
    return AdvOutreach(
      id: asInt(j['id']),
      subject: asStr(j['subject']).trim(),
      sender: AdvRef.maybe(j['sender']),
      labelAr: asStr(l['ar']).trim(),
      labelEn: asStr(l['en']).trim(),
      status: asStr(j['status'], 'queued'),
      email: asBool(j['email']),
      createdAt: _instant(j['created_at']),
      finishedAt: _instant(j['finished_at']),
      recipients: asInt(c['recipients']),
      delivered: asInt(c['delivered']),
      pushed: asInt(c['pushed']),
      read: asInt(c['read']),
      failed: asInt(c['failed']),
      capped: asInt(c['capped']),
      outOfScope: asInt(c['out_of_scope']),
      readRate: advNum(j['read_rate']),
      body: j.containsKey('body') ? asStr(j['body']) : null,
      audience: a is Map ? AdvAudience.fromJson(asMap(a)) : null,
      templateId: j['template_id'] == null ? null : asInt(j['template_id']),
    );
  }

  String get label => t(labelAr, labelEn).isNotEmpty ? t(labelAr, labelEn) : (labelAr.isNotEmpty ? labelAr : labelEn);

  /// Still being delivered.
  bool get inFlight => status == 'queued' || status == 'sending';

  /// Recipients who have not opened it yet (delivered, not read).
  int get unread => (delivered - read).clamp(0, recipients);
}

const advRecipientStates = ['all', 'unread', 'read', 'failed'];

String advRecipientStateLabel(String s) => switch (s) {
      'unread' => t('لم يقرؤوها', 'Not read'),
      'read' => t('قرؤوها', 'Read'),
      'failed' => t('لم تصلهم', 'Not delivered'),
      _ => t('الكل', 'Everyone'),
    };

String advRecipientStatusLabel(String s) => switch (s) {
      'queued' => t('في الانتظار', 'Queued'),
      'delivered' => t('وصلت', 'Delivered'),
      'failed' => t('لم تصل', 'Not delivered'),
      _ => s,
    };

class AdvOutreachRecipient {
  const AdvOutreachRecipient({required this.memberId, this.name = '', this.code, this.status = 'queued', this.pushed = false, this.deliveredAt, this.readAt});
  final int memberId;
  final String name;
  final String? code;

  /// `queued` · `delivered` · `failed`.
  final String status;

  /// A push or the e-mail fallback reached them.
  final bool pushed;
  final DateTime? deliveredAt, readAt;

  factory AdvOutreachRecipient.fromJson(Map<String, dynamic> j) => AdvOutreachRecipient(
        memberId: asInt(j['member_id']),
        name: asStr(j['name']).trim(),
        code: _str(j['code']),
        status: asStr(j['status'], 'queued'),
        pushed: asBool(j['pushed']),
        deliveredAt: _instant(j['delivered_at']),
        readAt: _instant(j['read_at']),
      );

  String get shown => name.isEmpty ? '#$memberId' : name;
  bool get read => readAt != null;
}

/// A message the student received (member route; the placeholders already filled).
class AdvStudentMessage {
  const AdvStudentMessage({required this.id, this.subject = '', this.body, this.senderName = '', this.sentAt, this.readAt});
  final int id;
  final String subject;

  /// null in the hub's `latest` (no body there).
  final String? body;
  final String senderName;
  final DateTime? sentAt, readAt;

  factory AdvStudentMessage.fromJson(Map<String, dynamic> j) => AdvStudentMessage(
        id: asInt(j['id']),
        subject: asStr(j['subject']).trim(),
        body: j.containsKey('body') ? asStr(j['body']) : null,
        senderName: asStr(j['sender_name']).trim(),
        sentAt: _instant(j['sent_at']),
        readAt: _instant(j['read_at']),
      );

  bool get unread => readAt == null;

  AdvStudentMessage markedRead(DateTime at) => AdvStudentMessage(id: id, subject: subject, body: body, senderName: senderName, sentAt: sentAt, readAt: readAt ?? at);
}

/// The hub's `outreach` block: `{"unread","latest"}`.
class AdvHubOutreach {
  const AdvHubOutreach({this.unread = 0, this.latest = const []});
  final int unread;
  final List<AdvStudentMessage> latest;

  factory AdvHubOutreach.fromJson(dynamic v) {
    final j = asMap(v);
    return AdvHubOutreach(unread: asInt(j['unread']), latest: [for (final m in asMapList(j['latest'])) AdvStudentMessage.fromJson(m)]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Status keys of the phase
// ═════════════════════════════════════════════════════════════════════════════

/// The staff `GET /status` `me` keys of Phase 8: the analytics tier, may send outreach, the health issues.
class AdvAnalyticsMe {
  const AdvAnalyticsMe({this.analytics, this.outreach = false, this.healthIssues = 0});

  /// `manage` · `aggregate` · null (no analytics).
  final String? analytics;
  final bool outreach;
  final int healthIssues;

  factory AdvAnalyticsMe.fromStatus(Map<String, dynamic> status) {
    final me = asMap(status['me']);
    final a = asStr(me['analytics']);
    return AdvAnalyticsMe(
      analytics: a == 'manage' || a == 'aggregate' ? a : null,
      outreach: asBool(me['outreach']),
      healthIssues: asInt(me['health_issues']),
    );
  }

  bool get manage => analytics == 'manage';
  bool get any => analytics != null;
}

/// Labels of the priorities in their order (the struggling card).
List<(String, String)> advPriorityChoices() => [for (final p in advPriorities) (p, advPriorityLabel(p))];
