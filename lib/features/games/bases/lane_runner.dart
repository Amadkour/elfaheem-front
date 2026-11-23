// lib/features/games/bases/lane_runner.dart — the lane-runner base of Games v4 (T38, CONTRACT §2: car_race, space_rocket).
//
//   RunnerGate       one fork: a label per lane (a word, a number, an answer); a gate hangs over the road with a sign above
//                    every lane
//   LaneRunnerGame   a Flame game: a vanishing-point road with parallax hills, speed lines, roadside scenery, a gate that
//                    comes towards the player, a car that steers between lanes and the particles of game_fx. A template
//                    shows a gate (`showGate`), hears the lane the player drove through (`onChosen`) and answers
//                    (`resolve`). Calm (sacred text): the gate WAITS in front of the car and the lane is chosen by a tap
//                    on it (no time pressure, no speed lines, no shake); a wrong lane is a quiet retry (`retry: true`).
//   LaneRunnerView   the widget: FlameHost + swipe (steer), tap (go to that lane) and tilt (setting `tilt`)
//
// Everything that costs is cached once per size: the sky, hills, road, scenery and car are recorded Pictures, the sign
// words are laid-out TextPainters per gate, the paints and paths are reused; a frame allocates no objects of its own
// (only the particles of game_fx, at most 80). The game never touches a platform object (headless tests drive
// `onGameResize` / `update` / `render` directly).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/flame_host.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_fx.dart';

/// True when [s] holds a right-to-left letter (Arabic, Hebrew, Syriac, Thaana).
bool textIsRtl(String s) => s.runes.any((r) => r >= 0x0590 && r <= 0x08FF);

/// One fork of the road: [labels] has one entry per lane (2..4), left to right on the screen.
class RunnerGate {
  const RunnerGate({required this.labels});
  final List<String> labels;
  int get lanes => labels.length;
}

enum RunnerPhase { idle, approach, hold, commit, judging, pass, retry }

/// How a lane sign is drawn.
enum _Sign { plain, hint, good, bad, dim }

class LaneRunnerGame extends FlameGame {
  LaneRunnerGame({required this.theme, this.speed = 3, this.equipped = const {}, this.lanes = 3})
      : calm = theme.calm,
        _carLane = (lanes - 1) ~/ 2;

  final AgeTheme theme;

  /// 1..5 (`settings.speed`): how fast the gate comes.
  final int speed;
  final Map<String, String?> equipped;

  /// Lanes of the road until the first gate says otherwise.
  int lanes;
  final bool calm;

  /// Reduce motion: no speed lines, no particles, a slow road.
  bool reduceMotion = false;

  /// The lane the player drove through (only once per gate, at the gate or when a calm tap commits).
  ValueChanged<int>? onChosen;

  /// The gate left the road (or a calm retry is ready for the next try).
  VoidCallback? onResolved;

  // ---- state ----
  RunnerGate? _gate;
  RunnerPhase _phase = RunnerPhase.idle;
  double _gateT = 0.1;
  double _phaseTime = 0;
  int _chosen = -1;
  int _carLane;
  double _carU = 0, _carVel = 0;
  double _time = 0, _scroll = 0, _boost = 0, _shake = 0;
  GameMood _mood = GameMood.idle;
  double _moodLeft = 0;
  bool _correct = false;
  final List<_Sign> _signs = [_Sign.plain, _Sign.plain, _Sign.plain, _Sign.plain];
  final List<_Plate?> _plates = [null, null, null, null];

  RunnerPhase get phase => _phase;
  RunnerGate? get gate => _gate;
  int get carLane => _carLane;
  bool get awaitingChoice => _phase == RunnerPhase.hold || _phase == RunnerPhase.approach;
  int get laneCount => _gate?.lanes ?? lanes;
  double get gateProgress => _gateT;

  // ---- geometry ----
  static const double _tCar = 0.9, _tHold = 0.74, _tStart = 0.12;
  double _w = 0, _h = 0, _hy = 0, _half = 0;

  double _yAt(double t) => _hy + t * (_h - _hy);
  double _xAt(double u, double t) => _w / 2 + u * _half * t;
  static double _laneU(int i, int n) => -1 + (2 * i + 1) / n;

  // ---- caches ----
  ui.Picture? _sky, _hillsFar, _hillsNear, _road, _tree, _tree2;
  final Map<GameMood, ui.Picture> _car = {};
  late final Paint _fill = Paint();
  late final Paint _line = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
  final Path _path = Path();
  final GameParticles _particles = GameParticles();
  Color _asphalt = Colors.black;

  // ---- speed lines (fixed, no per-frame randomness) ----
  static const int _nLines = 18;
  final List<double> _lineAng = List.generate(_nLines, (i) => (i / _nLines) * math.pi * 2 + (i.isOdd ? 0.11 : -0.05));
  final List<double> _linePh = List.generate(_nLines, (i) => ((i * 0.6180339) % 1.0));

  /// How many lines the player sees, tests read it.
  bool get speedLinesOn => !calm && !reduceMotion;

  @override
  Color backgroundColor() => const Color(0x00000000);

  // ---------------------------------------------------------------------------------------------- input

  /// Steers one lane ([d] is -1 left, +1 right).
  void steer(int d) => moveTo(_carLane + d);

  void moveTo(int lane) {
    final n = laneCount;
    _carLane = lane.clamp(0, n - 1);
  }

  /// The lane under screen x ([x] in the game's pixels), at the car's depth.
  int laneAtX(double x) {
    final n = laneCount;
    final u = (x - _w / 2) / (_half * _tCar);
    return (((u + 1) / 2) * n).floor().clamp(0, n - 1);
  }

  /// A tap at [x]: the car goes to that lane; in a calm round the tap also commits to it (the gate then comes).
  void tapAt(double x) {
    final lane = laneAtX(x);
    moveTo(lane);
    if (calm && _phase == RunnerPhase.hold) commit();
  }

  /// Calm: drive through the lane the car is in. Does nothing unless the gate is waiting.
  void commit([int? lane]) {
    if (_phase != RunnerPhase.hold) return;
    if (lane != null) moveTo(lane);
    _phase = RunnerPhase.commit;
    _phaseTime = 0;
  }

  // ---------------------------------------------------------------------------------------------- the gate

  /// A new fork comes down the road.
  void showGate(RunnerGate g) {
    assert(g.lanes >= 2 && g.lanes <= 4, 'a gate has 2..4 lanes');
    _gate = g;
    _gateT = _tStart;
    _phase = RunnerPhase.approach;
    _phaseTime = 0;
    _chosen = -1;
    for (var i = 0; i < 4; i++) {
      _signs[i] = _Sign.plain;
      _plates[i] = i < g.lanes ? _Plate(g.labels[i], theme.palette) : null;
    }
    _carLane = _carLane.clamp(0, g.lanes - 1);
  }

  /// Lights up the sign of [lane] (a hint).
  void hintLane(int lane) {
    if (lane >= 0 && lane < 4 && _signs[lane] == _Sign.plain) _signs[lane] = _Sign.hint;
  }

  /// The template's verdict on the lane just chosen. Right: the car speeds up and the sign lights. Wrong in a calm
  /// round ([retry]): the sign dims and the gate waits for another try. Wrong otherwise: a bump, the right sign lights
  /// and the gate passes. [correctLane] is shown on the signs when known.
  void resolve({required bool correct, int? correctLane, bool retry = false}) {
    if (_gate == null || _phase == RunnerPhase.pass || _phase == RunnerPhase.retry) return;
    _correct = correct;
    if (correct) {
      _signs[_chosen.clamp(0, 3)] = _Sign.good;
      _boost = 1;
      _setMood(GameMood.happy, 1.4);
      if (!reduceMotion) _burst(GameFxKind.correct);
      _phase = RunnerPhase.pass;
    } else if (retry || calm) {
      _signs[_chosen.clamp(0, 3)] = _Sign.dim;
      _setMood(GameMood.idle, 0);
      _phase = RunnerPhase.retry;
    } else {
      _signs[_chosen.clamp(0, 3)] = _Sign.bad;
      if (correctLane != null && correctLane >= 0 && correctLane < 4) _signs[correctLane] = _Sign.good;
      _shake = reduceMotion ? 0 : 1;
      _setMood(GameMood.sad, 1.4);
      _phase = RunnerPhase.pass;
    }
    _phaseTime = 0;
  }

  void _setMood(GameMood m, double secs) {
    _mood = m;
    _moodLeft = secs;
  }

  void _burst(GameFxKind kind) {
    final c = theme.palette;
    _particles.emit(kind, Offset(_xAt(_laneU(_carLane, laneCount), _tCar), _yAt(_tCar) - _half * 0.2), Size(_w, _h),
        [c.gold, c.accent, c.accent2, c.paper], calm: calm, seed: (_time * 1000).toInt());
  }

  void _choose(int lane) {
    _chosen = lane;
    _phase = RunnerPhase.judging;
    _phaseTime = 0;
    final cb = onChosen;
    if (cb != null) cb(lane);
  }

  // ---------------------------------------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    if (_w == 0) return;
    if (dt > 0.1) dt = 0.1;
    _time += dt;
    _phaseTime += dt;
    final base = reduceMotion ? 0.35 : 1.0;
    _scroll += dt * (1.5 + 0.45 * speed) * (1 + _boost * 1.6) * (calm ? 0.55 : 1) * base;
    _boost = math.max(0, _boost - dt * 0.9);
    _shake = math.max(0, _shake - dt * 2.2);
    if (_moodLeft > 0) {
      _moodLeft -= dt;
      if (_moodLeft <= 0) _mood = GameMood.idle;
    }

    // the car follows its lane with a critically damped spring
    final goal = _laneU(_carLane, laneCount);
    final k = 1 - math.exp(-11 * dt);
    final prev = _carU;
    _carU += (goal - _carU) * k;
    _carVel = dt > 0 ? (_carU - prev) / dt : 0;

    final g = _gate;
    if (g != null) {
      switch (_phase) {
        case RunnerPhase.approach:
          final d = math.max(2.0, 7.0 - 0.9 * speed);
          _gateT += dt * ((calm ? _tHold : _tCar) - _tStart) / d;
          if (calm && _gateT >= _tHold) {
            _gateT = _tHold;
            _phase = RunnerPhase.hold;
          } else if (!calm && _gateT >= _tCar) {
            _gateT = _tCar;
            _choose(_carLane);
          }
        case RunnerPhase.commit:
          _gateT += dt * (_tCar - _tHold) / 0.55;
          if (_gateT >= _tCar) {
            _gateT = _tCar;
            _choose(_carLane);
          }
        case RunnerPhase.pass:
          _gateT += dt * (_correct ? 0.9 : 0.6);
          if (_gateT > 1.28) {
            _gate = null;
            _phase = RunnerPhase.idle;
            onResolved?.call();
          }
        case RunnerPhase.retry:
          _gateT += (_tHold - _gateT) * (1 - math.exp(-5 * dt));
          if (_phaseTime > 0.9) {
            _gateT = _tHold;
            _chosen = -1;
            _phase = RunnerPhase.hold;
            onResolved?.call();
          }
        case RunnerPhase.hold:
        case RunnerPhase.judging:
        case RunnerPhase.idle:
          break;
      }
    }
    if (!reduceMotion) _particles.step(dt);
  }

  // ---------------------------------------------------------------------------------------------- caches

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    if (size.x == _w && size.y == _h) return;
    _w = size.x;
    _h = size.y;
    _hy = _h * 0.3;
    _half = math.min(_w * 0.5, (_h - _hy) * 0.62);
    _buildCaches();
  }

  void _buildCaches() {
    final p = theme.palette;
    _asphalt = Color.lerp(p.ink, p.near, theme.calm ? 0.45 : 0.3)!;
    _sky = _record((c) => _paintSky(c));
    _hillsFar = _record((c) => _paintHills(c, far: true), width: _w * 1.5);
    _hillsNear = _record((c) => _paintHills(c, far: false), width: _w * 1.5);
    _road = _record((c) => _paintRoad(c));
    _tree = _record((c) => _paintTree(c, 0), width: 70, height: 100);
    _tree2 = _record((c) => _paintTree(c, 1), width: 70, height: 100);
    _car.clear();
  }

  ui.Picture _record(void Function(Canvas) draw, {double? width, double? height}) {
    final r = ui.PictureRecorder();
    final c = Canvas(r, Rect.fromLTWH(0, 0, width ?? _w, height ?? _h));
    draw(c);
    return r.endRecording();
  }

  void _paintSky(Canvas c) {
    final p = theme.palette;
    final rect = Rect.fromLTWH(0, 0, _w, _h);
    c.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, _hy), [p.skyTop, p.skyMid, p.skyBottom], [0, 0.55, 1]));
    // the ground behind the road
    c.drawRect(
        Rect.fromLTWH(0, _hy, _w, _h - _hy),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, _hy), Offset(0, _h), [Color.lerp(p.mid, p.skyBottom, 0.45)!, p.near]));
    // a sun / moon glow on the horizon
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, _w, _hy + 1));
    final sun = Offset(_w * 0.72, _hy - _h * 0.09);
    c.drawCircle(
        sun,
        _h * 0.34,
        Paint()
          ..shader = ui.Gradient.radial(sun, _h * 0.34, [p.glow.withValues(alpha: theme.calm ? 0.45 : 0.75), p.glow.withValues(alpha: 0)]));
    c.drawCircle(sun, _h * 0.045, Paint()..color = p.paper.withValues(alpha: 0.92));
    final cloud = Paint()..color = p.cloud.withValues(alpha: theme.night ? 0.22 : 0.8);
    final r = math.Random(5);
    for (var i = 0; i < (theme.calm ? 3 : 5); i++) {
      final x = _w * (0.08 + 0.2 * i + r.nextDouble() * 0.08);
      final y = _hy * (0.18 + r.nextDouble() * 0.5);
      final s = _h * (0.03 + r.nextDouble() * 0.025);
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: s * 4.6, height: s * 1.5), cloud);
      c.drawOval(Rect.fromCenter(center: Offset(x + s * 0.9, y - s * 0.55), width: s * 2.6, height: s * 1.5), cloud);
    }
    c.restore();
    if (theme.night) {
      final star = Paint()..color = p.paper.withValues(alpha: 0.85);
      for (var i = 0; i < 46; i++) {
        c.drawCircle(Offset(r.nextDouble() * _w, r.nextDouble() * _hy * 0.8), 0.6 + r.nextDouble() * 1.1, star);
      }
    }
  }

  void _paintHills(Canvas c, {required bool far}) {
    final p = theme.palette;
    final w = _w * 1.5;
    final base = _hy + 1;
    final amp = _h * (far ? 0.075 : 0.05);
    final path = Path()..moveTo(0, base);
    for (var x = 0.0; x <= w; x += 6) {
      final y = base - amp * (0.55 + 0.3 * math.sin(x / w * math.pi * (far ? 5 : 8) + (far ? 0.4 : 2.0)) + 0.15 * math.sin(x / w * math.pi * 17));
      path.lineTo(x, y);
    }
    path.lineTo(w, base);
    path.close();
    final top = far ? p.far : p.mid;
    c.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, base - amp), Offset(0, base), [Color.lerp(top, p.skyBottom, far ? 0.3 : 0.1)!, top]));
    if (theme.age == GameAge.teen && !far) {
      // a lit skyline on the near layer
      final lit = Paint()..color = p.accent2.withValues(alpha: 0.7);
      final r = math.Random(9);
      for (var x = 10.0; x < w; x += 20 + r.nextDouble() * 18) {
        final bh = amp * (0.4 + r.nextDouble() * 0.9);
        c.drawRect(Rect.fromLTWH(x, base - bh, 12, bh), Paint()..color = p.near.withValues(alpha: 0.9));
        if (r.nextBool()) c.drawRect(Rect.fromLTWH(x + 3, base - bh + 4, 3, 3), lit);
      }
    }
  }

  void _paintRoad(Canvas c) {
    final p = theme.palette;
    final b = _yAt(1.3);
    final hw = _half * 1.3;
    final road = Path()
      ..moveTo(_w / 2, _hy)
      ..lineTo(_w / 2 + hw, b)
      ..lineTo(_w / 2 - hw, b)
      ..close();
    c.drawPath(
        road,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, _hy), Offset(0, _h), [
            Color.lerp(_asphalt, p.skyBottom, 0.5)!,
            Color.lerp(_asphalt, p.skyBottom, 0.12)!,
            _asphalt,
          ], [0, 0.35, 1]));
    // the edge lines
    final edge = Paint()..color = p.paper.withValues(alpha: theme.calm ? 0.55 : 0.9);
    for (final s in [-1.0, 1.0]) {
      final e = Path()
        ..moveTo(_w / 2 + s * 0.955 * 0.0, _hy)
        ..lineTo(_w / 2 + s * 0.94 * hw, b)
        ..lineTo(_w / 2 + s * 0.985 * hw, b)
        ..close();
      c.drawPath(e, edge);
    }
    // the haze at the horizon
    c.drawRect(
        Rect.fromLTWH(0, _hy - 2, _w, _h * 0.05),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, _hy - 2), Offset(0, _hy + _h * 0.05),
              [p.skyBottom.withValues(alpha: 0.7), p.skyBottom.withValues(alpha: 0)]));
  }

  void _paintTree(Canvas c, int kind) {
    final p = theme.palette;
    // origin at the bottom centre (35, 100)
    if (theme.age == GameAge.teen && !theme.calm) {
      // a neon lamp post
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 18, 6, 82), const Radius.circular(3)), Paint()..color = p.ink);
      c.drawCircle(const Offset(35, 16), 13, Paint()..shader = ui.Gradient.radial(const Offset(35, 16), 13, [p.accent.withValues(alpha: 0.85), p.accent.withValues(alpha: 0)]));
      c.drawCircle(const Offset(35, 16), 5, Paint()..color = p.paper);
      return;
    }
    final trunk = Color.lerp(p.hair, p.ink, 0.3)!;
    final leaf = kind == 0 ? p.near : Color.lerp(p.near, p.mid, 0.45)!;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 56, 8, 44), const Radius.circular(3)), Paint()..color = trunk);
    if (theme.age == GameAge.adult || theme.calm) {
      // a slim cypress
      final cy = Path()
        ..moveTo(35, 4)
        ..quadraticBezierTo(58, 46, 47, 78)
        ..lineTo(23, 78)
        ..quadraticBezierTo(12, 46, 35, 4);
      c.drawPath(cy, Paint()..color = leaf);
      c.drawPath(
          cy,
          Paint()
            ..shader = ui.Gradient.linear(const Offset(15, 0), const Offset(55, 0),
                [Colors.white.withValues(alpha: 0.12), Colors.black.withValues(alpha: 0.14)]));
      return;
    }
    // a round cartoon tree: three lobes, a light side and a dark side
    for (final o in const [Offset(35, 34), Offset(21, 46), Offset(49, 46)]) {
      c.drawCircle(o, 21, Paint()..color = leaf);
    }
    c.drawCircle(const Offset(28, 28), 9, Paint()..color = Colors.white.withValues(alpha: 0.18));
    c.drawCircle(const Offset(48, 52), 14, Paint()..color = Colors.black.withValues(alpha: 0.1));
    if (kind == 1) {
      for (final o in const [Offset(24, 38), Offset(44, 30), Offset(38, 52)]) {
        c.drawCircle(o, 3, Paint()..color = p.accent);
      }
    }
  }

  ui.Picture _carPicture(GameMood mood) {
    return _car.putIfAbsent(mood, () {
      final p = theme.palette;
      final r = ui.PictureRecorder();
      final c = Canvas(r, const Rect.fromLTWH(0, 0, 100, 80));
      // the driver first (behind the window), cropped to the cabin
      final eq = {...equipped}..remove('vehicle')..remove('trail');
      final cr = ui.PictureRecorder();
      CharacterPainter(theme, eq, mood, const AlwaysStoppedAnimation<double>(0)).paint(Canvas(cr), const Size(100, 100));
      final driver = cr.endRecording();
      final body = Color.lerp(p.accent, p.ink, 0.05)!;
      final dark = Color.lerp(p.accent, p.ink, 0.45)!;
      // wheels
      for (final x in [4.0, 78.0]) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 56, 18, 24), const Radius.circular(5)), Paint()..color = p.ink);
      }
      // cabin
      final cabin = Path()
        ..moveTo(22, 40)
        ..lineTo(29, 8)
        ..quadraticBezierTo(50, 2, 71, 8)
        ..lineTo(78, 40)
        ..close();
      c.drawPath(cabin, Paint()..shader = ui.Gradient.linear(const Offset(0, 4), const Offset(0, 40), [Color.lerp(body, p.paper, 0.25)!, body]));
      final win = Path()
        ..moveTo(27, 36)
        ..lineTo(33, 12)
        ..quadraticBezierTo(50, 8, 67, 12)
        ..lineTo(73, 36)
        ..close();
      c.save();
      c.drawPath(win, Paint()..color = Color.lerp(p.skyTop, p.ink, 0.55)!);
      c.clipPath(win);
      c.translate(50 - 0.5 * 52, -2);
      c.scale(0.52);
      c.drawPicture(driver);
      c.restore();
      c.drawPath(win, Paint()..shader = ui.Gradient.linear(const Offset(27, 12), const Offset(73, 36), [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)]));
      // the lower body
      final lower = RRect.fromRectAndRadius(const Rect.fromLTWH(6, 36, 88, 38), const Radius.circular(12));
      c.drawRRect(lower, Paint()..shader = ui.Gradient.linear(const Offset(0, 36), const Offset(0, 74), [Color.lerp(body, p.paper, 0.18)!, body, dark], [0, 0.45, 1]));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 38, 80, 4), const Radius.circular(2)), Paint()..color = p.paper.withValues(alpha: 0.28));
      // tail lights, plate, bumper
      for (final x in [12.0, 70.0]) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 46, 18, 9), const Radius.circular(3.5)), Paint()..color = const Color(0xFFE23B3B));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, 47.5, 9, 2.5), const Radius.circular(1.2)), Paint()..color = Colors.white.withValues(alpha: 0.55));
      }
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 54, 28, 11), const Radius.circular(2.5)), Paint()..color = p.paper);
      c.drawRect(const Rect.fromLTWH(36, 54, 28, 3), Paint()..color = p.accent2);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 68, 80, 6), const Radius.circular(3)), Paint()..color = dark);
      if (theme.outline > 0.4) {
        c.drawRRect(lower, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6 * theme.outline..color = p.ink);
      }
      return r.endRecording();
    });
  }

  // ---------------------------------------------------------------------------------------------- render

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_w == 0 || _sky == null) return;
    final p = theme.palette;
    final steer = _carU * theme.parallax;
    canvas.drawPicture(_sky!);
    canvas.save();
    canvas.translate(-_w * 0.25 - steer * 14, 0);
    canvas.drawPicture(_hillsFar!);
    canvas.restore();
    canvas.save();
    canvas.translate(-_w * 0.25 - steer * 34, 0);
    canvas.drawPicture(_hillsNear!);
    canvas.restore();
    canvas.drawPicture(_road!);
    _drawStripes(canvas, p);
    _drawScenery(canvas);
    if (speedLinesOn) _drawSpeedLines(canvas, p);
    final g = _gate;
    if (g != null) _drawGate(canvas, g, p);
    _drawCar(canvas, p);
    if (!reduceMotion) _drawParticles(canvas);
  }

  void _drawStripes(Canvas canvas, GamePalette p) {
    final n = laneCount;
    final scrollIdx = _scroll.floor();
    final frac = _scroll - scrollIdx;
    const gap = 1.0, len = 0.5;
    final dash = _fill..color = p.paper.withValues(alpha: theme.calm ? 0.6 : 0.88);
    for (var k = 16; k >= 0; k--) {
      final d0 = 1.0 + k * gap - frac * gap - 0.2;
      final d1 = d0 + len;
      if (d1 <= 0.9) continue;
      final t0 = 1 / math.max(d0, 0.8), t1 = 1 / d1;
      final y0 = _yAt(t0), y1 = _yAt(t1);
      // lane dividers
      for (var j = 1; j < n; j++) {
        final u = -1 + 2 * j / n;
        final w0 = 0.014 * _half * t0, w1 = 0.014 * _half * t1;
        _path
          ..reset()
          ..moveTo(_xAt(u, t0) - w0, y0)
          ..lineTo(_xAt(u, t0) + w0, y0)
          ..lineTo(_xAt(u, t1) + w1, y1)
          ..lineTo(_xAt(u, t1) - w1, y1)
          ..close();
        canvas.drawPath(_path, dash);
      }
      // rumble strips on the shoulder: alternate by the stripe's identity
      if (!theme.calm && ((k + scrollIdx) & 1) == 0) {
        _fill.color = p.accent.withValues(alpha: 0.85);
        for (final s in const [-1.0, 1.0]) {
          _path
            ..reset()
            ..moveTo(_xAt(s * 0.985, t0), y0)
            ..lineTo(_xAt(s * 1.075, t0), y0)
            ..lineTo(_xAt(s * 1.075, t1), y1)
            ..lineTo(_xAt(s * 0.985, t1), y1)
            ..close();
          canvas.drawPath(_path, _fill);
        }
        _fill.color = p.paper.withValues(alpha: theme.calm ? 0.6 : 0.88);
      }
    }
  }

  void _drawScenery(Canvas canvas) {
    const gap = 3.2;
    final scrollIdx = (_scroll / gap).floor();
    final frac = _scroll / gap - scrollIdx;
    for (var k = 5; k >= 0; k--) {
      final d = 1.1 + k * gap - frac * gap;
      if (d < 0.75) continue;
      final t = 1 / d;
      final id = k + scrollIdx;
      for (final side in const [-1.0, 1.0]) {
        final h = ((id * 2654435761 + (side > 0 ? 7 : 3)) & 0xffff) / 65535.0;
        final u = side * (1.28 + h * 0.5);
        final x = _xAt(u, t), y = _yAt(t);
        final sc = (math.min(_half * 0.9, _h * 0.3) * t) / 100;
        if (x < -80 || x > _w + 80) continue;
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(sc);
        canvas.translate(-35, -100);
        canvas.drawPicture(h > 0.5 ? _tree! : _tree2!);
        canvas.restore();
      }
    }
  }

  void _drawSpeedLines(Canvas canvas, GamePalette p) {
    final strength = 0.1 + _boost * 0.9;
    final vx = _w / 2, vy = _hy;
    final reach = math.max(_w, _h);
    _line.strokeWidth = 1.4 + _boost * 1.6;
    for (var i = 0; i < _nLines; i++) {
      final ph = (_time * (0.55 + 0.6 * _boost) + _linePh[i]) % 1.0;
      final a = _lineAng[i];
      final dx = math.cos(a), dy = math.sin(a).abs();
      if (dy < 0.12) continue;
      final r0 = reach * (0.1 + ph * ph * 0.95);
      final r1 = r0 + reach * (0.04 + 0.16 * ph);
      _line.color = p.paper.withValues(alpha: (strength * (0.15 + ph * 0.5)).clamp(0.0, 0.85));
      canvas.drawLine(Offset(vx + dx * r0, vy + dy * r0 * 0.9), Offset(vx + dx * r1, vy + dy * r1 * 0.9), _line);
    }
  }

  void _drawGate(Canvas canvas, RunnerGate g, GamePalette p) {
    final t = _gateT;
    final n = g.lanes;
    final fade = _phase == RunnerPhase.pass ? (1 - ((t - 0.97) / 0.13)).clamp(0.0, 1.0) : 1.0;
    if (fade <= 0) return;
    final ground = _yAt(t);
    final unit = _half * t;
    // the target lane glows on the road between the gate and the car
    if (_phase == RunnerPhase.hold || _phase == RunnerPhase.commit || _phase == RunnerPhase.approach) {
      final u0 = -1 + 2 * _carLane / n, u1 = -1 + 2 * (_carLane + 1) / n;
      _path
        ..reset()
        ..moveTo(_xAt(u0, t), ground)
        ..lineTo(_xAt(u1, t), ground)
        ..lineTo(_xAt(u1, _tCar + 0.1), _yAt(_tCar + 0.1))
        ..lineTo(_xAt(u0, _tCar + 0.1), _yAt(_tCar + 0.1))
        ..close();
      _fill.color = p.paper.withValues(alpha: 0.09 * fade);
      canvas.drawPath(_path, _fill);
    }
    final plateH = unit * 0.5;
    final beamY = ground - unit * 0.96;
    // posts and beam
    _line
      ..strokeWidth = math.max(2, unit * 0.05)
      ..color = Color.lerp(p.ink, p.paper, 0.15)!.withValues(alpha: fade);
    for (final s in const [-1.0, 1.0]) {
      canvas.drawLine(Offset(_xAt(s * 1.1, t), ground), Offset(_xAt(s * 1.1, t), beamY), _line);
    }
    canvas.drawLine(Offset(_xAt(-1.1, t), beamY), Offset(_xAt(1.1, t), beamY), _line);
    // a sign above every lane
    final laneW = 2 * unit / n;
    final pw = laneW * 0.88;
    final k = pw / 120;
    for (var i = 0; i < n; i++) {
      final plate = _plates[i];
      if (plate == null) continue;
      final cx = _xAt(_laneU(i, n), t);
      final cy = beamY + plateH * 0.62;
      var state = _signs[i];
      // hang from the beam
      _line
        ..strokeWidth = math.max(1, unit * 0.014)
        ..color = Color.lerp(p.ink, p.paper, 0.3)!.withValues(alpha: fade);
      canvas.drawLine(Offset(cx - pw * 0.3, beamY), Offset(cx - pw * 0.3, cy - plateH * 0.45), _line);
      canvas.drawLine(Offset(cx + pw * 0.3, beamY), Offset(cx + pw * 0.3, cy - plateH * 0.45), _line);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(k);
      plate.paint(canvas, state, fade, theme.calm, _time, theme.outline, p);
      canvas.restore();
      if (state == _Sign.hint && !reduceMotion) {
        // a gentle pulse under the hinted sign
        _fill.color = p.gold.withValues(alpha: (0.12 + 0.1 * math.sin(_time * 5)) * fade);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, ground), width: laneW * 0.8, height: unit * 0.16), _fill);
      }
    }
  }

  void _drawCar(Canvas canvas, GamePalette p) {
    final t = _tCar;
    final n = laneCount;
    final x = _xAt(_carU, t);
    final y = _yAt(t) + _half * 0.06;
    final laneW = 2 * _half * t / n;
    final cw = math.min(laneW * 0.8, _half * 0.5);
    final k = cw / 100;
    // the shadow
    _fill.color = Colors.black.withValues(alpha: 0.28);
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y - cw * 0.03), width: cw * 1.05, height: cw * 0.2), _fill);
    final bob = reduceMotion ? 0.0 : math.sin(_time * 14) * 0.6 * theme.bounce;
    final jolt = _shake > 0 ? math.sin(_shake * 38) * _shake * cw * 0.07 : 0.0;
    canvas.save();
    canvas.translate(x + jolt, y + bob);
    canvas.rotate((_carVel * 0.045).clamp(-0.22, 0.22) + (_shake > 0 ? math.sin(_shake * 30) * _shake * 0.05 : 0));
    canvas.scale(k);
    canvas.translate(-50, -78);
    if (_boost > 0.05 && !reduceMotion) {
      // exhaust glow
      _fill.color = p.gold.withValues(alpha: 0.5 * _boost);
      canvas.drawOval(const Rect.fromLTWH(30, 70, 40, 14), _fill);
    }
    canvas.drawPicture(_carPicture(_mood));
    canvas.restore();
  }

  void _drawParticles(Canvas canvas) {
    final items = _particles.items;
    for (var i = 0; i < items.length; i++) {
      final q = items[i];
      final f = 1 - q.age / q.life;
      _fill.color = q.color.withValues(alpha: f.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(q.x, q.y), q.size * (0.4 + 0.6 * f), _fill);
    }
  }

  /// Frees the cached pictures (the host calls it with the game's removal).
  @override
  void onRemove() {
    _sky?.dispose();
    _hillsFar?.dispose();
    _hillsNear?.dispose();
    _road?.dispose();
    _tree?.dispose();
    _tree2?.dispose();
    for (final c in _car.values) {
      c.dispose();
    }
    _car.clear();
    _sky = _hillsFar = _hillsNear = _road = _tree = _tree2 = null;
    super.onRemove();
  }
}

/// One sign: the plate and its word, laid out once (the Arabic text keeps its marks: a tall line height, no clipping).
class _Plate {
  _Plate(this.label, GamePalette p) {
    final rtl = textIsRtl(label);
    _tp = TextPainter(
      text: TextSpan(text: label, style: appText(34, w: FontWeight.w800, c: p.ink, h: 1.75)),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(maxWidth: 400);
    // the plate is 120 x 70 design units; the word is fitted into 100 x 54
    _fit = math.min(1.0, math.min(100 / math.max(1, _tp.width), 54 / math.max(1, _tp.height)));
  }

  final String label;
  late final TextPainter _tp;
  late final double _fit;
  final Paint _paint = Paint();
  final RRect _rr = RRect.fromRectAndRadius(const Rect.fromLTWH(-60, -35, 120, 70), const Radius.circular(14));

  void paint(Canvas c, _Sign state, double fade, bool calm, double time, double outline, GamePalette p) {
    final fill = switch (state) {
      _Sign.good => const Color(0xFFCDEFD9),
      _Sign.bad => const Color(0xFFF6CFCF),
      _Sign.dim => Color.lerp(p.paper, p.far, 0.5)!,
      _ => p.paper,
    };
    final edge = switch (state) {
      _Sign.good => const Color(0xFF2E9E6B),
      _Sign.bad => const Color(0xFFD64545),
      _Sign.hint => p.gold,
      _Sign.dim => p.far,
      _ => calm ? Color.lerp(p.paper, p.accent, 0.5)! : p.accent,
    };
    // a soft drop shadow, the plate, its edge, a lip of light at the top
    _paint.color = Colors.black.withValues(alpha: 0.2 * fade);
    c.drawRRect(_rr.shift(const Offset(0, 5)), _paint);
    _paint
      ..style = PaintingStyle.fill
      ..color = fill.withValues(alpha: (state == _Sign.dim ? 0.78 : 1) * fade);
    c.drawRRect(_rr, _paint);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = calm ? 2.5 : 3.5 + outline
      ..color = edge.withValues(alpha: fade);
    c.drawRRect(_rr, _paint);
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.35 * fade);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-52, -31, 104, 9), const Radius.circular(5)), _paint);
    c.save();
    c.scale(_fit);
    _tp.paint(c, Offset(-_tp.width / 2, -_tp.height / 2));
    c.restore();
  }
}

/// The widget: the game inside a [FlameHost] with swipe, tap and tilt.
class LaneRunnerView extends StatefulWidget {
  const LaneRunnerView({super.key, required this.game, required this.semanticLabel, this.tilt = false, this.tiltEvents});
  final LaneRunnerGame game;
  final String semanticLabel;

  /// Steer by tilting the phone (setting `tilt`).
  final bool tilt;

  /// The tilt source ([tiltStream] by default); tests pass their own.
  final Stream<({double x, double y})>? tiltEvents;

  @override
  State<LaneRunnerView> createState() => _LaneRunnerViewState();
}

class _LaneRunnerViewState extends State<LaneRunnerView> {
  StreamSubscription<({double x, double y})>? _tilt;
  double _drag = 0;
  int _lastTiltMs = 0;

  @override
  void initState() {
    super.initState();
    if (widget.tilt) {
      _tilt = (widget.tiltEvents ?? tiltStream()).listen((e) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // accelerometer x is positive when the phone leans left; a dead zone and a pause between steps
        if (e.x.abs() > 2.6 && now - _lastTiltMs > 420) {
          _lastTiltMs = now;
          widget.game.steer(e.x > 0 ? -1 : 1);
        }
      });
    }
  }

  @override
  void dispose() {
    _tilt?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => widget.game.tapAt(d.localPosition.dx),
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (d) {
        _drag += d.delta.dx;
        if (_drag.abs() > 36) {
          widget.game.steer(_drag > 0 ? 1 : -1);
          _drag = 0;
        }
      },
      child: FlameHost(
        game: widget.game,
        semanticLabel: widget.semanticLabel,
        onReduceMotion: (v) => widget.game.reduceMotion = v,
      ),
    );
  }
}
