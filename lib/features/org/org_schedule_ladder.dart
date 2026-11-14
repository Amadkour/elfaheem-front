// lib/features/org/org_schedule_ladder.dart — the relaxation LADDER: the pure side of the "perfect timetable"
// generator (docs/backend/ladder-spec.md, server services/organization/schedule_ladder.py).
//
// A ladder is an ordered list of rungs {key, mode}: the order is the priority (first = cheapest to break), the mode
// is auto (break and log) · ask (pause and ask the creator) · locked (never). `free_moves` is always first and auto.
//
//   ladderRungKeys / ladderModes / ladderDefault   the server constants (RUNG_KEYS, MODES, DEFAULT_LADDER)
//   rungName / rungWhy / ladderText                a Dart copy of the server's TEXT map (name + why, ar + en)
//   LadderRung · LadderCatalogRung · LadderFixedRule · LadderOptions · LadderPreset
//   LadderConfig                                   GET …/ladder: the timetable's ladder, the catalog, the options and
//                                                  the organization's presets; moveRung / setMode / resetToDefault /
//                                                  toBody (PUT …/ladder)
//   LadderDecision · LadderOption · LadderImpact   run.summary.decision while the run status is `waiting`
//   impactText                                     one line: "places 12 more · breaks 3 rules · 2 people"
//   LadderLive                                     run.summary.ladder_live (+ steps[] as LiveStep, + the decision)
//   LadderReport · LadderRungResult · LadderDecisionRecord · LadderBlocked · LadderStructural · LadderProof
//                                                  result.ladder — what every rung did, the decisions, which locked
//                                                  rung would complete the timetable, the structural additions, the
//                                                  two-pass proof; summaryText()
//   brokenRuleLine / ladderStatusText              result.broken[] items and the report status as text
//   ladderHeadline · orderedOptions · rungResultText · rungSkippedText · decisionByText · pendingBlockIds
//                                                  the texts and orderings the widgets (org_schedule_ladder_ui.dart) share
//
// Everything here is plain Dart (tested in test/org/org_schedule_ladder_test.dart); the API calls live on
// OrgScheduleProvider (org_providers.dart: loadLadder · saveLadder · savePreset · deletePreset · startLadder · decide).
library;

import '../admin/admin_common.dart';
import 'org_schedule_generate.dart' show LiveStep;

// ═════════════════════════════════════════════════════════════════════════════
//  Constants (schedule_ladder.RUNG_KEYS / MODES / DEFAULT_LADDER / TEXT / DEFAULTS)
// ═════════════════════════════════════════════════════════════════════════════

const ladderRungKeys = [
  'free_moves',
  'ta_limits',
  'doctor_limits',
  'rooms',
  'split_groups',
  'open_times',
  'student_times',
  'capacity',
  'student_clash',
];

const ladderModes = ['auto', 'ask', 'locked'];

/// The server's default ladder, in order.
const ladderDefault = [
  ('free_moves', 'auto'),
  ('ta_limits', 'auto'),
  ('doctor_limits', 'auto'),
  ('rooms', 'auto'),
  ('split_groups', 'auto'),
  ('open_times', 'ask'),
  ('student_times', 'ask'),
  ('capacity', 'locked'),
  ('student_clash', 'locked'),
];

/// key → (name ar, name en, why ar, why en) — the same strings as the server's TEXT.
const ladderText = <String, (String, String, String, String)>{
  'free_moves': (
    'تحريك الحصص فقط',
    'Free moves only',
    'يُحاول كل ترتيب ممكن للأيام والفترات والقاعات دون كسر أي قاعدة',
    'Every arrangement of days, periods and rooms is tried without breaking any rule',
  ),
  'ta_limits': (
    'حدود المعيدين',
    'TA limits',
    'يسمح لمعيد بحصة خارج أوقاته المتاحة أو فوق حده اليومي / الأسبوعي',
    'A TA may teach outside their available times or over their daily / weekly cap',
  ),
  'doctor_limits': (
    'حدود الدكاترة',
    'Doctor limits',
    'يسمح لدكتور بحصة خارج أوقاته المتاحة أو فوق حده اليومي / الأسبوعي',
    'A doctor may teach outside their available times or over their daily / weekly cap',
  ),
  'rooms': (
    'القاعات',
    'Rooms',
    'قاعة خارج أوقاتها، أو قاعة من نوع آخر لحصة نظرية، أو فتح قاعة / معمل جديد',
    'A room outside its times, another kind of hall for a theory session, or a new room / lab',
  ),
  'split_groups': (
    'تقسيم المجموعات',
    'Split groups',
    'تقسيم مجموعة كبيرة إلى مجموعتين أو أكثر بنفس المدرّس',
    'A large group is split into two or more groups taught by the same staff',
  ),
  'open_times': (
    'فتح أوقات جديدة',
    'Open new times',
    'إضافة فترة بعد آخر فترة، ثم يوم دراسي جديد',
    'A period after the last one, then a new teaching day',
  ),
  'student_times': (
    'أوقات الطلاب',
    'Student times',
    'حصة في وقت لم يُتَح للطلاب أو وهم مشغولون في جدول مفعّل آخر',
    'A session when the students were not available or are busy in another active timetable',
  ),
  'capacity': (
    'تجاوز السعة',
    'Over capacity',
    'قاعة بعدد طلاب يزيد عن سعتها بنسبة محدودة',
    'A room with more students than seats, up to a limited percentage',
  ),
  'student_clash': (
    'تعارض الطلاب',
    'Student clash',
    'طلاب في حصتين في الوقت نفسه — لا يُنصح به',
    'Students in two sessions at the same time — not recommended',
  ),
};

/// The rules that are never on the ladder (schedule_ladder.FIXED_RULES), for a catalog an older server lacks.
const ladderFixedDefault = [
  ('person_double', 'لا عضو في حصتين معاً', 'No one teaches two sessions at once'),
  ('room_double', 'لا قاعة لحصتين معاً', 'No room hosts two sessions at once'),
  ('course_overlap', 'حصص المقرر الواحد لا تتداخل', 'A course\'s own sessions never overlap'),
  ('lab_only', 'المعمل في معمل مجهّز دائماً', 'A lab always sits in an equipped lab'),
  ('doctor_or_ta', 'المقرر لدكتور فقط أو معيد فقط', 'A course is a doctor\'s or a TA\'s, never both'),
];

/// A rung's name in the current language ("stop" is the decision's "stop here" option; an unknown key is shown as is).
String rungName(String? key) {
  if (key == null || key.isEmpty) return '';
  if (key == 'stop') return t('التوقف هنا', 'stop here');
  final x = ladderText[key];
  return x == null ? key.replaceAll('_', ' ') : t(x.$1, x.$2);
}

/// What a rung allows, in the current language.
String rungWhy(String? key) {
  final x = ladderText[key];
  return x == null ? '' : t(x.$3, x.$4);
}

String _modeOk(dynamic v) {
  final m = '${v ?? 'auto'}';
  return ladderModes.contains(m) ? m : 'auto';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Ladder model
// ═════════════════════════════════════════════════════════════════════════════

class LadderRung {
  const LadderRung(this.key, this.mode);
  final String key;
  final String mode; // auto · ask · locked

  String get name => rungName(key);
  String get why => rungWhy(key);
  bool get locked => mode == 'locked';
  bool get asks => mode == 'ask';

  factory LadderRung.of(Map<String, dynamic> m) => LadderRung('${m['key'] ?? ''}', _modeOk(m['mode']));
  Map<String, dynamic> toJson() => {'key': key, 'mode': mode};
  LadderRung withMode(String m) => LadderRung(key, _modeOk(m));
}

/// One rung of the catalog (schedule_ladder.catalog().rungs[]).
class LadderCatalogRung {
  const LadderCatalogRung({required this.key, required this.nameAr, required this.nameEn, required this.whyAr, required this.whyEn, this.defaultMode = 'auto'});
  final String key, nameAr, nameEn, whyAr, whyEn, defaultMode;

  String get name => t(nameAr, nameEn);
  String get why => t(whyAr, whyEn);

  factory LadderCatalogRung.of(Map<String, dynamic> m) {
    final key = '${m['key'] ?? ''}';
    final x = ladderText[key];
    return LadderCatalogRung(
      key: key,
      nameAr: '${m['name_ar'] ?? x?.$1 ?? m['name_en'] ?? key}',
      nameEn: '${m['name_en'] ?? x?.$2 ?? m['name_ar'] ?? key}',
      whyAr: '${m['why_ar'] ?? x?.$3 ?? m['why_en'] ?? ''}',
      whyEn: '${m['why_en'] ?? x?.$4 ?? m['why_ar'] ?? ''}',
      defaultMode: _modeOk(m['default_mode']),
    );
  }

  /// The built-in catalog, for an older server (or before the first load).
  static List<LadderCatalogRung> get builtin => [
        for (final (k, mode) in ladderDefault)
          LadderCatalogRung(key: k, nameAr: ladderText[k]!.$1, nameEn: ladderText[k]!.$2, whyAr: ladderText[k]!.$3, whyEn: ladderText[k]!.$4, defaultMode: mode),
      ];
}

/// A rule that is never on the ladder (catalog().fixed[]).
class LadderFixedRule {
  const LadderFixedRule(this.key, this.ar, this.en);
  final String key, ar, en;
  String get text => t(ar, en);

  factory LadderFixedRule.of(Map<String, dynamic> m) => LadderFixedRule('${m['key'] ?? ''}', '${m['ar'] ?? m['en'] ?? ''}', '${m['en'] ?? m['ar'] ?? ''}');
  static List<LadderFixedRule> get builtin => [for (final (k, ar, en) in ladderFixedDefault) LadderFixedRule(k, ar, en)];
}

/// The numeric knobs (settings.ladder_options; schedule_ladder.DEFAULTS).
class LadderOptions {
  const LadderOptions({
    this.budgetS = 1200,
    this.solveS,
    this.decisionTimeoutS = 900,
    this.overflowPct = 10,
    this.maxNewPeriods = 2,
    this.maxNewDays = 1,
    this.maxNewRooms = 6,
    this.forkOptions = 3,
    this.deterministic = false,
  });
  final int budgetS; // the whole run, seconds (30..7200)
  final int? solveS; // one solve, seconds (3..600); null = scaled to the problem
  final int decisionTimeoutS; // an unanswered decision is applied automatically after this
  final int overflowPct; // the `capacity` rung: seats over capacity, %
  final int maxNewPeriods, maxNewDays, maxNewRooms; // what `open_times` / `rooms` may add
  final int forkOptions; // options per decision (1..4)
  final bool deterministic; // same input + seed → the same timetable (one-thread search, slower)

  factory LadderOptions.of(Map<String, dynamic> m) {
    const d = LadderOptions();
    return LadderOptions(
      budgetS: asInt(m['budget_s'], d.budgetS),
      solveS: m['solve_s'] == null ? null : asInt(m['solve_s']),
      decisionTimeoutS: asInt(m['decision_timeout_s'], d.decisionTimeoutS),
      overflowPct: asInt(m['overflow_pct'], d.overflowPct),
      maxNewPeriods: asInt(m['max_new_periods'], d.maxNewPeriods),
      maxNewDays: asInt(m['max_new_days'], d.maxNewDays),
      maxNewRooms: asInt(m['max_new_rooms'], d.maxNewRooms),
      forkOptions: asInt(m['fork_options'], d.forkOptions),
      deterministic: m['deterministic'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'budget_s': budgetS,
        'solve_s': solveS,
        'decision_timeout_s': decisionTimeoutS,
        'overflow_pct': overflowPct,
        'max_new_periods': maxNewPeriods,
        'max_new_days': maxNewDays,
        'max_new_rooms': maxNewRooms,
        'fork_options': forkOptions,
        'deterministic': deterministic,
      };

  LadderOptions copyWith({int? budgetS, int? solveS, bool clearSolveS = false, int? decisionTimeoutS, int? overflowPct, int? maxNewPeriods, int? maxNewDays, int? maxNewRooms, int? forkOptions, bool? deterministic}) =>
      LadderOptions(
        budgetS: budgetS ?? this.budgetS,
        solveS: clearSolveS ? null : (solveS ?? this.solveS),
        decisionTimeoutS: decisionTimeoutS ?? this.decisionTimeoutS,
        overflowPct: overflowPct ?? this.overflowPct,
        maxNewPeriods: maxNewPeriods ?? this.maxNewPeriods,
        maxNewDays: maxNewDays ?? this.maxNewDays,
        maxNewRooms: maxNewRooms ?? this.maxNewRooms,
        forkOptions: forkOptions ?? this.forkOptions,
        deterministic: deterministic ?? this.deterministic,
      );
}

/// A saved ladder of the organization (settings.timetable_ladder_presets[]).
class LadderPreset {
  const LadderPreset({required this.id, required this.name, required this.ladder, required this.options});
  final String id, name;
  final List<LadderRung> ladder;
  final LadderOptions options;

  factory LadderPreset.of(Map<String, dynamic> m) => LadderPreset(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        ladder: normalizeLadder([for (final x in asMapList(m['ladder'])) LadderRung.of(x)]),
        options: LadderOptions.of(asMap(m['options'])),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ladder': [for (final r in ladder) r.toJson()], 'options': options.toJson()};
}

/// A complete, ordered ladder from any partial list — the server's `normalize`: unknown keys dropped, duplicates
/// dropped, missing rungs appended in the default order, `free_moves` always first and auto.
List<LadderRung> normalizeLadder(List<LadderRung> raw) {
  final out = <LadderRung>[];
  final seen = <String>{};
  for (final r in raw) {
    if (!ladderRungKeys.contains(r.key) || seen.contains(r.key)) continue;
    seen.add(r.key);
    out.add(LadderRung(r.key, _modeOk(r.mode)));
  }
  for (final (k, mode) in ladderDefault) {
    if (!seen.contains(k)) out.add(LadderRung(k, mode));
  }
  return [
    const LadderRung('free_moves', 'auto'),
    for (final r in out)
      if (r.key != 'free_moves') r,
  ];
}

/// GET …/schedules/{sid}/ladder: `{ladder, options, catalog: {rungs, fixed, modes, default, options}, presets,
/// version?}` (the catalog keys are also accepted at the top level). Immutable: every operation returns a new config.
class LadderConfig {
  const LadderConfig({
    this.ladder = const [],
    this.rungs = const [],
    this.fixed = const [],
    this.modes = ladderModes,
    this.defaultLadder = const [],
    this.options = const LadderOptions(),
    this.presets = const [],
    this.version,
  });
  final List<LadderRung> ladder; // the timetable's ladder, in priority order
  final List<LadderCatalogRung> rungs; // the catalog (every rung the server knows)
  final List<LadderFixedRule> fixed; // never on the ladder
  final List<String> modes;
  final List<LadderRung> defaultLadder;
  final LadderOptions options;
  final List<LadderPreset> presets;
  final int? version; // the timetable's version, when the server sends it (expected_version of the PUT)

  factory LadderConfig.of(Map<String, dynamic> m) {
    final cat = asMap(m['catalog']);
    dynamic catOr(String k) => cat[k] ?? m[k];
    final rungs = [for (final x in asMapList(catOr('rungs'))) LadderCatalogRung.of(x)];
    final fixed = [for (final x in asMapList(catOr('fixed'))) LadderFixedRule.of(x)];
    final modes = [for (final x in (catOr('modes') as List?) ?? const []) '$x'];
    final def = [for (final x in asMapList(catOr('default'))) LadderRung.of(x)];
    return LadderConfig(
      ladder: normalizeLadder([for (final x in asMapList(m['ladder'])) LadderRung.of(x)]),
      rungs: rungs.isEmpty ? LadderCatalogRung.builtin : rungs,
      fixed: fixed.isEmpty ? LadderFixedRule.builtin : fixed,
      modes: modes.isEmpty ? ladderModes : modes,
      defaultLadder: def.isEmpty ? normalizeLadder(const []) : normalizeLadder(def),
      options: LadderOptions.of(asMap(m['options'] ?? cat['options'])),
      presets: [for (final x in asMapList(m['presets'])) LadderPreset.of(x)],
      version: m['version'] == null ? null : asInt(m['version']),
    );
  }

  LadderConfig copyWith({List<LadderRung>? ladder, LadderOptions? options, List<LadderPreset>? presets, int? version}) => LadderConfig(
        ladder: ladder ?? this.ladder,
        rungs: rungs,
        fixed: fixed,
        modes: modes,
        defaultLadder: defaultLadder,
        options: options ?? this.options,
        presets: presets ?? this.presets,
        version: version ?? this.version,
      );

  LadderRung? rung(String key) => ladder.cast<LadderRung?>().firstWhere((r) => r!.key == key, orElse: () => null);
  LadderCatalogRung? catalogRung(String key) => rungs.cast<LadderCatalogRung?>().firstWhere((r) => r!.key == key, orElse: () => null);
  int indexOf(String key) => ladder.indexWhere((r) => r.key == key);

  /// Is [key] the same as the default ladder (same order, same modes)?
  bool get isDefault {
    if (ladder.length != defaultLadder.length) return false;
    for (var i = 0; i < ladder.length; i++) {
      if (ladder[i].key != defaultLadder[i].key || ladder[i].mode != defaultLadder[i].mode) return false;
    }
    return true;
  }

  /// Move [key] by [delta] places (negative = earlier). `free_moves` stays first; moving past an end, or onto the
  /// first place, is a no-op.
  LadderConfig moveRung(String key, int delta) {
    final i = indexOf(key);
    if (i <= 0 || delta == 0 || key == 'free_moves') return this;
    final j = i + delta;
    if (j < 1 || j >= ladder.length) return this;
    final next = [...ladder];
    final r = next.removeAt(i);
    next.insert(j, r);
    return copyWith(ladder: next);
  }

  /// Set the mode of [key]; an unknown mode or key, or `free_moves` (always auto), is a no-op.
  LadderConfig setMode(String key, String mode) {
    if (!ladderModes.contains(mode) || key == 'free_moves') return this;
    final i = indexOf(key);
    if (i < 0) return this;
    final next = [...ladder];
    next[i] = next[i].withMode(mode);
    return copyWith(ladder: next);
  }

  /// The default ladder and options again.
  LadderConfig resetToDefault() => copyWith(ladder: [...defaultLadder], options: const LadderOptions());

  /// Take over a preset's ladder and options.
  LadderConfig applyPreset(LadderPreset p) => copyWith(ladder: normalizeLadder(p.ladder), options: p.options);

  /// PUT …/ladder body (expected_version is added by the provider).
  Map<String, dynamic> toBody() => {
        'ladder': [for (final r in ladder) r.toJson()],
        'options': options.toJson(),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Decision (run.summary.decision while status = waiting)
// ═════════════════════════════════════════════════════════════════════════════

/// What one option would do (the dry run of a rung): schedule_ladder.Run._option().impact.
class LadderImpact {
  const LadderImpact({
    this.placed = 0,
    this.required = 0,
    this.gain = 0,
    this.unplaced = 0,
    this.broken = 0,
    this.brokenByRung = const {},
    this.people = 0,
    this.complete = false,
    this.note = const {},
    this.seconds = 0,
  });
  final int placed, required, gain, unplaced, broken, people;
  final Map<String, int> brokenByRung; // rung key → broken rules attributed to it
  final bool complete;
  final Map<String, dynamic> note; // what the rung changed (people, new_rooms, splits, new_period, new_day, overflow_pct …)
  final double seconds;

  factory LadderImpact.of(Map<String, dynamic> m) => LadderImpact(
        placed: asInt(m['placed']),
        required: asInt(m['required']),
        gain: asInt(m['gain']),
        unplaced: asInt(m['unplaced']),
        broken: asInt(m['broken']),
        brokenByRung: {for (final e in asMap(m['broken_by_rung']).entries) e.key: asInt(e.value)},
        people: asInt(m['people']),
        complete: m['complete'] == true,
        note: asMap(m['note']),
        seconds: asDouble(m['seconds']),
      );
}

class LadderOption {
  const LadderOption({
    required this.id,
    this.rung,
    required this.nameAr,
    required this.nameEn,
    this.whyAr = '',
    this.whyEn = '',
    this.possible = true,
    this.rank = 0,
    this.recommended = false,
    this.reasonAr = '',
    this.reasonEn = '',
    this.impact,
  });
  final String id; // a rung key, or "stop"
  final String? rung;
  final String nameAr, nameEn, whyAr, whyEn, reasonAr, reasonEn;
  final bool possible, recommended;
  final int rank;
  final LadderImpact? impact;

  String get name => t(nameAr, nameEn);
  String get why => t(whyAr, whyEn);
  String get reason => t(reasonAr, reasonEn);
  bool get isStop => id == 'stop';

  factory LadderOption.of(Map<String, dynamic> m) {
    final id = '${m['id'] ?? ''}';
    final x = ladderText[id];
    return LadderOption(
      id: id,
      rung: m['rung'] == null ? null : '${m['rung']}',
      nameAr: '${m['name_ar'] ?? x?.$1 ?? m['name_en'] ?? id}',
      nameEn: '${m['name_en'] ?? x?.$2 ?? m['name_ar'] ?? id}',
      whyAr: '${m['why_ar'] ?? m['why_en'] ?? ''}',
      whyEn: '${m['why_en'] ?? m['why_ar'] ?? ''}',
      possible: m['possible'] != false,
      rank: asInt(m['rank']),
      recommended: m['recommended'] == true,
      reasonAr: '${m['reason_ar'] ?? m['reason_en'] ?? ''}',
      reasonEn: '${m['reason_en'] ?? m['reason_ar'] ?? ''}',
      impact: m['impact'] is Map ? LadderImpact.of(asMap(m['impact'])) : null,
    );
  }
}

/// "places 12 more · breaks 3 rules · 2 people" — one line about what an option would do; "stop here" and an
/// impossible option get their own words.
String impactText(LadderOption o) {
  if (o.isStop) return t('الحصص المتبقية تبقى بلا موعد', 'The remaining sessions stay unplaced');
  final i = o.impact;
  if (!o.possible || i == null) return t('لا شيء يمكن إضافته هنا', 'Nothing left to add here');
  final parts = <String>[
    if (i.complete)
      t('يُكمل الجدول (${i.placed} من ${i.required})', 'completes the timetable (${i.placed} of ${i.required})')
    else if (i.gain > 0)
      t('يضع ${i.gain} حصة إضافية (${i.unplaced} تبقى)', 'places ${i.gain} more (${i.unplaced} left)')
    else
      t('لا حصص إضافية', 'places nothing more'),
    i.broken == 0 ? t('لا قواعد مكسورة', 'breaks no rule') : t('يكسر ${i.broken} قاعدة', 'breaks ${i.broken} rule(s)'),
    if (i.people > 0) t('${i.people} شخص', '${i.people} people'),
  ];
  return parts.join(' · ');
}

/// The question the run asks the creator (schedule_ladder.Run._decide()).
class LadderDecision {
  const LadderDecision({
    required this.id,
    this.reason = 'ask',
    this.situationAr = '',
    this.situationEn = '',
    this.unplaced = 0,
    this.placed = 0,
    this.required = 0,
    this.top = const [],
    this.options = const [],
    this.recommended = 'stop',
  });
  final String id;
  final String reason; // ask · stack
  final String situationAr, situationEn;
  final int unplaced, placed, required;
  final List<(String, int)> top; // unplaced reasons, most frequent first
  final List<LadderOption> options;
  final String recommended; // an option id

  String get situation => t(situationAr, situationEn);
  LadderOption? get recommendedOption => options.cast<LadderOption?>().firstWhere((o) => o!.id == recommended, orElse: () => null);
  List<LadderOption> get possible => [for (final o in options) if (o.possible) o];

  factory LadderDecision.of(Map<String, dynamic> m) => LadderDecision(
        id: '${m['id'] ?? ''}',
        reason: '${m['reason'] ?? 'ask'}',
        situationAr: '${m['situation_ar'] ?? m['situation_en'] ?? ''}',
        situationEn: '${m['situation_en'] ?? m['situation_ar'] ?? ''}',
        unplaced: asInt(m['unplaced']),
        placed: asInt(m['placed']),
        required: asInt(m['required']),
        top: [for (final x in asMapList(m['top'])) ('${x['reason']}', asInt(x['n']))],
        options: [for (final x in asMapList(m['options'])) LadderOption.of(x)],
        recommended: '${m['recommended'] ?? 'stop'}',
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Live (run.summary while the run is open)
// ═════════════════════════════════════════════════════════════════════════════

/// The counters of a running ladder generation (run.summary.ladder_live), its step log and, while the run status is
/// `waiting`, the decision it waits for.
class LadderLive {
  const LadderLive({
    this.placed = 0,
    this.required = 0,
    this.unplaced = 0,
    this.broken = 0,
    this.rung,
    this.stage,
    this.elapsedS = 0,
    this.budgetS,
    this.solves = 0,
    this.steps = const [],
    this.decision,
    this.status = '',
  });
  final int placed, required, unplaced, broken, solves;
  final String? rung; // the rung being tried / relaxed now
  final String? stage; // prepare · round · applied · decision · decided · save · finish
  final int elapsedS;
  final int? budgetS;
  final List<LiveStep> steps; // oldest first; the last undone one is what happens now
  final LadderDecision? decision;
  final String status; // the run status (queued · running · waiting · …)

  bool get isWaiting => status == 'waiting';
  bool get hasBest => required > 0;
  /// The rung being tried now, by name.
  String get rungLabel => rung == null ? '' : rungName(rung);
  LiveStep? get current => steps.cast<LiveStep?>().lastWhere((x) => x!.done == false, orElse: () => null);
  List<LiveStep> get done => steps.where((x) => x.done).toList();
  int get pct => required == 0 ? 0 : ((100 * placed) ~/ required).clamp(0, 100);

  /// Null when the run is not a ladder run (no `ladder_live` in its summary).
  static LadderLive? of(Map<String, dynamic>? run) {
    final s = asMap(run?['summary']);
    final l = asMap(s['ladder_live']);
    if (l.isEmpty) return null;
    final dec = asMap(s['decision']);
    return LadderLive(
      placed: asInt(l['placed']),
      required: asInt(l['required']),
      unplaced: asInt(l['unplaced']),
      broken: asInt(l['broken']),
      rung: l['rung'] == null ? null : '${l['rung']}',
      stage: l['stage'] == null ? s['stage']?.toString() : '${l['stage']}',
      elapsedS: asInt(l['elapsed_s'] ?? s['elapsed_s']),
      budgetS: (l['budget_s'] ?? s['budget_s']) == null ? null : asInt(l['budget_s'] ?? s['budget_s']),
      solves: asInt(l['solves']),
      steps: [for (final x in asMapList(s['steps'])) LiveStep.of(x)],
      decision: dec.isEmpty ? null : LadderDecision.of(dec),
      status: '${run?['status'] ?? ''}',
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Report (result.ladder)
// ═════════════════════════════════════════════════════════════════════════════

class LadderRungResult {
  const LadderRungResult({
    required this.key,
    this.mode = 'auto',
    this.tried = false,
    this.applied = false,
    this.placedBefore = 0,
    this.placedAfter = 0,
    this.broken = 0,
    this.seconds = 0,
    this.note = const {},
    this.attempts,
  });
  final String key, mode;
  final bool tried, applied;
  final int placedBefore, placedAfter, broken;
  final double seconds;
  final Map<String, dynamic> note; // {skipped: nothing_to_add | no_gain | solver_timeout | passed_over} or what the rung changed
  final int? attempts;

  String get name => rungName(key);
  String? get skipped => note['skipped'] == null ? null : '${note['skipped']}';
  int get gain => (placedAfter - placedBefore).clamp(0, 1 << 30);

  factory LadderRungResult.of(Map<String, dynamic> m) => LadderRungResult(
        key: '${m['key'] ?? ''}',
        mode: _modeOk(m['mode']),
        tried: m['tried'] == true,
        applied: m['applied'] == true,
        placedBefore: asInt(m['placed_before']),
        placedAfter: asInt(m['placed_after']),
        broken: asInt(m['broken']),
        seconds: asDouble(m['seconds']),
        note: asMap(m['note']),
        attempts: m['attempts'] == null ? null : asInt(m['attempts']),
      );
}

class LadderDecisionRecord {
  const LadderDecisionRecord({required this.id, this.reason = 'ask', this.chosen = '', this.by = 'auto', this.recommended = '', this.atS = 0, this.options = const []});
  final String id, reason, chosen, by, recommended; // by: user · auto · timeout
  final double atS;
  final List<Map<String, dynamic>> options; // {id, rank, possible, impact, recommended}

  String get chosenName => rungName(chosen);
  bool get followedRecommendation => chosen == recommended;

  factory LadderDecisionRecord.of(Map<String, dynamic> m) => LadderDecisionRecord(
        id: '${m['id'] ?? ''}',
        reason: '${m['reason'] ?? 'ask'}',
        chosen: '${m['chosen'] ?? ''}',
        by: '${m['by'] ?? 'auto'}',
        recommended: '${m['recommended'] ?? ''}',
        atS: asDouble(m['at_s']),
        options: asMapList(m['options']),
      );
}

/// A locked rung that would have helped (result.ladder.blocked_by[]).
class LadderBlocked {
  const LadderBlocked({required this.key, required this.nameAr, required this.nameEn, this.wouldComplete = false, this.placedAfter = 0, this.required = 0});
  final String key, nameAr, nameEn;
  final bool wouldComplete;
  final int placedAfter, required;

  String get name => t(nameAr, nameEn);

  factory LadderBlocked.of(Map<String, dynamic> m) {
    final key = '${m['key'] ?? ''}';
    final x = ladderText[key];
    return LadderBlocked(
      key: key,
      nameAr: '${m['name_ar'] ?? x?.$1 ?? m['name_en'] ?? key}',
      nameEn: '${m['name_en'] ?? x?.$2 ?? m['name_ar'] ?? key}',
      wouldComplete: m['would_complete'] == true,
      placedAfter: asInt(m['placed_after']),
      required: asInt(m['required']),
    );
  }
}

/// What the run added to the timetable's structure (result.ladder.structural).
class LadderStructural {
  const LadderStructural({this.rooms = const [], this.periods = const [], this.days = const [], this.splits = const []});
  final List<Map<String, dynamic>> rooms; // {id, kind, capacity, capabilities, sessions, created_id?, removed?}
  final List<Map<String, dynamic>> periods; // {id, order, start, end, label, sessions, created_id?, removed?}
  final List<Map<String, dynamic>> days; // {day, sessions}
  final List<Map<String, dynamic>> splits; // {course_id, kind, from, groups, sizes, sessions, staff: [{group_no, teacher_id, new}]}

  bool get isEmpty => rooms.isEmpty && periods.isEmpty && days.isEmpty && splits.isEmpty;
  int get total => rooms.length + periods.length + days.length + splits.length;

  /// Proposed rooms / periods the server deleted again (their sessions' proposals were rejected).
  int get removedRooms => rooms.where((r) => r['removed'] == true).length;
  int get removedPeriods => periods.where((p) => p['removed'] == true).length;

  /// Groups a split handed to a colleague (structural.splits[].staff[].new).
  int get newStaff => [for (final s in splits) for (final x in asMapList(s['staff'])) if (x['new'] == true) x].length;

  factory LadderStructural.of(Map<String, dynamic> m) => LadderStructural(
        rooms: asMapList(m['rooms']),
        periods: asMapList(m['periods']),
        days: [for (final d in (m['days'] as List?) ?? const []) d is Map ? Map<String, dynamic>.from(d) : {'day': '$d'}],
        splits: asMapList(m['splits']),
      );

  /// "1 new room · 1 new period · 2 groups split (1 handed to a colleague)" (empty when nothing was added);
  /// a room / period removed again says so.
  List<String> get lines => [
        if (rooms.isNotEmpty)
          t('${rooms.length} قاعة جديدة', '${rooms.length} new room(s)') +
              (removedRooms > 0 ? t(' (أُزيلت $removedRooms)', ' ($removedRooms removed again)') : ''),
        if (periods.isNotEmpty)
          t('${periods.length} فترة جديدة', '${periods.length} new period(s)') +
              (removedPeriods > 0 ? t(' (أُزيلت $removedPeriods)', ' ($removedPeriods removed again)') : ''),
        if (days.isNotEmpty) t('${days.length} يوم جديد', '${days.length} new day(s)'),
        if (splits.isNotEmpty)
          t('${splits.length} مجموعة مقسّمة', '${splits.length} group(s) split') +
              (newStaff > 0 ? t(' ($newStaff لزميل)', ' ($newStaff handed to a colleague)') : ''),
      ];
}

/// The two validator passes (result.ladder.proof).
class LadderProof {
  const LadderProof({this.hardVsRelaxed = 0, this.hardVsOriginal = 0, this.neverBrokenViolations = 0, this.findings = const []});
  final int hardVsRelaxed; // must be 0: the result is conflict-free against the relaxed problem
  final int hardVsOriginal; // every one a deliberate, reported break
  final int neverBrokenViolations; // a person / room in two sessions etc. — must be 0
  final List<Map<String, dynamic>> findings;

  bool get clean => hardVsRelaxed == 0 && neverBrokenViolations == 0;

  factory LadderProof.of(Map<String, dynamic> m) => LadderProof(
        hardVsRelaxed: asInt(m['hard_vs_relaxed']),
        hardVsOriginal: asInt(m['hard_vs_original']),
        neverBrokenViolations: asInt(m['never_broken_violations']),
        findings: asMapList(m['findings']),
      );
}

/// result.ladder (schedule_ladder.Run.report()) plus the counters of the result it sits in.
class LadderReport {
  const LadderReport({
    this.status = 'incomplete',
    this.valid = true,
    this.ladder = const [],
    this.rungs = const [],
    this.decisions = const [],
    this.blockedBy = const [],
    this.structural = const LadderStructural(),
    this.proof = const LadderProof(),
    this.completionPct = 0,
    this.elapsedS = 0,
    this.budgetS = 0,
    this.solves = 0,
    this.seed = 7,
    this.auto = false,
    this.placed = 0,
    this.required = 0,
    this.broken = const [],
  });
  final String status; // complete · incomplete · invalid · time_limit · solver_timeout · stopped_by_creator · cancelled
  final bool valid;
  final List<LadderRung> ladder;
  final List<LadderRungResult> rungs;
  final List<LadderDecisionRecord> decisions;
  final List<LadderBlocked> blockedBy;
  final LadderStructural structural;
  final LadderProof proof;
  final int completionPct, solves, seed;
  final double elapsedS, budgetS;
  final bool auto;
  final int placed, required; // result.stats
  final List<Map<String, dynamic>> broken; // result.broken[] — {rule, rung, course_id, kind, group_no, day, period_ids, user_id?, room_id?, detail?}

  bool get complete => status == 'complete';
  bool get provenClean => valid && proof.clean;
  int get unplaced => (required - placed).clamp(0, 1 << 30);
  List<LadderRungResult> get applied => [for (final r in rungs) if (r.applied && r.key != 'free_moves') r];

  /// Broken rules per rung, in ladder order.
  Map<String, int> get brokenByRung {
    final n = <String, int>{};
    for (final b in broken) {
      n.update('${b['rung'] ?? ''}', (v) => v + 1, ifAbsent: () => 1);
    }
    final order = [for (final r in ladder) r.key];
    final keys = n.keys.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return {for (final k in keys) k: n[k]!};
  }

  /// The locked rung that would complete the timetable (the first), else the one that places the most.
  LadderBlocked? get bestBlocked {
    if (blockedBy.isEmpty) return null;
    return blockedBy.cast<LadderBlocked?>().firstWhere((b) => b!.wouldComplete, orElse: () => null) ??
        blockedBy.reduce((a, b) => b.placedAfter > a.placedAfter ? b : a);
  }

  /// Null when [result] (schedule.result) is not a ladder result.
  static LadderReport? of(Map<String, dynamic> result) {
    final m = asMap(result['ladder']);
    if (m.isEmpty) return null;
    final st = asMap(result['stats']);
    final rungs = [for (final x in asMapList(m['rungs'])) LadderRungResult.of(x)];
    final lastPlaced = rungs.isEmpty ? 0 : rungs.where((r) => r.applied).fold(0, (a, r) => r.placedAfter > a ? r.placedAfter : a);
    return LadderReport(
      status: '${m['status'] ?? 'incomplete'}',
      valid: m['valid'] != false,
      ladder: [for (final x in asMapList(m['ladder'])) LadderRung.of(x)],
      rungs: rungs,
      decisions: [for (final x in asMapList(m['decisions'])) LadderDecisionRecord.of(x)],
      blockedBy: [for (final x in asMapList(m['blocked_by'])) LadderBlocked.of(x)],
      structural: LadderStructural.of(asMap(m['structural'])),
      proof: LadderProof.of(asMap(m['proof'])),
      completionPct: asInt(m['completion_pct']),
      elapsedS: asDouble(m['elapsed_s']),
      budgetS: asDouble(m['budget_s']),
      solves: asInt(m['solves']),
      seed: asInt(m['seed'], 7),
      auto: m['auto'] == true,
      placed: asInt(st['sessions_placed'], lastPlaced),
      required: asInt(st['sessions_required']),
      broken: asMapList(result['broken']),
    );
  }

  /// "Complete: 180 of 180 placed, 3 rules bent (TA limits ×2, rooms ×1), 1 new period, proven conflict-free" —
  /// or the incomplete variants naming what blocks completion.
  String summaryText() {
    final placedText = t('وُضعت $placed من $required حصة', '$placed of $required placed');
    final byRung = brokenByRung;
    final bent = broken.isEmpty
        ? t('بلا كسر أي قاعدة', 'no rule bent')
        : t('كُسرت ${broken.length} قاعدة', '${broken.length} rule(s) bent') +
            (byRung.isEmpty ? '' : ' (${[for (final e in byRung.entries) '${rungName(e.key)} ×${e.value}'].join(t('، ', ', '))})');
    final parts = <String>[placedText, bent, ...structural.lines];
    switch (status) {
      case 'complete':
        parts.add(provenClean ? t('مُثبت خلوّه من التعارضات', 'proven conflict-free') : t('لم يُثبت خلوّه من التعارضات', 'not proven conflict-free'));
        return '${t('مكتمل', 'Complete')}: ${parts.join(t('، ', ', '))}';
      case 'invalid':
        return t('فشل الفحص النهائي: النتيجة فيها ${proof.hardVsRelaxed} تعارض لا يُسمح به ولم يُحفظ شيء',
            'The final check failed: the result has ${proof.hardVsRelaxed} disallowed conflict(s) and nothing was saved');
      case 'cancelled':
        return '${t('أُلغي', 'Cancelled')}: ${t('لم يتغير شيء في الجدول', 'nothing in the timetable changed')}';
    }
    final head = switch (status) {
      'time_limit' => t('انتهى الوقت', 'Time limit'),
      'solver_timeout' => t('المحلّل لم يكمل في وقته', 'The solver ran out of time'),
      'stopped_by_creator' => t('أُوقف بقرارك', 'Stopped by you'),
      _ => t('غير مكتمل', 'Incomplete'),
    };
    final b = bestBlocked;
    final why = b == null
        ? (status == 'incomplete' ? t('لا درجة مقفلة تُكمل الجدول — راجع البيانات', 'no locked rung would complete it — check the data') : null)
        : b.wouldComplete
            ? t('فتح «${b.name}» يُكمل الجدول', 'unlocking "${b.name}" would complete it')
            : t('فتح «${b.name}» يضع ${b.placedAfter} من ${b.required}', 'unlocking "${b.name}" would place ${b.placedAfter} of ${b.required}');
    return '$head: ${parts.join(t('، ', ', '))}${why == null ? '' : ' — $why'}';
  }
}

/// The report status in a few words.
String ladderStatusText(String status) => switch (status) {
      'complete' => t('جدول كامل', 'Complete timetable'),
      'incomplete' => t('غير مكتمل', 'Incomplete'),
      'invalid' => t('فشل الفحص النهائي', 'Failed the final check'),
      'time_limit' => t('انتهى الوقت', 'Time limit reached'),
      'solver_timeout' => t('المحلّل لم يكمل في وقته — أعد التوليد بوقت أطول', 'The solver ran out of time — generate again with a longer solve time'),
      'stopped_by_creator' => t('أُوقف بقرار المنشئ', 'Stopped by the creator'),
      'cancelled' => t('أُلغي', 'Cancelled'),
      _ => status.replaceAll('_', ' '),
    };

/// One result.broken[] item as a sentence: the rule, the rung that allowed it, and the detail the server attached
/// (the new room / period / day, the split sizes). [names] / [people] / [rooms] / [periods] turn ids into names.
String brokenRuleLine(Map<String, dynamic> b, {Map<int, String> names = const {}, Map<int, String> people = const {}, Map<int, String> rooms = const {}, Map<int, String> periods = const {}}) {
  final rule = '${b['rule'] ?? ''}';
  final d = asMap(b['detail']);
  String who() => people[asInt(b['user_id'])] ?? t('عضو هيئة', 'a staff member');
  String room() => rooms[asInt(b['room_id'])] ?? t('قاعة', 'a room');
  final what = switch (rule) {
    'teacher_unavailable' => t('${who()} في وقت غير متاح له', '${who()} at a time they are unavailable'),
    'teacher_day_limit' => t('${who()} فوق حده اليومي', '${who()} over their daily cap'),
    'teacher_week_limit' => t('${who()} فوق حده الأسبوعي', '${who()} over their weekly cap'),
    'room_unavailable' => t('${room()} في وقت غير متاح لها', '${room()} at a time it is unavailable'),
    'room_kind' => t('حصة نظرية في ${room()} من نوع آخر', 'a theory session in ${room()} of another kind'),
    'room_capabilities' => t('${room()} تنقصها تجهيزات مطلوبة', '${room()} lacks required equipment'),
    'room_capacity' => t('${room()} فوق سعتها', '${room()} over its capacity'),
    'new_room' => t('قاعة جديدة مقترحة (${d['kind'] ?? ''}، ${d['capacity'] ?? ''} مقعداً)', 'a proposed new room (${d['kind'] ?? ''}, ${d['capacity'] ?? ''} seats)'),
    'new_period' => t('فترة جديدة ${d['label'] ?? ''}', 'a new period ${d['label'] ?? ''}'),
    'new_day' => t('يوم جديد ${d['day'] ?? b['day'] ?? ''}', 'a new day ${d['day'] ?? b['day'] ?? ''}'),
    'group_split' => t('مجموعة مقسّمة إلى ${d['groups'] ?? ''} بدل ${d['from'] ?? ''}', 'a group split into ${d['groups'] ?? ''} instead of ${d['from'] ?? ''}'),
    'students_unavailable' => t('الطلاب في وقت غير متاح لهم', 'students at a time they are unavailable'),
    'students_busy_elsewhere' => t('الطلاب مشغولون في جدول مفعّل آخر', 'students busy in another active timetable'),
    'students_clash' => t('طلاب في حصتين في الوقت نفسه', 'students in two sessions at once'),
    _ => rule.replaceAll('_', ' '),
  };
  final course = names[asInt(b['course_id'])] ?? '${t('مقرر', 'course')} ${b['course_id'] ?? ''}';
  final kind = '${b['kind'] ?? 'lecture'}' == 'lab' ? t('معمل', 'lab') : t('محاضرة', 'lecture');
  final group = b['group_no'] == null ? '' : ' ${t('مج', 'G')}${b['group_no']}';
  final period = periods[asInt((b['period_ids'] as List?)?.firstOrNull)];
  final where = [if (b['day'] != null) '${b['day']}', ?period].join(' · ');
  final rung = b['rung'] == null ? '' : ' — ${rungName('${b['rung']}')}';
  return '$course ($kind$group)${where.isEmpty ? '' : ' $where'}: $what$rung';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Texts and orderings the widgets share (org_schedule_ladder_ui.dart)
// ═════════════════════════════════════════════════════════════════════════════

/// What is happening now, in one line: the open step's own text when there is one, else the stage / rung.
String ladderHeadline(LadderLive live) {
  switch (live.status) {
    case 'queued':
      return t('في الانتظار — يبدأ التوليد خلال لحظات', 'Queued — generation starts in a moment');
    case 'failed':
      return t('فشل التوليد — لم يتغير شيء', 'Generation failed — nothing changed');
    case 'cancelled':
      return t('أُلغي التوليد — الجدول كما كان', 'Generation cancelled — the timetable is as it was');
    case 'done':
    case 'finished':
    case 'completed':
      return t('انتهى التوليد', 'Generation finished');
  }
  if (live.isWaiting) return t('بانتظار قرارك', 'Waiting for your decision');
  final cur = live.current;
  if (cur != null && cur.text.isNotEmpty) return cur.text;
  final rung = live.rungLabel;
  return switch (live.stage) {
    'prepare' => t('تحميل البيانات…', 'Loading the data…'),
    'save' => t('حفظ الجدول…', 'Saving the timetable…'),
    'finish' => t('الفحص النهائي…', 'Final check…'),
    'round' || 'applied' || 'decided' when rung.isNotEmpty => t('تجربة: $rung', 'Trying: $rung'),
    _ => rung.isNotEmpty ? t('تجربة: $rung', 'Trying: $rung') : t('جارٍ التوليد…', 'Generating…'),
  };
}

/// Is a run with this status still going (the overlay stays, the sheet cannot be dismissed)?
bool ladderStatusOpen(String status) => const {'queued', 'running', 'waiting'}.contains(status);

/// A decision's options in the order they are shown: the possible rungs by rank, then the impossible ones, "stop"
/// always last.
List<LadderOption> orderedOptions(LadderDecision d) {
  int rank(LadderOption o) => o.rank;
  final possible = [for (final o in d.options) if (o.possible && !o.isStop) o]..sort((a, b) => rank(a).compareTo(rank(b)));
  final impossible = [for (final o in d.options) if (!o.possible && !o.isStop) o]..sort((a, b) => rank(a).compareTo(rank(b)));
  final stop = [for (final o in d.options) if (o.isStop) o];
  return [...possible, ...impossible, ...stop];
}

/// Why a rung was skipped (LadderRungResult.note.skipped), in a few words.
String rungSkippedText(String? skipped) => switch (skipped) {
      'nothing_to_add' => t('لا شيء يمكن إضافته', 'nothing to add'),
      'not_relevant' => t('لا تمسّ ما يعيق الحصص المتبقية', 'cannot touch what blocks the rest'),
      'no_gain' => t('لم يضف حصة', 'no gain'),
      'solver_timeout' => t('لم يكمل المحلّل في وقته', 'the solver ran out of time'),
      'passed_over' => t('تُخطّي بقرارك', 'passed over by you'),
      'locked' => t('مقفلة', 'locked'),
      'budget' || 'time_limit' => t('انتهى الوقت قبلها', 'out of time'),
      null => '',
      _ => skipped.replaceAll('_', ' '),
    };

/// One rung's row in the result table: "+12 placed · 2 rules bent · 30 s", "skipped: no gain", "not tried", "locked".
String rungResultText(LadderRungResult r) {
  if (r.mode == 'locked' && !r.tried) return t('مقفلة — لم تُجرَّب', 'locked — not tried');
  if (!r.tried) {
    final why = rungSkippedText(r.skipped);
    return why.isEmpty ? t('لم تُجرَّب', 'not tried') : t('تُخطّيت: $why', 'skipped: $why');
  }
  if (!r.applied) {
    final why = rungSkippedText(r.skipped);
    return why.isEmpty ? t('جُرّبت ولم تُطبَّق', 'tried, not applied') : t('تُخطّيت: $why', 'skipped: $why');
  }
  final parts = <String>[
    r.key == 'free_moves'
        ? t('وُضعت ${r.placedAfter} حصة بلا كسر', '${r.placedAfter} placed, nothing bent')
        : t('+${r.gain} حصة', '+${r.gain} placed'),
    if (r.broken > 0) t('كُسرت ${r.broken} قاعدة', '${r.broken} rule(s) bent'),
    if (r.seconds >= 1) '${r.seconds.round()} ${t('ث', 's')}',
  ];
  return parts.join(' · ');
}

/// Who took a decision (LadderDecisionRecord.by).
String decisionByText(String by) => switch (by) {
      'user' => t('بقرارك', 'by you'),
      'timeout' => t('تلقائياً بعد انتهاء المهلة', 'automatically after the timeout'),
      _ => t('تلقائياً', 'automatically'),
    };

/// The ids of the proposals (result.broken[] blocks) still waiting for a decision — what "Accept all" accepts.
List<String> pendingBlockIds(List<Map<String, dynamic>> broken) {
  final ids = <String>[];
  for (final b in broken) {
    if (!b.containsKey('decision') || b['decision'] != null) continue;
    final id = '${b['block_id'] ?? ''}';
    if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  return ids;
}
