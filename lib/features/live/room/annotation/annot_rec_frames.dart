// lib/features/live/room/annotation/annot_rec_frames.dart
//
// D-811: the drawing on a shared screen in the WEB recording. The web recorder composes the recording itself
// (web/recorder_compositor.js): a shared screen is the LiveKit video track, and the annotation is vector strokes on
// the data channel drawn by a Flutter layer over the room's view of the share (annotation_layer.dart), never part of
// that track. So the compositor drew the bare screen and every stroke was missing from the recording. Now the
// recorder holds one more image source, 'annot': a transparent canvas in the share's own shape that carries the
// strokes (and the laser dot), drawn by the compositor over the fitted share picture (the stage tile's `o`).
//
// This file is the pure half: the board → one frame of strokes in frame pixels, with each stroke's path traced once
// per change (an unchanged stroke reuses its trace), so a frame costs a canvas clear and a replay of the paths.
// Tests: test/org/annot_rec_frames_test.dart.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_education_app/features/live/room/whiteboard/board_rec_ink.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_painter.dart';

/// The compositor's source name of the annotation canvas.
const String kAnnotRecLabel = 'annot';

/// The canvas's long side: the recording canvas's width (1920), so a stroke is never scaled up there.
const int kAnnotRecLongSide = 1920;

/// The canvas size for a share of [aspect] (width / height); 16:9 while the share's shape is not known yet.
(int, int) annotRecSize(double? aspect, {int longSide = kAnnotRecLongSide}) {
  final a = (aspect != null && aspect.isFinite && aspect > 0) ? aspect.clamp(0.2, 5.0).toDouble() : 16 / 9;
  return a >= 1
      ? (longSide, math.max(1, (longSide / a).round()))
      : (math.max(1, (longSide * a).round()), longSide);
}

class AnnotRecFrames {
  // stroke key → (version, points, open, width, height, its trace)
  final Map<String, (int, int, bool, int, int, BoardRecStroke?)> _traces = {};

  /// Strokes traced so far (for the tests: an unchanged stroke is not traced again).
  int traced = 0;

  /// The whole drawing of [board] for a share of [aspect], laser dots included ([laserOpacity] 0..1 by age; a dot at
  /// 0 is left out). The frame's `open` list is everything to draw, in order, on a cleared canvas.
  BoardRecFrame frame(
    AnnotBoard board, {
    double? aspect,
    double Function(AnnotLaserDot dot)? laserOpacity,
    Color laserColor = const Color(0xFFE53935),
  }) {
    final (w, h) = annotRecSize(aspect);
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final out = <BoardRecStroke>[];
    final seen = <String>{};
    for (final s in board.strokes) {
      final key = s.ref.key;
      seen.add(key);
      final have = _traces[key];
      BoardRecStroke? trace;
      if (have != null &&
          have.$1 == s.version &&
          have.$2 == s.points.length &&
          have.$3 == s.open &&
          have.$4 == w &&
          have.$5 == h) {
        trace = have.$6;
      } else {
        trace = BoardRecStroke.ofAnnot(s, rect);
        traced++;
        _traces[key] = (s.version, s.points.length, s.open, w, h, trace);
      }
      if (trace != null) out.add(trace);
    }
    _traces.removeWhere((k, _) => !seen.contains(k));
    for (final d in board.lasers) {
      final a = laserOpacity?.call(d) ?? 1.0;
      if (a <= 0) continue;
      final c = AnnotFit.toLocal(d.x, d.y, rect);
      final r = math.max(5.0, rect.width * 0.007);
      out.add(BoardRecStroke.dot(laserColor.withValues(alpha: 0.35 * a), c.dx, c.dy, r * 2.2));
      out.add(BoardRecStroke.dot(laserColor.withValues(alpha: a), c.dx, c.dy, r));
    }
    return BoardRecFrame(width: w, height: h, clip: rect, open: out);
  }

  /// Forgets every trace (the recording stopped).
  void clear() => _traces.clear();
}
