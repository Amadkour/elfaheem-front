// lib/features/parent/parent_overview_page.dart — the parent's "Today" tab (Track B.5).
//
//   header     greeting · name · calendar · notifications
//   needs you     HomeStatStrip: alerts (→ Alerts tab) · pending link requests (→ Link tab), only counts above zero
//   today for my children   one AppCard per child: avatar · name · courses, then today's sessions as agenda rows,
//              attendance of the last 30 days as a pill, the 3 newest marks, the next exam, the open alerts (→ the
//              Alerts tab filtered on that child); the card opens the child's report
//   empty      "no children linked yet" → the Link tab (and the pending requests, if any)
// Data: ParentOverviewProvider (GET /api/v1/parent/overview — ONE call). Skeleton while it loads, ErrorRetry
// (retried by itself when the connection comes back), pull-to-refresh via AppRefresh.
// ParentOverviewBody takes plain values (test/ui/parent_home_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../auth/auth_provider.dart';
import '../shared/notification/notifications_provider.dart';
import 'parent_overview.dart';
import 'parent_reports_page.dart';

class ParentOverviewPage extends StatefulWidget {
  const ParentOverviewPage({
    super.key,
    required this.onOpenAlerts,
    required this.onOpenLink,
    required this.onOpenChildren,
  });

  /// Alerts tab, optionally filtered on one child.
  final void Function(int? childId) onOpenAlerts;
  final VoidCallback onOpenLink;
  final VoidCallback onOpenChildren;

  @override
  State<ParentOverviewPage> createState() => _ParentOverviewPageState();
}

class _ParentOverviewPageState extends State<ParentOverviewPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_onConnectivity);
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_onConnectivity);
    super.dispose();
  }

  void _onConnectivity() {
    if (!mounted || !AppConnectivity.instance.isOnline) return;
    final p = context.read<ParentOverviewProvider>();
    if (p.hasError && !p.loaded) p.load();
  }

  void _openChild(ParentChildOverview ch) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ParentChildReportScreen(studentId: ch.id, studentName: ch.name)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.watch<ParentOverviewProvider>();
    final user = context.watch<MyAuthProvider>().currentUser;
    final unread = context.watch<NotificationsProvider>().unreadCount;
    return SafeArea(
      child: AppRefresh(
        onRefresh: () => p.load(silent: true),
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.zero,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  HomeEntrance(
                    index: 0,
                    child: HomeHeader(
                      helpPageId: 'home.parent',
                      name: user?.name ?? 'role_parent'.tr,
                      leading: user == null ? null : UserChipButton(user: user, showLabel: false),
                      shellActions: [const CalendarEntryIcon(), NotificationIcon(unreadCount: unread)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ParentOverviewBody(
                    data: p.data,
                    loading: p.isLoading && !p.loaded,
                    error: p.hasError && !p.loaded ? (p.errorMessage ?? 'generic_error'.tr) : null,
                    onRetry: p.load,
                    onOpenAlerts: widget.onOpenAlerts,
                    onOpenLink: widget.onOpenLink,
                    onOpenChildren: widget.onOpenChildren,
                    onOpenChild: _openChild,
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Today tab below the header, over plain values.
class ParentOverviewBody extends StatelessWidget {
  const ParentOverviewBody({
    super.key,
    required this.data,
    this.loading = false,
    this.error,
    this.onRetry,
    required this.onOpenAlerts,
    required this.onOpenLink,
    required this.onOpenChildren,
    required this.onOpenChild,
  });

  final ParentOverviewData? data;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final void Function(int? childId) onOpenAlerts;
  final VoidCallback onOpenLink;
  final VoidCallback onOpenChildren;
  final ValueChanged<ParentChildOverview> onOpenChild;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = data;
    if (d == null && loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 36),
        child: AppListSkeleton(items: 4, padding: EdgeInsets.zero),
      );
    }
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorRetry(message: error ?? 'generic_error'.tr, onRetry: onRetry ?? () {}),
      );
    }
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);
    final pending = d.pendingRequests;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── what waits for me: one slim row of the counts above zero (the children are listed below) — the same calm
      //    "Needs you" strip as the student and instructor homes
      if (d.alertsTotal > 0 || pending > 0) ...[
        enter(HomeSection(
          id: 'parent.needs_you',
          title: 'home_needs_you'.tr,
          foldedSummary: 'home_needs_folded'.tr.replaceAll('{n}', '${d.alertsTotal + pending}'),
          child: HomeStatStrip(items: [
            HomeStat(
              icon: Icons.notifications_active_outlined,
              label: 'pl_tab_alerts'.tr,
              count: d.alertsTotal,
              tone: c.danger,
              onTap: () => onOpenAlerts(null),
            ),
            HomeStat(icon: Icons.link_rounded, label: 'pl_ov_requests'.tr, count: pending, tone: c.warning, onTap: onOpenLink),
          ]),
        )),
        const SizedBox(height: 24),
      ],

      // ── today for my children
      enter(HomeSectionTitle('pl_ov_today'.tr,
          count: d.children.isEmpty ? null : d.sessionsToday,
          actionLabel: d.children.isEmpty ? null : 'pl_tab_children'.tr,
          onAction: d.children.isEmpty ? null : onOpenChildren)),
      if (d.children.isEmpty)
        enter(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AppEmpty(
            icon: Icons.family_restroom_rounded,
            title: 'pl_no_children_title'.tr,
            message: pending > 0
                ? 'pl_ov_requests_pending'.tr.replaceAll('{n}', '$pending')
                : 'pl_no_children_hint'.tr,
            actionLabel: pending > 0 ? 'pl_tab_link'.tr : 'pl_link_child'.tr,
            onAction: onOpenLink,
          ),
        ))
      else ...[
        for (final ch in d.children)
          enter(Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: ParentChildOverviewCard(
              child: ch,
              onOpen: () => onOpenChild(ch),
              onOpenAlerts: () => onOpenAlerts(ch.id),
            ),
          )),
        Center(
          child: TextButton.icon(
            onPressed: onOpenLink,
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: Text('pl_link_another'.tr),
          ),
        ),
      ],
      const SizedBox(height: 36),
    ]);
  }
}

/// One child's day: who · today's sessions · attendance · newest marks · next exam · open alerts.
class ParentChildOverviewCard extends StatelessWidget {
  const ParentChildOverviewCard({super.key, required this.child, required this.onOpen, required this.onOpenAlerts});

  final ParentChildOverview child;
  final VoidCallback onOpen;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ch = child;
    final now = homeNow();
    final nowMin = now.hour * 60 + now.minute;
    final att = ch.attendancePct30d;
    final attColor = att == null ? c.textLight : appScoreColor(context, att.toDouble());
    final exam = ch.nextExam;
    final hot = ch.openAlerts > 0;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── who
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Row(children: [
            AppAvatar(name: ch.name, url: ch.imageUrl.isEmpty ? null : ch.imageUrl, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w600, c: c.textDark)),
                const SizedBox(height: 2),
                Text(
                  '${'pl_ov_courses_n'.tr.replaceAll('{n}', '${ch.courses}')} · ${'pl_ov_sessions_n'.tr.replaceAll('{n}', '${ch.todaySessions.length}')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appText(12, c: c.textMedium, h: 1.4),
                ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),

        // ── pills: attendance · alerts
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppBadgePill(
              att == null ? 'pl_ov_attendance_none'.tr : 'pl_ov_attendance'.tr.replaceAll('{n}', '$att'),
              color: attColor,
              icon: Icons.how_to_reg_rounded,
            ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onOpenAlerts,
              // the pill is 22 px; its tap target is 48 high (Android / iOS minimum)
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  widthFactor: 1,
                  child: AppBadgePill(
                hot ? 'pl_ov_alerts_n'.tr.replaceAll('{n}', '${ch.openAlerts}') : 'pl_ov_alerts_none'.tr,
                color: hot ? c.danger : c.success,
                icon: hot ? Icons.notifications_active_rounded : Icons.verified_rounded,
                  ),
                ),
              ),
            ),
          ]),
        ),

        // ── today's sessions
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: _Label('pl_ov_today_sessions'.tr, icon: Icons.today_rounded),
        ),
        if (ch.todaySessions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('pl_ov_no_sessions'.tr, style: appText(12.5, c: c.textLight)),
          )
        else
          for (final s in ch.todaySessions)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: _SessionRow(event: s, nowMin: nowMin),
            ),

        // ── newest marks
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: _Label('pl_ov_latest_marks'.tr, icon: Icons.grading_rounded),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: ch.latestMarks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text('pl_ov_no_marks'.tr, style: appText(12.5, c: c.textLight)),
                )
              : Wrap(spacing: 8, runSpacing: 8, children: [for (final m in ch.latestMarks) _MarkChip(mark: m)]),
        ),

        // ── next exam
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(children: [
            Icon(Icons.event_note_rounded, size: 18, color: exam == null ? c.textLight : c.accent2),
            const SizedBox(width: 8),
            Expanded(
              child: exam == null
                  ? Text('pl_ov_no_exam'.tr, style: appText(12.5, c: c.textLight))
                  : Text(
                      '${'pl_ov_next_exam'.tr} · ${exam.name}${exam.startsAt == null ? '' : ' · ${AppTime.dateTime(exam.startsAt!)}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(12.5, w: FontWeight.w500, c: c.textDark, h: 1.35),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(icon, size: 15, color: c.textMedium),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textMedium)),
      ),
    ]);
  }
}

/// An agenda-style row: time column · live / past tone · title · subtitle.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.event, required this.nowMin});
  final ParentEventRow event;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = event.startsAt, e = event.endsAt;
    final startMin = event.wallMinutes(AppTime.toZone);
    final endMin = e == null ? null : AppTime.toZone(e).hour * 60 + AppTime.toZone(e).minute;
    final live = startMin != null && endMin != null && nowMin >= startMin && nowMin < endMin;
    final past = endMin != null && nowMin >= endMin;
    final tone = live ? c.success : (past ? c.textLight : c.primary);
    final sub = [
      if (event.subtitle.isNotEmpty) event.subtitle,
      if (event.location.isNotEmpty) event.location,
      // the server's mode keyword ("online" / "offline") in the reader's language — it was shown raw
      if (event.mode.isNotEmpty) _modeLabel(event.mode),
    ].join(' · ');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 64,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s == null ? '—' : AppTime.time(s), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: appText(12, w: FontWeight.w600, c: appInk(context, tone))),
          if (e != null)
            Text(AppTime.time(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(10.5, c: c.textLight)),
        ]),
      ),
      Container(
        width: 3,
        height: 34,
        margin: const EdgeInsetsDirectional.only(end: 10, top: 2),
        decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(2)),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the live pill gets its own line: beside a long title it overflowed a 320 px phone
          Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: appText(13, w: FontWeight.w500, c: past ? c.textMedium : c.textDark, h: 1.25)),
          if (live)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 1),
              child: AppBadgePill('home_live'.tr, color: c.success, icon: Icons.sensors_rounded),
            ),
          if (sub.isNotEmpty)
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
        ]),
      ),
    ]);
  }
}

String _modeLabel(String mode) => switch (mode) {
      'online' => AppConfig.lang == 'ar' ? 'أونلاين' : 'Online',
      'offline' => AppConfig.lang == 'ar' ? 'حضوري' : 'In person',
      _ => mode,
    };

class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.mark});
  final ParentMark mark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = mark.percentage;
    final color = pct == null ? c.textLight : (mark.passed == false ? c.danger : appScoreColor(context, pct));
    final label = [
      if (mark.course.isNotEmpty) mark.course,
      mark.exam,
    ].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(pct == null ? '—' : '${pct.round()}%', style: appText(13, w: FontWeight.w600, c: color)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.textDark)),
          ),
        ]),
      ),
    );
  }
}
