// The listen bar's lecture outside the app (D-104): the media notification, the lock screen, headset buttons.
//
//   Android  VodMediaService (Kotlin): a "mediaPlayback" foreground service for the whole listen session — keeps the
//            stream loading with the screen off or in another app (wake + Wi-Fi locks while playing), a MediaStyle
//            notification with −10 s · play / pause · +10 s · close and a seek line, also on the lock screen.
//   iOS      VodNowPlaying (AppDelegate.swift): MPNowPlayingInfoCenter + MPRemoteCommandCenter. The sound itself goes
//            on through UIBackgroundModes audio + allowBackgroundPlayback.
//   Web      nothing (the tab keeps playing on its own).
//
// Both sides speak the same channel: Dart → start / update / stop; native → "command" {cmd, ms?} with cmd one of
// play · pause · back · forward · seek · stop. [VodMediaSync] (pure) decides when an update is worth a message:
// play / pause, speed, the length, a jump of the position — not every tick, the OS runs the clock from the rate.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/config/app_config.dart';

/// What the OS shows for the lecture.
@immutable
class VodMediaState {
  const VodMediaState({
    required this.playing,
    required this.position,
    required this.duration,
    this.speed = 1.0,
  });

  final bool playing;
  final Duration position, duration;
  final double speed;
}

/// Pure: whether the OS needs to hear about [now] after it last heard [sent] at [sentAt]. The OS advances the
/// clock by itself from the rate, so only a change of state or a jump (a seek, a stall) is sent, plus a
/// slow re-sync every [resync].
class VodMediaSync {
  VodMediaSync({this.jump = const Duration(seconds: 2), this.resync = const Duration(seconds: 30)});

  final Duration jump, resync;
  VodMediaState? _sent;
  DateTime? _sentAt;

  bool needs(VodMediaState now, DateTime at) {
    final s = _sent;
    final t = _sentAt;
    if (s == null || t == null) return true;
    if (s.playing != now.playing || s.speed != now.speed || s.duration != now.duration) return true;
    final elapsed = at.difference(t);
    if (elapsed >= resync) return true;
    final expected = s.playing
        ? s.position + Duration(microseconds: (elapsed.inMicroseconds * s.speed).round())
        : s.position;
    return (now.position - expected).abs() > jump;
  }

  void sent(VodMediaState s, DateTime at) {
    _sent = s;
    _sentAt = at;
  }

  void reset() {
    _sent = null;
    _sentAt = null;
  }
}

/// A command from the notification, the lock screen or a headset.
enum VodMediaCommand { play, pause, back, forward, seek, stop }

VodMediaCommand? vodMediaCommandOf(String? s) => switch (s) {
      'play' => VodMediaCommand.play,
      'pause' => VodMediaCommand.pause,
      'back' => VodMediaCommand.back,
      'forward' => VodMediaCommand.forward,
      'seek' => VodMediaCommand.seek,
      'stop' => VodMediaCommand.stop,
      _ => null,
    };

class VodMediaControls {
  VodMediaControls._();

  static const _ch = MethodChannel('com.doubley.nextbrain/vod_media');

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static final _sync = VodMediaSync();
  static bool _on = false;

  /// Starts the background service / the Now Playing entry for [title] and sends commands to [onCommand].
  static Future<void> start({
    required String title,
    required VodMediaState state,
    required void Function(VodMediaCommand cmd, Duration? at) onCommand,
  }) async {
    if (!supported) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'command') return null;
      final a = call.arguments;
      if (a is! Map) return null;
      final cmd = vodMediaCommandOf(a['cmd']?.toString());
      if (cmd == null) return null;
      final ms = a['ms'];
      onCommand(cmd, ms is num ? Duration(milliseconds: ms.toInt()) : null);
      return null;
    });
    _on = true;
    _sync.reset();
    final now = DateTime.now();
    _sync.sent(state, now);
    try {
      await _ch.invokeMethod<Object?>('start', {
        'title': title,
        'subtitle': 'vod_listening'.tr,
        'channelName': 'vod_media_channel'.tr,
        'labels': {
          'play': 'vod_play'.tr,
          'pause': 'vod_pause'.tr,
          'back': 'vod_back10'.tr,
          'forward': 'vod_fwd10'.tr,
          'close': 'vod_close_listen'.tr,
        },
        ..._args(state),
      });
    } catch (_) {
      // An app built before the native side existed: the sound still plays (no notification).
    }
  }

  /// Tells the OS about [state] when it changed enough ([VodMediaSync]).
  static void update(VodMediaState state) {
    if (!_on || !supported) return;
    final now = DateTime.now();
    if (!_sync.needs(state, now)) return;
    _sync.sent(state, now);
    unawaited(_ch.invokeMethod<Object?>('update', _args(state)).catchError((Object _) => null));
  }

  static Future<void> stop() async {
    if (!_on || !supported) return;
    _on = false;
    _sync.reset();
    _ch.setMethodCallHandler(null);
    try {
      await _ch.invokeMethod<Object?>('stop');
    } catch (_) {}
  }

  static Map<String, Object> _args(VodMediaState s) => {
        'playing': s.playing,
        'position': s.position.inMilliseconds,
        'duration': s.duration.inMilliseconds,
        'speed': s.speed,
      };
}
