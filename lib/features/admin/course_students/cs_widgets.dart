// lib/features/admin/course_students/cs_widgets.dart
//
// Presentational pieces of the "Courses & students" console: plain values in, callbacks out, no provider and no
// network (so the layout harness can pump them). Phones get cards, wide windows a calm table inside AppHScroll.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../admin_common.dart' show t;
import 'cs_models.dart';

/// Width from which the lists draw a table instead of cards.
const double kCsTableBreakpoint = 900;

// ── status ──────────────────────────────────────────────────────────────────

/// The theme's tone of a status (success / warning / danger / info / neutral), never a literal colour.
Color csTone(BuildContext context, CsStatus s) {
  final c = context.colors;
  return switch (s) {
    CsStatus.active => c.success,
    CsStatus.expiringSoon => c.warning,
    CsStatus.paymentIssue || CsStatus.accessError => c.danger,
    CsStatus.notEnrolled || CsStatus.staff => c.primary,
    _ => c.secondText,
  };
}

IconData csStatusIcon(CsStatus s) => switch (s) {
      CsStatus.active => Icons.check_circle_outline_rounded,
      CsStatus.expiringSoon => Icons.hourglass_bottom_rounded,
      CsStatus.expired => Icons.event_busy_rounded,
      CsStatus.cancelled => Icons.block_rounded,
      CsStatus.paymentIssue => Icons.payments_outlined,
      CsStatus.accessError => Icons.error_outline_rounded,
      CsStatus.notEnrolled => Icons.person_off_outlined,
      CsStatus.staff => Icons.badge_outlined,
      CsStatus.unknown => Icons.help_outline_rounded,
    };

class CsStatusBadge extends StatelessWidget {
  const CsStatusBadge(this.status, {super.key});
  final CsStatus status;

  @override
  Widget build(BuildContext context) =>
      AppBadgePill(csStatusLabel(status), color: csTone(context, status), icon: csStatusIcon(status));
}

String csDaysText(CsAccess a) {
  final n = a.daysLeft;
  if (n == null) return a.hasAccess && a.expiresAt == null ? t('بلا نهاية', 'No end') : '-';
  if (n < 0) return t('انتهى منذ ${-n} يوم', '${-n} d ago');
  return countText(n, ar1: 'يوم', ar2: 'يومان', arFew: '{n} أيام', arMany: '{n} يوماً', en1: '{n} day', en: '{n} days');
}

String csDate(DateTime? d) => d == null ? '-' : AppTime.date(d);

// ── small shared bits ───────────────────────────────────────────────────────

class CsPager extends StatelessWidget {
  const CsPager({super.key, required this.page, required this.pages, required this.total, required this.onPage});
  final int page;
  final int pages;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (pages <= 1) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: Center(child: Text(countText(total, ar1: 'نتيجة', arFew: '{n} نتائج', arMany: '{n} نتيجة', en1: '{n} result', en: '{n} results'), style: AppType.meta(context).copyWith(color: c.textMedium))),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xs, children: [
        IconButton(
          tooltip: t('السابق', 'Previous'),
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(t('صفحة $page من $pages · $total', 'Page $page of $pages · $total'), style: AppType.meta(context).copyWith(color: c.textMedium)),
        IconButton(
          tooltip: t('التالي', 'Next'),
          onPressed: page < pages ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    );
  }
}

/// Loading / error / empty / content switch of a list.
class CsAsyncBody extends StatelessWidget {
  const CsAsyncBody({super.key, required this.loading, required this.error, required this.empty, required this.onRetry, required this.emptyTitle, required this.builder, this.emptyIcon = Icons.search_off_rounded});
  final bool loading;
  final String? error;
  final bool empty;
  final VoidCallback onRetry;
  final String emptyTitle;
  final IconData emptyIcon;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: onRetry);
    }
    if (loading && empty) return const AppListSkeleton();
    if (empty) return AppEmpty(icon: emptyIcon, title: emptyTitle);
    return AnimatedOpacity(opacity: loading ? 0.5 : 1, duration: AppMotion.of(context).fast, child: builder(context));
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.text, {this.tone});
  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = tone == null ? c.textMedium : appInk(context, tone!);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: col),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: col))),
    ]);
  }
}

BoxDecoration _cardDeco(BuildContext context, {Color? fill}) {
  final c = context.colors;
  return BoxDecoration(color: fill ?? c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider));
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text, this.width);
  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textMedium)),
      );
}

// ── courses list ────────────────────────────────────────────────────────────

class CsCourseList extends StatelessWidget {
  const CsCourseList({super.key, required this.items, required this.onOpen});
  final List<CsCourseRow> items;
  final ValueChanged<CsCourseRow> onOpen;

  static const _w = [280.0, 170.0, 90.0, 90.0, 90.0, 120.0, 100.0, 90.0];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < kCsTableBreakpoint) {
          return Column(children: [
            for (final r in items)
              Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: _CourseCard(r, () => onOpen(r))),
          ]);
        }
        final c = context.colors;
        final head = [t('الدورة', 'Course'), t('المدرّس', 'Teacher'), t('نشط', 'Active'), t('ينتهي قريباً', 'Expiring'), t('منتهٍ', 'Expired'), t('الإيراد', 'Revenue'), t('الحالة', 'Status'), t('مشاكل', 'Issues')];
        return Container(
          decoration: _cardDeco(context),
          child: AppHScroll(
            child: SizedBox(
              width: _w.fold<double>(0, (a, b) => a + b) + AppSpace.md * 2,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(children: [for (var i = 0; i < head.length; i++) _HeadCell(head[i], _w[i])]),
                ),
                Divider(height: 1, color: c.divider),
                for (final r in items) _CourseRowTile(r, () => onOpen(r)),
              ]),
            ),
          ),
        );
      });
}

class _CourseCard extends StatelessWidget {
  const _CourseCard(this.r, this.onTap);
  final CsCourseRow r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Ink(
          padding: AppSpace.card,
          decoration: _cardDeco(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
              const SizedBox(width: AppSpace.sm),
              Icon(Icons.chevron_right_rounded, color: c.textMedium),
            ]),
            if (r.teacher != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(r.teacher!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
              _Metric(Icons.group_outlined, t('${r.active} نشط', '${r.active} active'), tone: c.success),
              _Metric(Icons.hourglass_bottom_rounded, t('${r.expiringSoon} ينتهي قريباً', '${r.expiringSoon} expiring'), tone: r.expiringSoon > 0 ? c.warning : null),
              _Metric(Icons.event_busy_rounded, t('${r.expired} منتهٍ', '${r.expired} expired')),
              _Metric(Icons.payments_outlined, csMoneyText(r.revenue, r.currency)),
            ]),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppBadgePill(csCourseStatusLabel(r.status), color: r.status == 'published' ? c.success : c.secondText),
              if (r.issues > 0) AppBadgePill(t('${r.issues} مشكلة', '${r.issues} issues'), color: c.danger, icon: Icons.warning_amber_rounded),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _CourseRowTile extends StatelessWidget {
  const _CourseRowTile(this.r, this.onTap);
  final CsCourseRow r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(double w, Widget child) => SizedBox(width: w, child: child);
    Text txt(String s) => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark));
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
        child: Row(children: [
          cell(CsCourseList._w[0], Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)))),
          cell(CsCourseList._w[1], Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: txt(r.teacher?.name ?? '-'))),
          cell(CsCourseList._w[2], txt('${r.active}')),
          cell(CsCourseList._w[3], txt('${r.expiringSoon}')),
          cell(CsCourseList._w[4], txt('${r.expired}')),
          cell(CsCourseList._w[5], Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: txt(csMoneyText(r.revenue, r.currency)))),
          cell(CsCourseList._w[6], Align(alignment: AlignmentDirectional.centerStart, child: AppBadgePill(csCourseStatusLabel(r.status), color: r.status == 'published' ? c.success : c.secondText))),
          cell(CsCourseList._w[7], r.issues > 0 ? Align(alignment: AlignmentDirectional.centerStart, child: AppBadgePill('${r.issues}', color: c.danger, icon: Icons.warning_amber_rounded)) : txt('-')),
        ]),
      ),
    );
  }
}

// ── roster ──────────────────────────────────────────────────────────────────

/// The status counts of a course as tappable filter chips ("All" first).
class CsStatusChips extends StatelessWidget {
  const CsStatusChips({super.key, required this.roster, required this.selected, required this.onSelect});
  final CsRoster roster;
  final CsStatus? selected;
  final ValueChanged<CsStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = roster.counts['total'] ?? roster.total;
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      AppChoiceChip(label: t('الكل ($total)', 'All ($total)'), selected: selected == null, onTap: () => onSelect(null)),
      for (final s in csFilterStatuses)
        if (roster.countOf(s) > 0 || selected == s)
          AppChoiceChip(label: '${csStatusLabel(s)} (${roster.countOf(s)})', selected: selected == s, onTap: () => onSelect(selected == s ? null : s)),
    ]);
  }
}

class CsRosterList extends StatelessWidget {
  const CsRosterList({super.key, required this.items, required this.onOpen});
  final List<CsRosterRow> items;
  final ValueChanged<CsRosterRow> onOpen;

  static const _w = [260.0, 110.0, 110.0, 110.0, 110.0, 150.0];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < kCsTableBreakpoint) {
          return Column(children: [
            for (final r in items) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: _RosterCard(r, () => onOpen(r))),
          ]);
        }
        final head = [t('الطالب', 'Student'), t('الباقة', 'Plan'), t('البداية', 'Start'), t('الانتهاء', 'Expiry'), t('المتبقي', 'Left'), t('الحالة', 'Status')];
        return Container(
          decoration: _cardDeco(context),
          child: AppHScroll(
            child: SizedBox(
              width: _w.fold<double>(0, (a, b) => a + b) + AppSpace.md * 2,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(children: [for (var i = 0; i < head.length; i++) _HeadCell(head[i], _w[i])]),
                ),
                for (final r in items) _RosterTableRow(r, () => onOpen(r)),
              ]),
            ),
          ),
        );
      });
}

Color? _flagFill(BuildContext context, CsAccess a) {
  final c = context.colors;
  if (a.paidNoAccess) return c.dangerTint;
  if (a.accessNoPayment) return appTintOn(context, c.warning);
  return null;
}

/// The inline explanation under a flagged row: what the flag means and why access is as it is.
class CsFlagNote extends StatelessWidget {
  const CsFlagNote(this.access, {super.key});
  final CsAccess access;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = access.paidNoAccess ? c.danger : c.warning;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 16, color: appInk(context, tone)),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text('${access.flags.map(csFlagText).join(' · ')} - ${csReasonText(access)}', style: AppType.meta(context).copyWith(color: appInk(context, tone), height: 1.4)),
        ),
      ]),
    );
  }
}

class _RosterCard extends StatelessWidget {
  const _RosterCard(this.r, this.onTap);
  final CsRosterRow r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = r.access;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Ink(
          padding: AppSpace.card,
          decoration: _cardDeco(context, fill: _flagFill(context, a)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AppAvatar(name: r.student.name, url: r.student.imageUrl, size: 40),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.student.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  if (r.student.contact.isNotEmpty) Text(r.student.contact, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                ]),
              ),
            ]),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              CsStatusBadge(a.kind),
              _Metric(Icons.workspace_premium_outlined, csPlanLabel(a.plan)),
              _Metric(Icons.play_arrow_rounded, csDate(a.startsAt)),
              _Metric(Icons.event_rounded, csDate(a.expiresAt)),
              _Metric(Icons.schedule_rounded, csDaysText(a), tone: a.kind == CsStatus.expiringSoon ? c.warning : null),
            ]),
            if (a.flags.isNotEmpty) CsFlagNote(a),
          ]),
        ),
      ),
    );
  }
}

class _RosterTableRow extends StatelessWidget {
  const _RosterTableRow(this.r, this.onTap);
  final CsRosterRow r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = r.access;
    Text txt(String s) => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark));
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(color: _flagFill(context, a), border: Border(top: BorderSide(color: c.divider))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: CsRosterList._w[0],
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
                child: Row(children: [
                  AppAvatar(name: r.student.name, url: r.student.imageUrl, size: 32),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.student.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                      if (r.student.contact.isNotEmpty) Text(r.student.contact, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                    ]),
                  ),
                ]),
              ),
            ),
            SizedBox(width: CsRosterList._w[1], child: txt(csPlanLabel(a.plan))),
            SizedBox(width: CsRosterList._w[2], child: txt(csDate(a.startsAt))),
            SizedBox(width: CsRosterList._w[3], child: txt(csDate(a.expiresAt))),
            SizedBox(width: CsRosterList._w[4], child: txt(csDaysText(a))),
            SizedBox(width: CsRosterList._w[5], child: Align(alignment: AlignmentDirectional.centerStart, child: CsStatusBadge(a.kind))),
          ]),
          if (a.flags.isNotEmpty) SizedBox(width: CsRosterList._w.fold<double>(0, (x, y) => x + y), child: CsFlagNote(a)),
        ]),
      ),
    );
  }
}

// ── lookup results ──────────────────────────────────────────────────────────

class CsLookupResults extends StatelessWidget {
  const CsLookupResults({super.key, required this.items, required this.onOpen});
  final List<CsStudent> items;
  final ValueChanged<CsStudent> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: _cardDeco(context),
      child: Column(children: [
        for (final s in items)
          InkWell(
            onTap: () => onOpen(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(children: [
                AppAvatar(name: s.name, url: s.imageUrl, size: 36),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    if (s.contact.isNotEmpty) Text(s.contact, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                  ]),
                ),
                if (csMatchedByLabel(s.matchedBy).isNotEmpty) ...[
                  const SizedBox(width: AppSpace.xs),
                  Flexible(child: AppBadgePill(csMatchedByLabel(s.matchedBy), color: c.primary)),
                ],
              ]),
            ),
          ),
      ]),
    );
  }
}
