// lib/features/org/org_schedule_generate.dart — the ONE "Generate timetable" action.
//
// The server runs strict rounds, then rounds that may break only the rules the admin marked Flexible, until every
// session is placed or no round makes progress (POST …/generate {complete: true}, schedule_jobs.complete). It saves
// a Draft. Every broken rule comes back as a proposal (result.broken[].decision null) the admin accepts or rejects;
// publishing waits for all of them (409 proposals_pending).
//
//   GenerationRule / generationRules   pure: the rule set shown before generating (settings.rules)
//   GenerationOutcome                  pure: placed / unplaced / proposals, from schedule.result
//   LiveRun / LiveStep                 pure: the live counters AND the step log of a running generation (run.summary:
//                                      steps[] — data loaded · attempt n strict / bending flexible rules · saving —
//                                      stage, started_at, elapsed_s, budget_s); patienceText for a slow step
//   createTimetable                    the one action (no questions, background, Draft)   GenerationLivePanel while it runs
//   GenerationLivePanel / GenerationVeil   the premium "a new version is being made" state: what is happening now, each
//                                      step with its time, the elapsed clock, the attempt's own budget bar, hints
//   showRulesSheet                     Locked / Flexible per rule, in break order; last resorts are suggestions only
//   ConflictDigest / ConflictsPanel    the small live conflicts panel (counts + top types)
//   showGenerationResult               result: unplaced with reason + fix, proposals, advice, conflicts (read-only)
//   TimetableCompletion                pure: % complete — never "complete" while anything is unplaced, clashing or pending
//   QuickActionsReport / QuickAction   pure: GET …/quick-actions — one Locked rule relaxed each, dry-run impact
//   showGenerationResult also IS the Quick Actions panel: completion, problems per course, one-rule fixes (apply
//   re-solves only the affected part, POST …/quick-actions/apply), proposals, last-resort advice (suggestions only)
library;

import 'package:flutter_education_app/design/app_mesh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../../design/app_kit.dart' show AppDropdown, AppListSkeleton;
import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show RowCard;
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_schedule_autopilot.dart';
import 'org_schedule_insights.dart';
import 'org_schedule_ladder.dart' show LadderLive, LadderReport, pendingBlockIds;
import 'org_schedule_ladder_ui.dart' show LadderLivePanel, LadderResultCard, showLadderSheet;
import 'org_schedule_optimizer.dart';
import 'org_schedule_preview.dart';
import 'org_schedule_remedies.dart';
import 'org_timetable_parts.dart' show courseName;
import 'org_ui.dart';
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pure
// ═════════════════════════════════════════════════════════════════════════════

class GenerationRule {
  const GenerationRule(this.key, this.ar, this.en, {this.fixed = false, this.flexibleByDefault = false, this.unlockable = false, this.suggestionOnly = false});
  final String key, ar, en;
  final bool fixed; // always locked (never sent)
  final bool flexibleByDefault;
  final bool unlockable; // settings.rules key the admin may switch (Locked / Flexible)
  final bool suggestionOnly; // a last resort the server only ever suggests — never applied automatically
}

/// Truly hard rules first (always locked), then the switchable rules in the order they give way when a session does
/// not fit (schedule_jobs.BREAK_ORDER: compactness first … instructor availability last), then the last resorts.
const generationRules = [
  GenerationRule('room_double', 'القاعة أو المعمل يستضيف حصة واحدة في الوقت نفسه', 'A room or lab hosts one session at a time', fixed: true),
  GenerationRule('person_double', 'الطالب أو المدرس أو المعيد لا يكون في مكانين في الوقت نفسه (في كل جداول الفصل)', 'A student, instructor or TA is never in two places at once (across the term\'s timetables)', fixed: true),
  GenerationRule('lab_only', 'الحصص العملية في معامل مجهّزة فقط، لا في قاعات المحاضرات', 'Practical sessions only in equipped labs, never lecture halls', fixed: true),
  GenerationRule('capacity', 'سعة القاعة لا تقل عن حجم المجموعة', 'Room capacity is at least the group size', fixed: true),
  GenerationRule('compact', 'جداول متقاربة وفجوات أقل', 'Compact schedules, fewer gaps', flexibleByDefault: true, unlockable: true),
  GenerationRule('preferred', 'الأوقات المفضلة', 'Preferred time slots', flexibleByDefault: true, unlockable: true),
  GenerationRule('soft_availability', 'تجنّب الأيام والفترات غير المفضلة للمدرس أو المعيد', 'Avoid an instructor\'s / TA\'s non-preferred days and periods', flexibleByDefault: true, unlockable: true),
  GenerationRule('extra_times', 'اقتراح أوقات إضافية خارج الفترات المحددة', 'Suggest extra time slots beyond the periods', flexibleByDefault: true, unlockable: true),
  GenerationRule('larger_hall', 'قاعة أكبر أو من نوع آخر لمحاضرة نظرية', 'A larger / other hall for a theory session', flexibleByDefault: true, unlockable: true),
  GenerationRule('rooms_and_times', 'استخدام القاعات والأوقات المتاحة فقط', 'Use only the available rooms and time slots', unlockable: true),
  GenerationRule('assistant_availability', 'احترام أيام وفترات إتاحة كل معيد', 'Respect each TA\'s available days and periods', unlockable: true),
  GenerationRule('instructor_availability', 'احترام أيام وفترات إتاحة كل مدرس', 'Respect each instructor\'s available days and periods', unlockable: true),
  GenerationRule('external', 'ملاذ أخير: عضو أو قاعة أو معمل من الخارج', 'Last resort: external staff, hall or lab', suggestionOnly: true),
  GenerationRule('new_slots', 'ملاذ أخير: فترات أو أيام جديدة', 'Last resort: new periods or days', suggestionOnly: true),
];

/// settings.rules as the admin set them, defaults filled in: key → flexible?
Map<String, bool> rulesFlexible(Map<String, dynamic> settings) {
  final stored = asMap(settings['rules']);
  return {
    for (final r in generationRules)
      if (r.unlockable) r.key: stored[r.key] == null ? r.flexibleByDefault : stored[r.key] == 'flexible',
  };
}

/// The order switchable rules give way (1 = first). Locked ones never give way.
List<GenerationRule> get breakOrder => [for (final r in generationRules) if (r.unlockable) r];

/// The live conflicts panel: hard / soft counts and the most frequent conflict types.
class ConflictDigest {
  const ConflictDigest(this.hard, this.soft, this.top);
  final int hard, soft;
  final List<(String, int)> top; // type → count, most frequent first (≤ 3)

  int get total => hard + soft;

  factory ConflictDigest.of(List<Map<String, dynamic>> conflicts) {
    final hard = conflicts.where((x) => x['severity'] == 'error').length;
    final n = <String, int>{};
    for (final x in conflicts) {
      n.update('${x['type']}', (v) => v + 1, ifAbsent: () => 1);
    }
    final top = n.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return ConflictDigest(hard, conflicts.length - hard, [for (final e in top.take(3)) (e.key, e.value)]);
  }
}

/// Server conflict types (org_schedule_router._CONFLICT_TEXT) in a few words.
String conflictTypeText(String type) => switch (type) {
      'room_double_booked' || 'room_busy_elsewhere' => t('قاعة محجوزة مرتين', 'Room booked twice'),
      'teacher_double_booked' || 'assistant_double_booked' || 'admin_assistant_double_booked' || 'staff_busy_elsewhere' =>
        t('عضو هيئة في حصتين', 'Staff member in two sessions'),
      'students_clash' || 'students_busy_elsewhere' => t('طلاب في حصتين', 'Students in two sessions'),
      'course_overlap' => t('حصتان للمقرر في وقت واحد', 'Two sessions of a course at once'),
      'teacher_unavailable' || 'staff_unavailable' || 'teacher_unavailable_overridden' || 'staff_unavailable_overridden' =>
        t('في وقت غير متاح للهيئة', 'At a time staff are unavailable'),
      'room_unavailable' || 'room_inactive' => t('قاعة غير متاحة', 'Room unavailable'),
      'students_unavailable' => t('الطلاب غير متاحين', 'Students unavailable'),
      'room_too_small' => t('القاعة أصغر من المجموعة', 'Room smaller than the group'),
      'room_missing_capabilities' || 'room_kind_mismatch' => t('قاعة غير مناسبة', 'Unsuitable room'),
      'teacher_overloaded' => t('تجاوز الحد اليومي', 'Over the daily limit'),
      'preference_avoided' || 'preference_not_preferred' => t('خارج الأوقات المفضلة', 'Outside preferred times'),
      'staff_not_eligible' || 'staff_not_eligible_overridden' => t('عضو غير مؤهل', 'Staff not eligible'),
      'group_out_of_range' => t('رقم مجموعة غير صحيح', 'Wrong group number'),
      _ => type.replaceAll('_', ' '),
    };

class GenerationOutcome {
  const GenerationOutcome({this.required, this.placed, this.unplaced = const [], this.proposals = const [], this.stopped});
  final int? required, placed;
  final List<Map<String, dynamic>> unplaced; // result.unscheduled
  final List<Map<String, dynamic>> proposals; // result.broken
  final String? stopped; // complete · no_progress · limit

  int get missing => unplaced.fold(0, (a, u) => a + asInt(u['missing'], 1));
  List<Map<String, dynamic>> get pending => [for (final x in proposals) if (x.containsKey('decision') && x['decision'] == null) x];

  factory GenerationOutcome.of(Map<String, dynamic> result) {
    final st = asMap(result['stats']);
    return GenerationOutcome(
      required: st['sessions_required'] == null ? null : asInt(st['sessions_required']),
      placed: st['sessions_placed'] == null ? null : asInt(st['sessions_placed']),
      unplaced: asMapList(result['unscheduled']),
      proposals: asMapList(result['broken']),
      stopped: asMap(result['complete'])['stopped'] as String?,
    );
  }
}

class LiveRun {
  const LiveRun({
    required this.round,
    required this.roundsMax,
    required this.unplaced,
    required this.top,
    this.placed,
    this.required,
    this.steps = const [],
    this.stage,
    this.startedAt,
    this.elapsedS = 0,
    this.budgetS,
  });
  final int round, roundsMax, unplaced;
  final int? placed, required; // the best result so far (it only ever improves)
  final List<(String, int)> top;
  final List<LiveStep> steps; // the step log, oldest first; the last undone one is what happens now
  final String? stage; // prepare · round · round_end · save · finish
  final DateTime? startedAt;
  final int elapsedS; // seconds since the run started, as the server last wrote it
  final int? budgetS; // the whole run's time budget

  /// The step in progress (none when the server only sent counters, or everything is done).
  LiveStep? get current => steps.cast<LiveStep?>().lastWhere((x) => x!.done == false, orElse: () => null);
  List<LiveStep> get done => steps.where((x) => x.done).toList();
  bool get hasBest => placed != null && required != null;

  static LiveRun? of(Map<String, dynamic>? run) {
    final s = asMap(run?['summary']);
    if (s['live'] != true) return null;
    return LiveRun(
      round: asInt(s['round']),
      roundsMax: asInt(s['rounds_max'], 6),
      unplaced: asInt(s['unplaced']),
      placed: s['placed'] == null ? null : asInt(s['placed']),
      required: s['required'] == null ? null : asInt(s['required']),
      top: [for (final x in asMapList(s['top'])) ('${x['reason']}', asInt(x['n']))],
      steps: [for (final x in asMapList(s['steps'])) LiveStep.of(x)],
      stage: s['stage']?.toString(),
      startedAt: DateTime.tryParse('${s['started_at'] ?? ''}'),
      elapsedS: asInt(s['elapsed_s']),
      budgetS: s['budget_s'] == null ? null : asInt(s['budget_s']),
    );
  }
}

/// One message of the generation's step log (run.summary.steps[]).
class LiveStep {
  const LiveStep({required this.id, required this.kind, required this.textAr, required this.textEn, required this.done, this.round, this.ms, this.at, this.limitS, this.relax, this.improved, this.rung, this.note = const {}, this.elapsedS});
  final int id;
  final String kind, textAr, textEn;
  final bool done;
  final int? round, ms; // ms: how long the step took, once done
  final DateTime? at; // when it started (server time)
  final double? limitS; // an attempt's own time budget
  final bool? relax, improved;
  final String? rung; // a ladder run: the rung this step is about (kind round · applied · decided)
  final Map<String, dynamic> note; // a ladder run: what the rung changed
  final double? elapsedS; // a ladder run: seconds since the run started when the step was written

  String get text => t(textAr, textEn);
  bool get isAttempt => kind == 'round';

  static LiveStep of(Map<String, dynamic> m) => LiveStep(
        id: asInt(m['id']),
        kind: '${m['kind'] ?? ''}',
        textAr: '${m['text_ar'] ?? m['text_en'] ?? ''}',
        textEn: '${m['text_en'] ?? m['text_ar'] ?? ''}',
        done: m['done'] == true,
        round: m['round'] == null ? null : asInt(m['round']),
        ms: m['ms'] == null ? null : asInt(m['ms']),
        at: DateTime.tryParse('${m['at'] ?? ''}'),
        limitS: m['limit_s'] == null ? null : double.tryParse('${m['limit_s']}'),
        relax: m['relax'] is bool ? m['relax'] as bool : null,
        improved: m['improved'] is bool ? m['improved'] as bool : null,
        rung: m['rung'] == null ? null : '${m['rung']}',
        note: asMap(m['note']),
        elapsedS: m['elapsed_s'] == null ? null : double.tryParse('${m['elapsed_s']}'),
      );
}

/// What to tell someone who has been watching one step for [inStep]: nothing at first, then why it takes time, then
/// that the server itself will stop the attempt. Keeps the creator patient without pretending to know the end.
String? patienceText(Duration inStep, {bool relax = false}) {
  final s = inStep.inSeconds;
  if (s < 8) return null;
  if (s < 20) {
    return t('ما زال العمل جارياً — كل محاولة قد تستخدم وقتها كاملاً للوصول إلى أفضل توزيع.',
        'Still working — each attempt may use its whole time budget to find the best placement.');
  }
  if (s < 45) {
    return relax
        ? t('هذه المحاولة تجرّب تجاوز القواعد المرنة وحدها، تركيبة بعد أخرى. أفضل نتيجة حتى الآن محفوظة.',
            'This attempt bends only the Flexible rules, one combination after another. The best result so far is kept.')
        : t('هذه المحاولة تستغرق أطول: حصص وقواعد وقاعات كثيرة تُجمَع معاً. أفضل نتيجة حتى الآن محفوظة.',
            'This attempt is taking longer: many sessions, rules and rooms are being combined. The best result so far is kept.');
  }
  return t('اقتربت المحاولة من حدّها الزمني؛ سيوقفها الخادم وينتقل إلى التالية أو يحفظ أفضل نتيجة.',
      'The attempt is near its time limit; the server stops it by itself and moves on or saves the best result.');
}

/// 0:42 · 1:05 — a clock for the elapsed time.
String liveClock(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  final m = s ~/ 60;
  return m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : '$m:${(s % 60).toString().padLeft(2, '0')}';
}

/// How complete a timetable really is. [isComplete] only when every session is placed, nothing hard clashes and no
/// proposal waits; until then [pct] stays below 100 so a half-valid timetable never reads as done.
class TimetableCompletion {
  const TimetableCompletion({required this.required, required this.placed, this.hard = 0, this.pending = 0});
  final int required, placed, hard, pending;

  int get unplaced => (required - placed).clamp(0, required);
  int get problems => unplaced + hard;
  bool get isComplete => required > 0 && unplaced == 0 && hard == 0 && pending == 0;
  int get pct {
    if (required == 0) return 0;
    final p = (100 * placed) ~/ required;
    return isComplete ? 100 : p.clamp(0, 99);
  }

  /// [result] = schedule.result, [conflicts] = GET …/validate.
  factory TimetableCompletion.of(Map<String, dynamic> result, List<Map<String, dynamic>> conflicts) {
    final o = GenerationOutcome.of(result);
    return TimetableCompletion(
      required: o.required ?? 0,
      placed: o.placed ?? 0,
      hard: conflicts.where((x) => x['severity'] == 'error').length,
      pending: o.pending.length,
    );
  }
}

/// One quick action: relax [rule] alone (null = re-solve the affected part as is). [before] / [after] = unplaced
/// sessions + hard conflicts.
class QuickAction {
  const QuickAction({this.rule, required this.before, required this.after, this.fixes = const [], this.breaks = 0, this.hardAfter = 0, this.unplacedAfter = 0, this.changes = const []});
  final String? rule;
  final int before, after, breaks;
  final int hardAfter, unplacedAfter; // what the re-solve leaves
  final List<Map<String, dynamic>> changes; // what it moves / places (schedule_reassign._diff shape) — the preview
  final List<({int courseId, String kind, int? group, int n})> fixes;

  int get deltaPct => before == 0 ? 0 : ((100 * (after - before)) / before).round();
  bool fixesLoad(int courseId, String kind, int? group) => fixes.any((f) => f.courseId == courseId && f.kind == kind && f.group == group);

  factory QuickAction.of(Map<String, dynamic> m) => QuickAction(
        rule: m['rule'] as String?,
        before: asInt(m['before']),
        after: asInt(m['after']),
        breaks: asInt(m['breaks']),
        hardAfter: asInt(m['hard_after']),
        unplacedAfter: asInt(m['unplaced_after']),
        changes: asMapList(m['changes']),
        fixes: [
          for (final f in asMapList(m['fixes']))
            (courseId: asInt(f['course_id']), kind: '${f['kind'] ?? 'lecture'}', group: f['group_no'] == null ? null : asInt(f['group_no']), n: asInt(f['n'], 1))
        ],
      );
}

class QuickActionsReport {
  const QuickActionsReport({required this.before, required this.actions, this.candidates = const [], this.hard = 0, this.unplaced = 0});
  final int before, hard, unplaced;
  final List<QuickAction> actions; // best first
  final List<String> candidates; // the Locked rules that were tried

  factory QuickActionsReport.of(Map<String, dynamic> m) => QuickActionsReport(
        before: asInt(m['before']),
        hard: asInt(m['hard']),
        unplaced: asInt(m['unplaced']),
        actions: [for (final a in asMapList(m['actions'])) if (a['rule'] == null || _relaxable.contains(a['rule'])) QuickAction.of(a)],
        candidates: [for (final r in (m['candidates'] as List?) ?? const []) '$r'],
      );
}

/// Only switchable rules are ever offered — a hard rule coming from the server is dropped, never shown as an action.
final _relaxable = {for (final r in generationRules) if (r.unlockable) r.key};

/// "Problems 12 → 7 (−42%)"
String impactText(int before, int after) {
  final d = before == 0 ? 0 : ((100 * (after - before)) / before).round();
  final sign = d <= 0 ? '−' : '+';
  return t('المشكلات من $before إلى $after ($sign${d.abs()}٪)', 'Problems $before → $after ($sign${d.abs()}%)');
}

String quickRuleText(String? rule) {
  if (rule == null) return t('أعد حل الحصص المتأثرة فقط', 'Re-solve only the affected sessions');
  final r = generationRules.where((x) => x.key == rule).firstOrNull;
  return r == null ? rule : t('خفّف: ${r.ar}', 'Relax: ${r.en}');
}

/// Loads never scheduled until their staff is fixed.
const staffingReasons = {'no_teacher', 'teacher_not_eligible', 'assistant_not_eligible', 'no_lab_instructor'};

String unplacedReasonText(String r) => switch (r) {
      'rooms_busy' => t('كل القاعات المناسبة محجوزة في كل وقت ممكن', 'Every fitting room is taken at every possible time'),
      'teacher_busy' => t('المدرس يدرّس مقرراً آخر في كل وقت ممكن', 'The teacher teaches another course at every possible time'),
      'teacher_unavailable' => t('المدرس غير متاح في الأوقات المناسبة', 'The teacher is unavailable at the fitting times'),
      'teacher_day_limit' => t('تجاوز الحد اليومي للمدرس', 'Over the teacher\'s daily limit'),
      'students_clash' => t('تتعارض مع مقرر يشترك معه الطلاب', 'Clashes with a course sharing its students'),
      'students_busy_elsewhere' => t('الطلاب مشغولون في جدول منشور آخر', 'The students are busy in another published timetable'),
      'students_unavailable' => t('الطلاب غير متاحين في الأوقات المناسبة', 'The students are unavailable at the fitting times'),
      'no_room_fits' => t('لا قاعة بالنوع والسعة والتجهيزات المطلوبة', 'No room has the required kind, capacity and equipment'),
      'travel_gap' => t('لا وقت كافٍ للانتقال بين المباني', 'Not enough travel time between buildings'),
      'course_already_there' => t('لا أوقات كافية لعدد الحصص', 'Not enough distinct times for the number of sessions'),
      'no_consecutive_periods' => t('الحصة تحتاج فترات متتالية أكثر مما في اليوم', 'Needs more consecutive periods than a day has'),
      'teacher_week_limit' => t('تجاوز الحد الأسبوعي للمدرس', 'Over the teacher\'s weekly cap'),
      'room_unavailable' => t('القاعات المناسبة غير متاحة في الأوقات الممكنة', 'The fitting rooms are unavailable at the possible times'),
      'time_limit' => t('كانت هناك أوقات حرة لكن انتهى وقت الحل', 'Free times existed but the solver ran out of time'),
      'removed_by_hand' => t('حُذفت يدوياً', 'Removed by hand'),
      'proposal_rejected' => t('رُفض اقتراح كسر القاعدة', 'The rule-break proposal was rejected'),
      'no_teacher' => t('لا يوجد مدرس معيّن للمقرر', 'No teacher is assigned to the course'),
      'teacher_not_eligible' => t('المدرس المعيّن غير مؤهل للمقرر', 'The assigned teacher cannot teach this course'),
      'assistant_not_eligible' => t('المعيد المعيّن غير مؤهل للسكشن', 'The assigned TA cannot teach this lab'),
      'no_lab_instructor' => t('لا يوجد معيد للسكشن', 'No TA for the lab'),
      _ => t('لا يوجد وقت متاح', 'No free time'),
    };

String unplacedFixText(String r) => switch (r) {
      'rooms_busy' || 'no_room_fits' => t('أضف قاعة مناسبة أو اجعل "قاعة أكبر" مرنة', 'Add a fitting room, or make "larger hall" flexible'),
      'teacher_busy' || 'teacher_day_limit' => t('عيّن مدرساً آخر مؤهلاً أو أضف وقتاً', 'Assign another eligible teacher, or add a time'),
      'teacher_unavailable' => t('اطلب إتاحة أوسع أو اجعل "إتاحة المدرس" مرنة', 'Ask for more availability, or make instructor availability flexible'),
      'students_clash' || 'students_busy_elsewhere' || 'students_unavailable' => t('أضف يوماً أو فترة أو قسّم المجموعة', 'Add a day or period, or split the group'),
      'course_already_there' || 'no_consecutive_periods' || 'travel_gap' => t('أضف فترات أو أيام دراسة', 'Add periods or study days'),
      'time_limit' => t('ولّد مرة أخرى أو ارفع المهلة', 'Generate again, or raise the time limit'),
      'teacher_week_limit' => t('ارفع الحد الأسبوعي أو عيّن عضواً آخر', 'Raise the weekly cap, or assign another member'),
      'proposal_rejected' || 'removed_by_hand' => t('ضعها يدوياً في خانة فارغة أو أعد التوليد', 'Place it by hand in a free cell, or generate again'),
      _ when staffingReasons.contains(r) => t('عيّن مدرساً / معيداً مؤهلاً من "المقررات والهيئة"', 'Assign an eligible teacher / TA in "Courses & staff"'),
      _ => t('أضف أوقاتاً أو قاعات', 'Add times or rooms'),
    };

String brokenRuleText(String rule) => switch (rule) {
      'teacher_unavailable' => t('في وقت غير متاح للمدرس/المعيد', 'At a time the instructor / TA is unavailable'),
      'teacher_day_limit' => t('يتجاوز الحد اليومي للمدرس', 'Over the teacher\'s daily limit'),
      'room_kind' => t('في قاعة من نوع آخر (أكبر)', 'In another (larger) kind of hall'),
      'room_unavailable' => t('في وقت غير متاح للقاعة', 'At a time the room is unavailable'),
      'room_capabilities' => t('في قاعة تفتقد تجهيزاً مطلوباً', 'In a room missing a required capability'),
      'room_capacity' => t('في قاعة أصغر قليلاً من المجموعة', 'In a room slightly smaller than the group'),
      'students_unavailable' => t('في وقت غير متاح للطلاب', 'At a time the students are unavailable'),
      'students_clash' => t('يتعارض مع حصة أخرى لنفس الطلاب', 'Clashes with another session of the same students'),
      'students_busy_elsewhere' => t('الطلاب مشغولون في جدول آخر', 'The students are busy in another timetable'),
      _ => rule,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

/// THE "Create timetable" action: no questions — a ladder run (D-013) in the background with the timetable's saved
/// ladder; it asks in place at every "Ask me" rung and saves a Draft; the studio follows the run (LadderLivePanel) and
/// shows the result when it ends. An older server without the ladder route gets the autopilot, and without that the
/// plain complete generation.
Future<void> createTimetable(BuildContext context, OrgScheduleProvider p) async {
  final sid = asInt(p.schedule!['id']);
  final ladder = await p.loadLadder(sid);
  var r = ladder != null ? await p.startLadder(sid, auto: false) : await p.startAutopilot();
  if (!r.ok && r.endpointMissing) r = await p.startGeneration(complete: true);
  if (!r.ok && r.code != 'generation_running') toast(orgErrorText(r.error!), error: true);
}

/// Rule control: the truly hard rules stay locked; every other rule is Locked or Flexible, listed in the order it gives
/// way; last resorts are suggestions only. Saved on the timetable (settings.rules) for every later generation.
Future<void> showRulesSheet(BuildContext context, OrgScheduleProvider p, {required bool canEdit}) async {
  final flex = rulesFlexible(asMap(p.schedule?['settings']));
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget row(Widget lead, String text, Widget trail) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 28, child: lead),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: orgText(ctx, size: 13))),
                const SizedBox(width: 8),
                trail,
              ]),
            );
        Widget tag(String s, Color col) => Text(s, style: orgText(ctx, size: 11.5, w: FontWeight.w700, color: col));
        Future<void> save({required bool generate}) async {
          set(() => busy = true);
          final rules = {for (final e in flex.entries) e.key: e.value ? 'flexible' : 'locked'};
          final r = generate ? await p.startGeneration(complete: true, settings: {'rules': rules}) : await p.saveRules(rules);
          if (!ctx.mounted) return;
          set(() => busy = false);
          if (r.ok || r.code == 'generation_running') {
            Navigator.pop(ctx);
          } else {
            toast(orgErrorText(r.error!), error: true);
          }
        }

        var n = 0;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('قواعد التوليد', 'Generation rules')),
            Text(
                t('القواعد المقفلة لا تُكسر أبداً. القواعد المرنة تتراجع عند الحاجة فقط وبهذا الترتيب، وكل كسر يظهر اقتراحاً تقبله أو ترفضه.',
                    'Locked rules are never broken. Flexible rules give way only when needed, in this order, and every break comes back as a proposal you accept or reject.'),
                style: orgText(ctx, size: 12, color: c.textMedium)),
            const SizedBox(height: 10),
            Text(t('قواعد ثابتة', 'Always locked'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
            for (final r in generationRules)
              if (r.fixed) row(Icon(Icons.lock_rounded, size: 18, color: c.textMedium), t(r.ar, r.en), tag(t('مقفلة', 'Locked'), c.textMedium)),
            const SizedBox(height: 10),
            Text(t('قابلة للضبط — بترتيب التراجع', 'Adjustable — in the order they give way'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
            for (final r in breakOrder)
              row(
                CircleAvatar(radius: 12, backgroundColor: c.primary.withValues(alpha: 0.12), child: Text('${++n}', style: orgText(ctx, size: 11, w: FontWeight.w800, color: c.primary))),
                t(r.ar, r.en),
                SizedBox(
                  width: 128,
                  child: AppDropdown<bool>(
                    value: flex[r.key],
                    enabled: canEdit && !busy,
                    items: [
                      DropdownMenuItem(value: false, child: Text(t('مقفلة', 'Locked'), overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: true, child: Text(t('مرنة', 'Flexible'), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => flex[r.key] = v ?? flex[r.key]!),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(t('الملاذ الأخير', 'Last resorts'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
            for (final r in generationRules)
              if (r.suggestionOnly) row(Icon(Icons.lightbulb_outline_rounded, size: 18, color: c.warning), t(r.ar, r.en), tag(t('اقتراح فقط', 'Suggestion only'), c.warning)),
            if (canEdit) ...[
              const SizedBox(height: 14),
              PrimaryButton(
                isLoading: busy,
                label: t('حفظ وإنشاء الجدول', 'Save & create timetable'),
                icon: Icons.auto_awesome_rounded,
                iconBefore: true,
                onPressed: () => save(generate: true),
              ),
              Center(child: TextButton(onPressed: busy ? null : () => save(generate: false), child: Text(t('حفظ القواعد فقط', 'Save the rules only')))),
            ],
          ]),
        );
      }));
}

/// The small live conflicts panel under the toolbar: hard / soft counts and the top conflict types. Tap → details.
class ConflictsPanel extends StatelessWidget {
  const ConflictsPanel({super.key, required this.conflicts, this.onTap});
  final List<Map<String, dynamic>> conflicts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ConflictDigest.of(conflicts);
    final done = _completionOf(context);
    final col = d.hard > 0 ? c.danger : (d.soft > 0 || (done != null && done.required > 0 && !done.isComplete) ? c.warning : c.success);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: col.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withValues(alpha: 0.3))),
        child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Icon(d.hard > 0 ? Icons.error_rounded : (d.soft > 0 ? Icons.warning_amber_rounded : Icons.verified_rounded), size: 18, color: col),
          if (done != null && done.required > 0)
            Text(done.isComplete ? t('الجدول مكتمل', 'Timetable complete') : t('مكتمل ${done.pct}٪', '${done.pct}% complete'),
                style: orgText(context, size: 12.5, w: FontWeight.w800, color: col)),
          Text(
              d.total == 0
                  ? t('لا تعارضات', 'No conflicts')
                  : t('${d.hard} إلزامي · ${d.soft} تنبيه', '${d.hard} hard · ${d.soft} warning(s)'),
              style: orgText(context, size: 12.5, w: FontWeight.w800, color: col)),
          for (final (type, n) in d.top) Text('$n × ${conflictTypeText(type)}', style: orgText(context, size: 12, color: c.textMedium)),
          if (_independentOf(context) case final ind? when ind.containsKey('hard'))
            Text(
              asInt(ind['hard']) == 0 ? t('تحقق مستقل ✓', 'Independently verified ✓') : t('التحقق المستقل: ${asInt(ind['hard'])} خرق', 'Independent check: ${asInt(ind['hard'])} violation(s)'),
              style: orgText(context, size: 12, w: FontWeight.w700, color: asInt(ind['hard']) == 0 ? c.success : c.danger),
            ),
          if (onTap != null && done != null && done.required > 0 && !done.isComplete)
            Text(t('إجراءات سريعة', 'Quick actions'), style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.primary)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: c.textLight),
        ]),
      ),
    );
  }

  Map<String, dynamic>? _independentOf(BuildContext context) {
    try {
      return Provider.of<OrgScheduleProvider>(context).independent;
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// The studio's timetable, when this panel sits under it (null elsewhere, e.g. in a layout test).
  TimetableCompletion? _completionOf(BuildContext context) {
    try {
      final p = Provider.of<OrgScheduleProvider>(context);
      return TimetableCompletion.of(asMap(p.schedule?['result']), conflicts);
    } on ProviderNotFoundException {
      return null;
    }
  }
}

/// The headline of a running generation: the best result so far, else the attempt, else what happens now.
String liveHeadline(Map<String, dynamic> run, LiveRun? live) {
  if (run['status'] == 'failed') return t('فشل التوليد — لم يتغير شيء', 'Generation failed — nothing changed');
  if (run['status'] == 'queued') return t('في الانتظار — سيبدأ التوليد خلال لحظات', 'Queued — generation starts in a moment');
  if (live == null) return t('جارٍ التوليد…', 'Generating…');
  final cur = live.current;
  if (cur != null && cur.kind.startsWith('fix')) return cur.text;        // the autopilot's fix loop speaks for itself
  if (live.hasBest) {
    return t('أفضل نتيجة حتى الآن: ${live.placed} من ${live.required} حصة · محاولة ${live.round} من ${live.roundsMax} كحد أقصى',
        'Best so far: ${live.placed} of ${live.required} sessions · attempt ${live.round} of at most ${live.roundsMax}');
  }
  if (live.round > 0) {
    return t('محاولة ${live.round} من ${live.roundsMax} كحد أقصى · ${live.unplaced} حصة بلا موعد',
        'Attempt ${live.round} of at most ${live.roundsMax} · ${live.unplaced} session(s) unplaced');
  }
  return live.current?.text ?? t('جارٍ التوليد…', 'Generating…');
}

/// While the run is open: what is happening now, every step with its time, the elapsed clock, the attempt's own budget
/// bar, the best result so far and the top reasons (polled by the provider). The clock ticks locally between polls, so a
/// slow attempt still looks alive — and a hint says why it takes time.
class GenerationLivePanel extends StatefulWidget {
  const GenerationLivePanel({super.key, required this.run, this.onCancel, this.compact = false});
  final Map<String, dynamic> run;
  final VoidCallback? onCancel;
  /// Only the headline, the clock and the current step (the veil over the grid).
  final bool compact;

  @override
  State<GenerationLivePanel> createState() => _GenerationLivePanelState();
}

class _GenerationLivePanelState extends State<GenerationLivePanel> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  DateTime _received = DateTime.now(); // when this run map arrived — the clock runs from here between polls
  bool _all = false;

  bool get _open => runIsOpen(widget.run);

  @override
  void initState() {
    super.initState();
    if (_open) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant GenerationLivePanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.run, widget.run)) _received = DateTime.now();
    if (_open && !_spin.isAnimating) _spin.repeat();
    if (!_open && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final run = widget.run;
    final live = LiveRun.of(run);
    final failed = run['status'] == 'failed';
    final open = _open;
    final accent = failed ? c.danger : c.primary;
    final progress = run['progress'] == null ? null : asInt(run['progress']).clamp(0, 100) / 100;
    final steps = live?.steps ?? const <LiveStep>[];
    final current = live?.current;
    final shown = _all || steps.length <= 4 ? steps : steps.sublist(steps.length - 4);

    Widget clockRow() => AnimatedBuilder(
          animation: _spin,
          builder: (_, _) {
            final since = DateTime.now().difference(_received);
            final elapsed = Duration(seconds: (live?.elapsedS ?? 0)) + (open ? since : Duration.zero);
            // how long the current step has run = the whole elapsed time minus the step's offset from the run start
            final offset = current?.at != null && live?.startedAt != null ? current!.at!.difference(live!.startedAt!) : null;
            final inStep = offset == null ? since : (elapsed - offset).isNegative ? Duration.zero : elapsed - offset;
            final limit = current?.limitS;
            final budget = live?.budgetS;
            final hint = open && current != null ? patienceText(inStep, relax: current.relax == true) : null;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(
                  budget != null
                      ? t('المدة ${liveClock(elapsed)} من ${liveClock(Duration(seconds: budget))} كحد أقصى', 'Elapsed ${liveClock(elapsed)} of up to ${liveClock(Duration(seconds: budget))}')
                      : t('المدة ${liveClock(elapsed)}', 'Elapsed ${liveClock(elapsed)}'),
                  style: orgText(context, size: 12, color: c.textMedium),
                ),
                if (current != null && open)
                  Text(
                    limit != null
                        ? t('هذه الخطوة: ${liveClock(inStep)} من ${liveClock(Duration(seconds: limit.round()))}', 'This step: ${liveClock(inStep)} of ${liveClock(Duration(seconds: limit.round()))}')
                        : t('هذه الخطوة: ${liveClock(inStep)}', 'This step: ${liveClock(inStep)}'),
                    style: orgText(context, size: 12, color: c.textMedium),
                  ),
              ]),
              if (current != null && open && limit != null && limit > 0) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (inStep.inMilliseconds / (limit * 1000)).clamp(0.0, 1.0),
                    minHeight: 3,
                    color: c.purple,
                    backgroundColor: c.purple.withValues(alpha: 0.15),
                  ),
                ),
              ],
              if (hint != null && !widget.compact)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.hourglass_top_rounded, size: 16, color: c.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(hint, style: orgText(context, size: 12, color: c.textMedium))),
                    ]),
                  ),
                ),
            ]);
          },
        );

    Widget stepRow(LiveStep s) {
      final now = s.done == false;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 18,
            height: 18,
            child: now
                ? (open ? const Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.remove_rounded, size: 16, color: c.textLight))
                : Icon(s.improved == false ? Icons.trending_flat_rounded : Icons.check_circle_rounded, size: 17, color: s.improved == false ? c.textLight : c.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.ms != null && s.ms! >= 1000 ? '${s.text} · ${liveClock(Duration(milliseconds: s.ms!))}' : s.text,
              style: orgText(context, size: 12.5, w: now ? FontWeight.w700 : FontWeight.w400, color: now ? c.textDark : c.textMedium),
            ),
          ),
        ]),
      );
    }

    final header = Row(children: [
      failed
          ? Icon(Icons.error_rounded, color: accent)
          : RotationTransition(turns: _spin, child: Icon(Icons.autorenew_rounded, color: accent)),
      const SizedBox(width: 8),
      Expanded(child: Text(liveHeadline(run, live), style: orgText(context, w: FontWeight.w800))),
      if (widget.onCancel != null) TextButton(onPressed: widget.onCancel, child: Text(t('إلغاء', 'Cancel'), style: TextStyle(color: c.danger))),
    ]);

    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      if (failed && '${run['error'] ?? ''}'.isNotEmpty) Text('${run['error']}', style: orgText(context, size: 12, color: c.textMedium)),
      if (!failed) ...[
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: progress, minHeight: 6, color: accent, backgroundColor: accent.withValues(alpha: 0.12)),
        ),
        const SizedBox(height: 6),
        clockRow(),
      ],
      if (widget.compact && current != null) stepRow(current),
      if (!widget.compact) ...[
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(t('ما الذي يحدث الآن', 'What is happening'), style: orgText(context, size: 12, w: FontWeight.w800, color: c.textMedium)),
          if (steps.length > 4)
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(_all ? t('أظهر الأخيرة فقط', 'Show the last few') : t('أظهر كل الخطوات (${steps.length})', 'Show every step (${steps.length})'),
                    style: orgText(context, size: 11.5, color: c.primary)),
              ),
            ),
          for (final s in shown) stepRow(s),
        ],
        for (final (reason, n) in live?.top ?? const <(String, int)>[])
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $n × ${unplacedReasonText(reason)}', style: orgText(context, size: 12, color: c.textMedium)),
          ),
      ],
    ]);

    if (widget.compact) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: body,
      );
    }
    return Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: 0.25))), child: AppMeshSurface(color: accent, style: AppMeshStyle.wash, radius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: body)));
  }
}

/// Over the grid while a new version is being generated: the old version stays visible but dimmed and untouchable, and
/// the compact live panel sits in the middle, so it is clear what is being worked on right now.
class GenerationVeil extends StatelessWidget {
  const GenerationVeil({super.key, required this.run, this.onCancel});
  final Map<String, dynamic> run;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: c.surface.withValues(alpha: 0.72),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(child: GenerationLivePanel(run: run, onCancel: onCancel, compact: true)),
        ),
      ),
    );
  }
}

/// The Quick Actions panel (and result of the last generation): completion, problems per course with their reason and
/// the one-rule fixes that solve them (impact shown before applying), proposals, last-resort advice, conflicts.
Future<void> showGenerationResult(BuildContext context, OrgScheduleProvider p, Map<int, String> courseNames, {required bool canEdit}) =>
    showAdminSheet<void>(context, (ctx) => QuickActionsPanel(p: p, names: courseNames, canEdit: canEdit));

/// GET …/quick-actions (dry run). Null + [missing] when the server has no such route yet.
Future<({QuickActionsReport? report, bool missing})> fetchQuickActions(OrgScheduleProvider p) async {
  final r = await orgCall(() => p.api.get('${p.base}/schedules/${p.schedule!['id']}/quick-actions'), quiet: true);
  return (report: r.ok ? QuickActionsReport.of(r.map) : null, missing: r.endpointMissing);
}

/// POST …/quick-actions/apply — relaxes [rule] alone (stored Flexible) and re-solves only the affected sessions.
Future<OrgCall> applyQuickAction(OrgScheduleProvider p, String? rule) async {
  final id = asInt(p.schedule!['id']);
  final r = await orgCall(
      () => p.api.post('${p.base}/schedules/$id/quick-actions/apply', body: {'rule': rule, 'expected_version': ?p.schedule!['version']}),
      ok: t('طُبّق الإجراء — الجدول ما زال مسودة', 'Applied — the timetable is still a draft'));
  if (r.ok || r.code == 'stale_version') await p.open(id);
  return r;
}

/// The studio's side panel (wide) / sheet (narrow): [studioQuickActions] in org_schedule_pages.dart.
Widget quickActionsSide(BuildContext context, OrgScheduleProvider p) {
  final s = context.read<OrgSession>();
  return QuickActionsPanel(
    p: p,
    names: {for (final l in p.loads) asInt(l['course_id']): courseName(l)},
    canEdit: s.can('schedule', 'update') && p.schedule?['status'] != 'active',
  );
}

class QuickActionsPanel extends StatefulWidget {
  const QuickActionsPanel({super.key, required this.p, required this.names, required this.canEdit});
  final OrgScheduleProvider p;
  final Map<int, String> names;
  final bool canEdit;

  @override
  State<QuickActionsPanel> createState() => _QuickActionsPanelState();
}

class _QuickActionsPanelState extends State<QuickActionsPanel> {
  List<ScheduleSuggestion>? advice;
  QuickActionsReport? quick;
  PreflightReport? preflight; // GET …/preflight (null: not loaded / old server)
  RemedyReport? remedies; // GET …/remedies: every conflict with ranked ways out (null: not loaded / old server)
  bool quickLoading = false, quickMissing = false, applying = false, remediesMissing = false;
  final busy = <String>{};
  final pfBusy = <String>{}; // pre-flight recommendation keys with a request in flight ('*' = accept-all)
  final rmBusy = <String>{}; // conflict keys with a remedy being applied
  bool _needRegen = false; // a data fix was saved: the timetable must be re-solved to use it
  String? _seen; // the timetable version + hard-clash count the panel was computed for

  Map<int, String> get _rooms => {for (final r in widget.p.rooms) asInt(r['id']): '${r['name']}'};
  List<String> get _days => ScheduleDraft.fromJson(widget.p.schedule ?? const {}).days;

  /// Before / after of one change on the grid; false when the person keeps the current version.
  Future<bool> _preview(ChangePlan plan, {String? applyLabel}) async =>
      await showChangePreview(context, plan, slots: widget.p.slots, periods: widget.p.periods, days: _days, names: widget.names, people: _people, rooms: _rooms, applyLabel: applyLabel) == true;

  /// The autopilot from the panel: the studio's live panel takes over while it runs.
  Future<void> _runAutopilot() async {
    final r = await runAutopilotWithPlan(context, widget.p);
    if (!mounted || r == null) return;
    setState(() => _needRegen = false);
  }

  /// Back to the revision taken before the run; data fixes stay (they are in the audit log).
  Future<void> _undoAutopilot(AutopilotReport r) async {
    final id = r.beforeRevisionId;
    if (id == null) return;
    final ok = await confirm(context,
        message: t('يعود الجدول كما كان قبل الإصلاح التلقائي${r.beforeSlots == 0 ? ' (كان فارغاً)' : ''}. تبقى تغييرات البيانات، وهي مسجّلة في السجل.',
            'The timetable goes back to how it was before the automatic run${r.beforeSlots == 0 ? ' (it was empty)' : ''}. Data changes stay; they are in the audit log.'),
        confirmLabel: t('تراجع', 'Undo'),
        danger: true);
    if (!ok || !mounted) return;
    await widget.p.restoreRevision(id);
  }

  String get _key => '${widget.p.schedule?['version']}|${widget.p.conflicts.where((x) => x['severity'] == 'error').length}|${runIsOpen(widget.p.genRun)}';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _seen = _key;
    if (runIsOpen(widget.p.genRun)) return; // a generation is writing the timetable: nothing to act on yet
    final done = TimetableCompletion.of(asMap(widget.p.schedule?['result']), widget.p.conflicts);
    if (done.unplaced > 0) _loadAdvice();
    if (widget.canEdit && done.problems > 0) _loadQuick();
    if (!done.isComplete) _loadPreflight();
    if (widget.p.conflicts.isNotEmpty) _loadRemedies();
  }

  Future<void> _loadRemedies() async {
    final r = await fetchRemedies(widget.p);
    if (!mounted) return;
    setState(() {
      remedies = r.report;
      remediesMissing = r.missing;
    });
  }

  /// One ranked way out of a conflict: a slot move / room change / group fix goes through the slot PUT (a remaining
  /// clash asks to force it), `resolve` re-solves the clashing part, the data fixes are the pre-flight ones.
  Future<void> _applyRemedy(RemedyItem item, ActionOption a) async {
    // the snapshot before / after with what moves highlighted; an older server without the preview gets the text
    final pv = await previewRemedy(widget.p, a);
    if (!mounted) return;
    final ok = pv.plan != null ? await _preview(pv.plan!) : await confirm(context, message: '${a.text}\n${a.why}', confirmLabel: t('تطبيق', 'Apply'));
    if (!ok || !mounted) return;
    String? reason;
    if (a.kind == 'override') {
      reason = await askText(context, title: t('سبب التجاوز (يظهر في السجل)', 'Reason for the override (kept in the log)'), multiline: true);
      if (reason == null || reason.trim().length < 3 || !mounted) return;
    }
    setState(() => rmBusy.add(item.key));
    var r = await applyRemedy(widget.p, a, overrideReason: reason?.trim());
    if (mounted && r.code == 'schedule_conflict') {
      final force = await confirm(context,
          message: t('ما زال هناك تعارض إلزامي بعد هذا التغيير. الحفظ رغم ذلك؟', 'A hard conflict remains after this change. Save anyway?'), danger: true);
      if (force && mounted) r = await applyRemedy(widget.p, a, force: true, overrideReason: reason?.trim());
    }
    if (!mounted) return;
    setState(() => rmBusy.remove(item.key));
    if (!r.ok) {
      if (r.code != 'schedule_conflict') toast(orgErrorText(r.error!), error: true);
      if (r.code == 'action_not_found' || r.code == 'stale_version') _loadRemedies();
      return;
    }
    final applied = asMap(r.map['applied']);
    if (applied['regenerate'] == true) {
      toast(t('حُفظ التغيير — أعد الحل ليُستخدم', 'Saved — re-solve to use it'));
      setState(() => _needRegen = true);
    } else {
      toast(t('طُبّق الحل', 'Applied'));
    }
    _loadRemedies();
  }

  Future<void> _loadPreflight() async {
    final p = widget.p;
    final id = p.schedule?['id'];
    if (id == null) return;
    final r = await orgCall(() => p.api.get('${p.base}/schedules/$id/preflight'), quiet: true);
    if (mounted && r.ok) setState(() => preflight = PreflightReport.of(r.map));
  }

  /// A recommendation as a quick action: Accept applies the server-side fix (course plan groups / weekly cap) and the
  /// draft must then be regenerated; Reject hides it (Restore undoes). The reply is the fresh report.
  Future<void> _acceptFinding(PreflightFinding f, ActionOption a) async {
    final ok = await confirm(context,
        message: '${a.text.isEmpty ? f.actionText : a.text}${a.why.isEmpty ? '' : '\n${a.why}'}\n${t('يُحفظ التغيير فوراً، ثم أعد التوليد ليُستخدم.', 'The change is saved now; regenerate to use it.')}',
        confirmLabel: t('قبول', 'Accept'));
    if (!ok || !mounted) return;
    await _preflightPost('accept', f, actionId: a.id);
  }

  /// The best automatic fix of every standing blocker, one after the other (POST …/preflight/accept-all).
  Future<void> _acceptAllFindings() async {
    final n = preflight?.visible.where((f) => f.blocker && f.automatic).length ?? 0;
    final ok = await confirm(context,
        message: t('تُطبَّق أفضل توصية تلقائية لكل مانع ($n) واحدة تلو الأخرى، ثم أعد التوليد.', 'The best automatic fix of each blocker ($n) is applied one after the other; then regenerate.'),
        confirmLabel: t('قبول الكل', 'Accept all'));
    if (!ok || !mounted) return;
    final p = widget.p;
    final id = p.schedule?['id'];
    if (id == null) return;
    setState(() => pfBusy.add('*'));
    final r = await orgCall(() => p.api.post('${p.base}/schedules/$id/preflight/accept-all', body: {'only_blockers': true}));
    if (!mounted) return;
    setState(() {
      pfBusy.remove('*');
      if (r.ok) preflight = PreflightReport.of(r.map);
    });
    if (r.ok) {
      final applied = asMapList(r.map['applied']).length;
      final skipped = asMapList(r.map['skipped']).length;
      toast(t('طُبّقت $applied توصية${skipped > 0 ? ' · تعذّر $skipped' : ''} — أعد الحل', '$applied applied${skipped > 0 ? ' · $skipped skipped' : ''} — re-solve to use them'));
      if (applied > 0) setState(() => _needRegen = true);
    }
  }

  Future<void> _rejectFinding(PreflightFinding f) => _preflightPost('dismiss', f);
  Future<void> _restoreFinding(PreflightFinding f) => _preflightPost('dismiss', f, undo: true);

  Future<void> _preflightPost(String what, PreflightFinding f, {bool undo = false, String? actionId}) async {
    final p = widget.p;
    final id = p.schedule?['id'];
    if (id == null || f.key.isEmpty) return;
    setState(() => pfBusy.add(f.key));
    final r = await orgCall(() => p.api.post('${p.base}/schedules/$id/preflight/$what', body: {'key': f.key, 'undo': undo, 'action_id': ?actionId}));
    if (!mounted) return;
    setState(() {
      pfBusy.remove(f.key);
      if (r.ok) preflight = PreflightReport.of(r.map);
    });
    if (!r.ok) {
      toast(orgErrorText(r.error!), error: true);
      if (r.code == 'finding_not_found') _loadPreflight();
      return;
    }
    if (what == 'accept') {
      toast(t('طُبّقت التوصية — أعد الحل لاستخدامها', 'Applied — re-solve to use it'));
      setState(() => _needRegen = true);
    }
  }

  Future<void> _loadQuick() async {
    setState(() => quickLoading = true);
    final r = await fetchQuickActions(widget.p);
    if (!mounted) return;
    setState(() {
      quick = r.report;
      quickMissing = r.missing;
      quickLoading = false;
    });
  }

  Future<void> _loadAdvice() async {
    final p = widget.p;
    try {
      final l = await suggestionApi(p).list(asInt(p.schedule!['id']));
      if (mounted) setState(() => advice = l.items.where((s) => s.status == 'pending').toList());
    } catch (_) {
      if (mounted) setState(() => advice = const []);
    }
  }

  Future<void> _apply(QuickAction a) async {
    final plan = ChangePlan.quick(
      title: quickRuleText(a.rule),
      hardBefore: quick?.hard ?? 0,
      unplacedBefore: quick?.unplaced ?? 0,
      hardAfter: a.hardAfter,
      unplacedAfter: a.unplacedAfter,
      changes: a.changes,
      breaks: a.breaks,
    );
    final ok = await _preview(plan);
    if (!ok || !mounted) return;
    setState(() => applying = true);
    final r = await applyQuickAction(widget.p, a.rule);
    if (!mounted) return;
    setState(() {
      applying = false;
      quick = null;
    });
    if (r.ok || r.code == 'stale_version') _refresh();
  }

  Future<void> _decide(String block, bool accept) async {
    setState(() => busy.add(block));
    await widget.p.decideProposals([block], accept: accept);
    if (mounted) setState(() => busy.remove(block));
  }

  /// "Accept all" on the ladder's result card: every proposal still pending, in one call.
  Future<void> _acceptAllProposals(List<String> ids) async {
    final ok = await confirm(context,
        message: t('قبول كل الاقتراحات (${ids.length})؟ تبقى الحصص كما وضعها التوليد، بالقواعد التي كُسرت.', 'Accept every proposal (${ids.length})? The sessions stay where the run put them, with the rules it bent.'),
        confirmLabel: t('قبول الكل', 'Accept all'));
    if (!ok || !mounted) return;
    setState(() => busy.addAll(ids));
    await widget.p.decideProposals(ids, accept: true);
    if (mounted) setState(() => busy.removeAll(ids));
  }

  final _proposalsKey = GlobalKey();

  void _scrollToProposals() {
    final ctx = _proposalsKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.05);
  }

  String _name(Map<String, dynamic> x) {
    final g = x['group_no'] == null ? '' : ' · ${t('مجموعة', 'group')} ${x['group_no']}';
    final kind = switch ('${x['kind'] ?? 'lecture'}') { 'lab' => ' · ${t('عملي', 'lab')}', 'tutorial' || 'section' => ' · ${t('سكشن', 'section')}', _ => '' };
    return '${widget.names[asInt(x['course_id'])] ?? '#${x['course_id']}'}$kind$g';
  }

  Map<int, String> get _people => {for (final m in widget.p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']}'};

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.p, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.colors;
    final p = widget.p;
    if (_key != _seen && !quickLoading && !applying) {
      _seen = _key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => quick = null);
        _refresh();
      });
    }
    final result = asMap(p.schedule?['result']);
    final o = GenerationOutcome.of(result);
    final done = TimetableCompletion.of(result, p.conflicts);
    final blocks = <String, Map<String, dynamic>>{};
    for (final x in o.proposals) {
      blocks.putIfAbsent('${x['block_id']}', () => x);
    }
    final actions = quick?.actions ?? const <QuickAction>[];
    final autopilot = AutopilotReport.of(result);
    final ladder = LadderReport.of(result);
    if (runIsOpen(p.genRun)) {                       // the autopilot / a generation is writing the timetable
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        SheetHeader(t('جارٍ العمل على الجدول', 'Working on the timetable')),
        // a ladder run: the live overlay with the decision inline (the side panel is where the run is watched)
        if (LadderLive.of(p.genRun) != null) LadderLivePanel(p: p, inlineDecision: true) else GenerationLivePanel(run: p.genRun!, onCancel: () => p.cancelGeneration()),
      ]);
    }
    final pendingIds = pendingBlockIds(o.proposals);
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SheetHeader(done.isComplete ? t('نتيجة التوليد', 'Generation result') : t('الإجراءات السريعة', 'Quick actions')),
      if (ladder != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LadderResultCard(
            report: ladder,
            names: widget.names,
            pending: pendingIds.length,
            onAcceptAll: widget.canEdit && pendingIds.isNotEmpty ? () => _acceptAllProposals(pendingIds) : null,
            onOpenProposals: pendingIds.isNotEmpty ? _scrollToProposals : null,
            onOpenLadder: p.schedule?['id'] == null ? null : () => showLadderSheet(context, p, asInt(p.schedule!['id']), canEdit: widget.canEdit),
          ),
        ),
      _completionCard(context, done, o),
      if (widget.canEdit && (done.problems > 0 || _needRegen)) _autopilotCard(context, done),
      if (autopilot != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: AutopilotSummaryCard(report: autopilot, onUndo: widget.canEdit ? () => _undoAutopilot(autopilot) : null)),
      if (applying) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      if (preflight != null && preflight!.findings.isNotEmpty && !done.isComplete)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: DataHealthCard(
            report: preflight!,
            courseNames: widget.names,
            people: _people,
            rooms: {for (final r in p.rooms) asInt(r['id']): '${r['name']}'},
            onAccept: widget.canEdit ? _acceptFinding : null,
            onAcceptAll: widget.canEdit ? _acceptAllFindings : null,
            onReject: widget.canEdit ? _rejectFinding : null,
            onRestore: widget.canEdit ? _restoreFinding : null,
            busy: pfBusy,
          ),
        ),
      if (p.slots.isNotEmpty && (done.isComplete || done.unplaced == 0))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: QualityCard(
            report: QualityReport.of(p.slots, p.periods, days: ScheduleDraft.fromJson(p.schedule ?? const {}).days, rooms: p.rooms),
            people: _people,
            relaxed: asMapList(result['relaxed']).length,
            broken: o.proposals.length,
            solver: result['solver'] == null ? null : asMap(result['solver']),
          ),
        ),
      if (widget.canEdit && done.problems > 0) ...[
        _title(context, t('حلول سريعة — قاعدة واحدة في كل مرة', 'Quick fixes — one rule at a time')),
        if (quickLoading)
          const SizedBox(height: 2 * 82.0, child: AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero))
        else if (quickMissing)
          _note(context, Icons.cloud_off_rounded, t('الإجراءات السريعة تحتاج تحديث الخادم.', 'Quick actions need a server update.'))
        else if (quick != null && actions.isEmpty)
          _note(context, Icons.info_outline_rounded,
              t('لا يحل تخفيف قاعدة واحدة أي مشكلة. جرّب الاقتراحات أدناه أو عدّل يدوياً.', 'No single rule relaxation helps. Try the suggestions below, or edit by hand.'))
        else
          for (final a in actions) _actionCard(context, a),
        _lockedNote(context),
      ],
      if (o.unplaced.isNotEmpty) ...[
        _title(context, t('مقررات بها مشكلات', 'Courses with problems')),
        for (final u in o.unplaced) _problem(context, u, actions),
      ],
      if (blocks.isNotEmpty) ...[
        KeyedSubtree(key: _proposalsKey, child: _title(context, t('قواعد مرنة كُسرت (اقتراحات)', 'Flexible rules broken (proposals)'))),
        for (final e in blocks.entries)
          _proposal(context, e.key, [for (final x in o.proposals) if ('${x['block_id']}' == e.key) x]),
      ],
      if (advice != null && advice!.isNotEmpty) ...[
        _title(context, t('الملاذ الأخير — اقتراحات فقط، لا تُطبّق تلقائياً', 'Last resorts — suggestions only, never applied automatically')),
        for (final s in advice!.take(6))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(suggestionTypeIcon(s.type), color: c.warning),
            title: Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title),
            subtitle: s.reason.isEmpty ? null : Text(s.reason),
          ),
      ],
      if (p.conflicts.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: done.hard > 0,
            title: Text(t('التعارضات (${p.conflicts.length})', 'Conflicts (${p.conflicts.length})'), style: orgText(context, w: FontWeight.w800)),
            subtitle: Text(
                remedies == null && !remediesMissing
                    ? t('جارٍ حساب الحلول…', 'Working out the fixes…')
                    : t('لكل تعارض حلول مرتّبة — الأفضل أولاً', 'Every conflict has ranked ways out — best first'),
                style: orgText(context, size: 12, color: c.textMedium)),
            children: [
              if (remedies != null)
                RemediesPanel(report: remedies!, courseNames: widget.names, onAccept: widget.canEdit ? _applyRemedy : null, busy: rmBusy)
              else if (remediesMissing)
                RemediesPanel(report: RemedyReport(items: [for (final x in p.conflicts) RemedyItem(key: '${x['type']}', conflict: x, actions: const [])]), courseNames: widget.names)
              else
                const SizedBox(height: 2 * 82.0, child: AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)),
            ],
          ),
        ),
    ]);
  }

  Widget _completionCard(BuildContext context, TimetableCompletion d, GenerationOutcome o) {
    final c = context.colors;
    final col = d.isComplete ? c.success : (d.hard > 0 ? c.danger : c.warning);
    final parts = [
      t('وُضعت ${d.placed} من ${d.required} حصة', '${d.placed} of ${d.required} sessions placed'),
      if (d.hard > 0) t('${d.hard} تعارض إلزامي', '${d.hard} hard conflict(s)'),
      if (d.pending > 0) t('${d.pending} اقتراح بانتظار قرارك', '${d.pending} proposal(s) pending'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: col.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(d.isComplete ? Icons.verified_rounded : Icons.pending_actions_rounded, color: col),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                d.isComplete ? t('الجدول مكتمل وبلا تعارضات', 'Timetable complete, no conflicts') : t('الجدول مكتمل بنسبة ${d.pct}٪', 'Timetable is ${d.pct}% complete'),
                style: orgText(context, size: 15, w: FontWeight.w800, color: col)),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: d.pct / 100, minHeight: 7, color: col, backgroundColor: col.withValues(alpha: 0.15)),
        ),
        const SizedBox(height: 8),
        Text(parts.join(' · '), style: orgText(context, size: 12.5, color: c.textMedium)),
        if (o.stopped == 'no_progress' || o.stopped == 'time_limit')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(t('انتهى التوليد بأفضل نتيجة ممكنة بالقواعد الحالية.', 'Generation finished with the best result the current rules allow.'),
                style: orgText(context, size: 12, color: c.textMedium)),
          ),
      ]),
    );
  }

  /// One button for the whole review stage: every automatic fix, validated, then a re-solve — nothing forced.
  Widget _autopilotCard(BuildContext context, TimetableCompletion d) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.primary.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_fix_high_rounded, color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(_needRegen ? t('حُفظت تغييرات في البيانات — أعد الحل', 'Data changes saved — re-solve now') : t('دع النظام يصلح ما يستطيع', 'Let the system fix what it can'), style: orgText(context, size: 14, w: FontWeight.w800, color: c.primary))),
          ]),
          const SizedBox(height: 4),
          Text(
              _needRegen
                  ? t('يُعاد التوليد بالبيانات الجديدة، ثم يُطبَّق أفضل حل تلقائي لكل تعارض يبقى، ولا يُفرض شيء.', 'The timetable is regenerated with the new data, then the best automatic fix of every remaining clash is applied; nothing is forced.')
                  : t('لكل تعارض (${d.hard}) وحصة بلا موعد (${d.unplaced}) يُطبَّق أفضل حل تلقائي بعد التحقق منه، وتُعاد جدولة ما يلزم فقط. ما يحتاج قراراً بشرياً يبقى لك.',
                      'For every clash (${d.hard}) and unplaced session (${d.unplaced}) the best automatic fix is applied after validation, and only what must move is re-solved. Whatever needs a human decision stays with you.'),
              style: orgText(context, size: 12.5, color: c.textMedium)),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(onPressed: _runAutopilot, icon: const Icon(Icons.auto_fix_high_rounded, size: 18), label: Text(_needRegen ? t('أعد الحل الآن', 'Re-solve now') : t('أصلح تلقائياً', 'Fix automatically'))),
          ),
        ]),
      ),
    );
  }

  Widget _actionCard(BuildContext context, QuickAction a) {
    final c = context.colors;
    final names = {for (final f in a.fixes) _name({'course_id': f.courseId, 'kind': f.kind, 'group_no': f.group})}.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RowCard(
        accent: c.primary,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(a.rule == null ? Icons.refresh_rounded : Icons.lock_open_rounded, size: 20, color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(quickRuleText(a.rule), style: orgText(context, w: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(impactText(a.before, a.after), style: orgText(context, size: 12, w: FontWeight.w800, color: c.success)),
            ),
            if (a.breaks > 0) Text(t('${a.breaks} اقتراح للمراجعة', '${a.breaks} proposal(s) to review'), style: orgText(context, size: 12, color: c.warning)),
          ]),
          if (names.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${t('يحل', 'Fixes')}: ${names.take(4).join('، ')}${names.length > 4 ? ' +${names.length - 4}' : ''}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: applying ? null : () => _apply(a),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: Text(t('تطبيق', 'Apply')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _problem(BuildContext context, Map<String, dynamic> u, List<QuickAction> actions) {
    final c = context.colors;
    final reason = '${u['reason'] ?? u['type']}';
    final fixers = [
      for (final a in actions)
        if (a.fixesLoad(asInt(u['course_id']), '${u['kind'] ?? 'lecture'}', u['group_no'] == null ? null : asInt(u['group_no']))) a
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RowCard(
        accent: c.warning,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_name(u)} · ${t('${asInt(u['missing'], 1)} حصة', '${asInt(u['missing'], 1)} session(s)')}', style: orgText(context, w: FontWeight.w700)),
          Text(unplacedReasonText(reason), style: orgText(context, size: 12, color: c.textMedium)),
          if ((u['core'] as List?)?.isNotEmpty == true)
            Text(coreText([for (final r in u['core'] as List) '$r']), style: orgText(context, size: 12, w: FontWeight.w700, color: c.textMedium)),
          Text(unplacedFixText(reason), style: orgText(context, size: 12, color: c.textLight)),
          if (asMapList(u['explain']).isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: Text(t('لماذا كل وقت مرفوض؟', 'Why is each time blocked?'), style: orgText(context, size: 12, w: FontWeight.w700, color: c.primary)),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ExplainRows(
                      rows: asMapList(u['explain']),
                      courseNames: widget.names,
                      periodLabel: (pid) => '${widget.p.periods.where((x) => asInt(x['id']) == pid).map((x) => x['label']).firstOrNull ?? 'P$pid'}',
                    ),
                  ),
                ],
              ),
            ),
          if (fixers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in fixers.take(3))
                  ActionChip(
                    avatar: Icon(Icons.bolt_rounded, size: 16, color: c.primary),
                    label: Text('${quickRuleText(a.rule)} · ${a.deltaPct}%', overflow: TextOverflow.ellipsis),
                    onPressed: applying ? null : () => _apply(a),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _lockedNote(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_rounded, size: 16, color: c.textLight),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
              '${t('لا تُخفَّف أبداً', 'Never relaxed')}: ${[for (final r in generationRules) if (r.fixed) t(r.ar, r.en)].join(' · ')}',
              style: orgText(context, size: 11.5, color: c.textLight)),
        ),
      ]),
    );
  }

  Widget _note(BuildContext context, IconData icon, String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: c.textMedium),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: orgText(context, size: 12.5, color: c.textMedium))),
      ]),
    );
  }

  Widget _title(BuildContext context, String s) =>
      Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(s, style: orgText(context, w: FontWeight.w800)));

  Widget _proposal(BuildContext context, String block, List<Map<String, dynamic>> items) {
    final c = context.colors;
    final x = items.first;
    final dec = x['decision'];
    return RowCard(
      accent: dec == null ? c.warning : (dec == 'accepted' ? c.success : c.textLight),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_name(x)} · ${dayLabels()[x['day']] ?? x['day']}', style: orgText(context, w: FontWeight.w700)),
        for (final i in items) Text('• ${brokenRuleText('${i['rule']}')}', style: orgText(context, size: 12, color: c.textMedium)),
        if (dec != null)
          Text(dec == 'accepted' ? t('مقبول', 'Accepted') : t('مرفوض', 'Rejected'), style: orgText(context, size: 12, w: FontWeight.w700))
        else if (widget.canEdit)
          busy.contains(block)
              ? const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
              : Wrap(spacing: 8, children: [
                  TextButton.icon(onPressed: () => _decide(block, true), icon: Icon(Icons.check_rounded, color: c.success), label: Text(t('قبول', 'Accept'))),
                  TextButton.icon(onPressed: () => _decide(block, false), icon: Icon(Icons.close_rounded, color: c.danger), label: Text(t('رفض', 'Reject'))),
                ]),
      ]),
    );
  }
}
