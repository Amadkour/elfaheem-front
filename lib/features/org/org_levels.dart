// lib/features/org/org_levels.dart — pure logic of academic levels (API: org_academic_router.py /academic/levels,
// services/organization/academic_levels.py). No widgets and no ApiClient here, so it is unit-tested
// (test/org/org_levels_test.dart).
//
//   LevelDraft        one level as edited: labels, departments mode (inherit | general | custom), rules, term courses
//   resolveLevels     effective departments of every level + where they come from ("inherited from Level N")
//   PrereqRule        one {type, params} rule + its human sentence
//   RuleResult        the server's evaluation of a rule for one student (have / need / met)
library;

import 'package:flutter_education_app/config/app_config.dart';

// same as admin_common's _t(), kept local so this file stays free of widget imports (unit tests load it alone)
String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

const levelTermKinds = ['term1', 'term2', 'summer'];
const ruleTypes = ['courses_passed', 'level_courses', 'min_courses', 'min_hours', 'min_average'];

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

List<int> _ints(dynamic v) => v is List ? [for (final x in v) _int(x)] : <int>[];

String termKindLabel(String kind) => switch (kind) {
      'term1' => _t('الفصل الأول', 'Term 1'),
      'term2' => _t('الفصل الثاني', 'Term 2'),
      _ => _t('الفصل الصيفي', 'Summer term'),
    };

/// One {type, params} prerequisite.
class PrereqRule {
  PrereqRule(this.type, [Map<String, dynamic>? params]) : params = {...?params};

  factory PrereqRule.fromJson(Map<String, dynamic> j) =>
      PrereqRule('${j['type']}', j['params'] is Map ? Map<String, dynamic>.from(j['params'] as Map) : null);

  final String type;
  final Map<String, dynamic> params;

  Map<String, dynamic> toJson() => {'type': type, 'params': params};

  List<int> get courseIds => _ints(params['course_ids']);

  /// The client-side check mirrors the server's (the server stays the judge).
  bool get isValid => switch (type) {
        'courses_passed' => courseIds.isNotEmpty &&
            (params['min_count'] == null || (_int(params['min_count']) >= 1 && _int(params['min_count']) <= courseIds.length)),
        'level_courses' => _int(params['percent'] ?? 100) >= 1 && _int(params['percent'] ?? 100) <= 100,
        'min_courses' => _int(params['count']) >= 1,
        'min_hours' => (num.tryParse('${params['hours']}') ?? 0) > 0,
        'min_average' => (num.tryParse('${params['percent']}') ?? 0) > 0 && (num.tryParse('${params['percent']}') ?? 0) <= 100,
        _ => false,
      };

  /// A friendly sentence: "Pass 3 of these 4 courses", "Pass 100% of Level 1's courses" …
  String describe({String Function(String key)? levelName, String Function(int id)? courseName}) {
    switch (type) {
      case 'courses_passed':
        final ids = courseIds;
        final names = courseName == null ? '' : ': ${ids.map(courseName).join('، ')}';
        final min = params['min_count'] == null ? ids.length : _int(params['min_count']);
        return min >= ids.length
            ? _t('اجتياز ${ids.length == 1 ? 'المقرر' : 'كل المقررات (${ids.length})'}$names', 'Pass ${ids.length == 1 ? 'the course' : 'all ${ids.length} courses'}$names')
            : _t('اجتياز $min من ${ids.length} مقررات$names', 'Pass $min of ${ids.length} courses$names');
      case 'level_courses':
        final pct = _int(params['percent'] ?? 100);
        final key = params['level_key'] == null ? null : '${params['level_key']}';
        final lvl = key == null ? _t('المستوى السابق', 'the previous level') : (levelName?.call(key) ?? key);
        final summer = params['include_summer'] == true ? _t(' مع الصيفي', ' incl. summer') : '';
        return pct >= 100 ? _t('اجتياز كل مقررات $lvl$summer', 'Pass every course of $lvl$summer') : _t('اجتياز $pct٪ من مقررات $lvl$summer', 'Pass $pct% of $lvl\'s courses$summer');
      case 'min_courses':
        return _t('اجتياز ${params['count']} مقررات على الأقل', 'Pass at least ${params['count']} courses');
      case 'min_hours':
        return _t('إتمام ${params['hours']} ساعة دراسية على الأقل', 'Complete at least ${params['hours']} study hours');
      case 'min_average':
        return _t('متوسط درجات ${params['percent']}٪ على الأقل', 'An average score of at least ${params['percent']}%');
      default:
        return type;
    }
  }
}

String ruleTypeLabel(String type) => switch (type) {
      'courses_passed' => _t('اجتياز مقررات محددة', 'Pass specific courses'),
      'level_courses' => _t('إنهاء مقررات مستوى', 'Finish a level\'s courses'),
      'min_courses' => _t('عدد المقررات المجتازة', 'Number of courses passed'),
      'min_hours' => _t('الساعات الدراسية المكتملة', 'Completed study hours'),
      _ => _t('متوسط الدرجات', 'Average score'),
    };

/// One level as edited on the levels page. [key] never changes after creation (students store it).
class LevelDraft {
  LevelDraft({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.programs = 'inherit',
    List<int>? programIds,
    List<PrereqRule>? prerequisites,
    Map<String, List<int>>? terms,
    this.hasSummer = false,
    this.students = 0,
  })  : programIds = programIds ?? <int>[],
        prerequisites = prerequisites ?? <PrereqRule>[],
        terms = {for (final k in levelTermKinds) k: [...?terms?[k]]};

  factory LevelDraft.fromJson(Map<String, dynamic> j) => LevelDraft(
        key: '${j['key']}',
        labelAr: '${j['label_ar'] ?? ''}',
        labelEn: '${j['label_en'] ?? ''}',
        programs: '${j['programs'] ?? 'inherit'}',
        programIds: _ints(j['program_ids']),
        prerequisites: [
          for (final r in (j['prerequisites'] as List?) ?? const [])
            if (r is Map) PrereqRule.fromJson(Map<String, dynamic>.from(r))
        ],
        terms: {for (final k in levelTermKinds) k: _ints((j['terms'] is Map ? j['terms'] as Map : const {})[k])},
        hasSummer: j['has_summer'] == true,
        students: _int(j['students']),
      );

  final String key;
  String labelAr, labelEn, programs;
  List<int> programIds;
  final List<PrereqRule> prerequisites;
  final Map<String, List<int>> terms;
  bool hasSummer;
  final int students;

  String get label {
    final a = labelAr.trim(), e = labelEn.trim();
    final v = _t(a.isNotEmpty ? a : e, e.isNotEmpty ? e : a);
    return v.isEmpty ? _t('المستوى $key', 'Level $key') : v;
  }

  List<int> get allCourses => [for (final k in levelTermKinds) ...terms[k]!];

  /// The full object the server expects (PUT /academic/levels replaces everything).
  Map<String, dynamic> toJson() => {
        'key': key,
        'label_ar': labelAr.trim().isEmpty ? null : labelAr.trim(),
        'label_en': labelEn.trim().isEmpty ? null : labelEn.trim(),
        'programs': programs,
        'program_ids': programs == 'custom' ? programIds : <int>[],
        'prerequisites': [for (final r in prerequisites) r.toJson()],
        'terms': {for (final k in levelTermKinds) k: (k == 'summer' && !hasSummer) ? <int>[] : terms[k]},
        'has_summer': hasSummer,
      };

  /// A new level key: the next free number ("1", "2", …).
  static String nextKey(Iterable<String> taken) {
    var i = 1;
    final set = taken.toSet();
    while (set.contains('$i')) {
      i++;
    }
    return '$i';
  }
}

/// The departments a level opens: [programIds] null = every department. [sourceIndex] = the level whose explicit
/// choice applies (null = nobody chose — general by default). [inherited] = this level follows a lower one.
class ResolvedLevel {
  const ResolvedLevel({required this.programIds, required this.inherited, required this.sourceIndex});
  final List<int>? programIds;
  final bool inherited;
  final int? sourceIndex;

  bool get isGeneral => programIds == null;
}

/// Same algorithm as the server's `resolve_levels`: a level that inherits takes the effective set of the level
/// below it, so editing a level reaches every higher level that still inherits; general / custom stop it.
List<ResolvedLevel> resolveLevels(List<LevelDraft> levels) {
  final out = <ResolvedLevel>[];
  List<int>? eff;
  int? src;
  for (var i = 0; i < levels.length; i++) {
    final l = levels[i];
    if (l.programs == 'custom') {
      eff = [...l.programIds];
      src = i;
    } else if (l.programs == 'general') {
      eff = null;
      src = i;
    }
    out.add(ResolvedLevel(programIds: eff == null ? null : [...eff], inherited: l.programs == 'inherit', sourceIndex: src));
  }
  return out;
}

/// Problems to fix before saving (empty = fine). Mirrors the server's checks so the admin sees them at once.
List<String> levelProblems(List<LevelDraft> levels) {
  final out = <String>[];
  for (final l in levels) {
    if (l.programs == 'custom' && l.programIds.isEmpty) {
      out.add(_t('${l.label}: اختر قسماً واحداً على الأقل أو اجعله عاماً', '${l.label}: pick at least one department or make it general'));
    }
    final seen = <int>{};
    for (final k in levelTermKinds) {
      if (k == 'summer' && !l.hasSummer) continue;
      for (final c in l.terms[k]!) {
        if (!seen.add(c)) out.add(_t('${l.label}: مقرر مكرر في أكثر من فصل', '${l.label}: a course is in more than one term'));
      }
    }
    for (final r in l.prerequisites) {
      if (!r.isValid) out.add(_t('${l.label}: شرط غير مكتمل', '${l.label}: an incomplete rule'));
    }
  }
  return out;
}

/// The server's evaluation of one rule for one student (GET /my-level, program checks).
class RuleResult {
  const RuleResult({required this.rule, required this.met, this.have, this.need, this.unit = '', this.noData = false, this.missing = const []});

  factory RuleResult.fromJson(Map<String, dynamic> j) => RuleResult(
        rule: PrereqRule.fromJson(j),
        met: j['met'] == true,
        have: j['have'] is num ? j['have'] as num : num.tryParse('${j['have']}'),
        need: j['need'] is num ? j['need'] as num : num.tryParse('${j['need']}'),
        unit: '${j['unit'] ?? ''}',
        noData: j['no_data'] == true,
        missing: _ints(j['missing_course_ids']),
      );

  final PrereqRule rule;
  final bool met, noData;
  final num? have, need;
  final String unit;
  final List<int> missing;

  /// 0..1 progress of this rule.
  double get progress {
    if (met) return 1;
    if (have == null || need == null || need == 0) return 0;
    return (have! / need!).clamp(0, 1).toDouble();
  }

  String get progressText {
    if (noData) return _t('لا توجد بيانات بعد', 'No data yet');
    String f(num? v) => v == null ? '—' : (v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1));
    final u = switch (unit) {
      'hours' => _t(' ساعة', ' h'),
      'percent' => '%',
      _ => '',
    };
    return '${f(have)}$u / ${f(need)}$u';
  }
}

/// Overall progress toward a set of rules (average of the rules' progress), 0..100 — same as the server.
int rulesPercent(List<RuleResult> results) {
  if (results.isEmpty) return 0;
  final sum = results.fold<double>(0, (a, r) => a + r.progress);
  return (100 * sum / results.length).round();
}
