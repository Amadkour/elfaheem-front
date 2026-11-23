// lib/features/games/bases/floating_tokens.dart — the floating-tokens base of Games v4 (T38, CONTRACT §2: balloon_pop,
// word_fishing).
//
//   FloatingTokensGame   a Flame game: a wave of tokens (balloons or pearls) rises into place, bobs and sways, and
//                        is tapped. The template hears `onTap(index)`, decides, and calls `pop(index, good:)`; a right pop
//                        throws the particles of game_fx, a wrong one a quiet ring (nothing red in a calm round).
//                        `release()` lets the rest float away; `onGone` fires when the wave has left the screen.
//                        `TokenMotion.drift` (word fishing, T47): the tokens sit in ROWS, every row a conveyor that moves one
//                        way (rows alternate), a fish (`TokenSkin.fish`) or a pearl pill (`TokenSkin.pearl`) as wide as its
//                        word. `pop` = caught (the fish swims up to the sentence), `mark` = not this one (a wiggle, an amber
//                        ring when calm), `release()` shrinks the rest away. Quran words (`setTokens(quran: true)`) are
//                        laid out once in the Quran role, never tilted or squashed; calm pearls hold still (no sway).
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
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show quranTextStyle;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/flame_host.dart';
import 'package:flutter_education_app/features/games/core/game_fx.dart';

enum TokenSkin { balloon, pearl, fish, train }

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
  // rows (drift motion): the row, the left edge on the row's belt, widths (design units), swim direction, wrong-tap clock
  int row = 0;
  double x0 = 0, ext = 100, bw = 100, dir = 1, markT = 99;
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

  /// Rows layout: the first row starts this many px from the top (a header sits above); null = 26 % of the height.
  double? _topInset;
  void setTopInset(double? v) {
    if (v == _topInset || (v != null && _topInset != null && (v - _topInset!).abs() < 2)) return;
    _topInset = v;
    if (_w > 0 && _tokens.isNotEmpty) _layout();
  }

  bool get _rows => motion == TokenMotion.drift;
  bool _quran = false;
  double _k = 1; // rows: px per design unit
  final List<double> _rowOff = [], _rowLen = [], _rowSpeed = [];
  double _maxExt = 100;

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
  ui.Picture? _bg, _rail;
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
  void setTokens(List<String> labels, {bool quran = false}) {
    _labels = labels;
    _quran = quran;
    _tokens.clear();
    final palette = theme.palette;
    for (var i = 0; i < labels.length; i++) {
      final t = _Token(i, labels[i], i % 5)
        ..phase = i * 1.7
        ..delay = i * 0.13;
      t.tp = TextPainter(
        text: TextSpan(text: labels[i], style: quran ? quranTextStyle(26, color: palette.ink) : appText(26, w: FontWeight.w800, c: palette.ink, h: 1.7)),
        textDirection: textIsRtl(labels[i]) ? TextDirection.rtl : TextDirection.ltr,
        textAlign: TextAlign.center,
        // sacred words are never clipped (no ellipsis): they wrap at a space and the whole word scales to fit
        maxLines: quran ? null : 2,
      )..layout(maxWidth: _rows ? 420 : 360);
      _tokens.add(t);
    }
    _waveOpen = labels.isNotEmpty;
    if (_w > 0) _layout();
  }

  void _layout() {
    final n = _tokens.length;
    if (n == 0) return;
    if (_rows) {
      _layoutRows();
      _buildPics();
      return;
    }
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

  /// Rows (drift): the tokens packed into rows of conveyors, as large as the screen lets them be (down to 0.5).
  void _layoutRows() {
    final fish = skin == TokenSkin.fish;
    _maxExt = 0;
    final px = 26 * (_quran ? 1.3 : 1.0);
    for (final t in _tokens) {
      t.bw = (t.tp.width + 44).clamp(120.0, 300.0);
      t.ext = t.bw + (fish ? 24 : (skin == TokenSkin.train ? 14 : 0));
      final lines = math.max(1, t.tp.computeLineMetrics().length);
      final visH = lines * px * (_quran ? 1.45 : 1.25);
      t.fit = math.min(1.0, math.min((t.bw - 44) / math.max(1, t.tp.width), 58 / visH));
      _maxExt = math.max(_maxExt, t.ext);
    }
    const margin = 14.0;
    final usable = _w - 2 * margin;
    final top = (_topInset ?? _h * 0.26) + 4, bottom = _h - 8;
    var k = _w >= 900 ? 1.3 : 1.0; // a wide screen gets bigger fish
    var rows = <List<_Token>>[];
    while (true) {
      k = math.min(k, usable / _maxExt);
      final gap = 14 * k;
      rows = [];
      var cur = <_Token>[];
      var w = 0.0;
      for (final t in _tokens) {
        final tw = t.ext * k;
        if (cur.isNotEmpty && w + gap + tw > usable) {
          rows.add(cur);
          cur = [];
          w = 0;
        }
        w += (cur.isEmpty ? 0 : gap) + tw;
        cur.add(t);
      }
      if (cur.isNotEmpty) rows.add(cur);
      if (rows.length * 104 * k <= bottom - top || k <= 0.5) break;
      k -= 0.04;
    }
    _k = k;
    _rail?.dispose();
    _rail = null;
    final pitch = math.min(104 * k * 1.12, (bottom - top) / rows.length);
    final y0 = top + ((bottom - top) - pitch * rows.length) / 2 + pitch / 2;
    _rowOff.clear();
    _rowLen.clear();
    _rowSpeed.clear();
    final base = (14 + 8.0 * speed) * (theme.calm ? 0.55 : 1.0);
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final sumW = row.fold<double>(0, (a, t) => a + t.ext * k);
      final s = math.min(40 * k, (usable - sumW) / math.max(1, row.length - 1));
      var left = 0.0;
      for (final t in row) {
        t.row = r;
        t.ay = y0 + r * pitch;
        t.dir = r.isEven ? 1 : -1;
        t.x0 = left;
        left += t.ext * k + s;
        t.dir = r.isEven ? 1 : -1;
      }
      _rowLen.add(math.max(0.0, usable - (sumW + s * (row.length - 1)))); // the room the row swims in
      _rowOff.add(0);
      _rowSpeed.add(base * (0.85 + 0.15 * (r % 3)) * (r.isEven ? 1 : -1));
    }
    for (final t in _tokens) {
      _place(t);
    }
  }

  void _place(_Token t) {
    final ext = t.ext * _k;
    final e = 14.0 + t.x0 + _rowLen[t.row] * (0.5 + 0.5 * math.sin(_rowOff[t.row]));
    t.x = e + ext / 2;
    t.y = t.ay + (reduceMotion ? 0.0 : math.sin(_time * 1.3 + t.phase) * 4 * _k * theme.bounce.clamp(0.3, 1.0));
  }

  bool _updateRows(double dt) {
    var any = false;
    if (!reduceMotion) {
      for (var r = 0; r < _rowOff.length; r++) {
        if (_rowLen[r] > 4) {
          _rowOff[r] += _rowSpeed[r] * dt / _rowLen[r] * math.pi;
          final d = math.cos(_rowOff[r]) * _rowSpeed[r] >= 0 ? 1.0 : -1.0;
          for (final t in _tokens) {
            if (t.row == r) t.dir = d;
          }
        }
      }
    }
    for (final t in _tokens) {
      t.age += dt;
      t.markT += dt;
      switch (t.state) {
        case _TokenState.rising:
          any = true;
          _place(t);
        case _TokenState.popping:
          any = true;
          t.popT += dt;
          _place(t);
          if (t.popT >= (reduceMotion ? 0.01 : 0.5)) t.state = _TokenState.gone;
        case _TokenState.leaving:
          any = true;
          t.popT += dt;
          _place(t);
          if (t.popT >= (reduceMotion ? 0.01 : 0.45)) t.state = _TokenState.gone;
        case _TokenState.gone:
          break;
      }
    }
    return any;
  }

  /// Lets every token still on the screen float away (rows: shrink away); [onGone] fires when they have left.
  void release() {
    for (final t in _tokens) {
      if (t.alive) {
        t.state = _TokenState.leaving;
        t.popT = 0;
      }
    }
  }

  /// A try that was not the right token: it wiggles (a ring in amber when the round is calm, nothing is lost). The
  /// token stays; only [pop] takes it.
  void mark(int i) {
    if (isAlive(i)) _tokens[i].markT = 0;
  }

  /// The centre of token [i] on the screen (tests and the template's hint).
  Offset tokenCenter(int i) => Offset(_tokens[i].x, _tokens[i].y);

  void _tapRows(double x, double y) {
    for (var i = _tokens.length - 1; i >= 0; i--) {
      final t = _tokens[i];
      if (!t.alive || t.age < t.delay + 0.3) continue;
      final hw = t.ext * _k / 2 * 1.04, hh = math.max(28.0, 50 * _k);
      final dx = (x - t.x) / hw, dy = (y - t.y) / hh;
      if (dx * dx + dy * dy <= 1.25) {
        onTap?.call(i);
        return;
      }
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
    if (_rows) {
      _tapRows(x, y);
      return;
    }
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
    if (_rows) any = _updateRows(dt);
    for (final t in (_rows ? const <_Token>[] : _tokens)) {
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
    _rail?.dispose();
    _rail = null;
    if (_tokens.isNotEmpty) _layout();
  }

  /// The sea of word fishing: water from the light top to a deep bottom, rays, bubbles, a sand floor with weed.
  ui.Picture _recordSea() {
    final p = theme.palette;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, _w, _h));
    final top = Color.lerp(p.skyTop, p.skyMid, theme.calm ? 0.35 : 0.55)!, deep = Color.lerp(p.skyTop, p.ink, theme.night ? 0.55 : 0.42)!;
    c.drawRect(Rect.fromLTWH(0, 0, _w, _h), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, _h), [top, Color.lerp(top, deep, 0.55)!, deep], [0, 0.5, 1]));
    final ray = Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, _h * 0.9), [p.paper.withValues(alpha: theme.calm ? 0.1 : 0.17), p.paper.withValues(alpha: 0)]);
    final r = math.Random(23);
    for (var i = 0; i < (theme.calm ? 3 : 5); i++) {
      final x = _w * (0.05 + 0.22 * i + r.nextDouble() * 0.08), w = _w * (0.04 + r.nextDouble() * 0.05);
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + w, 0)
          ..lineTo(x + w * 3.2 - _w * 0.12, _h * 0.9)
          ..lineTo(x - w * 0.6 - _w * 0.12, _h * 0.9)
          ..close(),
        ray,
      );
    }
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6;
    for (var i = 0; i < 16; i++) {
      final rad = 3 + r.nextDouble() * 8;
      final o = Offset(_w * r.nextDouble(), _h * (0.1 + 0.8 * r.nextDouble()));
      c.drawCircle(o, rad, line..color = p.paper.withValues(alpha: 0.32));
      c.drawCircle(o.translate(-rad * 0.3, -rad * 0.3), rad * 0.18, Paint()..color = p.paper.withValues(alpha: 0.5));
    }
    // the floor: a far ridge, the sand, and a little weed
    Path ridge(double base, double amp, double ph) {
      final path = Path()..moveTo(0, _h);
      for (var x = 0.0; x <= _w; x += 8) {
        path.lineTo(x, base - amp * math.sin(x / _w * math.pi * 2 + ph));
      }
      return path..lineTo(_w, _h)..close();
    }

    c.drawPath(ridge(_h * 0.955, _h * 0.012, 0.6), Paint()..color = Color.lerp(deep, p.ink, 0.25)!);
    c.drawPath(ridge(_h * 0.975, _h * 0.008, 2.2), Paint()..color = Color.lerp(p.gold, deep, 0.5)!);
    final weed = Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..color = Color.lerp(p.mid, deep, 0.25)!;
    for (var i = 0; i < 6; i++) {
      final x = _w * (0.06 + 0.17 * i + r.nextDouble() * 0.05), h = _h * (0.03 + r.nextDouble() * 0.03);
      c.drawPath(
        Path()
          ..moveTo(x, _h)
          ..quadraticBezierTo(x - 8, _h - h * 0.6, x + 2, _h - h)
          ..moveTo(x + 8, _h)
          ..quadraticBezierTo(x + 14, _h - h * 0.5, x + 6, _h - h * 0.8),
        weed,
      );
    }
    return rec.endRecording();
  }

  ui.Picture _recordBg() {
    if (_rows && skin != TokenSkin.train) return _recordSea();
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

  /// One picture per (colour, width): a fish facing right (tail on the left) or a pearl pill, centred on its span.
  ui.Picture _rowPic(_Token t) {
    final key = t.color * 1000 + (t.bw / 4).round();
    return _pics.putIfAbsent(key, () {
      final p = theme.palette;
      final base = _fishTone(t.color);
      final bw = t.bw, ext = t.ext;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, Rect.fromLTWH(-ext / 2 - 6, -60, ext + 12, 120));
      final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6 * theme.outline..color = p.ink;
      if (skin == TokenSkin.fish) {
        const cx = 12.0, h = 34.0;
        final bl = cx - bw / 2, br = cx + bw / 2;
        final fin = Color.lerp(base, p.ink, 0.12)!;
        final tail = Path()
          ..moveTo(bl + 16, 0)
          ..quadraticBezierTo(bl - 2, -h * 0.25, -ext / 2, -h * 0.9)
          ..quadraticBezierTo(-ext / 2 + 9, 0, -ext / 2, h * 0.9)
          ..quadraticBezierTo(bl - 2, h * 0.25, bl + 16, 0)
          ..close();
        final dorsal = Path()
          ..moveTo(cx - 20, -h * 0.9)
          ..quadraticBezierTo(cx - 4, -h * 1.62, cx + 26, -h * 0.88)
          ..close();
        final belly = Path()
          ..moveTo(cx - 8, h * 0.85)
          ..quadraticBezierTo(cx + 6, h * 1.5, cx + 28, h * 0.8)
          ..close();
        final body = Path()
          ..moveTo(bl + 10, 0)
          ..cubicTo(bl + 32, -h * 1.1, br - 42, -h * 1.2, br - 4, -h * 0.26)
          ..cubicTo(br + 2, -h * 0.06, br + 2, h * 0.06, br - 4, h * 0.26)
          ..cubicTo(br - 42, h * 1.2, bl + 32, h * 1.1, bl + 10, 0)
          ..close();
        for (final f in [tail, dorsal, belly]) {
          c.drawPath(f, Paint()..color = fin);
          if (theme.outline > 0.4) c.drawPath(f, line);
        }
        c.drawPath(
          body,
          Paint()..shader = ui.Gradient.linear(Offset(cx, -h * 1.1), Offset(cx, h * 1.1), [Color.lerp(base, p.paper, 0.38)!, base, Color.lerp(base, p.ink, 0.22)!], [0, 0.5, 1]),
        );
        // scale-stripes toward the tail, a pale belly
        final stripe = Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..color = p.ink.withValues(alpha: theme.calm ? 0.07 : 0.14);
        for (var i = 0; i < 2; i++) {
          final x = bl + 22 + i * 11.0;
          c.drawPath(Path()..moveTo(x, -h * 0.5)..quadraticBezierTo(x - 7, 0, x, h * 0.5), stripe);
        }
        if (theme.outline > 0.4) c.drawPath(body, line);
        // the plate the word sits on
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx - 6, 0), width: bw - 38, height: 46), const Radius.circular(18)), Paint()..color = p.paper.withValues(alpha: 0.93));
        // the eye
        final eye = Offset(br - 18, -h * 0.34);
        c.drawCircle(eye, 7, Paint()..color = p.paper);
        c.drawCircle(eye.translate(1.6, 0.4), 3.6, Paint()..color = p.ink);
        c.drawCircle(eye.translate(2.6, -1), 1.2, Paint()..color = p.paper);
      } else if (skin == TokenSkin.train) {
        // a wagon on its wheels: the couplers at both ends, a body in the token's colour, the word on a painted plate
        final body = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, -4), width: bw, height: 62), const Radius.circular(12));
        final edge = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6 * theme.outline..color = p.ink;
        final bar = Paint()..color = p.ink.withValues(alpha: 0.7);
        for (final sx in [-1.0, 1.0]) {
          c.drawRect(Rect.fromLTWH(sx * (bw / 2 + 6) - 8, 14, 16, 5), bar);
        }
        c.drawRRect(body.shift(const Offset(0, 3)), Paint()..color = p.ink.withValues(alpha: 0.14));
        c.drawRRect(body, Paint()..shader = ui.Gradient.linear(const Offset(0, -35), const Offset(0, 27), [Color.lerp(base, p.paper, 0.3)!, base, Color.lerp(base, p.ink, 0.2)!], [0, 0.55, 1]));
        // the roof rim and two boards
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-bw / 2 - 3, -38, bw + 6, 8), const Radius.circular(4)), Paint()..color = Color.lerp(base, p.ink, 0.3)!);
        final board = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = p.ink.withValues(alpha: theme.calm ? 0.1 : 0.18);
        c.drawLine(Offset(-bw / 2 + 6, 17), Offset(bw / 2 - 6, 17), board);
        if (theme.outline > 0.4) c.drawRRect(body, edge);
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, -2), width: bw - 30, height: 46), const Radius.circular(10)), Paint()..color = p.paper.withValues(alpha: 0.94));
        // the wheels
        final dx = math.max(24.0, bw / 2 - 30);
        for (final sx in [-dx, dx]) {
          c.drawCircle(Offset(sx, 30), 11, Paint()..color = p.ink.withValues(alpha: 0.85));
          c.drawCircle(Offset(sx, 30), 4.5, Paint()..color = p.gold);
        }
      } else {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bw, height: 70), const Radius.circular(35));
        final soft = Color.lerp(base, p.paper, 0.62)!;
        c.drawRRect(r.shift(const Offset(0, 4)), Paint()..color = p.ink.withValues(alpha: 0.12));
        c.drawRRect(r, Paint()..shader = ui.Gradient.radial(Offset(-bw * 0.22, -22), bw * 0.75, [p.paper, soft, Color.lerp(base, p.paper, 0.3)!], [0, 0.5, 1]));
        c.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Color.lerp(base, p.ink, 0.1)!.withValues(alpha: 0.55));
        c.drawOval(Rect.fromCenter(center: Offset(-bw * 0.3, -22), width: bw * 0.26, height: 11), Paint()..color = p.paper.withValues(alpha: 0.8));
      }
      return rec.endRecording();
    });
  }

  /// The track under every row of wagons: two rails and the sleepers, one picture the width of the screen.
  ui.Picture _railPic() {
    return _rail ??= () {
      final p = theme.palette;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, Rect.fromLTWH(0, -4, _w, 20));
      final sleeper = Paint()..style = PaintingStyle.stroke..strokeWidth = 5 * _k..color = Color.lerp(p.ink, p.gold, 0.35)!.withValues(alpha: 0.7);
      for (var x = 6.0; x < _w; x += 22 * _k) {
        c.drawLine(Offset(x, 1), Offset(x, 10 * _k), sleeper);
      }
      final rail = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.4 * _k..strokeCap = StrokeCap.round..color = p.ink.withValues(alpha: theme.calm ? 0.6 : 0.8);
      c.drawLine(const Offset(0, 0), Offset(_w, 0), rail);
      c.drawLine(Offset(0, 6 * _k), Offset(_w, 6 * _k), rail);
      return rec.endRecording();
    }();
  }

  Color _fishTone(int i) {
    final p = theme.palette;
    final base = [p.accent2, p.accent, p.gold, Color.lerp(p.accent, p.paper, 0.4)!, Color.lerp(p.accent2, p.accent, 0.5)!][i % 5];
    return theme.calm ? Color.lerp(base, p.paper, 0.18)! : base;
  }

  void _renderRows(Canvas canvas) {
    final fish = skin == TokenSkin.fish;
    final calm = theme.calm;
    final topY = (_topInset ?? _h * 0.26) - 30;
    if (skin == TokenSkin.train && _tokens.isNotEmpty) {
      final rail = _railPic();
      var last = -1;
      for (final t in _tokens) {
        if (t.row == last) continue;
        last = t.row;
        canvas.save();
        canvas.translate(0, t.ay + 44 * _k);
        canvas.drawPicture(rail);
        canvas.restore();
      }
    }
    for (final t in _tokens) {
      if (t.state == _TokenState.gone) continue;
      var s = 1.0, cx = t.x, cy = t.y, rot = 0.0;
      switch (t.state) {
        case _TokenState.rising:
          final p = ((t.age - t.delay) / 0.45).clamp(0.0, 1.0);
          if (p <= 0) continue;
          // eased in with a small overshoot (a still scale under Reduce motion)
          final q = p - 1;
          s = reduceMotion ? 1.0 : (calm ? 1 + q * q * q : 1 + 2.70158 * q * q * q + 1.70158 * q * q);
        case _TokenState.popping:
          final f = (t.popT / 0.5).clamp(0.0, 1.0), e = f * f * (3 - 2 * f);
          cx = t.x + (_w / 2 - t.x) * e;
          cy = t.y + (topY - t.y) * e;
          s = 1 - 0.5 * e;
        case _TokenState.leaving:
          s = 1 - (t.popT / 0.45).clamp(0.0, 1.0);
          if (s <= 0.02) continue;
        case _TokenState.gone:
          break;
      }
      if (!calm && !reduceMotion && fish) {
        rot = t.markT < 0.5 ? math.sin(t.markT * 34) * 0.2 * (1 - t.markT / 0.5) : math.sin(_time * 1.4 + t.phase) * 0.035;
      }
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot);
      canvas.scale(_k * s);
      final ext = t.ext;
      if (t.hinted && t.alive) {
        _ring
          ..strokeWidth = 5
          ..color = theme.palette.gold.withValues(alpha: reduceMotion ? 0.85 : 0.55 + 0.4 * math.sin(_time * 5));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: ext + 16, height: 100), const Radius.circular(44)), _ring);
      }
      canvas.save();
      if (fish && t.dir < 0) canvas.scale(-1, 1);
      canvas.drawPicture(_rowPic(t));
      canvas.restore();
      canvas.save();
      canvas.translate(fish ? 8.0 * t.dir : 0, 0);
      canvas.scale(t.fit);
      t.tp.paint(canvas, Offset(-t.tp.width / 2, -t.tp.height / 2));
      canvas.restore();
      if (t.markT < 0.6) {
        final f = reduceMotion ? 0.3 : t.markT / 0.6;
        _ring
          ..strokeWidth = calm ? 5 : 3.5
          ..color = (calm ? theme.palette.gold : theme.palette.ink).withValues(alpha: (calm ? 0.9 : 0.4) * (1 - f));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: ext + 8 + 26 * f, height: 84 + 26 * f), const Radius.circular(46)), _ring);
      }
      canvas.restore();
    }
  }

  // ---------------------------------------------------------------------------------------------- render

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bg = _bg;
    if (bg == null) return;
    canvas.drawPicture(bg);
    final k = _r / 50;
    if (_rows) _renderRows(canvas);
    for (final t in (_rows ? const <_Token>[] : _tokens)) {
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
    _rail?.dispose();
    _rail = null;
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
