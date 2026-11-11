// lib/features/org/org_schedule_insights.dart — what the CP-SAT engine explains, before and after a generation.
//
//   PreflightReport / PreflightFinding   pure: GET …/preflight — impossible inputs in plain words with their fix
//   ActionOption / RankedActions         one ranked way out of a finding or a conflict (shared with org_schedule_remedies)
//   DataHealthCard                       the data-health panel (blockers · warnings · demand vs supply · engine)
//   ruleShort / coreText                 pure: a rule name → a few words; "blocked by A + B" for unscheduled[].core
//   ExplainRows                          the per-option reasons of an unplaced session (unscheduled[].explain)
//   QualityReport                        pure: workload balance · idle gaps · same-day repeats · room use → score 0–100
//   QualityCard                          the quality report after a generation
//   WhyHere / WhyHereSection             GET …/slots/{id}/why — why a placed session sits where it is
//
// Everything pure is tested in test/org/org_insights_test.dart; the widgets in test/ui/insights_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show RowCard;
import 'org_common.dart' show dayLabels;
import 'org_providers.dart' show orgDays;
import 'package:flutter_education_app/design/app_tokens.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pre-flight (data health)
// ═════════════════════════════════════════════════════════════════════════════

/// One way to solve a finding or a conflict, as the server ranks it (`actions[]` of GET …/preflight and
/// GET …/remedies): [auto] ones are applied with one click, the others say what to do by hand.
class ActionOption {
  const ActionOption({required this.id, required this.kind, required this.rank, required this.score, required this.auto, required this.textAr, required this.textEn, this.whyAr = '', this.whyEn = '', this.params = const {}});
  final String id, kind, textAr, textEn, whyAr, whyEn;
  final int rank, score;
  final bool auto;

  /// the parameters the server needs back (slot_id, day, group_size, …)
  final Map<String, dynamic> params;

  String get text => t(textAr, textEn);
  String get why => t(whyAr, whyEn);

  /// what POST …/remedies/apply takes
  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, ...params};

  factory ActionOption.of(Map<String, dynamic> m) => ActionOption(
        id: '${m['id'] ?? m['kind'] ?? ''}',
        kind: '${m['kind'] ?? ''}',
        rank: asInt(m['rank'], 1),
        score: asInt(m['score']),
        auto: m['auto'] == true,
        textAr: '${m['text_ar'] ?? m['text_en'] ?? m['kind'] ?? ''}',
        textEn: '${m['text_en'] ?? m['text_ar'] ?? m['kind'] ?? ''}',
        whyAr: '${m['why_ar'] ?? m['why_en'] ?? ''}',
        whyEn: '${m['why_en'] ?? m['why_ar'] ?? ''}',
        params: {for (final e in m.entries) if (!const {'id', 'kind', 'rank', 'score', 'auto', 'text_ar', 'text_en', 'why_ar', 'why_en'}.contains(e.key)) e.key: e.value},
      );

  static List<ActionOption> listOf(dynamic v) => [for (final x in asMapList(v)) ActionOption.of(x)]..sort((a, b) => a.rank.compareTo(b.rank));
}

class PreflightFinding {
  const PreflightFinding({required this.code, required this.severity, required this.textAr, required this.textEn, required this.fixAr, required this.fixEn, this.courseId, this.userId, this.roomId, this.detail = const {}, this.key = '', this.action = const {}, this.actions = const [], this.dismissed = false});
  final String code, severity, textAr, textEn, fixAr, fixEn;
  final int? courseId, userId, roomId;
  final Map<String, dynamic> detail;

  /// stable id of the recommendation (code + what it names): what accept / dismiss send back
  final String key;

  /// the best automatic fix (older servers: the only one) — `split_groups` {session_kind, group_size, groups} ·
  /// `raise_week_cap` {max_week} · …
  final Map<String, dynamic> action;

  /// every way out, best first (rank 1 = recommended); empty on an older server
  final List<ActionOption> actions;

  /// rejected by the admin (kept in the report, not counted)
  final bool dismissed;

  bool get blocker => severity == 'blocker';
  bool get automatic => actions.isNotEmpty ? actions.any((a) => a.auto) : action.isNotEmpty;
  ActionOption? get best => actions.where((a) => a.auto).firstOrNull;
  String get text => t(textAr, textEn);
  String get fix => t(fixAr, fixEn);

  /// What "Accept" will do, in words (empty when the fix is manual).
  String get actionText => (best?.text ?? '').isNotEmpty ? best!.text : _legacyActionText;

  String get _legacyActionText => switch ('${action['kind']}') {
        'split_groups' => t(
            'تقسيم ${_kindAr('${action['session_kind']}')} المقرر إلى ${asInt(action['groups'])} مجموعات بحد ${asInt(action['group_size'])} طالباً في خطة المقرر',
            'Split the course ${_kindEn('${action['session_kind']}')} into ${asInt(action['groups'])} groups of at most ${asInt(action['group_size'])} in the course plan'),
        'raise_week_cap' => t('رفع الحد الأسبوعي للعضو إلى ${asInt(action['max_week'])} فترة', "Raise the member's weekly cap to ${asInt(action['max_week'])} periods"),
        _ => '',
      };

  static String _kindAr(String k) => switch (k) { 'lab' => 'معمل', 'tutorial' => 'سكشن', _ => 'محاضرة' };
  static String _kindEn(String k) => switch (k) { 'lab' => 'lab', 'tutorial' => 'tutorial', _ => 'lecture' };

  factory PreflightFinding.of(Map<String, dynamic> m) {
    final actions = ActionOption.listOf(m['actions']);
    final legacy = asMap(m['action']);
    return PreflightFinding(
      code: '${m['code']}',
      severity: '${m['severity'] ?? 'warning'}',
      textAr: '${m['text_ar'] ?? m['text_en'] ?? m['code']}',
      textEn: '${m['text_en'] ?? m['text_ar'] ?? m['code']}',
      fixAr: '${m['fix_ar'] ?? m['fix_en'] ?? ''}',
      fixEn: '${m['fix_en'] ?? m['fix_ar'] ?? ''}',
      courseId: m['course_id'] == null ? null : asInt(m['course_id']),
      userId: m['user_id'] == null ? null : asInt(m['user_id']),
      roomId: m['room_id'] == null ? null : asInt(m['room_id']),
      detail: asMap(m['detail']),
      key: '${m['key'] ?? ''}',
      action: legacy,
      // an older server sends `action` only: show it as the one automatic option
      actions: actions.isNotEmpty || legacy.isEmpty
          ? actions
          : [ActionOption(id: '${legacy['kind']}', kind: '${legacy['kind']}', rank: 1, score: 80, auto: true, textAr: '', textEn: '', params: {for (final e in legacy.entries) if (e.key != 'kind') e.key: e.value})],
      dismissed: m['dismissed'] == true,
    );
  }
}

class PreflightReport {
  const PreflightReport({required this.findings, required this.summary, this.engine});
  final List<PreflightFinding> findings; // blockers first; dismissed ones included (see [visible] / [hidden])
  final Map<String, dynamic> summary; // sessions · periods_needed · cells · rooms · room_cells · utilization_pct · teachers · sessions_by_kind · cohorts
  final String? engine;

  /// the recommendations still standing / the ones the admin rejected
  List<PreflightFinding> get visible => [for (final f in findings) if (!f.dismissed) f];
  List<PreflightFinding> get hidden => [for (final f in findings) if (f.dismissed) f];

  int get blockers => visible.where((f) => f.blocker).length;
  int get automatic => visible.where((f) => f.automatic).length;
  int get warnings => visible.length - blockers;
  bool get clean => visible.isEmpty;
  int get sessions => asInt(summary['sessions']);
  int get utilizationPct => asInt(summary['utilization_pct']);

  factory PreflightReport.of(Map<String, dynamic> m) {
    final items = [for (final x in asMapList(m['findings'])) PreflightFinding.of(x)]..sort((a, b) => (a.blocker ? 0 : 1).compareTo(b.blocker ? 0 : 1));
    return PreflightReport(findings: items, summary: asMap(m['summary']), engine: m['engine'] as String?);
  }
}

/// The widest a Wrap item may be: the screen minus the card's own padding and margins.
double wrapWidth(BuildContext context) => (MediaQuery.sizeOf(context).width - 96).clamp(160.0, 900.0);

String engineLabel(String? engine) => switch (engine) {
      'cpsat' => t('محرّك CP-SAT (حل بالقيود)', 'CP-SAT constraint solver'),
      'heuristic' => t('المحرّك التقريبي', 'Heuristic engine'),
      _ => '',
    };

/// The data-health panel shown before (and next to) a generation. [names] resolve ids in the fix lines. Every
/// recommendation is a quick action: Accept (the server applies the fix, only when [PreflightFinding.automatic]) or
/// Reject (hidden, with Restore). [busy] holds the keys with a request in flight.
class DataHealthCard extends StatelessWidget {
  const DataHealthCard({super.key, required this.report, this.courseNames = const {}, this.people = const {}, this.rooms = const {}, this.onFix, this.onAccept, this.onAcceptAll, this.onReject, this.onRestore, this.busy = const {}});
  final PreflightReport report;
  final Map<int, String> courseNames, people, rooms;

  /// tapped a finding (open the course / member / room it names)
  final void Function(PreflightFinding f)? onFix;

  /// Accept one of the finding's ranked ways out (an automatic one); null = read-only
  final void Function(PreflightFinding f, ActionOption a)? onAccept;

  /// Accept the best automatic fix of every standing blocker in one go (POST …/preflight/accept-all)
  final VoidCallback? onAcceptAll;
  final void Function(PreflightFinding f)? onReject, onRestore;
  final Set<String> busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final col = r.blockers > 0 ? c.danger : (r.warnings > 0 ? c.warning : c.success);
    final s = r.summary;
    String who(PreflightFinding f) => [
          if (f.courseId != null) courseNames[f.courseId] ?? '#${f.courseId}',
          if (f.userId != null) people[f.userId] ?? '#${f.userId}',
          if (f.roomId != null) rooms[f.roomId] ?? '#${f.roomId}',
        ].join(' · ');
    return RowCard(
      accent: col,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r.clean ? Icons.health_and_safety_rounded : (r.blockers > 0 ? Icons.report_rounded : Icons.warning_amber_rounded), color: col, size: AppIconSize.md),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              r.clean
                  ? t('البيانات سليمة — جاهزة للتوليد', 'Data is healthy — ready to generate')
                  : r.blockers > 0
                      ? t('${r.blockers} مانع يوقف التوليد الكامل', '${r.blockers} blocker(s) prevent a complete timetable')
                      : t('${r.warnings} تنبيه على البيانات', '${r.warnings} data warning(s)'),
              style: AppType.bodyStrong(context).copyWith(color: col),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        // chips never grow past the card: each is bounded to the screen width (a Wrap gives none; a LayoutBuilder
        // is not allowed inside the card's intrinsic-height row)
        Wrap(spacing: 8, runSpacing: 4, children: [
          _chip(context, Icons.event_note_rounded, t('${r.sessions} حصة', '${r.sessions} sessions'), wrapWidth(context)),
          _chip(context, Icons.grid_on_rounded, t('${asInt(s['cells'])} خانة × ${asInt(s['rooms'])} قاعة', '${asInt(s['cells'])} cells × ${asInt(s['rooms'])} rooms'), wrapWidth(context)),
          _chip(context, Icons.speed_rounded, t('استغلال القاعات ${r.utilizationPct}٪', 'Room use ${r.utilizationPct}%'), wrapWidth(context)),
          if (asInt(s['cohorts']) > 0) _chip(context, Icons.groups_rounded, t('${asInt(s['cohorts'])} مجموعة طلاب', '${asInt(s['cohorts'])} student cohorts'), wrapWidth(context)),
          if (engineLabel(r.engine).isNotEmpty) _chip(context, Icons.memory_rounded, engineLabel(r.engine), wrapWidth(context)),
        ]),
        if (onAcceptAll != null && r.visible.where((f) => f.blocker && f.automatic).length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: FilledButton.tonalIcon(
              onPressed: busy.contains('*') ? null : onAcceptAll,
              icon: busy.contains('*') ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textMedium)) : const Icon(Icons.done_all_rounded, size: AppIconSize.sm),
              label: Text(t('قبول كل التوصيات المقترحة (${r.visible.where((f) => f.blocker && f.automatic).length})', 'Accept every recommended fix (${r.visible.where((f) => f.blocker && f.automatic).length})')),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        for (final f in r.visible.take(12))
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              onTap: onFix == null ? null : () => onFix!(f),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(f.blocker ? Icons.block_rounded : Icons.info_outline_rounded, size: AppIconSize.sm, color: f.blocker ? c.danger : c.warning),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.text, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
                    if (who(f).isNotEmpty) Text(who(f), style: AppType.meta(context).copyWith(color: c.textMedium)),
                    if (f.fix.isNotEmpty && f.actions.isEmpty) Text('${t('الحل', 'Fix')}: ${f.fix}', style: AppType.meta(context).copyWith(color: c.textMedium)),
                    if (f.actions.isNotEmpty)
                      RankedActions(
                        actions: f.actions,
                        onAccept: onAccept == null ? null : (a) => onAccept!(f, a),
                        busy: busy.contains(f.key),
                        trailing: onReject == null ? null : _rejectButton(context, f),
                      )
                    else if (onAccept != null || onReject != null)
                      _actions(context, f),
                  ]),
                ),
              ]),
            ),
          ),
        if (r.visible.length > 12) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(t('+${r.visible.length - 12} أخرى', '+${r.visible.length - 12} more'), style: AppType.meta(context).copyWith(color: c.textLight))),
        if (r.hidden.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text(t('${r.hidden.length} توصية مرفوضة', '${r.hidden.length} rejected recommendation(s)'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textLight)),
          ),
          for (final f in r.hidden.take(6))
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: Text(f.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight))),
                if (onRestore != null)
                  TextButton(
                    onPressed: busy.contains(f.key) ? null : () => onRestore!(f),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
                    child: Text(t('استعادة', 'Restore')),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _rejectButton(BuildContext context, PreflightFinding f) => OutlinedButton.icon(
        onPressed: busy.contains(f.key) ? null : () => onReject!(f),
        icon: const Icon(Icons.close_rounded, size: AppIconSize.sm),
        label: Text(t('رفض', 'Reject')),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm), foregroundColor: context.colors.textMedium),
      );

  /// Accept · Reject under a recommendation of an OLDER server (one `action`, no ranked list). A manual-only fix
  /// gets a small "by hand" label instead of Accept.
  Widget _actions(BuildContext context, PreflightFinding f) {
    final c = context.colors;
    final wait = busy.contains(f.key);
    final spinner = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textMedium));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (f.automatic && onAccept != null)
          Tooltip(
            message: f.actionText,
            child: FilledButton.tonalIcon(
              onPressed: wait ? null : () => onAccept!(f, f.best ?? f.actions.first),
              icon: wait ? spinner : const Icon(Icons.check_rounded, size: AppIconSize.sm),
              label: Text(t('قبول', 'Accept')),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm)),
            ),
          )
        else if (!f.automatic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
            decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Text(t('يُنفَّذ يدوياً', 'Fix by hand'), style: AppType.meta(context).copyWith(color: c.textMedium)),
          ),
        if (onReject != null)
          OutlinedButton.icon(
            onPressed: wait ? null : () => onReject!(f),
            icon: wait && !(f.automatic && onAccept != null) ? spinner : const Icon(Icons.close_rounded, size: AppIconSize.sm),
            label: Text(t('رفض', 'Reject')),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm), foregroundColor: c.textMedium),
          ),
      ]),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text, double maxWidth) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.isFinite ? maxWidth : 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
        decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AppIconSize.xs, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium))),
        ]),
      ),
    );
  }
}

/// The ranked ways out of one finding / conflict: rank badge · score · text · why · Accept (automatic) or a
/// "by hand" label. Shows the first [visibleCount], the rest behind "show all". [trailing] (e.g. Reject) sits on the
/// last row. Used by [DataHealthCard] and the remedies panel.
class RankedActions extends StatefulWidget {
  const RankedActions({super.key, required this.actions, this.onAccept, this.busy = false, this.trailing, this.visibleCount = 3});
  final List<ActionOption> actions;
  final void Function(ActionOption a)? onAccept;
  final bool busy;
  final Widget? trailing;
  final int visibleCount;

  @override
  State<RankedActions> createState() => _RankedActionsState();
}

class _RankedActionsState extends State<RankedActions> {
  bool all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = all ? widget.actions : widget.actions.take(widget.visibleCount).toList();
    final hidden = widget.actions.length - shown.length;
    final spinner = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textMedium));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final a in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Container(
              padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xs, AppSpace.xs, AppSpace.xs),
              decoration: BoxDecoration(
                color: (a.rank == 1 && a.auto ? c.success : c.textLight).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: (a.rank == 1 && a.auto ? c.success : c.divider).withValues(alpha: a.rank == 1 && a.auto ? 0.5 : 1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _rankBadge(context, a),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.text, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
                      if (a.why.isNotEmpty) Text(a.why, style: AppType.meta(context).copyWith(color: c.textMedium)),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _scoreChip(context, a),
                  if (a.auto && widget.onAccept != null)
                    FilledButton.tonalIcon(
                      onPressed: widget.busy ? null : () => widget.onAccept!(a),
                      icon: widget.busy ? spinner : const Icon(Icons.check_rounded, size: AppIconSize.sm),
                      label: Text(a.rank == 1 ? t('قبول (مقترح)', 'Accept (recommended)') : t('قبول', 'Accept')),
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm)),
                    )
                  else if (!a.auto)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                      decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(AppRadius.chip)),
                      child: Text(t('يُنفَّذ يدوياً', 'By hand'), style: AppType.meta(context).copyWith(color: c.textMedium)),
                    ),
                  if (identical(a, shown.last) && widget.trailing != null) widget.trailing!,
                ]),
              ]),
            ),
          ),
        if (hidden > 0 || all && widget.actions.length > widget.visibleCount)
          TextButton(
            onPressed: () => setState(() => all = !all),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
            child: Text(all ? t('أقل', 'Fewer') : t('+$hidden حلول أخرى', '+$hidden more ways')),
          ),
      ]),
    );
  }

  Widget _rankBadge(BuildContext context, ActionOption a) {
    final c = context.colors;
    final top = a.rank == 1 && a.auto;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: top ? c.success : c.inputBg, shape: BoxShape.circle),
      child: Text('#${a.rank}', style: AppType.overline(context).copyWith(color: top ? c.onHero : c.textMedium)),
    );
  }

  Widget _scoreChip(BuildContext context, ActionOption a) {
    final c = context.colors;
    final col = a.score >= 70 ? c.success : (a.score >= 40 ? c.warning : c.textLight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Text(t('الترجيح ${a.score}٪', 'Fit ${a.score}%'), style: AppType.overline(context).copyWith(color: col)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Explanations (unscheduled[].core / explain · why-here rules)
// ═════════════════════════════════════════════════════════════════════════════

/// A solver rule in a few words (short form for chips and "blocked by" lines).
String ruleShort(String rule) => switch (rule) {
      'teacher_busy' => t('المدرس مشغول', 'instructor busy'),
      'teacher_unavailable' => t('المدرس غير متاح', 'instructor unavailable'),
      'teacher_day_limit' => t('الحد اليومي للمدرس', 'instructor daily limit'),
      'teacher_week_limit' => t('الحد الأسبوعي للمدرس', 'instructor weekly cap'),
      'students_clash' => t('طلاب في حصة أخرى', 'students in another session'),
      'students_unavailable' => t('الطلاب غير متاحين', 'students unavailable'),
      'students_busy_elsewhere' => t('الطلاب في جدول آخر', 'students in another timetable'),
      'course_already_there' => t('حصة أخرى للمقرر', 'another session of the course'),
      'rooms_busy' => t('القاعات محجوزة', 'rooms taken'),
      'room_unavailable' => t('القاعة غير متاحة', 'room unavailable'),
      'no_room_fits' => t('لا قاعة مناسبة', 'no fitting room'),
      'travel_gap' => t('وقت الانتقال بين المباني', 'travel time between buildings'),
      'no_consecutive_periods' => t('لا فترات متتالية كافية', 'not enough consecutive periods'),
      'time_limit' => t('انتهى وقت الحل', 'solver ran out of time'),
      'no_free_cell' => t('لا خانة حرة', 'no free cell'),
      _ => rule.replaceAll('_', ' '),
    };

/// "Blocked by: instructor busy + rooms taken" — the smallest set of rules that together block every option.
String coreText(List<String> core) {
  if (core.isEmpty) return '';
  if (core.length == 1 && core.first == 'time_limit') return t('كانت هناك أوقات حرة — انتهى وقت الحل قبل وضعها؛ ولّد مرة أخرى', 'Free times existed — the solver ran out of time; generate again');
  return '${t('يمنعها معاً', 'Blocked by')}: ${core.map(ruleShort).join(' + ')}';
}

/// One line per option of unscheduled[].explain: "Sunday · P1: instructor busy (Physics II)".
class ExplainRows extends StatelessWidget {
  const ExplainRows({super.key, required this.rows, this.courseNames = const {}, this.periodLabel, this.max = 8});
  final List<Map<String, dynamic>> rows;
  final Map<int, String> courseNames;
  final String Function(int periodId)? periodLabel;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = dayLabels();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final x in rows.take(max))
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(
            '${labels['${x['day']}'] ?? x['day']} · ${[for (final p in (x['period_ids'] as List? ?? const [])) periodLabel?.call(asInt(p)) ?? 'P$p'].join('+')}: '
            '${[for (final r in (x['rules'] as List? ?? const [])) ruleShort('$r')].join('، ')}'
            '${_blockers(x)}',
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
        ),
      if (rows.length > max) Text(t('+${rows.length - max} وقتاً آخر', '+${rows.length - max} more times'), style: AppType.meta(context).copyWith(color: c.textLight)),
    ]);
  }

  String _blockers(Map<String, dynamic> x) {
    final names = [
      for (final b in asMapList(x['blocked_by']))
        if (b['course_id'] != null) courseNames[asInt(b['course_id'])] ?? '#${b['course_id']}' else if (b['external'] == true) t('جدول آخر', 'another timetable'),
    ];
    return names.isEmpty ? '' : ' (${names.toSet().take(2).join('، ')})';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Quality report
// ═════════════════════════════════════════════════════════════════════════════

/// Fairness and quality of a timetable, from its slots alone. Score 0–100:
///   40 · workload balance (1 − coefficient of variation of periods per instructor / TA, clipped)
///   30 · compactness (1 − idle periods between a person's first and last session of a day ÷ taught periods)
///   30 · spread (1 − repeats of a course group on one day ÷ sessions)
/// Room use (busy room-cells ÷ available exclusive room-cells) is reported, not scored: both 30 % and 95 % can be right.
class QualityReport {
  const QualityReport({required this.score, required this.balance, required this.compactness, required this.spread, required this.utilizationPct, required this.workload, required this.idle, required this.repeats, required this.sessions});
  final int score;
  final double balance, compactness, spread; // 0–1
  final int utilizationPct;
  final Map<int, int> workload; // person → periods a week (instructors and TAs)
  final int idle, repeats, sessions;

  /// [periods] with id · order; [days] the teaching days; [rooms] active rooms ({id, exclusive}).
  factory QualityReport.of(List<Map<String, dynamic>> slots, List<Map<String, dynamic>> periods, {List<String> days = const [], List<Map<String, dynamic>> rooms = const []}) {
    final order = <int, int>{};
    final sorted = [...periods]..sort((a, b) => asInt(a['order']).compareTo(asInt(b['order'])));
    for (final (i, p) in sorted.indexed) {
      order[asInt(p['id'])] = i;
    }
    final load = <int, int>{};
    final perDay = <(int, String), Set<int>>{}; // (person, day) → period indexes
    final groupDay = <(int, String, int?, String), int>{}; // (course, kind, group, day) → blocks
    final blocks = <String>{};
    final roomCells = <(int, String, int)>{};
    for (final s in slots) {
      final pi = order[asInt(s['period_id'])];
      for (final k in const ['teacher_id', 'assistant_id']) {
        if (s[k] == null) continue;
        final u = asInt(s[k]);
        load[u] = (load[u] ?? 0) + 1;
        if (pi != null) (perDay[(u, '${s['day']}')] ??= {}).add(pi);
      }
      if (s['room_id'] != null) roomCells.add((asInt(s['room_id']), '${s['day']}', asInt(s['period_id'])));
      final key = '${s['block_id'] ?? 'slot-${s['id']}'}|${s['course_id']}';
      if (blocks.add(key)) {
        final g = (asInt(s['course_id']), '${s['kind'] ?? 'lecture'}', s['group_no'] == null ? null : asInt(s['group_no']), '${s['day']}');
        groupDay[g] = (groupDay[g] ?? 0) + 1;
      }
    }
    final sessions = blocks.length;
    // balance
    double balance = 1;
    if (load.length > 1) {
      final mean = load.values.fold<int>(0, (a, b) => a + b) / load.length;
      final varc = load.values.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) / load.length;
      final cv = mean == 0 ? 0 : (varc <= 0 ? 0 : _sqrt(varc) / mean);
      balance = (1 - cv).clamp(0, 1).toDouble();
    }
    // idle periods between first and last of a day
    var idle = 0, taught = 0;
    for (final set in perDay.values) {
      taught += set.length;
      if (set.length < 2) continue;
      final lo = set.reduce((a, b) => a < b ? a : b), hi = set.reduce((a, b) => a > b ? a : b);
      idle += (hi - lo + 1) - set.length;
    }
    final compactness = taught == 0 ? 1.0 : (1 - idle / taught).clamp(0, 1).toDouble();
    // same-day repeats of one course group
    final repeats = groupDay.values.fold<int>(0, (a, n) => a + (n > 1 ? n - 1 : 0));
    final spread = sessions == 0 ? 1.0 : (1 - repeats / sessions).clamp(0, 1).toDouble();
    final exclusive = rooms.where((r) => r['exclusive'] != false && r['is_active'] != false).length;
    final cells = days.length * periods.length * exclusive;
    final util = cells == 0 ? 0 : (100 * roomCells.length / cells).round();
    final score = sessions == 0 ? 0 : (40 * balance + 30 * compactness + 30 * spread).round().clamp(0, 100);
    return QualityReport(score: score, balance: balance, compactness: compactness, spread: spread, utilizationPct: util, workload: load, idle: idle, repeats: repeats, sessions: sessions);
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    var x = v;
    for (var i = 0; i < 40; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }

  /// The busiest people first: (person, periods).
  List<(int, int)> get topWorkload => (workload.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1)));
}

String qualityLabel(int score) => score >= 85 ? t('ممتاز', 'Excellent') : score >= 70 ? t('جيد', 'Good') : score >= 50 ? t('مقبول', 'Fair') : t('ضعيف', 'Poor');

class QualityCard extends StatelessWidget {
  const QualityCard({super.key, required this.report, this.people = const {}, this.relaxed = 0, this.broken = 0, this.solver});
  final QualityReport report;
  final Map<int, String> people;
  final int relaxed, broken; // preferences relaxed · rules broken on purpose (from result)
  final Map<String, dynamic>? solver; // result.solver (status, wall_s, deterministic)

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final col = r.score >= 70 ? c.success : (r.score >= 50 ? c.warning : c.danger);
    String pct(double v) => '${(100 * v).round()}%';
    final top = r.topWorkload.take(5).toList();
    final maxLoad = top.isEmpty ? 1 : top.first.$2;
    return RowCard(
      accent: col,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.14), shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
            child: Text('${r.score}', style: AppType.section(context).copyWith(color: col)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('جودة الجدول', 'Timetable quality')} · ${qualityLabel(r.score)}', style: AppType.bodyStrong(context)),
              Text(
                t('توازن العبء ${pct(r.balance)} · تماسك الأيام ${pct(r.compactness)} · توزيع المقررات ${pct(r.spread)} · استغلال القاعات ${r.utilizationPct}٪',
                    'Workload balance ${pct(r.balance)} · compact days ${pct(r.compactness)} · course spread ${pct(r.spread)} · room use ${r.utilizationPct}%'),
                style: AppType.meta(context).copyWith(color: c.textMedium),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: 10, runSpacing: 4, children: [
            for (final w in <Widget>[
          Text(t('${r.sessions} حصة', '${r.sessions} sessions'), style: AppType.meta(context).copyWith(color: c.textMedium)),
          Text(t('${r.idle} فترة فراغ', '${r.idle} idle period(s)'), style: AppType.meta(context).copyWith(color: r.idle > 0 ? c.warning : c.textMedium)),
          Text(t('${r.repeats} تكرار في اليوم نفسه', '${r.repeats} same-day repeat(s)'), style: AppType.meta(context).copyWith(color: r.repeats > 0 ? c.warning : c.textMedium)),
          if (relaxed > 0) Text(t('$relaxed تفضيل غير مُلبّى', '$relaxed preference(s) relaxed'), style: AppType.meta(context).copyWith(color: c.warning)),
          if (broken > 0) Text(t('$broken قاعدة كُسرت باقتراح', '$broken rule(s) broken as proposals'), style: AppType.meta(context).copyWith(color: c.warning)),
          if (solver != null && solver!['status'] != null)
            Text(
              '${solver!['status'] == 'OPTIMAL' ? t('حل أمثل', 'Optimal') : t('أفضل حل في الوقت', 'Best within the time')} · ${solver!['wall_s'] ?? '?'} ${t('ث', 's')}'
              '${solver!['deterministic'] == true ? ' · ${t('قابل للتكرار', 'reproducible')}' : ''}',
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
            ])
              ConstrainedBox(constraints: BoxConstraints(maxWidth: wrapWidth(context)), child: w),
        ]),
        if (top.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('العبء الأسبوعي (فترات)', 'Weekly load (periods)'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
          for (final (uid, n) in top)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(children: [
                SizedBox(width: 120, child: Text(people[uid] ?? '#$uid', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: context.colors.textDark))),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    child: LinearProgressIndicator(value: n / maxLoad, minHeight: 8, color: c.primary, backgroundColor: c.primary.withValues(alpha: 0.12)),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                SizedBox(width: 24, child: Text('$n', textAlign: TextAlign.end, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark))),
              ]),
            ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Why here?
// ═════════════════════════════════════════════════════════════════════════════

class WhyHere {
  const WhyHere({required this.found, required this.options, required this.free, required this.blockedBy, required this.alternatives, required this.here, this.brokenRules = const []});
  final bool found;
  final int options, free;
  final Map<String, int> blockedBy; // rule → how many other times it blocks
  final List<Map<String, dynamic>> alternatives; // free {day, period_ids}
  final Map<String, dynamic> here; // teacher_prefers · teacher_avoids · teacher_unavailable · org_avoids · students · room_capacity · room_is_smallest_fit · locked
  final List<Map<String, dynamic>> brokenRules;

  factory WhyHere.of(Map<String, dynamic> m) => WhyHere(
        found: m['found'] != false && m['known_load'] != false,
        options: asInt(m['options']),
        free: asInt(m['free']),
        blockedBy: {for (final e in asMap(m['blocked_by']).entries) e.key: asInt(e.value)},
        alternatives: asMapList(m['alternatives']),
        here: asMap(m['here']),
        brokenRules: asMapList(m['broken_rules']),
      );

  /// The sentences shown to the admin, most useful first.
  List<String> get facts {
    final out = <String>[];
    if (here['teacher_prefers'] == true) out.add(t('وقت يفضّله المدرس', 'A time the instructor prefers'));
    if (here['teacher_avoids'] == true) out.add(t('وقت يتجنّبه المدرس — لم يتوفر أفضل', 'A time the instructor avoids — nothing better was free'));
    if (here['teacher_unavailable'] == true) out.add(t('المدرس غير متاح هنا (قاعدة كُسرت أو تجاوز)', 'The instructor is unavailable here (a broken rule or an override)'));
    if (here['org_avoids'] == true) out.add(t('وقت تتجنّبه المؤسسة', 'A time the organization avoids'));
    if (here['room_capacity'] != null) {
      out.add(here['room_is_smallest_fit'] == true
          ? t('أصغر قاعة تكفي ${here['students']} طالباً (سعة ${here['room_capacity']})', 'The smallest room that fits ${here['students']} students (capacity ${here['room_capacity']})')
          : t('قاعة بسعة ${here['room_capacity']} لـ ${here['students']} طالباً', 'A room for ${here['room_capacity']} with ${here['students']} students'));
    }
    if (here['locked'] == true) out.add(t('مثبتة يدوياً — المولّد لا يحركها', 'Pinned by hand — the generator never moves it'));
    out.add(free == 0
        ? t('لا وقت آخر متاح لهذه الحصة الآن', 'No other time is free for this session right now')
        : t('$free من $options وقتاً آخر متاح أيضاً', '$free of $options other times are also free'));
    return out;
  }
}

class WhyHereSection extends StatelessWidget {
  const WhyHereSection({super.key, required this.why, this.periodLabel});
  final WhyHere why;
  final String Function(int periodId)? periodLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = dayLabels();
    if (!why.found) return Text(t('لا يمكن تفسير هذه الحصة: عبء المقرر غير معروف.', 'Cannot explain this session: its course load is unknown.'), style: AppType.label(context).copyWith(color: c.textMedium));
    final blocked = why.blockedBy.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final f in why.facts)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline_rounded, size: AppIconSize.xs, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(f, style: AppType.label(context).copyWith(color: context.colors.textDark))),
          ]),
        ),
      if (blocked.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text('${t('الأوقات الأخرى يمنعها', 'Other times are blocked by')}: ${blocked.take(4).map((e) => '${e.value} × ${ruleShort(e.key)}').join('، ')}', style: AppType.meta(context).copyWith(color: c.textMedium)),
        ),
      if (why.alternatives.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(
            '${t('بدائل حرة', 'Free alternatives')}: ${why.alternatives.take(4).map((a) => '${labels['${a['day']}'] ?? a['day']} ${[for (final p in (a['period_ids'] as List? ?? const [])) periodLabel?.call(asInt(p)) ?? 'P$p'].join('+')}').join('، ')}',
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
        ),
      for (final b in why.brokenRules) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text('${t('قاعدة كُسرت هنا', 'Rule broken here')}: ${ruleShort('${b['rule']}')}', style: AppType.meta(context).copyWith(color: c.warning))),
    ]);
  }
}

/// Keeps `orgDays` referenced for callers that import this file for day order.
List<String> get insightDays => orgDays;
