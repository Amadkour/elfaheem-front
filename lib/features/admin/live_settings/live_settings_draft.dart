// lib/features/admin/live_settings/live_settings_draft.dart
//
// The super admin's "Live performance" settings (D-089) — the pure part of the admin page.
//
//   GET /api/v1/admin/live-settings   → LiveSettingsInfo.fromJson (settings, recommended, stored fields, env, …)
//   PUT /api/v1/admin/live-settings   ← LiveSettingsDraft.changesFrom(original) (only the changed fields)
//                                       or {reset: true} (back to the recommended set + the server's env defaults)
//
//   LiveSettingsDraft      every field of the server's settings object (contract v1 of `live_config` + the server-
//                          only `server_recording_tiers`); fromJson is tolerant (a missing / unknown value reads
//                          as the recommended one), equality by value, `changesFrom` = the PUT body
//   estimateBandwidth      what one viewer downloads and the teacher uploads with a draft (pure, unit-tested); the
//                          page's live preview
//   LiveSettingsApi        the two calls
//
// The app's live room reads the same values from `live_config` in its join payloads — that model belongs to the
// live room code (lib/features/live/), not to this page. Server: services/live_settings_service.py.
library;

import 'dart:math' as math;

import 'package:flutter_education_app/core/api_client.dart';

const kLiveSettingsFeatureKey = 'admin.live_settings';
const kLiveSettingsPath = '/api/v1/admin/live-settings';

const kVideoCodecs = ['vp8', 'h264', 'vp9'];
const kWeakNetworkModes = ['adaptive', 'audio_first'];
const kHostCameraCaps = ['720p', '540p', '360p'];
const kParticipantCameraCaps = ['540p', '360p', '180p'];
const kCameraFps = [15, 24, 30];
const kRecordingModes = ['server', 'client'];
const kRecordingEngines = ['composite', 'media'];
const kRecordingTiers = ['single', 'all'];
const kScreenFpsMin = 5, kScreenFpsMax = 30;
const kScreenBitrateMin = 500, kScreenBitrateMax = 6000, kScreenBitrateStep = 250;

String _pick(dynamic v, List<String> allowed, String fallback) {
  final s = '${v ?? ''}'.trim().toLowerCase();
  return allowed.contains(s) ? s : fallback;
}

int _pickInt(dynamic v, int fallback, {List<int>? allowed, int? min, int? max}) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null || n != n.roundToDouble()) return fallback;
  final i = n.toInt();
  if (allowed != null && !allowed.contains(i)) return fallback;
  if ((min != null && i < min) || (max != null && i > max)) return fallback;
  return i;
}

bool _pickBool(dynamic v, bool fallback) => v is bool ? v : fallback;

class LiveSettingsDraft {
  const LiveSettingsDraft({
    required this.videoCodec,
    required this.weakNetwork,
    required this.cameraMaxHost,
    required this.cameraMaxParticipant,
    required this.cameraFps,
    required this.screenFpsMax,
    required this.screenBitrateKbps,
    required this.audioDtx,
    required this.audioRed,
    required this.participantsCameraDefaultOff,
    required this.pauseHiddenVideo,
    required this.recordingMode,
    required this.serverRecordingEngine,
    required this.serverRecordingTiers,
  });

  /// The server's recommended set (services/live_settings_service.py DEFAULTS); the page shows the server's own
  /// copy when it has one (`LiveSettingsInfo.recommended`).
  static const recommended = LiveSettingsDraft(
    videoCodec: 'vp8',
    weakNetwork: 'adaptive',
    cameraMaxHost: '720p',
    cameraMaxParticipant: '360p',
    cameraFps: 24,
    screenFpsMax: 15,
    screenBitrateKbps: 2500,
    audioDtx: true,
    audioRed: true,
    participantsCameraDefaultOff: true,
    pauseHiddenVideo: true,
    recordingMode: 'server',
    serverRecordingEngine: 'composite',
    serverRecordingTiers: 'single',
  );

  factory LiveSettingsDraft.fromJson(Map<String, dynamic>? j, {LiveSettingsDraft fallback = recommended}) {
    final m = j ?? const <String, dynamic>{};
    final f = fallback;
    return LiveSettingsDraft(
      videoCodec: _pick(m['video_codec'], kVideoCodecs, f.videoCodec),
      weakNetwork: _pick(m['weak_network'], kWeakNetworkModes, f.weakNetwork),
      cameraMaxHost: _pick(m['camera_max_host'], kHostCameraCaps, f.cameraMaxHost),
      cameraMaxParticipant: _pick(m['camera_max_participant'], kParticipantCameraCaps, f.cameraMaxParticipant),
      cameraFps: _pickInt(m['camera_fps'], f.cameraFps, allowed: kCameraFps),
      screenFpsMax: _pickInt(m['screen_fps_max'], f.screenFpsMax, min: kScreenFpsMin, max: kScreenFpsMax),
      screenBitrateKbps:
          _pickInt(m['screen_bitrate_kbps'], f.screenBitrateKbps, min: kScreenBitrateMin, max: kScreenBitrateMax),
      audioDtx: _pickBool(m['audio_dtx'], f.audioDtx),
      audioRed: _pickBool(m['audio_red'], f.audioRed),
      participantsCameraDefaultOff: _pickBool(m['participants_camera_default_off'], f.participantsCameraDefaultOff),
      pauseHiddenVideo: _pickBool(m['pause_hidden_video'], f.pauseHiddenVideo),
      recordingMode: _pick(m['recording_mode'], kRecordingModes, f.recordingMode),
      serverRecordingEngine: _pick(m['server_recording_engine'], kRecordingEngines, f.serverRecordingEngine),
      serverRecordingTiers: _pick(m['server_recording_tiers'], kRecordingTiers, f.serverRecordingTiers),
    );
  }

  final String videoCodec;
  final String weakNetwork;
  final String cameraMaxHost;
  final String cameraMaxParticipant;
  final int cameraFps;
  final int screenFpsMax;
  final int screenBitrateKbps;
  final bool audioDtx;
  final bool audioRed;
  final bool participantsCameraDefaultOff;
  final bool pauseHiddenVideo;
  final String recordingMode;
  final String serverRecordingEngine;
  final String serverRecordingTiers;

  Map<String, dynamic> toJson() => {
        'video_codec': videoCodec,
        'weak_network': weakNetwork,
        'camera_max_host': cameraMaxHost,
        'camera_max_participant': cameraMaxParticipant,
        'camera_fps': cameraFps,
        'screen_fps_max': screenFpsMax,
        'screen_bitrate_kbps': screenBitrateKbps,
        'audio_dtx': audioDtx,
        'audio_red': audioRed,
        'participants_camera_default_off': participantsCameraDefaultOff,
        'pause_hidden_video': pauseHiddenVideo,
        'recording_mode': recordingMode,
        'server_recording_engine': serverRecordingEngine,
        'server_recording_tiers': serverRecordingTiers,
      };

  /// The fields whose value differs from [other] (the PUT body: only what the super admin changed).
  Map<String, dynamic> changesFrom(LiveSettingsDraft other) {
    final a = toJson(), b = other.toJson();
    return {for (final e in a.entries) if (b[e.key] != e.value) e.key: e.value};
  }

  /// How many fields differ from [other] (the "n changes" line, "n away from recommended").
  int differencesFrom(LiveSettingsDraft other) => changesFrom(other).length;

  LiveSettingsDraft copyWith({
    String? videoCodec,
    String? weakNetwork,
    String? cameraMaxHost,
    String? cameraMaxParticipant,
    int? cameraFps,
    int? screenFpsMax,
    int? screenBitrateKbps,
    bool? audioDtx,
    bool? audioRed,
    bool? participantsCameraDefaultOff,
    bool? pauseHiddenVideo,
    String? recordingMode,
    String? serverRecordingEngine,
    String? serverRecordingTiers,
  }) =>
      LiveSettingsDraft(
        videoCodec: videoCodec ?? this.videoCodec,
        weakNetwork: weakNetwork ?? this.weakNetwork,
        cameraMaxHost: cameraMaxHost ?? this.cameraMaxHost,
        cameraMaxParticipant: cameraMaxParticipant ?? this.cameraMaxParticipant,
        cameraFps: cameraFps ?? this.cameraFps,
        screenFpsMax: screenFpsMax ?? this.screenFpsMax,
        screenBitrateKbps: screenBitrateKbps ?? this.screenBitrateKbps,
        audioDtx: audioDtx ?? this.audioDtx,
        audioRed: audioRed ?? this.audioRed,
        participantsCameraDefaultOff: participantsCameraDefaultOff ?? this.participantsCameraDefaultOff,
        pauseHiddenVideo: pauseHiddenVideo ?? this.pauseHiddenVideo,
        recordingMode: recordingMode ?? this.recordingMode,
        serverRecordingEngine: serverRecordingEngine ?? this.serverRecordingEngine,
        serverRecordingTiers: serverRecordingTiers ?? this.serverRecordingTiers,
      );

  @override
  bool operator ==(Object other) => other is LiveSettingsDraft && differencesFrom(other) == 0;

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

/// GET /admin/live-settings.
class LiveSettingsInfo {
  const LiveSettingsInfo({
    required this.settings,
    this.recommended = LiveSettingsDraft.recommended,
    this.stored = const {},
    this.envRecordingMode,
    this.envRecordingTiers,
    this.updatedAt,
  });

  factory LiveSettingsInfo.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? map(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;
    final rec = LiveSettingsDraft.fromJson(map(j['recommended']));
    final env = map(j['env']) ?? const {};
    return LiveSettingsInfo(
      settings: LiveSettingsDraft.fromJson(map(j['settings']), fallback: rec),
      recommended: rec,
      stored: {for (final s in (j['stored'] is List ? j['stored'] as List : const [])) '$s'},
      envRecordingMode: env['recording_mode'] is String ? env['recording_mode'] as String : null,
      envRecordingTiers: env['server_recording_tiers'] is String ? env['server_recording_tiers'] as String : null,
      updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}'),
    );
  }

  final LiveSettingsDraft settings;
  final LiveSettingsDraft recommended;

  /// The fields the super admin set (the rest are the recommended / env defaults).
  final Set<String> stored;

  /// The server's env default while nobody picked a recording mode / tiers (RECORDING_MODE, RECORDING_QUALITIES).
  final String? envRecordingMode;
  final String? envRecordingTiers;
  final DateTime? updatedAt;
}

// ── Bandwidth preview ────────────────────────────────────────────────────────

/// Top-layer bitrate at 30 fps, VP8 (kbit/s) — the order of LiveKit's own presets (h720 1.7 Mbit/s, h360 0.45 …).
const Map<String, int> kLayerKbps30 = {'720p': 1700, '540p': 900, '360p': 500, '180p': 160};

/// Relative size of the same picture per codec (VP9 ≈ 30 % smaller; H.264 constrained baseline a little larger).
const Map<String, double> kCodecFactor = {'vp8': 1.0, 'h264': 1.1, 'vp9': 0.7};

const kOpusKbps = 32;

/// A typical class for the preview: this many students, this many tiles visible on a viewer's screen.
const kPreviewStudents = 20;
const kPreviewVisibleTiles = 4;

/// Cameras that are on in the preview class when students join with the camera OFF (a few turn it on).
const kPreviewCamerasWhenDefaultOff = 2;

int layerKbps(String layer, int fps, String codec) {
  final base = kLayerKbps30[layer] ?? kLayerKbps30['360p']!;
  final f = math.pow(fps.clamp(5, 30) / 30, 0.7);
  return (base * f * (kCodecFactor[codec] ?? 1.0)).round();
}

/// The simulcast layers a camera capped at [top] publishes (top + 360p + 180p, without duplicates).
List<String> simulcastLayers(String top) {
  const order = ['720p', '540p', '360p', '180p'];
  final i = order.indexOf(top);
  final out = <String>[top];
  if (i >= 0 && i < order.indexOf('360p')) out.add('360p');
  if (top != '180p') out.add('180p');
  return out;
}

class LiveBandwidth {
  const LiveBandwidth({
    required this.teacherCameraKbps,
    required this.screenKbps,
    required this.audioKbps,
    required this.studentTilesKbps,
    required this.studentTiles,
    required this.camerasOn,
    required this.teacherUploadKbps,
    required this.participantUploadKbps,
    required this.weakNetworkFloorKbps,
  });

  /// The teacher's camera at its top layer (the main stage).
  final int teacherCameraKbps;

  /// The screen share at most (static slides use much less).
  final int screenKbps;
  final int audioKbps;

  /// The students' camera tiles a viewer downloads (low layer each).
  final int studentTilesKbps;
  final int studentTiles;
  final int camerasOn;

  /// Camera layers + screen share.
  final int teacherUploadKbps;

  /// One student with the camera on (0 is never shown: the camera may be off).
  final int participantUploadKbps;

  /// Below about this much a viewer is moved off the full video (adaptive: steps down; audio first: audio only).
  final int weakNetworkFloorKbps;

  int get perViewerKbps => teacherCameraKbps + audioKbps + studentTilesKbps;
  int get perViewerWithShareKbps => perViewerKbps + screenKbps;

  /// One hour of a class with the share on, per viewer (megabytes).
  int get perViewerHourMb => (perViewerWithShareKbps * 3600 / 8 / 1000).round();
}

LiveBandwidth estimateBandwidth(LiveSettingsDraft d) {
  final codec = d.videoCodec;
  final teacher = layerKbps(d.cameraMaxHost, d.cameraFps, codec);
  final upload = [for (final l in simulcastLayers(d.cameraMaxHost)) layerKbps(l, d.cameraFps, codec)]
      .fold<int>(0, (a, b) => a + b);
  final participantUp = [for (final l in simulcastLayers(d.cameraMaxParticipant)) layerKbps(l, d.cameraFps, codec)]
      .fold<int>(0, (a, b) => a + b);
  final camerasOn = d.participantsCameraDefaultOff ? kPreviewCamerasWhenDefaultOff : kPreviewStudents;
  // a hidden tile still downloads its low layer unless paused
  final tiles = d.pauseHiddenVideo ? math.min(kPreviewVisibleTiles, camerasOn) : camerasOn;
  final tileKbps = layerKbps('180p', math.min(d.cameraFps, 15), codec);
  var audio = kOpusKbps.toDouble();
  if (d.audioRed) audio *= 1.9; // the previous frame rides along with each packet
  if (d.audioDtx) audio *= 0.65; // pauses between sentences send (almost) nothing
  return LiveBandwidth(
    teacherCameraKbps: teacher,
    screenKbps: (d.screenBitrateKbps * (kCodecFactor[codec] ?? 1.0)).round(),
    audioKbps: audio.round(),
    studentTilesKbps: tiles * tileKbps,
    studentTiles: tiles,
    camerasOn: camerasOn,
    teacherUploadKbps: upload + d.screenBitrateKbps,
    participantUploadKbps: participantUp,
    weakNetworkFloorKbps: d.weakNetwork == 'audio_first' ? 350 : layerKbps('180p', d.cameraFps, codec) + 100,
  );
}

/// "1.8" (Mbit/s, one decimal), "0.45" under 1.
String mbps(int kbps) {
  final v = kbps / 1000;
  if (v >= 10) return v.toStringAsFixed(0);
  if (v >= 1) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

// ── API ──────────────────────────────────────────────────────────────────────

class LiveSettingsApi {
  const LiveSettingsApi();

  Future<LiveSettingsInfo> load() async {
    final r = await ApiClient().get(kLiveSettingsPath);
    return LiveSettingsInfo.fromJson(r is Map ? r.cast<String, dynamic>() : const {});
  }

  /// Only the fields that changed; the answer is the new state.
  Future<LiveSettingsInfo> save(Map<String, dynamic> changes) async {
    final r = await ApiClient().put(kLiveSettingsPath, body: changes);
    return LiveSettingsInfo.fromJson(r is Map ? r.cast<String, dynamic>() : const {});
  }

  /// Every stored value cleared: the recommended set + the server's env defaults.
  Future<LiveSettingsInfo> reset() async {
    final r = await ApiClient().put(kLiveSettingsPath, body: const {'reset': true});
    return LiveSettingsInfo.fromJson(r is Map ? r.cast<String, dynamic>() : const {});
  }
}
