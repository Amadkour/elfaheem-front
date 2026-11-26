// lib/features/data_lab/data_lab_widgets.dart
// Small reusable building blocks of the Data Lab (all colours come from the app theme). Warm Editorial (D-610 –
// D-629): paper cards on a warm hairline, the hero is a tinted block, chips / buttons / fields wear the kit's
// control language (radius 14, solid emerald for the chosen thing, never a gradient wash).
library;

import 'dart:math' as math;


import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';

import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_chips.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_badges.dart' show appWashOn;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_gradients.dart' show AppBrandLayer;
import 'package:flutter_education_app/design/app_hero.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show AppFieldLabel, appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

/// Translation with a friendly English fallback while a key is not in the language files yet.
String dlTr(String key, String fallback) {
  final v = key.tr;
  return (v.isEmpty || v == key) ? fallback : v;
}

/// The kit's text style (appText): the person's font, and their reading spacing on an explicit height
/// (an inherited height gets it from AppDisplayScope's default style).
TextStyle dlText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) {
  final sp = ReadingSpacing.current;
  return TextStyle(
    fontFamily: AppFonts.family,
    fontSize: size,
    fontWeight: w,
    color: c,
    height: sp.height(h),
    wordSpacing: sp.isNormal ? null : sp.wordSpacing,
    letterSpacing: sp.letters(AppConfig.lang),
  );
}

/// Traffic-light colour for a 0–100 value, taken from the active theme.
Color dlScoreColor(BuildContext context, double? v) {
  final c = context.colors;
  if (v == null) return c.textLight;
  if (v >= 75) return c.success;
  if (v >= 50) return c.warning;
  return c.danger;
}

/// Tabular digits for figures that sit in a row (they do not dance while they count).
const List<FontFeature> dlTabular = [FontFeature.tabularFigures()];

/// Paper card used by every block of the Data Lab: the card surface on a warm hairline, radius `card`, no resting
/// shadow (D-612). A tappable card presses in (D-582).
class DlCard extends StatelessWidget {
  const DlCard({super.key, required this.child, this.padding = AppSpace.card, this.margin, this.onTap, this.onLongPress});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  /// A long press (e.g. starts a selection); null: none.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.cardAll;
    return AppPressScale(
      enabled: onTap != null || onLongPress != null,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: r,
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: ClipRRect(
          borderRadius: r,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, onLongPress: onLongPress, child: Padding(padding: padding, child: child)),
          ),
        ),
      ),
    );
  }
}

/// The page's hero is the kit's (KIT_SPEC §5.2): the old names stay for the Data Lab's callers.
typedef DlHero = AppHero;
typedef DlHeroStat = AppHeroStat;

/// Tonal pill button (Import / Export / New column …): the tone's tint with its readable ink, radius `control`,
/// like `AppButton.tonal`; presses in.
class DlActionPill extends StatelessWidget {
  const DlActionPill({super.key, required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    // the label / icon ink: the tone made readable on its own tint in the open mode
    final ink = appInk(context, col);
    final off = onTap == null;
    final r = AppRadius.controlAll;
    return Semantics(
      container: true,
      button: true,
      enabled: !off,
      child: DlTapTarget(
        child: AppPressScale(
          enabled: !off,
          child: Opacity(
            opacity: off ? 0.45 : 1,
            child: Material(
              color: col.withValues(alpha: c.isDark ? 0.18 : 0.10),
              borderRadius: r,
              child: InkWell(
                borderRadius: r,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: AppIconSize.md, color: ink),
                    const SizedBox(width: AppSpace.xs),
                    // Flexible: a long label (or a big text scale on a phone) ellipsizes instead of overflowing.
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grows a compact control's tap target to the Material minimum, 48 x 48 (which also covers iOS's 44 x 44),
/// without changing how it looks: the same idea as a Material button's padded tap target. The child keeps the
/// incoming width constraints (a pill that fills an Expanded still fills it) and its own height, and sits centred
/// in a box of at least 48 x 48. A tap anywhere in that box goes to the child (at its centre). Put a
/// `Semantics(container: true)` above it so the screen reader's button is the whole box too.
class DlTapTarget extends SingleChildRenderObjectWidget {
  const DlTapTarget({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDlTapTarget();
}

class _RenderDlTapTarget extends RenderShiftedBox {
  _RenderDlTapTarget() : super(null);

  static const double _min = kMinInteractiveDimension;

  static BoxConstraints _forChild(BoxConstraints c) =>
      BoxConstraints(minWidth: c.minWidth, maxWidth: c.maxWidth, maxHeight: c.maxHeight);

  Size _grow(BoxConstraints c, Size child) =>
      c.constrain(Size(math.max(child.width, _min), math.max(child.height, _min)));

  @override
  double computeMinIntrinsicWidth(double height) => math.max(super.computeMinIntrinsicWidth(height), _min);

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(super.computeMaxIntrinsicWidth(height), _min);

  @override
  double computeMinIntrinsicHeight(double width) => math.max(super.computeMinIntrinsicHeight(width), _min);

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(super.computeMaxIntrinsicHeight(width), _min);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    return _grow(constraints, c == null ? Size.zero : c.getDryLayout(_forChild(constraints)));
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = _grow(constraints, Size.zero);
      return;
    }
    c.layout(_forChild(constraints), parentUsesSize: true);
    size = _grow(constraints, c.size);
    (c.parentData! as BoxParentData).offset =
        Offset((size.width - c.size.width) / 2, (size.height - c.size.height) / 2);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final c = child;
    if (c == null || !size.contains(position)) return false;
    // around the visible control: hand the tap to its centre
    final center = c.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, _) => c.hitTest(result, position: center),
    );
  }
}

/// A thin progress bar with a value, coloured by how good the number is.
class DlBar extends StatelessWidget {
  const DlBar({super.key, required this.value, this.max = 100, this.height = 7, this.color, this.marker});

  final double? value;
  final double max;
  final double height;
  final Color? color;

  /// Optional marker (class average), same scale as [value].
  final double? marker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = value == null ? 0.0 : (value! / (max == 0 ? 100 : max)).clamp(0.0, 1.0);
    // the redesign kit (KIT_SPEC §5.1): the area set's gradient a -> b on the kit track; an explicit colour stays
    final set = AppAreaScope.of(context);
    final fill = color == null ? LinearGradient(colors: [set.a, set.b]) : null;
    final r = BorderRadius.circular(AppRadius.pill);
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: height + AppSpace.xs,
        child: Stack(alignment: AlignmentDirectional.centerStart, children: [
          Container(height: height, decoration: BoxDecoration(color: c.kit.track, borderRadius: r)),
          // fills from 0 the first time, glides on a change (D-582)
          AppFill(
            value: pct,
            builder: (_, v) => Container(
                height: height,
                width: w * v,
                decoration: BoxDecoration(color: color, gradient: fill, borderRadius: r)),
          ),
          if (marker != null)
            PositionedDirectional(
              start: (w * (marker! / (max == 0 ? 100 : max)).clamp(0.0, 1.0)) - AppBorder.hairline,
              child: Container(width: AppBorder.focus, height: height + AppSpace.xs, color: c.textDark.withValues(alpha: 0.55)),
            ),
        ]),
      );
    });
  }
}

/// Round gauge, e.g. progress 72 %.
class DlRing extends StatelessWidget {
  const DlRing({super.key, required this.value, required this.label, this.size = 86, this.color});

  final double? value;
  final String label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? dlScoreColor(context, value);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // the arc inks itself in (M2, AppInkRing); the figure counts up; nothing moves under Reduce motion
      AppInkRing(
        value: ((value ?? 0) / 100).clamp(0.0, 1.0),
        color: col,
        track: c.kit.track,
        size: size,
        stroke: size * 0.115,
        center: Semantics(
          label: value == null ? '–' : '${value!.round()}%',
          child: ExcludeSemantics(
            child: value == null
                ? Text('–', style: AppType.figure(context).copyWith(color: c.textDark, fontSize: size * 0.22))
                : AppCountUp('${value!.round()}%',
                    textDirection: TextDirection.ltr,
                    // the figure scales with the ring it sits in
                    style: AppType.figure(context).copyWith(color: c.textDark, fontSize: size * 0.22)),
          ),
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      Text(label, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
    ]);
  }
}

/// Round avatar with the first letter when there is no photo.
class DlAvatar extends StatelessWidget {
  const DlAvatar({super.key, required this.name, this.url, this.size = 40});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      // a flat sky tint (an information surface), never a gradient
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.blockSky),
      child: Text(name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
          // the letter scales with the avatar it sits in
          style: AppType.bodyStrong(context).copyWith(fontSize: size * 0.42, color: c.blockInk)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

/// Small status pill ("Temporary", "Waiting for the student" …): an opaque tint, the tone's readable ink.
class DlTag extends StatelessWidget {
  const DlTag(this.label, this.color, {super.key, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = appInk(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.colors.isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: ink))),
      ]),
    );
  }
}

/// Section title used inside sheets and the profile: the editorial section role, more air above than below.
class DlSectionTitle extends StatelessWidget {
  const DlSectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.md, AppSpace.xxs, AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.section(context)),
            if (subtitle != null) Text(subtitle!, style: AppType.meta(context)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Primary action of the Data Lab sheets: the kit's solid emerald button at full width (busy keeps its width).
class DlPrimaryButton extends StatelessWidget {
  const DlPrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) =>
      AppButton.primary(label: label, onPressed: onPressed, icon: icon, busy: busy, expand: true);
}

/// Text field in the kit's field language: the label above the warm well (`appFieldDecoration`).
class DlField extends StatelessWidget {
  const DlField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboard,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.ltr = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  /// Enter (a multi-line field: Ctrl+Enter on web / desktop, see design/app_keyboard.dart).
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppFieldLabel(label),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          textDirection: ltr ? TextDirection.ltr : null,
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(context, hint: hint),
        ),
      ]),
    );
  }
}

/// Selectable chip: the kit's [AppChip] (KIT_SPEC §5.1; the old call shape compiles unchanged).
typedef DlChoiceChip = AppChip;

// ─────────────────────────────────────────────────────────────────────────────
// Premium building blocks (all colours from the theme)
// ─────────────────────────────────────────────────────────────────────────────

/// Compact number pill: icon · value · label. Used in the sheet's header (paper on a hairline; the tone lives in the
/// icon only, so a row of them stays calm).
class DlStatChip extends StatelessWidget {
  const DlStatChip({super.key, required this.icon, required this.value, required this.label, this.color, this.tooltip});

  final IconData icon;
  final String value, label;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: AppIconSize.lg + AppSpace.xxs,
          height: AppIconSize.lg + AppSpace.xxs,
          decoration: BoxDecoration(color: col.withValues(alpha: c.isDark ? 0.22 : 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: AppIconSize.xs, color: appInk(context, col)),
        ),
        const SizedBox(width: AppSpace.xs),
        AppCountUp(value, memoryKey: 'dlstat:$label',
            style: AppType.bodyStrong(context).copyWith(color: c.textDark, fontFeatures: dlTabular)),
        const SizedBox(width: AppSpace.xxs),
        Text(label, style: AppType.meta(context).copyWith(color: c.textMedium)),
      ]),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// Soft pulsing placeholder while the first page loads (no package needed).
class DlShimmer extends StatefulWidget {
  const DlShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<DlShimmer> createState() => _DlShimmerState();
}

class _DlShimmerState extends State<DlShimmer> with SingleTickerProviderStateMixin {
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
    opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: _a, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

class DlSkeletonBox extends StatelessWidget {
  const DlSkeletonBox({super.key, this.width, this.height = 12, this.radius = AppRadius.chip});

  final double? width;
  final double height, radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: context.colors.inputBg, borderRadius: BorderRadius.circular(radius)),
  );
}

/// The shape of the sheet while it loads: calmer than a spinner, and the page does not jump when data arrives.
class DlSheetSkeleton extends StatelessWidget {
  const DlSheetSkeleton({super.key, this.rows = 9, this.columns = 4});

  final int rows, columns;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DlShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
        children: [
          Row(children: [
            const DlSkeletonBox(width: 120, height: AppSpace.xl),
            for (var j = 0; j < columns; j++) ...[
              const SizedBox(width: AppSpace.sm),
              const Expanded(child: DlSkeletonBox(height: AppSpace.xl)),
            ],
          ]),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < rows; i++)
            Container(
              height: AppTouch.min,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
              child: Row(children: [
                const DlSkeletonBox(width: AppIconSize.lg, height: AppIconSize.lg, radius: AppRadius.pill),
                const SizedBox(width: AppSpace.sm),
                DlSkeletonBox(width: 70.0 + (i * 23) % 40, height: AppSpace.sm),
                const SizedBox(width: AppSpace.lg),
                for (var j = 0; j < columns; j++) ...[
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Center(child: DlSkeletonBox(width: 26.0 + (i + j) * 7 % 20, height: AppSpace.sm))),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

/// Five bars: how the class is spread over 0–20 %, 20–40 % … 80–100 % of the full mark.
class DlHistogram extends StatelessWidget {
  const DlHistogram({super.key, required this.buckets, this.height = 74});

  final List<int> buckets;
  final double height;

  static const _labels = ['0–20', '20–40', '40–60', '60–80', '80–100'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = buckets.fold<int>(0, (m, e) => e > m ? e : m);
    final motion = AppMotion.of(context);
    return Directionality(
      textDirection: TextDirection.ltr, // a scale always reads low → high
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(i < buckets.length ? '${buckets[i]}' : '0',
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark, fontFeatures: dlTabular)),
              const SizedBox(height: AppSpace.xxs),
              // the bars grow once, one after another (a short cascade low → high)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: top == 0 || i >= buckets.length ? 0 : buckets[i] / top),
                duration: motion.slow + Duration(milliseconds: motion.slow == Duration.zero ? 0 : 60 * i),
                curve: AppMotion.curve,
                builder: (_, t, _) => Container(
                  height: AppSpace.xxs + (height - AppSpace.xxs) * t,
                  decoration: BoxDecoration(
                    color: dlScoreColor(context, i * 20.0 + 10).withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.chip), bottom: Radius.circular(AppSpace.xxs)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              FittedBox(fit: BoxFit.scaleDown, child: Text(_labels[i], maxLines: 1, style: AppType.meta(context))),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A calm, tinted message block (tips, warnings, "locked" notes …): the tone's quiet wash with a hairline of the tone
/// (D-728: the fill alone, at 8 %, read as a heavy green slab), radius `card`, ink text.
class DlBanner extends StatelessWidget {
  const DlBanner({super.key, required this.icon, required this.text, this.color, this.action});

  final IconData icon;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      decoration: BoxDecoration(
        color: c.isDark ? col.withValues(alpha: 0.16) : appWashOn(context, col),
        borderRadius: AppRadius.cardAll,
        border: c.isDark ? null : Border.all(color: col.withValues(alpha: 0.16), width: AppBorder.hairline),
      ),
      child: Row(children: [
        Icon(icon, size: AppIconSize.md, color: appInk(context, col)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(text, style: AppType.body(context).copyWith(color: c.textDark))),
        ?action,
      ]),
    );
  }
}

/// "3 min ago" / "yesterday" / a date — friendly time for the history.
String dlAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return dlTr('dl_ago_now', 'just now');
  if (d.inMinutes < 60) return '${d.inMinutes} ${dlTr('dl_ago_min', 'min ago')}';
  if (d.inHours < 24) return '${d.inHours} ${dlTr('dl_ago_hours', 'h ago')}';
  if (d.inDays == 1) return dlTr('dl_ago_yesterday', 'yesterday');
  if (d.inDays < 7) return '${d.inDays} ${dlTr('dl_ago_days', 'days ago')}';
  return AppTime.date(t.toUtc());   // platform / organization timezone, localized month
}

// ─────────────────────────────────────────────────────────────────────────────
// Column style colours
// ─────────────────────────────────────────────────────────────────────────────

/// A style colour: a theme name (follows the app theme and dark mode) or '#RRGGBB'.
Color? dlStyleColor(BuildContext context, String? token) {
  if (token == null || token.isEmpty) return null;
  final c = context.colors;
  switch (token) {
    case 'primary':
      return c.primary;
    case 'success':
      return c.success;
    case 'warning':
      return c.warning;
    case 'danger':
      return c.danger;
    case 'purple':
      return c.purple;
    case 'accent':
      return c.accent;
    case 'accent2':
      return c.accent2;
  }
  if (token.startsWith('#') && token.length == 7) {
    final v = int.tryParse(token.substring(1), radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return null;
}

/// Red → amber → green for 0 → 50 → 100 (the colour scale of a column).
Color dlScaleColor(BuildContext context, double pct) {
  final c = context.colors;
  final t = (pct / 100).clamp(0.0, 1.0);
  return t < 0.5 ? Color.lerp(c.danger, c.warning, t * 2)! : Color.lerp(c.warning, c.success, (t - 0.5) * 2)!;
}

/// Text alignment of a style value ('start' | 'center' | 'end').
TextAlign dlTextAlign(String? a) => switch (a) {
  'start' => TextAlign.start,
  'end' => TextAlign.end,
  _ => TextAlign.center,
};

AlignmentDirectional dlAlignment(String? a) => switch (a) {
  'start' => AlignmentDirectional.centerStart,
  'end' => AlignmentDirectional.centerEnd,
  _ => AlignmentDirectional.center,
};

/// A row of colour swatches (+ "none"). [value] is the selected token.
class DlSwatches extends StatelessWidget {
  const DlSwatches({super.key, required this.value, required this.onChanged, this.allowNone = true, this.size = 30});

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowNone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget dot(String? token) {
      final col = dlStyleColor(context, token);
      final on = value == token;
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onChanged(token),
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: col ?? c.inputBg,
            border: Border.all(color: on ? c.textDark : c.divider, width: on ? AppBorder.focus : AppBorder.hairline),
          ),
          child: col == null
              ? Icon(Icons.format_color_reset_rounded, size: size * 0.55, color: c.textMedium)
              : (on ? Icon(Icons.check_rounded, size: size * 0.6, color: c.onHero) : null),
        ),
      );
    }

    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      if (allowNone) dot(null),
      for (final t in dlStyleColors) dot(t),
    ]);
  }
}