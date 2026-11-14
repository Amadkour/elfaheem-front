// lib/features/live/live_presenter_cam.dart
//
// The presenter's camera over a share (D-094): the rules, with no widget and no LiveKit in them, so they are
// unit-tested (test/org/live_presenter_cam_test.dart). The widgets are in
// lib/features/live/room/widgets/presenter_cam_box.dart; room.dart wires them.
//
// While a screen share or the whiteboard fills the stage, the room used to draw no camera at all (the thumbnail strip
// is off then), so a viewer saw the content only and adaptive stream paused the presenter's camera nobody drew.
// Now every viewer gets the presenter's camera in a floating box (like Zoom / Meet), plus up to a few other cameras
// as small bubbles next to it, inside the device's video budget.
//
//   what      presenterCamPlan — which camera floats in the box (the presenter's, or one the viewer tapped), which
//             go in the bubble row and how many are left out ("+n"). The presenter themself gets nothing (they have
//             their own self-view); a camera that is off is never drawn (no empty box).
//   size      presenterDockSize — the box (the self-view's sizes) with the bubble row on top or under it.
//   where     presenterCamSpot — the remembered side / height, by default the side opposite my self-view, moved to
//             the other end or side when it would overlap my self-view (the two boxes never cover each other).
//   prefs     shape · size · side · height, remembered on the device (PresenterCamStore). "Minimize to a name" is
//             per room, like "Hide self view".
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/features/live/live_self_view.dart';

/// One remote camera the room could float: who, and whether its video can be drawn now (published, not muted,
/// received — an audio-only room or a camera turned off says false).
@immutable
class LiveCamFacts {
  const LiveCamFacts(this.identity, {this.camOn = true});

  final String identity;
  final bool camOn;
}

/// What floats over the share.
@immutable
class PresenterCamPlan {
  const PresenterCamPlan({this.main, this.bubbles = const [], this.more = 0});

  static const PresenterCamPlan none = PresenterCamPlan();

  /// The camera in the box (null: no box).
  final String? main;

  /// The cameras drawn as small bubbles next to the box, in stage order.
  final List<String> bubbles;

  /// Cameras that are on but not drawn (past the video budget): the "+n" bubble.
  final int more;

  /// Anything is drawn.
  bool get any => main != null || bubbles.isNotEmpty || more > 0;

  @override
  bool operator ==(Object other) =>
      other is PresenterCamPlan && other.main == main && listEquals(other.bubbles, bubbles) && other.more == more;

  @override
  int get hashCode => Object.hash(main, Object.hashAll(bubbles), more);

  @override
  String toString() => 'PresenterCamPlan(main: $main, bubbles: $bubbles, more: $more)';
}

/// The most bubbles drawn next to the box (the rest is "+n").
const int kPresenterCamMaxBubbles = 3;

/// What floats over the stage. [presenter]: whoever fills the stage with a screen share or a whiteboard (null: no
/// share is on the stage — the normal thumbnail strip is in charge). [me]: this device's identity. [cams]: the remote
/// cameras in stage order (the presenter's may be among them). [pinned]: a camera the viewer tapped into the box.
/// [suppressed]: the room draws no floating camera now (minimized without video, or my own camera swapped onto the
/// stage). [budget]: liveVideoBudget — how many remote videos this screen decodes at once; the share on the stage is
/// one of them.
PresenterCamPlan presenterCamPlan({
  required String? presenter,
  required String me,
  required List<LiveCamFacts> cams,
  String? pinned,
  bool suppressed = false,
  int budget = 4,
  int maxBubbles = kPresenterCamMaxBubbles,
}) {
  if (presenter == null || presenter.isEmpty || suppressed) return PresenterCamPlan.none;
  // The presenter sees their own content and their own self-view: nothing new.
  if (presenter == me) return PresenterCamPlan.none;
  final seen = <String>{};
  final on = <String>[
    for (final c in cams)
      if (c.camOn && c.identity.isNotEmpty && c.identity != me && seen.add(c.identity)) c.identity,
  ];
  if (on.isEmpty) return PresenterCamPlan.none;
  String? main;
  if (pinned != null && on.contains(pinned)) {
    main = pinned;
  } else if (on.contains(presenter)) {
    main = presenter;
  }
  // The presenter's bubble comes first (a viewer who pinned someone else finds them at once).
  final rest = [
    if (main != presenter && on.contains(presenter)) presenter,
    for (final id in on)
      if (id != main && id != presenter) id,
  ];
  var videos = math.max(0, budget - 1 - (main == null ? 0 : 1)); // the share is one video
  // No box but past the budget anyway: never the "+n" bubble alone.
  if (main == null && videos == 0) return PresenterCamPlan.none;
  videos = math.min(videos, maxBubbles);
  final bubbles = rest.take(videos).toList();
  return PresenterCamPlan(main: main, bubbles: bubbles, more: rest.length - bubbles.length);
}

/// The side opposite [side].
SelfViewSide otherSide(SelfViewSide side) => side == SelfViewSide.left ? SelfViewSide.right : SelfViewSide.left;

/// A bubble's diameter on a stage [stageWidth] wide.
double presenterBubbleSize(double stageWidth) => stageWidth >= kSelfViewWideBreakpoint ? 52 : 44;

/// The gap between bubbles, and between the bubble row and the box.
const double kPresenterBubbleGap = 6;
const double kPresenterRowGap = 8;

/// The width of a row of [count] bubbles (the "+n" one included).
double presenterRowWidth(int count, double bubble) => count <= 0 ? 0 : count * bubble + (count - 1) * kPresenterBubbleGap;

/// The floating unit: [box] (Size.zero: no box) with a row of [bubbles] bubbles (the "+n" one included) above or
/// under it.
Size presenterDockSize({required Size box, required int bubbles, required double bubble}) {
  final row = presenterRowWidth(bubbles, bubble);
  if (bubbles <= 0) return box;
  if (box.isEmpty) return Size(row, bubble);
  return Size(math.max(box.width, row), box.height + kPresenterRowGap + bubble);
}

/// The self-view box's rectangle on [stage] (what the presenter's camera keeps clear of).
Rect selfViewRect({required Size stage, required SelfViewPrefs prefs, required SelfViewKeepOut keepOut}) {
  final box = selfViewBoxSize(shape: prefs.shape, size: prefs.size, stage: stage);
  return selfViewOffset(stage: stage, box: box, keepOut: keepOut, side: prefs.side, y: prefs.y) & box;
}

/// The "Show self view" chip's rectangle while the self-view is hidden (its width is the chip's usual one).
Rect selfViewChipRect({required Size stage, required SelfViewPrefs prefs, required SelfViewKeepOut keepOut, double width = 190}) {
  const chip = Size(0, 40);
  final at = selfViewOffset(stage: stage, box: chip, keepOut: keepOut, side: prefs.side, y: prefs.y);
  final left = prefs.side == SelfViewSide.left ? keepOut.base.left : stage.width - keepOut.base.right - width;
  return Rect.fromLTWH(left, at.dy, width, chip.height);
}

/// The space kept between the two boxes.
const double kPresenterCamClearance = 10;

/// Where the presenter's camera rests: [side] / [y] as remembered ([side] null: never moved — the side opposite
/// [selfSide]); when that would overlap [avoid] (my self-view), the other end of the same side, then the same height on
/// the other side, then the other end there. Nothing fits (a tiny stage): the first choice.
({SelfViewSide side, double y}) presenterCamSpot({
  required Size stage,
  required Size unit,
  required SelfViewKeepOut keepOut,
  required SelfViewSide? side,
  required double y,
  required SelfViewSide selfSide,
  Rect? avoid,
}) {
  final first = side ?? otherSide(selfSide);
  final yy = y.clamp(0.0, 1.0);
  final end = yy >= 0.5 ? 0.0 : 1.0;
  final tries = <({SelfViewSide side, double y})>[
    (side: first, y: yy),
    (side: first, y: end),
    (side: otherSide(first), y: yy),
    (side: otherSide(first), y: end),
  ];
  if (avoid == null || avoid.isEmpty) return tries.first;
  final keep = avoid.inflate(kPresenterCamClearance);
  for (final t in tries) {
    final at = selfViewOffset(stage: stage, box: unit, keepOut: keepOut, side: t.side, y: t.y);
    if (!(at & unit).overlaps(keep)) return t;
  }
  return tries.first;
}

/// The bubble row goes on the stage's side of the box: above it in the lower half, under it in the upper half.
bool presenterRowAbove(double y) => y >= 0.5;

// ─────────────────────────────────────────────────────────────────────────────
// Preferences (device-local)
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class PresenterCamPrefs {
  const PresenterCamPrefs({
    this.shape = SelfViewShape.box,
    this.size = SelfViewSize.small,
    this.side,
    this.y = 1,
  });

  final SelfViewShape shape;
  final SelfViewSize size;

  /// Null until the box is first moved: it then sits opposite the self-view.
  final SelfViewSide? side;

  /// 0 = top of the free range, 1 = bottom.
  final double y;

  PresenterCamPrefs copyWith({SelfViewShape? shape, SelfViewSize? size, SelfViewSide? side, double? y}) =>
      PresenterCamPrefs(shape: shape ?? this.shape, size: size ?? this.size, side: side ?? this.side, y: y ?? this.y);

  /// The self-view options sheet edits shape and size through SelfViewPrefs.
  SelfViewPrefs get asSelfViewPrefs => SelfViewPrefs(shape: shape, size: size, side: side ?? SelfViewSide.left, y: y);

  Map<String, Object> toJson() => {'shape': shape.name, 'size': size.name, 'side': ?side?.name, 'y': y};

  /// Unknown or missing fields fall back to the defaults (an older or damaged value never throws).
  factory PresenterCamPrefs.fromJson(Object? raw) {
    if (raw is! Map) return const PresenterCamPrefs();
    T? pick<T extends Enum>(List<T> values, Object? v) => values.where((e) => e.name == v).firstOrNull;
    final y = raw['y'];
    return PresenterCamPrefs(
      shape: pick(SelfViewShape.values, raw['shape']) ?? SelfViewShape.box,
      size: pick(SelfViewSize.values, raw['size']) ?? SelfViewSize.small,
      side: pick(SelfViewSide.values, raw['side']),
      y: y is num && y.isFinite ? y.toDouble().clamp(0.0, 1.0) : 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PresenterCamPrefs && other.shape == shape && other.size == size && other.side == side && other.y == y;

  @override
  int get hashCode => Object.hash(shape, size, side, y);

  @override
  String toString() => 'PresenterCamPrefs(${toJson()})';
}

/// The remembered presenter's-camera box (one per device).
class PresenterCamStore extends ValueNotifier<PresenterCamPrefs> {
  PresenterCamStore._() : super(const PresenterCamPrefs());

  static final PresenterCamStore instance = PresenterCamStore._();

  static const String storageKey = 'live.presenter_cam.v1';

  bool _loaded = false;

  /// Reads the saved value once (later calls do nothing). Storage errors keep the defaults.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(storageKey);
      if (raw != null) value = PresenterCamPrefs.fromJson(jsonDecode(raw));
    } catch (_) {
      // Private window / blocked storage: the defaults.
    }
  }

  /// Changes the value now and saves it in the background.
  Future<void> update(PresenterCamPrefs next) async {
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
    value = const PresenterCamPrefs();
  }
}
