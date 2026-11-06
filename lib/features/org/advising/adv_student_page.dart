// lib/features/org/advising/adv_student_page.dart — the student 360 (docs/advising/PHASE4.md "Student 360"): a header
// (name, program, level, standing, advisors, the risk score with every reason) and five sections — Overview (the
// numbers, the CGPA trend, last contact) · Academic (GPA by term, each term's courses from the registrar's record) ·
// Flags (adv_flags.dart) · Notes (adv_notes.dart, with the offline drafts of adv_draft_store.dart) · Timeline. Phones
// switch sections with chips; wide screens show Overview + Academic in one column and Flags · Notes · Timeline in the
// other. Directors also get "Change advisor" (the Phase 3 student sheet).
//
//   AdvStudentHeader    AdvOverviewSection    AdvAcademicSection    AdvTimelinePane    AdvStudentView (plain values)
//   AdvStudentPage      loads the profile, flags, notes, timeline and categories; every write goes through AdvApi
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_registrar.dart' show regStatusText, standingText;
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_case_parts.dart';
import 'adv_draft_store.dart';
import 'adv_flags.dart';
import 'adv_models.dart';
import 'adv_notes.dart';
import 'adv_parts.dart';
import 'adv_students_page.dart' show showAdvStudentSheet;

/// The 360's sections, in order.
const advCaseSections = ['overview', 'academic', 'flags', 'notes', 'timeline'];

/// The sections of the wide layout's second column.
const advCasePanes = ['flags', 'notes', 'timeline'];

String advCaseSectionLabel(String s) => switch (s) {
      'academic' => t('الأكاديمي', 'Academic'),
      'flags' => t('التنبيهات', 'Flags'),
      'notes' => t('الملاحظات', 'Notes'),
      'timeline' => t('السجل الزمني', 'Timeline'),
      _ => t('نظرة عامة', 'Overview'),
    };

IconData advCaseSectionIcon(String s) => switch (s) {
      'academic' => Icons.school_outlined,
      'flags' => Icons.flag_outlined,
      'notes' => Icons.sticky_note_2_outlined,
      'timeline' => Icons.timeline_rounded,
      _ => Icons.dashboard_outlined,
    };

String _standing(String? s) {
  if (s == null) return '';
  final l = standingText(s);
  return l.isEmpty ? s : l;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Header
// ═════════════════════════════════════════════════════════════════════════════

class AdvStudentHeader extends StatelessWidget {
  const AdvStudentHeader({super.key, required this.profile, this.onChangeAdvisor});
  final AdvCaseProfile profile;

  /// Directors: opens the student's advisors sheet (null: not offered).
  final VoidCallback? onChangeAdvisor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final standing = _standing(p.standing);
    final identity = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppAvatar(name: p.shown, size: AppTouch.primary),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(p.shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
          if (p.subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(p.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
          if (standing.isNotEmpty || p.joinedAt != null) ...[
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              if (standing.isNotEmpty)
                AppBadgePill(standing, color: p.standing == 'probation' ? c.danger : (p.standing == 'honours' ? c.success : c.primary), icon: Icons.workspace_premium_outlined),
              if (p.joinedAt != null) AppBadgePill(t('انضم ${advDate(p.joinedAt)}', 'Joined ${advDate(p.joinedAt)}'), color: c.textMedium, icon: Icons.event_available_rounded),
            ]),
          ],
        ]),
      ),
    ]);
    final primary = p.primary;
    final others = [for (final a in p.advisors) if (a.type != 'primary') a];
    final advisors = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        ExcludeSemantics(child: Icon(primary == null ? Icons.person_search_rounded : Icons.co_present_rounded, size: AppIconSize.md, color: primary == null ? appInk(context, c.warning) : c.primary)),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(primary == null ? t('لا مرشد أكاديمي بعد', 'No academic advisor yet') : primary.shown,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
            Text(
              primary == null
                  ? t('يسنده مدير الإرشاد', 'The advising director assigns one')
                  : [advAdvisorTypeLabel('primary'), if (primary.since != null) t('منذ ${advDate(primary.since)}', 'since ${advDate(primary.since)}'), if (primary.locked) t('مقفل', 'locked')].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ]),
        ),
      ]),
      for (final o in others)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppIconSize.md + AppSpace.xs, top: AppSpace.xxs),
          child: Text('${advAdvisorTypeLabel(o.type)}: ${o.shown}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ),
      if (onChangeAdvisor != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: onChangeAdvisor,
            icon: const Icon(Icons.swap_horiz_rounded, size: AppIconSize.md),
            label: Text(primary == null ? t('إسناد مرشد', 'Assign an advisor') : t('تغيير المرشد', 'Change advisor')),
          ),
        ),
    ]);
    final s = p.stats;
    final risk = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('درجة الخطر', 'Risk score'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xxs),
      AdvRiskMeter(score: s.riskScore, large: true),
      if (s.riskReasons.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        for (final r in s.riskReasons)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs + 2),
                child: ExcludeSemantics(child: Icon(Icons.circle, size: AppSpace.xs - 2, color: advRiskColor(context, s.riskScore))),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(advRiskReasonText(r, flags: s.openFlags), style: AppType.body(context).copyWith(color: c.textDark))),
            ]),
          ),
      ] else ...[
        const SizedBox(height: AppSpace.xxs),
        Text(t('لا عوامل خطر الآن.', 'No risk factors right now.'), style: AppType.meta(context)),
      ],
    ]);
    return AppCard(
      padding: AppSpace.card,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 720 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
        if (!wide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            identity,
            Divider(height: AppSpace.lg, color: c.divider),
            risk,
            Divider(height: AppSpace.lg, color: c.divider),
            advisors,
          ]);
        }
        // the risk column carries the divider on its start edge (no IntrinsicHeight: the bars inside measure
        // themselves with a LayoutBuilder)
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [identity, const SizedBox(height: AppSpace.md), advisors])),
          const SizedBox(width: AppSpace.md),
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.md),
              decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: c.divider))),
              child: risk,
            ),
          ),
        ]);
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Overview
// ═════════════════════════════════════════════════════════════════════════════

/// Lays [children] out in [cols] equal columns (2 on a phone, 3 when there is room).
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 480 ? 3 : 2;
        final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class AdvOverviewSection extends StatelessWidget {
  const AdvOverviewSection({super.key, required this.profile, this.now});
  final AdvCaseProfile profile;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final s = p.stats;
    final trend = [for (final g in p.gpaTrend) if (g.cgpa != null) g.cgpa!];
    final absence = s.absenceMax;
    final flags = s.openFlags.total;
    final days = advDaysSince(s.lastContactAt, now: now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvSectionTitle(advCaseSectionLabel('overview'), first: true),
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _TileGrid(children: [
            AdvMiniStat(label: t('المعدل التراكمي', 'CGPA'), value: advGpa(s.cgpa), tone: s.cgpa != null && s.cgpa! < 2 ? c.danger : null),
            AdvMiniStat(label: t('معدل آخر فصل', 'Last term GPA'), value: advGpa(s.lastTermGpa), tone: s.lastTermGpa != null && s.cgpa != null && s.lastTermGpa! <= s.cgpa! - 0.3 ? c.warning : null),
            AdvMiniStat(label: t('أعلى غياب', 'Highest absence'), value: advPct(absence), tone: absence == null ? null : (absence >= 25 ? c.danger : (absence >= 15 ? c.warning : null))),
            AdvMiniStat(label: t('مقررات راسبة', 'Failed courses'), value: '${s.failedCount}', tone: s.failedCount > 0 ? c.danger : null),
            AdvMiniStat(label: t('تنبيهات مفتوحة', 'Open flags'), value: '$flags', tone: s.openFlags.urgent > 0 ? c.danger : (flags > 0 ? c.warning : null)),
            AdvMiniStat(label: t('لقاءات هذا الفصل', 'Meetings this term'), value: '${p.meetingsTerm}'),
          ]),
          if (trend.length >= 2) ...[
            const SizedBox(height: AppSpace.md),
            Row(children: [
              Expanded(child: Text(t('اتجاه المعدل التراكمي', 'CGPA trend'), style: AppType.meta(context))),
              Text('${advGpa(trend.first)} → ${advGpa(trend.last)}', textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: AppSpace.xxs),
            AppSparkline(trend, color: trend.last < trend.first ? c.warning : c.primary, label: t('اتجاه المعدل التراكمي', 'CGPA trend')),
          ],
          const SizedBox(height: AppSpace.sm),
          AppInfoRow(Icons.forum_outlined, advLastContactText(s.lastContactAt, now: now)),
          if (days == null || days > 30)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(t('يُستحسن التواصل مع الطالب قريباً.', 'Reaching out to the student soon is a good idea.'), style: AppType.meta(context).copyWith(color: appInk(context, c.warning))),
            ),
          AppInfoRow(Icons.sticky_note_2_outlined, countText(p.counts.notes, ar1: 'ملاحظة واحدة', ar2: 'ملاحظتان', arFew: '${p.counts.notes} ملاحظات', arMany: '${p.counts.notes} ملاحظة', en1: '1 note', en: '${p.counts.notes} notes')),
          if (p.counts.handovers > 0)
            AppInfoRow(Icons.handshake_outlined, countText(p.counts.handovers, ar1: 'ملف تسليم واحد', ar2: 'ملفا تسليم', arFew: '${p.counts.handovers} ملفات تسليم', arMany: '${p.counts.handovers} ملف تسليم', en1: '1 handover', en: '${p.counts.handovers} handovers')),
          if (p.counts.restricted > 0)
            AppInfoRow(
              Icons.lock_outline_rounded,
              countText(p.counts.restricted,
                  ar1: 'عنصر واحد خاص أو حساس لا يظهر لك', ar2: 'عنصران خاصان أو حساسان لا يظهران لك', arFew: '${p.counts.restricted} عناصر خاصة أو حساسة لا تظهر لك', arMany: '${p.counts.restricted} عنصراً خاصاً أو حساساً لا يظهر لك',
                  en1: '1 private or sensitive item is hidden from you', en: '${p.counts.restricted} private or sensitive items are hidden from you'),
            ),
        ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Academic
// ═════════════════════════════════════════════════════════════════════════════

class AdvAcademicSection extends StatelessWidget {
  const AdvAcademicSection({super.key, required this.profile});
  final AdvCaseProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final a = p.academic;
    final points = [for (final g in p.gpaTrend) if (g.termGpa != null || g.cgpa != null) g];
    final children = <Widget>[AdvSectionTitle(t('السجل الأكاديمي', 'Academic record'))];
    if (a == null && points.isEmpty) {
      children.add(AppCard(
        padding: AppSpace.card,
        child: Row(children: [
          ExcludeSemantics(child: Icon(Icons.menu_book_outlined, color: c.textMedium, size: AppIconSize.lg)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              t('لا سجل أكاديمي في نظام التسجيل لهذا الطالب — قد لا تستخدم المؤسسة نظام التسجيل.',
                  'This student has no record in the registrar — the organization may not use the registrar.'),
              style: AppType.body(context),
            ),
          ),
        ]),
      ));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
    }
    if (points.isNotEmpty) {
      children.add(AppCard(
        padding: AppSpace.card,
        child: AppBarChart(
          title: t('المعدل حسب الفصل', 'GPA by term'),
          labels: [for (final g in points) g.label.isEmpty ? '#${g.termId}' : g.label],
          series: [
            AppChartSeries(t('معدل الفصل', 'Term GPA'), [for (final g in points) g.termGpa ?? 0]),
            AppChartSeries(t('التراكمي', 'CGPA'), [for (final g in points) g.cgpa ?? 0]),
          ],
          height: 180,
          format: (v) => v.toStringAsFixed(1),
        ),
      ));
    }
    if (a != null) {
      children.add(const SizedBox(height: AppSpace.sm));
      children.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (a.cgpa != null) AppBadgePill(t('التراكمي ${advGpa(a.cgpa)}', 'CGPA ${advGpa(a.cgpa)}'), color: a.cgpa! < 2 ? c.danger : c.primary, icon: Icons.school_outlined),
        if (a.earned != null) AppBadgePill(t('الساعات المكتسبة ${_num(a.earned!)}', 'Earned credits ${_num(a.earned!)}'), color: c.textMedium, icon: Icons.check_circle_outline_rounded),
        if (_standing(a.standing).isNotEmpty) AppBadgePill(_standing(a.standing), color: a.standing == 'probation' ? c.danger : c.success, icon: Icons.workspace_premium_outlined),
      ]));
      final terms = a.terms.reversed.toList();
      if (terms.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Text(t('لا مقررات مسجلة بعد.', 'No courses registered yet.'), style: AppType.body(context)),
        ));
      }
      for (var i = 0; i < terms.length; i++) {
        children.add(Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: _TermBlock(term: terms[i], open: i == 0)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

/// One registrar term: its GPA and credits, the courses under it (folded except the latest).
class _TermBlock extends StatefulWidget {
  const _TermBlock({required this.term, required this.open});
  final AdvAcademicTerm term;
  final bool open;

  @override
  State<_TermBlock> createState() => _TermBlockState();
}

class _TermBlockState extends State<_TermBlock> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tm = widget.term;
    final credits = AdvAcademicSection._num(tm.credits);
    final meta = [
      if (tm.termGpa != null) t('المعدل ${advGpa(tm.termGpa)}', 'GPA ${advGpa(tm.termGpa)}'),
      t('$credits ساعة', '$credits credits'),
      countText(tm.courses.length, ar1: 'مقرر واحد', ar2: 'مقرران', arFew: '${tm.courses.length} مقررات', arMany: '${tm.courses.length} مقرراً', en1: '1 course', en: '${tm.courses.length} courses'),
    ].join(' · ');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tm.label.isEmpty ? '#${tm.id}' : tm.label, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                      Text(meta, style: AppType.meta(context)),
                    ]),
                  ),
                  ExcludeSemantics(child: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.textMedium)),
                ]),
              ),
            ),
          ),
        ),
        if (_open)
          for (final course in tm.courses) ...[
            Divider(height: AppBorder.hairline, color: c.divider),
            _CourseRow(course: course),
          ],
      ]),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course});
  final AdvCourseRow course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = course;
    final abs = x.absencePct;
    final status = x.status == 'completed' || x.status == 'registered' || x.status.isEmpty ? null : regStatusText(x.status);
    final meta = [
      if (x.credits != null) t('${AdvAcademicSection._num(x.credits!)} ساعة', '${AdvAcademicSection._num(x.credits!)} cr'),
      if (abs != null && abs > 0) t('غياب ${advPct(abs)}', 'absence ${advPct(abs)}'),
      if (x.attempt > 1) t('محاولة ${x.attempt}', 'attempt ${x.attempt}'),
      ?status,
    ].join(' · ');
    final Widget grade = x.letter != null
        ? AppBadgePill(x.letter!, color: x.failed ? c.danger : c.primary)
        : (x.denied ? AppBadgePill(t('حرمان', 'Denied'), color: c.danger, icon: Icons.block_rounded) : AppBadgePill(t('جارٍ', 'In progress'), color: c.textMedium));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                if (x.code != null) TextSpan(text: '${x.code}  ', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
                TextSpan(text: x.name.isEmpty ? '—' : x.name),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.row(context),
            ),
            if (meta.isNotEmpty)
              Text(meta, style: AppType.meta(context).copyWith(color: abs != null && abs >= 25 ? appInk(context, c.danger) : (abs != null && abs >= 15 ? appInk(context, c.warning) : null))),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        grade,
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Timeline
// ═════════════════════════════════════════════════════════════════════════════

IconData advTimelineIcon(String kind) => switch (kind) {
      'assigned' => Icons.person_add_alt_rounded,
      'unassigned' => Icons.person_remove_alt_1_rounded,
      'handover' => Icons.handshake_outlined,
      'flag_opened' => Icons.flag_rounded,
      'flag_status' => Icons.published_with_changes_rounded,
      'note' => Icons.sticky_note_2_outlined,
      'contact' => Icons.forum_outlined,
      _ => Icons.circle_outlined,
    };

Color advTimelineColor(BuildContext context, AdvTimelineEntry e) {
  final c = context.colors;
  return switch (e.kind) {
    'flag_opened' => e.data['priority'] == 'urgent' ? c.danger : c.warning,
    'flag_status' => c.warning,
    'contact' => c.success,
    'assigned' || 'handover' => c.primary,
    _ => c.textMedium,
  };
}

class AdvTimelinePane extends StatelessWidget {
  const AdvTimelinePane({super.key, required this.load, this.entries, this.hasMore = false, this.loadingMore = false, this.errorText, this.onRetry, this.onMore});
  final AdvLoad load;
  final List<AdvTimelineEntry>? entries;
  final bool hasMore, loadingMore;
  final String? errorText;
  final VoidCallback? onRetry, onMore;

  @override
  Widget build(BuildContext context) {
    final list = entries;
    if (load != AdvLoad.ready || list == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 3);
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Column(children: [
          ExcludeSemantics(child: Icon(Icons.timeline_rounded, size: AppIconSize.xl, color: context.colors.textLight)),
          const SizedBox(height: AppSpace.xs),
          Text(t('لا نشاط بعد', 'No activity yet'), textAlign: TextAlign.center, style: AppType.body(context)),
        ]),
      );
    }
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < list.length; i++)
          AdvRailRow(
            last: i == list.length - 1 && !hasMore,
            icon: advTimelineIcon(list[i].kind),
            color: advTimelineColor(context, list[i]),
            child: MergeSemantics(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(list[i].text, style: AppType.row(context))),
                Text([if (list[i].at != null) AppTime.dateTime(list[i].at!), ?list[i].actor].join(' · '), style: AppType.meta(context)),
              ]),
            ),
          ),
        if (hasMore && onMore != null)
          Align(
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
              onPressed: loadingMore ? null : onMore,
              icon: loadingMore ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.expand_more_rounded),
              label: Text(t('نشاط أقدم', 'Older activity')),
            ),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The 360 (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class AdvStudentView extends StatelessWidget {
  const AdvStudentView({
    super.key,
    required this.load,
    this.profile,
    this.errorText,
    this.section = 'overview',
    this.flags = const SizedBox.shrink(),
    this.notes = const SizedBox.shrink(),
    this.timeline = const SizedBox.shrink(),
    this.now,
    this.onRetry,
    this.onSection,
    this.onChangeAdvisor,
  });

  final AdvLoad load;
  final AdvCaseProfile? profile;
  final String? errorText;

  /// The open section (phones) / the second column's pane (wide: Flags when Overview or Academic is chosen).
  final String section;

  /// The panes, built by the caller from AdvFlagsPane · AdvNotesPane · AdvTimelinePane.
  final Widget flags, notes, timeline;
  final DateTime? now;
  final VoidCallback? onRetry, onChangeAdvisor;
  final ValueChanged<String>? onSection;

  /// The width from which the 360 shows two columns.
  static const double wideFrom = 1000;

  Widget _pane(String s) => switch (s) {
        'notes' => notes,
        'timeline' => timeline,
        _ => flags,
      };

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (load != AdvLoad.ready || p == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    }
    return LayoutBuilder(builder: (context, box) {
      final header = AdvStudentHeader(profile: p, onChangeAdvisor: onChangeAdvisor);
      final pad = EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl);
      if (box.maxWidth >= wideFrom) {
        final pane = advCasePanes.contains(section) ? section : 'flags';
        return ListView(padding: pad, children: [
          header,
          const SizedBox(height: AppSpace.md),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AdvOverviewSection(profile: p, now: now),
                AdvAcademicSection(profile: p),
              ]),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              flex: 6,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OrgSegmented<String>(
                  value: pane,
                  options: [for (final s in advCasePanes) (s, _paneLabel(s, p))],
                  onChanged: (s) => onSection?.call(s),
                ),
                const SizedBox(height: AppSpace.sm),
                _pane(pane),
              ]),
            ),
          ]),
        ]);
      }
      final index = advCaseSections.indexOf(section).clamp(0, advCaseSections.length - 1);
      final current = advCaseSections[index];
      return ListView(padding: EdgeInsets.only(bottom: pad.bottom), children: [
        Padding(padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 0), child: header),
        const SizedBox(height: AppSpace.sm),
        OrgSectionChips(
          items: [for (final s in advCaseSections) (_paneLabel(s, p), advCaseSectionIcon(s))],
          index: index,
          onChanged: (i) => onSection?.call(advCaseSections[i]),
        ),
        const SizedBox(height: AppSpace.sm),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad.left),
          child: switch (current) {
            'academic' => AdvAcademicSection(profile: p),
            'flags' || 'notes' || 'timeline' => _pane(current),
            _ => AdvOverviewSection(profile: p, now: now),
          },
        ),
      ]);
    });
  }

  /// "Flags · 2" (open flags) · "Notes · 14" · the others plain.
  static String _paneLabel(String s, AdvCaseProfile p) => switch (s) {
        'flags' when p.counts.flagsOpen > 0 => '${advCaseSectionLabel(s)} · ${p.counts.flagsOpen}',
        'notes' when p.counts.notes > 0 => '${advCaseSectionLabel(s)} · ${p.counts.notes}',
        _ => advCaseSectionLabel(s),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvStudentPage extends StatelessWidget {
  const AdvStudentPage({super.key, required this.orgId, required this.memberId, this.name});
  final int orgId, memberId;

  /// Shown as the title until the profile loads.
  final String? name;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: name ?? t('الطالب', 'Student'),
        subtitle: t('ملف الإرشاد', 'Advising record'),
        helpPageId: 'org.advising',
        maxWidth: 1280,
        child: _AdvStudentBody(orgId: orgId, memberId: memberId),
      );
}

class _AdvStudentBody extends StatefulWidget {
  const _AdvStudentBody({required this.orgId, required this.memberId});
  final int orgId, memberId;

  @override
  State<_AdvStudentBody> createState() => _AdvStudentBodyState();
}

class _AdvStudentBodyState extends State<_AdvStudentBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  final _store = AdvDraftStore.instance;
  OrgPageRefresh? _refresh;
  StreamSubscription<LiveEvent>? _live;

  AdvCaseProfile? _profile;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  String _section = 'overview';
  List<AdvCategory> _categories = const [];

  String _flagView = 'open';
  AdvPage<AdvFlag>? _flags;
  AdvLoad _flagsLoad = AdvLoad.loading;
  String? _flagsError;

  final List<AdvNote> _notes = [];
  AdvLoad _notesLoad = AdvLoad.loading;
  String? _notesError;
  int _notesPage = 1, _notesTotal = 0, _notesRestricted = 0;
  bool _notesMore = false, _notesLoadingMore = false;

  List<AdvTimelineEntry> _timeline = const [];
  String? _next;
  AdvLoad _tlLoad = AdvLoad.loading;
  String? _tlError;
  bool _tlLoadingMore = false;

  final _body = TextEditingController();
  AdvNoteDraft _draft = const AdvNoteDraft();
  bool _draftSaved = false, _sending = false;
  String? _composeError;
  List<AdvQueuedNote> _queued = const [];
  Timer? _saveTimer;
  bool _online = AppConnectivity.instance.isOnline;

  int get _org => widget.orgId;
  int get _member => widget.memberId;
  bool get _manage => _profile?.can.assign ?? false;

  int? get _me {
    try {
      return context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reloadAll);
    _live = LiveEvents.instance.listen({LiveEvents.connectivity}, (_) {
      if (!mounted) return;
      final online = AppConnectivity.instance.isOnline;
      setState(() => _online = online);
      if (online && _load != AdvLoad.ready) _reloadAll();
    });
    _store.changes.addListener(_onStoreChanged);
    _body.addListener(_onTyped);
    _restoreDraft();
    _readQueue();
    _reloadAll();
    _store.flush();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reloadAll);
    _live?.cancel();
    _store.changes.removeListener(_onStoreChanged);
    _saveTimer?.cancel();
    if (_body.text.trim().isNotEmpty) _store.saveDraft(_org, _member, _draft.copyWith(body: _body.text));
    _body.dispose();
    super.dispose();
  }

  // ── loading ────────────────────────────────────────────────────────────────

  Future<void> _reloadAll() async {
    await Future.wait([_loadProfile(), _loadFlags(), _loadNotes(), _loadTimeline(), _loadCategories()]);
    if (mounted && _profile != null) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _loadProfile() async {
    final r = await orgCall(() => _api.profile(_member), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _profile = r.data as AdvCaseProfile;
        _load = AdvLoad.ready;
      } else if (_profile == null) {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
      }
    });
  }

  Future<void> _loadCategories() async {
    final r = await orgCall(() => _api.categories(), quiet: true);
    if (mounted && r.ok) setState(() => _categories = r.data as List<AdvCategory>);
  }

  Future<void> _loadFlags() async {
    final view = _flagView;
    final r = await orgCall(() => _api.flags(_member, status: view), quiet: true);
    if (!mounted || view != _flagView) return;
    setState(() {
      if (r.ok) {
        _flags = r.data as AdvPage<AdvFlag>;
        _flagsLoad = AdvLoad.ready;
      } else {
        _flags = null;
        _flagsLoad = advFailLoad(r);
        _flagsError = advErrorText(r.error!);
      }
    });
  }

  Future<void> _loadNotes({bool more = false}) async {
    final page = more ? _notesPage + 1 : 1;
    if (more) setState(() => _notesLoadingMore = true);
    final r = await orgCall(() => _api.notes(_member, page: page), quiet: true);
    if (!mounted) return;
    setState(() {
      _notesLoadingMore = false;
      if (r.ok) {
        final p = r.data as AdvPage<AdvNote>;
        if (!more) _notes.clear();
        _notes.addAll([for (final n in p.items) if (!_notes.any((x) => x.id == n.id)) n]);
        _notesPage = p.page;
        _notesTotal = p.total;
        _notesRestricted = p.restricted;
        _notesMore = p.page < p.pages;
        _notesLoad = AdvLoad.ready;
      } else if (!more) {
        _notesLoad = advFailLoad(r);
        _notesError = advErrorText(r.error!);
      } else {
        showAppNotice(advErrorText(r.error!), error: true);
      }
    });
    if (r.ok) _settleQueued();
  }

  /// A note written offline that is already in the list (its `client_id` came back with it) leaves the queue: the
  /// server had it before the connection dropped.
  Future<void> _settleQueued() async {
    final posted = {for (final n in _notes) if (n.clientId != null) n.clientId!};
    for (final q in _queued) {
      if (posted.contains(q.clientId)) await _store.discard(q);
    }
  }

  Future<void> _loadTimeline({bool more = false}) async {
    if (more) setState(() => _tlLoadingMore = true);
    final r = await orgCall(() => _api.timeline(_member, before: more ? _next : null), quiet: true);
    if (!mounted) return;
    setState(() {
      _tlLoadingMore = false;
      if (r.ok) {
        final p = r.data as AdvTimelinePage;
        _timeline = more ? [..._timeline, ...p.items] : p.items;
        _next = p.next;
        _tlLoad = AdvLoad.ready;
      } else if (!more) {
        _tlLoad = advFailLoad(r);
        _tlError = advErrorText(r.error!);
      } else {
        showAppNotice(advErrorText(r.error!), error: true);
      }
    });
  }

  /// After a write: the numbers, the score and the timeline move with it.
  void _afterWrite() {
    _loadProfile();
    _loadTimeline();
  }

  // ── the composer and the offline drafts ────────────────────────────────────

  Future<void> _restoreDraft() async {
    final d = await _store.draft(_org, _member);
    if (!mounted || d == null || _body.text.isNotEmpty) return;
    setState(() {
      _draft = d.copyWith(body: '');
      _draftSaved = true;
    });
    _body.text = d.body;
  }

  Future<void> _readQueue() async {
    final q = await _store.queued(_org, _member);
    if (!mounted) return;
    final before = _queued.where((x) => !x.failed).length;
    final now = q.where((x) => !x.failed).length;
    setState(() => _queued = q);
    // notes written offline were posted: show them
    if (now < before) {
      _loadNotes();
      _afterWrite();
    }
  }

  void _onStoreChanged() => _readQueue();

  void _onTyped() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final d = _draft.copyWith(body: _body.text);
    await _store.saveDraft(_org, _member, d);
    if (mounted && _draftSaved != d.worthKeeping) setState(() => _draftSaved = d.worthKeeping);
  }

  void _setDraft(AdvNoteDraft d) {
    setState(() {
      _draft = d;
      _composeError = null;
    });
    if (_body.text.trim().isNotEmpty) _saveDraft();
  }

  Future<void> _send() async {
    final d = _draft.copyWith(body: _body.text);
    final why = d.error();
    if (why != null) {
      setState(() => _composeError = why);
      return;
    }
    setState(() {
      _sending = true;
      _composeError = null;
    });
    _saveTimer?.cancel();
    final r = await _store.send(_org, _member, d);
    if (!mounted) return;
    setState(() {
      _sending = false;
      switch (r.state) {
        case AdvSendState.sent:
        case AdvSendState.queued:
          _draft = AdvNoteDraft(visibility: _draft.visibility, sensitive: false);
          _draftSaved = false;
          final made = r.note;
          if (made != null) {
            _notes.insert(0, made);
            _notesTotal++;
          }
        case AdvSendState.failed:
          _composeError = advErrorText(r.error!);
      }
    });
    if (r.state == AdvSendState.failed) return;
    _body.clear();
    _saveTimer?.cancel();
    if (r.state == AdvSendState.sent) {
      showAppNotice(t('أُضيفت الملاحظة', 'Note added'));
      _afterWrite();
    } else {
      showAppNotice(t('محفوظة على هذا الجهاز · تُرسل عند عودة الاتصال', 'Saved on this device · will send when online'));
      _readQueue();
    }
  }

  Future<void> _pickContactTime() async {
    final d = await pickAdvContactTime(context, _draft.contactAt);
    if (d != null) _setDraft(_draft.copyWith(contactAt: () => d));
  }

  Future<void> _reopenQueued(AdvQueuedNote q) async {
    final d = await _store.reopen(q);
    if (!mounted) return;
    setState(() {
      _draft = d.copyWith(body: '');
      _draftSaved = true;
    });
    _body.text = d.body;
  }

  // ── flags ──────────────────────────────────────────────────────────────────

  bool _canChange(AdvFlag f) {
    final can = _profile?.can ?? const AdvCaseCan();
    if (!f.closed) return can.flag;
    return _manage || (f.owner != null && f.owner!.userId == _me);
  }

  bool _canEdit(AdvFlag f) => _manage || (f.owner != null && f.owner!.userId == _me);

  Future<void> _addFlag() async {
    final f = await showAdvFlagSheet(context, _api, memberId: _member, categories: _categories);
    if (f == null || !mounted) return;
    _loadFlags();
    _afterWrite();
  }

  Future<void> _editFlag(AdvFlag f) async {
    final saved = await showAdvFlagSheet(context, _api, memberId: _member, categories: _categories, flag: f);
    if (saved == null || !mounted) return;
    _loadFlags();
    _afterWrite();
  }

  Future<void> _flagStatus(AdvFlag f) async {
    final saved = await showAdvFlagStatusSheet(context, _api, f, canReopen: _canChange(f), onStale: () {
      if (mounted) _loadFlags();
    });
    if (saved == null || !mounted) return;
    _loadFlags();
    _afterWrite();
  }

  // ── notes ──────────────────────────────────────────────────────────────────

  Future<void> _editNote(AdvNote n) async {
    final saved = await showAdvNoteEditSheet(context, _api, n, categories: _categories, canSensitive: _profile?.can.sensitive ?? false);
    if (saved == null || !mounted) return;
    setState(() {
      final i = _notes.indexWhere((x) => x.id == saved.id);
      if (i >= 0) _notes[i] = saved;
    });
    _afterWrite();
  }

  Future<void> _deleteNote(AdvNote n) async {
    final yes = await appConfirm(context, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف هذه الملاحظة؟', 'Delete this note?'));
    if (!yes || !mounted) return;
    final r = await orgCall(() => _api.deleteNote(n.id), ok: t('حُذفت الملاحظة', 'Note deleted'));
    if (!r.ok || !mounted) return;
    setState(() {
      _notes.removeWhere((x) => x.id == n.id);
      _notesTotal = _notesTotal > 0 ? _notesTotal - 1 : 0;
    });
    _afterWrite();
  }

  // ── advisor ────────────────────────────────────────────────────────────────

  Future<void> _changeAdvisor() async {
    final p = _profile;
    if (p == null) return;
    final pol = await orgCall(() => _api.policy(), quiet: true);
    if (!mounted) return;
    final multi = pol.ok && (pol.data as AdvPolicyBundle).effective.multi;
    final saved = await showAdvStudentSheet(context, _api, p.toStudent(), manage: true, multi: multi);
    if (saved != null && mounted) _afterWrite();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final can = p?.can ?? const AdvCaseCan();
    final composer = can.note
        ? AdvNoteComposer(
            body: _body,
            draft: _draft,
            categories: _categories,
            canSensitive: can.sensitive,
            offline: !_online,
            draftSaved: _draftSaved,
            queued: _queued,
            busy: _sending,
            error: _composeError,
            onVisibility: (v) => _setDraft(_draft.copyWith(visibility: v)),
            onSensitive: (v) => _setDraft(_draft.copyWith(sensitive: v)),
            onCategory: (id) => _setDraft(_draft.copyWith(categoryId: () => id)),
            onContact: (on) => _setDraft(_draft.copyWith(contactMode: () => on ? (_draft.contactMode ?? 'in_person') : null, contactAt: () => null)),
            onMode: (m) => _setDraft(_draft.copyWith(contactMode: () => m)),
            onPickContactDate: _pickContactTime,
            onSubmit: _sending ? null : _send,
            onDiscardQueued: (q) => _store.discard(q),
            onReopenQueued: _reopenQueued,
          )
        : null;
    return AdvStudentView(
      load: _load,
      profile: p,
      errorText: _error,
      section: _section,
      onSection: (s) => setState(() => _section = s),
      onRetry: () {
        setState(() => _load = AdvLoad.loading);
        _reloadAll();
      },
      onChangeAdvisor: can.assign ? _changeAdvisor : null,
      flags: AdvFlagsPane(
        load: _flagsLoad,
        page: _flags,
        view: _flagView,
        errorText: _flagsError,
        onView: (v) {
          setState(() {
            _flagView = v;
            _flagsLoad = AdvLoad.loading;
          });
          _loadFlags();
        },
        onAdd: can.flag ? _addFlag : null,
        onRetry: () {
          setState(() => _flagsLoad = AdvLoad.loading);
          _loadFlags();
        },
        canChange: _canChange,
        canEdit: _canEdit,
        onStatus: _flagStatus,
        onEdit: _editFlag,
        onHistory: (f) => showAdvFlagHistorySheet(context, _api, f),
      ),
      notes: AdvNotesPane(
        load: _notesLoad,
        composer: composer,
        notes: _notesLoad == AdvLoad.ready ? _notes : null,
        total: _notesTotal,
        restricted: _notesRestricted,
        hasMore: _notesMore,
        loadingMore: _notesLoadingMore,
        errorText: _notesError,
        onRetry: () {
          setState(() => _notesLoad = AdvLoad.loading);
          _loadNotes();
        },
        onMore: () => _loadNotes(more: true),
        canEdit: (n) => n.mine,
        canDelete: (n) => n.mine || _manage,
        onEdit: _editNote,
        onDelete: _deleteNote,
      ),
      timeline: AdvTimelinePane(
        load: _tlLoad,
        entries: _tlLoad == AdvLoad.ready ? _timeline : null,
        hasMore: _next != null,
        loadingMore: _tlLoadingMore,
        errorText: _tlError,
        onRetry: () {
          setState(() => _tlLoad = AdvLoad.loading);
          _loadTimeline();
        },
        onMore: () => _loadTimeline(more: true),
      ),
    );
  }
}

