// lib/features/org/org_schedule_generate.dart — the ONE "Generate timetable" action.
//
// The server runs strict rounds, then rounds that may break only the rules the admin marked Flexible, until every
// session is placed or no round makes progress (POST …/generate {complete: true}, schedule_jobs.complete). It saves
// a Draft. Every broken rule comes back as a proposal (result.broken[].decision null) the admin accepts or rejects;
// publishing waits for all of them (409 proposals_pending).
//
//   GenerationRule / generationRules   pure: the rule set shown before generating (settings.rules)
//   GenerationOutcome                  pure: placed / unplaced / proposals, from schedule.result
//   LiveRun                            pure: the live counters of a running generation (run.summary)
//   createTimetable                    the one action (no questions, background, Draft)   GenerationLivePanel while it runs
//   showRulesSheet                     Locked / Flexible per rule, in break order; last resorts are suggestions only
//   ConflictDigest / ConflictsPanel    the small live conflicts panel (counts + top types)
//   showGenerationResult               result: unplaced with reason + fix, proposals, advice, conflicts (read-only)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../../design/app_kit.dart' show AppDropdown;
import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show RowCard;
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_schedule_optimizer.dart';
import 'org_timetable_parts.dart' show ConflictList;
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
  const LiveRun({required this.round, required this.roundsMax, required this.unplaced, required this.top});
  final int round, roundsMax, unplaced;
  final List<(String, int)> top;

  static LiveRun? of(Map<String, dynamic>? run) {
    final s = asMap(run?['summary']);
    if (s['live'] != true) return null;
    return LiveRun(
      round: asInt(s['round']),
      roundsMax: asInt(s['rounds_max'], 6),
      unplaced: asInt(s['unplaced']),
      top: [for (final x in asMapList(s['top'])) ('${x['reason']}', asInt(x['n']))],
    );
  }
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
      'proposal_rejected' || 'removed_by_hand' => t('ضعها يدوياً في خانة فارغة أو أعد التوليد', 'Place it by hand in a free cell, or generate again'),
      _ when staffingReasons.contains(r) => t('عيّن مدرساً / معيداً مؤهلاً من "المقررات والهيئة"', 'Assign an eligible teacher / TA in "Courses & staff"'),
      _ => t('أضف أوقاتاً أو قاعات', 'Add times or rooms'),
    };

String brokenRuleText(String rule) => switch (rule) {
      'teacher_unavailable' => t('في وقت غير متاح للمدرس/المعيد', 'At a time the instructor / TA is unavailable'),
      'teacher_day_limit' => t('يتجاوز الحد اليومي للمدرس', 'Over the teacher\'s daily limit'),
      'room_kind' => t('في قاعة من نوع آخر (أكبر)', 'In another (larger) kind of hall'),
      'room_unavailable' => t('في وقت غير متاح للقاعة', 'At a time the room is unavailable'),
      'students_unavailable' => t('في وقت غير متاح للطلاب', 'At a time the students are unavailable'),
      _ => rule,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

/// THE "Create timetable" action: no questions — the server generates in the background with the stored rules and
/// saves a Draft; the studio follows the run (live panel) and shows the result when it ends.
Future<void> createTimetable(BuildContext context, OrgScheduleProvider p) async {
  final r = await p.startGeneration(complete: true);
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
    final col = d.hard > 0 ? c.danger : (d.soft > 0 ? c.warning : c.success);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: col.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withValues(alpha: 0.3))),
        child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Icon(d.hard > 0 ? Icons.error_rounded : (d.soft > 0 ? Icons.warning_amber_rounded : Icons.verified_rounded), size: 18, color: col),
          Text(
              d.total == 0
                  ? t('لا تعارضات', 'No conflicts')
                  : t('${d.hard} إلزامي · ${d.soft} تنبيه', '${d.hard} hard · ${d.soft} warning(s)'),
              style: orgText(context, size: 12.5, w: FontWeight.w800, color: col)),
          for (final (type, n) in d.top) Text('$n × ${conflictTypeText(type)}', style: orgText(context, size: 12, color: c.textMedium)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: c.textLight),
        ]),
      ),
    );
  }
}

/// While the run is open: round, unresolved sessions and the top reasons (polled by the provider).
class GenerationLivePanel extends StatelessWidget {
  const GenerationLivePanel({super.key, required this.run, this.onCancel});
  final Map<String, dynamic> run;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = LiveRun.of(run);
    final failed = run['status'] == 'failed';
    return RowCard(
      accent: failed ? c.danger : c.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(failed ? Icons.error_rounded : Icons.autorenew_rounded, color: failed ? c.danger : c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                failed
                    ? t('فشل التوليد — لم يتغير شيء', 'Generation failed — nothing changed')
                    : live == null
                        ? t('جارٍ التوليد…', 'Generating…')
                        : t('الجولة ${live.round} من ${live.roundsMax} · ${live.unplaced} حصة بلا موعد', 'Round ${live.round} of ${live.roundsMax} · ${live.unplaced} session(s) unplaced'),
                style: orgText(context, w: FontWeight.w800)),
          ),
          if (onCancel != null) TextButton(onPressed: onCancel, child: Text(t('إلغاء', 'Cancel'), style: TextStyle(color: c.danger))),
        ]),
        if (failed && '${run['error'] ?? ''}'.isNotEmpty) Text('${run['error']}', style: orgText(context, size: 12, color: c.textMedium)),
        if (!failed) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: run['progress'] == null ? null : asInt(run['progress']).clamp(0, 100) / 100),
        ],
        for (final (reason, n) in live?.top ?? const <(String, int)>[])
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $n × ${unplacedReasonText(reason)}', style: orgText(context, size: 12, color: c.textMedium)),
          ),
      ]),
    );
  }
}

/// The result of the last generation: what is unplaced and why, the proposals, last-resort advice, conflicts.
Future<void> showGenerationResult(BuildContext context, OrgScheduleProvider p, Map<int, String> courseNames, {required bool canEdit}) =>
    showAdminSheet<void>(context, (ctx) => _ResultSheet(p: p, names: courseNames, canEdit: canEdit));

class _ResultSheet extends StatefulWidget {
  const _ResultSheet({required this.p, required this.names, required this.canEdit});
  final OrgScheduleProvider p;
  final Map<int, String> names;
  final bool canEdit;

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  List<ScheduleSuggestion>? advice;
  final busy = <String>{};

  @override
  void initState() {
    super.initState();
    if (GenerationOutcome.of(asMap(widget.p.schedule?['result'])).missing > 0) _loadAdvice();
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

  Future<void> _decide(String block, bool accept) async {
    setState(() => busy.add(block));
    await widget.p.decideProposals([block], accept: accept);
    if (mounted) setState(() => busy.remove(block));
  }

  String _name(Map<String, dynamic> x) {
    final g = x['group_no'] == null ? '' : ' · ${t('مجموعة', 'group')} ${x['group_no']}';
    return '${widget.names[asInt(x['course_id'])] ?? '#${x['course_id']}'}${x['kind'] == 'lab' ? ' · ${t('عملي', 'lab')}' : ''}$g';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.p, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.colors;
    final p = widget.p;
    final o = GenerationOutcome.of(asMap(p.schedule?['result']));
    final blocks = <String, Map<String, dynamic>>{};
    for (final x in o.proposals) {
      blocks.putIfAbsent('${x['block_id']}', () => x);
    }
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SheetHeader(t('نتيجة التوليد', 'Generation result')),
      Text(t('وُضعت ${o.placed ?? '?'} من ${o.required ?? '?'} حصة', 'Placed ${o.placed ?? '?'} of ${o.required ?? '?'} sessions'),
          style: orgText(context, size: 15, w: FontWeight.w800, color: o.missing == 0 ? c.success : c.warning)),
      if (o.stopped == 'no_progress')
        Text(t('توقف التوليد لأن المحاولات لم تعد تحسّن النتيجة.', 'Stopped: further rounds made no progress.'), style: orgText(context, size: 12, color: c.textMedium)),
      if (o.unplaced.isNotEmpty) ...[
        _title(context, t('حصص بلا موعد', 'Unplaced sessions')),
        for (final u in o.unplaced)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_busy_rounded, color: c.warning),
            title: Text('${_name(u)} · ${asInt(u['missing'], 1)}× — ${unplacedReasonText('${u['reason'] ?? u['type']}')}'),
            subtitle: Text(unplacedFixText('${u['reason'] ?? u['type']}')),
          ),
      ],
      if (blocks.isNotEmpty) ...[
        _title(context, t('قواعد مرنة كُسرت (اقتراحات)', 'Flexible rules broken (proposals)')),
        for (final e in blocks.entries)
          _proposal(context, e.key, [for (final x in o.proposals) if ('${x['block_id']}' == e.key) x]),
      ],
      if (advice != null && advice!.isNotEmpty) ...[
        _title(context, t('اقتراحات لإكمال الجدول (لا تُطبّق تلقائياً)', 'Ways to complete it (never applied automatically)')),
        for (final s in advice!.take(6))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(suggestionTypeIcon(s.type), color: c.primary),
            title: Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title),
            subtitle: s.reason.isEmpty ? null : Text(s.reason),
          ),
      ],
      if (p.conflicts.isNotEmpty) ...[
        _title(context, t('التعارضات', 'Conflicts')),
        ConflictList(conflicts: p.conflicts, courseNames: widget.names),
      ],
    ]);
  }

  Widget _title(BuildContext context, String s) =>
      Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(s, style: orgText(context, w: FontWeight.w800)));

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
