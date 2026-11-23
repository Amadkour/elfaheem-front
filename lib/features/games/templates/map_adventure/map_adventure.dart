// lib/features/games/templates/map_adventure/map_adventure.dart — Map Adventure (Games v4 T42, CONTRACT §2): `mcq` and
// `true_false` questions (sacred text allowed: a calm round) over QuestionStage. The scene is the progress bar: a map
// strip above each question with a winding trail, one stop per question and a treasure (kids) or flag at the end. A right
// answer walks the traveller to the next stop at once; a missed question (not in a calm round) leaves its stop grey
// and the traveller steps on when the next question comes. In a calm round (sacred text) the traveller is a quiet
// lantern: no character, no grey stops, nothing is lost by a wrong try, and the ayah is replayed.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/question_stage.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';

class MapAdventureTemplate extends GameTemplate {
  const MapAdventureTemplate();

  @override
  String get key => 'map_adventure';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.choose};
  @override
  Set<ItemType> get accepts => const {ItemType.mcq, ItemType.trueFalse};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'مغامرة الخريطة';
  @override
  String get nameEn => 'Map Adventure';
  @override
  IconData get icon => Icons.map_rounded;

  @override
  Widget build(GameSession s) => MapAdventureGame(session: s);
}

const MapAdventureTemplate kMapAdventure = MapAdventureTemplate();

/// How one stop of the trail ended.
enum StopResult { pending, right, missed }

class MapAdventureGame extends StatefulWidget {
  const MapAdventureGame({super.key, required this.session, this.silent = false, this.reciters});
  final GameSession session;
  final bool silent;

  /// Tests replace the reciter list loader.
  final ReciterLoader? reciters;

  @override
  State<MapAdventureGame> createState() => _MapAdventureGameState();
}

class _MapAdventureGameState extends State<MapAdventureGame> {
  final QuestionStageController _stage = QuestionStageController();
  late final List<StopResult> _results = List.filled(widget.session.items.length, StopResult.pending);
  int _cur = -1;
  GameMood _mood = GameMood.idle;

  @override
  void dispose() {
    unawaited(GameAudio.instance.stopRecitation());
    super.dispose();
  }

  void _play(GameItem it) {
    final segs = stageSegments(it);
    if (segs.isEmpty) return;
    final r = widget.session.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(segs, reciter: r is String ? r : null).catchError((Object _) {}));
  }

  void _shown(GameItem it) {
    if (mounted) setState(() => _cur = math.min(_cur + 1, _results.length - 1));
    _play(it);
  }

  void _setMood(GameMood m) {
    if (mounted) setState(() => _mood = m);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _mood == m) setState(() => _mood = GameMood.idle);
    });
  }

  void _wrong(GameItem it) {
    final calm = widget.session.calm || widget.session.sacred || it.sacred;
    if (calm) {
      _play(it); // the ayah again, the learner tries once more
      return;
    }
    setState(() {
      if (_cur >= 0 && _results[_cur] == StopResult.pending) _results[_cur] = StopResult.missed;
    });
    _setMood(GameMood.sad);
  }

  void _right(GameItem it) {
    setState(() {
      if (_cur >= 0) _results[_cur] = StopResult.right;
    });
    _setMood(GameMood.happy);
  }

  /// The stop the traveller stands on: the next one once the question is answered right.
  int get _pos {
    if (_cur < 0) return 0;
    return _results[_cur] == StopResult.right ? _cur + 1 : _cur;
  }

  Widget? _header(BuildContext context, GameItem it, StageSurface sf) {
    final theme = AgeThemeScope.of(context);
    final tall = MediaQuery.sizeOf(context).height >= 700;
    final audio = it.media.audio != null && it.media.audio!.isNotEmpty;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MapAdventureStrip(
        theme: theme,
        surface: sf,
        total: _results.length,
        position: _pos,
        results: List.of(_results),
        mood: _mood,
        calm: widget.session.calm || widget.session.sacred || it.sacred,
        height: wide ? 148 : (tall ? 124 : 100),
      ),
      if (audio) ...[
        AppSpace.gapSm,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: widget.session.reciter?['key'] as String?),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return StageFrame(
      session: widget.session,
      kinds: kMapAdventure.kinds,
      silent: widget.silent,
      onHint: _stage.hint,
      child: QuestionStage(
        session: widget.session,
        controller: _stage,
        silent: widget.silent,
        header: _header,
        onItemShown: _shown,
        onWrong: _wrong,
        onRight: _right,
      ),
    );
  }
}

/// The trail's geometry for one size: a stop every `dx`, on a gentle wave, joined by smooth segments.
class _Trail {
  _Trail(Size size, int total, {required bool rtl}) : stops = [], segs = [], metrics = [] {
    final n = total + 1;
    final pad = math.min(34.0, size.width * 0.09);
    final w = size.width - pad * 2;
    final base = size.height * 0.74;
    final amp = size.height * 0.1;
    for (var k = 0; k < n; k++) {
      final f = n == 1 ? 0.0 : k / (n - 1);
      final x = pad + (rtl ? 1 - f : f) * w;
      stops.add(Offset(x, base + math.sin(k * 1.25) * amp * (k == 0 ? 0.4 : 1)));
    }
    for (var k = 0; k < n - 1; k++) {
      final a = stops[k], b = stops[k + 1];
      final mx = (a.dx + b.dx) / 2;
      final p = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      segs.add(p);
      metrics.add(p.computeMetrics().first);
    }
    spacing = n > 1 ? (w / (n - 1)) : w;
  }

  final List<Offset> stops;
  final List<Path> segs;
  final List<ui.PathMetric> metrics;
  double spacing = 40;

  /// The point on the trail at fractional stop [t] (0 .. total).
  Offset at(double t) {
    if (segs.isEmpty) return stops.first;
    final k = t.floor().clamp(0, segs.length - 1);
    final f = (t - k).clamp(0.0, 1.0);
    final m = metrics[k];
    return m.getTangentForOffset(m.length * f)?.position ?? stops[k];
  }
}

/// The map strip: plain values only (the layout harness and the golden draw it without a session).
class MapAdventureStrip extends StatefulWidget {
  const MapAdventureStrip({
    super.key,
    required this.theme,
    required this.surface,
    required this.total,
    required this.position,
    required this.results,
    this.mood = GameMood.idle,
    this.calm = false,
    this.height = 124,
  });

  final AgeTheme theme;
  final StageSurface surface;

  /// Questions in the round; the strip has `total + 1` stops (the last one is the treasure).
  final int total;

  /// The stop the traveller stands on (0 .. total).
  final int position;
  final List<StopResult> results;
  final GameMood mood;
  final bool calm;
  final double height;

  @override
  State<MapAdventureStrip> createState() => _MapAdventureStripState();
}

class _MapAdventureStripState extends State<MapAdventureStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  double _from = 0, _to = 0;
  _Trail? _trail;
  Size _trailSize = Size.zero;
  int _trailTotal = -1;
  bool _trailRtl = false;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.position.toDouble();
    _c.value = 1;
  }

  @override
  void didUpdateWidget(MapAdventureStrip old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      _from = _value;
      _to = widget.position.toDouble();
      if (appMotionOff(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _value => _from + (_to - _from) * Curves.easeInOutCubic.transform(_c.value);

  _Trail _trailFor(Size s, bool rtl) {
    if (_trail == null || _trailSize != s || _trailTotal != widget.total || _trailRtl != rtl) {
      _trail = _Trail(s, widget.total, rtl: rtl);
      _trailSize = s;
      _trailTotal = widget.total;
      _trailRtl = rtl;
    }
    return _trail!;
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final theme = widget.theme;
    final sf = widget.surface;
    final kids = theme.age == GameAge.kids && !widget.calm;
    final label = t('الخريطة: المحطة ${widget.position} من ${widget.total}', 'Map: stop ${widget.position} of ${widget.total}');
    return Semantics(
      label: label,
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(sf.radius + 4),
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, widget.height);
            final trail = _trailFor(size, rtl);
            final charSize = math.min(widget.height * 0.52, 76.0);
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = _value;
                final moving = _c.isAnimating;
                final p = trail.at(v);
                final hop = moving && kids ? math.sin(math.pi * ((v * 2) % 1)) * 8 : 0.0;
                return Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _MapPainter(
                          theme: theme,
                          surface: sf,
                          trail: trail,
                          results: widget.results,
                          value: v,
                          calm: widget.calm,
                          kids: kids,
                          rtl: rtl,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: p.dx - charSize / 2,
                    top: p.dy - charSize * 0.92 - hop,
                    width: charSize,
                    height: charSize,
                    child: widget.calm
                        ? CustomPaint(painter: _LanternPainter(theme))
                        : GameCharacter(theme: theme, mood: widget.mood, size: charSize),
                  ),
                ]);
              },
            );
          }),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.theme,
    required this.surface,
    required this.trail,
    required this.results,
    required this.value,
    required this.calm,
    required this.kids,
    required this.rtl,
  });

  final AgeTheme theme;
  final StageSurface surface;
  final _Trail trail;
  final List<StopResult> results;
  final double value;
  final bool calm, kids, rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final pal = theme.palette;
    final rect = Offset.zero & size;
    final night = theme.night;
    // the panel: paper, with two soft hills of the age's land colours
    canvas.drawRect(rect, Paint()..color = pal.paper.withValues(alpha: night ? 0.9 : 0.94));
    final far = Path()
      ..moveTo(0, size.height * 0.62)
      ..cubicTo(size.width * 0.25, size.height * 0.4, size.width * 0.5, size.height * 0.62, size.width * 0.75, size.height * 0.48)
      ..cubicTo(size.width * 0.88, size.height * 0.42, size.width * 0.95, size.height * 0.5, size.width, size.height * 0.46)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(far, Paint()..color = pal.far.withValues(alpha: calm ? 0.2 : 0.34));
    final near = Path()
      ..moveTo(0, size.height * 0.82)
      ..cubicTo(size.width * 0.3, size.height * 0.64, size.width * 0.62, size.height * 0.92, size.width, size.height * 0.7)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(near, Paint()..color = pal.mid.withValues(alpha: calm ? 0.22 : 0.4));

    final line = kids ? 6.0 : (theme.age == GameAge.teen && !calm ? 3.0 : 2.5);
    // the trail ahead: dashes along each segment
    final ahead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..strokeCap = StrokeCap.round
      ..color = pal.ink.withValues(alpha: 0.28);
    final dash = line * 2.4, gap = line * 2.2;
    final k0 = value.floor().clamp(0, trail.segs.length);
    for (var k = k0; k < trail.segs.length; k++) {
      final m = trail.metrics[k];
      var d = k == k0 ? m.length * (value - k0).clamp(0.0, 1.0) : 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), ahead);
        d += dash + gap;
      }
    }
    // the trail behind: solid in the accent, with a soft ink edge for kids
    final done = Path();
    for (var k = 0; k < math.min(k0, trail.segs.length); k++) {
      done.addPath(trail.segs[k], Offset.zero);
    }
    if (k0 < trail.segs.length && value > k0) {
      final m = trail.metrics[k0];
      done.addPath(m.extractPath(0, m.length * (value - k0)), Offset.zero);
    }
    if (kids) {
      canvas.drawPath(
        done,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = line + 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = pal.ink.withValues(alpha: 0.85),
      );
    }
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = calm ? pal.accent.withValues(alpha: 0.8) : pal.accent,
    );

    // the stops
    final n = trail.stops.length;
    final r = (trail.spacing * 0.28).clamp(4.0, kids ? 11.0 : 8.0);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kids ? 3.0 : 1.6
      ..color = pal.ink;
    for (var k = 0; k < n - 1; k++) {
      final c = trail.stops[k];
      final passed = k < value - 0.001;
      final missed = k < results.length && results[k] == StopResult.missed && passed;
      final fill = passed ? (missed ? pal.ink.withValues(alpha: 0.35) : pal.gold) : pal.paper;
      canvas.drawCircle(c, r, Paint()..color = fill);
      canvas.drawCircle(c, r, outline..color = passed ? pal.ink : pal.ink.withValues(alpha: 0.45));
      if (passed && !missed && r >= 6) {
        // a small tick: the stop was reached
        final tick = Path()
          ..moveTo(c.dx - r * 0.42, c.dy)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.34)
          ..lineTo(c.dx + r * 0.46, c.dy - r * 0.34);
        canvas.drawPath(
          tick,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = kids ? 2.2 : 1.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = pal.ink,
        );
      }
    }
    final end = trail.stops.last;
    final reached = value >= n - 1 - 0.001;
    if (kids) {
      _chest(canvas, end, math.max(r * 2.4, 22), pal, reached);
    } else {
      _flag(canvas, end, math.max(r * 3.2, 26), pal, reached);
    }
  }

  void _flag(Canvas canvas, Offset base, double h, GamePalette pal, bool reached) {
    final dir = rtl ? -1.0 : 1.0;
    final pole = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = pal.ink;
    canvas.drawLine(base, base.translate(0, -h), pole);
    final cloth = Path()
      ..moveTo(base.dx, base.dy - h)
      ..lineTo(base.dx + dir * h * 0.62, base.dy - h * 0.8)
      ..lineTo(base.dx, base.dy - h * 0.58)
      ..close();
    canvas.drawPath(cloth, Paint()..color = reached ? pal.gold : pal.accent);
    canvas.drawCircle(base, 3.2, Paint()..color = pal.ink);
  }

  void _chest(Canvas canvas, Offset base, double w, GamePalette pal, bool reached) {
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: base.translate(0, -w * 0.2), width: w, height: w * 0.58), const Radius.circular(5));
    final lidTop = reached ? -w * 0.62 : -w * 0.5;
    final lid = RRect.fromRectAndCorners(
      Rect.fromLTWH(base.dx - w / 2, base.dy + lidTop - w * 0.14, w, w * 0.28),
      topLeft: const Radius.circular(9),
      topRight: const Radius.circular(9),
    );
    final wood = Paint()..color = Color.lerp(pal.accent2, pal.ink, 0.45)!;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = pal.ink;
    if (reached) {
      canvas.drawCircle(base.translate(0, -w * 0.62), w * 0.34, Paint()..color = pal.gold.withValues(alpha: 0.55));
    }
    canvas.drawRRect(body, wood);
    canvas.drawRRect(body, edge);
    canvas.drawRRect(lid, Paint()..color = Color.lerp(pal.accent2, pal.paper, 0.1)!);
    canvas.drawRRect(lid, edge);
    canvas.drawCircle(base.translate(0, -w * 0.2), 3.4, Paint()..color = pal.gold);
  }

  @override
  bool shouldRepaint(_MapPainter o) =>
      o.value != value || o.trail != trail || o.theme != theme || o.calm != calm || !listEquals(o.results, results) || o.rtl != rtl || o.surface.context != surface.context;
}

/// The calm traveller: a small lantern (no face, nothing that moves much).
class _LanternPainter extends CustomPainter {
  _LanternPainter(this.theme);
  final AgeTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final pal = theme.palette;
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height - s * 0.34);
    canvas.drawCircle(c, s * 0.34, Paint()..color = pal.gold.withValues(alpha: 0.28));
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.3, height: s * 0.4), Radius.circular(s * 0.08));
    canvas.drawRRect(body, Paint()..color = pal.gold.withValues(alpha: 0.9));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = pal.ink,
    );
    canvas.drawLine(c.translate(0, -s * 0.2), c.translate(0, -s * 0.3), Paint()
      ..strokeWidth = 1.8
      ..color = pal.ink);
  }

  @override
  bool shouldRepaint(_LanternPainter o) => o.theme != theme;
}
