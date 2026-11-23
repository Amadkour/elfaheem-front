// lib/features/games/learner/level_map.dart — the level map of one subject (Games v4 T72): a winding path of level
// nodes (stars under each, a lock with the unlock rule on a locked one, the current node pulsing). Plain values only
// (no provider, no request): the games home feeds it; the layout harness and the goldens draw it as is.
//
// Age look (AgeThemeScope): kids = fat path, thick outlines, big nodes; teen = medium; adult = thin and quiet. The
// pulse is a decorative loop: syncMotionLoop parks it under Reduce motion.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

/// One node of the map.
class LevelNode {
  const LevelNode({
    required this.id,
    required this.no,
    required this.title,
    this.stars = 0,
    this.locked = false,
    this.sacred = false,
    this.unlockMinStars = 1,
    this.previousNo,
  });

  final int id, no;
  final String title;
  final int stars;
  final bool locked, sacred;

  /// The unlock rule of a locked node: [unlockMinStars] stars in level [previousNo].
  final int unlockMinStars;
  final int? previousNo;

  /// "Earn 1 star in level 2 to open this one."
  String get unlockText {
    final p = previousNo;
    final n = unlockMinStars;
    final stars = n == 1 ? t('نجمة', 'star') : t('نجوم', 'stars');
    return p == null
        ? t('أنهِ المستوى السابق لتفتح هذا', 'Finish the level before this one to open it')
        : t('اكسب $n $stars في المستوى $p لتفتح هذا', 'Earn $n $stars in level $p to open this one');
  }

  String get semantics => [
        t('المستوى $no', 'Level $no'),
        title,
        if (locked) unlockText else if (stars == 0) t('جديد', 'new') else t('$stars من 3 نجوم', '$stars of 3 stars'),
      ].join(', ');
}

/// The first unlocked node that is not yet at 3 stars (the one to play next), or null.
int? currentNodeId(List<LevelNode> nodes, {int? preferred}) {
  if (preferred != null) {
    for (final n in nodes) {
      if (n.id == preferred && !n.locked && n.stars < 3) return n.id;
    }
  }
  for (final n in nodes) {
    if (!n.locked && n.stars == 0) return n.id;
  }
  for (final n in nodes) {
    if (!n.locked && n.stars < 3) return n.id;
  }
  return null;
}

class LevelMap extends StatefulWidget {
  const LevelMap({super.key, required this.nodes, this.currentId, this.onOpen, this.onLocked, this.tint});

  final List<LevelNode> nodes;
  final int? currentId;
  final ValueChanged<LevelNode>? onOpen, onLocked;

  /// The subject's colour (null = the age theme's accent).
  final Color? tint;

  @override
  State<LevelMap> createState() => _LevelMapState();
}

class _LevelMapState extends State<LevelMap> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _pulse, reverse: true, rest: 0);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static const double _labelW = 150;

  @override
  Widget build(BuildContext context) {
    final age = AgeThemeScope.of(context);
    final kids = age.age == GameAge.kids;
    final node = kids ? 84.0 : AppTouch.primary + AppSpace.md;
    final scaler = MediaQuery.textScalerOf(context);
    final labelH = scaler.scale(13) * 1.4 * 2 + AppIconSize.sm + AppSpace.md;
    final rowH = node + labelH + AppSpace.md;
    final c = context.colors;
    final accent = widget.tint ?? age.palette.accent;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 360.0;
      final amp = math.max(0.0, math.min((w - _labelW) / 2, 120.0));
      final n = widget.nodes.length;
      final dir = Directionality.of(context);
      double cx(int i) {
        final dx = amp * math.sin(i * math.pi / 2.1);
        return w / 2 + (dir == TextDirection.rtl ? -dx : dx);
      }

      final centers = [for (var i = 0; i < n; i++) Offset(cx(i), i * rowH + node / 2 + AppSpace.xs)];
      final cur = widget.currentId;
      final reached = cur == null ? n : widget.nodes.indexWhere((e) => e.id == cur);
      final line = kids ? AppSpace.sm : (age.age == GameAge.teen ? AppSpace.xs : AppSpace.xxs);
      return SizedBox(
        height: n * rowH + AppSpace.md,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _PathPainter(
                  centers: centers,
                  reached: reached < 0 ? 0 : reached,
                  track: c.divider,
                  done: accent,
                  width: line,
                  dashed: age.age == GameAge.adult,
                ),
              ),
            ),
          ),
          for (var i = 0; i < n; i++)
            Positioned(
              left: centers[i].dx - _labelW / 2,
              top: centers[i].dy - node / 2,
              width: _labelW,
              child: _NodeView(
                key: ValueKey('games.v4.node.${widget.nodes[i].id}'),
                data: widget.nodes[i],
                size: node,
                current: widget.nodes[i].id == cur,
                pulse: _pulse,
                accent: accent,
                age: age,
                onTap: () => widget.nodes[i].locked ? widget.onLocked?.call(widget.nodes[i]) : widget.onOpen?.call(widget.nodes[i]),
              ),
            ),
        ]),
      );
    });
  }
}

class _NodeView extends StatelessWidget {
  const _NodeView({
    super.key,
    required this.data,
    required this.size,
    required this.current,
    required this.pulse,
    required this.accent,
    required this.age,
    this.onTap,
  });

  final LevelNode data;
  final double size;
  final bool current;
  final Animation<double> pulse;
  final Color accent;
  final AgeTheme age;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = age.palette;
    final locked = data.locked;
    final done = !locked && data.stars > 0;
    final ring = switch (age.age) { GameAge.kids => AppBorder.line, GameAge.teen => AppBorder.strong, GameAge.adult => AppBorder.hairline };
    final fill = locked ? c.divider.withValues(alpha: 0.5) : (done ? accent : Color.alphaBlend(accent.withValues(alpha: 0.14), c.cardBg));
    final ink = locked ? c.textLight : (done ? p.paper : accent);
    final edge = locked ? c.divider : (current ? p.gold : accent);
    Widget disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: edge, width: ring),
        boxShadow: locked || age.age == GameAge.adult ? null : AppShadow.card(context),
      ),
      child: locked
          ? Icon(Icons.lock_rounded, color: ink, size: AppIconSize.lg)
          : Text('${data.no}', style: AppType.figureLarge(context).copyWith(color: ink)),
    );
    if (current) {
      disc = AnimatedBuilder(
        animation: pulse,
        builder: (context, child) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Positioned.fill(
            left: -AppSpace.sm * pulse.value,
            top: -AppSpace.sm * pulse.value,
            right: -AppSpace.sm * pulse.value,
            bottom: -AppSpace.sm * pulse.value,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.gold.withValues(alpha: 0.12 + 0.28 * (1 - pulse.value))),
            ),
          ),
          child!,
        ]),
        child: disc,
      );
    }
    return Semantics(
      button: true,
      label: data.semantics,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + AppSpace.xs,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: size, child: Center(child: disc)),
          const SizedBox(height: AppSpace.xxs),
          DecoratedBox(
            decoration: BoxDecoration(color: c.cardBg.withValues(alpha: 0.94), borderRadius: AppRadius.chipAll),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (locked) const SizedBox(height: AppIconSize.sm) else LearnStars(stars: data.stars, size: AppIconSize.sm),
                Text(data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppType.label(context).copyWith(color: locked ? c.textLight : c.textDark)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter({required this.centers, required this.reached, required this.track, required this.done, required this.width, required this.dashed});

  final List<Offset> centers;
  final int reached;
  final Color track, done;
  final double width;
  final bool dashed;

  Path _seg(Offset a, Offset b) {
    final my = (a.dy + b.dy) / 2;
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx, my, b.dx, my, b.dx, b.dy);
  }

  void _draw(Canvas canvas, Path path, Paint paint) {
    if (!dashed) return canvas.drawPath(path, paint);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), paint);
        d += 14;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = track;
    final hit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = done.withValues(alpha: 0.85);
    for (var i = 0; i + 1 < centers.length; i++) {
      _draw(canvas, _seg(centers[i], centers[i + 1]), i < reached ? hit : base);
    }
  }

  @override
  bool shouldRepaint(_PathPainter o) =>
      o.centers.length != centers.length || o.reached != reached || o.track != track || o.done != done || o.width != width || o.dashed != dashed;
}
