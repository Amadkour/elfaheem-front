// lib/features/courses/student/details/subject_guest_space.dart
//
// The subject page before the student subscribes (SubjectProfile rows 1-2, SubjMGuest / SubjWGuest; BK). Plain
// values, no provider: the course screen (`course_detail_screen.dart`) fills it for a visitor and a student who is
// not enrolled.
//
//   hero    the learn area's band: the spiral book in the subject's colour with "اضغط على الكتاب" (tap → the
//           spread with the facts and the first lessons; a phone opens it in a sheet), the grade and the kind pills,
//           the title, "المعلم" + the name, the lessons and rating chips
//   body    the price card ("١٩٩ ريال في الشهر", "احجز المادة", "شوف مقدمة المادة"), the extra cards (a booking
//           of this subject, the payment status, a live class), "وش بتاخذ في المادة", the teacher, "تشمل",
//           "المزيد" (the course's other pages: عن الدورة, the exams, the reviews, the path …)
//   phone   one column, the forward button pinned at the bottom; from 1000 px two columns
//
// Never a student count (privacy). Wording: "دورة", "حصة" / "درس", never "جلسة" or "كورس".
// Motion (subject page): M12 on the book, M1 on the cards, M9 on taps.
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
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';

class SubjectGuestSpace extends StatefulWidget {
  const SubjectGuestSpace({
    super.key,
    required this.title,
    required this.teacher,
    this.subject,
    this.grade,
    this.kindLabel,
    this.teacherImageUrl,
    this.teacherYears,
    this.teacherBio,
    this.onTeacher,
    this.lessonsCount = 0,
    this.rating,
    this.facts = const [],
    this.bookNote,
    this.steps = const [],
    this.price,
    this.priceNote,
    this.priceBlock,
    this.primaryLabel,
    this.onPrimary,
    this.notes = const [],
    this.onPreview,
    this.includes = const [],
    this.extras = const [],
    this.more = const [],
    this.menu = const [],
    this.onBack,
    this.onRefresh,
  });

  final String title;
  final String? subject, grade;

  /// "حصص مباشرة ودروس مسجّلة" — what the course is made of.
  final String? kindLabel;
  final String teacher;
  final String? teacherImageUrl;
  final int? teacherYears;
  final String? teacherBio;
  final VoidCallback? onTeacher;
  final int lessonsCount;
  final String? rating;
  final List<SubjectFact> facts;

  /// The open book's line under the facts ("مع كل درس دفتر وتمارين").
  final String? bookNote;

  /// "وش بتاخذ في المادة": the first steps of the path (the card shows [kSubjectPathSteps]).
  final List<SubjectStep> steps;

  /// "١٩٩ ريال" + "في الشهر"; or [priceBlock] (the course's own price block with its discount).
  final String? price, priceNote;
  final Widget? priceBlock;

  /// "احجز المادة"; null (or [onPrimary] null) → no button (a note in [notes] says why).
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// Above the buttons: the payment status, a refusal, a plan that ended.
  final List<Widget> notes;

  /// "شوف مقدمة المادة"; null hides it.
  final VoidCallback? onPreview;

  /// "تشمل": what the subject includes, a few words each.
  final List<String> includes;

  /// Cards under the price card (a booking of this subject, the archive, a live class …).
  final List<Widget> extras;
  final List<CourseSpaceAction> more;
  final List<CourseSpaceTopAction> menu;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;

  @override
  State<SubjectGuestSpace> createState() => _SubjectGuestSpaceState();
}

class _SubjectGuestSpaceState extends State<SubjectGuestSpace> {
  bool _open = false;

  SubjectGuestSpace get w => widget;

  Widget _book({required bool open, required Size size, bool chip = true}) => SubjectBook(
        title: w.title,
        subject: w.subject,
        grade: w.grade,
        teacher: w.teacher,
        facts: w.facts,
        note: w.bookNote,
        toc: [for (final s in w.steps.take(4)) s.title],
        open: open,
        size: size,
        showOpenChip: chip,
      );

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
            Center(child: FittedBox(fit: BoxFit.scaleDown, child: _book(open: true, size: kSubjectBookSheet))),
          ],
        ),
      ),
    );
  }

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
                child: twoCols ? _twoColumns(phone: phone) : _stack([..._mainCards(phone: phone), ..._sideCards()]),
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
          final buy = phone && w.primaryLabel != null && w.onPrimary != null;
          if (!buy) return view;
          return Column(children: [Expanded(child: view), _footer(context)]);
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
    final book = Semantics(
      button: true,
      label: 'sb_subj_tap_book_hint'.tr,
      child: GestureDetector(
        onTap: () => _tapBook(phone),
        child: AppWobble(
          child: phone
              // the wide book drawn smaller: every line of its cover stays (the phone size drops them)
              ? SizedBox.fromSize(
                  size: kSubjectBookSheet,
                  child: FittedBox(child: _book(open: false, size: kSubjectBookWide)),
                )
              : _book(open: _open, size: kSubjectBookWide),
        ),
      ),
    );
    final bookBlock = Column(mainAxisSize: MainAxisSize.min, children: [
      book,
      const SizedBox(height: AppSpace.sm),
      if (!_open || phone) const FittedBox(fit: BoxFit.scaleDown, child: SubjectBookHint()),
    ]);
    final info = _info(context, phone: phone);
    final content = phone
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: bookBlock),
            const SizedBox(height: AppSpace.lg),
            info,
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: info),
            const SizedBox(width: AppSpace.xxl),
            Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.md), child: bookBlock),
          ]);
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bar, content]),
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
          if (w.grade != null && w.grade!.isNotEmpty) SubjectHeroPill(label: w.grade!),
          if (w.kindLabel != null) SubjectHeroPill(label: w.kindLabel!),
        ]),
        const SizedBox(height: AppSpace.sm),
        Semantics(
          header: true,
          child: Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.display(context).copyWith(color: c.onHero)),
        ),
        const SizedBox(height: AppSpace.sm),
        InkWell(
          onTap: w.onTeacher,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SubjectAvatar(name: w.teacher, imageUrl: w.teacherImageUrl, ring: c.heroGlassBorder,
                size: phone ? AppDashSize.avatarSm - AppSpace.xxs : AppDashSize.ringSm),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('bk_teacher_label'.tr, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                Text(w.teacher, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: (phone ? AppType.section(context) : AppType.bodyStrong(context)).copyWith(color: c.onHero)),
              ]),
            ),
          ]),
        ),
        if (w.lessonsCount > 0 || w.rating != null) ...[
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

  Widget _priceCard({required bool phone}) {
    final c = context.colors;
    final price = w.priceBlock ??
        (w.price == null
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(w.price!, style: AppType.figureLarge(context).copyWith(color: c.textDark)),
                if (w.priceNote != null) Text(w.priceNote!, style: AppType.body(context).copyWith(color: c.textMedium)),
              ]));
    final preview = w.onPreview == null
        ? null
        : AppButton.secondary(
            label: 'bk_preview'.tr,
            icon: Icons.play_arrow_rounded,
            size: AppButtonSize.lg,
            expand: phone,
            onPressed: w.onPreview,
          );
    final buy = !phone && w.primaryLabel != null && w.onPrimary != null
        ? AppButton.hot(label: w.primaryLabel!, trailingIcon: Icons.arrow_forward_rounded, size: AppButtonSize.lg, onPressed: w.onPrimary)
        : null;
    if (price == null && preview == null && buy == null && w.notes.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) ...[
          ?price,
          for (final n in w.notes) ...[const SizedBox(height: AppSpace.sm), n],
          if (preview != null) ...[const SizedBox(height: AppSpace.md), preview],
        ] else ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.lg,
            runSpacing: AppSpace.md,
            children: [
              ?price,
              Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [?buy, ?preview]),
            ],
          ),
          for (final n in w.notes) ...[const SizedBox(height: AppSpace.sm), n],
        ],
      ]),
    );
  }

  Widget _pathCard() {
    final shown = w.steps.take(kSubjectPathSteps).toList();
    final c = context.colors;
    return AppCard(
      title: 'bk_path_guest'.tr,
      action: Text('bk_path_guest_note'.tr, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, s) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          AppFlipIn(index: i, group: 'guest_path', child: SubjectStepRow(key: ValueKey('guest_step_${s.id}'), step: s)),
        ],
      ]),
    );
  }

  Widget _includesCard() {
    final c = context.colors;
    return AppCard(
      title: 'bk_includes'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, t) in w.includes.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_rounded, size: AppIconSize.md, color: c.kit.ok.ink),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(t, style: AppType.body(context))),
          ]),
        ],
      ]),
    );
  }

  List<Widget> _mainCards({required bool phone}) => [
        _priceCard(phone: phone),
        ...w.extras,
        if (w.steps.isNotEmpty) _pathCard(),
      ];

  List<Widget> _sideCards() => [
        if (w.teacher.isNotEmpty)
          SubjectTeacherCard(
            name: w.teacher,
            imageUrl: w.teacherImageUrl,
            years: w.teacherYears,
            bio: w.teacherBio,
            onOpen: w.onTeacher,
          ),
        if (w.includes.isNotEmpty) _includesCard(),
        if (w.more.isNotEmpty) SubjectMoreCard(items: w.more),
      ];

  Widget _stack(List<Widget> cards, {int from = 0}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.md),
            AppFlipIn(index: from + i, group: 'guest_cards', child: card),
          ],
        ],
      );

  Widget _twoColumns({required bool phone}) {
    final main = _mainCards(phone: phone);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _stack(main)),
      const SizedBox(width: AppSpace.lg),
      SizedBox(width: kSubjectAsideW, child: _stack(_sideCards(), from: main.length)),
    ]);
  }

  Widget _footer(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.kit.line, width: AppBorder.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
          child: Row(children: [
            if (w.price != null) ...[
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (w.priceNote != null) Text(w.priceNote!, style: AppType.meta(context)),
                Text(w.price!, style: AppType.figure(context).copyWith(color: c.textDark)),
              ]),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: AppButton.hot(
                label: w.primaryLabel!,
                trailingIcon: Icons.arrow_forward_rounded,
                size: AppButtonSize.lg,
                expand: true,
                onPressed: w.onPrimary,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
