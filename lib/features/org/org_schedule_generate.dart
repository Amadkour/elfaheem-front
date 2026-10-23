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
//   showGenerateSheet                  rules + start          GenerationLivePanel   while it runs
//   showGenerationResult               result: unplaced with reason + fix, proposals, advice, conflicts (read-only)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../../design/app_switch.dart';
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
  const GenerationRule(this.key, this.ar, this.en, {this.fixed = false, this.flexibleByDefault = false, this.unlockable = false});
  final String key, ar, en;
  final bool fixed; // always locked (never sent)
  final bool flexibleByDefault;
  final bool unlockable; // settings.rules key the admin may switch
}

/// In the server's order: always locked → locked but may be unlocked → flexible (first to break first).
const generationRules = [
  GenerationRule('room_double', 'القاعة أو المعمل يستضيف حصة واحدة في الوقت نفسه', 'A room or lab hosts one session at a time', fixed: true),
  GenerationRule('person_double', 'الطالب أو المدرس أو المعيد لا يكون في مكانين في الوقت نفسه', 'A student, instructor or TA is never in two places at once', fixed: true),
  GenerationRule('lab_only', 'الحصص العملية في معامل مجهّزة فقط، لا في قاعات المحاضرات', 'Practical sessions only in equipped labs, never lecture halls', fixed: true),
  GenerationRule('capacity', 'سعة القاعة لا تقل عن حجم المجموعة', 'Room capacity is at least the group size', fixed: true),
  GenerationRule('instructor_availability', 'احترام أيام وفترات إتاحة كل مدرس', 'Respect each instructor\'s available days and periods', unlockable: true),
  GenerationRule('assistant_availability', 'احترام أيام وفترات إتاحة كل معيد', 'Respect each TA\'s available days and periods', unlockable: true),
  GenerationRule('rooms_and_times', 'استخدام القاعات والأوقات المتاحة فقط', 'Use only the available rooms and time slots', unlockable: true),
  GenerationRule('compact', 'جداول متقاربة وفجوات أقل', 'Compact schedules, fewer gaps'),
  GenerationRule('preferred', 'الأوقات المفضلة', 'Preferred time slots'),
  GenerationRule('soft_availability', 'العمل في يوم أو فترة غير مفضلة للمدرس أو المعيد', 'Instructor / TA on a non-preferred day or period'),
  GenerationRule('extra_times', 'فتح أوقات إضافية خارج الفترات المحددة (اقتراح)', 'Open extra time slots beyond the periods (suggestion)'),
  GenerationRule('larger_hall', 'قاعة أكبر أو من نوع آخر لمحاضرة نظرية', 'A larger / other hall for a theory session', flexibleByDefault: true, unlockable: true),
  GenerationRule('external', 'ملاذ أخير: عضو أو قاعة أو معمل من الخارج (اقتراح فقط)', 'Last resort: external staff, hall or lab (suggestion only)'),
];

/// settings.rules as the admin set them, defaults filled in: key → flexible?
Map<String, bool> rulesFlexible(Map<String, dynamic> settings) {
  final stored = asMap(settings['rules']);
  return {
    for (final r in generationRules)
      if (r.unlockable) r.key: stored[r.key] == null ? r.flexibleByDefault : stored[r.key] == 'flexible',
  };
}

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

/// The rules (Locked / Flexible) and the one button.
Future<void> showGenerateSheet(BuildContext context, OrgScheduleProvider p) async {
  final flex = rulesFlexible(asMap(p.schedule?['settings']));
  final labGroup = TextEditingController(text: '${asInt(asMap(p.schedule?['settings'])['lab_group_default'], 25)}');
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget fixedRow(GenerationRule r, String state, Color col) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(state == 'fixed' ? Icons.lock_rounded : Icons.tune_rounded, size: 18, color: col),
                const SizedBox(width: 10),
                Expanded(child: Text(t(r.ar, r.en), style: orgText(ctx, size: 13))),
                Text(state == 'fixed' ? t('مقفلة', 'Locked') : t('مرنة', 'Flexible'), style: orgText(ctx, size: 11.5, w: FontWeight.w700, color: col)),
              ]),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('توليد الجدول', 'Generate timetable')),
            Text(
                t('يضع الخادم كل الحصص ثم يحاول حتى يكتمل الجدول أو يتوقف التقدم، ويحفظه مسودة. أي قاعدة مرنة تُكسر تظهر لك اقتراحاً تقبله أو ترفضه.',
                    'The server places every session and keeps trying until the timetable is complete or stops improving, then saves a Draft. Any flexible rule it breaks comes back as a proposal you accept or reject.'),
                style: orgText(ctx, size: 12, color: c.textMedium)),
            const SizedBox(height: 8),
            for (final r in generationRules)
              if (r.fixed)
                fixedRow(r, 'fixed', c.textMedium)
              else if (r.unlockable)
                AppSwitchTile(
                  dense: true,
                  title: t(r.ar, r.en),
                  subtitle: flex[r.key]! ? t('مرنة — تُكسر عند الحاجة فقط', 'Flexible — broken only if needed') : t('مقفلة — لا تُكسر', 'Locked — never broken'),
                  value: flex[r.key]!,
                  onChanged: (v) => set(() => flex[r.key] = v),
                )
              else
                fixedRow(r, 'soft', c.primary),
            Field(controller: labGroup, label: t('حجم مجموعة المعمل الافتراضي', 'Default lab group size'), keyboard: TextInputType.number, ltr: true),
            const SizedBox(height: 12),
            PrimaryButton(
              isLoading: busy,
              label: t('توليد الجدول', 'Generate timetable'),
              icon: Icons.auto_awesome_rounded,
              iconBefore: true,
              onPressed: () async {
                set(() => busy = true);
                final r = await p.startGeneration(complete: true, settings: {
                  'rules': {for (final e in flex.entries) e.key: e.value ? 'flexible' : 'locked'},
                  'lab_group_default': (int.tryParse(labGroup.text.trim()) ?? 25).clamp(1, 500),
                });
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r.ok || r.code == 'generation_running') {
                  Navigator.pop(ctx);
                } else {
                  toast(orgErrorText(r.error!), error: true);
                }
              },
            ),
          ]),
        );
      }));
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
