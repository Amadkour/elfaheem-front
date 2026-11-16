// lib/features/courses/course_space/course_space_parts.dart
//
// The pieces of [CourseSpace] (course_space.dart), each one plain values only so the layout harness can pump it:
//   CourseSpaceHero        the masthead (D-940): the cover (phone: full bleed, the block overlapping its foot;
//                          desktop: framed at 16:9 inside the block) · the block (pills · title · one line · teacher
//                          · progress · the call to action; the stats grid) · the chrome on the canvas or on the cover
//   CourseCover            the cover picture shown whole over a blurred copy of itself (D-942), a plate without one
//   CourseProgressBar      the one progress bar of the course page: an emerald fill that fills once (AppFill)
//   CourseSpaceTabBar      underline tabs (labels in ink, a 2 px ink rule under the open one); scrolls when the tabs
//                          do not fit; count + live dot per tab
//   CourseSpotlightStack   column of contextual cards that leaves no gap for a card that hides itself
//   CourseSpotlightCard    one contextual card: icon · title · line · progress · action
//   CourseReadinessCard    the teacher's setup checklist (n of m done, the open steps as chips)
//   CourseActionStrip      phones: the quick-action tiles that share the width (the rest behind "More")
//   CourseActionList       desktop side column: the same actions as a list card
//   CourseSideCard         the side column's card surface
//   CourseInfoGroup        the About / Details tab: ONE card, its sections split by hairlines
//   CourseInfoSection      a titled section of that card (+ trailing action)
//   CourseInfoRow          icon · title · subtitle · trailing row inside a section
//   CourseScheduleChips    the weekly schedule as day / time chips (sky: schedule information)
//   CourseRatingStars      ★★★★☆ 4.6 (n) drawn with icons (never star glyphs: the app fonts lack them)
//   CourseSectionHeader    title · count · trailing (the list header of a tab)
//
// Warm Editorial (D-610 – D-629): the hero block is the page's one memorable thing (the title in the editorial
// serif, the figures and the progress under it); everything else is paper on the canvas — cards on a warm hairline,
// no resting shadows, radii by hierarchy (chip 10 · control 14 · card 16 · block 24), emerald only for the primary
// action and progress / completion. Text roles come from AppType, spacing from AppSpace.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeCard;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart' show CourseSchedule;
import 'package:flutter_education_app/features/courses/private_flag.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _keyed(String? featureKey, Widget child) =>
    featureKey == null ? child : ParentComponent(featureKey: featureKey, child: child);

// ═════════════════════════════════════════════════════════════════════════════
// Hero
// ═════════════════════════════════════════════════════════════════════════════

class CourseSpaceHero extends StatelessWidget {
  const CourseSpaceHero({
    super.key,
    required this.data,
    this.background,
    this.topActions = const [],
    this.onBack,
    this.rounded = false,
    this.withBar = true,
    this.showCta = true,
  });

  final CourseSpaceHeroData data;
  final Widget? background;
  final List<CourseSpaceTopAction> topActions;
  final VoidCallback? onBack;

  /// true → the desktop masthead (the chrome on the canvas, the cover framed inside the block); false → the phone's
  /// (the cover full bleed under the status bar, the block overlapping its foot).
  final bool rounded;

  /// false: the desktop masthead draws no bar of its own — [CourseSpace] pins [CourseSpaceBar] over both columns.
  final bool withBar;

  /// false: the call to action is left out (a phone whose sticky bottom bar carries it).
  final bool showCta;

  bool get _hasCover => background != null || data.imageUrl.isNotEmpty || data.coverImage != null;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      return rounded ? _wide(context, w) : _narrow(context, w);
    },
  );

  Widget _bar({required bool onCover}) =>
      _keyed('course_hero.topbar', _TopBar(onBack: onBack, actions: topActions, onCover: onCover));

  CourseSpaceCta? get _cta => showCta && data.cta != null && !data.cta!.isEmpty ? data.cta : null;

  /// Phone / tablet (D-944): the chrome on the canvas, then ONE block — the cover framed whole at 16:9 at its top
  /// (nothing ever sits on the picture), the text, the stats, the progress and the call to action under it.
  Widget _narrow(BuildContext context, double w) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kCourseGutter, vertical: AppSpace.xs),
            child: _bar(onCover: false),
          ),
          const SizedBox(height: AppSpace.xxs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kCourseGutter),
            child: AppBlock(
              tone: data.tone,
              hero: true,
              wash: true,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasCover)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xs, AppSpace.xs, 0),
                      child: _CoverFrame(
                        tilt: false,
                        child: background ?? CourseCover(imageUrl: data.imageUrl, image: data.coverImage),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(AppSpace.lg, _hasCover ? AppSpace.md : AppSpace.lg, AppSpace.lg, AppSpace.lg),
                    child: _HeroInfo(data: data, cta: _cta, wide: false, statsInline: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop (D-940): ONE block — the text column (pills · title · line · teacher · progress · call to action) with
  /// the cover framed at 16:9 beside it, then a hairline and the stats across the block's width.
  Widget _wide(BuildContext context, double w) {
    final side = _hasCover && w >= 720;
    final coverW = (w * 0.38).clamp(280.0, 520.0);
    final frame = !_hasCover
        ? null
        : _CoverFrame(child: background ?? CourseCover(imageUrl: data.imageUrl, image: data.coverImage));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (withBar) ...[_bar(onCover: false), const SizedBox(height: AppSpace.xs)],
        AppBlock(
          tone: data.tone,
          hero: true,
          wash: true,
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Builder(
            builder: (context) {
              final ink = AppBlock.colorsOf(context);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (frame != null && !side) ...[frame, const SizedBox(height: AppSpace.lg)],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _HeroInfo(data: data, cta: _cta, wide: true, statsInline: false)),
                      if (frame != null && side) ...[
                        const SizedBox(width: AppSpace.xl),
                        SizedBox(width: coverW, child: frame),
                      ],
                    ],
                  ),
                  if (data.stats.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.lg),
                    Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: ink.ink.withValues(alpha: 0.12)),
                    const SizedBox(height: AppSpace.md),
                    _keyed('course_hero.stats', _StatsGrid(stats: data.stats, wide: true)),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The desktop cover: 16:9, the card radius, a hairline frame and a soft lift, the picture whole (CourseCover); a
/// reel keeps its own controls and shows its play mark until it plays (CourseReelPlayer).
class _CoverFrame extends StatelessWidget {
  const _CoverFrame({required this.child, this.tilt = true});

  final Widget child;
  final bool tilt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.card);
    final framed = MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.of(context, 1)),
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: c.cardEdge, width: AppBorder.hairline),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    return tilt ? AppTilt.subtle(radius: AppRadius.card, child: framed) : framed;
  }
}

/// The course page's floating bar on desktop (D-648): Back and the page's actions in one white card, pinned over both
/// columns like every pushed page's bar. The same actions, kill switches and callbacks as the hero's own bar.
class CourseSpaceBar extends StatelessWidget {
  const CourseSpaceBar({super.key, this.topActions = const [], this.onBack});

  final List<CourseSpaceTopAction> topActions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) =>
      _keyed('course_hero.topbar', _TopBar(onBack: onBack, actions: topActions, onCover: false));
}

/// The widest the progress runs on a wide block (it reads as one group with the call to action).
const double _kFiguresMax = 560;

/// "12 ratings" under the rating figure (the stat cell draws the average as its value).
String courseRatingCount(int n) => countText(
  n,
  ar1: 'تقييم واحد',
  ar2: 'تقييمان',
  arFew: '{n} تقييمات',
  arMany: '{n} تقييمًا',
  en1: '1 rating',
  en: '{n} ratings',
);

/// The hero's title role (D-940): a clear scale, never the display size. Desktop: headline for a short title, the
/// page title's size for a long one (two lines at most); phone: the page title's size, a section's for a long one
/// (three lines at most).
TextStyle courseHeroTitleStyle(BuildContext context, String title, {required bool wide}) {
  final n = title.characters.length;
  if (wide) return n > 52 ? AppType.pageTitle(context) : AppType.headline(context);
  return n > 48 ? AppType.section(context) : AppType.pageTitle(context);
}

/// The block's text: pills · the title · one line · the teacher · (phone: the stats) · progress · call to action.
class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.data, required this.cta, required this.wide, required this.statsInline});

  final CourseSpaceHeroData data;
  final CourseSpaceCta? cta;
  final bool wide;
  final bool statsInline;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final pills = <Widget>[
      if (data.category != null && data.category!.isNotEmpty)
        _keyed('course_hero.category', _HeroPill(label: data.category!, icon: Icons.local_offer_outlined)),
      if (data.isPrivate) _keyed('course_hero.private', PrivateFlag(label: data.privateLabel)),
      for (final p in data.badges) _keyed(p.featureKey, _HeroPill(label: p.label, icon: p.icon, color: p.color)),
    ];
    final title = courseHeroTitleStyle(context, data.title, wide: wide).copyWith(color: b.ink);
    final subtitle = data.subtitle?.trim() ?? '';
    return Directionality(
      textDirection: Helpers.textDirOf(data.title),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pills.isNotEmpty) ...[
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: pills),
            const SizedBox(height: AppSpace.sm),
          ],
          Semantics(
            header: true,
            child: Text(data.title, maxLines: wide ? 2 : 3, overflow: TextOverflow.ellipsis, style: title),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            _keyed(
              'course_hero.description',
              Text(
                // one line: the first line of the description (the About tab has the rest)
                subtitle.split('\n').first,
                maxLines: wide ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.body(context).copyWith(color: b.muted),
              ),
            ),
          ],
          if (data.teacherName != null && data.teacherName!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            _keyed(
              'course_hero.teacher',
              _TeacherChip(name: data.teacherName!, imageUrl: data.teacherImageUrl, onTap: data.onTeacher),
            ),
          ],
          if (statsInline && data.stats.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _keyed('course_hero.stats', _StatsGrid(stats: data.stats, wide: false)),
          ],
          if (data.progress != null) ...[
            const SizedBox(height: AppSpace.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kFiguresMax),
              child: _keyed('course_hero.progress', _HeroProgress(value: data.progress!, label: data.progressLabel)),
            ),
          ],
          if (cta != null) ...[
            SizedBox(height: wide ? AppSpace.lg : AppSpace.md),
            _HeroCta(cta: cta!, wide: wide),
          ],
        ],
      ),
    );
  }
}

/// The hero's call to action (D-941): the price, the ONE primary button, the secondary and the icon actions. Wide: one
/// row that wraps; phone: the price and the primary across the width, the secondary and the icons under it.
class _HeroCta extends StatelessWidget {
  const _HeroCta({required this.cta, required this.wide});

  final CourseSpaceCta cta;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    // a tablet's block is wide enough for the desktop's one row (a full-width button there is a slab)
    if (!wide) {
      return LayoutBuilder(
        builder: (context, box) =>
            box.maxWidth >= 560 ? _HeroCta(cta: cta, wide: true) : _build(context),
      );
    }
    return _build(context);
  }

  Widget _build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final p = cta.primary;
    final s = cta.secondary;
    final primary = p == null
        ? null
        : _keyed(
            p.featureKey,
            AppButton.primary(label: p.label, icon: p.icon, onPressed: p.onTap, size: AppButtonSize.lg, expand: !wide),
          );
    final secondary = s == null
        ? null
        : _keyed(
            s.featureKey,
            AppButton.secondary(label: s.label, icon: s.icon, onPressed: s.onTap, size: AppButtonSize.lg, expand: !wide),
          );
    final icons = [
      for (final a in cta.icons)
        if (a.featureKey == null || !AppConfig.disableList.contains(a.featureKey)) _CtaIconButton(action: a),
    ];
    final caption = cta.caption == null || cta.caption!.isEmpty
        ? null
        : Text(
            cta.caption!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(color: b.muted),
          );
    if (wide) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cta.note != null) ...[cta.note!, const SizedBox(height: AppSpace.sm)],
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (cta.price != null)
                Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.xs), child: cta.price!),
              ?primary,
              ?secondary,
              ...icons,
            ],
          ),
          if (caption != null) ...[const SizedBox(height: AppSpace.xs), caption],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cta.price != null) ...[
          Align(alignment: AlignmentDirectional.centerStart, child: cta.price!),
          const SizedBox(height: AppSpace.sm),
        ],
        if (cta.note != null) ...[cta.note!, const SizedBox(height: AppSpace.sm)],
        ?primary,
        if (caption != null) ...[const SizedBox(height: AppSpace.xs), caption],
        if (secondary != null || icons.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              if (secondary != null) Expanded(child: secondary),
              for (final i in icons) ...[const SizedBox(width: AppSpace.xs), i],
            ],
          ),
        ],
      ],
    );
  }
}

/// An icon action of the call to action (Share): a 48 px paper circle with a hairline, its tooltip as its label.
class _CtaIconButton extends StatelessWidget {
  const _CtaIconButton({required this.action});

  final CourseSpaceTopAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: action.selected,
      label: action.tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: action.tooltip,
        child: Material(
          color: c.cardBg,
          shape: CircleBorder(side: BorderSide(color: c.cardEdge, width: AppBorder.hairline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: action.onTap,
            child: SizedBox(
              width: AppTouch.primary,
              height: AppTouch.primary,
              child: Icon(
                action.icon,
                size: AppIconSize.md,
                color: action.color == null ? c.textDark : ensureContrast(action.color!, [c.cardBg], min: 3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cover picture fading in over a quiet plate (no flash, no layout jump), or the plate alone. The picture is
/// shown WHOLE (D-942): contained inside [inset] over a blurred, cover-fitted copy of itself, so a cover whose text
/// runs to its edges is never cut, and a 16:9 cover in a 16:9 frame fills it edge to edge. With [parallax] the blurred
/// copy drifts a few pixels against the page's scroll (AppParallaxImage).
class CourseCover extends StatelessWidget {
  const CourseCover({super.key, required this.imageUrl, this.image, this.parallax = false, this.inset = EdgeInsets.zero});

  final String imageUrl;

  /// A picture already in hand; wins over [imageUrl].
  final ImageProvider? image;
  final bool parallax;

  /// Where the sharp picture sits inside the cover (a phone keeps it clear of the status bar and the block).
  final EdgeInsets inset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plate = ColoredBox(
      color: c.inputBg,
      child: Center(
        child: Icon(Icons.auto_stories_rounded, size: AppIconSize.hero, color: c.textLight.withValues(alpha: 0.5)),
      ),
    );
    final provider = image ?? (imageUrl.isEmpty ? null : NetworkImage(imageUrl));
    if (provider == null) return plate;
    Widget pic(BoxFit fit) => Image(
      image: provider,
      fit: fit,
      frameBuilder: (_, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: AppMotion.of(context).slow,
              curve: AppEase.out,
              child: child,
            ),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final backdrop = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: SizedBox.expand(child: pic(BoxFit.cover)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        plate,
        ClipRect(child: parallax ? AppParallaxImage(image: backdrop) : backdrop),
        // the blurred copy steps back a little so the sharp picture reads as the subject
        ColoredBox(color: c.heroShade.withValues(alpha: 0.16)),
        Padding(padding: inset, child: pic(BoxFit.contain)),
      ],
    );
  }
}

/// The hero's chrome: back at the start · the inline actions at the end, ending with ⋮ when some actions are rarer
/// (D-111). On the canvas it is the floating bar every pushed page wears (D-648): one white rounded card with Back
/// and the actions inside it as ghosts; on the cover it stays glass. Every target is 48 px; the icons mirror
/// themselves in Arabic.
class _TopBar extends StatelessWidget {
  const _TopBar({this.onBack, required this.actions, required this.onCover});

  final VoidCallback? onBack;
  final List<CourseSpaceTopAction> actions;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final a in actions)
        if (a.featureKey == null || !AppConfig.disableList.contains(a.featureKey)) a,
    ];
    final inline = [for (final a in shown) if (!a.overflow) a];
    final menu = [for (final a in shown) if (a.overflow) a];
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 560;
        final hasGroup = inline.isNotEmpty || menu.isNotEmpty;
        final buttons = [
          for (final a in inline)
            a.primary && wide
                ? _CapsuleLabelButton(action: a, onCover: onCover)
                : _CapsuleIconButton(action: a, onCover: onCover),
          if (menu.isNotEmpty) _CapsuleMenu(actions: menu, onCover: onCover),
        ];
        final row = Row(
          children: [
            if (onBack != null) AppBackButton(onHero: onCover, onPressed: onBack),
            Expanded(
              child: !hasGroup
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: onCover
                            ? _Capsule(onCover: true, children: buttons)
                            : Row(mainAxisSize: MainAxisSize.min, children: buttons),
                      ),
                    ),
            ),
          ],
        );
        if (onCover) return row;
        return ChromeCard(
          height: ChromeCard.barHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: row,
        );
      },
    );
  }
}

/// The action group on the cover: frosted glass.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.children, required this.onCover});

  final List<Widget> children;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs / 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: c.heroShade.withValues(alpha: 0.34),
            border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
          ),
          child: row,
        ),
      ),
    );
  }
}

Color _chromeInk(BuildContext context, bool onCover) => onCover ? context.colors.onHero : context.colors.textDark;

class _CapsuleIconButton extends StatelessWidget {
  const _CapsuleIconButton({required this.action, required this.onCover});

  final CourseSpaceTopAction action;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: action.selected,
      label: action.tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: action.tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: action.onTap,
            child: SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              // a page-given colour (the favourite's gold) is deepened until it reads on the bar (3:1, a glyph)
              child: Icon(action.icon, size: AppIconSize.md, color: action.color == null ? _chromeInk(context, onCover) : (onCover ? action.color : ensureContrast(action.color!, [context.colors.cardBg], min: 3))),
            ),
          ),
        ),
      ),
    );
  }
}
/// The primary action with its word (wide screens): "Edit course" — a solid primary pill with its own ink, lifted to
/// 4.5:1 (the old translucent tint washed the label out on the paper bar, D-648).
/// The primary action with its word (wide screens): "Edit course" — the emerald tint with emerald ink on paper.
class _CapsuleLabelButton extends StatelessWidget {
  const _CapsuleLabelButton({required this.action, required this.onCover});

  final CourseSpaceTopAction action;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = onCover ? c.heroGlass : c.primary;
    final ink = onCover ? c.onHero : ensureContrast(c.onHero, [fill]);
    final radius = BorderRadius.circular(AppRadius.pill);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs, horizontal: AppSpace.xxs / 2),
      child: Material(
        color: fill,
        borderRadius: radius,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs, minWidth: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: AppIconSize.md, color: ink),
                  const SizedBox(width: AppSpace.xs),
                  Text(
                    action.tooltip,
                    maxLines: 1,
                    style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleMenu extends StatelessWidget {
  const _CapsuleMenu({required this.actions, required this.onCover});

  final List<CourseSpaceTopAction> actions;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      tooltip: _t('المزيد', 'More'),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      onSelected: (i) => actions[i].onTap(),
      itemBuilder: (_) => [
        for (final (i, a) in actions.indexed)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(a.icon, size: AppIconSize.md, color: a.color ?? c.textMedium),
                const SizedBox(width: AppSpace.sm),
                Flexible(child: Text(a.tooltip, style: AppType.row(context))),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: AppTouch.min,
        height: AppTouch.min,
        child: Icon(Icons.more_vert_rounded, size: AppIconSize.md, color: _chromeInk(context, onCover)),
      ),
    );
  }
}

/// A small pill in the block: paper with a hairline, or [color]'s opaque tint with its ink darkened to read (a
/// danger / warning fill with white text would fall under AA on the warm block).
class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final tone = color;
    final fill = tone == null ? c.cardBg : appTintOn(context, tone, surface: b.surface);
    final ink = tone == null ? b.ink : appInkOn(context, tone, fill);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpace.lg + AppSpace.xxs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm - AppSpace.xxs / 2, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: tone == null ? Border.all(color: c.divider, width: AppBorder.hairline) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs + 1)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500, color: ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherChip extends StatelessWidget {
  const _TeacherChip({required this.name, this.imageUrl, this.onTap});

  final String name;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final chip = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(0, AppSpace.xxs, AppSpace.xs, AppSpace.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.divider, width: AppBorder.hairline)),
              child: CircleAvatar(
                radius: AppSpace.md,
                backgroundColor: c.cardBg,
                backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
                onBackgroundImageError: hasImage ? (_, _) {} : null,
                child: hasImage
                    ? null
                    : Text(
                        name.characters.first,
                        style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: b.ink),
                      ),
              ),
            ),
            const SizedBox(width: AppSpace.sm - AppSpace.xxs / 2),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.row(context).copyWith(color: b.ink),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpace.xxs / 2),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: b.muted),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.pill), onTap: onTap, child: chip),
    );
  }
}

/// The hero's stats (D-940, D-945): equal tiles in balanced rows — one row across a wide block, 2 (or 3 when they
/// divide evenly) per row on a phone, the last row's tiles sharing its width. A tile: the icon in a paper well, the
/// value in the page-title type, the label as a caption; a tile with an action wears a hairline and a chevron.
/// D-1081: a hero figure as the soft-wash count card; the tones take turns (emerald · gold · sky · peach), a figure
/// with a meaning of its own (the rating's star) keeps gold. A tappable one (students → the list) presses.
const _kStatTones = [AppBlockTone.emerald, AppBlockTone.gold, AppBlockTone.sky, AppBlockTone.peach];

Widget _statCard(CourseSpaceStat st, int index) => AppStatCard(
      key: ValueKey('course_hero.stat.$index'),
      icon: st.icon,
      value: st.value,
      label: st.label,
      tone: st.tone != null ? AppBlockTone.gold : _kStatTones[index % _kStatTones.length],
      onTap: st.onTap,
      footer: st.footer,
      bars: st.bars,
      barsCaption: st.barsCaption,
      warn: st.warn,
    );

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.wide});

  final List<CourseSpaceStat> stats;
  final bool wide;

  /// The narrowest a tile gets before the row breaks.
  static const double _kTileMin = 150;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final s in stats)
        if (s.featureKey == null || !AppConfig.disableList.contains(s.featureKey)) s,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        const gap = AppSpace.xs;
        final w = box.maxWidth;
        final n = shown.length;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        int cols;
        if (w / n >= _kTileMin * scale) {
          cols = n;
        } else if (n % 3 == 0 && w / 3 >= (_kTileMin - AppSpace.xl) * scale) {
          cols = 3;
        } else {
          cols = w >= (_kTileMin - AppSpace.xl) * 2 * scale ? 2 : 1;
        }
        final rows = <Widget>[];
        for (var i = 0; i < n; i += cols) {
          final part = shown.sublist(i, (i + cols).clamp(0, n));
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (j, st) in part.indexed) ...[
                  if (j > 0) const SizedBox(width: gap),
                  Expanded(child: _statCard(st, i + j)),
                ],
              ],
            ),
          ));
        }
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

/// The enrolled student's progress through the course: its label, the percentage and the emerald bar that fills.
class _HeroProgress extends StatelessWidget {
  const _HeroProgress({required this.value, this.label});

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final v = value.clamp(0.0, 1.0);
    final pct = '${(v * 100).round()}%';
    return Semantics(
      label: label == null ? pct : '$label $pct',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AppCountUp(pct, memoryKey: 'course_hero.progress', style: AppType.figure(context).copyWith(color: b.ink)),
              if (label != null && label!.isNotEmpty) ...[
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: b.muted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          CourseProgressBar(value: v, height: AppSpace.xs, color: c.primary, track: b.ink.withValues(alpha: 0.1)),
        ],
      ),
    );
  }
}

/// The course page's progress bar: a rounded track and an emerald (or [color]) fill that fills once from 0, and glides
/// from the old value when it changes (AppFill; at once under Reduce motion).
class CourseProgressBar extends StatelessWidget {
  const CourseProgressBar({super.key, required this.value, this.color, this.track, this.height = 6});

  /// 0…1.
  final double value;
  final Color? color;
  final Color? track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = color ?? c.primary;
    final radius = BorderRadius.circular(AppRadius.pill);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: track ?? fill.withValues(alpha: 0.14), borderRadius: radius),
          child: AppFill(
            value: value.clamp(0.0, 1.0),
            builder: (context, v) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: v.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: fill, borderRadius: radius)),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab bar
// ═════════════════════════════════════════════════════════════════════════════

/// The page's sections as underline tabs (the kit's AppUnderlineTabs language): labels in ink, a 2 px ink rule
/// under the open one sitting on the bar's warm hairline.
class CourseSpaceTabBar extends StatelessWidget {
  const CourseSpaceTabBar({super.key, required this.tabs, required this.active, required this.onTab});

  final List<CourseSpaceTab> tabs;
  final String active;
  final ValueChanged<String> onTab;

  /// Equal segments get a label beside the icon when every tab's label + count fits whole in its segment (H7:
  /// "Sessi… 4" at 390 px in English), else the icon above the label (the count beside the icon) from [_stackedW];
  /// narrower still, the row scrolls.
  static const double _rowW = 110, _stackedW = 64;

  /// A tab's inner padding: row (start/end 15, top 10, bottom 13 — the rule sits on the bar's foot) and stacked
  /// (5 · 8 · 11). The heights below count them.
  static const EdgeInsets _rowPad = EdgeInsets.fromLTRB(15, 10, 15, 13), _stackPad = EdgeInsets.fromLTRB(5, 8, 5, 11);

  static TextStyle _labelStyle(BuildContext context, {required bool stacked, bool active = false}) {
    final base = stacked ? AppType.meta(context) : AppType.label(context);
    return base.copyWith(fontWeight: active || stacked ? FontWeight.w600 : FontWeight.w500, height: 1.4);
  }

  static TextStyle _countStyle(BuildContext context) =>
      AppType.meta(context).copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);

  static double _textW(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      // the Text draws its style over the inherited one (the theme's tracking), so measure it the same way
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = tp.width;
    tp.dispose();
    return width;
  }

  /// The width one tab needs laid out as a row: padding, icon 18 + 8, label, count 6 + n.
  static double _rowNeed(BuildContext context, CourseSpaceTab t) {
    var need = _rowPad.horizontal + 18 + 8 + _textW(context, t.label, _labelStyle(context, stacked: false, active: true)) + 2;
    if (t.live) need += 14;
    if (t.count != null && t.count! > 0) need += 6 + _textW(context, '${t.count}', _countStyle(context));
    return need;
  }

  /// The width one tab needs stacked: its padding and the label whole ("Announc…" at 390 px with five teacher tabs).
  static double _stackedNeed(BuildContext context, CourseSpaceTab t) =>
      _stackPad.horizontal + _textW(context, t.label, _labelStyle(context, stacked: true)) + 1;

  static bool _stacked(BuildContext context, double inner, List<CourseSpaceTab> visible) {
    if (visible.isEmpty) return false;
    final per = inner / visible.length;
    if (per < _stackedW) return false;
    if (visible.any((t) => _stackedNeed(context, t) > per)) return false; // the row scrolls instead
    if (per < _rowW) return true;
    return visible.any((t) => _rowNeed(context, t) > per);
  }

  static List<CourseSpaceTab> _visible(List<CourseSpaceTab> tabs) => [
    for (final t in tabs)
      if (t.featureKey == null || !AppConfig.disableList.contains(t.featureKey)) t,
  ];

  /// The bar's height for a page [width] at the current text scale (the pinned header needs a fixed extent).
  static double heightFor(BuildContext context, {required double width, required List<CourseSpaceTab> tabs}) {
    final scaler = MediaQuery.textScalerOf(context);
    // outer padding 8 + 8, the track's top 3, the tab's padding, the icon / label lines
    if (_stacked(context, width - kCourseGutter * 2 - 6, _visible(tabs))) {
      final size = _labelStyle(context, stacked: true).fontSize ?? 12;
      return (16 + 3 + _stackPad.vertical + 18 + 3 + scaler.scale(size) * 1.45).ceilToDouble();
    }
    final line = scaler.scale(_labelStyle(context, stacked: false).fontSize ?? 13) * 1.45;
    return (16 + 3 + _rowPad.vertical + (line < 20 ? 20 : line)).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = _visible(tabs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.xs, kCourseGutter, AppSpace.xs),
      child: DecoratedBox(
        // the warm hairline the open tab's rule sits on
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 3, 3, 0),
          child: LayoutBuilder(
            builder: (context, box) {
              final stacked = _stacked(context, box.maxWidth, visible);
              final fits = visible.isEmpty ||
                  stacked ||
                  (box.maxWidth / visible.length >= _rowW &&
                      !visible.any((t) => _rowNeed(context, t) > box.maxWidth / visible.length));
              Widget item(CourseSpaceTab t) =>
                  _TabPill(tab: t, active: t.id == active, stacked: stacked, onTap: () => onTab(t.id));
              if (fits) {
                return Row(children: [for (final t in visible) Expanded(child: item(t))]);
              }
              return _ScrollingTabs(active: active, children: {for (final t in visible) t.id: item(t)});
            },
          ),
        ),
      ),
    );
  }
}

/// More tabs than fit: the row scrolls, its far edge fades (there is more), and the active tab is brought into view.
class _ScrollingTabs extends StatefulWidget {
  const _ScrollingTabs({required this.active, required this.children});

  final String active;
  final Map<String, Widget> children;

  @override
  State<_ScrollingTabs> createState() => _ScrollingTabsState();
}

class _ScrollingTabsState extends State<_ScrollingTabs> {
  final _keys = <String, GlobalKey>{};
  final _ctl = ScrollController();
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void didUpdateWidget(_ScrollingTabs old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final end = _ctl.hasClients && _ctl.position.pixels >= _ctl.position.maxScrollExtent - 4;
    if (end != _atEnd) setState(() => _atEnd = end);
  }

  void _reveal({bool animate = true}) {
    final ctx = _keys[widget.active]?.currentContext;
    if (!mounted || ctx == null || !_ctl.hasClients) return;
    // only this row scrolls (Scrollable.ensureVisible would also move the page)
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final to = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.5).offset.clamp(0.0, _ctl.position.maxScrollExtent);
    final d = AppMotion.of(context).base;
    if (animate && d > Duration.zero) {
      _ctl.animateTo(to, duration: d, curve: AppEase.out);
    } else {
      _ctl.jumpTo(to);
    }
    _onScroll();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final row = SingleChildScrollView(
      controller: _ctl,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in widget.children.entries) KeyedSubtree(key: _keys.putIfAbsent(e.key, GlobalKey.new), child: e.value),
        ],
      ),
    );
    // Always the mask (opaque at the end): dropping it re-created the row's scroll position at 0, so revealing a last
    // tab (Progress, About) scrolled it back out of sight.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
        end: rtl ? Alignment.centerLeft : Alignment.centerRight,
        stops: const [0, 0.86, 1],
        colors: [const Color(0xFF000000), const Color(0xFF000000), Color(_atEnd ? 0xFF000000 : 0x00000000)],
      ).createShader(r),
      child: row,
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.tab, required this.active, required this.onTap, this.stacked = false});

  final CourseSpaceTab tab;
  final bool active;
  final VoidCallback onTap;

  /// Icon above the label (narrow phones).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? c.textDark : c.textMedium;
    final iconColor = active ? c.textDark : c.textLight;
    final count = tab.count != null && tab.count! > 0
        ? Text(
            '${tab.count}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: CourseSpaceTabBar._countStyle(context).copyWith(
              color: active ? c.textMedium : c.textLight,
              height: stacked ? 1.0 : 1.4,
            ),
          )
        : null;
    final label = Text(
      tab.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: CourseSpaceTabBar._labelStyle(context, stacked: stacked, active: active).copyWith(color: fg),
    );
    final Widget content = stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 18,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.live) ...[_LiveDot(color: c.danger), const SizedBox(width: AppSpace.xxs)],
                    Icon(tab.icon, size: 18, color: iconColor),
                    // the count beside the icon, so the label below keeps the whole segment
                    if (count != null) ...[const SizedBox(width: AppSpace.xxs), Flexible(child: count)],
                  ],
                ),
              ),
              const SizedBox(height: 3),
              label,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tab.live) ...[_LiveDot(color: c.danger), const SizedBox(width: 6)],
              Icon(tab.icon, size: 18, color: iconColor),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: label),
              if (count != null) ...[const SizedBox(width: 6), count],
            ],
          );
    final motion = AppMotion.of(context);
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.chip)),
        child: AnimatedContainer(
          duration: motion.base,
          curve: AppEase.out,
          padding: stacked ? CourseSpaceTabBar._stackPad : CourseSpaceTabBar._rowPad,
          foregroundDecoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: active ? c.textDark : c.textDark.withValues(alpha: 0), width: AppBorder.focus),
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _a, reverse: true); // reduce motion parks this decorative loop
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_a),
    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Spotlight
// ═════════════════════════════════════════════════════════════════════════════

/// Stacks contextual cards [AppSpace.sm] apart. A child that renders nothing (SizedBox.shrink) shares a run with its
/// neighbour, so it leaves no gap.
class CourseSpotlightStack extends StatelessWidget {
  const CourseSpotlightStack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      runSpacing: AppSpace.sm,
      children: [for (final w in children) ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth), child: w)],
    ),
  );
}

/// The paper surface every card of the page sits on: the card colour on a warm hairline, radius card, no shadow
/// (D-612); [tint] lays an opaque wash of a tone over it for the loudest state (live now), with a hairline in it.
BoxDecoration _paper(BuildContext context, {Color? tint, Color? accent}) {
  final c = context.colors;
  return BoxDecoration(
    color: tint == null ? c.cardBg : appTintOn(context, tint).withAlpha(255),
    borderRadius: BorderRadius.circular(AppRadius.card),
    border: Border.all(
      color: tint != null
          ? tint.withValues(alpha: c.isDark ? 0.45 : 0.3)
          : (accent?.withValues(alpha: 0.35) ?? c.divider),
      width: AppBorder.hairline,
    ),
  );
}

/// The tinted square well of an icon (radius control): the tone's opaque tint, the icon in the tone's ink.
class _IconWell extends StatelessWidget {
  const _IconWell({required this.icon, required this.tone, this.size = 40, this.on});

  final IconData icon;
  final Color tone;
  final double size;

  /// The surface the well sits on (its tint is laid over it); null = the card.
  final Color? on;

  @override
  Widget build(BuildContext context) {
    final fill = appTintOn(context, tone, surface: on);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Icon(icon, color: appInkOn(context, tone, fill), size: size * 0.48),
    );
  }
}

/// One contextual card: what matters about this course right now, and the one tap that acts on it.
class CourseSpotlightCard extends StatelessWidget {
  const CourseSpotlightCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.progress,
    this.progressLabel,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.onTap,
    this.live = false,
    this.filled = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Tone of the card; null → primary.
  final Color? color;

  /// 0…1, a bar under the text.
  final double? progress;
  final String? progressLabel;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  /// A pulsing "live" dot next to the title.
  final bool live;

  /// The loudest state (live now): the whole card takes an opaque tint of its tone.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final danger = tone == c.danger;
    final surface = filled ? appTintOn(context, tone) : c.cardBg;

    Widget? action;
    if (actionLabel != null && onAction != null) {
      action = danger
          ? AppButton.danger(label: actionLabel!, icon: actionIcon ?? Icons.arrow_forward_rounded, size: AppButtonSize.sm, onPressed: onAction)
          : AppButton.primary(label: actionLabel!, icon: actionIcon ?? Icons.arrow_forward_rounded, size: AppButtonSize.sm, onPressed: onAction);
    }

    return LayoutBuilder(
      builder: (context, box) {
        // the action sits at the end while the text keeps ~60 % of the card; below that it goes under the text
        final roomy = box.maxWidth >= 340 * MediaQuery.textScalerOf(context).scale(1);
        final act = action == null
            ? null
            : roomy
            ? ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.38), child: action)
            : action;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (live) ...[_LiveDot(color: c.danger), const SizedBox(width: AppSpace.xs)],
                Flexible(
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                ),
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs / 2),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(height: 1.45),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(child: CourseProgressBar(value: progress!, color: tone == c.primary ? c.primary : tone)),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    progressLabel ?? '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
                    style: AppType.meta(context).copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
        final well = _IconWell(icon: icon, tone: tone, on: surface);

        final body = Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: roomy || act == null
              ? Row(
                  children: [
                    well,
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: text),
                    if (act != null) ...[const SizedBox(width: AppSpace.sm), act],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [well, const SizedBox(width: AppSpace.sm), Expanded(child: text)],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    act,
                  ],
                ),
        );

        final radius = BorderRadius.circular(AppRadius.card);
        return DecoratedBox(
          decoration: _paper(context, tint: filled ? tone : null),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(borderRadius: radius, onTap: onTap, child: body),
          ),
        );
      },
    );
  }
}

/// One step of the course setup checklist.
class CourseReadinessItem {
  const CourseReadinessItem({required this.label, required this.done, this.icon, this.onTap});

  final String label;
  final bool done;
  final IconData? icon;
  final VoidCallback? onTap;
}

/// "Your course is n of m ready" — shown only while a step is open; the open steps are one tap each.
class CourseReadinessCard extends StatelessWidget {
  const CourseReadinessCard({super.key, required this.items, this.title});

  final List<CourseReadinessItem> items;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final open = items.where((i) => !i.done).toList();
    if (items.isEmpty || open.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final done = items.length - open.length;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: _paper(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconWell(icon: Icons.rocket_launch_rounded, tone: c.warning),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? _t('جهّز كورسك', 'Get your course ready'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.section(context),
                    ),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(
                      _t('$done من ${items.length} خطوات مكتملة', '$done of ${items.length} steps done'),
                      style: AppType.meta(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          CourseProgressBar(value: done / items.length, color: c.primary),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final i in open)
                ActionChip(
                  avatar: Icon(i.icon ?? Icons.add_circle_outline_rounded, size: AppIconSize.sm, color: appInk(context, c.primary)),
                  label: Text(i.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  labelStyle: AppType.label(context).copyWith(color: c.textDark),
                  backgroundColor: c.cardBg,
                  side: BorderSide(color: c.divider, width: AppBorder.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
                  onPressed: i.onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Quick actions
// ═════════════════════════════════════════════════════════════════════════════

List<CourseSpaceAction> _visibleActions(List<CourseSpaceAction> all) => [
  for (final a in all)
    if (a.featureKey == null || !AppConfig.disableList.contains(a.featureKey)) a,
];

/// Phones: the course's quick actions as ONE row of tiles that share the width; when they do not all fit, the
/// last tile is "More", which lists the rest in a sheet (a row cut at the edge read as broken, M14).
class CourseActionStrip extends StatelessWidget {
  const CourseActionStrip({super.key, required this.actions});

  final List<CourseSpaceAction> actions;

  @override
  Widget build(BuildContext context) {
    final shown = _visibleActions(actions);
    if (shown.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = kCourseGutter - AppSpace.xxs;
        // Every tile fits → they share the width evenly; otherwise the last tile is "More".
        if (shown.length * _ActionTile.width <= box.maxWidth - pad * 2) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: pad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final a in shown) Expanded(child: _ActionTile(action: a, fill: true))],
            ),
          );
        }
        final fit = ((box.maxWidth - pad * 2) / _ActionTile.width).floor().clamp(2, shown.length);
        final head = shown.take(fit - 1).toList();
        final rest = shown.skip(fit - 1).toList();
        final more = CourseSpaceAction(
          icon: Icons.more_horiz_rounded,
          label: _t('المزيد', 'More'),
          color: c.textMedium,
          onTap: () => _openMore(context, rest),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in head) Expanded(child: _ActionTile(action: a, fill: true)),
              Expanded(child: _ActionTile(action: more, fill: true)),
            ],
          ),
        );
      },
    );
  }

  static void _openMore(BuildContext context, List<CourseSpaceAction> rest) {
    showAppModalSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheet) => AppSheetContent(title: _t('اختصارات الكورس', 'Course shortcuts'), children: [
        for (final a in rest)
          _ActionRow(
            action: a,
            onTap: () {
              Navigator.of(sheet).pop();
              a.onTap();
            },
          ),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, this.fill = false});

  static const double width = 84;

  final CourseSpaceAction action;

  /// Takes the width it is given instead of [width].
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = action.color ?? c.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
      child: SizedBox(
        width: fill ? null : width - AppSpace.xs,
        child: AppPressScale(
          scale: 0.97,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: action.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs - 2, horizontal: AppSpace.xxs / 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionIcon(icon: action.icon, tone: tone, badge: action.badge, size: AppTouch.min),
                    const SizedBox(height: AppSpace.xs - 2),
                    Text(
                      action.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tone, this.badge, required this.size});

  final IconData icon;
  final Color tone;
  final String? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: size + 6,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _IconWell(icon: icon, tone: tone, size: size),
          if (badge != null && badge!.isNotEmpty)
            PositionedDirectional(
              top: -2,
              end: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: c.danger,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: c.background, width: AppBorder.strong),
                ),
                child: Text(
                  badge!,
                  textAlign: TextAlign.center,
                  style: AppType.overline(context).copyWith(letterSpacing: 0, color: appInkOnFill(context, c.danger)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Desktop side column: the same actions as a list card.
class CourseActionList extends StatelessWidget {
  const CourseActionList({super.key, required this.actions, this.title});

  final List<CourseSpaceAction> actions;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final shown = _visibleActions(actions);
    if (shown.isEmpty) return const SizedBox.shrink();
    return CourseSideCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.md, AppSpace.xs, AppSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, AppSpace.xs, AppSpace.xs),
            child: Text(title ?? _t('اختصارات الكورس', 'Course shortcuts'), style: AppType.section(context)),
          ),
          for (final a in shown) _ActionRow(action: a, onTap: a.onTap),
        ],
      ),
    );
  }
}

/// Desktop (D-944): the course's shortcuts as ONE slim row of paper pills under the hero (icon · label · badge), so
/// no side column is kept just for them. Wraps when they do not fit.
class CourseActionRow extends StatelessWidget {
  const CourseActionRow({super.key, required this.actions, this.title});

  final List<CourseSpaceAction> actions;

  /// The row's name for screen readers ("Course shortcuts").
  final String? title;

  @override
  Widget build(BuildContext context) {
    final shown = _visibleActions(actions);
    if (shown.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: title ?? _t('اختصارات الكورس', 'Course shortcuts'),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: [for (final a in shown) _keyed(a.featureKey, _ActionPill(action: a))],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action});

  final CourseSpaceAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Tooltip(
      message: action.caption ?? action.label,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.cardEdge, width: AppBorder.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIcon(icon: action.icon, tone: action.color ?? c.primary, badge: action.badge, size: AppSpace.xl + AppSpace.xxs),
                  const SizedBox(width: AppSpace.xs),
                  Text(action.label, maxLines: 1, style: AppType.row(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One action as a list row (the desktop side column and the phone's "More" sheet).
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, this.onTap});

  final CourseSpaceAction action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = action;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs - 2),
          child: Row(
            children: [
              _ActionIcon(icon: a.icon, tone: a.color ?? c.primary, badge: a.badge, size: 38),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    if (a.caption != null && a.caption!.isNotEmpty)
                      Text(a.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLight, size: AppIconSize.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card surface of the side column (and of any block that should look like it): paper on a warm hairline.
class CourseSideCard extends StatelessWidget {
  const CourseSideCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.lg - AppSpace.xxs), this.accent});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// A coloured hairline (e.g. primary for the buy card).
  final Color? accent;

  @override
  Widget build(BuildContext context) =>
      Container(padding: padding, decoration: _paper(context, accent: accent), child: child);
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab content: list header · About / Details
// ═════════════════════════════════════════════════════════════════════════════

/// Title · count · trailing — the header of a list inside a tab: the editorial section heading, more air above
/// it than under it.
class CourseSectionHeader extends StatelessWidget {
  const CourseSectionHeader({super.key, required this.title, this.count, this.trailing, this.padding});

  final String title;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(kCourseGutter + AppSpace.xxs, AppSpace.md, kCourseGutter, AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: AppSpace.xs),
                  Text(
                    '$count',
                    style: AppType.label(context).copyWith(
                      color: c.textLight,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpace.xs), trailing!],
        ],
      ),
    );
  }
}

/// The About / Details tab: ONE card whose sections are split by hairlines (no stack of boxes).
/// Children that render nothing still take no room; pass the sections in order.
class CourseInfoGroup extends StatelessWidget {
  const CourseInfoGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: _paper(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: AppBorder.hairline,
                thickness: AppBorder.hairline,
                indent: AppSpace.md,
                endIndent: AppSpace.md,
                color: c.divider,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A titled section of a [CourseInfoGroup] (on its own it draws no box either): an editorial heading with a quiet
/// glyph in the section's tone.
class CourseInfoSection extends StatelessWidget {
  const CourseInfoSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.color,
    this.trailing,
    this.featureKey,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? color;
  final Widget? trailing;
  final String? featureKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    return _keyed(
      featureKey,
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg - AppSpace.xxs, AppSpace.md, AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppIconSize.md, color: appInk(context, tone)),
                const SizedBox(width: AppSpace.xs + 2),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: AppSpace.xs), Flexible(child: trailing!)],
              ],
            ),
            if (children.isNotEmpty) ...[const SizedBox(height: AppSpace.sm), ...children],
          ],
        ),
      ),
    );
  }
}

/// icon · title · subtitle · trailing — one line inside a [CourseInfoSection].
class CourseInfoRow extends StatelessWidget {
  const CourseInfoRow({super.key, required this.title, this.subtitle, this.icon, this.color, this.trailing, this.onTap});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? Icons.check_circle_rounded, size: AppIconSize.sm + 1, color: appInk(context, tone)),
          ),
          const SizedBox(width: AppSpace.xs + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.row(context).copyWith(height: 1.45)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(subtitle!, style: AppType.meta(context).copyWith(height: 1.5)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpace.xs), Flexible(child: trailing!)],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(AppRadius.chip), onTap: onTap, child: row);
  }
}

/// The weekly schedule as day / time chips on the sky tint (schedule information, D-613).
class CourseScheduleChips extends StatelessWidget {
  const CourseScheduleChips({super.key, required this.schedules});

  final List<CourseSchedule> schedules;

  @override
  Widget build(BuildContext context) {
    final sky = AppBlockColors.of(context, AppBlockTone.sky);
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        for (final s in schedules)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            decoration: BoxDecoration(
              color: sky.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: sky.border == null ? null : Border.all(color: sky.border!, width: AppBorder.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.dayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: sky.ink),
                ),
                Text(
                  AppTime.clockRange(s.startTime, s.endTime),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(
                    color: sky.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// ★★★★☆ 4.6 (128) — the stars are icons (the app fonts have no star glyphs).
class CourseRatingStars extends StatelessWidget {
  const CourseRatingStars({super.key, required this.value, this.count, this.size = 16, this.color});

  /// 0…5.
  final double value;
  final int? count;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.accent2;
    final v = value.clamp(0.0, 5.0);
    final figure = AppType.label(context).copyWith(
      fontSize: size * 0.85,
      fontWeight: FontWeight.w600,
      color: c.textDark,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            v >= i ? Icons.star_rounded : (v >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: v >= i - 0.5 ? tone : c.textLight.withValues(alpha: 0.6),
          ),
        const SizedBox(width: AppSpace.xs),
        Text(v.toStringAsFixed(1), style: figure),
        if (count != null && count! > 0) ...[
          const SizedBox(width: AppSpace.xxs),
          Flexible(
            child: Text(
              '($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(fontSize: size * 0.75, color: c.textLight),
            ),
          ),
        ],
      ],
    );
  }
}
