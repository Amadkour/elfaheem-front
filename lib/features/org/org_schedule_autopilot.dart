// lib/features/org/org_schedule_autopilot.dart — "Power AI schedule": the timetable in one tap, and what the autopilot did.
//
//   TermNeed / termsNeedingTimetable   pure: the current / next term without a timetable (from the dashboard's attention
//                                      item `term_without_timetable`, or computed from the terms + timetables lists)
//   AutopilotReport / AutopilotEntry   pure: result.autopilot — before / after metrics, rounds, why it stopped, the log,
//                                      the revision to undo to
//   DataFixPlan / DataFix / DataFixPicker   GET …/autopilot/plan — the data fixes an attended run would apply; the
//                                      person ticks them (people / room changes are off by default)
//   runAutopilotWithPlan               the one call every "Fix automatically" button makes: plan → confirm → start
//   TermTimetableCard                  "Term 1 2026/2027 has no timetable — Generate now" (or exactly what blocks it)
//   AutopilotSummaryCard               what the autopilot fixed, what it left for a person
//   timetableRequest                   a deep link into the Timetable section ('generate' · 'open:' + schedule id)
//
// The server side is services/organization/schedule_autopilot.py: POST …/schedules/auto {term_id} (create + autopilot)
// and POST …/schedules/{sid}/autopilot (data fixes → complete generation → every automatic remedy → re-solve).
// Pure parts are tested in test/org/org_autopilot_test.dart; the widgets in test/ui/autopilot_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppPrimaryButton;

import '../admin/admin_common.dart';
import 'org_providers.dart';
import 'org_schedule_reassign.dart' show ReassignMetrics;
import 'org_v3.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

/// What the Timetable section should open next time it builds: 'generate' (the term cards) or 'open:<schedule id>'.
final ValueNotifier<String?> timetableRequest = ValueNotifier<String?>(null);

String termKindLabel(String kind) => switch (kind) {
      'term1' => t('الفصل الأول', 'Term 1'),
      'term2' => t('الفصل الثاني', 'Term 2'),
      'summer' => t('الفصل الصيفي', 'Summer'),
      _ => kind,
    };

class TermNeed {
  const TermNeed({required this.id, required this.yearLabel, required this.kind, required this.status, this.start, this.end, this.blocked = const []});
  final int id;
  final String yearLabel, kind, status; // status: current | upcoming
  final DateTime? start, end;
  final List<Map<String, dynamic>> blocked; // schedule_auto.preconditions: {code, text_ar, text_en}

  bool get ready => blocked.isEmpty;
  bool get current => status == 'current';

  /// The same term with what the app itself knows blocks the generation (no periods / rooms yet).
  TermNeed withBlocked(List<Map<String, dynamic>> b) => TermNeed(id: id, yearLabel: yearLabel, kind: kind, status: status, start: start, end: end, blocked: b.isEmpty ? blocked : b);
  String get label => '${termKindLabel(kind)} $yearLabel';
  List<String> get blockedTexts => [for (final b in blocked) t('${b['text_ar'] ?? b['code']}', '${b['text_en'] ?? b['code']}')];

  /// An item of the dashboard attention `terms[]` (server: schedule_autopilot.term_brief).
  factory TermNeed.of(Map<String, dynamic> m) => TermNeed(
        id: asInt(m['id']),
        yearLabel: '${m['year_label'] ?? ''}',
        kind: '${m['kind'] ?? ''}',
        status: '${m['status'] ?? 'current'}',
        start: DateTime.tryParse('${m['start_date'] ?? ''}'),
        end: DateTime.tryParse('${m['end_date'] ?? ''}'),
        blocked: asMapList(m['blocked']),
      );
}

DateTime? _day(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// The current term and the next one that have no timetable yet — the same rule as the server's
/// `terms_needing_timetable` (a timetable of the term, or one without a term whose dates overlap it, covers it).
/// [terms] = GET …/academic/terms items · [schedules] = GET …/schedules items. Blocked reasons are not known here.
List<TermNeed> termsNeedingTimetable(List<Map<String, dynamic>> terms, List<Map<String, dynamic>> schedules, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final open = [
    for (final x in terms)
      if (_day(x['end_date']) != null && !_day(x['end_date'])!.isBefore(day)) x,
  ]..sort((a, b) => _day(a['start_date'])!.compareTo(_day(b['start_date'])!));
  final cur = open.where((x) => !_day(x['start_date'])!.isAfter(day)).firstOrNull;
  final nxt = open.where((x) => _day(x['start_date'])!.isAfter(day)).firstOrNull;
  bool covered(Map<String, dynamic> term) {
    final ts = _day(term['start_date']), te = _day(term['end_date']);
    for (final s in schedules) {
      if (s['status'] == 'archived') continue;
      if (s['term_id'] != null && asInt(s['term_id']) == asInt(term['id'])) return true;
      if (s['term_id'] == null) {
        final ss = _day(s['start_date']), se = _day(s['end_date']);
        if (ss == null || se == null || ts == null || te == null) continue;
        if (!ss.isAfter(te) && !se.isBefore(ts)) return true;
      }
    }
    return false;
  }

  return [
    for (final (x, status) in [(cur, 'current'), (nxt, 'upcoming')])
      if (x != null && !covered(x))
        TermNeed(id: asInt(x['id']), yearLabel: '${x['year_label'] ?? ''}', kind: '${x['kind'] ?? ''}', status: status, start: _day(x['start_date']), end: _day(x['end_date'])),
  ];
}

class AutopilotEntry {
  const AutopilotEntry({required this.round, required this.kind, required this.textAr, required this.textEn, required this.ok});
  final int round;
  final String kind, textAr, textEn;
  final bool ok;
  String get text => t(textAr, textEn);

  factory AutopilotEntry.of(Map<String, dynamic> m) =>
      AutopilotEntry(round: asInt(m['round']), kind: '${m['kind'] ?? ''}', textAr: '${m['text_ar'] ?? m['text_en'] ?? ''}', textEn: '${m['text_en'] ?? m['text_ar'] ?? ''}', ok: m['ok'] != false);
}

/// result.autopilot (schedule_autopilot.after_generation).
class AutopilotReport {
  const AutopilotReport({required this.before, required this.after, this.rounds = 0, this.stopped = '', this.log = const [], this.attended = true, this.fixed = 0, this.beforeRevisionId, this.beforeSlots = 0});
  final ReassignMetrics before, after;
  final int rounds, fixed;
  final String stopped; // complete · no_progress · time_limit · rounds · cancelled · no_actor
  final List<AutopilotEntry> log;
  final bool attended;

  /// the revision taken before the run ("Undo everything" restores it) and how many sessions it held
  final int? beforeRevisionId;
  final int beforeSlots;
  bool get canUndo => beforeRevisionId != null;

  bool get complete => stopped == 'complete';
  List<AutopilotEntry> get applied => [for (final x in log) if (x.ok && x.kind != 'manual' && x.kind != 'skipped') x];
  List<AutopilotEntry> get left => [for (final x in log) if (!x.ok) x];
  int get hardFixed => (before.hard - after.hard).clamp(0, 1 << 30);
  int get placedMore => (before.unplaced - after.unplaced).clamp(0, 1 << 30);

  static AutopilotReport? of(Map<String, dynamic> result) {
    final m = asMap(result['autopilot']);
    if (m.isEmpty) return null;
    return AutopilotReport(
      before: ReassignMetrics.of(asMap(m['before'])),
      after: ReassignMetrics.of(asMap(m['after'])),
      rounds: asInt(m['rounds']),
      stopped: '${m['stopped'] ?? ''}',
      log: [for (final x in asMapList(m['log'])) AutopilotEntry.of(x)],
      attended: m['attended'] != false,
      fixed: asInt(m['fixed']),
      beforeRevisionId: m['before_revision_id'] == null ? null : asInt(m['before_revision_id']),
      beforeSlots: asInt(m['before_slots']),
    );
  }
}

/// One data fix of GET …/autopilot/plan: a pre-flight blocker with its automatic way out.
class DataFix {
  const DataFix({required this.key, required this.code, required this.kind, required this.people, required this.textAr, required this.textEn, this.findingAr = '', this.findingEn = '', this.whyAr = '', this.whyEn = ''});
  final String key, code, kind, textAr, textEn, findingAr, findingEn, whyAr, whyEn;

  /// changes people, rooms or who teaches — only applied when ticked
  final bool people;

  String get text => t(textAr, textEn);
  String get finding => t(findingAr, findingEn);
  String get why => t(whyAr, whyEn);

  factory DataFix.of(Map<String, dynamic> m) => DataFix(
        key: '${m['key'] ?? ''}',
        code: '${m['code'] ?? ''}',
        kind: '${m['kind'] ?? ''}',
        people: m['people'] == true,
        textAr: '${m['text_ar'] ?? m['text_en'] ?? ''}',
        textEn: '${m['text_en'] ?? m['text_ar'] ?? ''}',
        findingAr: '${m['finding_ar'] ?? m['finding_en'] ?? ''}',
        findingEn: '${m['finding_en'] ?? m['finding_ar'] ?? ''}',
        whyAr: '${m['why_ar'] ?? m['why_en'] ?? ''}',
        whyEn: '${m['why_en'] ?? m['why_ar'] ?? ''}',
      );
}

class DataFixPlan {
  const DataFixPlan({this.fixes = const [], this.defaults = const {}});
  final List<DataFix> fixes;
  final Set<String> defaults; // the keys an unconfirmed run applies (never people / room changes)

  bool get isEmpty => fixes.isEmpty;
  List<DataFix> get people => [for (final f in fixes) if (f.people) f];

  factory DataFixPlan.of(Map<String, dynamic> m) => DataFixPlan(
        fixes: [for (final x in asMapList(m['data_fixes'])) DataFix.of(x)],
        defaults: {for (final k in (m['default'] as List? ?? const [])) '$k'},
      );
}

/// The fixes with a tick each; people / room changes carry a warning and start unticked.
class DataFixPicker extends StatelessWidget {
  const DataFixPicker({super.key, required this.plan, required this.selected, this.onToggle});
  final DataFixPlan plan;
  final Set<String> selected;
  final void Function(String key, bool on)? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          t('قبل التوليد يقترح فحص البيانات هذه الإصلاحات. ما تختاره يُحفظ فوراً ويبقى بعد أي تراجع؛ تغييرات الأشخاص والقاعات غير مختارة افتراضياً.',
              'Before generating, the data check suggests these fixes. What you tick is saved at once and stays after any undo; changes to people and rooms start unticked.'),
          style: AppType.label(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.xs),
      for (final f in plan.fixes)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: selected.contains(f.key),
          onChanged: onToggle == null ? null : (v) => onToggle!(f.key, v == true),
          title: Text(f.text, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
          subtitle: Text(
            [if (f.finding.isNotEmpty) f.finding, if (f.why.isNotEmpty) f.why, if (f.people) t('يغيّر أشخاصاً أو قاعات', 'changes people or rooms')].join(' · '),
            style: AppType.meta(context).copyWith(color: f.people ? c.warning : c.textMedium),
          ),
          secondary: f.people ? Icon(Icons.warning_amber_rounded, color: c.warning, size: AppIconSize.md) : null,
        ),
    ]);
  }
}

/// The confirmation before an attended run: the ticked keys, or null when the person backs out.
Future<List<String>?> askDataFixes(BuildContext context, DataFixPlan plan) {
  final selected = <String>{...plan.defaults};
  return showAdminSheet<List<String>>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('إصلاحات البيانات قبل التوليد', 'Data fixes before generating')),
            DataFixPicker(plan: plan, selected: selected, onToggle: (k, on) => set(() => on ? selected.add(k) : selected.remove(k))),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              FilledButton.icon(onPressed: () => Navigator.pop(ctx, selected.toList()), icon: const Icon(Icons.auto_fix_high_rounded, size: AppIconSize.md), label: Text(t('ابدأ (${selected.length} إصلاح)', 'Start (${selected.length} fix(es))'))),
              OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, const <String>[]), icon: const Icon(Icons.skip_next_rounded, size: AppIconSize.md), label: Text(t('بلا إصلاحات بيانات', 'Without data fixes'))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
            ]),
          ]),
        );
      }));
}

/// Every "Fix automatically" button: the data-fix plan (GET …/autopilot/plan), the confirmation when there is
/// anything to confirm, then POST …/autopilot. An older server without the plan route starts with the server's
/// default (the timetable's own plans / settings only). Null = the person backed out.
Future<OrgCall?> runAutopilotWithPlan(BuildContext context, OrgScheduleProvider p) async {
  final plan = await p.autopilotPlan();
  List<String>? keys;
  if (plan.ok) {
    final dp = DataFixPlan.of(plan.map);
    if (dp.isEmpty) {
      keys = const [];
    } else {
      if (!context.mounted) return null;
      keys = await askDataFixes(context, dp);
      if (keys == null) return null;
    }
  }
  final r = await p.startAutopilot(dataFixKeys: keys);
  if (!r.ok && r.code != 'generation_running' && context.mounted) toast(orgErrorText(r.error!), error: true);
  return r;
}

String autopilotStopText(String stopped) => switch (stopped) {
      'complete' => t('اكتمل: كل الحصص في أماكنها وبلا تعارضات إلزامية', 'Complete: every session placed, no hard conflicts'),
      'no_progress' => t('توقّف: ما بقي لا يُحل تلقائياً — يحتاج قرارك', 'Stopped: what is left cannot be fixed automatically — it needs your decision'),
      'time_limit' => t('انتهى الوقت المخصص — ما بقي يحتاج قرارك', 'Time budget used up — what is left needs your decision'),
      'rounds' => t('انتهت جولات الإصلاح — ما بقي يحتاج قرارك', 'Fix rounds used up — what is left needs your decision'),
      'cancelled' => t('أُلغي', 'Cancelled'),
      'no_actor' => t('لم يُشغَّل الإصلاح التلقائي (لا مسؤول للمؤسسة)', 'Automatic fixing did not run (no organization admin)'),
      _ => stopped,
    };

/// "Term 1 2026/2027 has no timetable yet" with Generate now (or the exact blockers and a Set up button).
class TermTimetableCard extends StatelessWidget {
  const TermTimetableCard({super.key, required this.need, this.onGenerate, this.onSetup, this.busy = false, this.compact = false});
  final TermNeed need;
  final VoidCallback? onGenerate, onSetup;
  final bool busy, compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = need.ready ? c.primary : c.warning;
    final when = need.current ? t('الفصل الحالي', 'current term') : t('الفصل القادم', 'next term');
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(need.ready ? Icons.auto_awesome_rounded : Icons.flag_rounded, color: col),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('${need.label} بلا جدول بعد', '${need.label} has no timetable yet'), style: AppType.section(context)),
              Text(
                need.ready
                    ? t('$when · بضغطة واحدة: يُنشأ الجدول من مقررات الفصل، يُولَّد، وتُصلَح تعارضاته تلقائياً، ثم تراجعه وتنشره.',
                        '$when · One tap: the timetable is created from the term\'s courses, generated, its conflicts fixed automatically, then you review and publish.')
                    : t('$when · ينقص قبل التوليد: ${need.blockedTexts.join(' · ')}', '$when · Needed before generating: ${need.blockedTexts.join(' · ')}'),
                style: AppType.label(context).copyWith(color: c.textMedium),
              ),
            ]),
          ),
        ]),
        if (onGenerate != null || onSetup != null) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: need.ready
                  ? AppPrimaryButton(label: t('ولّد الجدول الآن', 'Generate now'), icon: Icons.auto_awesome_rounded, busy: busy, onPressed: busy ? null : onGenerate)
                  : OutlinedButton.icon(onPressed: onSetup, icon: const Icon(Icons.tune_rounded, size: AppIconSize.md), label: Text(t('أكمل الإعداد', 'Complete the setup'))),
            ),
          ),
        ],
      ]),
    );
  }
}

/// What the autopilot did on the last run: numbers before / after, every applied fix, what it left to a person.
class AutopilotSummaryCard extends StatelessWidget {
  const AutopilotSummaryCard({super.key, required this.report, this.limit = 6, this.onUndo});
  final AutopilotReport report;
  final int limit;

  /// "Undo everything": restore the revision taken before the run (data fixes stay — they are audited)
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final col = r.complete ? c.success : (r.after.hard > 0 ? c.danger : c.warning);
    Widget delta(String label, int before, int after) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
          decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.textLight.withValues(alpha: 0.25))),
          child: Text('$label $before ← $after', textDirection: TextDirection.rtl, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: after < before ? c.success : (after > before ? c.danger : c.textMedium))),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: col.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_fix_high_rounded, color: col),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('الإصلاح التلقائي', 'Automatic fixing'), style: AppType.bodyStrong(context).copyWith(color: col))),
          Text(t('${r.rounds} جولة', '${r.rounds} round(s)'), style: AppType.meta(context).copyWith(color: c.textMedium)),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(autopilotStopText(r.stopped), style: AppType.label(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          delta(t('تعارض إلزامي', 'hard'), r.before.hard, r.after.hard),
          delta(t('بلا مكان', 'unplaced'), r.before.unplaced, r.after.unplaced),
          delta(t('تنبيه', 'warnings'), r.before.warnings, r.after.warnings),
          delta(t('الدرجة', 'score'), r.before.score, r.after.score),
        ]),
        if (r.applied.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('ما طُبّق (${r.applied.length})', 'Applied (${r.applied.length})'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
          for (final x in r.applied.take(limit))
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle_rounded, size: AppIconSize.xs, color: c.success),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(x.text, style: AppType.meta(context).copyWith(color: c.textMedium))),
              ]),
            ),
          if (r.applied.length > limit) Text(t('+${r.applied.length - limit} أخرى', '+${r.applied.length - limit} more'), style: AppType.meta(context).copyWith(color: c.textLight)),
        ],
        if (r.left.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('يحتاج قرارك (${r.left.length})', 'Needs your decision (${r.left.length})'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
          for (final x in r.left.take(limit))
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.person_rounded, size: AppIconSize.xs, color: c.warning),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(x.text, style: AppType.meta(context).copyWith(color: c.textMedium))),
              ]),
            ),
          if (r.left.length > limit) Text(t('+${r.left.length - limit} أخرى', '+${r.left.length - limit} more'), style: AppType.meta(context).copyWith(color: c.textLight)),
        ],
        if (onUndo != null && r.canUndo) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: onUndo,
              icon: const Icon(Icons.undo_rounded, size: AppIconSize.md),
              label: Text(r.beforeSlots == 0 ? t('تراجع (جدول فارغ)', 'Undo (back to an empty timetable)') : t('تراجع عن كل شيء', 'Undo everything')),
            ),
          ),
        ],
      ]),
    );
  }
}
