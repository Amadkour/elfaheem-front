// lib/features/live/live_self_view.dart
//
// The live room's self-view (D-092): the rules, with no widget and no LiveKit in them, so they are unit-tested
// (test/org/live_self_view_test.dart). The widgets are in
// lib/features/live/room/widgets/self_view_pip.dart; room.dart wires them.
//
//   where     selfViewSpot — the box (PiP), the stage, the "Show self view" chip or nothing. Never the stage AND
//             the box at once (the "my camera twice" fix stays).
//   size      selfViewBoxSize — box (3:4 on phones, 16:9 on wide screens) or circle, small or medium, never more than
//             a share of the stage.
//   position  the box hugs the left or right edge (physical) at a fraction of the free height; a drop snaps to the
//             nearer side, and to a corner when it lands near one. The keep-out insets carry the badge column, the
//             thumbnail strip, the whiteboard dock and the bottom badges, so the box never covers them; a smaller
//             stage (keyboard, chat column, rotation) keeps the box at the same side and fraction.
//   prefs     shape · size · side · height · "fill the stage while I'm alone", remembered on the device
//             (SelfViewStore, SharedPreferences). "Hide self view" is per room on purpose (Zoom does the same): a
//             hidden view never surprises the next class.
//   controls  liveControlsAfterTap / liveControlsAfterIdle — the bar's show / hide rules.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SelfViewShape { box, circle }

enum SelfViewSize { small, medium }

/// The physical edge the box hugs (the room's badge column is on the physical right in both languages).
enum SelfViewSide { left, right }

/// Where the self-view is drawn.
enum SelfViewSpot {
  /// The camera is off (or the room draws no video): nothing.
  none,

  /// The floating box / circle over the stage.
  box,

  /// The camera fills the stage (alone and asked for it, or swapped with the stage's content).
  stage,

  /// "Hide self view": only the small chip that brings it back.
  hiddenChip,
}

/// Where the self-view goes. [stageHasOther]: someone's video, a share or a board fills the stage. [swapped]: the
/// person tapped the box to put themselves on the stage (the stage's content then sits in the box). [aloneOnStage]:
/// the remembered choice "fill the stage while I'm alone". [parked]: the room is minimized and draws no video.
SelfViewSpot selfViewSpot({
  required bool camOn,
  required bool stageHasOther,
  bool swapped = false,
  bool hidden = false,
  bool aloneOnStage = false,
  bool parked = false,
}) {
  if (!camOn || parked) return SelfViewSpot.none;
  if (swapped) return SelfViewSpot.stage;
  if (!stageHasOther && aloneOnStage) return SelfViewSpot.stage;
  if (hidden) return SelfViewSpot.hiddenChip;
  return SelfViewSpot.box;
}

/// Width from which the box is landscape (16:9, a laptop camera) instead of portrait (3:4, a phone held upright).
const double kSelfViewWideBreakpoint = 720;

/// The box's size on a stage of [stage]: box 3:4 on phones (96 × 128 / 124 × 165), 16:9 on wide stages (200 × 113 /
/// 264 × 149); circle 92 / 120 on phones, 120 / 156 on wide stages. Scaled down so it never takes more than 42 % of
/// the stage's width or 34 % of its height.
Size selfViewBoxSize({required SelfViewShape shape, required SelfViewSize size, required Size stage}) {
  final wide = stage.width >= kSelfViewWideBreakpoint;
  final medium = size == SelfViewSize.medium;
  final Size base;
  if (shape == SelfViewShape.circle) {
    final d = wide ? (medium ? 156.0 : 120.0) : (medium ? 120.0 : 92.0);
    base = Size(d, d);
  } else {
    base = wide ? (medium ? const Size(264, 149) : const Size(200, 113)) : (medium ? const Size(124, 165) : const Size(96, 128));
  }
  if (stage.width <= 0 || stage.height <= 0) return base;
  final k = math.min(1.0, math.min(stage.width * 0.42 / base.width, stage.height * 0.34 / base.height));
  return Size(base.width * k, base.height * k);
}

/// What the box keeps clear of: [base] on every side, plus [topRight] / [topLeft] more at the top of that side (the
/// badge column on the physical right; nothing on the left by default).
@immutable
class SelfViewKeepOut {
  const SelfViewKeepOut({this.base = const EdgeInsets.all(12), this.topRight = 0, this.topLeft = 0});

  final EdgeInsets base;
  final double topRight;
  final double topLeft;

  double topFor(SelfViewSide side) => base.top + (side == SelfViewSide.right ? topRight : topLeft);

  @override
  bool operator ==(Object other) =>
      other is SelfViewKeepOut && other.base == base && other.topRight == topRight && other.topLeft == topLeft;

  @override
  int get hashCode => Object.hash(base, topRight, topLeft);
}

/// The vertical range the box's top may take on [side]: (min, max); max ≥ min.
(double, double) selfViewYRange({required Size stage, required Size box, required SelfViewKeepOut keepOut, required SelfViewSide side}) {
  final top = keepOut.topFor(side);
  final bottom = stage.height - keepOut.base.bottom - box.height;
  if (bottom >= top) return (top, bottom);
  // A stage too short for both keep-outs: one spot, as low as the stage allows (never above its top edge).
  final y = math.max(0.0, math.min(bottom, stage.height - box.height));
  return (y, y);
}

/// The box's top-left on [stage] for a side and a height fraction ([y] 0 = highest, 1 = lowest).
Offset selfViewOffset({
  required Size stage,
  required Size box,
  required SelfViewKeepOut keepOut,
  required SelfViewSide side,
  required double y,
}) {
  final x = side == SelfViewSide.left
      ? keepOut.base.left
      : math.max(keepOut.base.left, stage.width - keepOut.base.right - box.width);
  final (minY, maxY) = selfViewYRange(stage: stage, box: box, keepOut: keepOut, side: side);
  return Offset(x, minY + (maxY - minY) * y.clamp(0.0, 1.0));
}

/// A drop within this distance of the top or bottom end snaps into the corner.
const double kSelfViewCornerSnap = 56;

/// Where a dragged box settles: the side its (fling-projected) centre is on, and the height fraction — a corner when
/// it lands within [kSelfViewCornerSnap] of the top or bottom end. [topLeft] is where the finger left it, [velocity]
/// the fling in px/s (projected 120 ms ahead, like iOS's picture in picture).
({SelfViewSide side, double y}) selfViewSnap({
  required Size stage,
  required Size box,
  required SelfViewKeepOut keepOut,
  required Offset topLeft,
  Offset velocity = Offset.zero,
}) {
  final projected = topLeft + velocity * 0.12;
  final centreX = projected.dx + box.width / 2;
  final side = centreX < stage.width / 2 ? SelfViewSide.left : SelfViewSide.right;
  final (minY, maxY) = selfViewYRange(stage: stage, box: box, keepOut: keepOut, side: side);
  final span = maxY - minY;
  if (span <= 0) return (side: side, y: 1.0);
  final py = projected.dy.clamp(minY, maxY);
  if (py - minY <= kSelfViewCornerSnap) return (side: side, y: 0.0);
  if (maxY - py <= kSelfViewCornerSnap) return (side: side, y: 1.0);
  return (side: side, y: ((py - minY) / span).clamp(0.0, 1.0));
}

/// The box while a finger moves it: anywhere on the stage, inside its edges.
Offset selfViewDragClamp({required Size stage, required Size box, required Offset topLeft}) => Offset(
      topLeft.dx.clamp(0.0, math.max(0.0, stage.width - box.width)),
      topLeft.dy.clamp(0.0, math.max(0.0, stage.height - box.height)),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Over the shared content (D-105)
// ─────────────────────────────────────────────────────────────────────────────
//
// A shared screen is drawn `contain` inside the share view: a phone's portrait screen is a narrow column in the middle
// of a laptop's stage, a laptop's 16:9 screen a band across a phone's. A camera box placed by the stage's edges then
// floated in the empty bars beside or under the picture — never in front of the shared content. While a share fills
// the stage the presenter's camera (viewers, D-094) and the presenter's own self-view hug the corner of the PICTURE
// instead, scaled down when the picture is small.

/// Where the share view draws the video on its stage (the room's _PremiumScreenShareView: 12 px around, the presenter
/// bar's 72 px under it, a 1.5 px border).
const EdgeInsets kShareVideoInsets = EdgeInsets.fromLTRB(13.5, 13.5, 13.5, 73.5);

/// The shared picture on [stage]: a frame of [aspect] (width / height) fitted `contain` into the share view's video
/// area. Null when the aspect is unknown or the stage has no room.
Rect? shareContentRect(Size stage, double? aspect, {EdgeInsets insets = kShareVideoInsets}) {
  if (aspect == null || !aspect.isFinite || aspect <= 0) return null;
  final area = insets.deflateRect(Offset.zero & stage);
  if (area.width <= 0 || area.height <= 0) return null;
  final w = math.min(area.width, area.height * aspect);
  final h = w / aspect;
  return Rect.fromCenter(center: area.center, width: w, height: h);
}

/// The gap between the picture's edge and the box.
const double kOverContentInset = 10;

/// The box over the picture takes at most this share of the picture's width / height (the rest stays readable).
const double kOverContentMaxWidth = 0.55;
const double kOverContentMaxHeight = 0.45;

/// Below this (its shorter side, px) a box over the picture is too small to see a face: it stays by the stage's edges.
const double kOverContentMinSide = 52;

/// The box and its keep-out while it floats over the shared picture [content] (stage coordinates): the keep-out
/// becomes the picture's inside (inset [kOverContentInset], never past [keepOut]'s own limits) and the box shrinks to
/// at most [kOverContentMaxWidth] × [kOverContentMaxHeight] of it. Null — keep the stage's placement — when the
/// picture is unknown or too small for a box of at least [kOverContentMinSide].
({Size box, SelfViewKeepOut keepOut})? selfViewOverContent({
  required Size stage,
  required Size box,
  required SelfViewKeepOut keepOut,
  required Rect? content,
}) {
  if (content == null || content.isEmpty || box.isEmpty || stage.isEmpty) return null;
  final inner = Rect.fromLTRB(
    math.max(content.left + kOverContentInset, keepOut.base.left),
    math.max(content.top + kOverContentInset, keepOut.base.top),
    math.min(content.right - kOverContentInset, stage.width - keepOut.base.right),
    math.min(content.bottom - kOverContentInset, stage.height - keepOut.base.bottom),
  );
  if (inner.width <= 0 || inner.height <= 0) return null;
  final k = math.min(
    1.0,
    math.min(inner.width * kOverContentMaxWidth / box.width, inner.height * kOverContentMaxHeight / box.height),
  );
  final scaled = Size(box.width * k, box.height * k);
  if (scaled.shortestSide < kOverContentMinSide) return null;
  return (
    box: scaled,
    keepOut: SelfViewKeepOut(
      base: EdgeInsets.fromLTRB(inner.left, inner.top, stage.width - inner.right, stage.height - inner.bottom),
    ),
  );
}

/// The gap between a floating box and a scrollbar's hit strip beside it (px).
const double kClearOfRailGap = 4;

/// D-109: a whiteboard's vertical scrollbar [rail] (its hit strip, stage coordinates) runs down beside the column a
/// box of [width] rests in — the page's end edge, where the box sits on the page's corner (D-105): the keep-out grows
/// on that side so the box rests beside the strip, never on it (the thumb stays whole and a drag there scrolls). A
/// rail that the box's column does not reach, or a stage with no room left beside it, keeps [keepOut].
SelfViewKeepOut selfViewClearOfRail({
  required SelfViewKeepOut keepOut,
  required Size stage,
  required double width,
  required Rect? rail,
}) {
  if (rail == null || rail.isEmpty || width <= 0 || stage.isEmpty) return keepOut;
  final b = keepOut.base;
  var left = b.left, right = b.right;
  // The right-hand column: [stage.width - right - width, stage.width - right].
  if (rail.left < stage.width - b.right && rail.right > stage.width - b.right - width) {
    right = math.max(right, stage.width - rail.left + kClearOfRailGap);
  }
  // The left-hand column (Arabic: the rail is on the page's left edge).
  if (rail.right > b.left && rail.left < b.left + width) {
    left = math.max(left, rail.right + kClearOfRailGap);
  }
  if (left == b.left && right == b.right) return keepOut;
  if (stage.width - left - right < width) return keepOut;
  return SelfViewKeepOut(base: b.copyWith(left: left, right: right), topRight: keepOut.topRight, topLeft: keepOut.topLeft);
}

// ─────────────────────────────────────────────────────────────────────────────
// Preferences (device-local)
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class SelfViewPrefs {
  const SelfViewPrefs({
    this.shape = SelfViewShape.box,
    this.size = SelfViewSize.small,
    this.side = SelfViewSide.right,
    this.y = 1,
    this.aloneOnStage = false,
  });

  final SelfViewShape shape;
  final SelfViewSize size;
  final SelfViewSide side;

  /// 0 = top of the free range, 1 = bottom.
  final double y;

  /// Alone on the stage, the camera fills it (else the box floats over the waiting card).
  final bool aloneOnStage;

  SelfViewPrefs copyWith({SelfViewShape? shape, SelfViewSize? size, SelfViewSide? side, double? y, bool? aloneOnStage}) =>
      SelfViewPrefs(
        shape: shape ?? this.shape,
        size: size ?? this.size,
        side: side ?? this.side,
        y: y ?? this.y,
        aloneOnStage: aloneOnStage ?? this.aloneOnStage,
      );

  Map<String, Object> toJson() =>
      {'shape': shape.name, 'size': size.name, 'side': side.name, 'y': y, 'alone_on_stage': aloneOnStage};

  /// Unknown or missing fields fall back to the defaults (an older or damaged value never throws).
  factory SelfViewPrefs.fromJson(Object? raw) {
    if (raw is! Map) return const SelfViewPrefs();
    T pick<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.firstWhere((e) => e.name == v, orElse: () => fallback);
    final y = raw['y'];
    return SelfViewPrefs(
      shape: pick(SelfViewShape.values, raw['shape'], SelfViewShape.box),
      size: pick(SelfViewSize.values, raw['size'], SelfViewSize.small),
      side: pick(SelfViewSide.values, raw['side'], SelfViewSide.right),
      y: y is num && y.isFinite ? y.toDouble().clamp(0.0, 1.0) : 1.0,
      aloneOnStage: raw['alone_on_stage'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SelfViewPrefs &&
      other.shape == shape &&
      other.size == size &&
      other.side == side &&
      other.y == y &&
      other.aloneOnStage == aloneOnStage;

  @override
  int get hashCode => Object.hash(shape, size, side, y, aloneOnStage);

  @override
  String toString() => 'SelfViewPrefs(${toJson()})';
}

/// The remembered self-view (one per device): the room, the pre-join page and the box all read it.
class SelfViewStore extends ValueNotifier<SelfViewPrefs> {
  SelfViewStore._() : super(const SelfViewPrefs());

  static final SelfViewStore instance = SelfViewStore._();

  static const String storageKey = 'live.self_view.v1';

  bool _loaded = false;

  /// Reads the saved value once (later calls do nothing). Storage errors keep the defaults.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(storageKey);
      if (raw != null) value = SelfViewPrefs.fromJson(jsonDecode(raw));
    } catch (_) {
      // Private window / blocked storage: the defaults.
    }
  }

  /// Changes the value now and saves it in the background.
  Future<void> update(SelfViewPrefs next) async {
    if (next == value) return;
    value = next;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(storageKey, jsonEncode(next.toJson()));
    } catch (_) {
      // Not saved: the room still uses it until the app closes.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    value = const SelfViewPrefs();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The controls bar: show / hide
// ─────────────────────────────────────────────────────────────────────────────

/// After a tap on the stage: hidden → shown (and the hide timer starts again); shown → hidden when the bar
/// auto-hides here (a phone, nothing being drawn), else it stays and the timer starts again.
({bool visible, bool restartTimer}) liveControlsAfterTap({required bool visible, required bool autoHide}) {
  if (visible && autoHide) return (visible: false, restartTimer: false);
  return (visible: true, restartTimer: true);
}

/// When the hide timer fires: hidden only where the bar auto-hides.
bool liveControlsAfterIdle({required bool visible, required bool autoHide}) => visible && !autoHide;
