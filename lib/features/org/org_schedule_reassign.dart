// lib/features/org/org_schedule_reassign.dart — change who teaches a session: scope, rebuilt timetable, before/after.
//
//   ReassignPlan / ReassignVersion   pure: POST …/slots/{id}/reassign?dry_run=true — before & after with metrics,
//                                    ranking, moved sessions, conflicts, and the winner
//   askReassignScope                 the confirmation: all sessions of the course · this weekly session · one date only
//   pickSlotDate                     a date on the slot's weekday (scope "once")
//   ReassignCompareSheet             the two versions side by side, ranked (#1 recommended), Apply / Keep
//   showReassignCompare              opens it; true = apply the after version
//
// Pure parts are tested in test/org/org_reassign_test.dart; the sheet in test/ui/reassign_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../admin/admin_common.dart';
import 'org_common.dart' show dayLabels;
import 'org_ui.dart' show OrgActionCard, orgText;

const reassignScopes = ['course', 'weekly', 'once'];

class ReassignMetrics {
  const ReassignMetrics({this.hard = 0, this.unplaced = 0, this.warnings = 0, this.soft = 0, this.moved = 0, this.changed = 0, this.score = 0});
  final int hard, unplaced, warnings, soft, moved, changed, score;

  factory ReassignMetrics.of(Map<String, dynamic> m) => ReassignMetrics(
      hard: asInt(m['hard']), unplaced: asInt(m['unplaced']), warnings: asInt(m['warnings']), soft: asInt(m['soft']), moved: asInt(m['moved']), changed: asInt(m['changed']), score: asInt(m['score']));

  /// the server's order: hard → unplaced → warnings → soft → moved (lower is better)
  List<int> get key => [hard, unplaced, warnings, soft, moved];
  bool get valid => hard == 0 && unplaced == 0;
}

class ReassignVersion {
  const ReassignVersion({required this.name, required this.metrics, this.conflicts = const [], this.changes = const []});
  final String name; // before | after
  final ReassignMetrics metrics;
  final List<Map<String, dynamic>> conflicts, changes;

  factory ReassignVersion.of(String name, Map<String, dynamic> m) =>
      ReassignVersion(name: name, metrics: ReassignMetrics.of(asMap(m['metrics'])), conflicts: asMapList(m['conflicts']), changes: asMapList(m['changes']));
}

class ReassignPlan {
  const ReassignPlan({required this.scope, required this.field, this.userId, this.targets = const [], this.released = const [], this.resolved = false, required this.before, required this.after, this.winner = 'after', this.ranking = const [], this.reasonAr = '', this.reasonEn = '', this.version = 0});
  final String scope, field, winner, reasonAr, reasonEn;
  final int? userId;
  final List<int> targets, released;
  final bool resolved;
  final ReassignVersion before, after;
  final List<Map<String, dynamic>> ranking;
  final int version;

  bool get afterWins => winner == 'after';
  String get reason => t(reasonAr, reasonEn);
  int rankOf(String name) => asInt(ranking.where((r) => r['version'] == name).firstOrNull?['rank'], name == winner ? 1 : 2);
  ReassignVersion of(String name) => name == 'after' ? after : before;

  factory ReassignPlan.of(Map<String, dynamic> m) => ReassignPlan(
        scope: '${m['scope'] ?? 'weekly'}',
        field: '${m['field'] ?? 'teacher_id'}',
        userId: m['user_id'] == null ? null : asInt(m['user_id']),
        targets: [for (final i in (m['targets'] as List? ?? const [])) asInt(i)],
        released: [for (final i in (m['released'] as List? ?? const [])) asInt(i)],
        resolved: m['resolved'] == true,
        before: ReassignVersion.of('before', asMap(m['before'])),
        after: ReassignVersion.of('after', asMap(m['after'])),
        winner: '${m['winner'] ?? 'after'}',
        ranking: asMapList(m['ranking']),
        reasonAr: '${m['reason_ar'] ?? m['reason_en'] ?? ''}',
        reasonEn: '${m['reason_en'] ?? m['reason_ar'] ?? ''}',
        version: asInt(m['version']),
      );
}

String reassignScopeTitle(String scope) => switch (scope) {
      'course' => t('كل حصص المقرر', 'Every session of the course'),
      'once' => t('هذه الحصة في تاريخ واحد فقط', 'This session on one date only'),
      _ => t('هذه الحصة كل أسبوع', 'This weekly session only'),
    };

String reassignScopeHint(String scope) => switch (scope) {
      'course' => t('يتغيّر المدرس في كل حصص هذا المقرر من النوع نفسه، ويُحدَّث عبء المقرر', 'Changes the staff on every session of this course of the same kind, and on the course load'),
      'once' => t('تغيير لتاريخ واحد (بديل) — يبقى الجدول الأسبوعي كما هو ويُبلَّغ الطلاب', 'A one-date change (a substitute) — the weekly timetable stays, the students are told'),
      _ => t('يتغيّر في هذه الحصة كل أسبوع وتُثبَّت؛ باقي حصص المقرر كما هي', 'Changes this session every week and pins it; the other sessions of the course stay'),
    };

/// "Do you want this change for every session of the course, this weekly session, or one date only?"
Future<String?> askReassignScope(BuildContext context, {required String who, required String fieldLabel}) {
  return showAdminSheet<String>(context, (ctx) {
    final c = ctx.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(t('تغيير $fieldLabel إلى $who', 'Change $fieldLabel to $who')),
        Text(
            t('على أي نطاق تريد هذا التغيير؟ يُعاد بناء ما يتأثر من الجدول وتُعرض النسختان قبل وبعد مرتّبتين قبل الحفظ.',
                'How far should this change go? What it affects is rebuilt and both versions, before and after, are shown ranked before anything is saved.'),
            style: orgText(ctx, size: 12.5, color: c.textMedium)),
        const SizedBox(height: 10),
        for (final (scope, icon, col) in [('course', Icons.menu_book_rounded, c.primary), ('weekly', Icons.event_repeat_rounded, c.success), ('once', Icons.event_rounded, c.warning)])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OrgActionCard(icon: icon, color: col, title: reassignScopeTitle(scope), subtitle: reassignScopeHint(scope), onTap: () => Navigator.pop(ctx, scope)),
          ),
      ]),
    );
  });
}

int weekdayIndexOf(String day) => const {'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7}[day] ?? 1;

/// The first date on or after [from] that falls on [day].
DateTime nextDateOf(String day, DateTime from) {
  var d = DateTime(from.year, from.month, from.day);
  while (d.weekday != weekdayIndexOf(day)) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A date that falls on the slot's weekday (scope "once"), today or later.
Future<DateTime?> pickSlotDate(BuildContext context, String day, {DateTime? now}) {
  final first = nextDateOf(day, now ?? DateTime.now());
  return showDatePicker(
    context: context,
    initialDate: first,
    firstDate: first,
    lastDate: first.add(const Duration(days: 365)),
    selectableDayPredicate: (d) => d.weekday == weekdayIndexOf(day),
    helpText: t('اختر تاريخ الحصة (${dayLabels()[day] ?? day})', 'Pick the session date (${dayLabels()[day] ?? day})'),
  );
}

/// Before / after, ranked. [names] course names, [people] user names, [periods] period id → label, [rooms] room names.
class ReassignCompareSheet extends StatelessWidget {
  const ReassignCompareSheet({super.key, required this.plan, this.names = const {}, this.people = const {}, this.periods = const {}, this.rooms = const {}, this.onApply, this.onKeep});
  final ReassignPlan plan;
  final Map<int, String> names, people, periods, rooms;
  final VoidCallback? onApply, onKeep;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final who = p.userId == null ? t('بلا أحد', 'nobody') : (people[p.userId] ?? '#${p.userId}');
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final cards = [for (final name in ['before', 'after']) _versionCard(context, p.of(name), p.rankOf(name) == 1)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(t('قبل وبعد التغيير', 'Before and after')),
      Text('${reassignScopeTitle(p.scope)} · ${p.field == 'teacher_id' ? t('المدرس', 'teacher') : t('المعيد', 'assistant')}: $who',
          style: orgText(context, size: 12.5, color: c.textMedium)),
      if (p.resolved)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(t('تعارض التغيير مع حصص أخرى، فأُعيد حل الحصص المتأثرة فقط — باقي الجدول كما هو.', 'The change clashed with other sessions, so only the affected ones were re-solved — the rest stays.'),
              style: orgText(context, size: 12, color: c.textMedium)),
        ),
      const SizedBox(height: 10),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])])
      else ...[
        cards[0],
        const SizedBox(height: 8),
        cards[1],
      ],
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.leaderboard_rounded, size: 16, color: c.textMedium),
        const SizedBox(width: 6),
        Expanded(child: Text(p.reason, style: orgText(context, size: 12, color: c.textMedium))),
      ]),
      if (p.after.changes.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(t('ما يتغيّر (${p.after.changes.length})', 'What changes (${p.after.changes.length})'), style: orgText(context, w: FontWeight.w800)),
        for (final x in p.after.changes.take(8)) _changeLine(context, x),
        if (p.after.changes.length > 8) Text(t('+${p.after.changes.length - 8} أخرى', '+${p.after.changes.length - 8} more'), style: orgText(context, size: 12, color: c.textLight)),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: onApply,
          icon: Icon(p.afterWins ? Icons.check_rounded : Icons.warning_amber_rounded, size: 18),
          label: Text(p.afterWins ? t('تطبيق النسخة بعد التغيير', 'Apply the after version') : t('تطبيق رغم أنها أسوأ', 'Apply although it ranks worse')),
          style: FilledButton.styleFrom(backgroundColor: p.afterWins ? null : c.warning),
        ),
        OutlinedButton.icon(onPressed: onKeep, icon: const Icon(Icons.undo_rounded, size: 18), label: Text(t('إبقاء النسخة الحالية', 'Keep the current version'))),
      ]),
    ]);
  }

  Widget _versionCard(BuildContext context, ReassignVersion v, bool top) {
    final c = context.colors;
    final m = v.metrics;
    final col = top ? c.success : c.textLight;
    final title = v.name == 'after' ? t('بعد التغيير', 'After') : t('قبل التغيير', 'Before');
    Widget stat(String label, int n, {bool bad = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: (bad && n > 0 ? c.danger : c.textLight).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text('$label $n', style: orgText(context, size: 11.5, w: FontWeight.w700, color: bad && n > 0 ? c.danger : c.textMedium)),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: col.withValues(alpha: top ? 0.6 : 0.3), width: top ? 1.5 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: top ? c.success : c.inputBg, borderRadius: BorderRadius.circular(8)),
            child: Text(top ? t('#1 مقترح', '#1 recommended') : '#2', style: orgText(context, size: 11, w: FontWeight.w800, color: top ? Colors.white : c.textMedium)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: orgText(context, w: FontWeight.w800))),
          Text('${m.score}', style: orgText(context, size: 18, w: FontWeight.w900, color: top ? c.success : c.textMedium)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: m.score / 100, minHeight: 6, color: top ? c.success : c.textLight, backgroundColor: c.textLight.withValues(alpha: 0.15)),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          stat(t('تعارض إلزامي', 'hard'), m.hard, bad: true),
          stat(t('بلا مكان', 'unplaced'), m.unplaced, bad: true),
          stat(t('تنبيه', 'warnings'), m.warnings),
          stat(t('تفضيل', 'soft'), m.soft),
          if (v.name == 'after') stat(t('نُقلت', 'moved'), m.moved),
        ]),
        if (v.conflicts.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final x in v.conflicts.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(x['severity'] == 'error' ? Icons.block_rounded : Icons.warning_amber_rounded, size: 14, color: x['severity'] == 'error' ? c.danger : c.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(t('${x['text_ar'] ?? x['type']}', '${x['text_en'] ?? x['type']}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 11.5, color: c.textMedium))),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _changeLine(BuildContext context, Map<String, dynamic> x) {
    final c = context.colors;
    final labels = dayLabels();
    String cell(Map<String, dynamic> m) => [
          if (m['day'] != null) labels['${m['day']}'] ?? '${m['day']}',
          if (m['period_id'] != null) periods[asInt(m['period_id'])] ?? '#${m['period_id']}',
          if (m['room_id'] != null) rooms[asInt(m['room_id'])] ?? '',
          if (m['teacher_id'] != null) people[asInt(m['teacher_id'])] ?? '#${m['teacher_id']}',
          if (m['assistant_id'] != null) people[asInt(m['assistant_id'])] ?? '#${m['assistant_id']}',
        ].where((s) => s.isNotEmpty).join(' · ');
    final course = names[asInt(x['course_id'])] ?? '#${x['course_id']}';
    final kind = x['kind'] == 'lab' ? ' · ${t('عملي', 'lab')}' : '';
    final what = switch ('${x['change']}') {
      'moved' => '${cell(asMap(x['from']))} ← ${cell(asMap(x['to']))}',
      'placed' => '${t('وُضعت في', 'placed at')} ${cell(asMap(x['to']))}',
      'unplaced' => t('بلا مكان', 'left unplaced'),
      _ => '${cell(asMap(x['from']))} ← ${cell(asMap(x['to']))}',
    };
    final icon = switch ('${x['change']}') { 'moved' => Icons.low_priority_rounded, 'placed' => Icons.add_location_alt_rounded, 'unplaced' => Icons.location_off_rounded, _ => Icons.person_rounded };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: x['change'] == 'unplaced' ? c.danger : c.textMedium),
        const SizedBox(width: 6),
        Expanded(child: Text('$course$kind: $what', style: orgText(context, size: 12, color: c.textMedium))),
      ]),
    );
  }
}

/// Opens the comparison; resolves true to apply the after version, false / null to keep the current one.
Future<bool?> showReassignCompare(BuildContext context, ReassignPlan plan,
    {Map<int, String> names = const {}, Map<int, String> people = const {}, Map<int, String> periods = const {}, Map<int, String> rooms = const {}}) {
  return showAdminSheet<bool>(
    context,
    (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: ReassignCompareSheet(plan: plan, names: names, people: people, periods: periods, rooms: rooms, onApply: () => Navigator.pop(ctx, true), onKeep: () => Navigator.pop(ctx, false)),
    ),
  );
}
