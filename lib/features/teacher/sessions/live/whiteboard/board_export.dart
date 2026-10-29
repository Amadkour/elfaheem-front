// lib/features/teacher/sessions/live/whiteboard/board_export.dart
//
// The board as an image (D-087 Save as PNG, D-093 formats), drawn straight from the items — not a screenshot of the
// stage — so it is the same on every device, never shows the selection, the tags or the zoom, and works for a page
// that is not on screen:
//   landscape  1920 × 1080        portrait  1440 × 1920
//   continuous the part on the presenter's screen, or the whole board down to its lowest content as ONE tall image
//              (1600 px wide, at most [kBoardExportMaxHeight] px tall: a longer board is scaled down to fit).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'board_controller.dart';
import 'board_format.dart';
import 'board_painter.dart';
import 'board_protocol.dart';
import 'board_stage.dart' show boardTextStyle;

/// The tallest image a continuous board is saved as (a 1600 px wide board of 7 widths: 11 200 px → scaled).
const kBoardExportMaxHeight = 8192.0;

/// What part of the board.
enum BoardExportRegion { page, visible, whole }

/// The page fraction [region] covers: (from, to).
(double, double) boardExportSpan(BoardController c, BoardExportRegion region, {BoardViewportPos? view}) {
  if (!c.isContinuous || region == BoardExportRegion.page) return (0, 1);
  if (region == BoardExportRegion.visible && view != null) return (view.top, math.min(1.0, view.bottom));
  final bottom = boardContentBottom(c.scene.visibleItems, aspect: c.aspect, textHeight: c.textHeight);
  const margin = 0.35 / kBoardContinuousLength; // a third of a width of paper under the last line
  return (0, math.min(1.0, math.max(bottom + margin, 0.75 / kBoardContinuousLength)));
}

/// The output size (px) of [span] of a page of [aspect] drawn [width] px wide, scaled down to [maxHeight].
Size boardExportSize(double aspect, (double, double) span, {double width = 1920, double maxHeight = kBoardExportMaxHeight}) {
  final h = width / aspect * (span.$2 - span.$1);
  if (h <= maxHeight || h <= 0) return Size(width, math.max(1, h));
  final s = maxHeight / h;
  return Size(width * s, maxHeight);
}

/// The visible page of [c] (its [region]) as PNG bytes. Null when there is no board.
Future<Uint8List?> boardRenderPng(BoardController c, {BoardExportRegion region = BoardExportRegion.page, BoardViewportPos? view}) async {
  if (!c.active) return null;
  final aspect = c.aspect;
  final span = boardExportSpan(c, region, view: view);
  final baseWidth = c.isContinuous ? 1600.0 : (aspect >= 1 ? 1920.0 : 1920.0 * aspect);
  final out = boardExportSize(aspect, span, width: baseWidth);
  final w = out.width;
  final pageH = w / aspect; // the whole page's height at this width
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.translate(0, -span.$1 * pageH);
  final drawn = Size(w, span.$2 * pageH);
  BoardBackgroundPainter(c.background).paint(canvas, drawn);
  final items = c.scene.visibleItems.toList();
  BoardItemsPainter(
    items: () => items,
    lasers: () => const [],
    laserColor: const Color(0x00000000),
    laserOpacity: (_) => 0,
    coordSize: Size(w, pageH),
  ).paint(canvas, drawn);
  for (final tx in items.whereType<BoardText>()) {
    final rtl = boardTextIsRtl(tx.text, fallbackRtl: false);
    final tp = TextPainter(
      text: TextSpan(text: tx.text, style: boardTextStyle(tx, w)),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: math.max(8, tx.boxWidth * w));
    // A right-to-left box is aligned to its right edge, as on the stage.
    final dx = rtl ? tx.x * w + math.max(8, tx.boxWidth * w) - tp.width : tx.x * w;
    tp.paint(canvas, Offset(dx, tx.y * pageH));
    tp.dispose();
  }
  final picture = rec.endRecording();
  final image = await picture.toImage(out.width.round(), out.height.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
