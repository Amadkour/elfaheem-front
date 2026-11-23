// lib/features/games/bases/floating_tokens.dart — the floating-tokens base of Games v4 (T38, CONTRACT §2: balloon_pop,
// word_fishing).
//
//   FloatingTokensGame   a Flame game: a wave of tokens (balloons or pearls) rises into place, bobs and sways, and
//                        is tapped. The template hears `onTap(index)`, decides, and calls `pop(index, good:)`; a right pop
//                        throws the particles of game_fx, a wrong one a quiet ring (nothing red in a calm round).
//                        `release()` lets the rest float away; `onGone` fires when the wave has left the screen.
//                        `TokenMotion.drift` swims the tokens sideways instead of hovering (word fishing).
//   FloatingTokensView   the widget: FlameHost + tap
//
// Cached: the balloon / pearl pictures (one per colour, recorded once per size), the word of every token as a
// TextPainter laid out once per wave. A frame allocates nothing of its own (the particles of game_fx aside).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/games/bases/lane_runner.dart' show textIsRtl;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/flame_host.dart';
import 'package:flutter_education_app/features/games/core/game_fx.dart';

enum TokenSkin { balloon, pearl }

enum TokenMotion { hover, drift }

enum _TokenState { rising, popping, leaving, gone }

class _Token {
  _Token(this.index, this.label, this.color);
  final int index;
  final String label;
  final int color;
  late TextPainter tp;
  double fit = 1;
  double ax = 0, ay = 0; // anchor
  double x = 0, y = 0;
  double delay = 0, age = 0, phase = 0, vx = 0;
  double popT = 0;
  bool good = true;
  bool hinted = false;
  _TokenState state = _TokenState.rising;
  bool get alive => state == _TokenState.rising;
}

class FloatingTokensGame extends FlameGame {
  FloatingTokensGame({required this.theme, this.skin = TokenSkin.balloon, this.motion = TokenMotion.hover, this.speed = 3});

  final AgeTheme theme;
  final TokenSkin skin;
  final TokenMotion motion;

  /// 1..5: how fast the tokens rise and drift.
  final int speed;
  bool reduceMotion = false;

  /// The token at screen position was tapped (its index in the wave).
  ValueChanged<int>? onTap;

  /// Every token of the wave has popped or floated off.
  VoidCallback? onGone;

  final List<_Token> _tokens = [];
  bool _waveOpen = false;
  double _time = 0, _w = 0, _h = 0, _r = 40;
  List<String> _labels = const [];
  final GameParticles _particles = GameParticles();
  final Map<int, ui.Picture> _pics = {};
  ui.Picture? _bg;
  final Paint _fill = Paint();
  final Paint _ring = Paint()..style = PaintingStyle.stroke;

  int get liveCount => _tokens.where((t) => t.alive).length;
  int get tokenCount => _tokens.length;
  bool get settled => _tokens.isNotEmpty && _tokens.every((t) => !t.alive || t.age >= t.delay + _riseTime);
  double get _riseTime => math.max(0.5, 1.7 - 0.2 * speed);
  bool isAlive(int i) => i >= 0 && i < _tokens.length && _tokens[i].alive;

  @override
  Color backgroundColor() => const Color(0x00000000);

  // ---------------------------------------------------------------------------------------------- wave

  /// A new wave of [labels]: they rise from below the screen into a loose grid (or swim in, for drift).
  void setTokens(List<String> labels) {
    _labels = labels;
    _tokens.clear();
    final palette = theme.palette;
    for (var i = 0; i < labels.length; i++) {
      final t = _Token(i, labels[i], i % 5)
        ..phase = i * 1.7
        ..delay = i * 0.13;
      t.tp = TextPainter(
        text: TextSpan(text: labels[i], style: appText(26, w: FontWeight.w800, c: palette.ink, h: 1.7)),
        textDirection: textIsRtl(labels[i]) ? TextDirection.rtl : TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: 360);
      _tokens.add(t);
    }
    _waveOpen = labels.isNotEmpty;
    if (_w > 0) _layout();
  }

  void _layout() {
    final n = _tokens.length;
    if (n == 0) return;
    final cols = n <= 3 ? n : (n <= 6 ? 3 : 4);
    final rows = (n / cols).ceil();
    final top = _h * 0.26, bottom = _h * 0.9;
    final usable = math.min(_w, _h * 1.25), left = (_w - usable) / 2;
    final cellW = usable / cols, cellH = (bottom - top) / rows;
    _r = math.max(22.0, math.min(math.min(cellW * 0.4, cellH * 0.36), 62.0));
    final rng = math.Random(_labels.join('|').hashCode);
    for (final t in _tokens) {
      final c = t.index % cols, r = t.index ~/ cols;
      // the last row is centred when it is short
      final inRow = r == rows - 1 ? n - r * cols : cols;
      final off = (cols - inRow) * cellW / 2;
      t.ax = left + off + (c + 0.5) * cellW + (rng.nextDouble() - 0.5) * cellW * 0.16;
      t.ay = top + (r + 0.5) * cellH + (rng.nextDouble() - 0.5) * cellH * 0.12;
      t.x = t.ax;
      t.y = _h + _r * 2.4;
      t.fit = math.min(1.0, math.min(_r * 1.5 / math.max(1, t.tp.width), _r * 1.15 / math.max(1, t.tp.height)));
      if (motion == TokenMotion.drift) {
        t.vx = (t.index.isEven ? 1 : -1) * (16 + 9.0 * speed) * (0.7 + 0.3 * ((t.index * 37) % 7) / 7);
      }
    }
    _buildPics();
  }

  /// Lets every token still on the screen float away; [onGone] fires when they have left.
  void release() {
    for (final t in _tokens) {
      if (t.alive) t.state = _TokenState.leaving;
    }
  }

  /// A hint: the token pulses.
  void hintToken(int i) {
    if (i >= 0 && i < _tokens.length) _tokens[i].hinted = true;
  }

  /// The template's verdict on a tap: the token pops. [good] throws particles; a wrong pop is a ring (none when calm).
  void pop(int i, {required bool good}) {
    if (!isAlive(i)) return;
    final t = _tokens[i];
    t.state = _TokenState.popping;
    t.popT = 0;
    t.good = good;
    if (good && !reduceMotion) {
      final p = theme.palette;
      _particles.emit(GameFxKind.correct, Offset(t.x, t.y), Size(_w, _h), [p.gold, p.accent, p.accent2, p.paper], calm: theme.calm, seed: i * 7919 + _tokens.length);
    }
  }

  /// A tap at screen ([x], [y]): the top-most live token under it is reported.
  void tapAt(double x, double y) {
    for (var i = _tokens.length - 1; i >= 0; i--) {
      final t = _tokens[i];
      if (!t.alive || t.age < t.delay + 0.2) continue;
      final dx = (x - t.x) / (_r * 1.15), dy = (y - t.y) / (_r * 1.3);
      if (dx * dx + dy * dy <= 1) {
        onTap?.call(i);
        return;
      }
    }
  }

  // ---------------------------------------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    if (_w == 0) return;
    if (dt > 0.1) dt = 0.1;
    _time += dt;
    var any = false;
    for (final t in _tokens) {
      t.age += dt;
      switch (t.state) {
        case _TokenState.rising:
          any = true;
          final p = ((t.age - t.delay) / _riseTime).clamp(0.0, 1.0);
          final e = 1 - math.pow(1 - p, 3).toDouble();
          final startY = _h + _r * 2.4;
          final bob = reduceMotion || p < 1 ? 0.0 : math.sin(_time * 1.3 + t.phase) * _r * 0.12 * theme.bounce.clamp(0.4, 1.0);
          t.y = startY + (t.ay - startY) * e + bob;
          if (motion == TokenMotion.drift && p >= 1) {
            t.ax += t.vx * dt;
            final lim = _w + _r * 2;
            if (t.ax > lim) t.ax = -_r * 2;
            if (t.ax < -_r * 2) t.ax = lim;
          }
          t.x = t.ax + (reduceMotion || p < 1 ? 0.0 : math.sin(_time * 0.9 + t.phase) * _r * 0.1);
        case _TokenState.popping:
          any = true;
          t.popT += dt;
          if (t.popT >= (reduceMotion ? 0.01 : 0.22)) t.state = _TokenState.gone;
        case _TokenState.leaving:
          any = true;
          t.y -= dt * (160 + 70 * speed);
          t.x += math.sin(_time * 2 + t.phase) * dt * 12;
          if (t.y < -_r * 3) t.state = _TokenState.gone;
        case _TokenState.gone:
          break;
      }
    }
    if (!reduceMotion) _particles.step(dt);
    if (_waveOpen && !any && _tokens.isNotEmpty) {
      _waveOpen = false;
      onGone?.call();
    }
  }

  // ---------------------------------------------------------------------------------------------- pictures

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0 || (size.x == _w && size.y == _h)) return;
    _w = size.x;
    _h = size.y;
    _bg?.dispose();
    _bg = _recordBg();
    if (_tokens.isNotEmpty) _layout();
  }

  ui.Picture _recordBg() {
    final p = theme.palette;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, _w, _h));
    c.drawRect(Rect.fromLTWH(0, 0, _w, _h), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, _h), [p.skyTop, p.skyMid, p.skyBottom], [0, 0.55, 1]));
    final sun = Offset(_w * 0.78, _h * 0.2);
    c.drawCircle(sun, _h * 0.4, Paint()..shader = ui.Gradient.radial(sun, _h * 0.4, [p.glow.withValues(alpha: theme.calm ? 0.4 : 0.65), p.glow.withValues(alpha: 0)]));
    final cloud = Paint()..color = p.cloud.withValues(alpha: theme.night ? 0.18 : 0.7);
    final r = math.Random(11);
    for (var i = 0; i < 6; i++) {
      final x = _w * (0.05 + 0.17 * i + r.nextDouble() * 0.06), y = _h * (0.12 + r.nextDouble() * 0.6);
      final s = _h * (0.03 + r.nextDouble() * 0.03);
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: s * 4.6, height: s * 1.5), cloud);
      c.drawOval(Rect.fromCenter(center: Offset(x + s, y - s * 0.55), width: s * 2.6, height: s * 1.5), cloud);
    }
    // soft hills at the bottom
    for (final (i, col) in [p.far, p.mid, p.near].indexed) {
      final path = Path()..moveTo(0, _h);
      final base = _h * (0.9 - 0.04 * (2 - i));
      for (var x = 0.0; x <= _w; x += 8) {
        path.lineTo(x, base - _h * 0.03 * math.sin(x / _w * math.pi * (2 + i) + i * 1.3));
      }
      path.lineTo(_w, _h);
      path.close();
      c.drawPath(path, Paint()..color = col);
    }
    return rec.endRecording();
  }

  void _buildPics() {
    for (final v in _pics.values) {
      v.dispose();
    }
    _pics.clear();
  }

  Color _tone(int i) {
    final p = theme.palette;
    final base = [p.accent, p.accent2, p.gold, Color.lerp(p.accent, p.skyTop, 0.5)!, Color.lerp(p.accent2, p.accent, 0.5)!][i % 5];
    return theme.calm ? Color.lerp(base, p.paper, 0.2)! : base;
  }

  ui.Picture _picFor(int colorIdx) {
    return _pics.putIfAbsent(colorIdx, () {
      final p = theme.palette;
      final base = _tone(colorIdx);
      final rec = ui.PictureRecorder();
      // design units: the token is 100 wide, centred at (0,0); balloon is 120 tall + knot + string
      final c = Canvas(rec, const Rect.fromLTWH(-60, -70, 120, 260));
      if (skin == TokenSkin.balloon) {
        final string = Path()
          ..moveTo(0, 66)
          ..quadraticBezierTo(14, 92, -6, 116)
          ..quadraticBezierTo(-18, 140, 4, 170);
        c.drawPath(string, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = p.ink.withValues(alpha: 0.45));
        final body = Path()
          ..moveTo(0, 66)
          ..cubicTo(-62, 36, -54, -64, 0, -64)
          ..cubicTo(54, -64, 62, 36, 0, 66)
          ..close();
        c.drawPath(body, Paint()..shader = ui.Gradient.radial(const Offset(-18, -26), 96, [Color.lerp(base, Colors.white, 0.5)!, base, Color.lerp(base, p.ink, 0.28)!], [0, 0.5, 1]));
        // a knot and a shine
        c.drawPath(Path()..moveTo(0, 62)..lineTo(-7, 76)..lineTo(7, 76)..close(), Paint()..color = Color.lerp(base, p.ink, 0.3)!);
        c.drawOval(Rect.fromCenter(center: const Offset(-28, -34), width: 18, height: 30), Paint()..color = Colors.white.withValues(alpha: 0.38));
        if (theme.outline > 0.4) c.drawPath(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4 * theme.outline..color = p.ink);
        // the paper plate the word sits on
        c.drawOval(Rect.fromCenter(center: const Offset(0, -2), width: 80, height: 54), Paint()..color = p.paper.withValues(alpha: 0.9));
      } else {
        c.drawCircle(Offset.zero, 52, Paint()..shader = ui.Gradient.radial(const Offset(-16, -18), 80, [Colors.white.withValues(alpha: 0.95), Color.lerp(base, p.paper, 0.6)!, base.withValues(alpha: 0.85)], [0, 0.55, 1]));
        c.drawCircle(Offset.zero, 52, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Color.lerp(base, p.ink, 0.2)!.withValues(alpha: 0.6));
        c.drawCircle(const Offset(-18, -20), 8, Paint()..color = Colors.white.withValues(alpha: 0.7));
      }
      return rec.endRecording();
    });
  }

  // ---------------------------------------------------------------------------------------------- render

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bg = _bg;
    if (bg == null) return;
    canvas.drawPicture(bg);
    final k = _r / 50;
    for (final t in _tokens) {
      if (t.state == _TokenState.gone) continue;
      var scale = k, alpha = 1.0;
      if (t.state == _TokenState.popping) {
        final f = (t.popT / 0.22).clamp(0.0, 1.0);
        scale = k * (1 + 0.35 * f);
        alpha = 1 - f;
      }
      canvas.save();
      canvas.translate(t.x, t.y);
      final sway = reduceMotion ? 0.0 : math.sin(_time * 1.1 + t.phase) * 0.05;
      canvas.rotate(sway);
      canvas.scale(scale);
      if (alpha < 1) canvas.saveLayer(const Rect.fromLTWH(-70, -80, 140, 280), _fill..color = Color.fromRGBO(255, 255, 255, alpha));
      if (t.hinted && t.alive) {
        _ring
          ..strokeWidth = 5
          ..color = theme.palette.gold.withValues(alpha: reduceMotion ? 0.8 : 0.5 + 0.4 * math.sin(_time * 5));
        canvas.drawCircle(Offset.zero, 62, _ring);
      }
      canvas.drawPicture(_picFor(t.color));
      canvas.save();
      canvas.scale(t.fit * (skin == TokenSkin.balloon ? 0.95 : 1.1));
      t.tp.paint(canvas, Offset(-t.tp.width / 2, -t.tp.height / 2 - (skin == TokenSkin.balloon ? 2 : 0)));
      canvas.restore();
      if (alpha < 1) canvas.restore();
      canvas.restore();
      if (t.state == _TokenState.popping && !t.good && !theme.calm && !reduceMotion) {
        // a quiet ring that widens and fades
        final f = (t.popT / 0.22).clamp(0.0, 1.0);
        _ring
          ..strokeWidth = 3
          ..color = theme.palette.ink.withValues(alpha: 0.35 * (1 - f));
        canvas.drawCircle(Offset(t.x, t.y), _r * (1 + f), _ring);
      }
    }
    if (!reduceMotion) {
      final items = _particles.items;
      for (var i = 0; i < items.length; i++) {
        final q = items[i];
        final f = (1 - q.age / q.life).clamp(0.0, 1.0);
        _fill.color = q.color.withValues(alpha: f);
        canvas.drawCircle(Offset(q.x, q.y), q.size * (0.4 + 0.6 * f), _fill);
      }
    }
  }

  @override
  void onRemove() {
    _bg?.dispose();
    _bg = null;
    for (final v in _pics.values) {
      v.dispose();
    }
    _pics.clear();
    super.onRemove();
  }
}

class FloatingTokensView extends StatelessWidget {
  const FloatingTokensView({super.key, required this.game, required this.semanticLabel});
  final FloatingTokensGame game;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => game.tapAt(d.localPosition.dx, d.localPosition.dy),
      child: FlameHost(game: game, semanticLabel: semanticLabel, onReduceMotion: (v) => game.reduceMotion = v),
    );
  }
}
