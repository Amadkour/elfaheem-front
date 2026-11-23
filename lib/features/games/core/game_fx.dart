// lib/features/games/core/game_fx.dart — the visual feedback of Games v4 (T26, CONTRACT §2 settings).
//
//   GameFxKind        correct | wrong | combo | levelUp | finish
//   GameFxController  `fire(kind, at:)`; a template or the shell calls it, GameFxLayer draws it
//   GameFxLayer       wraps a game: ONE Ticker runs only while particles are alive (no idle loop), ONE CustomPainter,
//                     at most [kGameFxMaxParticles] particles alive at once (60 fps budget, no per-particle widget).
//                     Reduce motion: nothing moves, nothing is drawn. Calm (sacred content): a right answer is one
//                     soft ring, a wrong one draws and shakes NOTHING (the shell says "try again"); no confetti
//   GameFxSession     binds a GameSession to a controller: a score gain is `correct` (a run of three `combo`), a
//                     counted answer with no gain is `wrong`, the end is `finish`
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone, appToneColor;
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';

enum GameFxKind { correct, wrong, combo, levelUp, finish }

/// The most particles alive at once.
const int kGameFxMaxParticles = 80;

/// From this run of right answers a `combo` fires instead of `correct`.
const int kGameFxComboFrom = 3;

class GameFxEvent {
  const GameFxEvent(this.kind, this.at, this.id);
  final GameFxKind kind;

  /// Where it starts, 0..1 of the layer (null = the centre).
  final Offset? at;
  final int id;
}

class GameFxController extends ChangeNotifier {
  GameFxEvent? last;
  int _n = 0;

  void fire(GameFxKind kind, {Offset? at}) {
    last = GameFxEvent(kind, at, ++_n);
    notifyListeners();
  }
}

/// One particle: position and velocity in logical pixels, [life] seconds, a shape (0 dot, 1 confetti bar).
class GameParticle {
  GameParticle(this.x, this.y, this.vx, this.vy, this.life, this.color, this.size, this.bar, this.spin);
  double x, y;
  final double vx, vy, life, size, spin;
  final Color color;
  final bool bar;
  double age = 0;
}

/// Pure particle maths (tests drive it without a ticker).
class GameParticles {
  final List<GameParticle> items = [];
  static const double gravity = 520;

  /// Adds the particles of [kind] around [origin]; the total never goes over [kGameFxMaxParticles].
  void emit(GameFxKind kind, Offset origin, Size size, List<Color> colors, {required bool calm, int seed = 0}) {
    if (colors.isEmpty) return;
    final r = math.Random(seed);
    var n = switch (kind) {
      GameFxKind.correct => 14,
      GameFxKind.combo => 24,
      GameFxKind.levelUp => 40,
      GameFxKind.finish => 36,
      GameFxKind.wrong => 0,
    };
    if (calm) n = 0;
    n = math.min(n, kGameFxMaxParticles - items.length);
    final confetti = kind == GameFxKind.levelUp || kind == GameFxKind.finish;
    for (var i = 0; i < n; i++) {
      final a = confetti ? -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.2 : (i / n) * math.pi * 2 + r.nextDouble() * 0.4;
      final v = (confetti ? 320 : 160) * (0.5 + r.nextDouble() * 0.6);
      items.add(GameParticle(origin.dx, origin.dy, math.cos(a) * v, math.sin(a) * v, 0.7 + r.nextDouble() * (confetti ? 0.7 : 0.3),
          colors[i % colors.length], 3 + r.nextDouble() * 3, confetti && i.isOdd, r.nextDouble() * 6));
    }
  }

  /// Advances [dt] seconds; drops the finished ones. True while something is alive.
  bool step(double dt, {bool gravityOn = true}) {
    for (final p in items) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    items.removeWhere((p) => p.age >= p.life);
    if (gravityOn) {
      // gravity pulls the velocity of the confetti; applied to position through a second-order term
      for (final p in items) {
        if (p.bar) p.y += 0.5 * gravity * dt * dt * (1 + p.age * 6);
      }
    }
    return items.isNotEmpty;
  }
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.particles, this.ring, this.ringColor, this.tick) : super(repaint: tick);
  final GameParticles particles;

  /// A calm right answer's ring: (progress 0..1, centre), null = none.
  final ValueNotifier<({double t, Offset c})?> ring;
  final Color ringColor;
  final ValueNotifier<int> tick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles.items) {
      final k = (p.age / p.life).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: 1 - k);
      if (p.bar) {
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.spin + p.age * 8);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size * 2, height: p.size), paint);
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(p.x, p.y), p.size * (1 - k * 0.5), paint);
      }
    }
    final r = ring.value;
    if (r != null && r.t < 1) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ringColor.withValues(alpha: (1 - r.t) * 0.6);
      canvas.drawCircle(r.c, 24 + 56 * Curves.easeOutCubic.transform(r.t), stroke);
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}

/// Wraps [child] with the effects of [controller]. See the library header for what it does under Reduce motion and calm.
class GameFxLayer extends StatefulWidget {
  const GameFxLayer({super.key, required this.controller, required this.child, this.calm = false});

  final GameFxController controller;
  final Widget child;
  final bool calm;

  @override
  State<GameFxLayer> createState() => _GameFxLayerState();
}

class _GameFxLayerState extends State<GameFxLayer> with TickerProviderStateMixin {
  final GameParticles _particles = GameParticles();
  final ValueNotifier<int> _tick = ValueNotifier(0);
  final ValueNotifier<({double t, Offset c})?> _ring = ValueNotifier(null);
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  Duration _prev = Duration.zero;
  double _ringAge = 1;
  Size _size = Size.zero;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFx);
  }

  @override
  void didUpdateWidget(GameFxLayer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onFx);
      widget.controller.addListener(_onFx);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce motion parks everything at once (a loop already running stops).
    if (appMotionOff(context)) {
      _ticker.stop();
      _particles.items.clear();
      _ring.value = null;
      _shake.stop();
      _shake.value = 0;
    }
  }

  void _onFx() {
    final e = widget.controller.last;
    if (e == null || e.id == _seen || !mounted) return;
    _seen = e.id;
    if (appMotionOff(context) || _size.isEmpty) return;
    final c = context.colors;
    final origin = Offset((e.at?.dx ?? 0.5) * _size.width, (e.at?.dy ?? 0.5) * _size.height);
    if (e.kind == GameFxKind.wrong) {
      if (!widget.calm) _shake.forward(from: 0);
      return;
    }
    if (widget.calm) {
      // sacred: one soft ring, no particles, no confetti
      if (e.kind == GameFxKind.correct || e.kind == GameFxKind.finish) {
        _ringAge = 0;
        _ring.value = (t: 0, c: origin);
        _start();
      }
      return;
    }
    final colors = [c.success, appToneColor(context, AppTone.gold), c.primary];
    _particles.emit(e.kind, origin, _size, colors, calm: false, seed: e.id);
    _start();
  }

  void _start() {
    if (!_ticker.isActive) {
      _prev = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration now) {
    final dt = _prev == Duration.zero ? 0.016 : math.min(0.05, (now - _prev).inMicroseconds / 1e6);
    _prev = now;
    final alive = _particles.step(dt);
    var ringAlive = false;
    final r = _ring.value;
    if (r != null) {
      _ringAge += dt / 0.7;
      ringAlive = _ringAge < 1;
      _ring.value = ringAlive ? (t: _ringAge, c: r.c) : null;
    }
    _tick.value++;
    if (!alive && !ringAlive) _ticker.stop(); // no idle loop
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFx);
    _ticker.dispose();
    _shake.dispose();
    _tick.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      _size = box.biggest.isFinite ? box.biggest : Size.zero;
      return Stack(
        fit: StackFit.passthrough,
        children: [
          AnimatedBuilder(
            animation: _shake,
            child: widget.child,
            builder: (_, child) {
              final dx = _shake.isAnimating ? math.sin(_shake.value * math.pi * 6) * 8 * (1 - _shake.value) : 0.0;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: _FxPainter(_particles, _ring, c.success, _tick), size: Size.infinite)),
            ),
          ),
        ],
      );
    });
  }
}

/// Feeds [controller] from [session]: the layer needs no template code.
class GameFxSession {
  GameFxSession(this.session, this.controller) {
    _score = session.score;
    _count = session.trace.length;
    session.addListener(_onSession);
  }

  final GameSession session;
  final GameFxController controller;
  int _score = 0, _count = 0, _streak = 0;
  bool _done = false;

  /// The run of right answers (a wrong one resets it).
  int get streak => _streak;

  void _onSession() {
    if (session.finished) {
      if (!_done) {
        _done = true;
        controller.fire(GameFxKind.finish);
      }
      return;
    }
    final n = session.trace.length;
    if (n == _count) return;
    final gained = session.score > _score;
    _count = n;
    _score = session.score;
    if (gained) {
      _streak++;
      controller.fire(_streak >= kGameFxComboFrom ? GameFxKind.combo : GameFxKind.correct);
    } else {
      _streak = 0;
      controller.fire(GameFxKind.wrong);
    }
  }

  void dispose() => session.removeListener(_onSession);
}
