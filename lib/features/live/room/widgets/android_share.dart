// android_share.dart — the Android share's native calls and the room's mic gate.
//
// AndroidShareNative: ScreenCaptureService through MainActivity's channels (screen_share methods,
// live_events stream). LiveMicGate: every mic tap in the room (control bar, mini box, phone-call
// mute) goes through it, so a share with device audio mutes by zeroing the mic samples natively
// while the track keeps carrying the shared audio (see ShareMicPolicy in share_presets.dart).
// Viewers still see the presenter's mic as on during such a soft mute (the publication stays
// unmuted: LiveKit's server drops a muted track's packets, the shared audio with them).
//
// The native soft mute is process-static (ElFaheemAudioMixer): the gate clears it on every reset,
// always AFTER the mic was really muted when it could still be heard (release, endDeviceAudio).
// The gate also owns "muted by a phone call" (callStarted / callEnded): a tap on the mic in
// between clears it, so the call's end only gives back a mic the call itself took.
// The logic runs on [LiveMic] (a LocalParticipant's mic in the room, a fake in
// test/org/live_mic_gate_test.dart).

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:flutter_education_app/features/live/room/widgets/live_room_rules.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_presets.dart';

/// Device audio can go with an Android share: Android 10 (API 29) for playback capture, the
/// microphone may be published (the audio rides on the mic track) and the room lets a share's
/// audio go out (`screen_share_audio`). Otherwise the share runs without it.
bool shareDeviceAudioAvailable({
  required int apiLevel,
  required bool micAllowed,
  required bool shareAudioAllowed,
}) =>
    apiLevel >= 29 && micAllowed && shareAudioAllowed;

/// The note under the share sheet's device-audio switch: playback capture takes every app's media
/// audio, also when only one app is shared (Android 14+).
String shareDeviceAudioScopeNote({required bool arabic}) => arabic
    ? 'يشمل صوت الجهاز صوت كل التطبيقات التي تشغّل وسائط، حتى عند مشاركة تطبيق واحد.'
    : 'Device audio includes every app playing media, even when you share a single app.';

class AndroidShareNative {
  const AndroidShareNative._();

  static const _channel = MethodChannel('com.doubley.nextbrain/screen_share');
  static const _events = EventChannel('com.doubley.nextbrain/live_events');

  /// Whether device audio can be offered (see [shareDeviceAudioAvailable]).
  static Future<bool> deviceAudioSupported({bool micAllowed = true, bool shareAudioAllowed = true}) async {
    try {
      final caps = await _channel.invokeMethod<Map>('shareCapabilities');
      final sdk = caps?['sdk'];
      final apiLevel = sdk is num ? sdk.toInt() : (caps?['deviceAudio'] == true ? 29 : 0);
      return shareDeviceAudioAvailable(
        apiLevel: apiLevel,
        micAllowed: micAllowed,
        shareAudioAllowed: shareAudioAllowed,
      );
    } catch (e) {
      log('[SS] shareCapabilities: $e');
      return false;
    }
  }

  /// The device's API level (0 when unknown): 34+ lets the person share a single app.
  static Future<int> apiLevel() async {
    try {
      final sdk = (await _channel.invokeMethod<Map>('shareCapabilities'))?['sdk'];
      return sdk is num ? sdk.toInt() : 0;
    } catch (e) {
      log('[SS] shareCapabilities: $e');
      return 0;
    }
  }

  /// Shows the system dialog when needed and answers once the native share runs (or failed).
  static Future<ShareStartOutcome> start(SharePreset preset, {required bool deviceAudio}) async {
    final raw = await _channel.invokeMethod<Object?>(
      'startScreenCaptureService',
      preset.nativeArgs(deviceAudio: deviceAudio),
    );
    return ShareStartOutcome.parse(raw);
  }

  /// Share off (idempotent). Also clears the native soft mute.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopScreenShare');
    } catch (e) {
      log('[SS] stopScreenShare: $e');
    }
  }

  static Future<void> setMicSoftMute(bool muted) async {
    try {
      await _channel.invokeMethod<void>('setMicSoftMute', {'muted': muted});
    } catch (e) {
      log('[SS] setMicSoftMute: $e');
    }
  }

  static Stream<LiveNativeEvent> events() => _events
      .receiveBroadcastStream()
      .map(LiveNativeEvent.parse)
      .where((e) => e != null)
      .cast<LiveNativeEvent>();
}

/// The mic the gate drives.
abstract class LiveMic {
  /// The track is published and not (LiveKit-)muted.
  bool get enabled;

  /// The server lets this participant publish the microphone.
  bool get allowed;

  Future<void> setEnabled(bool on);
}

/// A LocalParticipant's microphone.
class ParticipantMic implements LiveMic {
  const ParticipantMic(this.participant);

  final LocalParticipant participant;

  @override
  bool get enabled => participant.isMicrophoneEnabled();

  @override
  bool get allowed {
    final perms = participant.permissions;
    return liveAllowedControls(
      canPublish: perms.canPublish,
      sources: [for (final s in perms.canPublishSources) s.name],
      host: false, // the host only changes Share
    ).mic;
  }

  @override
  Future<void> setEnabled(bool on) => participant.setMicrophoneEnabled(on);
}

/// The room's one mic switch. Outside a share with device audio it is plain
/// `setMicrophoneEnabled`; inside one it flips the native soft mute.
class LiveMicGate extends ChangeNotifier {
  LiveMicGate._() : _native = AndroidShareNative.setMicSoftMute;

  /// A gate of its own with [native] in place of the platform channel.
  @visibleForTesting
  LiveMicGate.withNative(Future<void> Function(bool muted) native) : _native = native;

  static final LiveMicGate instance = LiveMicGate._();

  final Future<void> Function(bool muted) _native;

  bool _deviceAudio = false;
  bool _softMuted = false;
  bool _mutedByCall = false;

  /// A share with device audio runs (its audio rides on the mic track).
  bool get deviceAudioActive => _deviceAudio;
  bool get softMuted => _softMuted;

  /// A phone call muted the mic and nobody touched it since.
  bool get mutedByCall => _mutedByCall;

  static LiveMic? _wrap(LocalParticipant? p) => p == null ? null : ParticipantMic(p);

  // ── LocalParticipant API (the room) ─────────────────────────────────────────

  /// The mic as the presenter sees it: on = the viewers hear it.
  bool micOn(LocalParticipant? p) => isOn(_wrap(p));

  /// A tap on the mic by the person (control bar, mini box, keyboard).
  Future<void> setMic(LocalParticipant p, bool on) => userSet(ParticipantMic(p), on);

  Future<void> toggle(LocalParticipant p) => setMic(p, !micOn(p));

  /// The share's device audio started: from now on the track stays on and "mute" is the soft mute.
  /// False (nothing changed, the share goes on without device audio) when the mic may not be
  /// published or its track could not come on.
  Future<bool> beginDeviceAudio(LocalParticipant p) => begin(ParticipantMic(p));

  /// The share ended: a soft-muted mic is muted for real first, then the soft mute is cleared,
  /// so the mic is never heard in between. [p] null (the room closed): only the native flag.
  Future<void> endDeviceAudio(LocalParticipant? p) => end(_wrap(p));

  /// A phone call started: mutes an audible mic and remembers it. True when it muted it.
  Future<bool> muteForCall(LocalParticipant p) => callStarted(ParticipantMic(p));

  /// The call ended: gives the mic back only when the call muted it and nobody touched it since.
  Future<bool> restoreAfterCall(LocalParticipant p) => callEnded(ParticipantMic(p));

  /// Leaving the room: await it BEFORE the disconnect. A soft-muted mic is muted for real, then
  /// the native soft mute is cleared, so the mic is never heard on the way out.
  Future<void> release(LocalParticipant? p) => releaseMic(_wrap(p));

  // ── LiveMic API ─────────────────────────────────────────────────────────────

  bool isOn(LiveMic? m) => (m?.enabled ?? false) && !_softMuted;

  Future<void> userSet(LiveMic m, bool on) async {
    _mutedByCall = false; // the person decides from now on, not the call's end
    await _set(m, on);
  }

  Future<bool> begin(LiveMic m) async {
    if (!m.allowed) {
      log('[SS] device audio: the mic may not be published — share without it');
      return false;
    }
    final next = ShareMicPolicy.onShareStart(micOn: isOn(m), deviceAudio: true);
    _deviceAudio = true;
    try {
      // The soft mute first: when the track has to come on for a muted mic, it starts silent.
      await _setSoft(next.softMuted);
      if (next.trackEnabled && !m.enabled) await m.setEnabled(true);
    } catch (e) {
      log('[SS] device audio: the mic track could not come on ($e) — share without it');
      _deviceAudio = false;
      if (!m.enabled) await _setSoft(false); // nothing publishes: safe to clear
      notifyListeners();
      return false;
    }
    log('[SS] device audio on the mic track: $next');
    notifyListeners();
    return true;
  }

  Future<void> end(LiveMic? m) async {
    if (!_deviceAudio) return;
    final current = ShareMicState(trackEnabled: m?.enabled ?? false, softMuted: _softMuted);
    final next = ShareMicPolicy.onShareStop(current);
    _deviceAudio = false;
    var muted = true;
    if (m != null && !next.trackEnabled && m.enabled) muted = await _muteForReal(m);
    if (muted) {
      await _setSoft(false);
    } else {
      // Still silent; the next tap (or reset) settles it.
      log('[SS] mic mute after the share failed twice: the soft mute stays on');
    }
    notifyListeners();
  }

  Future<bool> callStarted(LiveMic m) async {
    if (!isOn(m)) return false;
    _mutedByCall = true;
    try {
      await _set(m, false);
    } catch (_) {
      _mutedByCall = false;
      rethrow;
    }
    return true;
  }

  Future<bool> callEnded(LiveMic m) async {
    if (!_mutedByCall) return false;
    _mutedByCall = false;
    if (!m.allowed) return false;
    await _set(m, true);
    return true;
  }

  Future<void> releaseMic(LiveMic? m) async {
    _mutedByCall = false;
    if (_softMuted && m != null && m.enabled && !await _muteForReal(m)) {
      // Never clear while the track may still carry the mic; reset (after the disconnect) does.
      _deviceAudio = false;
      notifyListeners();
      return;
    }
    final changed = _deviceAudio || _softMuted;
    _deviceAudio = false;
    _softMuted = false;
    await _native(false); // always: a flag left natively is not in these Dart flags
    if (changed) notifyListeners();
  }

  /// The room closed: nothing of the share's mic state may outlive it. Always clears the native
  /// soft mute (one left by a dead engine is not in the Dart flags). Synchronous: when the room may
  /// still be connected and soft-muted, await [release] first.
  void reset() {
    final changed = _deviceAudio || _softMuted || _mutedByCall;
    _deviceAudio = false;
    _softMuted = false;
    _mutedByCall = false;
    unawaited(_native(false));
    if (changed) notifyListeners();
  }

  // ── internals ───────────────────────────────────────────────────────────────

  Future<void> _set(LiveMic m, bool on) async {
    if (!_deviceAudio) {
      await m.setEnabled(on);
      // A soft mute left by a failed real mute (end) goes once the track is what was asked.
      await _setSoft(false);
      return;
    }
    // With device audio the track stays on (it carries the shared audio): only the soft mute flips.
    // The soft mute first: when the track has to come on for a muted mic, it starts silent.
    await _setSoft(!on);
    if (!m.enabled) await m.setEnabled(true);
  }

  Future<void> _setSoft(bool muted) async {
    if (muted == _softMuted) return;
    _softMuted = muted;
    await _native(muted);
    notifyListeners();
  }

  /// A real (LiveKit) mute, retried once. False when it failed both times.
  Future<bool> _muteForReal(LiveMic m) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await m.setEnabled(false);
        return true;
      } catch (e) {
        log('[SS] mic mute (attempt $attempt): $e');
      }
    }
    return false;
  }
}
