// lib/features/parent/parent_overview_page.dart — the parent's "Today" tab (Track B.5, D-305).
//
//   header     greeting · name · calendar · notifications
//   needs you     HomeStatStrip: alerts (→ Alerts tab) · pending link requests (→ Link tab), only counts above zero
//   my child   (D-305, with the server's pulse) the child switcher, then "How is <name> doing" (status · one
//              sentence · attendance / average vs class / missed work with their 6-week lines), "Needs your
//              attention" (findings with one action each: message the teacher · report · alerts), "This week",
//              Subjects (strength / focus, class-average marker), the learning path, Latest marks
//              (parent_pulse_widgets.dart); without a pulse (older server, `parent.insights` off) the cards below
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
import 'parent_message_teacher.dart';
import 'parent_overview.dart';
import 'parent_pulse.dart';
import 'parent_pulse_widgets.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart' show parentChildTone;

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
                constraints: const BoxConstraints(maxWidth: kHomeWideMax),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  HomeEntrance(
                    index: 0,
                    child: HomeHeader(
                      helpPageId: 'home.parent',
                      name: user?.name ?? 'role_parent'.tr,
                      leading: user == null ? null : UserChipButton(user: user, showLabel: false),
                      shellActions: [const CalendarEntryIcon(), const ChatEntryIcon(), NotificationIcon(unreadCount: unread)],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
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
///
/// With the server's pulse (D-305): the child switcher (two children or more), then the selected child's "How is
/// `name` doing" hero, "Needs your attention" and "This week" — beside Subjects, the learning path and Latest marks
/// on a wide screen (HomeDashboard), one column on a phone. Without it (an older server, `parent.insights` off) the
/// per-child cards of every child, as before.
class ParentOverviewBody extends StatefulWidget {
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
    this.onMessageTeacher,
  });

  final ParentOverviewData? data;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final void Function(int? childId) onOpenAlerts;
  final VoidCallback onOpenLink;
  final VoidCallback onOpenChildren;
  final ValueChanged<ParentChildOverview> onOpenChild;

  /// "Message the teacher" for a child (a course preselected or null); null → the message sheet itself.
  final void Function(ParentChildOverview child, int? courseId)? onMessageTeacher;

  @override
  State<ParentOverviewBody> createState() => _ParentOverviewBodyState();
}

class _ParentOverviewBodyState extends State<ParentOverviewBody> {
  int? _selected;

  static bool get _pulseOn => !AppConfig.disableList.contains('parent.insights');

  ParentChildOverview? _current(ParentOverviewData d) {
    if (d.children.isEmpty) return null;
    return d.children.firstWhere((c) => c.id == _selected, orElse: () => d.children.first);
  }

  void _message(ParentChildOverview ch, int? courseId) {
    final cb = widget.onMessageTeacher;
    if (cb != null) return cb(ch, courseId);
    showParentMessageTeacher(context, childId: ch.id, childName: ch.name, teachers: ch.pulse?.teachers ?? const [], courseId: courseId);
  }

  void _act(ParentChildOverview ch, PulseInsight i) {
    final a = i.action;
    if (a == null) return;
    switch (a.kind) {
      case PulseActionKind.messageTeacher:
        _message(ch, a.courseId);
      case PulseActionKind.openReport:
        widget.onOpenChild(ch);
      case PulseActionKind.openAlerts:
        widget.onOpenAlerts(ch.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.data;
    if (d == null && widget.loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(parentHomeGutter, AppSpace.xs, parentHomeGutter, AppSpace.xl),
        child: AppListSkeleton(items: 4, padding: EdgeInsets.zero),
      );
    }
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: ErrorRetry(message: widget.error ?? 'generic_error'.tr, onRetry: widget.onRetry ?? () {}),
      );
    }
    // ONE orchestrated entrance (HomeEntrance, after the header's 0): the strip, the switcher and the child's block
    // rise in turn; the sections under the block arrive with it (one entrance per container)
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);
    final pending = d.pendingRequests;
    final ch = _current(d);
    final pulse = _pulseOn ? ch?.pulse : null;

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
              tone: c.warning, // an alert asks for a look; red stays for errors / live (D-630)
              onTap: () => widget.onOpenAlerts(null),
            ),
            HomeStat(icon: Icons.link_rounded, label: 'pl_ov_requests'.tr, count: pending, tone: c.warning, onTap: widget.onOpenLink),
          ]),
        )),
        const SizedBox(height: AppSpace.md),
      ],

      if (d.children.isEmpty) ...[
        enter(HomeSectionTitle('pl_ov_today'.tr)),
        enter(Padding(
          padding: const EdgeInsets.symmetric(horizontal: parentHomeGutter),
          child: AppEmpty(
            icon: Icons.family_restroom_rounded,
            title: 'pl_no_children_title'.tr,
            message: pending > 0 ? 'pl_ov_requests_pending'.tr.replaceAll('{n}', '$pending') : 'pl_no_children_hint'.tr,
            actionLabel: pending > 0 ? 'pl_tab_link'.tr : 'pl_link_child'.tr,
            onAction: widget.onOpenLink,
          ),
        )),
      ] else if (pulse != null && ch != null) ...[
        // ── my children: one chip each (status dot), the selected child's block below
        if (d.children.length > 1) ...[
          enter(ParentChildSwitcher(children: d.children, selectedId: ch.id, onSelect: (id) => setState(() => _selected = id))),
          const SizedBox(height: AppSpace.sm),
        ],
        enter(Padding(
          padding: const EdgeInsets.symmetric(horizontal: parentHomeGutter),
          // switching children crossfades the picture in place (it is the same block, another child)
          child: AnimatedSwitcher(
            duration: AppMotion.of(context).base,
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: KeyedSubtree(key: ValueKey('pulse-${ch.id}'), child: _pulseLayout(ch, pulse)),
          ),
        )),
      ] else ...[
        // ── an older server / `parent.insights` off: today for my children, one block each (as before)
        enter(HomeSectionTitle('pl_ov_today'.tr,
            count: d.sessionsToday, actionLabel: 'pl_tab_children'.tr, onAction: widget.onOpenChildren)),
        for (final x in d.children)
          enter(Padding(
            padding: const EdgeInsets.fromLTRB(parentHomeGutter, 0, parentHomeGutter, AppSpace.md),
            child: ParentChildOverviewCard(
              child: x,
              onOpen: () => widget.onOpenChild(x),
              onOpenAlerts: () => widget.onOpenAlerts(x.id),
            ),
          )),
      ],
      if (d.children.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: Center(
            child: Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              AppButton.ghost(label: 'pl_tab_children'.tr, icon: Icons.family_restroom_rounded, onPressed: widget.onOpenChildren),
              AppButton.ghost(label: 'pl_link_another'.tr, icon: Icons.add_link_rounded, onPressed: widget.onOpenLink),
            ]),
          ),
        ),
      const SizedBox(height: AppSpace.xl),
    ]);
  }

  Widget _pulseLayout(ParentChildOverview ch, ParentPulse p) {
    final canMessage = parentMessageTeacherOn && p.teachers.isNotEmpty;
    final hero = ParentPulseHero(child: ch, pulse: p, onOpenReport: () => widget.onOpenChild(ch));
    final insights = ParentInsightsCard(
      childName: ch.name,
      insights: p.insights,
      canMessage: canMessage,
      onAction: (i) => _act(ch, i),
    );
    final week = ParentWeekCard(events: p.upcoming);
    final subjects = p.subjects.isEmpty
        ? null
        : ParentSubjectsCard(subjects: p.subjects, onMessage: canMessage ? (s) => _message(ch, s.courseId) : null);
    final road = p.roadmap == null ? null : ParentRoadmapCard(roadmap: p.roadmap!, childName: ch.name);
    final marks = ch.latestMarks.isEmpty && ch.nextExam == null ? null : _MarksCard(child: ch);
    return HomeDashboard(
      gap: AppSpace.md,
      main: [hero, insights, week],
      // the side column's cards keep a gutter from the main column (HomeDashboard draws none of its own)
      side: [
        for (final w in [?subjects, ?road, ?marks])
          Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.md), child: w),
      ],
      narrow: [hero, insights, week, ?subjects, ?road, ?marks],
    );
  }
}

/// The newest marks and the next exam of one child (the pulse layout's side card).
class _MarksCard extends StatelessWidget {
  const _MarksCard({required this.child});
  final ParentChildOverview child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exam = child.nextExam;
    return ParentPulseSection(
      title: 'pl_ov_latest_marks'.tr,
      icon: Icons.grading_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (child.latestMarks.isEmpty)
          Text('pl_ov_no_marks'.tr, style: AppType.body(context).copyWith(color: c.textLight))
        else
          for (final m in child.latestMarks) _MarkLine(mark: m),
        if (exam != null) ...[
          const SizedBox(height: AppSpace.sm),
          _NextExam(exam: exam),
        ],
      ]),
    );
  }
}

/// One child's day (an older server, or `parent.insights` off): a block in the child's own tone — who · today's
/// sessions · attendance · newest marks · next exam · open alerts; the block opens the child's report.
class ParentChildOverviewCard extends StatelessWidget {
  const ParentChildOverviewCard({super.key, required this.child, required this.onOpen, required this.onOpenAlerts});

  final ParentChildOverview child;
  final VoidCallback onOpen;
  final VoidCallback onOpenAlerts;

  static const double _avatar = AppTouch.min;

  @override
  Widget build(BuildContext context) {
    final ch = child;
    final now = homeNow();
    final nowMin = now.hour * 60 + now.minute;
    final att = ch.attendancePct30d;
    final exam = ch.nextExam;
    final hot = ch.openAlerts > 0;

    return AppBlock(
      // a child keeps the same tone on every screen (the reports use it too)
      tone: parentChildTone(ch.id),
      onTap: onOpen,
      semanticLabel: ch.name,
      padding: const EdgeInsets.all(AppSpace.md + AppSpace.xxs),
      child: Builder(builder: (context) {
        final ink = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── who
          Row(children: [
            AppAvatar(name: ch.name, url: ch.imageUrl.isEmpty ? null : ch.imageUrl, size: _avatar),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: ink.ink)),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(
                  '${'pl_ov_courses_n'.tr.replaceAll('{n}', '${ch.courses}')} · ${'pl_ov_sessions_n'.tr.replaceAll('{n}', '${ch.todaySessions.length}')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: ink.muted, height: 1.4),
                ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: ink.muted),
          ]),

          // ── pills: attendance · alerts
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppStatusBadge(
              label: att == null ? 'pl_ov_attendance_none'.tr : 'pl_ov_attendance'.tr.replaceAll('{n}', '$att'),
              tone: att == null ? AppTone.neutral : (att >= 75 ? AppTone.success : (att >= 50 ? AppTone.warning : AppTone.danger)),
              icon: Icons.how_to_reg_rounded,
            ),
            Semantics(
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: onOpenAlerts,
                // the pill is 24 px; its tap target is 48 high (Android / iOS minimum)
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Center(
                    widthFactor: 1,
                    child: AppStatusBadge(
                      label: hot ? 'pl_ov_alerts_n'.tr.replaceAll('{n}', '${ch.openAlerts}') : 'pl_ov_alerts_none'.tr,
                      tone: hot ? AppTone.danger : AppTone.success,
                      icon: hot ? Icons.notifications_active_rounded : Icons.verified_rounded,
                    ),
                  ),
                ),
              ),
            ),
          ]),

          // ── today's sessions: a paper sheet inside the block, so the rows read as a list
          const SizedBox(height: AppSpace.xs),
          _Label('pl_ov_today_sessions'.tr, icon: Icons.today_rounded),
          const SizedBox(height: AppSpace.xxs),
          if (ch.todaySessions.isEmpty)
            Text('pl_ov_no_sessions'.tr, style: AppType.meta(context).copyWith(color: ink.muted))
          else
            for (final s in ch.todaySessions)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs + AppBorder.focus),
                child: _SessionRow(event: s, nowMin: nowMin),
              ),

          // ── newest marks
          const SizedBox(height: AppSpace.md),
          _Label('pl_ov_latest_marks'.tr, icon: Icons.grading_rounded),
          const SizedBox(height: AppSpace.xxs),
          if (ch.latestMarks.isEmpty)
            Text('pl_ov_no_marks'.tr, style: AppType.meta(context).copyWith(color: ink.muted))
          else
            for (final m in ch.latestMarks) _MarkLine(mark: m),

          // ── next exam
          const SizedBox(height: AppSpace.sm),
          if (exam == null)
            Row(children: [
              Icon(Icons.event_note_rounded, size: AppIconSize.sm, color: ink.faint),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text('pl_ov_no_exam'.tr, style: AppType.meta(context).copyWith(color: ink.muted))),
            ])
          else
            _NextExam(exam: exam),
        ]);
      }),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ink = AppBlock.colorsOf(context);
    return Row(children: [
      Icon(icon, size: AppIconSize.xs, color: ink.muted),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink.muted)),
      ),
    ]);
  }
}

/// The next exam: an icon well · "Next exam · name · when".
class _NextExam extends StatelessWidget {
  const _NextExam({required this.exam});
  final ParentNextExam exam;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(Icons.event_note_rounded, size: AppIconSize.sm, color: appInk(context, c.warning)),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(
          '${'pl_ov_next_exam'.tr} · ${exam.name}${exam.startsAt == null ? '' : ' · ${AppTime.dateTime(exam.startsAt!)}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.label(context).copyWith(color: c.textDark, height: 1.4),
        ),
      ),
    ]);
  }
}

/// An agenda-style row: time column · live / past rail · title · subtitle.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.event, required this.nowMin});
  final ParentEventRow event;
  final int nowMin;

  static const double _timeWidth = AppSpace.xxxl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = AppBlock.colorsOf(context);
    final s = event.startsAt, e = event.endsAt;
    final startMin = event.wallMinutes(AppTime.toZone);
    final endMin = e == null ? null : AppTime.toZone(e).hour * 60 + AppTime.toZone(e).minute;
    final live = startMin != null && endMin != null && nowMin >= startMin && nowMin < endMin;
    final past = endMin != null && nowMin >= endMin;
    final tone = live ? c.success : (past ? ink.faint : c.primary);
    final sub = [
      if (event.subtitle.isNotEmpty) event.subtitle,
      if (event.location.isNotEmpty) event.location,
      // the server's mode keyword ("online" / "offline") in the reader's language — it was shown raw
      if (event.mode.isNotEmpty) _modeLabel(event.mode),
    ].join(' · ');
    const tabular = [FontFeature.tabularFigures()];
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: _timeWidth,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s == null ? '—' : AppTime.time(s), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink.accentInk(tone), fontFeatures: tabular)),
            if (e != null)
              Text(AppTime.time(e), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: ink.muted, fontFeatures: tabular)),
          ]),
        ),
        Container(
          width: AppBorder.focus + AppBorder.hairline,
          margin: const EdgeInsetsDirectional.only(end: AppSpace.sm, top: AppBorder.focus, bottom: AppBorder.focus),
          decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.pill)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // the live pill gets its own line: beside a long title it overflowed a 320 px phone
            Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppType.row(context).copyWith(color: past ? ink.muted : ink.ink, height: 1.3)),
            if (live)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
                child: AppStatusBadge(label: 'home_live'.tr, tone: AppTone.success, icon: Icons.sensors_rounded, dense: true),
              ),
            if (sub.isNotEmpty)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink.muted)),
          ]),
        ),
      ]),
    );
  }
}

String _modeLabel(String mode) => switch (mode) {
      'online' => AppConfig.lang == 'ar' ? 'أونلاين' : 'Online',
      'offline' => AppConfig.lang == 'ar' ? 'حضوري' : 'In person',
      _ => mode,
    };

/// One mark as a quiet line: the figure in its score tone (a small tinted pill) · course · exam.
class _MarkLine extends StatelessWidget {
  const _MarkLine({required this.mark});
  final ParentMark mark;

  static const double _figureWidth = AppTouch.primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = mark.percentage;
    final tone = pct == null ? AppTone.neutral : (mark.passed == false ? AppTone.danger : (pct >= 75 ? AppTone.success : (pct >= 50 ? AppTone.warning : AppTone.danger)));
    final label = [
      if (mark.course.isNotEmpty) mark.course,
      mark.exam,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        SizedBox(
          width: _figureWidth,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppStatusBadge(label: pct == null ? '—' : '${pct.round()}%', tone: tone),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: c.textDark)),
        ),
      ]),
    );
  }
}
