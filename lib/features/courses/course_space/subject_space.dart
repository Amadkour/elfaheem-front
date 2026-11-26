// lib/features/courses/course_space/subject_space.dart
//
// The enrolled student's subject page (SubjectProfile, S-B; rows 3-8 of SCREEN_MAP "صفحة المادة"). Plain values,
// no provider: the student's course screen (`course_detail_screen.dart`) fills it. A teacher and a visitor who is
// not enrolled keep `CourseSpace`.
//
//   hero    the learn area's band (drifting shapes): the spiral book in the subject's colour (tap → the spread with
//           the facts and the path; a phone opens it in a sheet), "مشترك" + the grade, the title, "معلمك", the
//           mode pill, the lessons and rating chips
//   body    phone: one column — the live card (or the next class), the extra cards, "مسارك في المادة", the teacher,
//           the tools, "المزيد"; from 1000 px two columns: the live card and the path at the start, the teacher, the
//           tools and "المزيد" at the end
//
// Slots the booking group (BK) fills later: [SubjectSpace.onChat], [onBot], [onSchedule] (null = the row and the
// teacher card's button are hidden), [extras] (cards under the live card).
//
// Motion (DESIGN_SYSTEM §1.3, subject page): M12 on the book, M1 on the cards and steps, M8 on the join button, M9
// on taps; the hero's M6 wipe is off (the page's hero move is M1).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart'
    show CourseSpaceAction, CourseSpaceTopAction;
import 'package:flutter_education_app/features/courses/course_space/subject_space_parts.dart';

export 'package:flutter_education_app/features/courses/course_space/subject_space_parts.dart';

/// The side column's width from [Breakpoints.desktop].
const double kSubjectAsideW = 350;

/// How many steps the path card shows (the lessons page shows them all).
const int kSubjectPathSteps = 6;

/// The live class now, or null.
class SubjectLive {
  const SubjectLive({required this.title, required this.onJoin, this.startedAgo});

  final String title;
  final String? startedAgo;
  final VoidCallback onJoin;
}

/// The next class, or null.
class SubjectNext {
  const SubjectNext({required this.when, this.title, this.until, this.onJoin, this.note});

  final String when;
  final String? title;
  final DateTime? until;
  final VoidCallback? onJoin;
  final String? note;
}

class SubjectSpace extends StatefulWidget {
  const SubjectSpace({
    super.key,
    required this.title,
    required this.teacher,
    this.subject,
    this.grade,
    this.teacherImageUrl,
    this.teacherYears,
    this.teacherBio,
    this.onTeacher,
    this.mode,
    this.lessonsCount = 0,
    this.rating,
    this.facts = const [],
    this.scheduleNote,
    this.live,
    this.next,
    this.steps = const [],
    this.done = 0,
    this.total = 0,
    this.onAllLessons,
    this.onChat,
    this.onBot,
    this.onNotes,
    this.onSchedule,
    this.onExams,
    this.examsNote,
    this.onAttendance,
    this.attendanceNote,
    this.extras = const [],
    this.more = const [],
    this.menu = const [],
    this.onBack,
    this.onRefresh,
  });

  final String title;

  /// The server's subject (slug or name): the book's colour. Null → the category / the "other" colour.
  final String? subject;
  final String? grade;
  final String teacher;
  final String? teacherImageUrl;
  final int? teacherYears;
  final String? teacherBio;
  final VoidCallback? onTeacher;

  /// "مجموعة، عن بعد" — only what the course payload says.
  final String? mode;
  final int lessonsCount;

  /// The average rating, already formatted ("4.8"); null hides the chip and the fact.
  final String? rating;
  final List<SubjectFact> facts;
  final String? scheduleNote;
  final SubjectLive? live;
  final SubjectNext? next;

  /// The whole path in order (the card shows a window of [kSubjectPathSteps] around the current step).
  final List<SubjectStep> steps;
  final int done, total;
  final VoidCallback? onAllLessons;

  // ── slots (BK) ─────────────────────────────────────────────────────────────
  final VoidCallback? onChat;
  final VoidCallback? onBot;
  final VoidCallback? onNotes;
  final VoidCallback? onSchedule;
  final VoidCallback? onExams;
  final String? examsNote;
  final VoidCallback? onAttendance;
  final String? attendanceNote;

  /// Cards under the live / next card (Play now, the plan ending, the archive, attendance check-in …).
  final List<Widget> extras;

  /// "المزيد": the course's other pages.
  final List<CourseSpaceAction> more;

  /// The hero's ⋮ menu (share, favourite, ask the documents, my analytics, support, refresh).
  final List<CourseSpaceTopAction> menu;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;

  /// The steps the path card shows: from the step before the current one, [kSubjectPathSteps] long.
  static List<SubjectStep> pathWindow(List<SubjectStep> steps) {
    if (steps.length <= kSubjectPathSteps) return steps;
    var at = steps.indexWhere((s) => s.state == SubjectStepState.live || s.state == SubjectStepState.current);
    if (at < 0) at = steps.indexWhere((s) => s.state != SubjectStepState.done);
    if (at < 0) at = steps.length - 1;
    final start = (at - 1).clamp(0, steps.length - kSubjectPathSteps);
    return steps.sublist(start, start + kSubjectPathSteps);
  }

  @override
  State<SubjectSpace> createState() => _SubjectSpaceState();
}

class _SubjectSpaceState extends State<SubjectSpace> {
  bool _open = false;

  SubjectSpace get w => widget;

  double? get _progress => w.total > 0 ? (w.done / w.total).clamp(0, 1).toDouble() : null;

  String get _pathCount => sbFill('sb_subj_path_count', {'done': sbDigits(w.done), 'total': sbDigits(w.total)});

  List<String> get _toc => [for (final s in w.steps.take(4)) s.title];

  void _tapBook(bool phone) {
    if (!phone) {
      setState(() => _open = !_open);
      return;
    }
    showAppSheet<void>(
      context,
      (ctx) => AppAreaScope(
        area: AppArea.learn,
        child: AppSheetContent(
          title: w.title,
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _book(open: true, size: kSubjectBookSheet),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _book({required bool open, required Size size}) => SubjectBook(
        title: w.title,
        subject: w.subject,
        grade: w.grade,
        teacher: w.teacher,
        facts: w.facts,
        note: w.scheduleNote,
        progress: _progress,
        progressLabel: w.total > 0 ? _pathCount : null,
        toc: _toc,
        open: open,
        size: size,
        showOpenChip: size.width >= kSubjectBookWide.width,
      );

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: AppArea.learn,
        child: LayoutBuilder(builder: (context, box) {
          final width = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
          final phone = width < Breakpoints.mobile;
          final twoCols = width >= Breakpoints.desktop;
          final gutter = AppSpace.gutter(width);
          final body = Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.content.max),
                child: twoCols ? _twoColumns() : _oneColumn(),
              ),
            ),
          );
          Widget view = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: AppHeroOverlap(hero: _hero(context, phone: phone), body: body)),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
            ],
          );
          if (w.onRefresh != null) view = AppRefresh(onRefresh: w.onRefresh!, child: view);
          return view;
        }),
      );

  // ── hero ───────────────────────────────────────────────────────────────────

  Widget _hero(BuildContext context, {required bool phone}) {
    final c = context.colors;
    final menu = [
      for (final a in w.menu)
        if (a.featureKey == null || !AppConfig.disableList.contains(a.featureKey)) a,
    ];
    final bar = Row(children: [
      if (w.onBack != null) AppBackButton(onPressed: w.onBack, onHero: true),
      const Spacer(),
      if (menu.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'sb_subj_menu'.tr,
          icon: Icon(Icons.more_vert_rounded, color: c.onHero),
          onSelected: (i) => menu[i].onTap(),
          itemBuilder: (_) => [
            for (final (i, a) in menu.indexed)
              PopupMenuItem<int>(
                value: i,
                child: Row(children: [
                  Icon(a.icon, size: AppIconSize.md, color: a.color ?? c.textMedium),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(child: Text(a.tooltip, style: AppType.row(context))),
                ]),
              ),
          ],
        ),
    ]);
    final info = _info(context, phone: phone);
    final bookSize = phone ? kSubjectBookPhone : kSubjectBookWide;
    final book = Semantics(
      button: true,
      label: 'sb_subj_tap_book_hint'.tr,
      child: GestureDetector(
        onTap: () => _tapBook(phone),
        child: AppWobble(child: _book(open: _open && !phone, size: bookSize)),
      ),
    );
    final Widget content = phone
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.xs), child: book),
              const SizedBox(width: AppSpace.lg),
              Expanded(child: info),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.md), child: book),
                const SizedBox(height: AppSpace.md),
                if (!_open) const SubjectBookHint(),
              ]),
              const SizedBox(width: AppSpace.xxl),
              Expanded(child: info),
            ],
          );
    return AppHeroSurface(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            phone ? AppSpace.md : AppSpace.lg,
            AppSpace.xs,
            phone ? AppSpace.md : AppSpace.lg,
            (phone ? AppHeroMetrics.overlapStudentPhone : AppHeroMetrics.overlapWide) + AppSpace.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.content.max),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [bar, SizedBox(height: phone ? AppSpace.xs : AppSpace.md), content],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(BuildContext context, {required bool phone}) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          SubjectHeroPill(label: 'sb_subj_enrolled'.tr, icon: Icons.check_rounded, tone: c.kit.ok),
          if (!phone && w.grade != null && w.grade!.isNotEmpty) SubjectHeroPill(label: w.grade!),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(
          w.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (phone ? AppType.headline(context) : AppType.display(context)).copyWith(color: c.onHero),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: w.onTeacher,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SubjectAvatar(name: w.teacher, imageUrl: w.teacherImageUrl, ring: c.heroGlassBorder),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('sb_subj_your_teacher'.tr, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                    Text(w.teacher, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
                  ]),
                ),
              ]),
            ),
            if (!phone && w.mode != null) SubjectHeroPill(label: w.mode!, warm: true),
          ],
        ),
        if (!phone && (w.lessonsCount > 0 || w.rating != null)) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (w.lessonsCount > 0) SubjectHeroPill(label: sbLessons(w.lessonsCount), icon: Icons.menu_book_outlined),
            if (w.rating != null)
              SubjectHeroPill(label: sbFill('sb_subj_rating', {'n': appDigits(w.rating!)}), icon: Icons.star_rounded),
          ]),
        ],
      ],
    );
  }

  // ── body ───────────────────────────────────────────────────────────────────

  List<Widget> _mainCards() => [
        if (w.live != null)
          SubjectLiveCard(
            title: w.live!.title,
            teacher: w.teacher,
            teacherImageUrl: w.teacherImageUrl,
            startedAgo: w.live!.startedAgo,
            onJoin: w.live!.onJoin,
          )
        else if (w.next != null)
          SubjectNextCard(
            when: w.next!.when,
            title: w.next!.title,
            until: w.next!.until,
            onJoin: w.next!.onJoin,
            note: w.next!.note,
          ),
        ...w.extras,
        if (w.steps.isNotEmpty) _pathCard(),
      ];

  List<Widget> _sideCards() => [
        SubjectTeacherCard(
          name: w.teacher,
          imageUrl: w.teacherImageUrl,
          years: w.teacherYears,
          bio: w.teacherBio,
          onChat: w.onChat,
          onOpen: w.onTeacher,
        ),
        SubjectToolsCard(tools: [
          if (w.onBot != null)
            SubjectTool(icon: Icons.auto_awesome_outlined, label: 'sb_subj_bot'.tr, onTap: w.onBot!, accent: AppAccent.grape),
          if (w.onNotes != null)
            SubjectTool(
              icon: Icons.edit_outlined,
              label: 'sb_subj_notes'.tr,
              onTap: w.onNotes!,
              accent: AppAccent.sun,
              featureKey: 'course.notebook',
            ),
          if (w.onSchedule != null)
            SubjectTool(icon: Icons.calendar_month_outlined, label: 'sb_subj_schedule'.tr, onTap: w.onSchedule!, accent: AppAccent.sky),
          if (w.onExams != null)
            SubjectTool(
              icon: Icons.assignment_turned_in_outlined,
              label: 'sb_subj_exams'.tr,
              note: w.examsNote,
              onTap: w.onExams!,
              accent: AppAccent.mint,
              featureKey: 'exams',
            ),
          if (w.onAttendance != null)
            SubjectTool(
              icon: Icons.task_alt_rounded,
              label: 'sb_subj_attendance'.tr,
              note: w.attendanceNote,
              onTap: w.onAttendance!,
              accent: AppAccent.mint,
              featureKey: 'course_hero.attendance',
            ),
        ]),
        if (w.more.isNotEmpty) SubjectMoreCard(items: w.more),
      ];

  Widget _stack(List<Widget> cards, {int from = 0}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.md),
            AppFlipIn(index: from + i, group: 'subject_cards', child: card),
          ],
        ],
      );

  Widget _oneColumn() {
    final main = _mainCards();
    return _stack([...main, ..._sideCards()]);
  }

  Widget _twoColumns() {
    final main = _mainCards();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _stack(main)),
        const SizedBox(width: AppSpace.lg),
        SizedBox(width: kSubjectAsideW, child: _stack(_sideCards(), from: main.length)),
      ],
    );
  }

  Widget _pathCard() {
    final shown = SubjectSpace.pathWindow(w.steps);
    return AppCard(
      title: 'sb_subj_path'.tr,
      action: w.total > 0
          ? _CountAction(children: [
              AppProgressRing(value: _progress ?? 0, showPercent: false, size: AppIconSize.xl),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text(_pathCount, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: context.colors.kit.warmTone.ink, fontWeight: FontWeight.w600))),
            ])
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in shown.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            AppFlipIn(index: i, group: 'subject_path', child: SubjectStepRow(key: ValueKey('subject_step_${s.id}'), step: s)),
          ],
          if (w.onAllLessons != null && w.steps.length > shown.length) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(label: 'sb_subj_all_lessons'.tr, onPressed: w.onAllLessons),
            ),
          ],
        ],
      ),
    );
  }
}

/// A card head's count (ring + "1 من 24 درس"): at most 45 % of the card, so a long count never pushes the title out.
class _CountAction extends StatelessWidget {
  const _CountAction({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .45),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}
