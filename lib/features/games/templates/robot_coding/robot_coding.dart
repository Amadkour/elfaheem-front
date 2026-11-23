// lib/features/games/templates/robot_coding/robot_coding.dart — Robot Coding (Games v4 T56, CONTRACT §2 `robot_coding`).
//
//   program   a grid with crates and a glowing goal: build a program from F / L / R and LOOP blocks, press Run, the robot
//             rolls it. The app animates with `simulateProgram` (core/game_grade.dart, the server's rules): every frame is
//             the simulator run on a prefix of the expanded program, so the picture and the server agree.
//
// One item = one grid. A Run is a trace entry (`a` = the program); the first three runs count and the best one scores
// (2 = at or under par, 1 = reached, 0 = not reached). A run is recorded when the robot stops. Step only rehearses
// (never recorded). Done with an item: par reached, a third run, or "Next" after a reached run.
//
// Arrow semantics are the robot's (F = forward, L / R turn its own left / right), so the icons never mirror; the strip and
// the palette read in the UI direction. Sacred text is refused (`sacredAllowed` false).
//
//   RobotSpec / RobotTok / planRobotRun   plain values and the pure plan (frames from the simulator)
//   RobotBoardPainter                     soft-3D grid: slab, tiles, crates, glowing goal, the robot
//   RobotCodingView                       the page (tests drive it by keys: cmd-F, run, step, reset, next, tok-i)
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/question_stage.dart' show StageClosing;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_grade.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';

/// Fixed sizes of the program strip and its loop / delete buttons (a tap target, in logical pixels).
const double _kStripH = 76, _kBtnW = 36, _kBtnWSm = 32, _kBtnH = 46;

const String kRobotCodingKey = 'robot_coding';

// ─────────────────────────────────────────────────────────────────────────────
//  Plain values and the pure plan
// ─────────────────────────────────────────────────────────────────────────────

/// One grid of a `program` item (CONTRACT §3).
class RobotSpec {
  const RobotSpec({required this.w, required this.h, required this.sx, required this.sy, required this.sdir, required this.gx, required this.gy, required this.walls, required this.cmds, required this.max, required this.par});

  final int w, h, sx, sy, sdir, gx, gy, max, par;
  final Set<int> walls;

  /// The blocks on offer, in palette order: `F`, `L`, `R`, `LOOP`.
  final List<String> cmds;

  bool wall(int x, int y) => walls.contains(x * 1000 + y);

  factory RobotSpec.fromBody(Map<String, dynamic> b) {
    int i(Object? v) => (v as num).toInt();
    final s = b['start'] as List, g = b['goal'] as List;
    final c = <String>{for (final x in (b['cmds'] as List? ?? const ['F', 'L', 'R'])) x as String};
    return RobotSpec(
      w: i(b['w']), h: i(b['h']), sx: i(s[0]), sy: i(s[1]), sdir: i(s[2]), gx: i(g[0]), gy: i(g[1]),
      walls: {for (final p in (b['walls'] as List? ?? const [])) i((p as List)[0]) * 1000 + i(p[1])},
      cmds: [for (final k in const ['F', 'L', 'R', 'LOOP']) if (c.contains(k)) k],
      max: i(b['max']), par: i(b['par']),
    );
  }
}

/// One block of the strip: a command, or a loop (`n` times its `body`).
class RobotTok {
  RobotTok(this.id, this.cmd, {this.n = 2, List<String>? body}) : body = body ?? [];
  final int id;
  final String cmd;
  int n;
  final List<String> body;
  bool get isLoop => cmd == 'LOOP';

  /// The block as a trace entry (CONTRACT §5).
  Object toAnswer() => isLoop ? {'loop': n, 'do': List<String>.of(body)} : cmd;
}

/// Tokens as written: a basic command is 1, a loop 1 + its body (the server's `length`).
int robotLength(List<RobotTok> toks) => toks.fold(0, (a, k) => a + 1 + (k.isLoop ? k.body.length : 0));

List<Object> robotAnswer(List<RobotTok> toks) => [for (final k in toks) k.toAnswer()];

/// The robot after one step: cell, quarter turns (continuous, so a turn animates the short way) and what happened.
class RobotFrame {
  const RobotFrame(this.x, this.y, this.turns, this.kind);
  final int x, y;
  final double turns;

  /// `start`, `F`, `L`, `R` or `bump` (the move was refused: a crate or the edge).
  final String kind;
}

/// The run as the simulator plays it: [frames] (the start first), the strip block each step came from, the verdict.
class RobotPlan {
  const RobotPlan(this.frames, this.owner, this.result);
  final List<RobotFrame> frames;
  final List<int> owner;
  final ProgramRun result;
}

/// Plays [toks] on [body] with [simulateProgram]: frame k is the simulator on the first k commands of the expanded
/// program, so what the child sees is what the server will grade.
RobotPlan planRobotRun(Map<String, dynamic> body, List<RobotTok> toks) {
  final flat = <String>[], own = <int>[];
  for (var i = 0; i < toks.length; i++) {
    final k = toks[i];
    if (k.isLoop) {
      for (var r = 0; r < k.n; r++) {
        for (final c in k.body) {
          flat.add(c);
          own.add(i);
        }
      }
    } else {
      flat.add(k.cmd);
      own.add(i);
    }
  }
  final s = body['start'] as List;
  var turns = (s[2] as num).toDouble();
  final frames = <RobotFrame>[RobotFrame((s[0] as num).toInt(), (s[1] as num).toInt(), turns, 'start')];
  final owner = <int>[];
  final cap = math.min(flat.length, kProgramMaxSteps);
  for (var k = 1; k <= cap; k++) {
    final r = simulateProgram(body, flat.sublist(0, k));
    final c = flat[k - 1];
    owner.add(own[k - 1]);
    if (r.bumped) {
      final p = frames.last;
      frames.add(RobotFrame(p.x, p.y, p.turns, 'bump'));
      break;
    }
    if (c == 'L') turns -= 1;
    if (c == 'R') turns += 1;
    frames.add(RobotFrame(r.x, r.y, turns, c));
    if (r.reached) break;
  }
  return RobotPlan(frames, owner, simulateProgram(body, robotAnswer(toks)));
}

/// The robot's pose between two frames, [t] in `0 .. frames.length - 1`.
class RobotPose {
  const RobotPose(this.x, this.y, this.turns, this.hop, this.bump);
  final double x, y, turns;

  /// 0..1 lift of a roll; 0..1 of a bump's lunge.
  final double hop, bump;
}

RobotPose robotPoseAt(List<RobotFrame> frames, double t) {
  if (frames.length < 2) {
    final f = frames.first;
    return RobotPose(f.x.toDouble(), f.y.toDouble(), f.turns, 0, 0);
  }
  final tt = t.clamp(0.0, frames.length - 1.0);
  final i = math.min(tt.floor(), frames.length - 2);
  final f = Curves.easeInOut.transform(tt - i);
  final a = frames[i], b = frames[i + 1];
  final arc = math.sin((tt - i) * math.pi);
  if (b.kind == 'bump') return RobotPose(a.x.toDouble(), a.y.toDouble(), a.turns, 0, arc);
  return RobotPose(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.turns + (b.turns - a.turns) * f, b.kind == 'F' ? arc : 0, 0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  The board painter
// ─────────────────────────────────────────────────────────────────────────────

class RobotBoardPainter extends CustomPainter {
  RobotBoardPainter({required this.spec, required this.theme, required this.frames, required this.move, required this.pulse, required this.reached, required this.still})
      : super(repaint: Listenable.merge([move, pulse]));

  final RobotSpec spec;
  final AgeTheme theme;
  final List<RobotFrame> frames;
  final Animation<double> move, pulse;

  /// The run ended on the goal: it flares.
  final bool reached;

  /// Reduce motion: no idle bob.
  final bool still;

  static final MaskFilter _soft = const MaskFilter.blur(BlurStyle.normal, 9);
  final Paint _p = Paint();

  GamePalette get pal => theme.palette;

  /// The cell size and the top-left of the grid for a canvas of [size].
  static (double cs, Offset origin) fit(Size size, int w, int h) {
    final pad = math.min(size.width, size.height) * 0.05;
    final cs = math.max(8.0, math.min((size.width - pad * 2) / w, (size.height - pad * 2 - 0) / (h + 0.55)));
    final bw = cs * w, bh = cs * h;
    return (cs, Offset((size.width - bw) / 2, (size.height - bh - cs * 0.3) / 2 + cs * 0.2));
  }

  Color get _tileA => Color.lerp(pal.mid, pal.paper, theme.night ? 0.22 : 0.34)!;
  Color get _tileB => Color.lerp(pal.mid, pal.paper, theme.night ? 0.34 : 0.5)!;
  Color get _wood => Color.lerp(pal.accent2, pal.ink, 0.34)!;

  @override
  void paint(Canvas canvas, Size size) {
    final (cs, o) = fit(size, spec.w, spec.h);
    final bw = cs * spec.w, bh = cs * spec.h, depth = cs * 0.22, rad = Radius.circular(cs * 0.2);
    final top = RRect.fromRectAndRadius(Rect.fromLTWH(o.dx, o.dy, bw, bh), rad);
    final pose = robotPoseAt(frames, move.value * (frames.length - 1));
    final ol = theme.outline;

    // the slab: a soft shadow on the floor, then the thickness under the tiles
    canvas.drawRRect(top.shift(Offset(0, depth + cs * 0.16)), _p..color = pal.ink.withValues(alpha: theme.night ? 0.5 : 0.22)..maskFilter = _soft);
    _p.maskFilter = null;
    canvas.drawRRect(top.shift(Offset(0, depth)), _p..color = Color.lerp(pal.near, pal.ink, 0.45)!);

    // the tiles
    canvas.save();
    canvas.clipRRect(top);
    for (var y = 0; y < spec.h; y++) {
      for (var x = 0; x < spec.w; x++) {
        canvas.drawRect(Rect.fromLTWH(o.dx + x * cs, o.dy + y * cs, cs + 0.5, cs + 0.5), _p..color = (x + y).isEven ? _tileA : _tileB);
      }
    }
    // a soft light from the top
    canvas.drawRect(top.outerRect, _p..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pal.paper.withValues(alpha: 0.18), pal.paper.withValues(alpha: 0)]).createShader(top.outerRect));
    _p.shader = null;
    canvas.restore();
    canvas.drawRRect(top, _p..style = PaintingStyle.stroke..strokeWidth = 1.5 + 2.5 * ol..color = (theme.night ? pal.paper : pal.ink).withValues(alpha: 0.28 + 0.2 * ol));
    _p.style = PaintingStyle.fill;

    Offset cell(num x, num y) => Offset(o.dx + (x + 0.5) * cs, o.dy + (y + 0.5) * cs);

    // start pad
    final sc = cell(spec.sx, spec.sy);
    canvas.drawCircle(sc, cs * 0.34, _p..style = PaintingStyle.stroke..strokeWidth = cs * 0.04..color = pal.accent2.withValues(alpha: 0.7));
    _p.style = PaintingStyle.fill;

    _goal(canvas, cell(spec.gx, spec.gy), cs);

    // crates above the robot's row, the robot, crates below it (they hide its feet)
    final robotRow = (pose.y + 0.5).floor();
    for (var y = 0; y < spec.h; y++) {
      if (y == robotRow + 1) _robot(canvas, cell(pose.x, pose.y), cs, pose);
      for (var x = 0; x < spec.w; x++) {
        if (spec.wall(x, y)) _crate(canvas, Rect.fromLTWH(o.dx + x * cs, o.dy + y * cs, cs, cs), cs);
      }
    }
    if (robotRow + 1 >= spec.h || robotRow < 0) _robot(canvas, cell(pose.x, pose.y), cs, pose);
  }

  void _crate(Canvas canvas, Rect c, double cs) {
    final x0 = c.left + cs * 0.08, w = cs * 0.84, fh = cs * 0.3, th = cs * 0.54, bottom = c.bottom - cs * 0.06;
    final front = RRect.fromRectAndRadius(Rect.fromLTWH(x0, bottom - fh, w, fh), Radius.circular(cs * 0.05));
    final topf = RRect.fromRectAndRadius(Rect.fromLTWH(x0, bottom - fh - th, w, th + cs * 0.04), Radius.circular(cs * 0.09));
    canvas.drawOval(Rect.fromLTWH(x0 - cs * 0.02, bottom - cs * 0.06, w + cs * 0.04, cs * 0.12), _p..color = pal.ink.withValues(alpha: 0.25));
    canvas.drawRRect(front, _p..color = Color.lerp(_wood, pal.ink, 0.22)!);
    canvas.drawRRect(topf, _p..color = Color.lerp(_wood, pal.paper, 0.3)!);
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(1.2, cs * 0.035)..strokeCap = StrokeCap.round..color = pal.ink.withValues(alpha: 0.3);
    final inner = topf.deflate(cs * 0.08).outerRect;
    canvas.drawRRect(RRect.fromRectAndRadius(inner, Radius.circular(cs * 0.04)), line);
    canvas.drawLine(inner.topLeft, inner.bottomRight, line);
    canvas.drawLine(inner.topRight, inner.bottomLeft, line);
    canvas.drawLine(Offset(x0 + w * 0.33, bottom - fh + cs * 0.03), Offset(x0 + w * 0.33, bottom - cs * 0.03), line);
    canvas.drawLine(Offset(x0 + w * 0.67, bottom - fh + cs * 0.03), Offset(x0 + w * 0.67, bottom - cs * 0.03), line);
    if (ol > 0.5) {
      canvas.drawRRect(topf, Paint()..style = PaintingStyle.stroke..strokeWidth = cs * 0.04..color = pal.ink);
      canvas.drawRRect(front, Paint()..style = PaintingStyle.stroke..strokeWidth = cs * 0.04..color = pal.ink);
    }
  }

  double get ol => theme.outline;

  void _goal(Canvas canvas, Offset c, double cs) {
    final k = pulse.value;
    final boost = reached && move.value >= 0.999 ? 1.4 : 1.0;
    final glow = cs * (0.62 + 0.1 * math.sin(k * math.pi * 2)) * boost;
    canvas.drawCircle(c, glow, _p..shader = RadialGradient(colors: [pal.gold.withValues(alpha: theme.calm ? 0.45 : 0.75), pal.gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: glow)));
    _p.shader = null;
    canvas.drawCircle(c, cs * 0.36, _p..color = pal.paper.withValues(alpha: 0.85));
    canvas.drawCircle(c, cs * 0.36, _p..style = PaintingStyle.stroke..strokeWidth = cs * 0.05..color = pal.gold);
    _p.style = PaintingStyle.fill;
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final r = (i.isEven ? 0.24 : 0.105) * cs * (boost > 1 ? 1.12 : 1);
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, _p..color = pal.gold);
    canvas.drawPath(star, _p..style = PaintingStyle.stroke..strokeWidth = cs * 0.035..strokeJoin = StrokeJoin.round..color = Color.lerp(pal.gold, pal.ink, 0.55)!);
    _p.style = PaintingStyle.fill;
  }

  void _robot(Canvas canvas, Offset c0, double cs, RobotPose pose) {
    final a = pose.turns * math.pi / 2;
    final dir = Offset(math.sin(a), -math.cos(a));
    var c = c0;
    c += dir * (pose.bump * cs * 0.3);
    if (!still && pose.hop == 0 && pose.bump == 0) c += Offset(0, math.sin(pulse.value * math.pi * 2) * cs * 0.012);
    final lift = pose.hop * cs * 0.08;
    final u = cs;

    // the way it faces: a soft chevron on the floor
    final tip = c0 + dir * (0.58 * u) + Offset(0, u * 0.06);
    final side = Offset(-dir.dy, dir.dx);
    final chev = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - dir.dx * u * 0.15 + side.dx * u * 0.13, tip.dy - dir.dy * u * 0.15 + side.dy * u * 0.13)
      ..lineTo(tip.dx - dir.dx * u * 0.15 - side.dx * u * 0.13, tip.dy - dir.dy * u * 0.15 - side.dy * u * 0.13)
      ..close();
    canvas.drawPath(chev, _p..color = pal.accent.withValues(alpha: 0.8));

    // shadow
    canvas.drawOval(Rect.fromCenter(center: c0 + Offset(0, u * 0.3), width: u * (0.5 - pose.hop * 0.08), height: u * 0.15), _p..color = pal.ink.withValues(alpha: 0.28));

    c = c.translate(0, -lift);
    final edge = Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.03 * ol..color = pal.ink;
    // wheels
    for (final s in [-1.0, 1.0]) {
      final w = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(s * u * 0.2, u * 0.27), width: u * 0.2, height: u * 0.15), Radius.circular(u * 0.07));
      canvas.drawRRect(w, _p..color = Color.lerp(pal.ink, pal.paper, 0.12)!);
      canvas.drawCircle(w.center, u * 0.03, _p..color = pal.paper.withValues(alpha: 0.7));
    }
    // body
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, u * 0.08), width: u * 0.5, height: u * 0.36), Radius.circular(u * 0.12));
    canvas.drawRRect(body, _p..color = pal.accent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(body.left + u * 0.04, body.top + u * 0.03, body.width - u * 0.08, u * 0.08), Radius.circular(u * 0.04)), _p..color = pal.paper.withValues(alpha: 0.28));
    canvas.drawCircle(body.center + Offset(0, u * 0.03), u * 0.055, _p..color = pal.gold);
    if (ol > 0.5) canvas.drawRRect(body, edge);
    // head
    final head = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, -u * 0.17), width: u * 0.54, height: u * 0.34), Radius.circular(u * 0.14));
    canvas.drawCircle(head.center + Offset(-u * 0.29, 0), u * 0.045, _p..color = pal.accent2);
    canvas.drawCircle(head.center + Offset(u * 0.29, 0), u * 0.045, _p..color = pal.accent2);
    canvas.drawRRect(head, _p..color = pal.paper);
    if (ol > 0.5) canvas.drawRRect(head, edge);
    // visor and eyes look the way it faces
    final visor = RRect.fromRectAndRadius(Rect.fromCenter(center: head.center + Offset(dir.dx * u * 0.04, dir.dy * u * 0.02), width: u * (0.4 - 0.08 * dir.dx.abs()), height: u * 0.19), Radius.circular(u * 0.09));
    canvas.drawRRect(visor, _p..color = Color.lerp(pal.ink, pal.accent, 0.12)!);
    final sep = u * (0.085 - 0.045 * dir.dx.abs());
    final look = Offset(dir.dx * u * 0.07, dir.dy * u * 0.035);
    for (final s in [-1.0, 1.0]) {
      final e = visor.center + look + Offset(s * sep, 0);
      canvas.drawCircle(e, u * 0.062, _p..color = pal.gold.withValues(alpha: 0.35));
      canvas.drawCircle(e, u * 0.04, _p..color = pal.gold);
    }
    // antenna
    final ant = head.center + Offset(u * 0.1, -u * 0.17);
    canvas.drawLine(ant + Offset(0, u * 0.03), ant + Offset(u * 0.03, -u * 0.06), Paint()..strokeWidth = u * 0.03..strokeCap = StrokeCap.round..color = pal.ink.withValues(alpha: 0.8));
    final blink = 0.55 + 0.45 * math.sin(pulse.value * math.pi * 2);
    canvas.drawCircle(ant + Offset(u * 0.03, -u * 0.075), u * 0.05, _p..color = pal.accent2.withValues(alpha: 0.4 + 0.6 * blink));

    if (pose.bump > 0.1) {
      // a bump: little sparks at the crate
      final hit = c0 + dir * (0.52 * u);
      final sp = Paint()..strokeWidth = u * 0.03..strokeCap = StrokeCap.round..color = pal.gold.withValues(alpha: pose.bump);
      for (var i = 0; i < 5; i++) {
        final r = a + (i - 2) * 0.5;
        final d = Offset(math.sin(r), -math.cos(r));
        canvas.drawLine(hit + d * u * 0.08, hit + d * u * (0.08 + 0.12 * pose.bump), sp);
      }
    }
  }

  @override
  bool shouldRepaint(RobotBoardPainter old) => old.frames != frames || old.theme != theme || old.reached != reached || old.spec != spec;
}

// ─────────────────────────────────────────────────────────────────────────────
//  The template
// ─────────────────────────────────────────────────────────────────────────────

class RobotCodingTemplate extends GameTemplate {
  const RobotCodingTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => kRobotCodingKey;
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.program};
  @override
  Set<ItemType> get accepts => const {ItemType.program};
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'الروبوت المبرمج';
  @override
  String get nameEn => 'Robot Coding';
  @override
  IconData get icon => Icons.smart_toy_rounded;

  @override
  Widget build(GameSession s) => RobotCodingView(session: s, silent: silent);
}

enum _Phase { edit, playing, done }

const _kCmdIcon = {'F': Icons.arrow_upward_rounded, 'L': Icons.turn_left_rounded, 'R': Icons.turn_right_rounded, 'LOOP': Icons.repeat_rounded};

String _cmdWord(String c) => switch (c) {
      'F' => t('تقدّم', 'Go'),
      'L' => t('يسار', 'Left'),
      'R' => t('يمين', 'Right'),
      _ => t('كرّر', 'Loop'),
    };

class RobotCodingView extends StatefulWidget {
  const RobotCodingView({super.key, required this.session, this.silent = false, this.advanceMs = 1800});
  final GameSession session;
  final bool silent;

  /// How long a finished item stays before the next one (0 = tests step it with `next`).
  final int advanceMs;

  @override
  State<RobotCodingView> createState() => RobotCodingViewState();
}

class RobotCodingViewState extends State<RobotCodingView> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  final ScrollController _scroll = ScrollController();
  final List<RobotTok> _toks = [];
  int _item = -1, _nextId = 1, _active = 0, _runs = 0, _gen = 0, _stepAt = 0, _lit = -1;
  _Phase _phase = _Phase.edit;
  List<RobotFrame> _frames = const [];
  List<int> _owner = const [];
  RobotSpec? _spec;
  String? _msg;
  bool _msgGood = false, _reached = false, _canNext = false;
  Timer? _auto;

  GameSession get s => widget.session;

  /// Tests read these.
  int get itemIndex => _item;
  int get runsUsed => _runs;
  List<RobotTok> get tokens => List.unmodifiable(_toks);

  @override
  void initState() {
    super.initState();
    _move.addListener(_onMove);
    _nextItem();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _pulse, rest: 0.0);
  }

  @override
  void dispose() {
    _auto?.cancel();
    _move.dispose();
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _body => s.items[_item].body;
  int get _stepMs => switch (AgeThemeScope.of(context).age) { GameAge.kids => 520, GameAge.teen => 330, GameAge.adult => 420 };
  bool get _editable => _phase != _Phase.playing && _runs < kProgramRuns;
  int get _len => robotLength(_toks);

  void _tick([GameSound sound = GameSound.tap]) => GameFeedback.instance.play(sound, silent: widget.silent);

  // ---- the flow ----

  void _nextItem() {
    _auto?.cancel();
    for (var i = _item + 1; i < s.items.length; i++) {
      if (s.items[i].type != ItemType.program) continue;
      _item = i;
      _spec = RobotSpec.fromBody(s.items[i].body);
      _toks.clear();
      _active = 0;
      _runs = 0;
      _canNext = false;
      _msg = null;
      _resetRobot(notify: false);
      if (mounted) setState(() {});
      return;
    }
    _item = s.items.length;
    if (!s.finished) s.finish('done');
    if (mounted) setState(() {});
  }

  void _resetRobot({bool notify = true}) {
    _gen++;
    _auto?.cancel();
    _move.stop();
    _move.value = 0;
    final sp = _spec!;
    _frames = [RobotFrame(sp.sx, sp.sy, sp.sdir.toDouble(), 'start')];
    _owner = const [];
    _lit = -1;
    _stepAt = 0;
    _reached = false;
    _phase = _Phase.edit;
    if (notify && mounted) setState(() {});
  }

  /// A change to the program: the robot goes back to the start and a finished run no longer stands.
  void _edited() {
    final keep = _msg;
    _resetRobot(notify: false);
    _canNext = false;
    _msg = _runs >= kProgramRuns ? keep : null;
    setState(() {});
  }

  void _say(String text, {bool good = false}) => setState(() {
        _msg = text;
        _msgGood = good;
      });

  // ---- editing ----

  void _add(String c) {
    if (!_editable) return;
    _tick();
    final sp = _spec!;
    RobotTok? loop;
    for (final k in _toks) {
      if (k.id == _active && k.isLoop) loop = k;
    }
    if (c == 'LOOP') {
      if (loop != null) {
        _active = 0;
        setState(() {});
        return;
      }
      if (_len + 1 > sp.max) return _full();
      final k = RobotTok(_nextId++, 'LOOP');
      _toks.add(k);
      _active = k.id;
    } else {
      if (_len + 1 > sp.max) return _full();
      if (loop != null && loop.body.length < 10) {
        loop.body.add(c);
      } else {
        _toks.add(RobotTok(_nextId++, c));
      }
    }
    _edited();
    _toEnd();
  }

  void _full() => _say(t('وصلت إلى أقصى عدد من الأوامر', 'That is the most blocks you can use'));

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      });

  void _remove(int i) {
    if (!_editable) return;
    _tick();
    _toks.removeAt(i);
    _edited();
  }

  void _removeBody(int i, int j) {
    if (!_editable) return;
    _tick();
    _toks[i].body.removeAt(j);
    _edited();
  }

  void _cycle(int i) {
    if (!_editable) return;
    _tick();
    final k = _toks[i];
    k.n = k.n >= 9 ? 2 : k.n + 1;
    _edited();
  }

  void _toggleActive(int i) {
    if (!_editable) return;
    _tick();
    final id = _toks[i].id;
    _active = _active == id ? 0 : id;
    setState(() {});
  }

  void _reorder(int from, int to) {
    if (from == to) return;
    _toks.insert(to, _toks.removeAt(from));
    _tick(GameSound.snap);
    _edited();
  }

  /// Every loop needs something inside; names the first that does not (the Run button stays off).
  bool get _emptyLoop => _toks.any((k) => k.isLoop && k.body.isEmpty);
  bool get _canRun => _toks.isNotEmpty && !_emptyLoop && _len <= _spec!.max && _phase != _Phase.playing && _runs < kProgramRuns;

  // ---- running ----

  void _run() {
    if (!_canRun) return;
    _tick();
    final plan = planRobotRun(_body, _toks);
    final gen = ++_gen;
    _auto?.cancel();
    setState(() {
      _frames = plan.frames;
      _owner = plan.owner;
      _phase = _Phase.playing;
      _msg = null;
      _reached = false;
      _active = 0;
    });
    final steps = plan.frames.length - 1;
    if (appMotionOff(context) || steps == 0) {
      _move.value = 1;
      _finishRun(plan, gen);
      return;
    }
    _move.duration = Duration(milliseconds: _stepMs * steps);
    _move.forward(from: 0).then((_) => _finishRun(plan, gen), onError: (_) {});
  }

  void _finishRun(RobotPlan plan, int gen) {
    if (!mounted || gen != _gen || _phase != _Phase.playing) return;
    final r = s.answer(_item, robotAnswer(_toks));
    if (r == null) {
      setState(() => _phase = _Phase.edit);
      return;
    }
    _runs++;
    final res = plan.result;
    final good = res.reached;
    _lit = -1;
    _phase = _Phase.done;
    _reached = good;
    _canNext = r.points == 2 || good || _runs >= kProgramRuns;
    if (s.finished) {
      setState(() {});
      return;
    }
    if (r.points == 2) {
      _say(t('ممتاز! وصل بأقل عدد من الأوامر', 'Perfect! Goal reached with the fewest blocks'), good: true);
    } else if (good) {
      _say(t('وصل إلى الهدف! جرّب أوامر أقل للحصول على المكافأة (${_spec!.par})', 'Goal reached! Try ${_spec!.par} blocks or fewer for the bonus'), good: true);
    } else if (res.bumped) {
      _say(t('اصطدم الروبوت! غيّر الأوامر وحاول مجددًا', 'Bump! Change the blocks and try again'));
    } else {
      _say(t('لم يصل بعد إلى الهدف', 'Not at the goal yet'));
    }
    setState(() {});
    if (r.points == 2 || _runs >= kProgramRuns) {
      final g = _gen;
      if (widget.advanceMs > 0) {
        _auto = Timer(Duration(milliseconds: widget.advanceMs), () {
          if (mounted && g == _gen && _phase == _Phase.done) _nextItem();
        });
      }
    }
  }

  void _step() {
    if (_toks.isEmpty || _emptyLoop || _phase == _Phase.playing) return;
    _tick();
    if (_stepAt == 0 || _frames.length < 2 || _stepAt >= _frames.length - 1) {
      final plan = planRobotRun(_body, _toks);
      _gen++;
      _frames = plan.frames;
      _owner = plan.owner;
      _stepAt = 0;
      _move.value = 0;
      _reached = false;
    }
    _stepAt++;
    final n = _frames.length - 1;
    if (appMotionOff(context)) {
      _move.value = _stepAt / n;
    } else {
      _move.animateTo(_stepAt / n, duration: Duration(milliseconds: _stepMs), curve: Curves.linear);
    }
    _reached = _stepAt >= n && planRobotRun(_body, _toks).result.reached;
    setState(() {});
  }

  void _onMove() {
    final n = _frames.length - 1;
    var lit = -1;
    if (n > 0 && (_phase == _Phase.playing || _stepAt > 0)) {
      final i = (_move.value * n).floor();
      lit = i >= n || i >= _owner.length ? -1 : _owner[i];
    }
    if (lit != _lit && mounted) setState(() => _lit = lit);
  }

  void _primary() {
    if (_phase == _Phase.done && _canNext) {
      _nextItem();
    } else {
      _run();
    }
  }

  // ---- the page ----

  @override
  Widget build(BuildContext context) {
    final sacred = s.sacred;
    return StageFrame(
      session: s,
      kinds: kRobotCodingKinds,
      silent: widget.silent,
      child: Material(
        type: MaterialType.transparency,
        child: sacred
            ? Center(child: Text(t('هذه اللعبة لا تعرض نصوصًا مقدسة', 'This game does not show sacred text'), style: appText(16, w: FontWeight.w700)))
            : s.finished || _item >= s.items.length
                ? Builder(builder: (context) {
                    final theme = AgeThemeScope.of(context);
                    return StageClosing(session: s, theme: theme, sf: StageSurface(theme, context));
                  })
                : _page(context),
      ),
    );
  }

  Widget _page(BuildContext context) {
    final theme = AgeThemeScope.of(context);
    final sf = StageSurface(theme, context);
    final sp = _spec!;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final reduce = appMotionOff(context);
    final board = Semantics(
      label: t('شبكة الروبوت ${sp.w} في ${sp.h}', 'Robot grid ${sp.w} by ${sp.h}'),
      image: true,
      child: CustomPaint(
        painter: RobotBoardPainter(spec: sp, theme: theme, frames: _frames, move: _move, pulse: _pulse, reached: _reached, still: reduce),
        child: const SizedBox.expand(),
      ),
    );
    final boardArea = Stack(children: [
      Positioned.fill(child: board),
      Positioned(
        left: AppSpace.sm,
        right: AppSpace.sm,
        bottom: AppSpace.xxs,
        child: IgnorePointer(child: Center(child: _banner(sf))),
      ),
    ]);
    final strip = _strip(sf, theme, vertical: wide);
    final panel = Column(mainAxisSize: MainAxisSize.min, children: [_palette(sf), const SizedBox(height: AppSpace.xs), _actions(sf)]);
    final pad = EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.sm);
    if (wide) {
      return Padding(
        padding: pad,
        child: Column(children: [
          _header(sf),
          const SizedBox(height: AppSpace.xs),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: boardArea),
              const SizedBox(width: AppSpace.md),
              SizedBox(
                width: 380,
                child: Column(children: [Expanded(child: strip), const SizedBox(height: AppSpace.sm), panel]),
              ),
            ]),
          ),
        ]),
      );
    }
    return Padding(
      padding: pad,
      child: Column(children: [
        _header(sf),
        Expanded(child: boardArea),
        const SizedBox(height: AppSpace.xs),
        SizedBox(height: _kStripH, child: strip),
        const SizedBox(height: AppSpace.xs),
        panel,
      ]),
    );
  }

  Widget _header(StageSurface sf) {
    final it = s.items[_item];
    final sp = _spec!;
    final prompt = it.prompt.of(AppConfig.lang);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sf.paper.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(sf.radius),
            border: Border.all(color: Color.lerp(sf.paper, sf.accent, 0.4)!, width: sf.edgeWidth * 0.6),
            boxShadow: sf.lift(blur: 12, dy: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Row(children: [
              Expanded(
                child: Text(prompt.isEmpty ? t('أوصل الروبوت إلى النجمة', 'Get the robot to the star') : prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: sf.ink, h: 1.35)),
              ),
              const SizedBox(width: AppSpace.xs),
              _pill(sf, Icons.view_module_rounded, '$_len/${sp.max}', over: _len >= sp.max, key: const ValueKey('count'), tip: t('الأوامر المستخدمة / الأقصى', 'Blocks used / most allowed')),
              const SizedBox(width: AppSpace.xxs),
              _pill(sf, Icons.flag_rounded, '${sp.par}', tip: t('عدد الأوامر للمكافأة', 'Blocks for the bonus')),
              const SizedBox(width: AppSpace.xxs),
              _pill(sf, Icons.replay_rounded, '${math.max(0, kProgramRuns - _runs)}', key: const ValueKey('runs-left'), tip: t('محاولات متبقية', 'Runs left')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pill(StageSurface sf, IconData icon, String text, {bool over = false, Key? key, String? tip}) => Semantics(
        label: tip,
        child: ExcludeSemantics(
          child: DecoratedBox(
            key: key,
            decoration: BoxDecoration(color: sf.tint(over ? sf.wrong : sf.accent, 0.16), borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: over ? sf.wrong : sf.accent),
                const SizedBox(width: AppBorder.focus),
                Text(text, style: appText(13, w: FontWeight.w800, c: sf.ink)),
              ]),
            ),
          ),
        ),
      );

  Widget _banner(StageSurface sf) {
    return AnimatedSwitcher(
      duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 220),
      child: _msg == null
          ? const SizedBox.shrink(key: ValueKey('nomsg'))
          : DecoratedBox(
              key: ValueKey(_msg),
              decoration: BoxDecoration(
                color: sf.paper.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: _msgGood ? sf.right : sf.wrong, width: 2),
                boxShadow: sf.lift(blur: 10, dy: 3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_msgGood ? Icons.check_circle_rounded : Icons.info_rounded, size: 18, color: _msgGood ? sf.right : sf.wrong),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(child: Text(_msg!, style: appText(14, w: FontWeight.w700, c: sf.ink, h: 1.3))),
                ]),
              ),
            ),
    );
  }

  // ---- the program strip ----

  Widget _strip(StageSurface sf, AgeTheme theme, {required bool vertical}) {
    final wide = vertical;
    final immediate = wide || const {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(defaultTargetPlatform);
    final list = _toks.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Text(t('اضغط على الأوامر لبناء برنامجك', 'Tap the blocks to build your program'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: sf.ink.withValues(alpha: 0.6))),
            ),
          )
        : ReorderableListView.builder(
            scrollController: _scroll,
            scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.all(AppSpace.xs),
            itemCount: _toks.length,
            onReorderItem: _reorder,
            proxyDecorator: (child, index, anim) => AnimatedBuilder(
              animation: anim,
              builder: (context, c) {
                final k = Curves.easeOut.transform(anim.value);
                return Transform.scale(scale: 1 + 0.12 * k, child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.control), boxShadow: [BoxShadow(color: sf.ink.withValues(alpha: 0.35 * k), blurRadius: 16, offset: const Offset(0, 8))]), child: c));
              },
              child: Material(type: MaterialType.transparency, child: child),
            ),
            itemBuilder: (context, i) {
              final k = _toks[i];
              final chip = Padding(
                key: ValueKey('tok-key-${k.id}'),
                padding: EdgeInsetsDirectional.only(end: vertical ? 0 : AppSpace.xs, bottom: vertical ? AppSpace.xs : 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: vertical ? null : 1,
                  child: k.isLoop ? _loopBlock(sf, i, k) : _chip(sf, k.cmd, i, lit: _lit == i, onTap: () => _remove(i)),
                ),
              );
              return KeyedSubtree(
                key: ValueKey('tok-key-${k.id}'),
                child: immediate ? ReorderableDragStartListener(index: i, child: chip) : ReorderableDelayedDragStartListener(index: i, child: chip),
              );
            },
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: sf.paper.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(sf.radius),
        border: Border.all(color: sf.edge.withValues(alpha: 0.6), width: 1.5),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(sf.radius), child: list),
    );
  }

  Color _on(Color bg, StageSurface sf) => ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? sf.paper : sf.ink;

  Color _cmdColor(StageSurface sf, String c) => switch (c) { 'F' => sf.accent, 'LOOP' => sf.gold, _ => sf.theme.palette.accent2 };

  Widget _chip(StageSurface sf, String c, int i, {bool lit = false, VoidCallback? onTap, double size = 56}) {
    final bg = _cmdColor(sf, c);
    return Semantics(
      button: true,
      label: _cmdWord(c),
      child: GestureDetector(
        key: ValueKey('tok-$i'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 140),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: lit ? sf.paper : Color.lerp(bg, sf.ink, 0.35)!, width: lit ? 3 : sf.edgeWidth * 0.7),
            boxShadow: lit ? [BoxShadow(color: bg.withValues(alpha: 0.8), blurRadius: 14)] : null,
          ),
          child: Icon(_kCmdIcon[c], size: size * 0.52, color: _on(bg, sf)),
        ),
      ),
    );
  }

  Widget _loopBlock(StageSurface sf, int i, RobotTok k) {
    final bg = sf.gold;
    final active = _active == k.id;
    final on = _on(bg, sf);
    return DecoratedBox(
      key: ValueKey('tok-$i'),
      decoration: BoxDecoration(
        color: sf.tint(bg, 0.28),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: active ? sf.ink : Color.lerp(bg, sf.ink, 0.35)!, width: active ? 3 : sf.edgeWidth * 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppBorder.line),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            key: ValueKey('loop-open-$i'),
            onTap: () => _toggleActive(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(width: _kBtnW, height: _kBtnH, child: Icon(Icons.repeat_rounded, size: 26, color: sf.ink)),
          ),
          GestureDetector(
            key: ValueKey('loop-n-$i'),
            onTap: () => _cycle(i),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              label: t('مرات التكرار ${k.n}', 'Repeat ${k.n} times'),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text('×${k.n}', style: appText(16, w: FontWeight.w900, c: on)),
              ),
            ),
          ),
          for (var j = 0; j < k.body.length; j++) ...[
            const SizedBox(width: AppBorder.line),
            _chip(sf, k.body[j], i * 100 + j, size: 40, onTap: () => _removeBody(i, j)),
          ],
          if (k.body.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              child: Text(t('أضف أوامر', 'add blocks'), style: appText(12, w: FontWeight.w700, c: sf.ink.withValues(alpha: 0.6))),
            ),
          GestureDetector(
            key: ValueKey('loop-x-$i'),
            onTap: () => _remove(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(width: _kBtnWSm, height: _kBtnH, child: Icon(Icons.close_rounded, size: 18, color: sf.ink.withValues(alpha: 0.7))),
          ),
        ]),
      ),
    );
  }

  // ---- palette and actions ----

  Widget _palette(StageSurface sf) {
    final sp = _spec!;
    final full = _len >= sp.max;
    final loopOpen = _toks.any((k) => k.id == _active && k.isLoop);
    Widget key(String c) => _KeyButton(
          key: ValueKey('cmd-$c'),
          color: _cmdColor(sf, c),
          ink: sf.ink,
          on: _on(_cmdColor(sf, c), sf),
          icon: c == 'LOOP' && loopOpen ? Icons.check_rounded : _kCmdIcon[c]!,
          label: c == 'LOOP' && loopOpen ? t('تم', 'Done') : _cmdWord(c),
          dim: !_editable || (full && !(c == 'LOOP' && loopOpen)),
          onTap: () => _add(c),
          edge: sf.edgeWidth,
        );
    // the keys share one row equally; when a key would get less than a touch target, they wrap into two rows
    Widget row(List<String> cmds) => Row(children: [
          for (var i = 0; i < cmds.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Expanded(child: key(cmds[i])),
          ],
        ]);
    final cmds = sp.cmds;
    return LayoutBuilder(builder: (context, box) {
      final each = (box.maxWidth - AppSpace.xs * (cmds.length - 1)) / cmds.length;
      if (cmds.length < 2 || each >= AppTouch.min) return row(cmds);
      final half = (cmds.length + 1) ~/ 2;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        row(cmds.sublist(0, half)),
        const SizedBox(height: AppSpace.xs),
        row(cmds.sublist(half)),
      ]);
    });
  }

  Widget _actions(StageSurface sf) {
    final next = _phase == _Phase.done && _canNext;
    final last = next && !s.items.skip(_item + 1).any((e) => e.type == ItemType.program);
    final canPrimary = next || _canRun;
    final playing = _phase == _Phase.playing;
    // in a very narrow box the two round keys step down to the minimum touch size so Run keeps its room
    return LayoutBuilder(builder: (context, box) {
      final round = box.maxWidth < AppTouch.primary * 4 + AppSpace.xs + AppSpace.sm ? AppTouch.min : AppTouch.primary;
      return Row(children: [
      _RoundButton(key: const ValueKey('reset'), icon: Icons.restart_alt_rounded, label: t('إعادة', 'Reset'), sf: sf, size: round, onTap: _toks.isEmpty && _phase == _Phase.edit && _stepAt == 0 ? null : _reset),
      const SizedBox(width: AppSpace.xs),
      _RoundButton(key: const ValueKey('step'), icon: Icons.skip_next_rounded, label: t('خطوة', 'Step'), sf: sf, size: round, onTap: _toks.isEmpty || _emptyLoop || playing ? null : _step),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: _KeyButton(
          key: ValueKey(next ? 'next' : 'run'),
          color: sf.accent,
          ink: sf.ink,
          on: _on(sf.accent, sf),
          icon: next ? (last ? Icons.flag_rounded : Icons.arrow_forward_rounded) : Icons.play_arrow_rounded,
          label: next ? (last ? t('إنهاء', 'Finish') : t('التالي', 'Next')) : t('شغّل', 'Run'),
          dim: !canPrimary,
          onTap: _primary,
          edge: sf.edgeWidth,
          big: true,
        ),
      ),
      ]);
    });
  }

  void _reset() {
    _tick();
    _toks.clear();
    _active = 0;
    if (_runs >= kProgramRuns) {
      // the three runs are spent: there is only "Next"
      _resetRobot();
      return;
    }
    _canNext = false;
    _msg = null;
    _resetRobot();
  }
}

const Set<MechanicKind> kRobotCodingKinds = {MechanicKind.program};

/// A chunky key with a solid edge that presses in (palette, Run).
class _KeyButton extends StatefulWidget {
  const _KeyButton({super.key, required this.color, required this.ink, required this.on, required this.icon, required this.label, required this.onTap, required this.edge, this.dim = false, this.big = false});
  final Color color, ink, on;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double edge;
  final bool dim, big;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final lift = _down ? 0.0 : w.edge + 1;
    final h = w.big ? AppTouch.primary : AppTouch.primary - 4;
    final reduce = appMotionOff(context);
    return Semantics(
      button: true,
      enabled: !w.dim,
      label: w.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: w.onTap,
          child: Opacity(
            opacity: w.dim ? 0.45 : 1,
            child: SizedBox(
              height: h + w.edge + 1,
              child: Stack(children: [
                Positioned(left: 0, right: 0, bottom: 0, height: h, child: DecoratedBox(decoration: BoxDecoration(color: Color.lerp(w.color, w.ink, 0.4), borderRadius: BorderRadius.circular(AppRadius.control)))),
                AnimatedPositioned(
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 90),
                  left: 0,
                  right: 0,
                  top: w.edge + 1 - lift,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: w.color, borderRadius: BorderRadius.circular(AppRadius.control)),
                    // the label shows when the key itself has room for it (not the screen width: a key in a
                    // narrow side panel or at a large text size keeps just its icon, never a cut one)
                    child: LayoutBuilder(
                      builder: (context, box) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(w.icon, size: w.big ? 28 : 24, color: w.on),
                        if (box.maxWidth >= AppTouch.primary + AppSpace.lg) ...[
                          const SizedBox(width: AppSpace.xxs),
                          Flexible(child: Text(w.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(w.big ? 17 : 13, w: FontWeight.w800, c: w.on))),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small secondary round key (Reset, Step).
class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.sf, required this.onTap, this.size = AppTouch.primary});
  final IconData icon;
  final String label;
  final StageSurface sf;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    return Semantics(
      button: true,
      enabled: !off,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Opacity(
            opacity: off ? 0.4 : 1,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: sf.paper,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: sf.edge, width: sf.edgeWidth * 0.6),
              ),
              child: Icon(icon, size: 26, color: sf.ink),
            ),
          ),
        ),
      ),
    );
  }
}
