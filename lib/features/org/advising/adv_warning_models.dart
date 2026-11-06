// lib/features/org/advising/adv_warning_models.dart — pure models of the early warning (docs/advising/PHASE6.md):
// the rules and the kind catalog their editor is generated from, the engine and its runs, the alerts with their
// explanation, the student 360's "Early warning" block, the graduation projection, the advisor's digest choice and
// the settings group "Alerts and nudges". No Flutter widgets: unit-tested in test/org/adv_warning_models_test.dart.
//
// Every parser is tolerant of missing keys (an older server leaves a block out): a missing flag is false, a missing
// number is null, a missing list is empty. The app hard-codes no rule kind beyond its icon (adv_warning_parts.dart)
// and the explanation fallback (adv_texts.dart): names, help, parameters and limits come from the server's `kinds`.
library;

import 'package:flutter_education_app/core/plural.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t;
import '../org_registrar.dart' show termTitle;
import '../org_v3.dart' show orgParseUtc, orgUtc;
import 'adv_models.dart' show AdvCategory, AdvPolicy, AdvPolicyBundle, AdvRef, advGpa, advPriorities, advPriorityRank;
import 'adv_texts.dart' show advWarningKindFallback;

String? _text(dynamic v) {
  if (v == null || v is Map || v is List) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int? _int(dynamic v) {
  final n = _num(v);
  return n?.round();
}

String _priority(dynamic v, [String fallback = 'normal']) {
  final p = asStr(v);
  return advPriorities.contains(p) ? p : fallback;
}

/// "2" for a whole number, else "2.5" (one decimal) — credits, terms.
String advWhole(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

/// A text the server sends in both languages (`{"ar","en"}`): the app language, else the other one.
class AdvText {
  const AdvText({this.ar = '', this.en = ''});
  final String ar, en;

  factory AdvText.fromJson(dynamic v) {
    if (v is! Map) {
      final s = _text(v) ?? '';
      return AdvText(ar: s, en: s);
    }
    final m = asMap(v);
    return AdvText(ar: (_text(m['ar']) ?? ''), en: (_text(m['en']) ?? ''));
  }

  bool get isEmpty => ar.isEmpty && en.isEmpty;

  String get shown {
    final s = t(ar, en);
    return s.isNotEmpty ? s : (ar.isNotEmpty ? ar : en);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The kind catalog (`risk_rules.KINDS`, served with the rules)
// ═════════════════════════════════════════════════════════════════════════════

/// The units a parameter is written in.
const advRuleUnits = ['gpa', 'percent', 'count', 'days', 'terms'];

/// One parameter of a rule kind: `{"key","type","min","max","step","default","nullable","unit","label_ar","label_en"}`.
class AdvRuleParam {
  const AdvRuleParam({
    required this.key,
    this.type = 'number',
    this.min,
    this.max,
    this.step,
    this.defaultValue,
    this.defaultFlag,
    this.nullable = false,
    this.unit = '',
    this.labelAr = '',
    this.labelEn = '',
  });

  final String key;

  /// `number` (decimals allowed) · `int` · `bool` (an on / off choice, e.g. "also alert when at risk").
  final String type;
  final double? min, max, step, defaultValue;

  /// The default of a `bool` parameter.
  final bool? defaultFlag;

  /// May be left empty (e.g. `planned_terms`: empty = the organization's own plan).
  final bool nullable;

  /// `gpa` · `percent` · `count` · `days` · `terms` (anything else: no unit shown).
  final String unit;
  final String labelAr, labelEn;

  factory AdvRuleParam.fromJson(Map<String, dynamic> j) => AdvRuleParam(
        key: asStr(j['key']),
        type: const ['int', 'bool'].contains(asStr(j['type'])) ? asStr(j['type']) : 'number',
        min: _num(j['min']),
        max: _num(j['max']),
        step: _num(j['step']),
        defaultValue: j['default'] is bool ? null : _num(j['default']),
        defaultFlag: j['default'] is bool ? j['default'] as bool : null,
        nullable: asBool(j['nullable']),
        unit: asStr(j['unit']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
      );

  bool get isInt => type == 'int';
  bool get isBool => type == 'bool';

  /// The value a new rule starts with.
  Object? get initial => isBool ? (defaultFlag ?? false) : normalize(defaultValue);

  String get label {
    final s = t(labelAr, labelEn);
    if (s.isNotEmpty) return s;
    final other = labelAr.isNotEmpty ? labelAr : labelEn;
    return other.isNotEmpty ? other : key;
  }

  /// The step of the − / + buttons: the server's, else 1 for a whole number, 0.25 for a GPA, 1 otherwise.
  double get stepOrDefault {
    final s = step;
    if (s != null && s > 0) return s;
    if (isInt) return 1;
    return unit == 'gpa' ? 0.05 : 1;
  }

  /// [v] as it is sent: a whole number for an `int`, else the decimal rounded to the step's precision.
  Object? normalize(Object? v) {
    if (isBool) return v is bool ? v : (defaultFlag ?? false);
    if (v is! num) return null;
    if (isInt) return v.round();
    return double.parse(v.toDouble().toStringAsFixed(_decimals));
  }

  int get _decimals {
    if (isInt) return 0;
    if (unit == 'gpa') return 2;
    final s = stepOrDefault;
    if (s == s.roundToDouble()) return 0;
    return s * 10 == (s * 10).roundToDouble() ? 1 : 2;
  }

  /// The value alone, written for this unit ("2.00", "15", "45").
  String number(Object? v) {
    if (v is! num) return '';
    if (isInt) return '${v.round()}';
    final d = v.toDouble();
    if (unit == 'gpa') return advGpa(d);
    final s = d.toStringAsFixed(_decimals);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  /// The value with its unit ("2.00", "15 %", "45 days", "2 courses"); [empty] for a nullable value left empty.
  String format(Object? v, {String? empty}) {
    if (v is bool) return v ? t('نعم', 'Yes') : t('لا', 'No');
    if (v is! num) return empty ?? t('تلقائي', 'Automatic');
    final s = number(v);
    final n = v.round();
    return switch (unit) {
      'percent' => '$s%',
      'days' => countText(n, ar1: 'يوم واحد', ar2: 'يومان', arFew: '$s أيام', arMany: '$s يوماً', en1: '1 day', en: '$s days'),
      'terms' => countText(n, ar1: 'فصل واحد', ar2: 'فصلان', arFew: '$s فصول', arMany: '$s فصلاً', en1: '1 term', en: '$s terms'),
      _ => s,
    };
  }

  /// Why [v] cannot be saved, null when it can.
  String? check(Object? v) {
    if (isBool) return null;
    if (v is! num) return nullable ? null : t('اكتب قيمة «$label»', 'Give a value for "$label"');
    final lo = min, hi = max;
    if ((lo != null && v < lo - 1e-9) || (hi != null && v > hi + 1e-9)) {
      return t('«$label» بين ${number(lo)} و${number(hi)}', '"$label" is between ${number(lo)} and ${number(hi)}');
    }
    return null;
  }

  /// [v] moved one step up ([up]) or down, kept inside the limits.
  num stepped(num? v, {required bool up}) {
    final num from = v ?? defaultValue ?? min ?? 0;
    var next = from + (up ? stepOrDefault : -stepOrDefault);
    if (min != null && next < min!) next = min!;
    if (max != null && next > max!) next = max!;
    return normalize(next) as num;
  }
}

/// One kind of rule: `{"kind","label_ar","label_en","help_ar","help_en","default_priority","default_cooldown_days","params"}`.
class AdvRuleKind {
  const AdvRuleKind({
    required this.kind,
    this.labelAr = '',
    this.labelEn = '',
    this.helpAr = '',
    this.helpEn = '',
    this.defaultPriority = 'normal',
    this.defaultCooldownDays = 14,
    this.params = const [],
  });

  final String kind;
  final String labelAr, labelEn, helpAr, helpEn;
  final String defaultPriority;
  final int defaultCooldownDays;
  final List<AdvRuleParam> params;

  factory AdvRuleKind.fromJson(Map<String, dynamic> j) => AdvRuleKind(
        kind: asStr(j['kind']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        helpAr: asStr(j['help_ar']).trim(),
        helpEn: asStr(j['help_en']).trim(),
        defaultPriority: _priority(j['default_priority']),
        defaultCooldownDays: asInt(j['default_cooldown_days'], 14),
        params: [for (final m in asMapList(j['params'])) AdvRuleParam.fromJson(m)].where((p) => p.key.isNotEmpty).toList(),
      );

  String get label {
    final s = t(labelAr, labelEn);
    if (s.isNotEmpty) return s;
    final other = labelAr.isNotEmpty ? labelAr : labelEn;
    return other.isNotEmpty ? other : kind;
  }

  String get help {
    final s = t(helpAr, helpEn);
    return s.isNotEmpty ? s : (helpAr.isNotEmpty ? helpAr : helpEn);
  }

  AdvRuleParam? param(String key) => params.where((p) => p.key == key).firstOrNull;

  /// The parameters a new rule of this kind starts with.
  Map<String, Object?> get defaults => {for (final p in params) p.key: p.initial};
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rules
// ═════════════════════════════════════════════════════════════════════════════

/// Where a rule applies: `{"program_id","level","cohort"}` (any field null = any).
class AdvRuleScope {
  const AdvRuleScope({this.programId, this.level, this.cohort});
  final int? programId;
  final String? level, cohort;

  static AdvRuleScope? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = asMap(v);
    final s = AdvRuleScope(programId: m['program_id'] == null ? null : _int(m['program_id']), level: _text(m['level']), cohort: _text(m['cohort']));
    return s.isEmpty ? null : s;
  }

  bool get isEmpty => programId == null && level == null && cohort == null;

  /// The body's `scope`: null when it applies everywhere.
  Map<String, dynamic>? toJson() => isEmpty ? null : {'program_id': programId, 'level': level, 'cohort': cohort};

  AdvRuleScope copyWith({int? Function()? programId, String? Function()? level, String? Function()? cohort}) => AdvRuleScope(
        programId: programId == null ? this.programId : programId(),
        level: level == null ? this.level : level(),
        cohort: cohort == null ? this.cohort : cohort(),
      );

  /// "Software Engineering · Level 3 · 2023" ([programName] names the program id).
  String describe(String Function(int id) programName) => [
        if (programId != null) programName(programId!),
        ?level,
        ?cohort,
      ].join(' · ');
}

/// The rule an alert or a hit names: `{"id","key","kind","name_ar","name_en"}` (`id` null once the rule is deleted).
class AdvRuleRef {
  const AdvRuleRef({this.id, this.key = '', this.kind = '', this.nameAr = '', this.nameEn = ''});
  final int? id;
  final String key, kind, nameAr, nameEn;

  factory AdvRuleRef.fromJson(dynamic v) {
    final m = asMap(v);
    final id = m['id'];
    return AdvRuleRef(
      id: id == null ? null : _int(id),
      key: asStr(m['key']),
      kind: asStr(m['kind']),
      nameAr: asStr(m['name_ar']).trim(),
      nameEn: asStr(m['name_en']).trim(),
    );
  }

  String get name {
    final s = t(nameAr, nameEn);
    if (s.isNotEmpty) return s;
    final other = nameAr.isNotEmpty ? nameAr : nameEn;
    return other.isNotEmpty ? other : (key.isNotEmpty ? key : kind);
  }
}

/// One rule of `GET …/rules`.
class AdvRule {
  const AdvRule({
    required this.id,
    this.key = '',
    required this.kind,
    this.nameAr = '',
    this.nameEn = '',
    this.customName = false,
    this.params = const {},
    this.priority = 'normal',
    this.cooldownDays = 14,
    this.enabled = true,
    this.system = false,
    this.category,
    this.scope,
    this.summary = const AdvText(),
    this.updatedAt,
    this.updatedBy,
  });

  final int id;
  final String key, kind;

  /// The custom name when [customName], else the kind's label.
  final String nameAr, nameEn;
  final bool customName;
  /// Numbers, or a bool for a `bool` parameter (null: a nullable one left empty).
  final Map<String, Object?> params;
  final String priority;
  final int cooldownDays;
  final bool enabled;

  /// Seeded by the platform: edited and switched off, never deleted.
  final bool system;

  /// null: the organization's `academic` category.
  final AdvCategory? category;
  final AdvRuleScope? scope;

  /// "CGPA below 2.00".
  final AdvText summary;
  final DateTime? updatedAt;
  final AdvRef? updatedBy;

  factory AdvRule.fromJson(Map<String, dynamic> j) => AdvRule(
        id: asInt(j['id']),
        key: asStr(j['key']),
        kind: asStr(j['kind']),
        nameAr: asStr(j['name_ar']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        customName: asBool(j['custom_name']),
        params: {for (final e in asMap(j['params']).entries) e.key: e.value is bool ? e.value as bool : (e.value is int ? e.value as int : _num(e.value))},
        priority: _priority(j['priority']),
        cooldownDays: asInt(j['cooldown_days'], 14),
        enabled: asBool(j['enabled'], true),
        system: asBool(j['system']),
        category: AdvCategory.maybe(j['category']),
        scope: AdvRuleScope.maybe(j['scope']),
        summary: AdvText.fromJson(j['summary']),
        updatedAt: orgParseUtc(j['updated_at']),
        updatedBy: AdvRef.maybe(j['updated_by']),
      );

  String get name => AdvRuleRef(key: key, kind: kind, nameAr: nameAr, nameEn: nameEn).name;

  AdvRuleRef get ref => AdvRuleRef(id: id, key: key, kind: kind, nameAr: nameAr, nameEn: nameEn);

  /// The summary, else "name · param value · …" from the catalog ([kind]).
  String summaryText(AdvRuleKind? kind) {
    if (!summary.isEmpty) return summary.shown;
    final k = kind;
    if (k == null) return name;
    return [for (final p in k.params) if (params[p.key] != null) '${p.label}: ${p.format(params[p.key])}'].join(' · ');
  }

  AdvRule withEnabled(bool on) => AdvRule(
        id: id,
        key: key,
        kind: kind,
        nameAr: nameAr,
        nameEn: nameEn,
        customName: customName,
        params: params,
        priority: priority,
        cooldownDays: cooldownDays,
        enabled: on,
        system: system,
        category: category,
        scope: scope,
        summary: summary,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );
}

/// The rule editor's body: POST (with `kind`) and the whole-object PUT (without it).
class AdvRuleDraft {
  const AdvRuleDraft({
    required this.kind,
    this.params = const {},
    this.priority = 'normal',
    this.cooldownDays = 14,
    this.enabled = true,
    this.categoryId,
    this.scope = const AdvRuleScope(),
    this.nameAr = '',
    this.nameEn = '',
  });

  /// A new rule of [kind] with its defaults.
  factory AdvRuleDraft.fresh(AdvRuleKind kind) =>
      AdvRuleDraft(kind: kind.kind, params: kind.defaults, priority: kind.defaultPriority, cooldownDays: kind.defaultCooldownDays);

  factory AdvRuleDraft.of(AdvRule r) => AdvRuleDraft(
        kind: r.kind,
        params: Map.of(r.params),
        priority: r.priority,
        cooldownDays: r.cooldownDays,
        enabled: r.enabled,
        categoryId: r.category?.id == 0 ? null : r.category?.id,
        scope: r.scope ?? const AdvRuleScope(),
        nameAr: r.customName ? r.nameAr : '',
        nameEn: r.customName ? r.nameEn : '',
      );

  final String kind;
  final Map<String, Object?> params;
  final String priority;
  final int cooldownDays;
  final bool enabled;
  final int? categoryId;
  final AdvRuleScope scope;

  /// A custom name ('' = the kind's label).
  final String nameAr, nameEn;

  static const maxName = 120, maxCooldown = 365;

  AdvRuleDraft copyWith({
    Map<String, Object?>? params,
    String? priority,
    int? cooldownDays,
    bool? enabled,
    int? Function()? categoryId,
    AdvRuleScope? scope,
    String? nameAr,
    String? nameEn,
  }) =>
      AdvRuleDraft(
        kind: kind,
        params: params ?? this.params,
        priority: priority ?? this.priority,
        cooldownDays: cooldownDays ?? this.cooldownDays,
        enabled: enabled ?? this.enabled,
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        scope: scope ?? this.scope,
        nameAr: nameAr ?? this.nameAr,
        nameEn: nameEn ?? this.nameEn,
      );

  AdvRuleDraft withParam(String key, Object? v) => copyWith(params: {...params, key: v});

  /// Why it cannot be saved (checked against the catalog's limits), null when it can.
  String? error(AdvRuleKind? k) {
    if (k != null) {
      for (final p in k.params) {
        final why = p.check(params[p.key]);
        if (why != null) return why;
      }
    }
    if (cooldownDays < 0 || cooldownDays > maxCooldown) return t('فترة التهدئة بين 0 و365 يوماً', 'The cool-down is between 0 and 365 days');
    if (nameAr.trim().length > maxName || nameEn.trim().length > maxName) return t('الاسم 120 حرفاً على الأكثر', 'A name is at most 120 characters');
    return null;
  }

  /// The parameters the catalog knows, as they are sent ([k] null: every stored one).
  Map<String, dynamic> paramsBody(AdvRuleKind? k) =>
      k == null ? {for (final e in params.entries) e.key: e.value} : {for (final p in k.params) p.key: p.normalize(params[p.key])};

  /// [create]: the POST body (with `kind`).
  Map<String, dynamic> toJson(AdvRuleKind? k, {bool create = false}) => {
        if (create) 'kind': kind,
        'params': paramsBody(k),
        'priority': priority,
        'cooldown_days': cooldownDays,
        'enabled': enabled,
        'category_id': categoryId,
        'scope': scope.toJson(),
        'name_ar': nameAr.trim().isEmpty ? null : nameAr.trim(),
        'name_en': nameEn.trim().isEmpty ? null : nameEn.trim(),
      };

  /// The preview body: `{"kind","params","scope"}`.
  Map<String, dynamic> previewBody(AdvRuleKind? k) => {'kind': kind, 'params': paramsBody(k), 'scope': scope.toJson()};

  /// What changed from [r] (the editor asks before closing over unsaved changes).
  bool changedFrom(AdvRule? r, AdvRuleKind? k) {
    if (r == null) return true;
    return '${toJson(k)}' != '${AdvRuleDraft.of(r).toJson(k)}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The engine and its runs
// ═════════════════════════════════════════════════════════════════════════════

/// A run's counts (those that do not apply are 0).
class AdvWarningCounts {
  const AdvWarningCounts({
    this.students = 0,
    this.matched = 0,
    this.alerts = 0,
    this.suppressed = 0,
    this.flagsOpened = 0,
    this.flagsUpdated = 0,
    this.notified = 0,
    this.digestWaiting = 0,
    this.digests = 0,
    this.nudgesAdvisors = 0,
    this.nudgesStudents = 0,
  });

  final int students, matched, alerts, suppressed, flagsOpened, flagsUpdated, notified, digestWaiting, digests, nudgesAdvisors, nudgesStudents;

  factory AdvWarningCounts.fromJson(dynamic v) {
    final j = asMap(v);
    return AdvWarningCounts(
      students: asInt(j['students']),
      matched: asInt(j['matched']),
      alerts: asInt(j['alerts']),
      suppressed: asInt(j['suppressed']),
      flagsOpened: asInt(j['flags_opened']),
      flagsUpdated: asInt(j['flags_updated']),
      notified: asInt(j['notified']),
      digestWaiting: asInt(j['digest_waiting']),
      digests: asInt(j['digests']),
      nudgesAdvisors: asInt(j['nudges_advisors']),
      nudgesStudents: asInt(j['nudges_students']),
    );
  }
}

/// `Run` of the early-warning engine (an evaluation, or a digest / nudge pass).
class AdvWarningRun {
  const AdvWarningRun({
    required this.id,
    this.kind = 'evaluate',
    this.trigger = 'tick',
    this.status = 'running',
    this.actor,
    this.counts = const AdvWarningCounts(),
    this.error,
    this.startedAt,
    this.finishedAt,
    this.durationMs,
  });

  final int id;

  /// `evaluate` · `digest`.
  final String kind;

  /// `tick` · `manual` · `student` (one student's "Evaluate now").
  final String trigger;

  /// `running` · `done` · `failed`.
  final String status;
  final AdvRef? actor;
  final AdvWarningCounts counts;

  /// The error code of a failed run (`stale` for a run closed after 30 minutes).
  final String? error;
  final DateTime? startedAt, finishedAt;
  final int? durationMs;

  factory AdvWarningRun.fromJson(Map<String, dynamic> j) {
    final s = asStr(j['status'], 'running');
    final d = j['duration_ms'];
    return AdvWarningRun(
      id: asInt(j['id']),
      kind: asStr(j['kind']) == 'digest' ? 'digest' : 'evaluate',
      trigger: const ['manual', 'student'].contains(asStr(j['trigger'])) ? asStr(j['trigger']) : 'tick',
      status: const ['running', 'done', 'failed'].contains(s) ? s : 'running',
      actor: AdvRef.maybe(j['actor']),
      counts: AdvWarningCounts.fromJson(j['counts']),
      error: _text(j['error']),
      startedAt: orgParseUtc(j['started_at']),
      finishedAt: orgParseUtc(j['finished_at']),
      durationMs: d == null ? null : asInt(d),
    );
  }

  static AdvWarningRun? maybe(dynamic v) => v is Map && asInt(asMap(v)['id']) != 0 ? AdvWarningRun.fromJson(asMap(v)) : null;

  bool get running => status == 'running';
  bool get failed => status == 'failed';
  bool get done => status == 'done';
}

String advWarnRunStatusLabel(String s) => switch (s) {
      'done' => t('اكتمل', 'Done'),
      'failed' => t('تعذّر', 'Failed'),
      _ => t('قيد التشغيل', 'Running'),
    };

String advWarnRunKindLabel(String k) => k == 'digest' ? t('الملخصات والتذكيرات', 'Digests and nudges') : t('فحص القواعد', 'Rule check');

String advWarnRunTriggerLabel(String trig) => switch (trig) {
      'manual' => t('يدوياً', 'By hand'),
      'student' => t('لطالب واحد', 'One student'),
      _ => t('تلقائياً', 'Automatic'),
    };

/// Why a run failed, in words (`stale` = it stopped answering and was closed; anything else: the code itself).
String advWarnRunErrorText(String? code) => switch (code) {
      null || '' => '',
      'stale' => t('توقف التشغيل عن الاستجابة فأُغلق بعد 30 دقيقة — التشغيل التالي يعيد العمل', 'The run stopped answering and was closed after 30 minutes — the next run redoes the work'),
      _ => t('تعذّر إكمال التشغيل ($code) — التشغيل التالي يعيد ما لم يكتمل', 'The run could not finish ($code) — the next run redoes what is left'),
    };

/// "1.2 s" · "45 s" · "2 min".
String advDurationText(int? ms) {
  if (ms == null) return '';
  if (ms < 1000) return t('أقل من ثانية', 'under a second');
  final s = ms / 1000;
  if (s < 60) return t('${s < 10 ? s.toStringAsFixed(1) : s.round()} ث', '${s < 10 ? s.toStringAsFixed(1) : s.round()} s');
  final m = (s / 60).round();
  return t('$m د', '$m min');
}

/// The engine block of `GET …/rules`.
class AdvEngine {
  const AdvEngine({this.enabled = false, this.running, this.lastRun, this.nextRunAt});

  /// The organization's engine works (advising on, the kill switch on).
  final bool enabled;
  final AdvWarningRun? running, lastRun;
  final DateTime? nextRunAt;

  factory AdvEngine.fromJson(dynamic v) {
    final j = asMap(v);
    return AdvEngine(
      enabled: asBool(j['enabled']),
      running: AdvWarningRun.maybe(j['running']),
      lastRun: AdvWarningRun.maybe(j['last_run']),
      nextRunAt: orgParseUtc(j['next_run_at']),
    );
  }

  AdvEngine copyWith({AdvWarningRun? Function()? running, AdvWarningRun? Function()? lastRun}) => AdvEngine(
        enabled: enabled,
        running: running == null ? this.running : running(),
        lastRun: lastRun == null ? this.lastRun : lastRun(),
        nextRunAt: nextRunAt,
      );
}

/// `GET …/rules`: the rules, the kind catalog, the engine, whether I may edit.
class AdvRulesBundle {
  const AdvRulesBundle({this.rules = const [], this.kinds = const [], this.engine = const AdvEngine(), this.canEdit = false});

  final List<AdvRule> rules;
  final List<AdvRuleKind> kinds;
  final AdvEngine engine;
  final bool canEdit;

  factory AdvRulesBundle.fromJson(Map<String, dynamic> j) => AdvRulesBundle(
        rules: [for (final m in asMapList(j['items'])) AdvRule.fromJson(m)],
        kinds: [for (final m in asMapList(j['kinds'])) AdvRuleKind.fromJson(m)].where((k) => k.kind.isNotEmpty).toList(),
        engine: AdvEngine.fromJson(j['engine']),
        canEdit: asBool(j['can_edit']),
      );

  AdvRuleKind? kindOf(String kind) => kinds.where((k) => k.kind == kind).firstOrNull;

  /// The rules by kind, in the catalog's order (a kind the catalog no longer lists goes last); inside a kind the
  /// worst priority first.
  List<(String, List<AdvRule>)> get grouped {
    final order = [for (final k in kinds) k.kind, for (final r in rules) if (!kinds.any((k) => k.kind == r.kind)) r.kind];
    final seen = <String>{};
    return [
      for (final k in order)
        if (seen.add(k) && rules.any((r) => r.kind == k)) (k, [for (final r in rules) if (r.kind == k) r]..sort((a, b) => advPriorityRank(b.priority) - advPriorityRank(a.priority))),
    ];
  }

  int get enabledCount => rules.where((r) => r.enabled).length;

  AdvRulesBundle withRule(AdvRule r) => AdvRulesBundle(
        rules: [for (final x in rules) if (x.id == r.id) r else x, if (!rules.any((x) => x.id == r.id)) r],
        kinds: kinds,
        engine: engine,
        canEdit: canEdit,
      );

  AdvRulesBundle without(int id) => AdvRulesBundle(rules: [for (final x in rules) if (x.id != id) x], kinds: kinds, engine: engine, canEdit: canEdit);

  AdvRulesBundle withEngine(AdvEngine e) => AdvRulesBundle(rules: rules, kinds: kinds, engine: e, canEdit: canEdit);
}

/// The most rules an organization may hold (`advising_rule_limit`).
const advRuleLimit = 50;

/// One student of a preview's sample.
class AdvPreviewSample {
  const AdvPreviewSample({required this.memberId, this.name = '', this.code, this.explanation = const AdvText()});
  final int memberId;
  final String name;
  final String? code;
  final AdvText explanation;

  factory AdvPreviewSample.fromJson(Map<String, dynamic> j) =>
      AdvPreviewSample(memberId: asInt(j['member_id']), name: asStr(j['name']).trim(), code: _text(j['code']), explanation: AdvText.fromJson(j['explanation']));

  String get shown => name.isEmpty ? '#$memberId' : name;
}

/// `POST …/rules/preview`: evaluated over the facts of the last run, nothing written.
class AdvRulePreview {
  const AdvRulePreview({this.matches = 0, this.students = 0, this.evaluatedAt, this.needsRun = false, this.sample = const []});

  /// Students the draft matches now · students evaluated.
  final int matches, students;
  final DateTime? evaluatedAt;

  /// No stored facts yet: the engine has to run once first.
  final bool needsRun;
  final List<AdvPreviewSample> sample;

  factory AdvRulePreview.fromJson(Map<String, dynamic> j) => AdvRulePreview(
        matches: asInt(j['matches']),
        students: asInt(j['students']),
        evaluatedAt: orgParseUtc(j['evaluated_at']),
        needsRun: asBool(j['needs_run']),
        sample: [for (final m in asMapList(j['sample'])) AdvPreviewSample.fromJson(m)],
      );

  /// "12 of 340 students match now" · "No student matches now".
  String get headline {
    if (matches == 0) return t('لا يطابقها أي طالب الآن', 'No student matches now');
    final of = students > 0 ? t(' من $students', ' of $students') : '';
    return countText(matches,
        ar1: 'يطابقها طالب واحد$of الآن', ar2: 'يطابقها طالبان$of الآن', arFew: 'يطابقها $matches طلاب$of الآن', arMany: 'يطابقها $matches طالباً$of الآن',
        en1: '1 student$of matches now', en: '$matches students$of match now');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Alerts
// ═════════════════════════════════════════════════════════════════════════════

/// A term an alert or the 360 names: `{"id","label","kind"}`.
class AdvTermRef {
  const AdvTermRef({required this.id, this.label = '', this.kind = ''});
  final int id;
  final String label, kind;

  static AdvTermRef? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = asMap(v);
    return AdvTermRef(id: asInt(m['id']), label: asStr(m['label']).trim(), kind: asStr(m['kind']));
  }

  /// "First term 2025/2026" (the registrar's words), else the label.
  String get shown {
    final s = termTitle({'kind': kind, 'year_label': label});
    return s.isEmpty ? (label.isEmpty ? '#$id' : label) : s;
  }
}

/// How an alert reached the advisor: `urgent` (at once, advisors + directors) · `single` (a notice of its own) ·
/// `digest` (waits for the advisor's digest) · `none` (nobody to tell) · `pending` (not delivered yet).
const advDeliveries = ['urgent', 'single', 'digest', 'none', 'pending'];

String advDeliveryLabel(String d) => switch (d) {
      'urgent' => t('أُبلغ فوراً', 'Sent at once'),
      'single' => t('أُبلغ المرشد', 'Advisor told'),
      'digest' => t('في الملخص', 'In the digest'),
      'none' => t('لا أحد يُبلَّغ', 'Nobody to tell'),
      _ => t('بانتظار الإرسال', 'Not sent yet'),
    };

/// One alert of `GET …/alerts` (also the 360's `recent` and `GET …/flags/{id}/alerts`).
class AdvAlert {
  const AdvAlert({
    required this.id,
    required this.memberId,
    this.studentName = '',
    this.studentCode,
    this.rule = const AdvRuleRef(),
    this.priority = 'normal',
    this.level = 1,
    this.category,
    this.evidence = const {},
    this.explanation = const AdvText(),
    this.term,
    this.firedAt,
    this.flagId,
    this.flagStatus,
    this.delivery = 'pending',
  });

  final int id, memberId;
  final String studentName;
  final String? studentCode;
  final AdvRuleRef rule;
  final String priority;

  /// How far past the threshold (1 = just over it; higher = worse).
  final int level;
  final AdvCategory? category;

  /// The numbers as they were when the alert fired (kept for the record; the app shows [explanation]).
  final Map<String, dynamic> evidence;
  final AdvText explanation;
  final AdvTermRef? term;
  final DateTime? firedAt;

  /// The rule flag it opened or joined (null: none, e.g. an older server).
  final int? flagId;
  final String? flagStatus;
  final String delivery;

  factory AdvAlert.fromJson(Map<String, dynamic> j) {
    final student = asMap(j['student']);
    final flag = j['flag'];
    final f = flag is Map ? asMap(flag) : null;
    final d = asStr(j['delivery'], 'pending');
    return AdvAlert(
      id: asInt(j['id']),
      memberId: asInt(j['member_id']),
      studentName: asStr(student['name']).trim(),
      studentCode: _text(student['code']),
      rule: AdvRuleRef.fromJson(j['rule']),
      priority: _priority(j['priority']),
      level: asInt(j['level'], 1),
      category: AdvCategory.maybe(j['category']),
      evidence: asMap(j['evidence']),
      explanation: AdvText.fromJson(j['explanation']),
      term: AdvTermRef.maybe(j['term']),
      firedAt: orgParseUtc(j['fired_at']),
      flagId: f == null || f['id'] == null ? null : asInt(f['id']),
      flagStatus: f == null ? null : _text(f['status']),
      delivery: advDeliveries.contains(d) ? d : 'pending',
    );
  }

  String get studentShown => studentName.isEmpty ? '#$memberId' : studentName;

  /// The explanation in the app language; an alert without one (an older server) says what its rule's kind checks.
  String get explanationText => advExplanation(explanation, rule.kind);
}

/// [e] in the app language, else the kind's fallback sentence (adv_texts.dart).
String advExplanation(AdvText e, String kind) => e.isEmpty ? advWarningKindFallback(kind) : e.shown;

/// The alerts list's filters (ONE filter control: priority, rule, since; the student comes from a deep link).
class AdvAlertQuery {
  const AdvAlertQuery({this.memberId, this.ruleId, this.priority, this.since, this.flag = 'all', this.page = 1, this.size = 25});

  final int? memberId, ruleId;
  final String? priority;
  final DateTime? since;

  /// `open` · `closed` · `all` (the alert's flag).
  final String flag;
  final int page, size;

  AdvAlertQuery copyWith({
    int? Function()? memberId,
    int? Function()? ruleId,
    String? Function()? priority,
    DateTime? Function()? since,
    String? flag,
    int? page,
  }) =>
      AdvAlertQuery(
        memberId: memberId == null ? this.memberId : memberId(),
        ruleId: ruleId == null ? this.ruleId : ruleId(),
        priority: priority == null ? this.priority : priority(),
        since: since == null ? this.since : since(),
        flag: flag ?? this.flag,
        page: page ?? this.page,
        size: size,
      );

  int get activeFilters => [memberId, ruleId, priority, since].where((x) => x != null).length + (flag == 'all' ? 0 : 1);

  Map<String, dynamic> toQuery() => {
        'member_id': ?memberId,
        'rule_id': ?ruleId,
        'priority': ?priority,
        if (since != null) 'since': orgUtc(since),
        'flag': flag,
        'page': page,
        'size': size,
      };
}

/// The "since" choices of the alerts filter, in days (0 = any time).
const advSinceDays = [0, 1, 7, 30];

String advSinceLabel(int days) => switch (days) {
      0 => t('أي وقت', 'Any time'),
      1 => t('آخر 24 ساعة', 'Last 24 hours'),
      7 => t('آخر 7 أيام', 'Last 7 days'),
      _ => t('آخر $days يوماً', 'Last $days days'),
    };

const advAlertFlagViews = ['all', 'open', 'closed'];

String advAlertFlagViewLabel(String v) => switch (v) {
      'open' => t('تنبيهها مفتوح', 'Flag open'),
      'closed' => t('تنبيهها مغلق', 'Flag closed'),
      _ => t('الكل', 'All'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Graduation
// ═════════════════════════════════════════════════════════════════════════════

const advGraduationStatuses = ['delayed', 'at_risk', 'on_track', 'graduated', 'unknown'];

String advGraduationStatusLabel(String s) => switch (s) {
      'delayed' => t('متأخر عن التخرج', 'Delayed'),
      'at_risk' => t('معرّض للتأخر', 'At risk'),
      'on_track' => t('في موعده', 'On track'),
      'graduated' => t('متخرج', 'Graduated'),
      _ => t('غير معروف', 'Unknown'),
    };

/// Why the projection is unknown.
String advGraduationReasonText(String? r) => switch (r) {
      'no_program' => t('لا برنامج مسجّل للطالب، فلا يُعرف ما يحتاجه للتخرج.', 'The student has no program, so what they need to graduate is not known.'),
      'no_total' => t('لم تُحدَّد ساعات التخرج لبرنامج الطالب.', 'The student\'s program has no credit total set.'),
      'no_terms' => t('لا فصول دراسية مسجّلة بعد لحساب التقدم.', 'No terms are recorded yet to measure progress.'),
      'no_level' => t('لا مستوى دراسي مسجّل للطالب في برنامج الفرق الدراسية.', 'The student has no level recorded in a year-based program.'),
      _ => t('لا تتوفر بيانات كافية لتقدير موعد التخرج.', 'There is not enough data to project graduation.'),
    };

/// A course the graduation card lists: failed and not passed since (`attempts`), or a required course of a lower
/// level neither passed nor taken now (`level`).
class AdvGradCourse {
  const AdvGradCourse({this.courseId, this.code, this.nameAr = '', this.nameEn = '', this.credits, this.attempts, this.level});
  final int? courseId;
  final String? code;
  final String nameAr, nameEn;
  final double? credits;
  final int? attempts;
  final String? level;

  factory AdvGradCourse.fromJson(Map<String, dynamic> j) => AdvGradCourse(
        courseId: j['course_id'] == null ? null : _int(j['course_id']),
        code: _text(j['code']),
        nameAr: asStr(j['name_ar']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        credits: _num(j['credits']),
        attempts: j['attempts'] == null ? null : _int(j['attempts']),
        level: _text(j['level']),
      );

  /// The name in the app language, else the other one, else the code.
  String get name {
    final s = t(nameAr, nameEn);
    if (s.isNotEmpty) return s;
    final other = nameAr.isNotEmpty ? nameAr : nameEn;
    return other.isNotEmpty ? other : (code ?? '#${courseId ?? ''}');
  }
}

/// The graduation projection (`graduation.py`).
class AdvGraduation {
  const AdvGraduation({
    this.status = 'unknown',
    this.basis,
    this.reason,
    this.earned,
    this.inProgress,
    this.total,
    this.termsDone,
    this.plannedTerms,
    this.projectedTerms,
    this.delayTerms,
    this.neededPerTerm,
    this.maxLoad,
    this.level,
    this.expectedLevel,
    this.remaining,
    this.failedCount = 0,
    this.delayedCount = 0,
    this.failedCourses = const [],
    this.delayedCourses = const [],
  });

  /// `on_track` · `at_risk` · `delayed` · `graduated` · `unknown`.
  final String status;

  /// `credits` · `levels` · null (unknown).
  final String? basis;

  /// `no_program` · `no_total` · `no_terms` · `no_level` (unknown only).
  final String? reason;

  /// Credits still to earn after this term's registered ones (credit programs).
  final double? remaining;

  /// Failed courses not passed since · required courses of a lower level neither passed nor taken now.
  final int failedCount, delayedCount;

  /// Their lists (the 360 only; the graduation list sends the counts).
  final List<AdvGradCourse> failedCourses, delayedCourses;
  final double? earned, inProgress, total, neededPerTerm, maxLoad;
  final int? termsDone, plannedTerms, projectedTerms, delayTerms;

  /// Level programs: the member's level and the one expected by now.
  final String? level, expectedLevel;

  factory AdvGraduation.fromJson(Map<String, dynamic> j) {
    final s = asStr(j['status'], 'unknown');
    final b = asStr(j['basis']);
    return AdvGraduation(
      status: advGraduationStatuses.contains(s) ? s : 'unknown',
      basis: b == 'credits' || b == 'levels' ? b : null,
      reason: _text(j['reason']),
      earned: _num(j['earned']),
      inProgress: _num(j['in_progress']),
      total: _num(j['total']),
      termsDone: _int(j['terms_done']),
      plannedTerms: _int(j['planned_terms']),
      projectedTerms: _int(j['projected_terms']),
      delayTerms: _int(j['delay_terms']),
      neededPerTerm: _num(j['needed_per_term']),
      maxLoad: _num(j['max_load']),
      level: _text(j['level']),
      expectedLevel: _text(j['expected_level']),
      remaining: _num(j['remaining']),
      failedCount: asInt(j['failed_count']),
      delayedCount: asInt(j['delayed_count']),
      failedCourses: [for (final m in asMapList(j['failed_courses'])) AdvGradCourse.fromJson(m)],
      delayedCourses: [for (final m in asMapList(j['delayed_courses'])) AdvGradCourse.fromJson(m)],
    );
  }

  static AdvGraduation? maybe(dynamic v) => v is Map ? AdvGraduation.fromJson(asMap(v)) : null;

  bool get known => status != 'unknown';
  bool get credits => basis == 'credits';

  /// Earned out of the total, 0 – 1 (null without both).
  double? get progress {
    final e = earned, tot = total;
    if (e == null || tot == null || tot <= 0) return null;
    return (e / tot).clamp(0.0, 1.0);
  }

  /// The earned credits plus those in progress, 0 – 1 (the bar's lighter part).
  double? get progressWithCurrent {
    final e = earned, tot = total;
    if (e == null || tot == null || tot <= 0) return null;
    return ((e + (inProgress ?? 0)) / tot).clamp(0.0, 1.0);
  }

  /// "Needs 18 credits a term" (credit programs at risk / on track with a number).
  String? get neededText {
    final n = neededPerTerm;
    if (n == null || !credits || status == 'graduated') return null;
    final s = advWhole(n);
    return t('يحتاج $s ساعة في كل فصل متبقٍ', 'Needs $s credits each remaining term');
  }

  /// "3 terms late" · null when not delayed.
  String? get delayText {
    final d = delayTerms;
    if (d == null || d <= 0) return null;
    return countText(d, ar1: 'متأخر فصلاً واحداً', ar2: 'متأخر فصلين', arFew: 'متأخر $d فصول', arMany: 'متأخر $d فصلاً', en1: '1 term late', en: '$d terms late');
  }
}

/// One student of `GET …/graduation`.
class AdvGraduationItem {
  const AdvGraduationItem({required this.memberId, this.name = '', this.code, this.program, this.level, this.primary, this.graduation = const AdvGraduation()});

  final int memberId;
  final String name;
  final String? code, program, level;
  final AdvRef? primary;
  final AdvGraduation graduation;

  factory AdvGraduationItem.fromJson(Map<String, dynamic> j) => AdvGraduationItem(
        memberId: asInt(j['member_id']),
        name: asStr(j['name']).trim(),
        code: _text(j['code']),
        program: _text(j['program']),
        level: _text(j['level']),
        primary: AdvRef.maybe(j['primary']),
        graduation: AdvGraduation.maybe(j['graduation']) ?? const AdvGraduation(),
      );

  String get shown => name.isEmpty ? '#$memberId' : name;
}

/// The graduation list's filter: `delayed` · `at_risk` · `all`.
const advGraduationViews = ['delayed', 'at_risk', 'all'];

String advGraduationViewLabel(String v) => switch (v) {
      'delayed' => t('المتأخرون', 'Delayed'),
      'at_risk' => t('المعرّضون للتأخر', 'At risk'),
      _ => t('الكل', 'All'),
    };

class AdvGraduationQuery {
  const AdvGraduationQuery({this.status = 'all', this.programId, this.level, this.q = '', this.page = 1, this.size = 25});
  final String status;
  final int? programId;
  final String? level;
  final String q;
  final int page, size;

  AdvGraduationQuery copyWith({String? status, String? q, int? page}) =>
      AdvGraduationQuery(status: status ?? this.status, programId: programId, level: level, q: q ?? this.q, page: page ?? this.page, size: size);

  Map<String, dynamic> toQuery() => {
        'status': status,
        'program_id': ?programId,
        'level': ?level,
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'size': size,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  The student 360's "Early warning"
// ═════════════════════════════════════════════════════════════════════════════

/// A rule the student matches NOW (also one held back by its cool-down: [alertId] null).
class AdvWarningHit {
  const AdvWarningHit({this.rule = const AdvRuleRef(), this.priority = 'normal', this.level = 1, this.explanation = const AdvText(), this.evidence = const {}, this.alertId});

  final AdvRuleRef rule;
  final String priority;
  final int level;
  final AdvText explanation;
  final Map<String, dynamic> evidence;

  /// The alert that told the advisor (null: held back by the cool-down, already told earlier).
  final int? alertId;

  factory AdvWarningHit.fromJson(Map<String, dynamic> j) => AdvWarningHit(
        rule: AdvRuleRef.fromJson(j['rule']),
        priority: _priority(j['priority']),
        level: asInt(j['level'], 1),
        explanation: AdvText.fromJson(j['explanation']),
        evidence: asMap(j['evidence']),
        alertId: j['alert_id'] == null ? null : asInt(j['alert_id']),
      );

  String get explanationText => advExplanation(explanation, rule.kind);
}

/// `GET …/students/{member_id}/warning` (also the answer of "Evaluate now").
class AdvWarning {
  const AdvWarning({this.evaluatedAt, this.term, this.hits = const [], this.graduation, this.recent = const [], this.restricted = 0, this.canRun = false});

  /// null: the engine has not looked at this student yet.
  final DateTime? evaluatedAt;
  final AdvTermRef? term;
  final List<AdvWarningHit> hits;
  final AdvGraduation? graduation;
  final List<AdvAlert> recent;

  /// Alerts the caller may not read (sensitive category), only counted.
  final int restricted;
  final bool canRun;

  factory AdvWarning.fromJson(Map<String, dynamic> j) => AdvWarning(
        evaluatedAt: orgParseUtc(j['evaluated_at']),
        term: AdvTermRef.maybe(j['term']),
        hits: [for (final m in asMapList(j['hits'])) AdvWarningHit.fromJson(m)]..sort((a, b) => advPriorityRank(b.priority) - advPriorityRank(a.priority)),
        graduation: AdvGraduation.maybe(j['graduation']),
        recent: [for (final m in asMapList(j['recent'])) AdvAlert.fromJson(m)],
        restricted: asInt(j['restricted']),
        canRun: asBool(asMap(j['can'])['run']),
      );

  bool get evaluated => evaluatedAt != null;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Alert delivery (the advisor's digest choice) and the settings group
// ═════════════════════════════════════════════════════════════════════════════

/// `inherit` (the organization's default) · `off` (one notice per run) · `daily` · `weekly`.
const advDigestChoices = ['inherit', 'off', 'daily', 'weekly'];

String advDigestLabel(String d) => switch (d) {
      'inherit' => t('حسب إعداد المؤسسة', 'The organization\'s default'),
      'daily' => t('ملخص يومي', 'Daily digest'),
      'weekly' => t('ملخص أسبوعي', 'Weekly digest'),
      _ => t('إشعار مع كل فحص', 'A notice after each check'),
    };

String advDigestHint(String d) => switch (d) {
      'daily' => t('رسالة واحدة كل صباح بالتنبيهات الجديدة لطلابك', 'One message each morning with your students\' new alerts'),
      'weekly' => t('رسالة واحدة في الأسبوع بالتنبيهات الجديدة لطلابك', 'One message a week with your students\' new alerts'),
      'off' => t('إشعار بعد كل فحص فيه تنبيهات جديدة لطلابك', 'A notice after every check that finds new alerts for your students'),
      _ => '',
    };

/// 0 = Monday … 6 = Sunday (the server's `digest_weekday`).
String advWeekdayLabel(int d) => switch (d) {
      0 => t('الاثنين', 'Monday'),
      1 => t('الثلاثاء', 'Tuesday'),
      2 => t('الأربعاء', 'Wednesday'),
      3 => t('الخميس', 'Thursday'),
      4 => t('الجمعة', 'Friday'),
      5 => t('السبت', 'Saturday'),
      _ => t('الأحد', 'Sunday'),
    };

/// `GET …/alerts/prefs`.
class AdvAlertPrefs {
  const AdvAlertPrefs({this.digest = 'inherit', this.effective = 'off', this.orgDefault = 'off', this.digestHour = 7, this.digestWeekday = 6, this.timezone, this.lastDigestAt});

  final String digest, effective, orgDefault;
  final int digestHour, digestWeekday;
  final String? timezone;
  final DateTime? lastDigestAt;

  factory AdvAlertPrefs.fromJson(Map<String, dynamic> j) {
    String pick(dynamic v, String fb, {bool inherit = false}) {
      final s = asStr(v);
      return (inherit ? advDigestChoices : advDigestChoices.skip(1)).contains(s) ? s : fb;
    }

    return AdvAlertPrefs(
      digest: pick(j['digest'], 'inherit', inherit: true),
      effective: pick(j['effective'], 'off'),
      orgDefault: pick(j['org_default'], 'off'),
      digestHour: asInt(j['digest_hour'], 7).clamp(0, 23),
      digestWeekday: asInt(j['digest_weekday'], 6).clamp(0, 6),
      timezone: _text(j['timezone']),
      lastDigestAt: orgParseUtc(j['last_digest_at']),
    );
  }
}

/// The settings fields of the group "Alerts and nudges" (Phase 6 additions to `AdvisingPolicy`, plus `digest`).
const advAlertPolicyFields = ['digest', 'digest_hour', 'digest_weekday', 'nudge_after_days', 'nudge_advisors', 'nudge_students'];

/// The fields a department / program / level / cohort row may set: students' nudges read the student's scope;
/// digests and advisors' nudges read the organization's row only.
const advAlertScopeFields = ['nudge_students', 'nudge_after_days'];

/// The defaults of [advAlertPolicyFields] (the server's `AdvisingPolicy`).
const advAlertPolicyDefaults = <String, dynamic>{
  'digest': 'off',
  'digest_hour': 7,
  'digest_weekday': 6,
  'nudge_after_days': 21,
  'nudge_advisors': true,
  'nudge_students': true,
};

/// The values the group shows for one scope: its own settings over what it inherits.
class AdvAlertSettings {
  const AdvAlertSettings({this.digest = 'off', this.digestHour = 7, this.digestWeekday = 6, this.nudgeAfterDays = 21, this.nudgeAdvisors = true, this.nudgeStudents = true});

  final String digest;
  final int digestHour, digestWeekday, nudgeAfterDays;
  final bool nudgeAdvisors, nudgeStudents;

  factory AdvAlertSettings.fromMap(Map<String, dynamic> m) {
    dynamic v(String f) => m.containsKey(f) && m[f] != null ? m[f] : advAlertPolicyDefaults[f];
    final d = asStr(v('digest'));
    return AdvAlertSettings(
      digest: const ['off', 'daily', 'weekly'].contains(d) ? d : 'off',
      digestHour: asInt(v('digest_hour'), 7).clamp(0, 23),
      digestWeekday: asInt(v('digest_weekday'), 6).clamp(0, 6),
      nudgeAfterDays: asInt(v('nudge_after_days'), 21).clamp(1, 120),
      nudgeAdvisors: asBool(v('nudge_advisors'), true),
      nudgeStudents: asBool(v('nudge_students'), true),
    );
  }

  /// [policy]'s values (its `raw`, where later phases' fields live).
  factory AdvAlertSettings.of(AdvPolicy policy) => AdvAlertSettings.fromMap(policy.raw);

  dynamic value(String field) => switch (field) {
        'digest' => digest,
        'digest_hour' => digestHour,
        'digest_weekday' => digestWeekday,
        'nudge_after_days' => nudgeAfterDays,
        'nudge_advisors' => nudgeAdvisors,
        _ => nudgeStudents,
      };
}

/// What a scope inherits for the group's fields: the organization's effective settings for a scope row; for the
/// organization itself, the default of a field it sets (what it falls back to) and the effective value of one it
/// does not.
AdvAlertSettings advAlertInherited(AdvPolicyBundle b, String scopeType) {
  if (scopeType != 'org') return AdvAlertSettings.of(b.effective);
  return AdvAlertSettings.fromMap({
    for (final f in advAlertPolicyFields) f: b.orgSettings.containsKey(f) ? (b.defaults.raw[f] ?? advAlertPolicyDefaults[f]) : b.effective.raw[f],
  });
}

/// The group's values for a scope: [settings] (the draft's own) over [inherited].
AdvAlertSettings advAlertShown(AdvAlertSettings inherited, Map<String, dynamic> settings) =>
    AdvAlertSettings.fromMap({for (final f in advAlertPolicyFields) f: settings.containsKey(f) ? settings[f] : inherited.value(f)});

/// Why the group's own values cannot be saved, null when they can.
String? advAlertSettingsError(Map<String, dynamic> settings) {
  bool out(String f, int lo, int hi) => settings.containsKey(f) && settings[f] != null && (asInt(settings[f], -1) < lo || asInt(settings[f], -1) > hi);
  if (out('digest_hour', 0, 23)) return t('ساعة الإرسال بين 0 و23', 'The sending hour is between 0 and 23');
  if (out('digest_weekday', 0, 6)) return t('اختر يوم الملخص الأسبوعي', 'Choose the weekly digest\'s day');
  if (out('nudge_after_days', 1, 120)) return t('بدء التذكير بين 1 و120 يوماً من بداية الفصل', 'Nudges start between 1 and 120 days into the term');
  return null;
}
