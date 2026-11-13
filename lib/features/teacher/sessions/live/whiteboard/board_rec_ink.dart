// lib/features/teacher/sessions/live/whiteboard/board_rec_ink.dart
//
// D-318: the ink of the web recording as vectors. The recording's copy of the board used to be a Flutter raster read
// back to RGBA for every pen sample, a GPU stall on the thread that also draws the pen, so the ink lagged only while
// recording. Now a frame carries the strokes as path commands, which the recorder draws straight on its own 2D canvas
// (recorder_web_impl.dart); the raster is left for what really changes the page (a page turn, an undo, a scroll, text).
//
// The geometry is the painter's own (AnnotationPainter.traceStroke), so a stroke is the same shape on the stage, in
// the raster and here: test/org/board_rec_pacing_test.dart compares the pixels.
library;

import 'dart:typed_data';
import 'dart:ui';

import '../annotation/annotation_controller.dart' show AnnotStroke;
import '../annotation/annotation_ink.dart';
import '../annotation/annotation_painter.dart';
import 'board_painter.dart';
import 'board_protocol.dart';

/// One stroke of a recording frame, in the frame's pixels.
class BoardRecStroke {
  BoardRecStroke._(this.look, this._ops);

  /// [ink]'s shape in [rect] (the whole page in frame pixels); null when it has no points.
  static BoardRecStroke? of(BoardInk ink, Rect rect) {
    final ops = _OpList();
    final look = AnnotationPainter.traceStroke(BoardItemsPainter.strokeFor(ink), rect, ops);
    return look == null ? null : BoardRecStroke._(look, ops.values);
  }

  /// A screen-share annotation stroke [s] in [rect] (the shared picture in frame pixels, D-811); null without points.
  static BoardRecStroke? ofAnnot(AnnotStroke s, Rect rect) {
    final ops = _OpList();
    final look = AnnotationPainter.traceStroke(s, rect, ops);
    return look == null ? null : BoardRecStroke._(look, ops.values);
  }

  /// A filled dot (the laser pointer in the recording, D-811).
  factory BoardRecStroke.dot(Color color, double cx, double cy, double radius) =>
      BoardRecStroke._(AnnotStrokeLook(color: color, fill: true), (_OpList()..circle(cx, cy, radius)).values);

  final AnnotStrokeLook look;
  final List<double> _ops;

  /// Sends the path commands to [sink] in order.
  void replay(AnnotPathSink sink) {
    final o = _ops;
    var i = 0;
    while (i < o.length) {
      switch (o[i].toInt()) {
        case _moveTo:
          sink.moveTo(o[i + 1], o[i + 2]);
          i += 3;
        case _lineTo:
          sink.lineTo(o[i + 1], o[i + 2]);
          i += 3;
        case _cubicTo:
          sink.cubicTo(o[i + 1], o[i + 2], o[i + 3], o[i + 4], o[i + 5], o[i + 6]);
          i += 7;
        case _arc:
          sink.arc(o[i + 1], o[i + 2], o[i + 3], o[i + 4], o[i + 5]);
          i += 6;
        case _circle:
          sink.circle(o[i + 1], o[i + 2], o[i + 3]);
          i += 4;
        default:
          sink.close();
          i += 1;
      }
    }
  }
}

const _moveTo = 0, _lineTo = 1, _cubicTo = 2, _arc = 3, _circle = 4, _close = 5;

class _OpList implements AnnotPathSink {
  final values = <double>[];

  @override
  void moveTo(double x, double y) => values.addAll([_moveTo.toDouble(), x, y]);

  @override
  void lineTo(double x, double y) => values.addAll([_lineTo.toDouble(), x, y]);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x, double y) =>
      values.addAll([_cubicTo.toDouble(), x1, y1, x2, y2, x, y]);

  @override
  void arc(double cx, double cy, double r, double start, double sweep) =>
      values.addAll([_arc.toDouble(), cx, cy, r, start, sweep]);

  @override
  void circle(double cx, double cy, double r) => values.addAll([_circle.toDouble(), cx, cy, r]);

  @override
  void close() => values.add(_close.toDouble());
}

/// One update of the recording's board. The recorder keeps a base picture and shows it with the open strokes on top.
class BoardRecFrame {
  const BoardRecFrame({
    required this.width,
    required this.height,
    required this.clip,
    this.raster,
    this.commit = const [],
    this.open = const [],
  });

  final int width;
  final int height;

  /// The page's area of the frame: ink never reaches the margins around it.
  final Rect clip;

  /// A new base picture as RGBA (null: the base stays).
  final Uint8List? raster;

  /// Strokes that just finished: drawn into the base once, for good.
  final List<BoardRecStroke> commit;

  /// Strokes still being drawn: on top of the base in this frame only.
  final List<BoardRecStroke> open;
}
