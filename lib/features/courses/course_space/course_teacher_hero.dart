// lib/features/courses/course_space/course_teacher_hero.dart
//
// The teacher's header of the one course page (Tea1Course, redesign T1): the teacher role's hero band, the crumb
// "My courses > title", the book cover on the end side, the badges, the title, the teacher line, the figures as
// glass pills, the ONE call to action (New session) with Edit course · Share · More under it, and one quiet notice
// (a draft says why nobody sees it). Plain values only, no provider (the layout harness pumps it): the teacher's
// screen maps its course into [CourseTeacherHeroData] and hands the widget to `CourseSpace.heroOverride`; the
// student's and the visitor's header (CourseSpaceHero) is untouched.
//
//   phone    top bar (back · title · share · more) → crumb → [badges · title · teacher · pills | cover]
//            → New session (full width) → Edit · Share · More
//   desktop  crumb → [actions column | badges · title · line · teacher | cover] → the pills row
//
// Motion: the restrained teacher set only (M9 presses through the kit buttons); nothing loops.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart'
    show CourseSpaceBadge, CourseSpaceButton, CourseSpaceTopAction, CourseCover;

/// One figure of the pills row ("8 students", "24 sessions").
class CourseTeacherPill {
  const CourseTeacherPill({required this.icon, required this.value, required this.label, this.onTap});

  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;
}

/// Everything the teacher's header shows.
class CourseTeacherHeroData {
  const CourseTeacherHeroData({
    required this.title,
    required this.crumbRoot,
    this.subtitle,
    this.badges = const [],
    this.teacherName,
    this.teacherLine,
    this.teacherImageUrl,
    this.pills = const [],
    this.imageUrl = '',
    this.coverIcon = Icons.menu_book_rounded,
    this.primary,
    this.secondary,
    this.icons = const [],
    this.menu = const [],
    this.notice,
    this.onBack,
    this.onCrumb,
  });

  final String title;

  /// "My courses" (the crumb's first part; tapping it goes back).
  final String crumbRoot;
  final String? subtitle;
  final List<CourseSpaceBadge> badges;
  final String? teacherName;

  /// The teacher's second line after the name ("Grade 12 secondary").
  final String? teacherLine;
  final String? teacherImageUrl;
  final List<CourseTeacherPill> pills;
  final String imageUrl;
  final IconData coverIcon;
  final CourseSpaceButton? primary, secondary;

  /// Icon-only actions after Edit (Share).
  final List<CourseSpaceTopAction> icons;

  /// The ⋮ menu (refresh, ask the documents, Data Lab, the attendance switch …).
  final List<CourseSpaceTopAction> menu;
  final String? notice;
  final VoidCallback? onBack, onCrumb;
}

/// The cover of the hero: a book in the role's colours, or the course picture when it has one.
class CourseTeacherCover extends StatelessWidget {
  const CourseTeacherCover({super.key, required this.icon, this.imageUrl = ''});

  final IconData icon;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.card);
    final Widget face = imageUrl.isNotEmpty
        ? CourseCover(imageUrl: imageUrl)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [c.primaryLight, c.primary, c.accent],
              ),
            ),
            child: Center(child: Icon(icon, size: AppIconSize.xl, color: c.onHero)),
          );
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 0.78,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
            boxShadow: AppShadow.card(context),
          ),
          child: ClipRRect(borderRadius: radius, child: face),
        ),
      ),
    );
  }
}

class CourseTeacherHero extends StatelessWidget {
  const CourseTeacherHero({super.key, required this.data, this.wideAt = 720});

  final CourseTeacherHeroData data;

  /// From this width the actions move beside the title.
  final double wideAt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
        final wide = w >= wideAt;
        final top = wide ? 0.0 : MediaQuery.paddingOf(context).top;
        return AppHeroSurface(
          borderRadius: wide ? BorderRadius.circular(AppRadius.block) : BorderRadius.zero,
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.md, top + AppSpace.xs, AppSpace.md, AppSpace.lg),
            child: wide ? _wide(context, w - AppSpace.md * 2) : _narrow(context, w - AppSpace.md * 2),
          ),
        );
      });

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _topBar(BuildContext context) {
    final c = context.colors;
    final share = data.icons;
    return Row(children: [
      if (data.onBack != null) AppBackButton(onHero: true, onPressed: data.onBack),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: Text(data.title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
        ),
      ),
      for (final a in share) AppIconButton(icon: a.icon, tooltip: a.tooltip, onPressed: a.onTap, onHero: true),
      if (data.menu.isNotEmpty) _MoreMenu(actions: data.menu, onHero: true),
    ]);
  }

  Widget _crumb(BuildContext context) {
    final c = context.colors;
    final style = AppType.meta(context).copyWith(color: c.onHeroMuted);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        onTap: data.onCrumb ?? data.onBack,
        child: Text(data.crumbRoot, style: style),
      ),
      const SizedBox(width: AppSpace.xxs),
      Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.onHeroMuted),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(data.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
    ]);
  }

  Widget _badges() => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final b in data.badges) _Badge(badge: b),
      ]);

  Widget _teacher(BuildContext context) {
    final c = context.colors;
    final name = data.teacherName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    final line = [name, if (data.teacherLine != null && data.teacherLine!.isNotEmpty) data.teacherLine!].join('، ');
    return Row(children: [
      _Avatar(name: name, imageUrl: data.teacherImageUrl),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.onHeroMuted)),
      ),
    ]);
  }

  Widget _pills() => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final p in data.pills) _Pill(pill: p),
      ]);

  Widget _title(BuildContext context, {required bool wide}) {
    final c = context.colors;
    final style = (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: c.onHero);
    return Semantics(header: true, child: Text(data.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: style));
  }

  Widget _notice(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        child: Row(children: [
          Icon(Icons.visibility_outlined, size: AppIconSize.sm, color: c.kit.warmOnDark),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(data.notice!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: c.kit.warmOnDark)),
          ),
        ]),
      ),
    );
  }

  Widget _primary() {
    final p = data.primary;
    if (p == null) return const SizedBox.shrink();
    return AppButton.primary(label: p.label, icon: p.icon, onPressed: p.onTap, size: AppButtonSize.lg, expand: true);
  }

  Widget _secondaryRow({required bool withMenu}) {
    final s = data.secondary;
    return Row(children: [
      if (withMenu && data.menu.isNotEmpty) ...[_MoreMenu(actions: data.menu, onHero: true, round: true), const SizedBox(width: AppSpace.xs)],
      for (final a in data.icons) ...[
        AppIconButton(icon: a.icon, tooltip: a.tooltip, onPressed: a.onTap, onHero: true),
        const SizedBox(width: AppSpace.xs),
      ],
      if (s != null) Expanded(child: _GlassButton(label: s.label, icon: s.icon, onTap: s.onTap)),
    ]);
  }

  // ── layouts ───────────────────────────────────────────────────────────────

  Widget _narrow(BuildContext context, double w) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _topBar(context),
      const SizedBox(height: AppSpace.md),
      Align(alignment: AlignmentDirectional.centerStart, child: _crumb(context)),
      const SizedBox(height: AppSpace.sm),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _badges(),
            const SizedBox(height: AppSpace.sm),
            _title(context, wide: false),
            const SizedBox(height: AppSpace.sm),
            _teacher(context),
          ]),
        ),
        const SizedBox(width: AppSpace.md),
        SizedBox(width: w * 0.3, child: CourseTeacherCover(icon: data.coverIcon, imageUrl: data.imageUrl)),
      ]),
      if (data.pills.isNotEmpty) ...[const SizedBox(height: AppSpace.md), _pills()],
      const SizedBox(height: AppSpace.md),
      _primary(),
      const SizedBox(height: AppSpace.xs),
      _secondaryRow(withMenu: true),
      if (data.notice != null && data.notice!.isNotEmpty) ...[const SizedBox(height: AppSpace.sm), _notice(context)],
    ]);
  }

  Widget _wide(BuildContext context, double w) {
    final sub = data.subtitle;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: AlignmentDirectional.centerStart, child: _crumb(context)),
      const SizedBox(height: AppSpace.sm),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: w * 0.22,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _primary(),
            const SizedBox(height: AppSpace.xs),
            _secondaryRow(withMenu: true),
            if (data.notice != null && data.notice!.isNotEmpty) ...[const SizedBox(height: AppSpace.sm), _notice(context)],
          ]),
        ),
        const SizedBox(width: AppSpace.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _badges(),
            const SizedBox(height: AppSpace.sm),
            _title(context, wide: true),
            if (sub != null && sub.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: context.colors.onHeroMuted)),
            ],
            const SizedBox(height: AppSpace.sm),
            _teacher(context),
          ]),
        ),
        const SizedBox(width: AppSpace.lg),
        SizedBox(width: w * 0.14, child: CourseTeacherCover(icon: data.coverIcon, imageUrl: data.imageUrl)),
      ]),
      if (data.pills.isNotEmpty) ...[const SizedBox(height: AppSpace.md), _pills()],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Small parts
// ═════════════════════════════════════════════════════════════════════════════

class _Badge extends StatelessWidget {
  const _Badge({required this.badge});

  final CourseSpaceBadge badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = badge.color;
    final fill = tone == null ? c.cardBg : appTintOn(context, tone, surface: c.cardBg);
    final ink = tone == null ? c.textDark : appInkOn(context, tone, fill);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (badge.icon != null) ...[Icon(badge.icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(badge.label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.pill});

  final CourseTeacherPill pill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    final body = Container(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: radius,
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pill.icon, size: AppIconSize.sm, color: c.onHeroMuted),
        const SizedBox(width: AppSpace.xs),
        Text(pill.value, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w700)),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(pill.label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
        ),
      ]),
    );
    if (pill.onTap == null) return Semantics(container: true, child: body);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: radius, onTap: pill.onTap, child: body),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letter = name.trim().isEmpty ? '' : name.trim().characters.first;
    final url = imageUrl;
    return Container(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.primary,
        image: url == null || url.isEmpty ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url == null || url.isEmpty
          ? Text(letter, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w700))
          : null,
    );
  }
}

/// A glass outline button on the band (Edit course).
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: AppTouch.min,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            decoration: BoxDecoration(
              color: c.heroGlass,
              borderRadius: radius,
              border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
              ),
              if (icon != null) ...[const SizedBox(width: AppSpace.xs), Icon(icon, size: AppIconSize.sm, color: c.onHero)],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The ⋮ menu of the band.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.actions, required this.onHero, this.round = false});

  final List<CourseSpaceTopAction> actions;
  final bool onHero;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = [
      for (final a in actions)
        if (a.featureKey == null || !AppConfig.disableList.contains(a.featureKey)) a,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: AppConfig.lang == 'ar' ? 'المزيد' : 'More',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      onSelected: (i) => shown[i].onTap(),
      itemBuilder: (_) => [
        for (final (i, a) in shown.indexed)
          PopupMenuItem<int>(
            value: i,
            child: Row(children: [
              Icon(a.icon, size: AppIconSize.md, color: a.color ?? c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: Text(a.tooltip, style: AppType.row(context))),
            ]),
          ),
      ],
      child: SizedBox(
        width: AppTouch.min,
        height: AppTouch.min,
        child: Center(
          child: Container(
            width: AppIconButton.heroSize,
            height: AppIconButton.heroSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.heroGlass,
              border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
            ),
            child: Icon(Icons.more_horiz_rounded, size: AppIconSize.md, color: c.onHero),
          ),
        ),
      ),
    );
  }
}
