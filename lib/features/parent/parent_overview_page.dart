// lib/features/parent/parent_overview_page.dart — the parent's "Today" tab (Track B.5, D-305), redrawn for the
// redesign (Pa2Today `screen=today|all|empty`, phase 4).
//
//   one child   (the child picked in the top bar's switcher, or the only one, with the server's pulse) the child's
//               hero (ParentPulseHero: greeting · "<name> is doing well this week" · one sentence · Full report (hot)
//               · Message the teacher · attendance / average / missed), then "Needs your attention", "This week",
//               Subjects; on a wide screen a side column with the 6-week bars, the learning path ring and the newest
//               marks (parent_pulse_widgets.dart)
//   all         (the "All" chip, or no pulse: an older server, `parent.insights` off) "My children's day": classes
//               today and a live one now, then one card per child: who · courses · attendance · open alerts ·
//               today's classes (a live tag on the running one) · newest marks · next exam; the card opens the
//               child's report
//   empty       no child linked yet: how linking works in three steps → the link page (and "add your child" when
//               the parent may create the child's account, `parent.create_child`)
// Data: ParentOverviewProvider (GET /api/v1/parent/overview — ONE call; the home budget in test/perf counts it).
// Skeleton while it loads, ErrorRetry (retried by itself when the connection comes back), pull to refresh.
// ParentOverviewBody takes plain values (test/ui/parent_home_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/boot_splash.dart' show SplashState;
import 'package:flutter_education_app/design/home_kit.dart' show HomeHeader;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../auth/auth_provider.dart';
import 'pa_kit.dart';
import 'parent_message_teacher.dart';
import 'parent_overview.dart';
import 'parent_pulse.dart';
import 'parent_pulse_widgets.dart';
import 'parent_reports_page.dart';

class ParentOverviewPage extends StatefulWidget {
  const ParentOverviewPage({
    super.key,
    required this.onOpenAlerts,
    required this.onOpenLink,
    required this.onOpenChildren,
    this.onAddChild,
    this.footer,
  });

  /// Alerts tab, optionally filtered on one child.
  final void Function(int? childId) onOpenAlerts;
  final VoidCallback onOpenLink;
  final VoidCallback onOpenChildren;

  /// "Add your child" (the parent creates the child's account); null = not offered.
  final VoidCallback? onAddChild;

  /// Under the page (the children's organizations card).
  final Widget? footer;

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
    return AppRefresh(
      onRefresh: () => p.load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        children: [
          ParentOverviewBody(
            greeting: ParentHomeGreeting(name: _firstOr(user?.name, 'role_parent'.tr), helpPageId: 'home.parent'),
            data: p.data,
            loading: p.isLoading && !p.loaded,
            error: p.hasError && !p.loaded ? (p.errorMessage ?? 'generic_error'.tr) : null,
            onRetry: p.load,
            onOpenAlerts: widget.onOpenAlerts,
            onOpenLink: widget.onOpenLink,
            onOpenChildren: widget.onOpenChildren,
            onOpenChild: _openChild,
            onAddChild: widget.onAddChild,
          ),
          if (widget.footer != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: paWide(context) ? AppSpace.lg : AppSpace.md),
              child: widget.footer,
            ),
        ],
      ),
    );
  }
}

/// The greeting's plain values: the parent's name and the Info button's page id (drawn by the tab's top bar).
class ParentHomeGreeting {
  const ParentHomeGreeting({required this.name, this.leading, this.shellActions = const [], this.helpPageId});

  final String name;

  /// Kept for callers: the redesign's top bar carries the profile, the bell and the messages.
  final Widget? leading;
  final List<Widget> shellActions;
  final String? helpPageId;
}

/// The Today tab, over plain values (see the file header). [greeting] null = no greeting line in the hero.
class ParentOverviewBody extends StatefulWidget {
  const ParentOverviewBody({
    super.key,
    required this.data,
    this.greeting,
    this.loading = false,
    this.error,
    this.onRetry,
    required this.onOpenAlerts,
    required this.onOpenLink,
    required this.onOpenChildren,
    required this.onOpenChild,
    this.onMessageTeacher,
    this.onAddChild,
  });

  final ParentOverviewData? data;
  final ParentHomeGreeting? greeting;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final void Function(int? childId) onOpenAlerts;
  final VoidCallback onOpenLink;
  final VoidCallback onOpenChildren;
  final ValueChanged<ParentChildOverview> onOpenChild;

  /// "Message the teacher" for a child (a course preselected or null); null → the message sheet itself.
  final void Function(ParentChildOverview child, int? courseId)? onMessageTeacher;

  /// "Add your child" on the empty page; null = not offered.
  final VoidCallback? onAddChild;

  @override
  State<ParentOverviewBody> createState() => _ParentOverviewBodyState();
}

class _ParentOverviewBodyState extends State<ParentOverviewBody> {
  int? _local;
  bool _localPicked = false;

  static bool get _pulseOn => !AppConfig.disableList.contains('parent.insights');

  void _select(int? id) {
    final kids = PaKids.maybeOf(context, listen: false);
    if (kids != null) {
      kids.select(id);
    } else {
      setState(() {
        _local = id;
        _localPicked = true;
      });
    }
  }

  /// The child the page is about, or null for "all". One child only: that child.
  ParentChildOverview? _current(ParentOverviewData d, PaKids? kids) {
    if (d.children.isEmpty) return null;
    if (d.children.length == 1) return d.children.first;
    // outside the dashboard the first child is shown until a chip is picked (as the old home did)
    final first = d.children.first;
    final id = kids != null ? kids.selected : (_localPicked ? _local : (_pulseOn && first.pulse != null ? first.id : null));
    if (id == null) return null;
    for (final c in d.children) {
      if (c.id == id) return c;
    }
    return null;
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

  String? get _greetingLine {
    final g = widget.greeting;
    if (g == null) return null;
    return HomeHeader.greetingLine(g.name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final kids = PaKids.maybeOf(context);
    final d = widget.data;
    final wide = paWide(context);
    final gutter = wide ? AppSpace.lg : AppSpace.md;

    Widget frame(Widget hero, List<Widget> body) {
      Widget content = PaStack(children: body);
      // switching children crossfades the picture in place (it is the same page, another child)
      content = AnimatedSwitcher(
        duration: AppMotion.of(context).base,
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
        child: KeyedSubtree(key: ValueKey('pa.today.${kids?.selected ?? _local}'), child: content),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // a preview of the body alone (no dashboard band): the switcher above the hero
        if (kids == null && d != null && d.children.length > 1)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.xs, gutter, AppSpace.xs),
            child: ParentChildSwitcher(children: d.children, selectedId: _current(d, null)?.id, onSelect: _select),
          ),
        AppHeroOverlap(
          hero: ValueListenableBuilder<int>(valueListenable: AppTime.version, builder: (_, _, _) => hero),
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.content.max), child: content)),
          ),
        ),
      ]);
    }

    if (d == null) {
      final hero = AppHero(kicker: _greetingLine, title: 'pa_today_title'.tr);
      if (widget.loading) return frame(hero, const [AppListSkeleton(items: 3, padding: EdgeInsets.zero)]);
      return frame(hero, [ErrorRetry(message: widget.error ?? 'generic_error'.tr, onRetry: widget.onRetry ?? () {})]);
    }
    if (d.children.isEmpty) return _empty(d, frame);

    final ch = _current(d, kids);
    final pulse = _pulseOn ? ch?.pulse : null;
    if (ch != null && pulse != null) return _one(ch, pulse, frame, wide);
    return _all(d, ch, frame);
  }

  // ── no child linked yet ─────────────────────────────────────────────────

  Widget _empty(ParentOverviewData d, Widget Function(Widget, List<Widget>) frame) {
    final pending = d.pendingRequests;
    final name = widget.greeting?.name.trim() ?? '';
    final hero = AppHero(
      kicker: name.isEmpty ? null : paFmt('pa_hello_name', {'name': name}),
      title: 'pa_empty_title'.tr,
      subtitle: 'pa_empty_sub'.tr,
    );
    final c = context.colors;
    return frame(hero, [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: AppIconBox(icon: Icons.link_rounded, size: AppDashSize.disc)),
          const SizedBox(height: AppSpace.sm),
          Text('pa_my_kids_day'.tr, textAlign: TextAlign.center, style: AppType.pageTitle(context)),
          const SizedBox(height: AppSpace.xs),
          Text(
            pending > 0 ? paFmt('pa_requests_pending', {'n': appDigits('$pending')}) : 'pa_empty_card_sub'.tr,
            textAlign: TextAlign.center,
            style: AppType.body(context).copyWith(color: c.textMedium),
          ),
          const SizedBox(height: AppSpace.md),
          PaStep(n: 1, title: 'pa_step1_title'.tr, text: 'pa_step1_text'.tr),
          const SizedBox(height: AppSpace.sm),
          PaStep(n: 2, title: 'pa_step2_title'.tr, text: 'pa_step2_text'.tr),
          const SizedBox(height: AppSpace.sm),
          PaStep(n: 3, title: 'pa_step3_title'.tr, text: 'pa_step3_text'.tr),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(
            key: const ValueKey('pa.today.link'),
            label: pending > 0 ? 'pa_my_requests'.tr : 'pa_link_child'.tr,
            icon: Icons.link_rounded,
            expand: true,
            onPressed: widget.onOpenLink,
          ),
          if (widget.onAddChild != null) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(
              key: const ValueKey('pa.today.add'),
              label: 'pa_add_child_cta'.tr,
              icon: Icons.person_add_alt_1_rounded,
              onPressed: widget.onAddChild,
            ),
          ],
        ]),
      ),
    ]);
  }

  // ── one child ───────────────────────────────────────────────────────────

  Widget _one(ParentChildOverview ch, ParentPulse p, Widget Function(Widget, List<Widget>) frame, bool wide) {
    final canMessage = parentMessageTeacherOn && p.teachers.isNotEmpty;
    final hero = ParentPulseHero(
      child: ch,
      pulse: p,
      greeting: _greetingLine,
      onOpenReport: () => widget.onOpenChild(ch),
      onMessage: canMessage ? () => _message(ch, null) : null,
    );
    final insights = ParentInsightsCard(childName: ch.name, insights: p.insights, canMessage: canMessage, onAction: (i) => _act(ch, i));
    final week = ParentWeekCard(events: p.upcoming);
    final subjects = p.subjects.isEmpty
        ? null
        : ParentSubjectsCard(subjects: p.subjects, onMessage: canMessage ? (s) => _message(ch, s.courseId) : null);
    final r = p.roadmap;
    final road = r == null ? null : (r.total > 0 ? ParentPathCard(roadmap: r) : ParentRoadmapCard(roadmap: r, childName: ch.name));
    final marks = ch.latestMarks.isEmpty && ch.nextExam == null ? null : ParentMarksCard(child: ch);
    final six = wide ? ParentSixWeeksCard(pulse: p) : null;
    return frame(hero, [
      PaColumns(start: [insights, week, ?subjects], end: [?six, ?road, ?marks]),
    ]);
  }

  // ── every child ─────────────────────────────────────────────────────────

  Widget _all(ParentOverviewData d, ParentChildOverview? only, Widget Function(Widget, List<Widget>) frame) {
    final shown = only == null ? d.children : [only];
    final now = DateTime.now().toUtc();
    final live = [
      for (final c in d.children)
        for (final s in c.todaySessions)
          if (s.startsAt != null && s.endsAt != null && !now.isBefore(s.startsAt!) && now.isBefore(s.endsAt!)) (c, s),
    ];
    final today = d.sessionsToday;
    final classes = countText(today,
        ar0: 'ما فيه حصص اليوم', ar1: 'حصة واحدة اليوم', ar2: 'حصتين اليوم', arFew: '{n} حصص اليوم', arMany: '{n} حصة اليوم',
        en0: 'no classes today', en1: '1 class today', en: '{n} classes today');
    final title = paFmt(live.isEmpty ? 'pa_all_title' : 'pa_all_title_live', {'classes': appDigits(classes)});
    final atts = [for (final c in d.children) ?c.attendancePct30d];
    final avg = atts.isEmpty ? null : (atts.reduce((a, b) => a + b) / atts.length).round();
    final sub = [
      if (live.isNotEmpty) paFmt('pa_all_live_line', {'name': live.first.$1.name.split(' ').first, 'title': live.first.$2.title}),
      if (d.children.length > 1) 'pa_all_hint'.tr,
    ].join(' ');
    final hero = AppHero(
      kicker: _greetingLine,
      title: title,
      subtitle: sub.isEmpty ? null : sub,
      actions: [
        AppButton.secondary(
          key: const ValueKey('pa.today.children'),
          label: 'pa_tab_kids'.tr,
          trailingIcon: Icons.chevron_right_rounded,
          onPressed: widget.onOpenChildren,
        ),
      ],
      stats: [
        AppHeroStat(label: 'pa_linked_kids'.tr, value: appDigits('${d.children.length}')),
        AppHeroStat(label: 'pa_classes_today'.tr, value: appDigits('$today')),
        AppHeroStat(label: 'pa_avg_attendance'.tr, value: avg == null ? '—' : appDigits('$avg%')),
        AppHeroStat(label: 'pa_open_alerts'.tr, value: appDigits('${d.alertsTotal}'), onTap: () => widget.onOpenAlerts(null)),
      ],
    );
    return frame(hero, [
      for (final x in shown)
        ParentChildOverviewCard(child: x, onOpen: () => widget.onOpenChild(x), onOpenAlerts: () => widget.onOpenAlerts(x.id)),
    ]);
  }
}

/// The newest marks and the next exam of one child (the side column).
class ParentMarksCard extends StatelessWidget {
  const ParentMarksCard({super.key, required this.child});
  final ParentChildOverview child;

  @override
  Widget build(BuildContext context) {
    final exam = child.nextExam;
    return AppCard(
      title: 'pa_latest_marks'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (child.latestMarks.isEmpty)
          Text('pl_ov_no_marks'.tr, style: AppType.body(context).copyWith(color: context.colors.textMedium))
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

/// One child's day in the "all" view: a card in the child's own tone — who · courses and classes today · attendance
/// and open alerts · today's classes · newest marks · next exam; the card opens the child's report.
class ParentChildOverviewCard extends StatelessWidget {
  const ParentChildOverviewCard({super.key, required this.child, required this.onOpen, required this.onOpenAlerts});

  final ParentChildOverview child;
  final VoidCallback onOpen;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final ch = child;
    final att = ch.attendancePct30d;
    final exam = ch.nextExam;
    final hot = ch.openAlerts > 0;
    final tone = paKidTone(context, ch.id);
    final courses = countText(ch.courses,
        ar0: 'ما فيه دورات', ar1: 'دورة واحدة', ar2: 'دورتين', arFew: '{n} دورات', arMany: '{n} دورة',
        en0: 'no courses', en1: '1 course', en: '{n} courses');
    final classes = countText(ch.todaySessions.length,
        ar0: 'ما فيه حصص اليوم', ar1: 'حصة واحدة اليوم', ar2: 'حصتين اليوم', arFew: '{n} حصص اليوم', arMany: '{n} حصة اليوم',
        en0: 'no classes today', en1: '1 class today', en: '{n} classes today');
    return AppCard(
      variant: AppCardVariant.tint,
      tone: tone,
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: ch.name,
          child: Row(children: [
            PaKidAvatar(id: ch.id, name: ch.name, size: AppDashSize.avatarSm),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                Text(appDigits('$courses${paT('، ', ', ')}$classes'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(
            label: att == null ? 'pl_ov_attendance_none'.tr : paFmt('pa_attendance_month', {'n': appDigits('$att%')}),
            tone: att == null ? AppTone.neutral : (att >= 75 ? AppTone.success : (att >= 50 ? AppTone.warning : AppTone.danger)),
          ),
          Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: onOpenAlerts,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Center(
                  widthFactor: 1,
                  child: AppStatusBadge(
                    label: hot ? paFmt('pa_open_alerts_n', {'n': appDigits('${ch.openAlerts}')}) : 'pl_ov_alerts_none'.tr,
                    tone: hot ? AppTone.danger : AppTone.success,
                  ),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text('pa_classes_today'.tr, style: AppType.tileTitle(context)),
        if (ch.todaySessions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text('sv_pl_ov_no_sessions'.tr, style: AppType.meta(context)),
          )
        else
          for (final (i, s) in ch.todaySessions.indexed) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: context.colors.kit.line),
            ParentEventLine(event: s),
          ],
        if (ch.latestMarks.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text('pa_latest_marks'.tr, style: AppType.tileTitle(context)),
          for (final m in ch.latestMarks) _MarkLine(mark: m),
        ],
        const SizedBox(height: AppSpace.xs),
        if (exam == null)
          Text('pl_ov_no_exam'.tr, style: AppType.meta(context))
        else
          _NextExam(exam: exam),
      ]),
    );
  }
}

/// The next exam: a calendar glyph · "Next exam · name · when".
class _NextExam extends StatelessWidget {
  const _NextExam({required this.exam});
  final ParentNextExam exam;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(Icons.event_note_rounded, size: AppIconSize.sm, color: c.kit.warn.ink),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(
          '${'pl_ov_next_exam'.tr} · ${exam.name}${exam.startsAt == null ? '' : ' · ${AppTime.dateTime(exam.startsAt!)}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.label(context).copyWith(color: c.textDark),
        ),
      ),
    ]);
  }
}

/// One mark: the figure as a tag in its score tone · course · exam.
class _MarkLine extends StatelessWidget {
  const _MarkLine({required this.mark});
  final ParentMark mark;

  static const double _figureWidth = AppTouch.primary;

  @override
  Widget build(BuildContext context) {
    final pct = mark.percentage;
    final tone = pct == null
        ? AppTone.neutral
        : (mark.passed == false ? AppTone.danger : (pct >= 75 ? AppTone.success : (pct >= 50 ? AppTone.warning : AppTone.danger)));
    final label = [if (mark.course.isNotEmpty) mark.course, mark.exam].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        SizedBox(
          width: _figureWidth,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppStatusBadge(label: pct == null ? '—' : appDigits('${pct.round()}%'), tone: tone),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context))),
      ]),
    );
  }
}

/// The greeting's name: the first name of [full] (titles dropped), or [fallback] when there is none (D-750).
String _firstOr(String? full, String fallback) {
  final first = SplashState.firstName(full ?? '');
  return first.isEmpty ? fallback : first;
}
