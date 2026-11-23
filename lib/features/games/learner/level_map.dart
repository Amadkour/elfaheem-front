// lib/features/games/learner/level_map.dart — the level map of one subject (Games v4 T72, polished at G3): a winding
// path of chunky 3D level buttons over a painted landscape that scrolls with it. Plain values only (no provider, no
// request): the games home feeds it; the layout harness and the goldens draw it as is.
//
//   nodes      zig-zag left / right (mirrored in RTL), joined by a trail that is filled up to the current node
//   done       the subject's colour (gold at 3 stars), stars under it; current: larger, a soft ring, a "Start"
//              bubble above it and the learner's character (GameCharacter + equipped cosmetics) beside it;
//              locked: muted with a lock, a tap explains the unlock rule
//   landscape  one CustomPainter (_ScenePainter): meadow, hills, clouds, trees and props every node (kids), a night
//              sky with pines (teen), faint hills only (adult). Its paths are built once, in the painter's
//              constructor, and the state keeps the painter until the size or the data change.
//
// Age look (AgeThemeScope): kids vivid with thick outlines and a deep press; teen the night palette, thinner; adult
// quiet (thin dotted trail, shallow buttons, no character). The ring and the bubble bob are ONE decorative loop
// (syncMotionLoop, parked under Reduce motion); the character keeps its own. On open the list scrolls so the
// current node is in view (only when it is not already). The column is centred at AppWidth.form on a wide window,
// the landscape fills the whole width.
library;

import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';

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
    this.icon,
  });

  final int id, no;
  final String title;

  /// The template's icon, drawn beside the title.
  final IconData? icon;
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
  const LevelMap({
    super.key,
    required this.nodes,
    this.currentId,
    this.onOpen,
    this.onLocked,
    this.tint,
    this.equipped = const {},
  });

  final List<LevelNode> nodes;
  final int? currentId;
  final ValueChanged<LevelNode>? onOpen, onLocked;

  /// The subject's colour (null = the age theme's accent).
  final Color? tint;

  /// The learner's equipped cosmetics (`{hat, outfit, vehicle, trail: key}`), worn by the character on the current
  /// node.
  final Map<String, String?> equipped;

  @override
  State<LevelMap> createState() => _LevelMapState();
}

/// The sizes of one age's map.
class _Look {
  const _Look({required this.node, required this.current, required this.depth, required this.character, required this.gap});

  final double node, current, depth, character, gap;

  static _Look of(GameAge age) => switch (age) {
        GameAge.kids => const _Look(node: 72, current: 88, depth: 7, character: 84, gap: AppSpace.lg),
        GameAge.teen => const _Look(node: 64, current: 76, depth: 5, character: 64, gap: AppSpace.md),
        GameAge.adult => const _Look(node: AppTouch.primary + AppSpace.xxs, current: 68, depth: 3, character: 0, gap: AppSpace.md),
      };
}

class _LevelMapState extends State<LevelMap> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final Animation<double> _ringScale = Tween<double>(begin: 1, end: 1.38).chain(CurveTween(curve: Curves.easeOut)).animate(_loop);
  late final Animation<double> _ringFade = Tween<double>(begin: 0.7, end: 0).chain(CurveTween(curve: Curves.easeIn)).animate(_loop);
  late final Animation<Offset> _bob =
      _loop.drive(CurveTween(curve: const _Wave())).drive(Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.12)));
  final GlobalKey _currentKey = GlobalKey();
  _ScenePainter? _scene;

  static const double _labelW = 150;
  static const double _tail = AppSpace.xs;

  /// The zig-zag of the path, as a share of the amplitude (centre, out, far, out, centre, the other way, …).
  static const List<double> _wave = [0, 0.55, 1, 0.55, 0, -0.55, -1, -0.55];

  @override
  void initState() {
    super.initState();
    _revealCurrent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _loop, rest: 0);
  }

  @override
  void didUpdateWidget(LevelMap old) {
    super.didUpdateWidget(old);
    if (old.currentId != widget.currentId) _revealCurrent();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  /// After the frame: when the current node is not fully on screen, scroll the list so it sits mid-screen.
  void _revealCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _currentKey.currentContext;
      final ro = ctx?.findRenderObject();
      final scroll = ctx == null ? null : Scrollable.maybeOf(ctx);
      if (ro == null || !ro.attached || scroll == null) return;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) return;
      final pos = scroll.position;
      if (!pos.hasPixels || !pos.hasContentDimensions) return;
      final atTop = viewport.getOffsetToReveal(ro, 0).offset;
      final atEnd = viewport.getOffsetToReveal(ro, 1).offset;
      if (pos.pixels >= atEnd && pos.pixels <= atTop) return;
      final mid = viewport.getOffsetToReveal(ro, 0.5).offset;
      pos.jumpTo(mid.clamp(pos.minScrollExtent, pos.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final age = AgeThemeScope.of(context);
    final p = age.palette;
    final look = _Look.of(age.age);
    final scaler = MediaQuery.textScalerOf(context);
    const starRow = AppIconSize.sm;
    final labelH = scaler.scale(13) * 1.4 * 2 + AppSpace.xxs * 2;
    final bubbleText = AppType.row(context).fontSize ?? 15;
    final bubbleH = scaler.scale(bubbleText) * 1.4 + AppSpace.xs * 2 + _tail;
    final accent = widget.tint ?? p.accent;
    final dir = Directionality.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 360.0;
      final column = math.min(w, AppWidth.form.max);
      final amp = math.max(0.0, math.min((column - _labelW) / 2, 120.0));
      final n = widget.nodes.length;
      final cur = widget.currentId;
      final curIndex = cur == null ? -1 : widget.nodes.indexWhere((e) => e.id == cur);

      // the column: one row per node, the current one taller (its bubble sits above it)
      final tops = <double>[];
      final sizes = <double>[];
      final centers = <Offset>[];
      var y = AppSpace.lg;
      for (var i = 0; i < n; i++) {
        final isCur = i == curIndex;
        if (isCur) y += bubbleH + AppSpace.xxs;
        final s = isCur ? look.current : look.node;
        final dx = amp * _wave[i % _wave.length];
        final cx = w / 2 + (dir == TextDirection.rtl ? -dx : dx);
        tops.add(y);
        sizes.add(s);
        centers.add(Offset(cx, y + s / 2));
        y += s + look.depth + AppSpace.xxs + starRow + labelH + look.gap;
      }
      final height = y + AppSpace.sm;
      final reached = curIndex >= 0 ? curIndex : (n == 0 || widget.nodes.last.locked ? 0 : n - 1);

      final key = _SceneKey(Size(w, height), age, accent, reached, centers, sizes, look.depth);
      if (_scene?.key != key) _scene = _ScenePainter(key);

      Widget? character;
      if (curIndex >= 0 && look.character > 0) {
        final cx = centers[curIndex].dx;
        final side = cx > w / 2 + 1 ? -1.0 : 1.0;
        final ch = look.character;
        final s = sizes[curIndex];
        final left = (cx + side * (s / 2 + AppSpace.xs + ch / 2) - ch / 2).clamp(0.0, math.max(0.0, w - ch)).toDouble();
        character = Positioned(
          left: left,
          top: tops[curIndex] + s + look.depth - ch,
          width: ch,
          height: ch,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: GameCharacter(key: const ValueKey('games.v4.map.character'), theme: age, equipped: widget.equipped, size: ch),
            ),
          ),
        );
      }

      return SizedBox(
        height: height,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: ExcludeSemantics(child: RepaintBoundary(child: CustomPaint(painter: _scene)))),
          for (var i = 0; i < n; i++)
            Positioned(
              left: centers[i].dx - _labelW / 2,
              top: tops[i],
              width: _labelW,
              child: _NodeView(
                key: ValueKey('games.v4.node.${widget.nodes[i].id}'),
                anchor: i == curIndex ? _currentKey : null,
                data: widget.nodes[i],
                size: sizes[i],
                depth: look.depth,
                current: i == curIndex,
                ringScale: _ringScale,
                ringFade: _ringFade,
                accent: accent,
                age: age,
                onTap: () => widget.nodes[i].locked ? widget.onLocked?.call(widget.nodes[i]) : widget.onOpen?.call(widget.nodes[i]),
              ),
            ),
          if (curIndex >= 0)
            Positioned(
              left: centers[curIndex].dx - _labelW / 2,
              width: _labelW,
              top: tops[curIndex] - bubbleH - AppSpace.xxs,
              height: bubbleH,
              child: IgnorePointer(
                child: SlideTransition(
                  position: _bob,
                  child: Align(alignment: Alignment.bottomCenter, child: _StartBubble(age: age, accent: accent, tail: _tail)),
                ),
              ),
            ),
          ?character,
        ]),
      );
    });
  }
}

/// 0 → 1 → 0 over one loop: a smooth bob that rests at 0.
class _Wave extends Curve {
  const _Wave();

  @override
  double transformInternal(double t) => (1 - math.cos(2 * math.pi * t)) / 2;
}

/// "Start", a speech bubble above the current node.
class _StartBubble extends StatelessWidget {
  const _StartBubble({required this.age, required this.accent, required this.tail});

  final AgeTheme age;
  final Color accent;
  final double tail;

  @override
  Widget build(BuildContext context) {
    final p = age.palette;
    final adult = age.age == GameAge.adult;
    final fill = adult ? accent : p.paper;
    final ink = adult ? p.paper : accent;
    final edge = age.age == GameAge.kids ? Color.lerp(accent, p.ink, 0.15) : null;
    return CustomPaint(
      painter: _BubblePainter(fill: fill, edge: edge, tail: tail),
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs + tail),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(t('ابدأ', 'Start'), maxLines: 1, style: AppType.row(context).copyWith(color: ink, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.fill, required this.edge, required this.tail});

  final Color fill;
  final Color? edge;
  final double tail;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height - tail), const Radius.circular(AppRadius.control));
    final cx = size.width / 2;
    final path = Path.combine(
      PathOperation.union,
      Path()..addRRect(body),
      Path()
        ..moveTo(cx - tail, size.height - tail - 1)
        ..lineTo(cx, size.height)
        ..lineTo(cx + tail, size.height - tail - 1)
        ..close(),
    );
    final e = edge;
    if (e != null) canvas.drawPath(path.shift(const Offset(0, 3)), Paint()..color = e);
    canvas.drawPath(path, Paint()..color = fill);
    if (e != null) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = AppBorder.focus
            ..color = e);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter o) => o.fill != fill || o.edge != edge || o.tail != tail;
}

class _NodeView extends StatefulWidget {
  const _NodeView({
    super.key,
    this.anchor,
    required this.data,
    required this.size,
    required this.depth,
    required this.current,
    required this.ringScale,
    required this.ringFade,
    required this.accent,
    required this.age,
    this.onTap,
  });

  final Key? anchor;
  final LevelNode data;
  final double size, depth;
  final bool current;
  final Animation<double> ringScale, ringFade;
  final Color accent;
  final AgeTheme age;
  final VoidCallback? onTap;

  @override
  State<_NodeView> createState() => _NodeViewState();
}

class _NodeViewState extends State<_NodeView> {
  bool _down = false;

  void _press(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget;
    final age = d.age;
    final p = age.palette;
    final kids = age.age == GameAge.kids;
    final teen = age.age == GameAge.teen;
    final adult = age.age == GameAge.adult;
    final locked = d.data.locked;
    final perfect = !locked && d.data.stars >= 3;
    final Color fill;
    final Color glyph;
    if (locked) {
      fill = teen ? Color.lerp(p.mid, p.paper, 0.18)! : Color.alphaBlend(p.ink.withValues(alpha: 0.12), p.paper);
      glyph = teen ? p.paper.withValues(alpha: 0.6) : p.ink.withValues(alpha: 0.45);
    } else if (perfect) {
      fill = p.gold;
      glyph = p.ink;
    } else {
      fill = d.accent;
      glyph = p.paper;
    }
    final shade = Color.lerp(fill, p.ink, locked ? 0.22 : 0.32)!;
    final outline = switch (age.age) { GameAge.kids => AppBorder.line, GameAge.teen => AppBorder.strong, GameAge.adult => 0.0 };
    final lift = _down ? d.depth : 0.0;
    final Widget face = locked
        ? Icon(Icons.lock_rounded, color: glyph, size: kids ? AppIconSize.xl : AppIconSize.lg)
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${d.data.no}', maxLines: 1, style: AppType.figureLarge(context).copyWith(color: glyph, fontWeight: FontWeight.w800)),
          );
    Widget button = SizedBox(
      width: d.size,
      height: d.size + d.depth,
      child: CustomPaint(
        painter: _ButtonPainter(
          fill: fill,
          shade: shade,
          shine: p.paper.withValues(alpha: adult ? 0.14 : 0.3),
          edge: Color.lerp(shade, p.ink, 0.25)!,
          outline: outline,
          depth: d.depth,
          pressed: _down,
        ),
        child: Padding(
          padding: EdgeInsets.only(top: lift, bottom: d.depth - lift),
          child: Center(child: Padding(padding: const EdgeInsets.all(AppSpace.xs), child: face)),
        ),
      ),
    );
    if (d.current) {
      button = Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Positioned(
          top: 0,
          width: d.size,
          height: d.size,
          child: FadeTransition(
            opacity: d.ringFade,
            child: ScaleTransition(
              scale: d.ringScale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: perfect ? d.accent : p.gold, width: kids ? AppSpace.xs : AppSpace.xxs),
                ),
              ),
            ),
          ),
        ),
        button,
      ]);
    }
    final starOn = teen ? p.gold : Color.lerp(p.gold, p.accent2, 0.3)!;
    final starIdle = teen ? p.paper.withValues(alpha: 0.35) : p.ink.withValues(alpha: 0.22);
    final chip = teen ? p.ink.withValues(alpha: 0.55) : p.paper.withValues(alpha: adult ? 0.86 : 0.92);
    final text = teen ? p.paper : p.ink;
    return Semantics(
      button: true,
      label: d.data.semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: d.onTap,
        child: Column(key: d.anchor, mainAxisSize: MainAxisSize.min, children: [
          button,
          const SizedBox(height: AppSpace.xxs),
          DecoratedBox(
            decoration: BoxDecoration(color: chip, borderRadius: AppRadius.chipAll),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (!locked)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < 3; i++)
                      Icon(i < d.data.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: AppIconSize.sm, color: i < d.data.stars ? starOn : starIdle),
                  ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (d.data.icon != null) ...[
                    Icon(d.data.icon, size: AppIconSize.sm, color: locked ? text.withValues(alpha: 0.62) : text),
                    const SizedBox(width: AppSpace.xxs),
                  ],
                  Flexible(
                    child: Text(d.data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppType.label(context).copyWith(color: locked ? text.withValues(alpha: 0.62) : text)),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A chunky round button: a darker base [depth] below, the face on top (pushed down when [pressed]), a shine on the
/// upper face and, for kids / teen, an outline.
class _ButtonPainter extends CustomPainter {
  _ButtonPainter({
    required this.fill,
    required this.shade,
    required this.shine,
    required this.edge,
    required this.outline,
    required this.depth,
    required this.pressed,
  });

  final Color fill, shade, shine, edge;
  final double outline, depth;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final inset = outline / 2;
    final rr = r - inset;
    final lift = pressed ? depth : 0.0;
    final base = Offset(r, r + depth);
    final top = Offset(r, r + lift);
    final paint = Paint()..color = shade;
    canvas.drawCircle(base, rr, paint);
    canvas.drawRect(Rect.fromLTRB(inset, top.dy, size.width - inset, base.dy), paint);
    paint.color = fill;
    canvas.drawCircle(top, rr, paint);
    paint.color = shine;
    canvas.drawOval(Rect.fromLTWH(top.dx - rr * 0.46, top.dy - rr * 0.8, rr * 0.92, rr * 0.36), paint);
    if (outline > 0) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline
        ..color = edge;
      if (lift < depth) {
        canvas.drawArc(Rect.fromCircle(center: base, radius: rr), 0, math.pi, false, paint);
        canvas.drawLine(Offset(inset, top.dy), Offset(inset, base.dy), paint);
        canvas.drawLine(Offset(size.width - inset, top.dy), Offset(size.width - inset, base.dy), paint);
      }
      canvas.drawCircle(top, rr, paint);
    }
  }

  @override
  bool shouldRepaint(_ButtonPainter o) =>
      o.fill != fill || o.shade != shade || o.shine != shine || o.edge != edge || o.outline != outline || o.depth != depth || o.pressed != pressed;
}

/// What the scene is drawn from; the state rebuilds the painter only when this changes.
class _SceneKey {
  _SceneKey(this.size, this.age, this.accent, this.reached, this.centers, this.sizes, this.depth);

  final Size size;
  final AgeTheme age;
  final Color accent;
  final int reached;
  final List<Offset> centers;
  final List<double> sizes;
  final double depth;

  @override
  bool operator ==(Object o) =>
      o is _SceneKey &&
      o.size == size &&
      o.age.age == age.age &&
      o.age.night == age.night &&
      o.age.palette.accent == age.palette.accent &&
      o.accent == accent &&
      o.reached == reached &&
      o.depth == depth &&
      _same(o.centers, centers) &&
      _same(o.sizes, sizes);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(size, age.age, age.night, accent, reached, depth, centers.length);
}

/// The landscape and the trail. Everything is built in the constructor; paint() only draws.
class _ScenePainter extends CustomPainter {
  _ScenePainter(this.key) {
    _build();
  }

  final _SceneKey key;
  Paint? _ground;
  final List<(Path, Paint)> _back = [];
  final List<(List<Offset>, Paint)> _sky = [];
  final List<(Path, Paint)> _trail = [];
  final List<(List<Offset>, Paint)> _dots = [];

  GamePalette get _p => key.age.palette;

  static Paint _fill(Color c) => Paint()..color = c;

  static Paint _stroke(Color c, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width
    ..color = c;

  void _build() {
    final size = key.size;
    final w = size.width;
    final h = size.height;
    final age = key.age;
    final p = _p;
    final kids = age.age == GameAge.kids;
    final teen = age.age == GameAge.teen;
    final adult = age.age == GameAge.adult;
    final rect = Offset.zero & size;

    // the ground: a meadow (kids), a night (teen), nothing (adult: the card's own tint)
    if (kids) {
      _ground = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(p.far, p.paper, 0.6)!.withValues(alpha: 0), Color.lerp(p.far, p.paper, 0.6)!, Color.lerp(p.mid, p.paper, 0.55)!],
          stops: [0, math.min(0.25, 120 / h), 1],
        ).createShader(rect);
    } else if (teen) {
      _ground = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.skyTop.withValues(alpha: 0), p.skyTop, Color.lerp(p.skyTop, p.near, 0.7)!],
          stops: [0, math.min(0.25, 120 / h), 1],
        ).createShader(rect);
      final stars = <Offset>[];
      for (var i = 0; i < (h / 22).round(); i++) {
        stars.add(Offset(((i * 397 + 131) % 1000) / 1000 * w, 40 + ((i * 211 + 17) % 1000) / 1000 * (h - 40)));
      }
      _sky.add((stars, _stroke(p.paper.withValues(alpha: 0.45), 2)));
    }

    // hills: big soft ovals from alternate edges, two layers
    for (var b = 0, y0 = 170.0; y0 < h + 120; b++, y0 += 300) {
      final left = b.isEven;
      final far = adult ? p.far.withValues(alpha: 0.16) : (teen ? Color.lerp(p.far, p.skyTop, 0.35)! : Color.lerp(p.far, p.paper, 0.3)!);
      final near = adult ? p.mid.withValues(alpha: 0.1) : (teen ? Color.lerp(p.mid, p.skyTop, 0.2)! : Color.lerp(p.mid, p.paper, 0.38)!);
      _back.add((Path()..addOval(Rect.fromCenter(center: Offset(left ? 0 : w, y0), width: math.min(w * 1.15, 640), height: 230)), _fill(far)));
      _back.add((Path()..addOval(Rect.fromCenter(center: Offset(left ? w * 0.06 : w * 0.94, y0 + 110), width: math.min(w * 0.8, 460), height: 170)), _fill(near)));
    }

    if (kids) {
      final cloud = _fill(p.cloud);
      final edge = _stroke(p.skyTop.withValues(alpha: 0.3), AppBorder.strong);
      for (final (cx, cy, s) in [(w * 0.14, 34.0, 1.0), (w * 0.86, 70.0, 0.75)]) {
        final c = _cloud(Offset(cx, cy), s * 22);
        _back.add((c, cloud));
        _back.add((c, edge));
      }
    }

    // props beside the path, on the side away from it
    final centers = key.centers;
    if (!adult) {
      for (var i = 0; i < centers.length; i++) {
        final a = centers[i];
        final b = i + 1 < centers.length ? centers[i + 1] : Offset(w / 2, h);
        final pathX = (a.dx + b.dx) / 2;
        final y = (a.dy + b.dy) / 2 + 30;
        final onLeft = pathX > w / 2;
        final room = (onLeft ? pathX : w - pathX) - 110;
        final x = onLeft ? math.max(26.0, room * 0.45) : w - math.max(26.0, room * 0.45);
        final at = Offset(x, y);
        if (teen) {
          _pines(at, i);
        } else {
          switch (i % 3) {
            case 0:
              _tree(at);
            case 1:
              _bush(at, i);
            default:
              _rock(at);
          }
        }
        // the wide window: a second prop on the far side of the landscape
        if (w > 700) {
          final at2 = Offset(onLeft ? w - 70 - (i % 3) * 40 : 70 + (i % 3) * 40, y - 80);
          if (teen) {
            _pines(at2, i + 1);
          } else if (i.isEven) {
            _tree(at2);
          } else {
            _bush(at2, i);
          }
        }
      }
      // ground shadows under the buttons
      final shadow = _fill(p.ink.withValues(alpha: teen ? 0.3 : 0.12));
      for (var i = 0; i < centers.length; i++) {
        final c = centers[i];
        final r = key.sizes[i] / 2;
        _back.add((Path()..addOval(Rect.fromCenter(center: Offset(c.dx, c.dy + r + key.depth), width: r * 2.3, height: r * 0.5)), shadow));
      }
    }

    // the trail, filled up to the current node
    if (centers.length < 2) return;
    final done = Path();
    final todo = Path();
    for (var i = 0; i + 1 < centers.length; i++) {
      final a = centers[i];
      final b = centers[i + 1];
      final my = (a.dy + b.dy) / 2;
      final seg = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, my, b.dx, my, b.dx, b.dy);
      (i < key.reached ? done : todo).addPath(seg, Offset.zero);
    }
    if (kids) {
      final whole = Path()
        ..addPath(done, Offset.zero)
        ..addPath(todo, Offset.zero);
      _trail.add((whole, _stroke(Color.lerp(p.mid, p.ink, 0.35)!.withValues(alpha: 0.4), 30)));
      _trail.add((todo, _stroke(Color.lerp(p.paper, p.accent2, 0.25)!, 24)));
      _trail.add((done, _stroke(p.gold, 24)));
      _dots.add((_along(done, 22), _stroke(p.paper, 7)));
      _dots.add((_along(todo, 22), _stroke(Color.lerp(p.accent2, p.ink, 0.2)!.withValues(alpha: 0.45), 6)));
    } else if (teen) {
      _trail.add((todo, _stroke(p.paper.withValues(alpha: 0.12), 12)));
      _trail.add((done, _stroke(key.accent.withValues(alpha: 0.75), 12)));
      _dots.add((_along(done, 18), _stroke(p.paper.withValues(alpha: 0.9), 4)));
      _dots.add((_along(todo, 18), _stroke(p.paper.withValues(alpha: 0.35), 3)));
    } else {
      _dots.add((_along(todo, 10), _stroke(p.ink.withValues(alpha: 0.22), 3)));
      _trail.add((done, _stroke(key.accent.withValues(alpha: 0.75), 3)));
    }
  }

  /// Points every [step] along [path] (laid out once).
  static List<Offset> _along(Path path, double step) {
    final out = <Offset>[];
    for (final m in path.computeMetrics()) {
      for (var d = step / 2; d < m.length; d += step) {
        final tg = m.getTangentForOffset(d);
        if (tg != null) out.add(tg.position);
      }
    }
    return out;
  }

  static Path _cloud(Offset c, double r) => Path.combine(
        PathOperation.union,
        Path()
          ..addOval(Rect.fromCircle(center: c, radius: r))
          ..addOval(Rect.fromCircle(center: c.translate(-r * 0.95, r * 0.3), radius: r * 0.68)),
        Path()
          ..addOval(Rect.fromCircle(center: c.translate(r * 1.0, r * 0.32), radius: r * 0.62))
          ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(c.dx - r * 1.5, c.dy + r * 0.2, c.dx + r * 1.55, c.dy + r * 0.95), Radius.circular(r * 0.38))),
      );

  Paint get _line => _stroke(Color.lerp(_p.near, _p.ink, 0.45)!, AppBorder.focus);

  void _tree(Offset at) {
    final p = _p;
    _back.add((Path()..addOval(Rect.fromCenter(center: at.translate(0, 21), width: 48, height: 10)), _fill(p.ink.withValues(alpha: 0.12))));
    final trunk = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at.translate(0, 8), width: 10, height: 26), const Radius.circular(4)));
    _back.add((trunk, _fill(Color.lerp(p.hair, p.accent2, 0.3)!)));
    _back.add((trunk, _line));
    final crown = Path.combine(
      PathOperation.union,
      Path()..addOval(Rect.fromCircle(center: at.translate(0, -20), radius: 20)),
      Path()
        ..addOval(Rect.fromCircle(center: at.translate(-14, -7), radius: 14))
        ..addOval(Rect.fromCircle(center: at.translate(14, -7), radius: 14)),
    );
    _back.add((crown, _fill(p.near)));
    _back.add((Path()..addOval(Rect.fromCircle(center: at.translate(-7, -25), radius: 8)), _fill(Color.lerp(p.mid, p.paper, 0.2)!)));
    _back.add((crown, _line));
  }

  void _bush(Offset at, int seed) {
    final p = _p;
    final bush = Path.combine(
      PathOperation.union,
      Path()..addOval(Rect.fromCircle(center: at, radius: 14)),
      Path()
        ..addOval(Rect.fromCircle(center: at.translate(-15, 5), radius: 10))
        ..addOval(Rect.fromCircle(center: at.translate(15, 5), radius: 11))
        ..addRect(Rect.fromLTRB(at.dx - 15, at.dy + 5, at.dx + 15, at.dy + 15)),
    );
    _back.add((bush, _fill(p.mid)));
    _back.add((bush, _line));
    final petals = [p.accent, p.paper, p.accent2];
    for (var k = 0; k < 4; k++) {
      final c = at.translate(-16 + k * 11.0, k.isEven ? -3 : 5);
      _back.add((Path()..addOval(Rect.fromCircle(center: c, radius: 3.5)), _fill(petals[(seed + k) % 3])));
    }
  }

  void _rock(Offset at) {
    final p = _p;
    final stone = Color.lerp(p.paper, p.ink, 0.3)!;
    final edge = _stroke(Color.lerp(stone, p.ink, 0.4)!, AppBorder.focus);
    for (final r in [
      Path()..addOval(Rect.fromCenter(center: at, width: 34, height: 22)),
      Path()..addOval(Rect.fromCenter(center: at.translate(20, 5), width: 18, height: 12)),
    ]) {
      _back.add((r, _fill(stone)));
      _back.add((r, edge));
    }
    _back.add((Path()..addOval(Rect.fromCenter(center: at.translate(-5, -4), width: 12, height: 5)), _fill(p.paper.withValues(alpha: 0.6))));
    final tuft = Path();
    for (final dx in [-24.0, -19.0, 34.0]) {
      tuft
        ..moveTo(at.dx + dx, at.dy + 10)
        ..lineTo(at.dx + dx - 3, at.dy)
        ..moveTo(at.dx + dx, at.dy + 10)
        ..lineTo(at.dx + dx + 3, at.dy + 1);
    }
    _back.add((tuft, _stroke(p.near, AppBorder.focus)));
  }

  void _pines(Offset at, int seed) {
    final p = _p;
    final dark = _fill(Color.lerp(p.near, p.ink, 0.3)!);
    final rim = _stroke(key.accent.withValues(alpha: 0.4), AppBorder.hairline);
    for (final (dx, s) in [(0.0, 1.0), (18.0, 0.7), (-15.0, 0.6)]) {
      final x = at.dx + dx;
      final hgt = 46.0 * s * (seed.isEven ? 1 : 0.85);
      final tree = Path()
        ..moveTo(x, at.dy - hgt)
        ..lineTo(x + hgt * 0.32, at.dy)
        ..lineTo(x - hgt * 0.32, at.dy)
        ..close();
      _back.add((tree, dark));
      _back.add((tree, rim));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final g = _ground;
    if (g != null) canvas.drawRect(Offset.zero & size, g);
    for (final (points, paint) in _sky) {
      canvas.drawPoints(PointMode.points, points, paint);
    }
    for (final (path, paint) in _back) {
      canvas.drawPath(path, paint);
    }
    for (final (path, paint) in _trail) {
      canvas.drawPath(path, paint);
    }
    for (final (points, paint) in _dots) {
      canvas.drawPoints(PointMode.points, points, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter o) => o.key != key;
}
