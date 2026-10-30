// lib/features/teacher/sessions/live/whiteboard/board_export.dart
//
// The board as an image (D-087 Save as PNG, D-093 formats), drawn straight from the items — not a screenshot of the
// stage — so it is the same on every device, never shows the selection, the tags or the zoom, and works for a page
// that is not on screen:
//   landscape  1920 × 1080        portrait  1440 × 1920
//   continuous the part on the presenter's screen, or the whole board down to its lowest content as ONE tall image
//              (1600 px wide, at most [kBoardExportMaxHeight] px tall: a longer board is scaled down to fit). A page
//              grown sideways (D-107) is saved as wide as it is drawn ([boardExportSpanX]: its column, widened to
//              the content beside it + a margin; 1600 px per page width, at most [kBoardExportMaxWidth]).
//
// The 2 fps recording track of a continuous page (D-090, board_video_track.dart) is drawn here too
// ([boardRecordingRgba]): the presenter's view widened to 16:9 over the page's reach ([boardRecordingWindow]).
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

/// The widest one (a page grown to its whole [kBoardSideMax] reach: 4 widths × 1600 px).
const kBoardExportMaxWidth = 6400.0;

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

/// The page widths [region] covers across: (from, to). A fixed page, and a continuous one that never grew: its column
/// (0, 1). A continuous page grown sideways (D-107): the presenter's view ([BoardExportRegion.visible]), or what is
/// drawn — the column widened to the content beside it + [kBoardSideMargin] ([boardContinuousSpanX]).
(double, double) boardExportSpanX(BoardController c, BoardExportRegion region, {BoardViewportPos? view}) {
  if (!c.isContinuous || region == BoardExportRegion.page) return (0, 1);
  if (region == BoardExportRegion.visible && view != null) return view.width > 0 ? (view.left, view.right) : (0, 1);
  return boardContinuousSpanX(content: boardContentSpanX(c.scene.visibleItems));
}

/// The output size (px) of [span] (down) × [spanX] (across, page widths) of a page of [aspect] drawn [width] px per
/// page width, scaled down evenly to [maxHeight] × [maxWidth].
Size boardExportSize(double aspect, (double, double) span,
    {double width = 1920, double maxHeight = kBoardExportMaxHeight, (double, double) spanX = (0, 1), double maxWidth = kBoardExportMaxWidth}) {
  final w = width * (spanX.$2 - spanX.$1);
  final h = width / aspect * (span.$2 - span.$1);
  if (h <= 0 || w <= 0) return Size(math.max(1, w), math.max(1, h));
  final s = math.min(1.0, math.min(maxHeight / h, maxWidth / w));
  return Size(w * s, math.max(1, h * s));
}

/// Paints [region] of [c]'s visible page — x in page widths, y in page fractions — into [out] (px, from its corner):
/// the paper, the ink and shapes, the text boxes.
void _paintRegion(Canvas canvas, BoardController c, Rect region, Size out) {
  if (region.width <= 0 || region.height <= 0) return;
  final unit = out.width / region.width; // one page width, px
  final pageH = unit / c.aspect; // the whole page's height, px
  final ox = -region.left * unit;
  canvas.save();
  canvas.clipRect(Offset.zero & out);
  canvas.translate(0, -region.top * pageH);
  final drawn = Size(out.width, region.bottom * pageH);
  BoardBackgroundPainter(c.background, unit: unit, originX: ox).paint(canvas, drawn);
  final items = c.scene.visibleItems.toList();
  BoardItemsPainter(
    items: () => items,
    lasers: () => const [],
    laserColor: const Color(0x00000000),
    laserOpacity: (_) => 0,
    coordSize: Size(unit, pageH),
    coordOrigin: Offset(ox, 0),
  ).paint(canvas, drawn);
  for (final tx in items.whereType<BoardText>()) {
    final rtl = boardTextIsRtl(tx.text, fallbackRtl: false);
    final tp = TextPainter(
      text: TextSpan(text: tx.text, style: boardTextStyle(tx, unit)),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: math.max(8, tx.boxWidth * unit));
    // A right-to-left box is aligned to its right edge, as on the stage.
    final dx = rtl ? tx.x * unit + math.max(8, tx.boxWidth * unit) - tp.width : tx.x * unit;
    tp.paint(canvas, Offset(ox + dx, tx.y * pageH));
    tp.dispose();
  }
  canvas.restore();
}

/// The visible page of [c] (its [region]) as PNG bytes. Null when there is no board.
Future<Uint8List?> boardRenderPng(BoardController c, {BoardExportRegion region = BoardExportRegion.page, BoardViewportPos? view}) async {
  if (!c.active) return null;
  final aspect = c.aspect;
  final span = boardExportSpan(c, region, view: view);
  final spanX = boardExportSpanX(c, region, view: view);
  final baseWidth = c.isContinuous ? 1600.0 : (aspect >= 1 ? 1920.0 : 1920.0 * aspect);
  final out = boardExportSize(aspect, span, width: baseWidth, spanX: spanX);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  _paintRegion(canvas, c, Rect.fromLTRB(spanX.$1, span.$1, spanX.$2, span.$2), out);
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

/// The part of a continuous page the recording track shows (D-107): the presenter's [view] widened to the frame's
/// [frameAspect] — sideways first, over the page's reach [spanX] (what is drawn beside the view, a grown page's
/// paper), centred on the view; a view still too wide gets more of the page below it (within [extent]). x in page
/// widths, y in page fractions; [aspect] is the page's (width / whole length). What cannot be filled stays a margin
/// of the frame.
Rect boardRecordingWindow({
  required BoardViewportPos view,
  required (double, double) spanX,
  required double aspect,
  double extent = 1,
  double frameAspect = kBoardAspect,
}) {
  final vw = view.width > 0 ? view.width : 1.0;
  final vl = view.width > 0 ? view.left : 0.0;
  final hW = view.height / aspect; // the view's height in page widths
  var left = vl, w = vw, top = view.top, h = view.height;
  if (hW > 0 && vw / hW < frameAspect) {
    // Narrow (a phone's view): widen it over what the page has beside it.
    final reach = spanX.$2 - spanX.$1;
    w = math.min(reach, hW * frameAspect);
    w = math.max(w, vw);
    left = (vl + vw / 2 - w / 2).clamp(spanX.$1, math.max(spanX.$1, spanX.$2 - w)).toDouble();
    if (w < vw) left = vl;
  } else if (hW > 0) {
    // Wide (a laptop's view): more of the page below.
    final want = vw / frameAspect * aspect; // in page fractions
    final bottom = math.max(extent, view.bottom);
    h = math.min(want, bottom);
    top = math.max(0.0, math.min(view.top, bottom - h));
  }
  return Rect.fromLTWH(left, top, w, h);
}

/// The recording track's frame of a continuous board (D-090 / D-107): [boardRecordingWindow] around the presenter's
/// view, drawn from the items into [width] × [height] (fitted, centred, white around it) as RGBA. Null when there is
/// no continuous board.
Future<Uint8List?> boardRecordingRgba(BoardController c, {int width = 1280, int height = 720}) async {
  if (!c.active || !c.isContinuous) return null;
  final view = c.localViewport ?? BoardViewportPos(0, 1.2 / kBoardContinuousLength);
  final items = c.scene.visibleItems;
  final spanX = boardContinuousSpanX(content: boardContentSpanX(items), presenter: view);
  final bottom = math.max(view.bottom, boardContentBottom(items, aspect: c.aspect, textHeight: c.textHeight));
  final win = boardRecordingWindow(view: view, spanX: spanX, aspect: c.aspect, extent: bottom, frameAspect: width / height);
  final winW = win.width, winH = win.height / c.aspect; // page widths
  if (winW <= 0 || winH <= 0) return null;
  final s = math.min(width / winW, height / winH); // px per page width
  final out = Size(winW * s, winH * s);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
  canvas.translate((width - out.width) / 2, (height - out.height) / 2);
  _paintRegion(canvas, c, win, out);
  final picture = rec.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
