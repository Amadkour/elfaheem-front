// lib/features/teacher/sessions/live/widgets/live_video_view.dart
//
// THE way the live room draws a video track (D-092; every VideoTrackRenderer of the room, the pre-join preview and
// the minimized box goes through it). Two problems of livekit_client 2.13.1's VideoTrackRenderer, found on the S24
// Ultra:
//
//   1. Rebuild cost. On Android / iOS its build() is `FutureBuilder(future: _initializeRenderer())` — a NEW future
//      on every build, and each one re-attaches the renderer (srcObject over the platform channel) and makes a new
//      track listener. The room rebuilt every renderer once a second (the session clock) and on every speaker change.
//      LiveVideoView hands Flutter the SAME renderer widget while the track / fit / mirror stay the same
//      (LiveStableChild), so a parent rebuild never reaches the renderer; a RepaintBoundary keeps the texture's
//      layer out of the parent's repaints.
//   2. Taps. For a LOCAL track on a phone it wraps the video in its own GestureDetector (onTapDown → focus /
//      exposure, a scale recognizer → zoom). That detector won every tap in the arena, so the room's "tap the stage
//      to show the bar" never fired over my own camera or my own screen share, and on a share each tap threw
//      `PlatformException(setFocusMode … Video capturer not compatible)` (a screen capturer has no focus). The
//      renderer is behind an IgnorePointer here: the tap goes to whoever wraps the view. Focus-on-tap stays where it
//      works — LiveCameraFocus.tap, a local CAMERA on Android / iOS, guarded (the first failure turns it off for the
//      run; no exception per tap).
library;

import 'dart:async';
import 'dart:developer' show log;
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

/// Builds its child once and hands Flutter that same instance until [identity] changes, so a rebuild of the parent
/// stops here (Flutter skips an identical widget). Generic so its rebuild count is testable without a Room.
class LiveStableChild extends StatefulWidget {
  const LiveStableChild({super.key, required this.identity, required this.builder});

  /// What the child depends on (compared item by item with ==).
  final List<Object?> identity;
  final WidgetBuilder builder;

  @override
  State<LiveStableChild> createState() => _LiveStableChildState();
}

class _LiveStableChildState extends State<LiveStableChild> {
  Widget? _child;
  List<Object?>? _identity;

  @override
  Widget build(BuildContext context) {
    final id = widget.identity;
    if (_child == null || !listEquals(_identity, id)) {
      _identity = List<Object?>.of(id);
      _child = widget.builder(context);
    }
    return _child!;
  }
}

/// A video track, drawn without the renderer's own gestures and without re-attaching on parent rebuilds.
class LiveVideoView extends StatelessWidget {
  const LiveVideoView(
    this.track, {
    super.key,
    this.fit = VideoViewFit.cover,
    this.mirror = VideoViewMirrorMode.auto,
    this.renderMode = VideoRenderMode.texture,
    this.cachedRenderer,
    this.autoDisposeRenderer = true,
  });

  final VideoTrack track;
  final VideoViewFit fit;

  /// auto: a local front camera is mirrored (the self-view), everything else is not.
  final VideoViewMirrorMode mirror;
  final VideoRenderMode renderMode;
  final rtc.RTCVideoRenderer? cachedRenderer;
  final bool autoDisposeRenderer;

  @override
  Widget build(BuildContext context) => LiveVideoShell(
        identity: [track, fit, mirror, renderMode, cachedRenderer, autoDisposeRenderer],
        builder: (_) => VideoTrackRenderer(
          track,
          fit: fit,
          mirrorMode: mirror,
          renderMode: renderMode,
          cachedRenderer: cachedRenderer,
          autoDisposeRenderer: autoDisposeRenderer,
        ),
      );
}

/// What LiveVideoView puts around the renderer — its own layer, no pointer, one instance per [identity] — on its
/// own so test/ui/live_self_view_layout_test.dart can check it with a stand-in renderer (no Room, no texture).
class LiveVideoShell extends StatelessWidget {
  const LiveVideoShell({super.key, required this.identity, required this.builder});

  final List<Object?> identity;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: IgnorePointer(child: LiveStableChild(identity: identity, builder: builder)),
      );
}

/// Tap-to-focus for this device's camera (Android / iOS), the one thing the renderer's own detector was good for.
class LiveCameraFocus {
  LiveCameraFocus._();

  static bool _off = false;

  /// True once a focus call failed on this device (it is not tried again until the app restarts).
  static bool get disabled => _off;

  /// Whether a tap on [track] may focus at all: a local camera on a phone (never a screen share, never the web).
  static bool supports(VideoTrack? track) =>
      !_off && !kIsWeb && lkPlatformIsMobile() && track is LocalVideoTrack && track.source == TrackSource.camera;

  /// Focus and expose at [local] inside a view of [size]. [mirrored]: the view is mirrored (a front camera), so the
  /// x is flipped back to the sensor's. Never throws; the first failure turns it off.
  static Future<void> tap(VideoTrack? track, Offset local, Size size, {bool mirrored = true}) async {
    if (!supports(track) || size.isEmpty) return;
    var x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    if (mirrored) x = 1 - x;
    final media = track!.mediaStreamTrack;
    try {
      await rtc.Helper.setFocusPoint(media, Point<double>(x, y));
      await rtc.Helper.setExposurePoint(media, Point<double>(x, y));
    } catch (e) {
      _off = true;
      log('[LIVE] tap to focus is not available here: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() => _off = false;
}
