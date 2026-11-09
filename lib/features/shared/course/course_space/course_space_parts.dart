// lib/features/shared/course/course_space/course_space_parts.dart
//
// The pieces of [CourseSpace] (course_space.dart), each one plain values only so the layout harness can pump it:
//   CourseSpaceHero        cover · glass top bar · pills · title · teacher · glass stats + progress ring
//   CourseSpaceTabBar      the calm segmented bar (scrolls when the tabs do not fit), count + live dot per tab
//   CourseSpotlightStack   column of contextual cards that leaves no gap for a card that hides itself
//   CourseSpotlightCard    one contextual card: icon · title · line · progress · action
//   CourseReadinessCard    the teacher's setup checklist (n of m done, the open steps as chips)
//   CourseActionStrip      phones: horizontally scrolling quick-action tiles
//   CourseActionList       desktop side column: the same actions as a list card
//   CourseSideCard         the side column's card surface
//   CourseInfoGroup        the About / Details tab: ONE card, its sections split by hairlines
//   CourseInfoSection      a titled section of that card (+ trailing action)
//   CourseInfoRow          icon · title · subtitle · trailing row inside a section
//   CourseScheduleChips    the weekly schedule as day / time chips
//   CourseRatingStars      ★★★★☆ 4.6 (n) drawn with icons (never star glyphs: the app fonts lack them)
//   CourseSectionHeader    title · count · trailing (the list header of a tab)
//
// Type scale (shared with the homes): hero title w700 · titles w600 · row titles w500 · body / meta w400 muted ·
// figures w600. Hairline borders, no heavy shadows, one accent per card, the 8 · 16 · 24 · 32 rhythm.
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/app_time.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/parent_component.dart';
import '../../../teacher/home/teacher_models.dart' show CourseSchedule;
import '../private_flag.dart';
import 'course_space.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

TextStyle _ts(double size, FontWeight w, Color color, {double? h}) =>
    TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: color, height: h);

Widget _keyed(String? featureKey, Widget child) =>
    featureKey == null ? child : ParentComponent(featureKey: featureKey, child: child);

/// A tone as ink on the page: in dark mode a deep brand colour is mixed toward the light text so icons stay legible.
Color _lift(BuildContext context, Color tone) {
  final c = context.colors;
  return c.isDark ? Color.lerp(tone, c.textDark, 0.4)! : tone;
}

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
  });

  final CourseSpaceHeroData data;
  final Widget? background;
  final List<CourseSpaceTopAction> topActions;
  final VoidCallback? onBack;

  /// true → a rounded card (desktop), false → full bleed with rounded bottom corners (phone).
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
        final big = w >= 640;
        final minH = big ? 340.0 : (w * 0.92).clamp(300.0, 400.0);
        final pad = big ? 28.0 : 20.0;
        final radius = rounded
            ? BorderRadius.circular(28)
            : const BorderRadius.vertical(bottom: Radius.circular(28));
        final top = rounded ? 0.0 : MediaQuery.paddingOf(context).top;

        final pills = <Widget>[
          if (data.category != null && data.category!.isNotEmpty)
            _keyed('course_hero.category', _HeroPill(label: data.category!)),
          if (data.isPrivate) _keyed('course_hero.private', PrivateFlag(label: data.privateLabel)),
          for (final b in data.badges) _keyed(b.featureKey, _HeroPill(label: b.label, icon: b.icon, color: b.color)),
        ];

        return ClipRRect(
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH + top),
            child: Stack(
              alignment: AlignmentDirectional.bottomStart,
              children: [
                Positioned.fill(child: background ?? CourseCover(imageUrl: data.imageUrl)),
                // scrim: a soft top so the buttons read on a light image, a deep bottom for the text
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.28, 0.55, 1],
                        colors: [
                          c.heroShade.withValues(alpha: 0.5),
                          c.heroShade.withValues(alpha: 0.08),
                          c.heroShade.withValues(alpha: 0.4),
                          c.heroShade.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: top + 8,
                  left: pad - 8,
                  right: pad - 8,
                  child: _keyed('course_hero.topbar', _TopBar(onBack: onBack, actions: topActions)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, top + 72, pad, big ? 24 : 20),
                  child: Directionality(
                    textDirection: Helpers.textDirOf(data.title),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pills.isNotEmpty) ...[
                          Wrap(spacing: 6, runSpacing: 6, children: pills),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          data.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: big ? 30 : 24,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            letterSpacing: -0.2,
                            color: c.onHero,
                            shadows: [Shadow(color: c.heroShade.withValues(alpha: 0.4), blurRadius: 12)],
                          ),
                        ),
                        if (data.subtitle != null && data.subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _keyed(
                            'course_hero.description',
                            Text(
                              data.subtitle!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(13.5, FontWeight.w400, c.onHeroMuted, h: 1.5),
                            ),
                          ),
                        ],
                        if (data.teacherName != null && data.teacherName!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _keyed(
                            'course_hero.teacher',
                            _TeacherChip(
                              name: data.teacherName!,
                              imageUrl: data.teacherImageUrl,
                              onTap: data.onTeacher,
                            ),
                          ),
                        ],
                        if (data.stats.isNotEmpty || data.progress != null) ...[
                          const SizedBox(height: 16),
                          _keyed('course_hero.stats', _StatsStrip(data: data)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The cover image fading in over the brand gradient (no flash, no layout jump), or the gradient alone.
class CourseCover extends StatelessWidget {
  const CourseCover({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: c.accentGradient),
      child: Center(child: Icon(Icons.school_rounded, size: 88, color: c.onHero.withValues(alpha: 0.13))),
    );
    if (imageUrl.isEmpty) return fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          frameBuilder: (_, child, frame, sync) => sync
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 350),
                  child: child,
                ),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// The hero's top bar: back (a frosted disc at the start) · the inline actions in ONE frosted capsule at the end,
/// ending with ⋮ when some actions are rarer (D-111). Every target is 48 px; the glass is the darkened hero shade so
/// it reads on a light cover in both themes; the icons mirror themselves in Arabic.
class _TopBar extends StatelessWidget {
  const _TopBar({this.onBack, required this.actions});

  final VoidCallback? onBack;
  final List<CourseSpaceTopAction> actions;

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
        return Row(
          children: [
            if (onBack != null)
              CourseCoverButton(
                icon: Icons.arrow_back_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onTap: onBack!,
              ),
            Expanded(
              child: !hasGroup
                  ? const SizedBox.shrink()
                  : Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: _GlassCapsule(
                    children: [
                      for (final a in inline)
                        a.primary && wide
                            ? _CapsuleLabelButton(action: a)
                            : _CapsuleIconButton(action: a),
                      if (menu.isNotEmpty) _CapsuleMenu(actions: menu),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Frosted glass over the cover: blur + the darkened hero shade + a hairline in the on-hero ink.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.radius});

  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: c.heroShade.withValues(alpha: 0.34),
            border: Border.all(color: c.heroGlassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassCapsule extends StatelessWidget {
  const _GlassCapsule({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _Glass(
    radius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _CapsuleIconButton extends StatelessWidget {
  const _CapsuleIconButton({required this.action});

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
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: action.onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(action.icon, size: 20, color: action.color ?? c.onHero),
            ),
          ),
        ),
      ),
    );
  }
}

/// The primary action with its word (wide screens): "✎ Edit course".
class _CapsuleLabelButton extends StatelessWidget {
  const _CapsuleLabelButton({required this.action});

  final CourseSpaceTopAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Material(
        color: c.onHero.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 18, color: action.color ?? c.onHero),
                  const SizedBox(width: 8),
                  Text(action.tooltip, maxLines: 1, style: _ts(13, FontWeight.w600, c.onHero)),
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
  const _CapsuleMenu({required this.actions});

  final List<CourseSpaceTopAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      tooltip: _t('المزيد', 'More'),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (i) => actions[i].onTap(),
      itemBuilder: (_) => [
        for (final (i, a) in actions.indexed)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(a.icon, size: 20, color: a.color ?? c.textMedium),
                const SizedBox(width: 12),
                Flexible(child: Text(a.tooltip, style: _ts(14, FontWeight.w500, c.textDark))),
              ],
            ),
          ),
      ],
      child: SizedBox(width: 48, height: 48, child: Icon(Icons.more_vert_rounded, size: 20, color: c.onHero)),
    );
  }
}

/// A round frosted button over the cover (back …): a 40 px disc in a 48 px target, darkened glass so it reads on a
/// light image too.
class CourseCoverButton extends StatelessWidget {
  const CourseCoverButton({super.key, required this.icon, required this.onTap, this.tooltip, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Icon colour; null → the on-hero ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: _Glass(
                  radius: BorderRadius.circular(22),
                  child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: color ?? c.onHero)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;

  /// A tinted pill in this colour (draft · live); null → the glass pill.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone == null ? c.heroGlass : tone.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone ?? c.heroGlassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c.onHero), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ts(11.5, FontWeight.w500, c.onHero, h: 1.35),
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
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final chip = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 8, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.heroGlassBorder)),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: c.heroGlass,
              backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
              onBackgroundImageError: hasImage ? (_, _) {} : null,
              child: hasImage
                  ? null
                  : Text(name.characters.first, style: _ts(12, FontWeight.w600, c.onHero)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ts(13.5, FontWeight.w500, c.onHero),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.onHeroMuted),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: chip),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.data});

  final CourseSpaceHeroData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final divider = Container(width: 1, height: 28, color: c.heroGlassBorder);
    final cells = <Widget>[
      for (final s in data.stats) _keyed(s.featureKey, _StatCell(stat: s)),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: c.heroGlass,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.heroGlassBorder),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) divider,
                Expanded(child: cells[i]),
              ],
              if (data.progress != null) ...[
                if (cells.isNotEmpty) divider,
                const SizedBox(width: 10),
                _keyed('course_hero.progress', _ProgressRing(value: data.progress!, label: data.progressLabel)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final CourseSpaceStat stat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(stat.icon, size: 14, color: c.onHeroMuted),
                const SizedBox(width: 5),
                Text(stat.value, style: _ts(16, FontWeight.w600, c.onHero)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: c.onHeroMuted,
              decoration: stat.onTap == null ? null : TextDecoration.underline,
              decorationColor: c.onHeroFaint,
            ),
          ),
        ],
      ),
    );
    if (stat.onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: stat.onTap, child: body),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value, this.label});

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value.clamp(0.0, 1.0);
    return Tooltip(
      message: label ?? '',
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                backgroundColor: c.heroGlassBorder,
                valueColor: AlwaysStoppedAnimation(c.success),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text('${(v * 100).round()}%', style: _ts(10.5, FontWeight.w600, c.onHero)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab bar
// ═════════════════════════════════════════════════════════════════════════════

class CourseSpaceTabBar extends StatelessWidget {
  const CourseSpaceTabBar({super.key, required this.tabs, required this.active, required this.onTab});

  final List<CourseSpaceTab> tabs;
  final String active;
  final ValueChanged<String> onTab;

  /// Equal segments get a label beside the icon when every tab's label + count fits whole in its segment (H7:
  /// "Sessi… 4" at 390 px in English), else the icon above the label (the count beside the icon) from [_stackedW];
  /// narrower still, the row scrolls.
  static const double _rowW = 110, _stackedW = 64;

  static double _textW(BuildContext context, String text, double size, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _ts(size, weight, const Color(0xFF000000), h: 1.4)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = tp.width;
    tp.dispose();
    return width;
  }

  /// The width one tab needs laid out as a row: pill padding 14 + 14, hairline, icon 18 + 8, label, count 6 + n.
  static double _rowNeed(BuildContext context, CourseSpaceTab t) {
    var need = 28 + 2 + 18 + 8 + _textW(context, t.label, 13, FontWeight.w600) + 2;
    if (t.live) need += 14;
    if (t.count != null && t.count! > 0) need += 6 + _textW(context, '${t.count}', 11.5, FontWeight.w600);
    return need;
  }

  /// The width one tab needs stacked: pill padding 4 + 4, hairline, the label whole ("Announc…" at 390 px with five
  /// teacher tabs).
  static double _stackedNeed(BuildContext context, CourseSpaceTab t) =>
      8 + 2 + _textW(context, t.label, 11.5, FontWeight.w600) + 1;

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
    // padding 8 + 8, track 3 + 3, pill 9 + 9 (stacked 7 + 7), the active pill's hairline 1 + 1
    if (_stacked(context, width - kCourseGutter * 2 - 6, _visible(tabs))) {
      return (16 + 6 + 14 + 2 + 18 + 3 + scaler.scale(11.5) * 1.45).ceilToDouble();
    }
    final line = scaler.scale(13) * 1.45;
    return (16 + 6 + 18 + 2 + (line < 20 ? 20 : line)).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = _visible(tabs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, 8, kCourseGutter, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.textDark.withValues(alpha: c.isDark ? 0.07 : 0.045),
          borderRadius: BorderRadius.circular(15),
        ),
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
    if (animate) {
      _ctl.animateTo(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
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
    final iconColor = active ? _lift(context, c.primary) : c.textLight;
    final count = tab.count != null && tab.count! > 0
        ? Text(
            '${tab.count}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: _ts(11.5, FontWeight.w600, active ? c.textMedium : c.textLight, h: stacked ? 1.0 : 1.4),
          )
        : null;
    final label = Text(
      tab.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _ts(stacked ? 11.5 : 13, active ? FontWeight.w600 : FontWeight.w500, fg, h: 1.4),
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
                    if (tab.live) ...[_LiveDot(color: c.danger), const SizedBox(width: 4)],
                    Icon(tab.icon, size: 18, color: iconColor),
                    // the count beside the icon, so the label below keeps the whole segment
                    if (count != null) ...[const SizedBox(width: 4), Flexible(child: count)],
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
              const SizedBox(width: 8),
              Flexible(child: label),
              if (count != null) ...[const SizedBox(width: 6), count],
            ],
          );
    return Semantics(
      selected: active,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: stacked
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 7)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active ? c.cardBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? c.divider.withValues(alpha: 0.8) : Colors.transparent, width: 0.8),
            boxShadow: active
                ? [BoxShadow(color: c.heroShade.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]
                : null,
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

/// Stacks contextual cards 8 px apart. A child that renders nothing (SizedBox.shrink) shares a run with its
/// neighbour, so it leaves no gap.
class CourseSpotlightStack extends StatelessWidget {
  const CourseSpotlightStack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      runSpacing: 8,
      children: [for (final w in children) ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth), child: w)],
    ),
  );
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

  /// The loudest state (live now): the whole card takes a soft wash of its tone.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final ink = _lift(context, tone);

    Widget? action;
    if (actionLabel != null && onAction != null) {
      action = FilledButton.icon(
        onPressed: onAction,
        icon: Icon(actionIcon ?? Icons.arrow_forward_rounded, size: 17),
        label: Text(actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: tone,
          foregroundColor: c.onHero,
          elevation: 0,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        // the action sits at the end while the text keeps ~60 % of the card; below that it goes under the text
        final roomy = box.maxWidth >= 340 * MediaQuery.textScalerOf(context).scale(1);
        final act = action == null
            ? null
            : roomy
            ? ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.36), child: action)
            : action;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (live) ...[_LiveDot(color: c.danger), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _ts(14.5, FontWeight.w600, c.textDark, h: 1.35),
                  ),
                ),
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _ts(12.5, FontWeight.w400, c.textMedium, h: 1.45),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: tone.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(ink),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    progressLabel ?? '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
                    style: _ts(12, FontWeight.w600, c.textMedium),
                  ),
                ],
              ),
            ],
          ],
        );
        final iconTile = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: ink, size: 20),
        );

        final body = Padding(
          padding: const EdgeInsets.all(16),
          child: roomy || act == null
              ? Row(
                  children: [
                    iconTile,
                    const SizedBox(width: 12),
                    Expanded(child: text),
                    if (act != null) ...[const SizedBox(width: 12), act],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [iconTile, const SizedBox(width: 12), Expanded(child: text)],
                    ),
                    const SizedBox(height: 12),
                    act,
                  ],
                ),
        );

        return Container(
          decoration: BoxDecoration(
            color: filled ? Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.14 : 0.06), c.cardBg) : c.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: filled ? tone.withValues(alpha: 0.28) : c.divider.withValues(alpha: 0.7)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: body),
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
    final tone = _lift(context, c.warning);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.rocket_launch_rounded, color: tone, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? _t('جهّز كورسك', 'Get your course ready'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ts(14.5, FontWeight.w600, c.textDark, h: 1.35),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _t('$done من ${items.length} خطوات مكتملة', '$done of ${items.length} steps done'),
                      style: _ts(12.5, FontWeight.w400, c.textMedium),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done / items.length,
              minHeight: 4,
              backgroundColor: c.warning.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in open)
                ActionChip(
                  avatar: Icon(i.icon ?? Icons.add_circle_outline_rounded, size: 16, color: _lift(context, c.primary)),
                  label: Text(i.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  labelStyle: _ts(12.5, FontWeight.w500, c.textDark),
                  backgroundColor: c.cardBg,
                  side: BorderSide(color: c.divider),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        const pad = kCourseGutter - 4;
        // Every tile fits → they share the width evenly; otherwise the row scrolls (and the cut tile says so).
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
    final c = context.colors;
    showAppModalSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Text(_t('اختصارات الكورس', 'Course shortcuts'), style: _ts(14, FontWeight.w600, c.textDark)),
              ),
              for (final a in rest)
                _ActionRow(
                  action: a,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    a.onTap();
                  },
                ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: fill ? null : width - 8,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: action.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIcon(icon: action.icon, tone: tone, badge: action.badge, size: 48),
                  const SizedBox(height: 6),
                  Text(
                    action.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: _ts(11.5, FontWeight.w500, c.textMedium, h: 1.3),
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

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tone, this.badge, required this.size});

  final IconData icon;
  final Color tone;
  final String? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = _lift(context, this.tone);
    return SizedBox(
      width: size + 6,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: this.tone.withValues(alpha: c.isDark ? 0.16 : 0.09),
              borderRadius: BorderRadius.circular(size * 0.34),
            ),
            child: Icon(icon, color: tone, size: size * 0.44),
          ),
          if (badge != null && badge!.isNotEmpty)
            PositionedDirectional(
              top: -2,
              end: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: c.danger,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.cardBg, width: 1.5),
                ),
                child: Text(badge!, textAlign: TextAlign.center, style: _ts(9.5, FontWeight.w600, c.onHero)),
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
    final c = context.colors;
    return CourseSideCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Text(
              title ?? _t('اختصارات الكورس', 'Course shortcuts'),
              style: _ts(12.5, FontWeight.w600, c.textMedium),
            ),
          ),
          for (final a in shown) _ActionRow(action: a, onTap: a.onTap),
        ],
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
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      _ActionIcon(icon: a.icon, tone: a.color ?? c.primary, badge: a.badge, size: 38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(13.5, FontWeight.w500, c.textDark),
                            ),
                            if (a.caption != null && a.caption!.isNotEmpty)
                              Text(
                                a.caption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _ts(11.5, FontWeight.w400, c.textLight),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.textLight, size: 20),
                    ],
                  ),
                ),
              ),
            );
  }
}

/// The card surface of the side column (and of any block that should look like it).
class CourseSideCard extends StatelessWidget {
  const CourseSideCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.accent});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// A thin coloured border (e.g. primary for the buy card).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent?.withValues(alpha: 0.22) ?? c.divider.withValues(alpha: 0.7)),
        boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab content: list header · About / Details
// ═════════════════════════════════════════════════════════════════════════════

/// Title · count · trailing — the header of a list inside a tab.
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
      padding: padding ?? const EdgeInsets.fromLTRB(kCourseGutter + 4, 8, kCourseGutter, 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ts(16, FontWeight.w600, c.textDark),
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 8),
                  Text('$count', style: _ts(13, FontWeight.w500, c.textLight)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: c.divider.withValues(alpha: 0.6)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A titled section of a [CourseInfoGroup] (on its own it draws no box either).
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: _lift(context, tone)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _ts(14.5, FontWeight.w600, c.textDark, h: 1.35),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: trailing!)],
              ],
            ),
            if (children.isNotEmpty) ...[const SizedBox(height: 12), ...children],
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? Icons.check_circle_rounded, size: 17, color: _lift(context, tone).withValues(alpha: 0.85)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _ts(13.5, FontWeight.w500, c.textDark, h: 1.4)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: _ts(12.5, FontWeight.w400, c.textMedium, h: 1.45)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: trailing!)],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: row);
  }
}

/// The weekly schedule as day / time chips.
class CourseScheduleChips extends StatelessWidget {
  const CourseScheduleChips({super.key, required this.schedules});

  final List<CourseSchedule> schedules;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in schedules)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: c.isDark ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.dayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(12.5, FontWeight.w600, c.textDark),
                ),
                Text(
                  AppTime.clockRange(s.startTime, s.endTime),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(12, FontWeight.w400, c.textMedium),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            v >= i ? Icons.star_rounded : (v >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: v >= i - 0.5 ? tone : c.textLight.withValues(alpha: 0.6),
          ),
        const SizedBox(width: 8),
        Text(v.toStringAsFixed(1), style: _ts(size * 0.85, FontWeight.w600, c.textDark)),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ts(size * 0.75, FontWeight.w400, c.textLight),
            ),
          ),
        ],
      ],
    );
  }
}
