// lib/features/games/templates/constellation/constellation_game.dart — the Flame night sky of Constellation (T62).
//
// One scene: a cached night (gradient, two nebulae, hills, a thousand-year-old dust of tiny stars, one Picture), a few
// twinkling stars, the set's stars with a glow (one shared radial shader, scaled), a label plate under each (laid out once
// with a TextPainter; the Quran role for sacred text), golden threads that grow from star to star, a comet trail under the
// finger, and the reveal: the finished set's drawing is drawn in gold, glows, then flies into "my sky" at the bottom.
//
// Input (raw pointer, one finger): drag from star to star, or tap them one by one. A star is reached when the finger lifts
// on it or rests on it for 140 ms, so a finger passing over a wrong star on its way never costs a try.
//
// 60 fps: every Paint, Path, Shader and TextPainter is made when the round is laid out; a frame allocates nothing but
// short-lived Offsets. At most 24 sparks. Reduce motion: no twinkle, trail, sparks or shooting star; the reveal is short.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show quranTextStyle, textDirectionOf;
import 'package:flutter_education_app/features/games/core/age_theme.dart';

import 'constellation_art.dart';
import 'constellation_round.dart';

class _Thread {
  _Thread(this.a, this.b, this.t);
  final int a, b;
  double t;
}

class _Label {
  _Label(this.plain, this.lit, this.scale, this.chip);
  final TextPainter plain, lit;
  final double scale;

  /// The plate, centred on (0, 0) of the label's own space.
  final RRect chip;
}

class ConstellationGame extends FlameGame {
  ConstellationGame({required this.theme, this.skyBase = 0}) : night = NightSky.of(theme);

  final AgeTheme theme;
  final NightSky night;

  /// Drawings the learner already has in their sky before this round (the caption shows the total).
  final int skyBase;
  bool reduceMotion = false;

  /// False while the session is paused or over: the sky ignores the finger.
  bool Function()? canPlay;

  /// A try was made (right or wrong).
  void Function(StarTry result, {required bool setDone})? onTry;

  /// The reveal ended and the drawing joined the sky.
  VoidCallback? onRevealDone;

  ConstellationRound? round;
  int _shape = 0;

  // ---- geometry
  double _w = 0, _h = 0, _top = 120, _bottom = 60;
  double _r = 16;
  List<Offset> _pos = const [];
  List<_Label?> _labels = const [];
  List<double> _lit = const [], _shimmer = const [], _appear = const [];
  final List<_Thread> _threads = [];

  // ---- paints, built once
  final Paint _p = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
  final Paint _halo = Paint(), _haloGold = Paint();
  final Paint _plate = Paint();
  ui.Picture? _bg;
  final List<ui.Picture> _glyphs = [];
  final List<int> _skyShapes = [];
  TextPainter? _caption, _progress;
  Path? _revealFill;

  // ---- ambient
  double _time = 0;
  final List<double> _twX = [], _twY = [], _twPhase = [], _twSize = [];
  double _shootAt = 5, _shootT = -1, _shootX = 0, _shootY = 0;

  // ---- input
  Offset? _finger;
  int _anchor = -1, _dwellStar = -1, _hintStar = -1;
  double _dwellT = 0, _hintT = 0;
  bool _dwellFired = false, _moved = false;
  final List<double> _trailX = List.filled(14, 0), _trailY = List.filled(14, 0);
  int _trailN = 0;
  Offset? _downAt;

  // ---- sparks (at most 24)
  static const int _maxSparks = 24;
  final List<double> _sx = List.filled(_maxSparks, 0), _sy = List.filled(_maxSparks, 0);
  final List<double> _svx = List.filled(_maxSparks, 0), _svy = List.filled(_maxSparks, 0), _sl = List.filled(_maxSparks, 0);

  // ---- reveal
  double _revealT = -1;
  double get _revealLen => reduceMotion ? 0.7 : (theme.age == GameAge.kids ? 3.0 : 2.6);

  bool get revealing => _revealT >= 0;
  int get skyCount => skyBase + _skyShapes.length;
  int get glyphCount => _skyShapes.length;
  Offset starCenter(int i) => _pos[i];
  int get starCount => _pos.length;
  double get starRadius => _r;
  bool starLit(int i) => i < _lit.length && _lit[i] > 0.5;

  @override
  Color backgroundColor() => const Color(0x00000000);

  // ------------------------------------------------------------------------------------------------ round

  /// A new set: its stars, laid out inside [top]..[bottom] (the header and the strip sit outside).
  void setRound(ConstellationRound r, {required double top, required double bottom, int shape = 0}) {
    round = r;
    _shape = shape;
    _top = top;
    _bottom = bottom;
    _anchor = -1;
    _hintStar = -1;
    _finger = null;
    _revealT = -1;
    _threads.clear();
    final n = r.stars.length;
    _lit = [for (var i = 0; i < n; i++) r.isLinked(i) ? 1.0 : 0.0];
    _shimmer = List.filled(n, 0.0);
    _appear = [for (var i = 0; i < n; i++) reduceMotion ? 1.0 : -0.1 * i];
    for (final (a, b) in r.threads) {
      _threads.add(_Thread(a, b, 1));
    }
    if (_w > 0) _layout();
  }

  /// The free area between the header and the strip changed (rotation, a taller header): lay the stars out again.
  void setField({required double top, required double bottom}) {
    if ((top - _top).abs() < 1 && (bottom - _bottom).abs() < 1) return;
    _top = top;
    _bottom = bottom;
    if (_w > 0 && round != null) _layout();
  }

  void setProgress(int done, int total) {
    _progress = TextPainter(
      text: TextSpan(text: '$done / $total', style: appText(14, w: FontWeight.w700, c: night.text.withValues(alpha: 0.8))),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Pulses the star the learner should reach next (a hint).
  void hint() {
    final r = round;
    if (r == null) return;
    _hintStar = r.hintStar();
    _hintT = 2.4;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0 || (size.x == _w && size.y == _h)) return;
    _w = size.x;
    _h = size.y;
    _bg?.dispose();
    _bg = _recordBg();
    _twX.clear();
    _twY.clear();
    _twPhase.clear();
    _twSize.clear();
    final rnd = math.Random(11);
    final count = theme.age == GameAge.adult || theme.calm ? 22 : 40;
    for (var i = 0; i < count; i++) {
      _twX.add(rnd.nextDouble() * _w);
      _twY.add(rnd.nextDouble() * _h * 0.85);
      _twPhase.add(rnd.nextDouble() * 6.28);
      _twSize.add(0.8 + rnd.nextDouble() * 1.3);
    }
    _caption = TextPainter(
      text: TextSpan(text: t('سمائي', 'My sky'), style: appText(13, w: FontWeight.w700, c: night.text.withValues(alpha: 0.75))),
      textDirection: TextDirection.ltr,
    )..layout();
    _haloGold.shader = ui.Gradient.radial(Offset.zero, 1, [night.gold.withValues(alpha: 0.9), night.gold.withValues(alpha: 0)]);
    _halo.shader = ui.Gradient.radial(Offset.zero, 1, [night.star.withValues(alpha: 0.7), night.star.withValues(alpha: 0)]);
    if (round != null) _layout();
  }

  // ------------------------------------------------------------------------------------------------ layout

  void _layout() {
    final r = round!;
    final n = r.stars.length;
    final padX = 12.0;
    final f = Rect.fromLTRB(padX, _top, _w - padX, math.max(_top + 80, _h - _bottom));
    final kids = theme.age == GameAge.kids && !theme.calm;
    final rnd = math.Random(r.item.n * 7919 + n * 31 + 5);
    final pos = List<Offset>.filled(n, Offset.zero);
    final labels = List<_Label?>.filled(n, null);
    _r = 40;
    final big = _w >= 720;
    // readable at arm's length: Quran / Hadith 24 (28 on a wide screen), never under 20 after scaling; other words 19 / 21,
    // never under 17 (the polish bar)
    final fs = r.quran ? (big ? 28.0 : 24.0) : (big ? 21.0 : 19.0) * (kids ? 1.06 : 1.0);
    final floor = r.quran ? 20.0 : 17.0;

    void place(List<int> ids, Rect area) {
      final k = ids.length;
      if (k == 0) return;
      var cols = math.max(1, math.min(k, math.sqrt(k * area.width / area.height).round()));
      var rows = (k / cols).ceil();
      while (rows > 1 && (rows - 1) * cols >= k) {
        rows--;
      }
      final cw = area.width / cols, ch = area.height / rows;
      final cells = [for (var c = 0; c < cols * rows; c++) c]..shuffle(rnd);
      final base = (math.min(cw, ch) * 0.17).clamp(10.0, big ? 26.0 : 22.0) * (kids ? 1.25 : (theme.age == GameAge.adult ? 0.88 : 1.0));
      _r = math.min(_r, base);
      for (var j = 0; j < k; j++) {
        final id = ids[j];
        final cell = cells[j];
        final cx = area.left + (cell % cols + 0.5) * cw, top = area.top + (cell ~/ cols) * ch;
        final star = r.stars[id];
        final lab = _makeLabel(star.label, r.quran, fs, floor, cw - 10, math.max(18.0, ch - base * 2.6));
        labels[id] = lab;
        final labelH = lab.chip.height * lab.scale;
        final content = base * 2.5 + labelH;
        final slack = math.max(0.0, ch - content);
        final y0 = top + slack / 2 + (rnd.nextDouble() - 0.5) * slack * 0.7;
        final x = cx + (rnd.nextDouble() - 0.5) * math.max(0.0, cw - lab.chip.width * lab.scale - 6).clamp(0.0, cw * 0.3);
        pos[id] = Offset(x, y0 + base * 1.2);
      }
    }

    if (r.isPair) {
      final a = [for (var i = 0; i < n; i++) if (r.stars[i].side == StarSide.a) i];
      final b = [for (var i = 0; i < n; i++) if (r.stars[i].side == StarSide.b) i];
      if (f.width >= f.height * 1.15) {
        final mid = f.center.dx;
        place(a, Rect.fromLTRB(f.left, f.top, mid - 6, f.bottom));
        place(b, Rect.fromLTRB(mid + 6, f.top, f.right, f.bottom));
      } else {
        final mid = f.center.dy;
        place(a, Rect.fromLTRB(f.left, f.top, f.right, mid - 4));
        place(b, Rect.fromLTRB(f.left, mid + 4, f.right, f.bottom));
      }
    } else {
      place([for (var i = 0; i < n; i++) i], f);
    }
    for (final old in _labels) {
      old?.plain.dispose();
      old?.lit.dispose();
    }
    _pos = pos;
    _labels = labels;
  }

  /// A label laid out once: it wraps only between words (the line is never narrower than its longest word, so a word is
  /// never split), and the whole plate scales down to fit its cell, never under [floor] px of text. No ellipsis.
  _Label _makeLabel(String text, bool quran, double size, double floor, double maxW, double maxH) {
    TextStyle style(Color c) => quran ? quranTextStyle(size, color: c) : appText(size, w: FontWeight.w700, c: c, h: 1.3);
    final dir = textDirectionOf(text, AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
    TextPainter make(Color c, double w) =>
        TextPainter(text: TextSpan(text: text, style: style(c)), textDirection: dir, textAlign: TextAlign.center)..layout(maxWidth: w);
    final minScale = math.min(1.0, floor / size);
    const padX = 14.0;
    var word = 0.0;
    final probe = TextPainter(textDirection: dir);
    for (final w in text.split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      probe
        ..text = TextSpan(text: w, style: style(night.text))
        ..layout();
      word = math.max(word, probe.width);
    }
    probe.dispose();
    // the widest the text may run before it is scaled into the cell, and never narrower than its longest word
    final lineW = math.max(word + 1, maxW / minScale - padX * 2);
    var tp = make(night.text, lineW);
    var widest = 0.0;
    for (final m in tp.computeLineMetrics()) {
      widest = math.max(widest, m.width);
    }
    final plateW = widest + padX * 2, plateH = quran ? tp.height * 0.86 + 6 : tp.height + 10;
    final scale = math.min(1.0, math.min(maxW / plateW, maxH / plateH)).clamp(minScale, 1.0);
    final lit = make(night.textLit, lineW);
    return _Label(tp, lit, scale, RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: plateW, height: plateH), Radius.circular(math.min(plateH / 2, 18))));
  }

  // ------------------------------------------------------------------------------------------------ input

  int _hit(Offset p) {
    final r = round;
    if (r == null) return -1;
    var best = -1;
    var bestD = double.infinity;
    final hitR = math.max(28.0, _r * 1.7);
    for (var i = 0; i < _pos.length; i++) {
      var d = (p - _pos[i]).distance;
      final lab = _labels[i];
      if (lab != null) {
        final c = _labelCenter(i);
        if (lab.chip.shift(c).inflate(4).contains(p)) d = math.min(d, hitR * 0.9);
      }
      if (d <= hitR && d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  Offset _labelCenter(int i) {
    final lab = _labels[i]!;
    return Offset(_pos[i].dx, _pos[i].dy + _r * 1.25 + lab.chip.height * lab.scale / 2 + 2);
  }

  bool get _can => round != null && !revealing && (canPlay?.call() ?? true);

  void pointerDown(Offset p) {
    if (revealing) {
      _skipReveal();
      return;
    }
    if (!_can) return;
    _finger = p;
    _downAt = p;
    _moved = false;
    _trailN = 0;
    _pushTrail(p);
    final h = _hit(p);
    _dwellStar = h;
    _dwellT = 0;
    _dwellFired = false;
    final r = round!;
    if (r.isPair && h >= 0 && !r.isLinked(h) && (_anchor < 0 || r.stars[_anchor].side == r.stars[h].side)) _anchor = h;
  }

  void pointerMove(Offset p) {
    if (_finger == null) return;
    _finger = p;
    if (!_moved && _downAt != null && (p - _downAt!).distance > 8) _moved = true;
    _pushTrail(p);
  }

  void pointerUp(Offset p) {
    if (_finger == null) return;
    _finger = null;
    if (!_can) return;
    final h = _hit(p);
    if (h >= 0 && !(_dwellFired && h == _dwellStar)) _commit(h);
    if (h < 0 && _moved) _anchor = -1;
  }

  void pointerCancel() {
    _finger = null;
  }

  void _pushTrail(Offset p) {
    if (reduceMotion) return;
    if (_trailN == _trailX.length) {
      for (var i = 1; i < _trailN; i++) {
        _trailX[i - 1] = _trailX[i];
        _trailY[i - 1] = _trailY[i];
      }
      _trailN--;
    }
    _trailX[_trailN] = p.dx;
    _trailY[_trailN] = p.dy;
    _trailN++;
  }

  /// The learner reached star [s].
  void _commit(int s) {
    final r = round!;
    if (r.isLinked(s)) return;
    if (!r.isPair) {
      final from = r.tail;
      _try(r.trySequence(s), s, from);
      return;
    }
    if (_anchor < 0 || r.stars[_anchor].side == r.stars[s].side) {
      _anchor = s;
      return;
    }
    final a = _anchor;
    _anchor = -1;
    _try(r.tryPair(a, s), s, a);
  }

  void _try(StarTry? res, int star, int from) {
    final r = round!;
    if (res == null) return;
    if (res.right) {
      if (from >= 0) {
        _threads.add(_Thread(from, star, reduceMotion ? 1 : 0));
      } else {
        // the first star of a chain has no thread yet: it just lights
      }
      _lit[star] = math.max(_lit[star], reduceMotion ? 1.0 : 0.01);
      if (r.isPair && from >= 0) _lit[from] = math.max(_lit[from], reduceMotion ? 1.0 : 0.01);
      _sparks(star);
      if (_hintStar == star) _hintStar = -1;
    } else {
      _shimmer[star] = 0.9;
      if (r.isPair && from >= 0) _shimmer[from] = 0.9;
    }
    final done = r.complete;
    onTry?.call(res, setDone: done);
    if (done) _startReveal();
  }

  // ------------------------------------------------------------------------------------------------ sparks and reveal

  void _sparks(int star) {
    if (reduceMotion || theme.calm || theme.age == GameAge.adult) return;
    final c = _pos[star];
    final rnd = math.Random(star * 17 + _time.floor());
    final k = theme.age == GameAge.kids ? 12 : 8;
    var made = 0;
    for (var i = 0; i < _maxSparks && made < k; i++) {
      if (_sl[i] > 0) continue;
      final a = rnd.nextDouble() * 6.283, v = 30 + rnd.nextDouble() * 70;
      _sx[i] = c.dx;
      _sy[i] = c.dy;
      _svx[i] = math.cos(a) * v;
      _svy[i] = math.sin(a) * v;
      _sl[i] = 0.7 + rnd.nextDouble() * 0.4;
      made++;
    }
  }

  void _startReveal() {
    _revealT = 0;
    _anchor = -1;
    final cx = _w / 2, cy = (_top + (_h - _bottom)) / 2;
    final rad = math.min(_w * 0.36, (_h - _top - _bottom) * 0.36);
    _revealFill = shapeFor(_shape).fillPath(cx, cy, rad);
    if (!reduceMotion && !theme.calm) {
      final rnd = math.Random(_shape + 3);
      final k = theme.age == GameAge.adult ? 8 : _maxSparks;
      for (var i = 0; i < k; i++) {
        final a = rnd.nextDouble() * 6.283, v = 40 + rnd.nextDouble() * 90;
        _sx[i] = cx;
        _sy[i] = cy;
        _svx[i] = math.cos(a) * v;
        _svy[i] = math.sin(a) * v;
        _sl[i] = 0.9 + rnd.nextDouble() * 0.6;
      }
    }
  }

  void _skipReveal() {
    if (_revealT >= 0.35 && _revealT < 0.82) _revealT = 0.82;
  }

  void _finishReveal() {
    _revealT = -1;
    final shape = shapeFor(_shape);
    _skyShapes.add(shape.id);
    _glyphs.add(_recordGlyph(shape));
    _revealFill = null;
    onRevealDone?.call();
  }

  ui.Picture _recordGlyph(ConstellationShape s) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const rad = 11.0;
    _stroke
      ..color = night.gold
      ..strokeWidth = 1.4;
    for (final line in s.strokes) {
      for (var i = 0; i + 1 < line.length; i++) {
        c.drawLine(line[i] * rad, line[i + 1] * rad, _stroke);
      }
    }
    _p.color = night.gold.withValues(alpha: 0.3);
    c.drawPath(s.fillPath(0, 0, rad), _p);
    return rec.endRecording();
  }

  // ------------------------------------------------------------------------------------------------ update

  @override
  void update(double dt) {
    super.update(dt);
    if (dt > 0.1) dt = 0.1;
    _time += dt;
    final r = round;
    if (r == null) return;
    for (var i = 0; i < _lit.length; i++) {
      if (_lit[i] > 0 && _lit[i] < 1) _lit[i] = math.min(1.0, _lit[i] + dt * 3.2);
      if (_shimmer[i] > 0) _shimmer[i] = math.max(0.0, _shimmer[i] - dt);
      if (_appear[i] < 1) _appear[i] = math.min(1.0, _appear[i] + dt * 3.0);
    }
    for (final th in _threads) {
      if (th.t < 1) {
        th.t = math.min(1.0, th.t + dt / 0.38);
        if (th.t >= 1 && !r.isPair) _lit[th.b] = math.max(_lit[th.b], 0.5);
      }
    }
    if (_hintT > 0) {
      _hintT -= dt;
      if (_hintT <= 0) _hintStar = -1;
    }
    // a finger that rests on a star reaches it
    final f = _finger;
    if (f != null && _can) {
      final h = _hit(f);
      if (h >= 0 && h == _dwellStar) {
        _dwellT += dt;
        if (_dwellT >= 0.14 && !_dwellFired) {
          _dwellFired = true;
          _commit(h);
        }
      } else {
        _dwellStar = h;
        _dwellT = 0;
        _dwellFired = false;
      }
    }
    for (var i = 0; i < _maxSparks; i++) {
      if (_sl[i] <= 0) continue;
      _sl[i] -= dt;
      _sx[i] += _svx[i] * dt;
      _sy[i] += _svy[i] * dt;
      _svx[i] *= 0.96;
      _svy[i] = _svy[i] * 0.96 + 22 * dt;
    }
    if (!reduceMotion && !theme.calm && theme.age != GameAge.adult) {
      if (_shootT >= 0) {
        _shootT += dt;
        if (_shootT > 0.9) {
          _shootT = -1;
          _shootAt = _time + 7 + (_time * 13 % 6);
        }
      } else if (_time >= _shootAt && _w > 0) {
        _shootT = 0;
        _shootX = _w * (0.2 + (_time * 37 % 1) * 0.6);
        _shootY = _h * 0.04 + (_time * 53 % 1) * _h * 0.14;
      }
    }
    if (_revealT >= 0) {
      _revealT += dt / _revealLen;
      if (_revealT >= 1) _finishReveal();
    }
  }

  // ------------------------------------------------------------------------------------------------ pictures

  ui.Picture _recordBg() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final rect = Rect.fromLTWH(0, 0, _w, _h);
    c.drawRect(rect, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, _h), [night.top, night.mid, night.bottom], [0, 0.55, 1]));
    void nebula(double cx, double cy, double rx, double ry, Color col, double a) {
      c.save();
      c.translate(cx, cy);
      c.scale(rx, ry);
      c.drawCircle(Offset.zero, 1, Paint()..shader = ui.Gradient.radial(Offset.zero, 1, [col.withValues(alpha: a), col.withValues(alpha: 0)]));
      c.restore();
    }

    final kids = theme.age == GameAge.kids && !theme.calm;
    final soft = theme.age == GameAge.adult || theme.calm;
    nebula(_w * 0.2, _h * 0.3, _w * 0.65, _h * 0.3, night.nebulaA, soft ? 0.16 : (kids ? 0.42 : 0.3));
    nebula(_w * 0.85, _h * 0.62, _w * 0.6, _h * 0.28, night.nebulaB, soft ? 0.1 : (kids ? 0.3 : 0.2));
    nebula(_w * 0.5, _h * 0.05, _w * 0.8, _h * 0.2, night.nebulaA, soft ? 0.08 : 0.16);
    final rnd = math.Random(3);
    final dust = Paint();
    final count = (_w * _h / (soft ? 2600 : 1700)).round().clamp(60, 480);
    for (var i = 0; i < count; i++) {
      final y = rnd.nextDouble() * _h;
      final a = 0.12 + rnd.nextDouble() * 0.5 * (1 - y / _h * 0.5);
      dust.color = night.star.withValues(alpha: a);
      c.drawCircle(Offset(rnd.nextDouble() * _w, y), 0.4 + rnd.nextDouble() * 0.9, dust);
    }
    // soft hills along the bottom
    for (var layer = 0; layer < 2; layer++) {
      final base = _h * (0.93 - layer * 0.045);
      final path = Path()..moveTo(0, _h);
      for (var x = 0.0; x <= _w + 8; x += 8) {
        path.lineTo(x, base - math.sin(x / _w * 5.2 + layer * 1.7) * _h * 0.012 - math.sin(x / _w * 11 + layer) * _h * 0.006);
      }
      path
        ..lineTo(_w, _h)
        ..close();
      c.drawPath(path, Paint()..color = night.ground.withValues(alpha: 0.5 + layer * 0.3));
    }
    c.drawRect(
      rect,
      Paint()..shader = ui.Gradient.radial(rect.center, math.max(_w, _h) * 0.75, [night.ground.withValues(alpha: 0), night.ground.withValues(alpha: 0.5)], [0.55, 1]),
    );
    return rec.endRecording();
  }

  // ------------------------------------------------------------------------------------------------ render

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bg = _bg;
    if (bg == null) return;
    canvas.drawPicture(bg);
    _renderTwinkles(canvas);
    final r = round;
    final dim = _revealT < 0 ? 1.0 : (1 - (_revealT / 0.45).clamp(0.0, 1.0) * 0.75) * (_revealT > 0.8 ? (1 - (_revealT - 0.8) / 0.2) : 1.0);
    if (r != null && _pos.length == r.stars.length) {
      _renderThreads(canvas, dim);
      _renderDrag(canvas, r);
      for (var i = 0; i < _pos.length; i++) {
        _renderStar(canvas, r, i, dim);
      }
      for (var i = 0; i < _pos.length; i++) {
        _renderLabel(canvas, i, dim);
      }
    }
    _renderSparks(canvas);
    if (_revealT >= 0) _renderReveal(canvas);
    _renderStrip(canvas);
  }

  void _renderTwinkles(Canvas canvas) {
    for (var i = 0; i < _twX.length; i++) {
      final a = reduceMotion ? 0.55 : 0.3 + 0.5 * (0.5 + 0.5 * math.sin(_time * (1.1 + _twSize[i] * 0.5) + _twPhase[i]));
      _p.color = night.star.withValues(alpha: a);
      canvas.drawCircle(Offset(_twX[i], _twY[i]), _twSize[i], _p);
    }
    if (_shootT >= 0) {
      final k = _shootT / 0.9;
      final x = _shootX + k * _w * 0.28, y = _shootY + k * _w * 0.12;
      final a = math.sin(k * math.pi);
      _stroke
        ..color = night.star.withValues(alpha: a * 0.2)
        ..strokeWidth = 4;
      canvas.drawLine(Offset(x - 70, y - 30), Offset(x, y), _stroke);
      _stroke
        ..color = night.star.withValues(alpha: a * 0.85)
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(x - 46, y - 20), Offset(x, y), _stroke);
    }
  }

  double get _thick => theme.age == GameAge.kids && !theme.calm ? 4.2 : (theme.age == GameAge.adult || theme.calm ? 1.8 : 2.6);

  void _thread(Canvas canvas, Offset a, Offset b, double t, double alpha) {
    final end = Offset.lerp(a, b, Curves.easeOut.transform(t))!;
    final w = _thick;
    _stroke
      ..color = night.gold.withValues(alpha: 0.14 * alpha)
      ..strokeWidth = w * 4.2;
    canvas.drawLine(a, end, _stroke);
    _stroke
      ..color = night.gold.withValues(alpha: 0.32 * alpha)
      ..strokeWidth = w * 2.1;
    canvas.drawLine(a, end, _stroke);
    _stroke
      ..color = Color.lerp(night.gold, night.star, 0.35)!.withValues(alpha: alpha)
      ..strokeWidth = w;
    canvas.drawLine(a, end, _stroke);
    if (t < 1 && !reduceMotion) {
      canvas.save();
      canvas.translate(end.dx, end.dy);
      canvas.scale(_r * 1.6);
      _haloGold.color = night.gold.withValues(alpha: 1);
      canvas.drawCircle(Offset.zero, 1, _haloGold);
      canvas.restore();
    }
  }

  void _renderThreads(Canvas canvas, double dim) {
    for (final th in _threads) {
      if (th.a < _pos.length && th.b < _pos.length) _thread(canvas, _pos[th.a], _pos[th.b], th.t, dim);
    }
  }

  void _renderDrag(Canvas canvas, ConstellationRound r) {
    final f = _finger;
    if (f == null || revealing) return;
    final from = r.isPair ? _anchor : r.tail;
    if (from >= 0 && from < _pos.length) {
      _stroke
        ..color = night.star.withValues(alpha: 0.28)
        ..strokeWidth = _thick * 2.2;
      canvas.drawLine(_pos[from], f, _stroke);
      _stroke
        ..color = night.star.withValues(alpha: 0.85)
        ..strokeWidth = math.max(1.4, _thick * 0.7);
      canvas.drawLine(_pos[from], f, _stroke);
    }
    for (var i = 1; i < _trailN; i++) {
      final a = i / _trailN;
      _stroke
        ..color = night.gold.withValues(alpha: a * 0.45)
        ..strokeWidth = 1 + a * 4;
      canvas.drawLine(Offset(_trailX[i - 1], _trailY[i - 1]), Offset(_trailX[i], _trailY[i]), _stroke);
    }
    canvas.save();
    canvas.translate(f.dx, f.dy);
    canvas.scale(_r * 2.0);
    _haloGold.color = night.gold.withValues(alpha: 0.9);
    canvas.drawCircle(Offset.zero, 1, _haloGold);
    canvas.restore();
  }

  void _renderStar(Canvas canvas, ConstellationRound r, int i, double dim) {
    final c = _pos[i];
    final lit = Curves.easeOut.transform(_lit[i].clamp(0.0, 1.0));
    final ap = _appear[i];
    if (ap <= 0) return;
    final pop = Curves.easeOutBack.transform(ap.clamp(0.0, 1.0));
    final tw = reduceMotion ? 1.0 : 1 + 0.07 * math.sin(_time * 2.1 + i * 1.9);
    var s = _r * pop * tw;
    final selected = i == _anchor;
    if (selected) s *= 1.2;
    final hint = i == _hintStar && !reduceMotion ? 0.5 + 0.5 * math.sin(_time * 7) : (i == _hintStar ? 1.0 : 0.0);
    // the glow
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(s * (2.7 + lit * 0.9 + hint * 0.7 + (selected ? 0.5 : 0)));
    _halo.color = night.star.withValues(alpha: (0.38 * (1 - lit) + (selected ? 0.3 : 0)) * dim);
    canvas.drawCircle(Offset.zero, 1, _halo);
    if (lit > 0) {
      _haloGold.color = night.gold.withValues(alpha: lit * dim);
      canvas.drawCircle(Offset.zero, 1, _haloGold);
    }
    canvas.restore();
    // the star
    final isA = r.isPair && r.stars[i].side == StarSide.a;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(s);
    if (isA) canvas.rotate(math.pi / 4);
    _p.color = Color.lerp(night.star, night.gold, lit)!.withValues(alpha: dim);
    canvas.drawPath(sparklePath, _p);
    _p.color = night.star.withValues(alpha: dim);
    canvas.drawCircle(Offset.zero, 0.3, _p);
    if (theme.outline > 0.4 && !theme.calm) {
      _stroke
        ..color = night.star.withValues(alpha: 0.5 * dim)
        ..strokeWidth = 0.09;
      canvas.drawCircle(Offset.zero, 0.55, _stroke);
    }
    canvas.restore();
    final sh = _shimmer[i];
    if (sh > 0) {
      final k = 1 - sh / 0.9;
      _stroke
        ..color = night.amber.withValues(alpha: (1 - k) * 0.85)
        ..strokeWidth = 2.2;
      canvas.drawCircle(c, s * (1.2 + k * 1.6), _stroke);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(s * 2.4);
      _haloGold.color = night.amber.withValues(alpha: (1 - k) * 0.7 * (0.6 + 0.4 * math.sin(k * 18)));
      canvas.drawCircle(Offset.zero, 1, _haloGold);
      canvas.restore();
    }
  }

  void _renderLabel(Canvas canvas, int i, double dim) {
    final lab = _labels[i];
    if (lab == null || _appear[i] <= 0.3) return;
    final c = _labelCenter(i);
    final lit = _lit[i] > 0.5;
    final a = ((_appear[i] - 0.3) / 0.7).clamp(0.0, 1.0) * dim;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(lab.scale);
    _plate.color = night.chip.withValues(alpha: (lit ? 0.84 : 0.9) * a);
    canvas.drawRRect(lab.chip, _plate);
    if (lit) {
      _stroke
        ..color = night.gold.withValues(alpha: 0.5 * a)
        ..strokeWidth = 1;
      canvas.drawRRect(lab.chip, _stroke);
    }
    final tp = lit ? lab.lit : lab.plain;
    if (a < 1) {
      canvas.saveLayer(lab.chip.outerRect.inflate(4), _p..color = night.star.withValues(alpha: a));
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    }
    canvas.restore();
  }

  void _renderSparks(Canvas canvas) {
    for (var i = 0; i < _maxSparks; i++) {
      final l = _sl[i];
      if (l <= 0) continue;
      _p.color = night.gold.withValues(alpha: l.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(_sx[i], _sy[i]), 1.4 + l * 1.6, _p);
    }
  }

  void _renderReveal(Canvas canvas) {
    final t = _revealT;
    final shape = shapeFor(_shape);
    final cx = _w / 2, cy = (_top + (_h - _bottom)) / 2;
    final rad = math.min(_w * 0.36, (_h - _top - _bottom) * 0.36);
    var ox = cx, oy = cy, sc = rad;
    var alpha = 1.0;
    if (t > 0.82) {
      final k = Curves.easeInOutCubic.transform(((t - 0.82) / 0.18).clamp(0.0, 1.0));
      final sx = _stripStart() + 14 + _glyphs.length * 30, sy = _h - 28;
      ox = ui.lerpDouble(cx, sx, k)!;
      oy = ui.lerpDouble(cy, sy, k)!;
      sc = ui.lerpDouble(rad, 11, k)!;
      alpha = 1 - k * 0.3;
    }
    final breathe = reduceMotion ? 1.0 : 1 + 0.015 * math.sin(_time * 3);
    sc *= breathe;
    final total = shape.segments;
    final drawn = (Curves.easeInOut.transform((t / 0.45).clamp(0.0, 1.0)) * total).ceil();
    // the fill and its glow
    final fillK = ((t - 0.3) / 0.3).clamp(0.0, 1.0);
    if (fillK > 0) {
      canvas.save();
      canvas.translate(ox, oy);
      canvas.scale(sc * 2.4);
      _haloGold.color = night.gold.withValues(alpha: 0.55 * fillK * alpha);
      canvas.drawCircle(Offset.zero, 1, _haloGold);
      canvas.restore();
      canvas.save();
      canvas.translate(ox - cx * (sc / rad), oy - cy * (sc / rad));
      canvas.scale(sc / rad);
      _p.color = night.gold.withValues(alpha: 0.26 * fillK * alpha);
      canvas.drawPath(_revealFill!, _p);
      canvas.restore();
    }
    var left = drawn;
    final w = math.max(1.6, sc * 0.03);
    for (final pass in const [0, 1, 2]) {
      _stroke
        ..color = pass == 0
            ? night.gold.withValues(alpha: 0.16 * alpha)
            : (pass == 1 ? night.gold.withValues(alpha: 0.34 * alpha) : Color.lerp(night.gold, night.star, 0.4)!.withValues(alpha: alpha))
        ..strokeWidth = pass == 0 ? w * 4 : (pass == 1 ? w * 2.2 : w);
      left = drawn;
      for (final line in shape.strokes) {
        for (var i = 0; i + 1 < line.length && left > 0; i++, left--) {
          canvas.drawLine(Offset(ox + line[i].dx * sc, oy + line[i].dy * sc), Offset(ox + line[i + 1].dx * sc, oy + line[i + 1].dy * sc), _stroke);
        }
      }
    }
    // a bright dot at every sixth vertex: stars joined by threads
    _p.color = night.star.withValues(alpha: alpha);
    var seen = 0;
    for (final line in shape.strokes) {
      for (var i = 0; i < line.length; i += 6) {
        if (seen + i > drawn) break;
        canvas.drawCircle(Offset(ox + line[i].dx * sc, oy + line[i].dy * sc), math.max(1.8, sc * 0.03), _p);
      }
      seen += line.length;
    }
  }

  double _stripStart() => 14 + (_caption?.width ?? 0) + 10 + (skyBase > 0 ? math.min(skyBase, 3) * 16 + 6 : 0);

  void _renderStrip(Canvas canvas) {
    final y = _h - 28;
    final cap = _caption;
    var x = 14.0;
    if (cap != null) {
      cap.paint(canvas, Offset(x, y - cap.height / 2));
      x += cap.width + 10;
    }
    if (skyBase > 0 && cap != null) {
      final dots = math.min(skyBase, 3);
      _p.color = night.gold.withValues(alpha: 0.55);
      for (var i = 0; i < dots; i++) {
        canvas.save();
        canvas.translate(x + 7 + i * 16, y);
        canvas.scale(5);
        canvas.drawPath(sparklePath, _p);
        canvas.restore();
      }
      x += dots * 16 + 6;
    }
    for (var i = 0; i < _glyphs.length; i++) {
      canvas.save();
      canvas.translate(x + 14 + i * 30, y);
      canvas.drawPicture(_glyphs[i]);
      canvas.restore();
    }
    final pr = _progress;
    if (pr != null) pr.paint(canvas, Offset(_w - pr.width - 14, y - pr.height / 2));
  }

  @override
  void onRemove() {
    _bg?.dispose();
    for (final g in _glyphs) {
      g.dispose();
    }
    for (final l in _labels) {
      l?.plain.dispose();
      l?.lit.dispose();
    }
    super.onRemove();
  }
}
