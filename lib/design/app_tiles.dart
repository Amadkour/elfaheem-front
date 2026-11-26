// lib/design/app_tiles.dart
//
// Tiles of the redesign kit (KIT_SPEC §5.6, the reference's `.k-tile`, `.k-ico`, `.k-rules`):
//
//   AppIconBox(icon: Icons.calculate_rounded, tone: kit.accent(AppAccent.sun))   a 42 px glyph box, radius 13
//   AppTile(icon: …, title: 'Math', subtitle: 'Exponential functions', trailing: AppProgressRing(value: .38))
//                       a row on the well with the kit line; selected / locked / dense; hover shifts toward the start
//   AppRules(items: [(icon: Icons.timer_outlined, text: '40 minutes'), …])      at most 3 short rule rows
//
// Colours come from the nearest AppAreaScope (a student area or a role accent) unless a tone is passed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_area.dart';
import 'app_motion_kit.dart';
import 'app_progress.dart';
import 'app_tokens.dart';

/// A glyph box: [tone]'s tint with its ink, or (solid) the colour with the on-hero ink.
class AppIconBox extends StatelessWidget {
  const AppIconBox({super.key, required this.icon, this.tone, this.size = AppDashSize.glyph, this.solid = false});

  final IconData icon;

  /// Default: the area set's tone.
  final KitTone? tone;
  final double size;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? AppAreaScope.of(context).tone;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solid ? t.color : t.tint,
        borderRadius: BorderRadius.circular(AppRadius.glyph),
      ),
      child: Icon(icon, size: AppIconSize.md, color: solid ? context.colors.onHero : t.ink),
    );
  }
}

/// A row tile on the well.
class AppTile extends StatefulWidget {
  const AppTile({
    super.key,
    this.icon,
    this.leading,
    this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.locked = false,
    this.dense = false,
  });

  final IconData? icon;

  /// Replaces the icon box (an avatar, a cover).
  final Widget? leading;

  /// Default: the area set's tone.
  final KitTone? tone;
  final String title;
  final String? subtitle;

  /// Hugs the end: a ring, a tag, a small button, a chevron.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool locked;
  final bool dense;

  static const double minHeight = 64;
  static const double minDense = 52;

  /// Below this width a wide trailing wraps under the text.
  static const double narrow = 320;

  /// The widest trailing that never wraps (KIT_SPEC §5.6).
  static const double wideTrailing = 96;

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final w = widget;
    final tone = w.tone ?? AppAreaScope.of(context).tone;
    final radius = BorderRadius.circular(AppRadius.tile);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final motion = AppMotion.of(context);
    final tappable = w.onTap != null && !w.locked;

    final Widget? lead = w.locked
        ? AppIconBox(icon: Icons.lock_outline_rounded, tone: KitTone(kit.lock, kit.track, kit.lockInk))
        : w.leading ?? (w.icon == null ? null : AppIconBox(icon: w.icon!, tone: tone));

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(w.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.tileTitle(context).copyWith(color: w.locked ? kit.lockInk : null)),
        if (w.subtitle != null && w.subtitle!.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs / 2),
          Text(w.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ],
      ],
    );

    final body = LayoutBuilder(builder: (context, box) {
      // a wide trailing (not a single icon) goes under the text on a very narrow row
      final wrap = w.trailing != null && !_compact(w.trailing!) && box.maxWidth < AppTile.narrow;
      final row = Row(children: [
        if (lead != null) ...[lead, AppSpace.gapSm],
        Expanded(child: text),
        if (w.trailing != null && !wrap) ...[AppSpace.gapSm, w.trailing!],
      ]);
      if (!wrap) return row;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        row,
        AppSpace.gapXs,
        Align(alignment: AlignmentDirectional.centerEnd, child: w.trailing),
      ]);
    });

    final Decoration deco;
    if (w.locked) {
      deco = BoxDecoration(color: c.cardBg, borderRadius: radius);
    } else if (w.selected) {
      deco = BoxDecoration(
        gradient: LinearGradient(colors: [c.cardBg, tone.tint]),
        borderRadius: radius,
        border: Border.all(color: tone.color, width: AppBorder.focus),
      );
    } else {
      deco = BoxDecoration(
        color: kit.well,
        borderRadius: radius,
        border: Border.all(color: kit.line, width: AppBorder.strong),
        boxShadow: _hover && tappable ? AppElevation.of(context, 2) : null,
      );
    }

    Widget tile = AnimatedContainer(
      duration: motion.fast,
      curve: AppMotion.curve,
      transform: Matrix4.translationValues(_hover && tappable ? (rtl ? AppSpace.xxs : -AppSpace.xxs) : 0, 0, 0),
      constraints: BoxConstraints(minHeight: w.dense ? AppTile.minDense : AppTile.minHeight),
      decoration: deco,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tappable ? w.onTap : null,
          onHover: tappable ? (v) => setState(() => _hover = v) : null,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: w.dense ? AppSpace.xs : AppSpace.sm),
            child: body,
          ),
        ),
      ),
    );
    if (w.locked) tile = CustomPaint(foregroundPainter: _DashedEdge(kit.lock, AppRadius.tile), child: tile);
    if (tappable) {
      tile = AppAreaScope.playful(context)
          ? AppJelly(wide: true, child: tile)
          : AppPressScale(enabled: true, child: tile);
    }
    return Semantics(
      container: true,
      button: tappable,
      selected: w.selected,
      enabled: !w.locked,
      child: tile,
    );
  }
}

/// The dashed edge of a locked tile.
class _DashedEdge extends CustomPainter {
  _DashedEdge(this.color, this.radius);

  final Color color;
  final double radius;

  static const double _dash = 6, _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(AppBorder.strong / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.strong;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += _dash + _gap) {
        canvas.drawPath(m.extractPath(d, d + _dash), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) => old.color != color || old.radius != radius;
}

/// At most three short rule rows (an icon and a few words). A fourth item is not drawn.
class AppRules extends StatelessWidget {
  const AppRules({super.key, required this.items});

  final List<({IconData icon, String text})> items;

  static const int max = 3;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final tone = AppAreaScope.of(context).tone;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in items.take(max).indexed) ...[
        if (i > 0) AppSpace.gapXs,
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: kit.well,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: kit.line, width: AppBorder.strong),
          ),
          child: Row(children: [
            AppIconBox(icon: r.icon, tone: tone, size: AppTouch.min - AppSpace.sm),
            AppSpace.gapSm,
            Expanded(child: Text(r.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
          ]),
        ),
      ],
    ]);
  }
}

/// A trailing no wider than [AppTile.wideTrailing] (an icon, a ring, an icon box, a sized box): it stays on the row.
bool _compact(Widget t) => switch (t) {
      Icon() || AppIconBox() => true,
      AppProgressRing(:final size) => size <= AppTile.wideTrailing,
      SizedBox(:final width) => width != null && width <= AppTile.wideTrailing,
      _ => false,
    };
