// lib/features/shared/course/course_space/course_space_parts.dart
//
// The pieces of [CourseSpace] (course_space.dart), each one plain values only so the layout harness can pump it:
//   CourseSpaceHero        cinematic cover · glass top bar · pills · title · teacher · glass stats + progress ring
//   CourseSpaceTabBar      the segmented pill bar (scrolls when the tabs do not fit), count + live dot per tab
//   CourseSpotlightStack   column of contextual cards that leaves no gap for a card that hides itself
//   CourseSpotlightCard    one contextual card: icon · title · line · progress · action
//   CourseReadinessCard    the teacher's setup checklist (n of m done, the open steps as chips)
//   CourseActionStrip      phones: horizontally scrolling quick-action tiles
//   CourseActionList       desktop side column: the same actions as a list card
//   CourseSideCard         the side column's card surface
//   CourseInfoSection      a titled card of the About / Details tab (+ trailing action)
//   CourseInfoRow          icon · title · subtitle · trailing row inside a section
//   CourseScheduleChips    the weekly schedule as day / time chips
//   CourseSectionHeader    accent bar · title · count · trailing (the list header of a tab)
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/app_time.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/parent_component.dart';
import '../../../teacher/home/teacher_models.dart' show CourseSchedule;
import '../private_flag.dart';
import '../topbar.dart' show GlassBtn;
import 'course_space.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

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
        final pad = big ? 28.0 : 18.0;
        final radius = rounded
            ? BorderRadius.circular(28)
            : const BorderRadius.vertical(bottom: Radius.circular(30));
        final top = MediaQuery.paddingOf(context).top;

        final pills = <Widget>[
          if (data.category != null && data.category!.isNotEmpty)
            _keyed('course_hero.category', _HeroPill(label: data.category!, color: c.primary.withValues(alpha: 0.92))),
          if (data.isPrivate) _keyed('course_hero.private', PrivateFlag(label: data.privateLabel)),
          for (final b in data.badges) _keyed(b.featureKey, _HeroPill(label: b.label, icon: b.icon, color: b.color)),
        ];

        return ClipRRect(
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH + (rounded ? 0 : top)),
            child: Stack(
              alignment: AlignmentDirectional.bottomStart,
              children: [
                Positioned.fill(child: background ?? CourseCover(imageUrl: data.imageUrl)),
                // cinematic scrim: a soft top for the buttons, a deep bottom for the text
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.3, 0.58, 1],
                        colors: [
                          c.heroShade.withValues(alpha: 0.55),
                          c.heroShade.withValues(alpha: 0.05),
                          c.heroShade.withValues(alpha: 0.35),
                          c.heroShade.withValues(alpha: 0.96),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: (rounded ? 0 : top) + 10,
                  left: pad - 6,
                  right: pad - 6,
                  child: _keyed('course_hero.topbar', _TopBar(onBack: onBack, actions: topActions)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, (rounded ? 0 : top) + 72, pad, big ? 24 : 18),
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
                            fontSize: big ? 32 : 24,
                            fontWeight: FontWeight.w800,
                            height: 1.22,
                            color: c.onHero,
                            shadows: [Shadow(color: c.heroShade.withValues(alpha: 0.5), blurRadius: 14)],
                          ),
                        ),
                        if (data.subtitle != null && data.subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _keyed(
                            'course_hero.description',
                            Text(
                              data.subtitle!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, height: 1.5, color: c.onHeroMuted),
                            ),
                          ),
                        ],
                        if (data.teacherName != null && data.teacherName!.isNotEmpty) ...[
                          const SizedBox(height: 12),
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

class _TopBar extends StatelessWidget {
  const _TopBar({this.onBack, required this.actions});

  final VoidCallback? onBack;
  final List<CourseSpaceTopAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          GlassBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: onBack!,
          ),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in actions)
                    _keyed(a.featureKey, GlassBtn(icon: a.icon, tooltip: a.tooltip, iconColor: a.color, onTap: a.onTap)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final glass = color == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color ?? c.heroGlass,
        borderRadius: BorderRadius.circular(20),
        border: glass ? Border.all(color: c.heroGlassBorder) : null,
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
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w800, color: c.onHero),
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
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: c.heroGlassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: c.heroGlassBorder,
            backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
            onBackgroundImageError: hasImage ? (_, _) {} : null,
            child: hasImage
                ? null
                : Text(name.characters.first, style: TextStyle(color: c.onHero, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w700, color: c.onHero),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.onHeroMuted, textDirection: Directionality.of(context)),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(30), onTap: onTap, child: chip),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.data});

  final CourseSpaceHeroData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final divider = Container(width: 1, height: 30, color: c.heroGlassBorder);
    final cells = <Widget>[
      for (final s in data.stats) _keyed(s.featureKey, _StatCell(stat: s)),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: c.heroGlass,
            borderRadius: BorderRadius.circular(20),
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
                Icon(stat.icon, size: 15, color: c.onHeroMuted),
                const SizedBox(width: 5),
                Text(
                  stat.value,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 17, fontWeight: FontWeight.w800, color: c.onHero),
                ),
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
              fontSize: 10.5,
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
                strokeWidth: 3.6,
                strokeCap: StrokeCap.round,
                backgroundColor: c.heroGlassBorder,
                valueColor: AlwaysStoppedAnimation(c.success),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '${(v * 100).round()}%',
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 10, fontWeight: FontWeight.w800, color: c.onHero),
                ),
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

  /// Equal segments get a label beside the icon from this width, and the icon above the label from [_stackedW];
  /// narrower still, the row scrolls.
  static const double _rowW = 110, _stackedW = 64;

  static bool _stacked(double inner, int count) {
    final per = count == 0 ? inner : inner / count;
    return per < _rowW && per >= _stackedW;
  }

  /// The bar's height for a page [width] at the current text scale (the pinned header needs a fixed extent).
  static double heightFor(BuildContext context, {required double width, required int count}) {
    final scaler = MediaQuery.textScalerOf(context);
    // padding 10 + 10, container 4 + 4 + border 2, pill 10 + 10 (stacked 8 + 8)
    if (_stacked(width - kCourseGutter * 2 - 10, count)) {
      return (20 + 10 + 16 + 18 + 3 + scaler.scale(11.5) * 1.45).ceilToDouble();
    }
    final line = scaler.scale(13) * 1.45;
    return (20 + 10 + 20 + (line < 20 ? 20 : line)).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = [
      for (final t in tabs)
        if (t.featureKey == null || !AppConfig.disableList.contains(t.featureKey)) t,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, 10, kCourseGutter, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.divider),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final stacked = _stacked(box.maxWidth, visible.length);
            final fits = visible.isEmpty || stacked || box.maxWidth / visible.length >= _rowW;
            Widget item(CourseSpaceTab t) =>
                _TabPill(tab: t, active: t.id == active, stacked: stacked, onTap: () => onTab(t.id));
            if (fits) {
              return Row(children: [for (final t in visible) Expanded(child: item(t))]);
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final t in visible) item(t)]),
            );
          },
        ),
      ),
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
    final fg = active ? c.onHero : c.textMedium;
    final count = tab.count != null && tab.count! > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: active ? c.heroGlass : _lift(context, c.primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${tab.count}',
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: active ? c.onHero : _lift(context, c.primary),
              ),
            ),
          )
        : null;
    final label = Text(
      tab.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppFonts.family,
        fontSize: stacked ? 11.5 : 13,
        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        color: fg,
      ),
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
                    if (tab.live) ...[_LiveDot(color: active ? c.onHero : c.danger), const SizedBox(width: 4)],
                    Icon(tab.icon, size: 18, color: fg),
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
              if (tab.live) ...[_LiveDot(color: active ? c.onHero : c.danger), const SizedBox(width: 6)],
              Icon(tab.icon, size: 18, color: fg),
              const SizedBox(width: 7),
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
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? c.primaryGradient : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: active
                ? [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4))]
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
    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Spotlight
// ═════════════════════════════════════════════════════════════════════════════

/// Stacks contextual cards 10 px apart. A child that renders nothing (SizedBox.shrink) shares a run with its
/// neighbour, so it leaves no gap.
class CourseSpotlightStack extends StatelessWidget {
  const CourseSpotlightStack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      runSpacing: 10,
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

  /// A gradient card with on-hero ink (the loudest state: live now).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final ink = filled ? c.onHero : c.textDark;
    final sub = filled ? c.onHeroMuted : c.textMedium;

    Widget? action;
    if (actionLabel != null && onAction != null) {
      action = FilledButton.icon(
        onPressed: onAction,
        icon: Icon(actionIcon ?? Icons.arrow_forward_rounded, size: 17),
        label: Text(actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: filled ? c.onHero : tone,
          foregroundColor: filled ? tone : c.onHero,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        // the action sits at the end while the text keeps ~60 % of the card; below that it goes under the text
        final roomy = box.maxWidth >= 300 * MediaQuery.textScalerOf(context).scale(1);
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
                if (live) ...[_LiveDot(color: filled ? c.onHero : c.danger), const SizedBox(width: 7)],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 14.5, fontWeight: FontWeight.w800, color: ink),
                  ),
                ),
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, height: 1.4, color: sub),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: filled ? c.heroGlass : tone.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(filled ? c.onHero : tone),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    progressLabel ?? '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w800, color: ink),
                  ),
                ],
              ),
            ],
          ],
        );
        final iconTile = Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: filled ? c.heroGlass : tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: filled ? c.onHero : _lift(context, tone), size: 23),
        );

        final body = Padding(
          padding: const EdgeInsets.all(14),
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
            gradient: filled
                ? LinearGradient(colors: [tone, tone.withValues(alpha: 0.78)])
                : LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [tone.withValues(alpha: 0.10), c.cardBg],
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: filled ? tone : tone.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: (filled ? tone : c.heroShade).withValues(alpha: filled ? 0.3 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.warning.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.rocket_launch_rounded, color: c.warning, size: 22),
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
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _t('$done من ${items.length} خطوات مكتملة', '$done of ${items.length} steps done'),
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: done / items.length,
              minHeight: 6,
              backgroundColor: c.warning.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(c.warning),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in open)
                ActionChip(
                  avatar: Icon(i.icon ?? Icons.add_circle_outline_rounded, size: 16, color: c.primary),
                  label: Text(i.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  labelStyle: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textDark,
                  ),
                  backgroundColor: c.primary.withValues(alpha: 0.06),
                  side: BorderSide(color: c.primary.withValues(alpha: 0.18)),
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

/// Phones: the course's quick actions as a horizontally scrolling row of tiles.
class CourseActionStrip extends StatelessWidget {
  const CourseActionStrip({super.key, required this.actions});

  final List<CourseSpaceAction> actions;

  @override
  Widget build(BuildContext context) {
    final shown = _visibleActions(actions);
    if (shown.isEmpty) return const SizedBox.shrink();
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
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final a in shown) _ActionTile(action: a)],
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, this.fill = false});

  static const double width = 96;

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
            borderRadius: BorderRadius.circular(18),
            onTap: action.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIcon(icon: action.icon, tone: tone, badge: action.badge, size: 54),
                  const SizedBox(height: 7),
                  Text(
                    action.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: c.textDark,
                    ),
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
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [tone.withValues(alpha: 0.16), tone.withValues(alpha: 0.06)],
              ),
              borderRadius: BorderRadius.circular(size * 0.32),
              border: Border.all(color: tone.withValues(alpha: 0.18)),
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
                child: Text(
                  badge!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: c.onHero),
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
    final c = context.colors;
    return CourseSideCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Text(
              title ?? _t('اختصارات الكورس', 'Course shortcuts'),
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w800, color: c.textMedium),
            ),
          ),
          for (final a in shown)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: a.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      _ActionIcon(icon: a.icon, tone: a.color ?? c.primary, badge: a.badge, size: 40),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppFonts.family,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: c.textDark,
                              ),
                            ),
                            if (a.caption != null && a.caption!.isNotEmpty)
                              Text(
                                a.caption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: c.textLight),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.textLight, textDirection: Directionality.of(context)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The card surface of the side column (and of any block that should look like it).
class CourseSideCard extends StatelessWidget {
  const CourseSideCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.accent});

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
        border: Border.all(color: accent?.withValues(alpha: 0.25) ?? c.divider),
        boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// About / details content
// ═════════════════════════════════════════════════════════════════════════════

/// Accent bar · title · count · trailing — the header of a list inside a tab.
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
      padding: padding ?? const EdgeInsets.fromLTRB(kCourseGutter, 8, kCourseGutter, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(gradient: c.primaryGradient, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 16, fontWeight: FontWeight.w800, color: c.textDark),
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _lift(context, c.primary).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _lift(context, c.primary),
                      ),
                    ),
                  ),
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

/// A titled card of the About / Details tab.
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
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.divider),
          boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: _lift(context, tone)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 14.5, fontWeight: FontWeight.w800, color: c.textDark),
                  ),
                ),
                ?trailing,
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
            child: Icon(icon ?? Icons.check_circle_rounded, size: 18, color: _lift(context, tone)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 13.5, fontWeight: FontWeight.w700, color: c.textDark),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, height: 1.45, color: c.textMedium)),
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
              color: c.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.primary.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_repeat_rounded, size: 16, color: _lift(context, c.primary)),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.dayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, fontWeight: FontWeight.w800, color: c.textDark),
                      ),
                      Text(
                        '${AppTime.clock(s.startTime)} – ${AppTime.clock(s.endTime)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: c.textMedium),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
