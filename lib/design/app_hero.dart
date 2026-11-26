// lib/design/app_hero.dart
//
// The redesign hero (KIT_SPEC §5.2): a full-bleed band in the area's (or role's) radial gradient with three drifting
// shapes behind it, a gold kicker line, an editorial title (one key word may carry the squiggle), a subtitle, and
// optional stats, actions, a trailing block (wide) and a bottom row. The page body rides up over its lower edge
// through AppHeroOverlap.
//
//   AppHero(title:, subtitle:, kicker:, squiggle:, leading:, stats: [AppHeroStat(...)], actions: [...])
//   AppHeroSurface(child: ...)               only the background (for widgets that lay out their own hero)
//   AppHeroOverlap(hero: AppHero(...), body: Column(...))   the body starts `overlap` px above the hero's bottom
//
// The old Data Lab call `AppHero(title:, subtitle:, icon:, stats: [AppHeroStat(icon:, value:, label:)])` still works.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show KitSet;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_area.dart';
import 'app_motion_kit.dart';
import 'app_responsive.dart' show Breakpoints;
import 'app_tokens.dart';

bool _wideOf(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.mobile;

/// The hero's background: the radial gradient of [set] (default the area scope's) and, with [shapes], the drifting
/// shapes, clipped to [borderRadius].
class AppHeroSurface extends StatelessWidget {
  const AppHeroSurface({
    super.key,
    required this.child,
    this.set,
    this.shapes = true,
    this.scroll,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;
  final KitSet? set;
  final bool shapes;
  final ScrollController? scroll;
  final BorderRadiusGeometry borderRadius;

  /// The hero gradient of [set]: the light at the reading start, top.
  static RadialGradient gradientOf(BuildContext context, KitSet set) {
    final dir = Directionality.maybeOf(context) == TextDirection.rtl ? 1.0 : -1.0;
    return RadialGradient(
      center: Alignment(dir * 0.7, -1.6),
      radius: 1.4,
      colors: set.heroStops,
      stops: const [0, .45, 1],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = set ?? AppAreaScope.of(context);
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(children: [
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: gradientOf(context, s)))),
        if (shapes) Positioned.fill(child: AppDriftShapes(set: s, scroll: scroll, compact: !_wideOf(context))),
        child,
      ]),
    );
  }
}

/// One figure on a hero: a glass tile, the value rolls in (AppOdometer), the label under it.
class AppHeroStat extends StatelessWidget {
  const AppHeroStat({super.key, this.icon, required this.value, required this.label, this.delta, this.onTap});

  final IconData? icon;
  final String value, label;

  /// A signed, already formatted change ("+3"), drawn in the ok tone.
  final String? delta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = _wideOf(context);
    final radius = BorderRadius.circular(AppRadius.tile);
    final tile = Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: radius,
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.sm, color: c.onHeroMuted),
            const SizedBox(width: AppSpace.xxs),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: AppOdometer(value,
                  memoryKey: 'herostat:$label', style: AppType.statFigure(context, wide: wide).copyWith(color: c.onHero)),
            ),
          ),
          if (delta != null && delta!.isNotEmpty) ...[
            const SizedBox(width: AppSpace.xxs),
            Text(delta!,
                maxLines: 1,
                style: AppType.meta(context)
                    .copyWith(color: Color.lerp(c.kit.ok.color, c.onHero, .35), fontWeight: FontWeight.w600)),
          ],
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
      ]),
    );
    if (onTap == null) return Semantics(container: true, child: tile);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: radius, onTap: onTap, child: tile),
    );
  }
}

/// Tells a hero laid out by [AppHeroOverlap] how far the body rides up over it.
class _OverlapInfo extends InheritedWidget {
  const _OverlapInfo({required this.overlap, required super.child});

  final double overlap;

  @override
  bool updateShouldNotify(_OverlapInfo old) => old.overlap != overlap;
}

/// The page's hero band (see the file header).
class AppHero extends StatelessWidget {
  const AppHero({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.stats = const [],
    this.kicker,
    this.squiggle,
    this.leading,
    this.actions = const [],
    this.trailing,
    this.bottom,
    this.set,
    this.statsOnPhone,
    this.overlap = true,
    this.wipe = true,
    this.scroll,
  });

  final String title;
  final String? subtitle;

  /// Drawn only when [leading] is null and the page is wide.
  final IconData? icon;
  final List<AppHeroStat> stats;

  /// The small line above the title ("Good morning, Faisal").
  final String? kicker;

  /// ONE word of [title]; that word gets the squiggle (M7). Not found in the title: ignored.
  final String? squiggle;

  /// An avatar or a book cover before the text.
  final Widget? leading;

  /// At most 2 buttons under the text.
  final List<Widget> actions;

  /// Wide only: a block on the end side (a countdown, an activity card).
  final Widget? trailing;

  /// Under everything, full width, still on the gradient (a search pill, a notice).
  final Widget? bottom;

  /// Default: the area scope's set.
  final KitSet? set;

  /// Default: false under an area scope (student), true otherwise.
  final bool? statsOnPhone;

  /// Adds the bottom room the body rides up over (inside [AppHeroOverlap]).
  final bool overlap;

  /// M6 on first show (student areas only).
  final bool wipe;

  /// For the shapes' parallax.
  final ScrollController? scroll;

  /// The leading box: 56 on phones, 72 from 700 px.
  static double leadingSize(bool wide) => wide ? AppDashSize.avatar : AppDashSize.avatarSm;

  Widget _title(BuildContext context, TextStyle style) {
    final word = squiggle?.trim();
    final at = word == null || word.isEmpty ? -1 : title.indexOf(word);
    final text = at < 0
        ? Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: style)
        : Text.rich(
            TextSpan(children: [
              if (at > 0) TextSpan(text: title.substring(0, at)),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: AppSquiggle(child: Text(word!, style: style)),
              ),
              if (at + word.length < title.length) TextSpan(text: title.substring(at + word.length)),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
    return Semantics(header: true, label: title, child: ExcludeSemantics(child: text));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = set ?? AppAreaScope.of(context);
    final wide = _wideOf(context);
    final playful = AppAreaScope.playful(context);
    final ride = overlap ? context.dependOnInheritedWidgetOfExactType<_OverlapInfo>()?.overlap : null;
    final bottomPad = ride != null ? AppHeroMetrics.padBottom(ride) : (wide ? AppSpace.lg : AppSpace.md);
    final pad = EdgeInsetsDirectional.fromSTEB(
      wide ? AppSpace.lg : AppSpace.md,
      wide ? AppHeroMetrics.padTopWide : AppHeroMetrics.padTopPhone,
      wide ? AppSpace.lg : AppSpace.md,
      bottomPad,
    );

    final titleStyle = (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: c.onHero);
    final sub = subtitle;
    final textCol = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (kicker != null && kicker!.isNotEmpty) ...[
        Text(kicker!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.kicker(context).copyWith(color: c.kit.warmOnDark)),
        const SizedBox(height: AppSpace.xxs),
      ],
      _title(context, titleStyle),
      if (sub != null && sub.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(sub,
            maxLines: !wide && playful ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.body(context).copyWith(color: c.onHeroMuted)),
      ],
    ]);

    final lead = leading;
    final glyph = lead == null && wide && icon != null
        ? ExcludeSemantics(
            child: Container(
              width: AppDashSize.avatarSm,
              height: AppDashSize.avatarSm,
              decoration: BoxDecoration(
                color: c.heroGlass,
                borderRadius: BorderRadius.circular(AppRadius.tile),
                border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
              ),
              child: Icon(icon, color: c.onHero, size: AppIconSize.lg),
            ),
          )
        : null;

    Widget head = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (lead != null) ...[
        SizedBox.square(dimension: leadingSize(wide), child: lead),
        SizedBox(width: wide ? AppSpace.md : AppSpace.sm),
      ],
      Expanded(child: textCol),
      if (glyph != null) ...[const SizedBox(width: AppSpace.md), glyph],
    ]);

    final showStats = stats.isNotEmpty && (wide || (statsOnPhone ?? !playful));
    final children = <Widget>[head];
    if (showStats) {
      children
        ..add(const SizedBox(height: AppSpace.md))
        ..add(_Stats(stats: stats.take(4).toList(), wide: wide));
    }
    if (actions.isNotEmpty) {
      final a = actions.take(2).toList();
      children.add(const SizedBox(height: AppSpace.md));
      children.add(wide
          ? Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: a)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < a.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.xs), a[i]],
            ]));
    }

    Widget body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
    if (wide && trailing != null) {
      final main = body;
      body = LayoutBuilder(
        builder: (context, box) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: main),
          const SizedBox(width: AppSpace.lg),
          ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * .4), child: trailing),
        ]),
      );
    }
    if (bottom != null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        body,
        const SizedBox(height: AppSpace.md),
        bottom!,
      ]);
    }

    Widget hero = AppHeroSurface(
      set: s,
      scroll: scroll,
      child: Padding(padding: pad, child: DefaultTextStyle.merge(style: TextStyle(color: c.onHero), child: body)),
    );
    if (wipe) hero = AppWipe(group: 'hero', child: hero);
    return hero;
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats, required this.wide});

  final List<AppHeroStat> stats;
  final bool wide;

  static const double _oneRowMin = 360;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final oneRow = wide || (stats.length == 4 && box.maxWidth >= _oneRowMin) || stats.length == 1;
        if (oneRow) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.xs),
              Expanded(child: stats[i]),
            ],
          ]);
        }
        final rows = (stats.length / 2).ceil();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: AppSpace.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: stats[r * 2]),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: r * 2 + 1 < stats.length ? stats[r * 2 + 1] : const SizedBox.shrink()),
            ]),
          ],
        ]);
      });
}

/// Lays [hero] out, then [body] starting [overlap] px above the hero's bottom edge. Both stay inside its bounds, so
/// a tap on the overlapped part of the first card reaches it. A two-child RenderBox, not a Transform.
class AppHeroOverlap extends StatelessWidget {
  const AppHeroOverlap({super.key, required this.hero, required this.body, this.overlap});

  final Widget hero;
  final Widget body;

  /// Default: [AppHeroMetrics.overlapWide] from 700 px; below it [AppHeroMetrics.overlapStudentPhone] under an area
  /// scope, else [AppHeroMetrics.overlapPhone].
  final double? overlap;

  static double defaultOverlap(BuildContext context) {
    if (_wideOf(context)) return AppHeroMetrics.overlapWide;
    return AppAreaScope.playful(context) ? AppHeroMetrics.overlapStudentPhone : AppHeroMetrics.overlapPhone;
  }

  @override
  Widget build(BuildContext context) {
    final o = overlap ?? defaultOverlap(context);
    return _OverlapLayout(overlap: o, children: [_OverlapInfo(overlap: o, child: hero), body]);
  }
}

class _OverlapLayout extends MultiChildRenderObjectWidget {
  const _OverlapLayout({required this.overlap, required super.children});

  final double overlap;

  @override
  RenderAppHeroOverlap createRenderObject(BuildContext context) => RenderAppHeroOverlap(overlap: overlap);

  @override
  void updateRenderObject(BuildContext context, RenderAppHeroOverlap renderObject) => renderObject.overlap = overlap;
}

class _OverlapParentData extends ContainerBoxParentData<RenderBox> {}

/// The render box of [AppHeroOverlap]: child 0 is the hero, child 1 the body.
class RenderAppHeroOverlap extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OverlapParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _OverlapParentData> {
  RenderAppHeroOverlap({required double overlap}) : _overlap = overlap;

  double _overlap;
  double get overlap => _overlap;
  set overlap(double v) {
    if (v == _overlap) return;
    _overlap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OverlapParentData) child.parentData = _OverlapParentData();
  }

  RenderBox? get _hero => firstChild;
  RenderBox? get _body => _hero == null ? null : childAfter(_hero!);

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : constraints.minWidth;
    final childC = BoxConstraints(minWidth: w, maxWidth: w);
    final hero = _hero, body = _body;
    final hs = hero == null ? Size.zero : (dry ? hero.getDryLayout(childC) : (hero..layout(childC, parentUsesSize: true)).size);
    final top = math.max(0.0, hs.height - _overlap);
    final bs = body == null ? Size.zero : (dry ? body.getDryLayout(childC) : (body..layout(childC, parentUsesSize: true)).size);
    if (!dry) {
      if (hero != null) (hero.parentData! as _OverlapParentData).offset = Offset.zero;
      if (body != null) (body.parentData! as _OverlapParentData).offset = Offset(0, top);
    }
    return constraints.constrain(Size(w, math.max(hs.height, top + bs.height)));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _layout(constraints, dry: true);

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_hero?.getMinIntrinsicWidth(height) ?? 0, _body?.getMinIntrinsicWidth(height) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(_hero?.getMaxIntrinsicWidth(height) ?? 0, _body?.getMaxIntrinsicWidth(height) ?? 0);

  double _h(double width, double Function(RenderBox, double) f) {
    final hh = _hero == null ? 0.0 : f(_hero!, width);
    final bh = _body == null ? 0.0 : f(_body!, width);
    return math.max(hh, math.max(0.0, hh - _overlap) + bh);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _h(width, (c, w) => c.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) => _h(width, (c, w) => c.getMaxIntrinsicHeight(w));

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  // the body (painted last, on top) is hit first
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
