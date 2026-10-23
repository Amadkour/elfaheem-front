// lib/features/org/org_schedule_relaxation.dart — "which rule should give way?": up to 3 complete timetables, one per
// rule that could be broken, compared side by side.
//
//   POST …/schedules/{sid}/generate {trial, break_alternatives, settings.relaxation_mode}   (background run)
//        → run.summary.alternatives [{revision_id, rule, rank}] — `alternative` revisions only, the live timetable is
//          untouched (the same trial-generation infrastructure as org_schedule_alternatives.dart)
//   GET  …/revisions/{id}                       slots + summary.result (broken, stats) + summary.break_alternative
//   POST …/revisions/{id}/restore               one-tap apply (a version is saved first, so it can be rolled back)
//
// Pure (unit-tested): BreakAlternative · rankBreakAlternatives (fewest unplaced → broken rules per tier, most
// protected first → sessions affected → people affected; at most 3) · versionHealthScore · breakRuleLabel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart';
import 'org_schedule_copies.dart' show timetableNamesOf;
import 'org_schedule_export.dart' show TimetableGrid;
import 'org_schedule_versions.dart';
import 'org_ui.dart';
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pure
// ═════════════════════════════════════════════════════════════════════════════

const maxBreakAlternatives = 3;

/// The rule a version gives way on, in plain words (null = several rules at once).
String breakRuleLabel(String? rule) => switch (rule) {
      'teacher_unavailable' => t('وقت غير متاح لأحد أعضاء هيئة التدريس', 'A staff member\'s unavailable time'),
      'students_unavailable' => t('وقت غير متاح لطلاب المقرر', 'A time the students can\'t attend'),
      'students_clash' => t('تداخل مقررين لهما طلاب مشتركون', 'Two courses sharing students overlap'),
      'students_busy_elsewhere' => t('الطلاب مشغولون في جدول منشور آخر', 'Students busy in another published timetable'),
      'teacher_day_limit' => t('تجاوز الحد اليومي لحصص المدرس', 'A teacher goes over the daily limit'),
      'room_kind' => t('مكان من نوع آخر (مثل قاعة بدل معمل)', 'A different kind of room (e.g. a hall for a lab)'),
      'room_capabilities' => t('مكان ينقصه بعض التجهيزات', 'A room missing some equipment'),
      'room_unavailable' => t('مكان في وقت غير متاح له', 'A room at a time it is closed'),
      'room_capacity' => t('مكان أصغر قليلاً من عدد الطلاب', 'A room slightly smaller than the class'),
      null => t('عدة قواعد معاً', 'Several rules together'),
      _ => rule,
    };

/// What giving way on that rule means for people, in one sentence.
String breakRuleExplain(String? rule) => switch (rule) {
      'teacher_unavailable' => t('يُطلب من المدرس أو المعيد الحضور في وقت قال إنه لا يناسبه.', 'A teacher or assistant is asked to come at a time they said doesn\'t suit them.'),
      'students_unavailable' => t('تُوضع الحصة في وقت لا يناسب مجموعة الطلاب.', 'The session goes at a time that doesn\'t suit the student group.'),
      'students_clash' => t('بعض الطلاب لديهم حصتان في الوقت نفسه ويختارون إحداهما.', 'Some students have two sessions at once and must pick one.'),
      'students_busy_elsewhere' => t('يتعارض مع جدول منشور يحضره الطلاب أنفسهم.', 'Clashes with a published timetable the same students attend.'),
      'teacher_day_limit' => t('يدرّس المدرس فترات أكثر من الحد المحدد في يوم واحد.', 'A teacher teaches more periods than the set daily limit.'),
      'room_kind' || 'room_capabilities' || 'room_unavailable' || 'room_capacity' =>
        t('لا أحد يُحجز مرتين؛ التنازل في المكان فقط.', 'Nobody is double-booked; only the room gives way.'),
      _ => t('أقل ما يمكن كسره ليكتمل الجدول.', 'The least that has to give for a complete timetable.'),
    };

/// 0–100: the share of sessions placed, minus 2 points per broken rule (4 in the two most protected tiers).
int versionHealthScore({required int required, required int placed, required List<String> brokenTiers, RelaxationPolicy policy = RelaxationPolicy.standard}) {
  if (required <= 0) return 100;
  final top = policy.protectedFirst.take(2).toSet();
  final penalty = brokenTiers.fold<int>(0, (a, tier) => a + (top.contains(tier) ? 4 : 2));
  return (100 * placed / required - penalty).round().clamp(0, 100);
}

class BreakAlternative {
  BreakAlternative({
    required this.revisionId,
    required this.rule,
    required this.rank,
    required this.slots,
    required this.result,
    this.recommended = false,
  });

  final int revisionId;
  final String? rule;
  int rank;
  bool recommended;
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic> result; // the generation report of that version (broken, stats …)

  List<Map<String, dynamic>> get broken => asMapList(result['broken']);
  int get required => asInt(asMap(result['stats'])['sessions_required']);
  int get placed => asInt(asMap(result['stats'])['sessions_placed']);
  int get unplaced => (required - placed).clamp(0, 1 << 30);
  int get sessionsAffected => {for (final b in broken) '${b['course_id']}|${b['kind']}|${b['group_no']}|${b['block_id']}'}.length;
  int get peopleAffected => {for (final b in broken) if (b['user_id'] != null) asInt(b['user_id'])}.length;
  Map<String, int> get byTier => {for (final e in asMap(result['broken_by_tier']).entries) e.key: asInt(e.value)};

  /// Broken rules per tier, most protected tier first (compared lexicographically).
  List<int> tierVector(RelaxationPolicy policy) => [for (final tier in policy.protectedFirst) broken.where((b) => b['tier'] == tier).length];

  int health(RelaxationPolicy policy) =>
      versionHealthScore(required: required, placed: placed, brokenTiers: [for (final b in broken) '${b['tier']}'], policy: policy);

  factory BreakAlternative.fromRevision(Map<String, dynamic> rev, {String? rule, int rank = 0}) {
    final sm = asMap(rev['summary']);
    final meta = asMap(sm['break_alternative']);
    return BreakAlternative(
      revisionId: asInt(rev['id']),
      rule: (meta['rule'] ?? rule) as String?,
      rank: asInt(meta['rank'], rank),
      recommended: meta['recommended'] == true,
      slots: asMapList(rev['items']),
      result: asMap(sm['result']),
    );
  }
}

int _lex(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
}

/// Least disruptive first: fewest unplaced, then the tier vector (most protected tier first), then sessions, then
/// people affected. At most [cap]; ranks are rewritten 1..n and only rank 1 is "recommended".
List<BreakAlternative> rankBreakAlternatives(List<BreakAlternative> all, {RelaxationPolicy policy = RelaxationPolicy.standard, int cap = maxBreakAlternatives}) {
  final out = [...all]..sort((a, b) {
      var r = a.unplaced.compareTo(b.unplaced);
      if (r != 0) return r;
      r = _lex(a.tierVector(policy), b.tierVector(policy));
      if (r != 0) return r;
      r = a.sessionsAffected.compareTo(b.sessionsAffected);
      if (r != 0) return r;
      r = a.peopleAffected.compareTo(b.peopleAffected);
      return r != 0 ? r : a.rank.compareTo(b.rank);
    });
  final top = out.take(cap).toList();
  for (var i = 0; i < top.length; i++) {
    top[i].rank = i + 1;
    top[i].recommended = i == 0;
  }
  return top;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Server
// ═════════════════════════════════════════════════════════════════════════════

/// Starts the trial run, follows it and loads the stored versions. Throws [ApiException].
Future<List<BreakAlternative>> computeBreakAlternatives(OrgScheduleProvider p, {int seed = 7, bool Function()? cancelled}) async {
  final sid = asInt(p.schedule!['id']);
  final s = '${p.base}/schedules/$sid';
  final r = asMap(await p.api.post('$s/generate', queryParams: {'background': true}, body: {
    'trial': true,
    'break_alternatives': true,
    'persist_settings': false,
    'seed': seed,
    'settings': {'relaxation_mode': 'all_but_double_booking'},
    'label': t('بديل بكسر قاعدة', 'Rule-relaxed alternative'),
  }));
  var run = asMap(r['run']).isEmpty ? r : asMap(r['run']);
  for (var i = 0; i < 300 && runIsOpen(run); i++) {
    if (cancelled?.call() ?? false) return const [];
    await Future<void>.delayed(const Duration(seconds: 2));
    run = asMap(await p.api.get('$s/runs/${run['id']}'));
  }
  if (run['status'] != 'succeeded') {
    throw ApiException(statusCode: 409, message: '${run['error'] ?? t('تعذّر حساب البدائل', 'The alternatives could not be computed')}');
  }
  final items = asMapList(asMap(run['summary'])['alternatives']);
  final out = <BreakAlternative>[];
  for (final a in items) {
    final rev = asMap(await p.api.get('$s/revisions/${a['revision_id']}'));
    out.add(BreakAlternative.fromRevision(rev, rule: a['rule'] as String?, rank: asInt(a['rank'])));
  }
  return rankBreakAlternatives(out, policy: RelaxationPolicy.fromSettings(asMap(p.schedule?['settings'])));
}

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

/// Returns true when one alternative was applied.
Future<bool> openBreakAlternatives(BuildContext context, OrgScheduleProvider p) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => BasePage(
              useWebCard: true,
              maxWith: 1200,
              appBar: ScreenAppBar(title: t('أي قاعدة تتنازل عنها؟', 'Which rule should give way?')),
              child: _BreakAlternativesPage(p: p),
            ))) ??
    false;

class _BreakAlternativesPage extends StatefulWidget {
  const _BreakAlternativesPage({required this.p});
  final OrgScheduleProvider p;

  @override
  State<_BreakAlternativesPage> createState() => _BreakAlternativesPageState();
}

class _BreakAlternativesPageState extends State<_BreakAlternativesPage> {
  List<BreakAlternative>? items;
  String? error;
  bool applying = false;
  bool _gone = false;

  OrgScheduleProvider get p => widget.p;
  RelaxationPolicy get policy => RelaxationPolicy.fromSettings(asMap(p.schedule?['settings']));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      items = null;
      error = null;
    });
    try {
      final r = await computeBreakAlternatives(p, cancelled: () => _gone);
      if (mounted) setState(() => items = r);
    } catch (e) {
      final x = ApiException.from(e);
      if (mounted) {
        setState(() => error = orgEndpointMissing(x)
            ? t('هذه الميزة تحتاج تحديث الخادم.', 'This feature needs a server update.')
            : orgErrorText(x));
      }
    }
  }

  Future<void> _apply(BreakAlternative a) async {
    final ok = await appConfirm(context,
        message: t('تطبيق هذا البديل على الجدول؟ تُحفظ نسخة من الجدول الحالي أولاً ويمكنك الرجوع إليها من "النسخ".',
            'Apply this alternative to the timetable? The current timetable is saved as a version first, so you can go back to it from "Versions".'),
        confirmLabel: t('تطبيق', 'Apply'));
    if (!ok || !mounted) return;
    setState(() => applying = true);
    final done = await p.restoreRevision(a.revisionId);
    if (!mounted) return;
    setState(() => applying = false);
    if (done) {
      appToast(t('طُبّق البديل على الجدول', 'The alternative is now the timetable'));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = items;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      AppHero(
        icon: Icons.balance_rounded,
        title: t('بدائل جاهزة، كل منها يتنازل عن قاعدة واحدة', 'Ready alternatives, each giving way on one rule'),
        subtitle: t('لم يكتمل الجدول دون كسر قاعدة. هذه أفضل النسخ الكاملة — مرتبة من الأقل إزعاجاً. لا أحد يُحجز مرتين في أي منها.',
            'The timetable can\'t be complete without bending a rule. These are the best complete versions — least disruptive first. Nobody is double-booked in any of them.'),
        stats: [
          if (list != null) AppHeroStat(icon: Icons.layers_rounded, value: '${list.length}', label: t('بدائل', 'alternatives')),
          AppHeroStat(icon: Icons.lock_rounded, value: '0', label: t('حجز مزدوج', 'double bookings')),
        ],
      ),
      const SizedBox(height: 14),
      if (error != null)
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger, action: TextButton(onPressed: _load, child: Text(t('أعد المحاولة', 'Try again'))))
      else if (list == null) ...[
        AppBanner(icon: Icons.hourglass_top_rounded, text: t('نجرّب كل قاعدة على حدة… قد يستغرق ذلك دقيقة.', 'Trying each rule on its own… this can take a minute.')),
        const SizedBox(height: 10),
        const SizedBox(height: 420, child: AppListSkeleton(items: 3, withAvatar: false)),
      ] else if (list.isEmpty)
        AppEmpty(
          icon: Icons.verified_rounded,
          title: t('لا حاجة لكسر أي قاعدة', 'No rule needs to give way'),
          message: t('ولّد الجدول من جديد — يمكن وضع كل الحصص دون تنازل.', 'Generate again — every session fits without bending a rule.'),
        )
      else ...[
        if (list.length == 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppBanner(
                icon: Icons.info_outline_rounded,
                text: t('بديل واحد فقط يضع كل الحصص؛ التنازل عن أي قاعدة أخرى وحدها يترك حصصاً بلا موعد.',
                    'Only one alternative places every session; giving way on any other rule alone leaves sessions without a time.')),
          ),
        LayoutBuilder(builder: (context, box) {
          final cards = [for (final a in list) _AltCard(a: a, p: p, policy: policy, busy: applying, onApply: () => _apply(a))];
          if (box.maxWidth >= 900 && cards.length > 1) {
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ]),
            );
          }
          return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]);
        }),
        const SizedBox(height: 6),
        Text(
            t('الترتيب: الأقل كسراً لأكثر الفئات حماية (حسب أولويات التخفيف)، ثم الأقل حصصاً، ثم الأقل أشخاصاً متأثرين.',
                'Order: fewest breaks in the most protected tiers (your relaxation priority), then fewest sessions, then fewest people affected.'),
            style: orgText(context, size: 12, color: c.textMedium)),
      ],
    ]);
  }
}

class _AltCard extends StatelessWidget {
  const _AltCard({required this.a, required this.p, required this.policy, required this.busy, required this.onApply});
  final BreakAlternative a;
  final OrgScheduleProvider p;
  final RelaxationPolicy policy;
  final bool busy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diff = diffVersions(p.slots, a.slots);
    final health = a.health(policy);
    final accent = a.recommended ? c.success : c.primary;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppBadgePill(t('الخيار ${a.rank}', 'Option ${a.rank}'), color: accent),
          if (a.recommended) AppBadgePill(t('موصى به', 'Recommended'), color: c.success, icon: Icons.star_rounded),
        ]),
        const SizedBox(height: 10),
        Text(breakRuleLabel(a.rule), maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 15.5, w: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(breakRuleExplain(a.rule), style: orgText(context, size: 12.5, color: c.textMedium)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Fig(icon: Icons.event_note_rounded, value: '${a.sessionsAffected}', label: t('حصص متأثرة', 'sessions affected'))),
          Expanded(child: _Fig(icon: Icons.people_alt_rounded, value: '${a.peopleAffected}', label: t('أشخاص متأثرون', 'people affected'))),
          Expanded(child: _Fig(icon: Icons.favorite_rounded, value: '$health', label: t('صحة الجدول', 'health'), color: appScoreColor(context, health.toDouble()))),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: a.required == 0 ? 1 : a.placed / a.required, minHeight: 8, color: a.unplaced == 0 ? c.success : c.warning),
        ),
        const SizedBox(height: 4),
        Text(t('${a.placed} من ${a.required} حصة مجدولة', '${a.placed} of ${a.required} sessions placed'), style: orgText(context, size: 12, color: c.textMedium)),
        if (a.byTier.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in a.byTier.entries) AppBadgePill('${relaxTierLabel(e.key)} × ${e.value}', color: c.warning),
          ]),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.compare_arrows_rounded, size: 18, color: c.textMedium),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                diff.isEmpty
                    ? t('مطابق للجدول الحالي', 'Same as the current timetable')
                    : t('مقارنة بالحالي: ${diff.timeChanged.length} نُقلت · ${diff.roomChanged.length} تغيّر مكانها · ${diff.added.length} أُضيفت · ${diff.removed.length} أُزيلت',
                        'vs current: ${diff.timeChanged.length} moved · ${diff.roomChanged.length} new room · ${diff.added.length} added · ${diff.removed.length} removed'),
                style: orgText(context, size: 12, color: c.textMedium)),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          OutlinedButton.icon(onPressed: () => _preview(context), icon: const Icon(Icons.grid_view_rounded, size: 18), label: Text(t('معاينة', 'Preview'))),
          AppPrimaryButton(label: t('تطبيق', 'Apply'), icon: Icons.check_rounded, busy: busy, onPressed: busy ? null : onApply),
        ]),
      ]),
    );
  }

  void _preview(BuildContext context) => showAppSheet<void>(
      context,
      (ctx) => SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: AppSheetHeader('${t('الخيار', 'Option')} ${a.rank} · ${breakRuleLabel(a.rule)}')),
              Expanded(child: TimetablePreview(slots: a.slots, p: p, highlight: {for (final b in a.broken) '${b['course_id']}|${b['day']}'})),
            ]),
          ));
}

class _Fig extends StatelessWidget {
  const _Fig({required this.icon, required this.value, required this.label, this.color});
  final IconData icon;
  final String value, label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Icon(icon, size: 18, color: color ?? c.primary),
      const SizedBox(height: 2),
      Text(value, style: orgText(context, size: 18, w: FontWeight.w800, color: color)),
      Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: orgText(context, size: 11, color: c.textMedium)),
    ]);
  }
}

/// A read-only weekly grid of any version's slots (days × periods, merged multi-period sessions); scrolls both ways.
class TimetablePreview extends StatelessWidget {
  const TimetablePreview({super.key, required this.slots, required this.p, this.highlight = const {}});
  final List<Map<String, dynamic>> slots;
  final OrgScheduleProvider p;
  final Set<String> highlight; // 'course|day' cells drawn as "a rule gives way here"

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = timetableNamesOf(p);
    final days = ScheduleDraft.fromJson(p.schedule ?? const {}).days;
    final g = TimetableGrid.build(slots, p.periods, days: days);
    final labels = dayLabelsPlain();
    const dayW = 92.0, colW = 132.0, rowH = 78.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(width: dayW),
            for (final per in g.periods)
              Container(
                width: colW,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Text('${per['label'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, w: FontWeight.w800)),
                  Text(periodRange(per), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 10.5, color: c.textMedium)),
                ]),
              ),
          ]),
          for (final d in g.days)
            Row(children: [
              SizedBox(width: dayW, height: rowH, child: Center(child: Text(labels[d] ?? d, style: orgText(context, w: FontWeight.w800)))),
              for (final e in g.rows[d]!)
                Container(
                  width: colW * e.span + 4 * (e.span - 1), // spans the 2+2 px gaps between the merged columns
                  height: rowH,
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: e.isEmpty ? c.inputBg.withValues(alpha: 0.5) : c.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: e.sessions.any((s) => highlight.contains('${s['course_id']}|$d')) ? c.warning : c.divider,
                        width: e.sessions.any((s) => highlight.contains('${s['course_id']}|$d')) ? 2 : 1),
                  ),
                  child: e.isEmpty
                      ? const SizedBox.shrink()
                      // fixed-height cell: one line per session when several share it, and clipped under a large text scale
                      : Column(clipBehavior: Clip.hardEdge, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final s in e.sessions.take(2))
                            Text(
                                '${names.course(s['course_id'])}${s['kind'] == 'lab' ? ' · ${t('عملي', 'Lab')}' : ''}${s['room_id'] == null ? '' : ' · ${names.room(s['room_id'])}'}',
                                maxLines: e.sessions.length > 1 ? 1 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: orgText(context, size: 11, w: FontWeight.w700)),
                          if (e.sessions.length > 2) Text('+${e.sessions.length - 2}', style: orgText(context, size: 11, color: c.textMedium)),
                        ]),
                ),
            ]),
        ]),
      ),
    );
  }
}
