// share_presets.dart — the pure parts of the Android screen share (no channels, no widgets):
//
// - ShareQuality / SharePreset: the presenter's two modes (D14). "Detail" is for slides and text
//   (longer side up to 1920 = 1080p, at most 15 fps, ~2.5 Mbps, keep the resolution when the
//   network is short); "Motion" is for video (720p, 30 fps, ~3 Mbps, keep the frame rate). The
//   preset sizes the native capture (ScreenPlaceholderRenderer scales on the GPU), the track's
//   dimensions and LiveKit's screen-share encoding.
// - ShareMicPolicy: the mic while device audio rides on the mic track. The fork mixes the shared
//   audio into the outgoing mic buffer (ElFaheemAudioMixer), so the mic track must stay published
//   and enabled while it runs; muting then zeroes the mic samples natively ("soft mute") instead
//   of muting the LiveKit track, which would silence the shared audio with it.
// - ShareStartOutcome / LiveNativeEvent: what the native side answers and emits.
// - Web (the same two presets): getDisplayMedia's constraints, the track's contentHint, the size the browser
//   gave, the tab-audio track's publish options, and whether the browser can share audio at all.
//
// Tests: test/org/live_share_presets_test.dart.

import 'package:livekit_client/livekit_client.dart';

enum ShareQuality { detail, motion }

class SharePreset {
  const SharePreset({
    required this.quality,
    required this.maxLongSide,
    required this.maxFps,
    required this.maxBitrate,
    required this.degradation,
  });

  final ShareQuality quality;

  /// The capture's longer side, in pixels (aspect kept, never upscaled).
  final int maxLongSide;
  final int maxFps;

  /// Bits per second for the one screen-share layer.
  final int maxBitrate;
  final DegradationPreference degradation;

  static const detail = SharePreset(
    quality: ShareQuality.detail,
    maxLongSide: 1920,
    maxFps: 15,
    maxBitrate: 2500000,
    degradation: DegradationPreference.maintainResolution,
  );

  static const motion = SharePreset(
    quality: ShareQuality.motion,
    maxLongSide: 1280,
    maxFps: 30,
    maxBitrate: 3000000,
    degradation: DegradationPreference.maintainFramerate,
  );

  static SharePreset of(ShareQuality q) => switch (q) {
        ShareQuality.detail => detail,
        ShareQuality.motion => motion,
      };

  /// The screen [width]x[height] scaled so the longer side is at most [maxLongSide], aspect kept,
  /// both even (I420). The same rule as the native renderer's scaledSize.
  (int, int) sizeFor(int width, int height) {
    if (width <= 0 || height <= 0) return (0, 0);
    final longer = width > height ? width : height;
    final scale = longer > maxLongSide ? maxLongSide / longer : 1.0;
    int even(double v) {
      final r = v.round() & ~1;
      return r < 2 ? 2 : r;
    }
    return (even(width * scale), even(height * scale));
  }

  VideoEncoding get encoding => VideoEncoding(maxFramerate: maxFps, maxBitrate: maxBitrate);

  /// The track's capture options: its dimensions are what LiveKit announces to the server.
  ScreenShareCaptureOptions captureOptions(int width, int height) => ScreenShareCaptureOptions(
        maxFrameRate: maxFps.toDouble(),
        params: VideoParameters(dimensions: VideoDimensions(width, height), encoding: encoding),
      );

  /// One layer (no simulcast: a scaled-down copy of slides is unreadable anyway, and the
  /// capture is already sized for the mode).
  VideoPublishOptions get publishOptions => VideoPublishOptions(
        name: VideoPublishOptions.defaultScreenShareName,
        screenShareEncoding: encoding,
        simulcast: false,
        degradationPreference: degradation,
      );

  /// Arguments for the native `startScreenCaptureService`.
  Map<String, Object> nativeArgs({required bool deviceAudio}) => {
        'maxLongSide': maxLongSide,
        'fps': maxFps,
        'deviceAudio': deviceAudio,
      };

  // ── Web (the browser's getDisplayMedia, W7) ────────────────────────────────────────────────────────────────

  /// The video track's `contentHint`: the encoder keeps text sharp ("detail") or motion smooth ("motion").
  String get contentHint => quality == ShareQuality.detail ? 'detail' : 'motion';

  /// getDisplayMedia's constraints: the preset's size and frame rate as upper bounds (the browser scales down,
  /// aspect kept), the tab / system audio when [audio] (played locally too: the presenter keeps hearing it), the
  /// app's own tab left out of the picker, and switching the shared tab allowed. Browsers that do not know a
  /// key ignore it.
  Map<String, dynamic> webDisplayMediaConstraints({required bool audio}) => {
        'video': {
          'width': {'max': maxLongSide},
          'height': {'max': maxLongSide},
          'frameRate': {'ideal': maxFps, 'max': maxFps},
        },
        'audio': audio
            ? {
                'suppressLocalAudioPlayback': false,
                'echoCancellation': false,
                'noiseSuppression': false,
                'autoGainControl': false,
              }
            : false,
        'systemAudio': audio ? 'include' : 'exclude',
        'suppressLocalAudioPlayback': false,
        'selfBrowserSurface': 'exclude',
        'surfaceSwitching': 'include',
      };

  /// The size the browser actually gave ([settings] = MediaStreamTrack.getSettings()), capped by the preset;
  /// a 16:9 frame of the preset when the browser does not say.
  (int, int) sizeFromSettings(Map<String, dynamic> settings) {
    int n(Object? v) => v is num ? v.round() : 0;
    final w = n(settings['width']), h = n(settings['height']);
    if (w > 0 && h > 0) return sizeFor(w, h);
    return sizeFor(maxLongSide, maxLongSide * 9 ~/ 16);
  }

  /// The shared tab / system audio track (web): music quality, no DTX (silence detection cuts quiet music).
  static const screenAudioPublishOptions = AudioPublishOptions(
    name: 'screen_share_audio',
    encoding: AudioEncoding.presetMusicHighQualityStereo,
    dtx: false,
    red: false,
  );
}

/// Whether this browser can share a tab's / the system's audio: Chromium (Chrome, Edge, Opera) can, Firefox and
/// Safari give video only. [suppressLocalAudioPlaybackSupported] is the feature test (Chromium 109+ lists that
/// constraint); the user agent covers older Chromium.
bool webDisplayAudioSupported({required String userAgent, required bool suppressLocalAudioPlaybackSupported}) {
  final ua = userAgent.toLowerCase();
  if (ua.contains('mobile') || ua.contains('android') || ua.contains('iphone') || ua.contains('ipad')) return false;
  if (suppressLocalAudioPlaybackSupported) return true;
  if (ua.contains('firefox') || ua.contains('fxios')) return false;
  return ua.contains('chrome/') || ua.contains('chromium/') || ua.contains('edg/');
}

/// The mic's two switches: the LiveKit publication (enabled = unmuted) and the native soft mute.
class ShareMicState {
  const ShareMicState({required this.trackEnabled, required this.softMuted});

  final bool trackEnabled;
  final bool softMuted;

  /// What the presenter's "mic on" means: the viewers hear the mic.
  bool get micAudible => trackEnabled && !softMuted;

  @override
  bool operator ==(Object other) =>
      other is ShareMicState && other.trackEnabled == trackEnabled && other.softMuted == softMuted;

  @override
  int get hashCode => Object.hash(trackEnabled, softMuted);

  @override
  String toString() => 'ShareMicState(track: $trackEnabled, soft: $softMuted)';
}

class ShareMicPolicy {
  const ShareMicPolicy._();

  /// A share starts. Without device audio nothing changes. With it the track must run: a muted
  /// mic becomes "track on, samples zeroed", so the mic is still not heard (never unmuted).
  static ShareMicState onShareStart({required bool micOn, required bool deviceAudio}) => deviceAudio
      ? ShareMicState(trackEnabled: true, softMuted: !micOn)
      : ShareMicState(trackEnabled: micOn, softMuted: false);

  /// The presenter taps the mic. With device audio only the soft mute flips.
  static ShareMicState onToggle(ShareMicState s, {required bool deviceAudio}) => deviceAudio
      ? ShareMicState(trackEnabled: true, softMuted: s.micAudible)
      : ShareMicState(trackEnabled: !s.trackEnabled, softMuted: false);

  /// The share ends: a soft-muted mic becomes a real (LiveKit) mute again.
  static ShareMicState onShareStop(ShareMicState s) =>
      ShareMicState(trackEnabled: s.micAudible, softMuted: false);
}

/// The native answer to `startScreenCaptureService`.
class ShareStartOutcome {
  const ShareStartOutcome({
    required this.ok,
    this.denied = false,
    this.error,
    this.width = 0,
    this.height = 0,
    this.deviceAudio = 'off',
  });

  final bool ok;
  final bool denied;
  final String? error;
  final int width;
  final int height;

  /// "off", "started", "capturing", "unsupported", "no_permission" or "failed: …".
  final String deviceAudio;

  bool get deviceAudioOn => deviceAudio == 'started' || deviceAudio == 'capturing';

  /// The person asked for device audio but it could not start (not "unsupported": the sheet
  /// never offers it then).
  bool get deviceAudioFailed => deviceAudio == 'no_permission' || deviceAudio.startsWith('failed');

  static ShareStartOutcome parse(Object? raw) {
    if (raw is bool) return ShareStartOutcome(ok: raw);
    if (raw is! Map) return const ShareStartOutcome(ok: false, error: 'no answer');
    int n(Object? v) => v is num ? v.toInt() : 0;
    return ShareStartOutcome(
      ok: raw['ok'] == true,
      denied: raw['denied'] == true,
      error: raw['error'] as String?,
      width: n(raw['width']),
      height: n(raw['height']),
      deviceAudio: (raw['deviceAudio'] as String?) ?? 'off',
    );
  }
}

/// An event from the native `live_events` channel.
class LiveNativeEvent {
  const LiveNativeEvent(this.type, [this.data = const {}]);

  final String type;
  final Map<Object?, Object?> data;

  static LiveNativeEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['event'];
    if (type is! String || type.isEmpty) return null;
    return LiveNativeEvent(type, raw);
  }

  /// `shareStopped` from outside the app (system chip / notification / cast tile, or the task
  /// was removed): the track must be unpublished. Our own stop also emits it ("user").
  bool get stoppedOutside => type == 'shareStopped' && data['reason'] != 'user';

  /// `audioInterruption` (a phone call): true while it holds the mic.
  bool? get interruption => type == 'audioInterruption' ? data['active'] == true : null;
}
