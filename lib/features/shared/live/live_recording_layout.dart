// lib/features/shared/live/live_recording_layout.dart
//
// What a device recording draws, frame by frame (D-306). Pure: test/org/live_recording_layout_test.dart.
//
// The web recorder (web/recorder_compositor.js) draws ONE 1920×1080 canvas. Before D-306 it knew two sources only —
// this browser's own camera and its own screen share — so a meeting recorded on the web missed the other people's
// cameras, their shared screens and every whiteboard. Now room.dart describes the room as plain values ([RecSource]:
// the stage — a shared screen or the whiteboard — and the cameras that are ON, in the room's order, the speaker
// first) and [recordingLayout] turns that into tiles on the canvas, sent to the compositor as JSON
// ([RecLayout.toJson]) whenever the room changes:
//
//   stage shown    the stage fills the canvas, letterboxed in its own shape; the cameras ride in a column of
//                  16:9 thumbnails on the end side (right; left in Arabic), at most [kRecMaxThumbs] and "+N"
//   no stage       the cameras in a grid (1 → the whole canvas, 2 → side by side, 3–4 → 2×2, 5–6 → 3×2,
//                  7–9 → 3×3; more → the first 9 and "+N"), each cell 16:9 and centred, the last row centred
//   nothing        no tiles: the compositor draws its branded placeholder (who, what, how long)
//
// A camera that is off is not a tile (the recording shows the people who show themselves). Audio is not laid out:
// every voice is mixed into the recording whatever is on screen. Fit: "contain" for the stage (a screen or a page is
// never cropped), "auto" for a camera (the compositor crops a camera whose shape is close to its cell and letterboxes
// a phone held upright).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// The recording canvas.
const Size kRecCanvas = Size(1920, 1080);

/// Camera thumbnails beside a shared stage.
const int kRecMaxThumbs = 4;

/// Cameras in the grid when nothing is shared.
const int kRecMaxGrid = 9;

const double _kMargin = 24, _kGap = 16, _kThumbW = 320;

enum RecSourceKind { camera, screen, board }

/// One thing the recording can draw: [label] is the compositor's source name ('camera' = this device's camera,
/// 'screen' = this device's share, 'board' = the whiteboard page, 'rcam_<track sid>' / 'rscreen_<track sid>').
class RecSource {
  const RecSource({required this.label, required this.kind, this.name = '', this.speaking = false});

  final String label;
  final RecSourceKind kind;
  final String name;
  final bool speaking;
}

/// A source placed on the canvas (pixels of [kRecCanvas]).
class RecTile {
  const RecTile({
    required this.label,
    required this.kind,
    required this.rect,
    this.name = '',
    this.main = false,
    this.speaking = false,
  });

  final String label;
  final RecSourceKind kind;
  final Rect rect;
  final String name;

  /// The stage (or the only camera).
  final bool main;
  final bool speaking;

  String get fit => kind == RecSourceKind.camera ? 'auto' : 'contain';

  Map<String, Object> toMap() => {
        'l': label,
        'k': kind.name,
        'x': rect.left.round(),
        'y': rect.top.round(),
        'w': rect.width.round(),
        'h': rect.height.round(),
        'f': fit,
        if (name.isNotEmpty) 'n': name,
        if (main) 'm': true,
        if (speaking) 's': true,
      };

  @override
  String toString() => 'RecTile($label ${rect.left.round()},${rect.top.round()} ${rect.width.round()}x${rect.height.round()})';
}

class RecLayout {
  const RecLayout({this.tiles = const [], this.more = 0, this.rtl = false});

  final List<RecTile> tiles;

  /// Cameras that are on but did not fit ("+N").
  final int more;
  final bool rtl;

  bool get isEmpty => tiles.isEmpty;

  /// The labels the compositor must hold a source for.
  Set<String> get labels => {for (final t in tiles) t.label};

  String toJson() => jsonEncode({
        'v': 1,
        'cw': kRecCanvas.width.round(),
        'ch': kRecCanvas.height.round(),
        'tiles': [for (final t in tiles) t.toMap()],
        if (more > 0) 'more': more,
        if (rtl) 'rtl': true,
      });
}

/// The device recorder starts by itself when the room opens (D-306): only for a course session's teacher with the
/// session's record switch on and a client-mode run. A meeting (a "Meet now" or a calendar meeting, never tied to a
/// course session) ALWAYS opens with the recording stopped — its creator presses Record — whoever opens it, a
/// teacher included.
bool liveRecordsAtStart({
  required bool isMeeting,
  required bool isTeacher,
  required bool recordingEnabled,
  required bool deviceRecorder,
}) =>
    !isMeeting && isTeacher && recordingEnabled && deviceRecorder;

/// The canvas for [stage] (a shared screen or the board; null = nothing shared) and [cameras] (on, in order).
RecLayout recordingLayout({RecSource? stage, List<RecSource> cameras = const [], bool rtl = false, Size canvas = kRecCanvas}) {
  final cams = [for (final c in cameras) if (c.kind == RecSourceKind.camera) c];
  if (stage != null && stage.kind != RecSourceKind.camera) return _stageLayout(stage, cams, rtl, canvas);
  if (cams.isEmpty) return RecLayout(rtl: rtl);
  return _gridLayout(cams, rtl, canvas);
}

RecLayout _stageLayout(RecSource stage, List<RecSource> cams, bool rtl, Size canvas) {
  if (cams.isEmpty) {
    return RecLayout(rtl: rtl, tiles: [
      RecTile(label: stage.label, kind: stage.kind, rect: Offset.zero & canvas, name: stage.name, main: true),
    ]);
  }
  final shown = cams.take(kRecMaxThumbs).toList();
  final more = cams.length - shown.length;
  final thumbH = _kThumbW * 9 / 16;
  final stageW = canvas.width - _kMargin * 2 - _kGap - _kThumbW;
  final stageLeft = rtl ? _kMargin + _kThumbW + _kGap : _kMargin;
  final colLeft = rtl ? _kMargin : _kMargin + stageW + _kGap;
  final tiles = <RecTile>[
    RecTile(
      label: stage.label,
      kind: stage.kind,
      rect: Rect.fromLTWH(stageLeft, _kMargin, stageW, canvas.height - _kMargin * 2),
      name: stage.name,
      main: true,
    ),
  ];
  // The column is centred on the canvas's height (room for the "+N" chip under it).
  final chip = more > 0 ? 56.0 : 0.0;
  final colH = shown.length * thumbH + (shown.length - 1) * _kGap + chip;
  var y = math.max(_kMargin, (canvas.height - colH) / 2);
  for (final c in shown) {
    tiles.add(RecTile(label: c.label, kind: c.kind, rect: Rect.fromLTWH(colLeft, y, _kThumbW, thumbH), name: c.name, speaking: c.speaking));
    y += thumbH + _kGap;
  }
  return RecLayout(tiles: tiles, more: more, rtl: rtl);
}

/// Columns × rows for [n] cameras.
(int, int) recordingGridShape(int n) {
  if (n <= 1) return (1, 1);
  if (n == 2) return (2, 1);
  if (n <= 4) return (2, 2);
  if (n <= 6) return (3, 2);
  return (3, 3);
}

RecLayout _gridLayout(List<RecSource> cams, bool rtl, Size canvas) {
  if (cams.length == 1) {
    final c = cams.first;
    return RecLayout(rtl: rtl, tiles: [
      RecTile(label: c.label, kind: c.kind, rect: Offset.zero & canvas, name: c.name, main: true, speaking: c.speaking),
    ]);
  }
  final shown = cams.take(kRecMaxGrid).toList();
  final more = cams.length - shown.length;
  final (cols, rows) = recordingGridShape(shown.length);
  final areaW = canvas.width - _kMargin * 2, areaH = canvas.height - _kMargin * 2;
  final cellW = math.min((areaW - (cols - 1) * _kGap) / cols, (areaH - (rows - 1) * _kGap) / rows * 16 / 9);
  final cellH = cellW * 9 / 16;
  final gridH = rows * cellH + (rows - 1) * _kGap;
  final top = (canvas.height - gridH) / 2;
  final tiles = <RecTile>[];
  for (var i = 0; i < shown.length; i++) {
    final row = i ~/ cols;
    final inRow = row == rows - 1 ? shown.length - row * cols : cols; // the last row may be short: centred
    final rowW = inRow * cellW + (inRow - 1) * _kGap;
    final rowLeft = (canvas.width - rowW) / 2;
    var col = i % cols;
    if (rtl) col = inRow - 1 - col; // the first camera on the start side
    final c = shown[i];
    tiles.add(RecTile(
      label: c.label,
      kind: c.kind,
      rect: Rect.fromLTWH(rowLeft + col * (cellW + _kGap), top + row * (cellH + _kGap), cellW, cellH),
      name: c.name,
      speaking: c.speaking,
    ));
  }
  return RecLayout(tiles: tiles, more: more, rtl: rtl);
}
