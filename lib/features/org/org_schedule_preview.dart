// lib/features/org/org_schedule_preview.dart — BEFORE / AFTER of one fix, drawn on the timetable, before it is applied.
//
//   ChangePlan          pure: POST …/remedies/preview {action} (schedule_autopilot.preview) or a quick action's
//                       `changes` — the two versions with metrics, the conflicts they leave, the changes, the winner
//   applyChanges        pure: the slots after the plan's changes (moved · changed · placed · unplaced)
//   highlightOf         pure: which slots to highlight on each snapshot (before: what moves away · after: where it lands)
//   MiniTimetable       a compact days × periods grid; highlighted sessions are coloured, the rest stay quiet
//   ChangePreviewSheet  both snapshots side by side (stacked on a phone), metrics, what changes, Apply / Keep
//   showChangePreview   opens it; true = apply
//   previewRemedy       the call; `missing` on an older server (the caller falls back to a text confirmation)
//
// Pure parts are tested in test/org/org_autopilot_test.dart; the widgets in test/ui/autopilot_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../admin/admin_common.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_schedule_insights.dart' show ActionOption;
import 'org_schedule_reassign.dart' show ReassignMetrics, ReassignVersion;
import 'org_v3.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

/// One fix as two versions. [regenerate] = a data change (nothing moves until the timetable is re-solved).
class ChangePlan {
  const ChangePlan({required this.title, required this.before, required this.after, this.winner = 'after', this.reasonAr = '', this.reasonEn = '', this.regenerate = false, this.resolved = false, this.targets = const [], this.ranking = const [], this.version = 0});
  final String title, winner, reasonAr, reasonEn;
  final ReassignVersion before, after;
  final bool regenerate, resolved;
  final List<int> targets;
  final List<Map<String, dynamic>> ranking;
  final int version;

  bool get afterWins => winner == 'after';
  String get reason => t(reasonAr, reasonEn);
  List<Map<String, dynamic>> get changes => after.changes;
  int rankOf(String name) => asInt(ranking.where((r) => r['version'] == name).firstOrNull?['rank'], name == winner ? 1 : 2);

  /// The server's preview (`POST …/remedies/preview`).
  factory ChangePlan.of(Map<String, dynamic> m, {String title = ''}) => ChangePlan(
        title: title,
        before: ReassignVersion.of('before', asMap(m['before'])),
        after: ReassignVersion.of('after', asMap(m['after'])),
        winner: '${m['winner'] ?? 'after'}',
        reasonAr: '${m['reason_ar'] ?? m['reason_en'] ?? ''}',
        reasonEn: '${m['reason_en'] ?? m['reason_ar'] ?? ''}',
        regenerate: m['regenerate'] == true,
        resolved: m['resolved'] == true,
        targets: [for (final i in (m['targets'] as List? ?? const [])) asInt(i)],
        ranking: asMapList(m['ranking']),
        version: asInt(m['version']),
      );

  /// A quick action (relax one rule / re-solve the affected part) from its dry run: counts, not full metrics.
  factory ChangePlan.quick({required String title, required int hardBefore, required int unplacedBefore, required int hardAfter, required int unplacedAfter, required List<Map<String, dynamic>> changes, int breaks = 0}) {
    final moved = changes.where((x) => x['change'] == 'moved' || x['change'] == 'placed').length;
    int score(int h, int u, int mv) => (100 - 25 * h - 15 * u - 2 * mv).clamp(0, 100);
    final before = ReassignMetrics(hard: hardBefore, unplaced: unplacedBefore, score: score(hardBefore, unplacedBefore, 0));
    final after = ReassignMetrics(hard: hardAfter, unplaced: unplacedAfter, moved: moved, warnings: breaks, score: score(hardAfter, unplacedAfter, moved));
    final wins = hardAfter + unplacedAfter <= hardBefore + unplacedBefore;
    return ChangePlan(
      title: title,
      before: ReassignVersion(name: 'before', metrics: before),
      after: ReassignVersion(name: 'after', metrics: after, changes: changes),
      winner: wins ? 'after' : 'before',
      reasonAr: 'المشكلات ${hardBefore + unplacedBefore} ← ${hardAfter + unplacedAfter}${moved > 0 ? '، نُقلت أو وُضعت $moved حصة' : ''}${breaks > 0 ? '، $breaks اقتراح كسر قاعدة للمراجعة' : ''}',
      reasonEn: 'Problems ${hardBefore + unplacedBefore} → ${hardAfter + unplacedAfter}${moved > 0 ? ', $moved session(s) moved or placed' : ''}${breaks > 0 ? ', $breaks rule-break proposal(s) to review' : ''}',
      ranking: [
        {'version': wins ? 'after' : 'before', 'rank': 1},
        {'version': wins ? 'before' : 'after', 'rank': 2},
      ],
    );
  }
}

/// The slots after [changes]: `unplaced` removes, `moved` / `changed` patch the fields in `to`, `placed` adds a new
/// session (negative id) at `to`.
List<Map<String, dynamic>> applyChanges(List<Map<String, dynamic>> slots, List<Map<String, dynamic>> changes) {
  final out = <int, Map<String, dynamic>>{for (final s in slots) asInt(s['id']): Map<String, dynamic>.from(s)};
  for (final x in changes) {
    final id = asInt(x['slot_id']);
    switch ('${x['change']}') {
      case 'unplaced':
        out.remove(id);
      case 'placed':
        out[id] = {'id': id, 'course_id': x['course_id'], 'kind': x['kind'] ?? 'lecture', 'group_no': x['group_no'], ...asMap(x['to'])};
      default:
        final cur = out[id];
        if (cur != null) out[id] = {...cur, ...asMap(x['to'])};
    }
  }
  return out.values.toList();
}

/// before: the sessions that move, change or disappear · after: the sessions that landed somewhere or changed.
({Set<int> before, Set<int> after}) highlightOf(List<Map<String, dynamic>> changes) => (
      before: {for (final x in changes) if (x['change'] != 'placed') asInt(x['slot_id'])},
      after: {for (final x in changes) if (x['change'] != 'unplaced') asInt(x['slot_id'])},
    );

/// "Physics · lab: Sunday · P1 ← Monday · P2 · Hall 3"
String changeLineText(Map<String, dynamic> x, {Map<int, String> names = const {}, Map<int, String> people = const {}, Map<int, String> periods = const {}, Map<int, String> rooms = const {}}) {
  final labels = dayLabels();
  String cell(Map<String, dynamic> m) => [
        if (m['day'] != null) labels['${m['day']}'] ?? '${m['day']}',
        if (m['period_id'] != null) periods[asInt(m['period_id'])] ?? '#${m['period_id']}',
        if (m['room_id'] != null) rooms[asInt(m['room_id'])] ?? '',
        if (m['teacher_id'] != null) people[asInt(m['teacher_id'])] ?? '#${m['teacher_id']}',
        if (m['assistant_id'] != null) people[asInt(m['assistant_id'])] ?? '#${m['assistant_id']}',
        if (m['group_no'] != null) '${t('مجموعة', 'group')} ${m['group_no']}',
        if (m.containsKey('locked')) (m['locked'] == true ? t('مثبّتة', 'pinned') : t('غير مثبّتة', 'unpinned')),
      ].where((s) => s.isNotEmpty).join(' · ');
  final course = names[asInt(x['course_id'])] ?? '#${x['course_id']}';
  final kind = x['kind'] == 'lab' ? ' · ${t('عملي', 'lab')}' : '';
  final what = switch ('${x['change']}') {
    'moved' => '${cell(asMap(x['from']))} ← ${cell(asMap(x['to']))}',
    'placed' => '${t('وُضعت في', 'placed at')} ${cell(asMap(x['to']))}',
    'unplaced' => t('بلا مكان', 'left unplaced'),
    _ => '${cell(asMap(x['from']))} ← ${cell(asMap(x['to']))}',
  };
  return '$course$kind: $what';
}

/// A compact timetable: rows = periods, columns = days. A session in [highlight] is drawn in [tone] (danger on the
/// "before" snapshot, success on the "after"); every other session stays grey. Scrolls sideways on a phone.
class MiniTimetable extends StatelessWidget {
  const MiniTimetable({super.key, required this.days, required this.periods, required this.slots, required this.highlight, required this.tone, this.names = const {}, this.title});
  final List<String> days;
  final List<Map<String, dynamic>> periods, slots;
  final Set<int> highlight;
  final Color tone;
  final Map<int, String> names;
  final String? title;

  static const cellW = 76.0, cellH = 46.0, headW = 44.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = dayLabels();
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;   // the cells grow with the text size
    final rowH = cellH * scale;
    final byCell = <String, List<Map<String, dynamic>>>{};
    for (final s in slots) {
      byCell.putIfAbsent('${s['day']}|${s['period_id']}', () => []).add(s);
    }
    Widget chip(Map<String, dynamic> s) {
      final hot = highlight.contains(asInt(s['id']));
      final name = names[asInt(s['course_id'])] ?? '#${s['course_id']}';
      final short = name.length > 9 ? '${name.substring(0, 8)}…' : name;
      return Container(
        margin: const EdgeInsets.only(bottom: AppSpace.xxs / 2),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: 1),
        decoration: BoxDecoration(
          color: hot ? tone.withValues(alpha: 0.22) : c.textLight.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: hot ? tone : Colors.transparent, width: hot ? 1.4 : 0),
        ),
        child: Text(short, maxLines: 1, overflow: TextOverflow.clip, softWrap: false,
            style: TextStyle(fontFamily: AppFonts.family, fontSize: 9.5, fontWeight: hot ? FontWeight.w600 : FontWeight.w600, color: hot ? tone : c.textMedium)),
      );
    }

    Widget head(String s, {double w = cellW}) => SizedBox(
          width: w,
          height: 22,
          child: Center(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: c.textMedium))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.chip))),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark))),
          ]),
        ),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: c.textLight.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [head('', w: headW), for (final d in days) head(labels[d] ?? d)]),
              for (final p in periods)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: headW, height: rowH, child: Center(child: Text('${p['label'] ?? p['id']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: c.textMedium)))),
                  for (final d in days)
                    Container(
                      width: cellW,
                      height: rowH,
                      padding: const EdgeInsets.all(AppSpace.xxs),
                      decoration: BoxDecoration(border: Border.all(color: c.textLight.withValues(alpha: 0.15), width: 0.5)),
                      child: Builder(builder: (_) {
                        final xs = byCell['$d|${p['id']}'] ?? const [];
                        final hot = xs.where((s) => highlight.contains(asInt(s['id']))).toList();
                        final rest = xs.where((s) => !highlight.contains(asInt(s['id']))).toList();
                        final shown = [...hot, ...rest].take(2).toList();
                        // a scroll view clips quietly: a third session never overflows the cell
                        return SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (final s in shown) chip(s),
                            if (xs.length > 2) Text('+${xs.length - 2}', style: AppType.meta(context).copyWith(color: c.textLight)),
                          ]),
                        );
                      }),
                    ),
                ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// The two snapshots of the timetable around one fix, with what changes and a verdict. [slots] = the timetable now.
class ChangePreviewSheet extends StatelessWidget {
  const ChangePreviewSheet({super.key, required this.plan, required this.slots, required this.periods, required this.days, this.names = const {}, this.people = const {}, this.rooms = const {}, this.onApply, this.onKeep, this.applyLabel});
  final ChangePlan plan;
  final List<Map<String, dynamic>> slots, periods;
  final List<String> days;
  final Map<int, String> names, people, rooms;
  final VoidCallback? onApply, onKeep;
  final String? applyLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final after = applyChanges(slots, p.changes);
    final hl = highlightOf(p.changes);
    final periodLabels = {for (final x in periods) asInt(x['id']): '${x['label'] ?? x['id']}'};
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final beforeGrid = _snapshot(context, t('قبل', 'Before'), slots, hl.before, c.danger, p.before, p.rankOf('before') == 1);
    final afterGrid = _snapshot(context, t('بعد', 'After'), after, hl.after, c.success, p.after, p.rankOf('after') == 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(t('قبل وبعد التطبيق', 'Before and after')),
      if (p.title.isNotEmpty) Text(p.title, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
      Text(
          p.regenerate
              ? t('هذا تغيير في البيانات لا في الشبكة: بعد تطبيقه يُعاد حل الجدول ليستفيد منه.', 'This changes the data, not the grid: after applying, the timetable is re-solved to use it.')
              : t('ما يتحرك مظلَّل: بالأحمر حيث كان، وبالأخضر حيث يستقر. لا يُحفظ شيء قبل «تطبيق».', 'What moves is highlighted: red where it was, green where it lands. Nothing is saved before Apply.'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      if (p.resolved)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(t('أُعيد حل الحصص المتعارضة فقط — باقي الجدول كما هو.', 'Only the clashing sessions were re-solved — the rest stays.'), style: AppType.meta(context).copyWith(color: c.textMedium)),
        ),
      const SizedBox(height: AppSpace.sm),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: beforeGrid), const SizedBox(width: AppSpace.sm), Expanded(child: afterGrid)])
      else ...[
        beforeGrid,
        const SizedBox(height: AppSpace.sm),
        afterGrid,
      ],
      const SizedBox(height: AppSpace.xs),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.leaderboard_rounded, size: AppIconSize.sm, color: c.textMedium),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(p.reason, style: AppType.meta(context).copyWith(color: c.textMedium))),
      ]),
      if (p.changes.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('ما يتغيّر (${p.changes.length})', 'What changes (${p.changes.length})'), style: AppType.bodyStrong(context)),
        for (final x in p.changes.take(8))
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                switch ('${x['change']}') { 'moved' => Icons.low_priority_rounded, 'placed' => Icons.add_location_alt_rounded, 'unplaced' => Icons.location_off_rounded, _ => Icons.edit_rounded },
                size: AppIconSize.xs,
                color: x['change'] == 'unplaced' ? c.danger : c.textMedium),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(changeLineText(x, names: names, people: people, periods: periodLabels, rooms: rooms), style: AppType.meta(context).copyWith(color: c.textMedium))),
            ]),
          ),
        if (p.changes.length > 8) Text(t('+${p.changes.length - 8} أخرى', '+${p.changes.length - 8} more'), style: AppType.meta(context).copyWith(color: c.textLight)),
      ],
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        FilledButton.icon(
          onPressed: onApply,
          icon: Icon(p.afterWins ? Icons.check_rounded : Icons.warning_amber_rounded, size: AppIconSize.md),
          label: Text(applyLabel ?? (p.afterWins ? t('تطبيق', 'Apply') : t('تطبيق رغم أنها أسوأ', 'Apply although it ranks worse'))),
          style: FilledButton.styleFrom(backgroundColor: p.afterWins ? null : c.warning),
        ),
        OutlinedButton.icon(onPressed: onKeep, icon: const Icon(Icons.undo_rounded, size: AppIconSize.md), label: Text(t('إبقاء الوضع الحالي', 'Keep as it is'))),
      ]),
    ]);
  }

  Widget _snapshot(BuildContext context, String title, List<Map<String, dynamic>> xs, Set<int> hl, Color tone, ReassignVersion v, bool top) {
    final c = context.colors;
    final m = v.metrics;
    Widget stat(String label, int n, {bool bad = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
          decoration: BoxDecoration(color: (bad && n > 0 ? c.danger : c.textLight).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Text('$label $n', style: AppType.overline(context).copyWith(color: bad && n > 0 ? c.danger : c.textMedium)),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: (top ? c.success : c.textLight).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: (top ? c.success : c.textLight).withValues(alpha: top ? 0.6 : 0.3), width: top ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
            decoration: BoxDecoration(color: top ? c.success : c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Text(top ? t('#1 مقترح', '#1 recommended') : '#2', style: AppType.overline(context).copyWith(color: top ? c.onHero : c.textMedium)),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(title, style: AppType.bodyStrong(context))),
          Text('${m.score}', style: AppType.section(context).copyWith(color: top ? c.success : c.textMedium)),
        ]),
        const SizedBox(height: AppSpace.xs),
        MiniTimetable(days: days, periods: periods, slots: xs, highlight: hl, tone: tone, names: names),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          stat(t('تعارض إلزامي', 'hard'), m.hard, bad: true),
          stat(t('بلا مكان', 'unplaced'), m.unplaced, bad: true),
          if (m.warnings > 0) stat(t('تنبيه', 'warnings'), m.warnings),
          if (m.soft > 0) stat(t('تفضيل', 'soft'), m.soft),
          if (v.name == 'after' && m.moved > 0) stat(t('نُقلت', 'moved'), m.moved),
        ]),
        if (v.conflicts.isNotEmpty)
          for (final x in v.conflicts.take(3))
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(x['severity'] == 'error' ? Icons.block_rounded : Icons.warning_amber_rounded, size: AppIconSize.xs, color: x['severity'] == 'error' ? c.danger : c.warning),
                const SizedBox(width: AppSpace.xxs),
                Expanded(child: Text(t('${x['text_ar'] ?? x['type']}', '${x['text_en'] ?? x['type']}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium))),
              ]),
            ),
      ]),
    );
  }
}

/// Opens the comparison; resolves true to apply, false / null to keep the current version.
Future<bool?> showChangePreview(BuildContext context, ChangePlan plan,
    {required List<Map<String, dynamic>> slots, required List<Map<String, dynamic>> periods, required List<String> days, Map<int, String> names = const {}, Map<int, String> people = const {}, Map<int, String> rooms = const {}, String? applyLabel}) {
  return showAdminSheet<bool>(
    context,
    (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
      child: ChangePreviewSheet(plan: plan, slots: slots, periods: periods, days: days, names: names, people: people, rooms: rooms, applyLabel: applyLabel, onApply: () => Navigator.pop(ctx, true), onKeep: () => Navigator.pop(ctx, false)),
    ),
  );
}

/// POST …/remedies/preview. `missing` = an older server (the caller shows a text confirmation instead).
Future<({ChangePlan? plan, bool missing})> previewRemedy(OrgScheduleProvider p, ActionOption a) async {
  final id = p.schedule?['id'];
  if (id == null) return (plan: null, missing: false);
  final r = await orgCall(() => p.api.post('${p.base}/schedules/$id/remedies/preview', body: {'action': a.toJson()}), quiet: true);
  if (r.ok) return (plan: ChangePlan.of(r.map, title: a.text), missing: false);
  return (plan: null, missing: r.endpointMissing);
}
