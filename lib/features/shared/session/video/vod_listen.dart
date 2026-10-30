// Listen-only (D-104): the lecture keeps playing as sound while the person uses the rest of the app, with the phone
// screen allowed to sleep.
//
//   VideoPlayerScreen  "Listen only" hands its controller over ([VodListenHandoff]) and closes; nothing is disposed,
//                      so no second POST …/play is made (that call counts a view).
//   VodListenSession   holds the controller while the bar is on screen: play / pause, ±10 s, scrub, the resume
//                      position every 5 s and on leaving the app (VodResume), the 75 % "watched" mark, wakelock off.
//                      It switches to the lecture's audio track (else the lightest video tier) so no picture is
//                      decoded for nobody, and remembers the stream to go back to.
//   VodListenLayer     (vod_listen_layer.dart) draws the bar at the top of the app in MaterialApp.builder; Expand
//                      pushes the player again with the same controller ([VodListenSession.takeBack]).
//
// One sound at a time (MediaFocus): opening another lecture's player or joining a live room stops the bar; signing
// out stops it too. Nothing is stored but the resume position (as the player already did).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/media_focus.dart';
import '../../../student/courses/details/course_detail_provider.dart';
import '../../../student/courses/security/device_id_service.dart';
import '../material/session_material_model.dart';
import 'vod_player_parts.dart';

/// Opens and initializes a player for [v] at [at] (clamped into the stream), with [speed] (and [volume] off phones).
/// Throws when the stream does not open; the half-opened controller is disposed then.
Future<VideoPlayerController> openVodController(
  MaterialVariant v, {
  Duration at = Duration.zero,
  double speed = 1.0,
  double? volume,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final url = v.url;
  if (url == null || url.isEmpty) throw StateError('no stream url');
  // Mobile: stream links only work with this device's id header. Web: a <video> element can't send headers (the
  // link carries ?d=…); the offline copy's loopback server needs none.
  final c = VideoPlayerController.networkUrl(
    Uri.parse(url),
    httpHeaders: (kIsWeb || url.startsWith('http://127.0.0.1'))
        ? const <String, String>{}
        : await DeviceIdService.instance.headers(),
    videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
  );
  try {
    await c.initialize().timeout(timeout);
    if (c.value.hasError) throw StateError(c.value.errorDescription ?? 'stream error');
    final pos = VodCarry(position: at, playing: false).seekIn(c.value.duration);
    if (pos > Duration.zero) await c.seekTo(pos);
    await c.setPlaybackSpeed(speed);
    if (volume != null) await c.setVolume(volume);
    return c;
  } catch (_) {
    unawaited(c.dispose().catchError((Object _) {}));
    rethrow;
  }
}

/// Everything the player hands to the bar and gets back on Expand.
class VodListenHandoff {
  VodListenHandoff({
    required this.controller,
    required this.material,
    required this.current,
    required this.variant,
    this.playlist,
    this.speed = 1.0,
    this.captionsOn = false,
    this.isOffline = false,
    this.downloaded = false,
    this.viewsNote,
    this.completionSent = false,
    this.progress,
  });

  /// The playing controller (replaced when the bar switched to the audio track).
  VideoPlayerController controller;

  /// The stream [controller] plays.
  MaterialVariant variant;

  /// The stream the player showed before the bar switched (null: no switch) — Expand goes back to it.
  MaterialVariant? returnTo;

  /// [controller] is not the player's own any more (its captions file was not attached).
  bool swapped = false;

  /// The lecture with its play links (the player's resolved model) and as it was listed.
  final SessionMaterialModel material, current;
  final List<SessionMaterialModel>? playlist;
  final double speed;
  final bool captionsOn, isOffline, downloaded;
  final String? viewsNote;
  bool completionSent;

  /// The app-wide course progress (marks the lecture watched at 75 %).
  final CourseDetailProvider? progress;
}

class VodListenSession extends ChangeNotifier with WidgetsBindingObserver {
  VodListenSession._();

  static final VodListenSession instance = VodListenSession._();

  /// Tests: what opens a stream (the real one needs a platform player).
  @visibleForTesting
  static Future<VideoPlayerController> Function(MaterialVariant v, {Duration at, double speed}) opener =
      (v, {at = Duration.zero, speed = 1.0}) => openVodController(v, at: at, speed: speed);

  VodListenHandoff? _h;
  bool _switching = false;
  bool _observing = false;
  bool _userPaused = false;
  DateTime? _keepPlayingUntil;
  Timer? _save;

  bool get active => _h != null;
  VodListenHandoff? get handoff => _h;

  /// The bar is moving to the audio track (its play button shows a spinner).
  bool get switching => _switching;

  /// Takes over [h] (the player closes right after). [play]: start / keep playing.
  void start(VodListenHandoff h, {required bool play}) {
    final prev = _h;
    if (prev != null && !identical(prev.controller, h.controller)) _end(prev, dispose: true);
    _h = h;
    _switching = false;
    _userPaused = !play;
    MediaFocus.claim(this, onLost: () => unawaited(stop()));
    h.controller.addListener(_onTick);
    _save?.cancel();
    _save = Timer.periodic(const Duration(seconds: 5), (_) => _persist());
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    // Nobody looks at the screen: it may sleep (the sound goes on — allowBackgroundPlayback).
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    if (play) {
      // Web: the <video> element that just left the page is paused by the browser a moment later.
      _keepPlayingUntil = DateTime.now().add(const Duration(seconds: 2));
      unawaited(h.controller.play().catchError((Object _) {}));
    }
    notifyListeners();
    final target = vodListenVariant(h.material, h.variant, offline: h.isOffline);
    if (vodSwitchDecision(h.variant, target) == VodSwitch.go) unawaited(_swapTo(h, target));
  }

  /// Expand: hands the controller back to a new player (nothing is disposed).
  VodListenHandoff? takeBack() {
    final h = _h;
    if (h == null) return null;
    _persist();
    _end(h, dispose: false);
    return h;
  }

  /// Close: saves the place and stops the sound.
  Future<void> stop() async {
    final h = _h;
    if (h == null) return;
    _persist();
    _end(h, dispose: true);
  }

  void togglePlay() {
    final c = _h?.controller;
    if (c == null || !c.value.isInitialized) return;
    final v = c.value;
    if (vodFinished(v.position, v.duration, playing: v.isPlaying)) {
      _userPaused = false;
      unawaited(c.seekTo(Duration.zero).then((_) => c.play()).catchError((Object _) {}));
    } else if (v.isPlaying) {
      _userPaused = true;
      _keepPlayingUntil = null;
      unawaited(c.pause());
      _persist();
    } else {
      _userPaused = false;
      unawaited(c.play());
    }
  }

  void seekBy(int seconds) {
    final c = _h?.controller;
    if (c == null || !c.value.isInitialized) return;
    final d = c.value.duration;
    var p = c.value.position + Duration(seconds: seconds);
    if (p < Duration.zero) p = Duration.zero;
    if (d > Duration.zero && p > d) p = d;
    unawaited(c.seekTo(p));
  }

  void seekToFraction(double f) {
    final c = _h?.controller;
    if (c == null || !c.value.isInitialized) return;
    final ms = (f.clamp(0.0, 1.0) * c.value.duration.inMilliseconds).round();
    unawaited(c.seekTo(Duration(milliseconds: ms)));
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _swapTo(VodListenHandoff h, MaterialVariant v) async {
    final old = h.controller;
    _switching = true;
    notifyListeners();
    VideoPlayerController? next;
    try {
      next = await opener(v, at: old.value.position, speed: h.speed);
      // Catch up with what the old stream played while the new one opened.
      if (identical(_h, h)) await next.seekTo(VodCarry(position: old.value.position, playing: false).seekIn(next.value.duration));
    } catch (_) {
      next = null; // the stream on screen goes on
    }
    if (!identical(_h, h)) {
      unawaited(next?.dispose());
      return;
    }
    _switching = false;
    if (next == null) {
      notifyListeners();
      return;
    }
    final playing = old.value.isPlaying || (!_userPaused && _keepPlayingUntil != null);
    old.removeListener(_onTick);
    await old.pause().catchError((Object _) {});
    h.returnTo ??= h.variant;
    h.controller = next;
    h.variant = v;
    h.swapped = true;
    next.addListener(_onTick);
    if (playing && !_userPaused) unawaited(next.play().catchError((Object _) {}));
    notifyListeners();
    unawaited(old.dispose().catchError((Object _) {}));
  }

  void _end(VodListenHandoff h, {required bool dispose}) {
    h.controller.removeListener(_onTick);
    _save?.cancel();
    _save = null;
    _keepPlayingUntil = null;
    _switching = false;
    MediaFocus.release(this);
    if (identical(_h, h)) _h = null;
    if (dispose) {
      final c = h.controller;
      unawaited(c.pause().catchError((Object _) {}).whenComplete(() => c.dispose().catchError((Object _) {})));
    }
    notifyListeners();
  }

  void _onTick() {
    final h = _h;
    if (h == null) return;
    final v = h.controller.value;
    if (!v.isInitialized) return;
    // Web: the browser paused the element the player page took off the screen — the person did not.
    final until = _keepPlayingUntil;
    if (until != null) {
      if (DateTime.now().isAfter(until)) {
        _keepPlayingUntil = null;
      } else if (!v.isPlaying && !_userPaused && !vodFinished(v.position, v.duration, playing: false)) {
        unawaited(h.controller.play().catchError((Object _) {}));
      }
    }
    if (!h.completionSent && v.duration > Duration.zero &&
        v.position.inMilliseconds / v.duration.inMilliseconds >= 0.75) {
      h.completionSent = true;
      final p = h.progress;
      if (p != null) unawaited(p.markMaterialComplete(h.material.sessionId, h.material.id));
    }
  }

  void _persist() {
    final h = _h;
    if (h == null) return;
    final v = h.controller.value;
    if (!v.isInitialized) return;
    unawaited(VodResume.save(h.material.sessionId, h.material.id, v.position, v.duration));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) _persist();
  }

  /// Tests: forget the session without touching a platform player.
  @visibleForTesting
  void debugReset() {
    _save?.cancel();
    _save = null;
    _h = null;
    _switching = false;
    _keepPlayingUntil = null;
    MediaFocus.release(this);
  }
}
