// lib/features/live/live_config.dart
//
// The super admin's live media settings (D-090): `live_config` in every live join / start payload (course session
// start + join, meeting join, the signed-in link join, the public guest join). Pure: parsing, defaults, the last
// value seen. Every field is optional; an older server (no `live_config`) or a missing / unknown field gets the
// recommended default below, so the room never depends on the server knowing this contract.
//
//   {"v":1,"video_codec":"vp8"|"h264"|"vp9","weak_network":"adaptive"|"audio_first",
//    "camera_max_host":"1080p"|"720p"|"540p"|"360p","camera_max_participant":"540p"|"360p"|"180p","camera_fps":15|24|30,
//    "camera_fps_host":15|24|30 (D-1504; absent: 30, or 15 when camera_fps is 15),
//    "screen_fps_max":5..30,"screen_bitrate_kbps":500..6000,"audio_dtx":bool,"audio_red":bool,
//    "participants_camera_default_off":bool,"pause_hidden_video":bool,
//    "recording_mode":"server"|"client","server_recording_engine":"composite"|"media"}
//
// What the room does with it is in live_media_plan.dart (publish options) and live_quality_governor.dart (weak
// network). Tests: test/org/live_config_test.dart.
library;

/// The camera / screen codec the publisher asks for (LiveKit falls back to the backup codec per subscriber).
enum LiveVideoCodec { vp8, h264, vp9 }

/// What a weak downlink does: lower the video layers (adaptive), or, below the threshold, keep the audio and drop
/// the cameras until it recovers (audioFirst).
enum LiveWeakNetwork { adaptive, audioFirst }

/// Who records a course session: LiveKit Egress on the server, or the teacher's device (chunks).
enum LiveRecordingMode { server, client }

/// The Egress flavour the server uses (shown in the info sheet only; the app does nothing different).
enum LiveServerRecordingEngine { composite, media }

/// A camera resolution class (16:9 landscape; a portrait camera is the same frame turned).
enum LiveCameraCap {
  p180(320, 180),
  p360(640, 360),
  p540(960, 540),
  p720(1280, 720),

  /// The host only, and only when the server's live config asks for it (D-1504).
  p1080(1920, 1080);

  const LiveCameraCap(this.width, this.height);

  final int width;
  final int height;

  /// "720p" / "720" / 720 → [p720]; null when not one of the five.
  static LiveCameraCap? parse(Object? raw) {
    final s = '${raw ?? ''}'.trim().toLowerCase().replaceAll('p', '');
    final n = int.tryParse(s);
    for (final c in LiveCameraCap.values) {
      if (c.height == n) return c;
    }
    return null;
  }

  String get label => '${height}p';
}

class LiveConfig {
  const LiveConfig({
    this.version = 1,
    this.videoCodec = LiveVideoCodec.vp8,
    this.weakNetwork = LiveWeakNetwork.adaptive,
    this.cameraMaxHost = LiveCameraCap.p720,
    this.cameraMaxParticipant = LiveCameraCap.p360,
    this.cameraFps = 24,
    this.cameraFpsHost = 30,
    this.screenFpsMax = 15,
    this.screenBitrateKbps = 2500,
    this.audioDtx = true,
    this.audioRed = true,
    this.participantsCameraDefaultOff = true,
    this.pauseHiddenVideo = true,
    this.recordingMode,
    this.serverRecordingEngine = LiveServerRecordingEngine.composite,
    this.fromServer = false,
  });

  /// The recommended values (what an older server gets). See docs/live/NOTES.md "Live media tuning".
  static const LiveConfig defaults = LiveConfig();

  final int version;
  final LiveVideoCodec videoCodec;
  final LiveWeakNetwork weakNetwork;

  /// The host's (teacher / meeting owner) camera cap: 720p (default), 540p or 360p; 1080p when the server sends it.
  final LiveCameraCap cameraMaxHost;

  /// Everyone else's camera cap: 540p, 360p or 180p.
  final LiveCameraCap cameraMaxParticipant;

  /// Everyone but the host: 15, 24 or 30.
  final int cameraFps;

  /// The host's camera (D-1504): `camera_fps_host` when the server sends it, else 30 — or 15 when the super admin
  /// chose 15 for every camera (`camera_fps`), the bandwidth-saving setting.
  final int cameraFpsHost;

  /// The screen share's frame-rate ceiling (5–30); the presenter's mode stays under it (Detail is 15 at most
  /// anyway, Motion 30). Default 15, the server's recommended value (D-1504): used only when the server sends none.
  final int screenFpsMax;

  /// The screen share's top bitrate in kbps (500–6000): Detail uses it, Motion 1.2× (capped at 6000).
  final int screenBitrateKbps;
  final bool audioDtx;
  final bool audioRed;

  /// Students (not hosts) start with the camera off: no camera track exists until they turn it on.
  final bool participantsCameraDefaultOff;

  /// Tiles nobody sees (off-screen, behind the minimized box, the app in the background) stop receiving video.
  final bool pauseHiddenVideo;

  /// Null = the server did not say (an older server): the teacher's device records as it always did.
  final LiveRecordingMode? recordingMode;
  final LiveServerRecordingEngine serverRecordingEngine;

  /// True when this came from a payload's `live_config` (not the built-in defaults).
  final bool fromServer;

  /// The teacher's device runs the chunk recorder for a course session (client mode, or a server that does not
  /// say). In server mode LiveKit Egress records and the device does not.
  bool get deviceRecorder => recordingMode != LiveRecordingMode.server;

  /// Server recording records tracks only: a presented whiteboard is then published as a slow video track too.
  bool get serverRecords => recordingMode == LiveRecordingMode.server;

  LiveCameraCap cameraCapFor({required bool host}) => host ? cameraMaxHost : cameraMaxParticipant;

  int cameraFpsFor({required bool host}) => host ? cameraFpsHost : cameraFps;

  /// The camera a person starts with on the pre-join page when nothing else decided it (a Rejoin keeps theirs).
  bool cameraStartsOn({required bool host}) => host || !participantsCameraDefaultOff;

  /// Never throws: anything that is not a map gives [defaults].
  static LiveConfig parse(Object? raw) {
    if (raw is! Map) return defaults;
    final j = <String, Object?>{for (final e in raw.entries) '${e.key}': e.value};
    String s(String k) => '${j[k] ?? ''}'.trim().toLowerCase().replaceAll('-', '_');
    bool b(String k, bool fallback) {
      final v = j[k];
      if (v is bool) return v;
      if (v is num) return v != 0;
      final t = s(k);
      if (t == 'true' || t == '1' || t == 'on' || t == 'yes') return true;
      if (t == 'false' || t == '0' || t == 'off' || t == 'no') return false;
      return fallback;
    }

    int? n(String k) {
      final v = j[k];
      if (v is num) return v.round();
      return int.tryParse(s(k));
    }

    const d = defaults;
    final codec = switch (s('video_codec')) {
      'h264' || 'avc' => LiveVideoCodec.h264,
      'vp9' => LiveVideoCodec.vp9,
      'vp8' => LiveVideoCodec.vp8,
      _ => d.videoCodec,
    };
    final weak = switch (s('weak_network')) {
      'audio_first' || 'audioonly' || 'audio_only' => LiveWeakNetwork.audioFirst,
      'adaptive' => LiveWeakNetwork.adaptive,
      _ => d.weakNetwork,
    };
    // The host cap is 1080p at most (D-1504, only when sent) and 360p at least; a participant's 540p at most and
    // 180p at least.
    var host = LiveCameraCap.parse(j['camera_max_host']) ?? d.cameraMaxHost;
    if (host == LiveCameraCap.p180) host = LiveCameraCap.p360;
    var part = LiveCameraCap.parse(j['camera_max_participant']) ?? d.cameraMaxParticipant;
    if (part.height > LiveCameraCap.p540.height) part = LiveCameraCap.p540;
    final fpsRaw = n('camera_fps');
    final fps = fpsRaw == null ? d.cameraFps : snapCameraFps(fpsRaw);
    final hostFpsRaw = n('camera_fps_host');
    final hostFps = hostFpsRaw != null ? snapCameraFps(hostFpsRaw) : (fps == 15 ? 15 : d.cameraFpsHost);
    final screenFps = (n('screen_fps_max') ?? d.screenFpsMax).clamp(5, 30);
    final screenKbps = (n('screen_bitrate_kbps') ?? d.screenBitrateKbps).clamp(500, 6000);
    final rec = switch (s('recording_mode')) {
      'server' => LiveRecordingMode.server,
      'client' => LiveRecordingMode.client,
      _ => null,
    };
    final engine = switch (s('server_recording_engine')) {
      'media' || 'track' || 'tracks' => LiveServerRecordingEngine.media,
      _ => LiveServerRecordingEngine.composite,
    };
    return LiveConfig(
      version: n('v') ?? 1,
      videoCodec: codec,
      weakNetwork: weak,
      cameraMaxHost: host,
      cameraMaxParticipant: part,
      cameraFps: fps,
      cameraFpsHost: hostFps,
      screenFpsMax: screenFps,
      screenBitrateKbps: screenKbps,
      audioDtx: b('audio_dtx', d.audioDtx),
      audioRed: b('audio_red', d.audioRed),
      participantsCameraDefaultOff: b('participants_camera_default_off', d.participantsCameraDefaultOff),
      pauseHiddenVideo: b('pause_hidden_video', d.pauseHiddenVideo),
      recordingMode: rec,
      serverRecordingEngine: engine,
      fromServer: true,
    );
  }

  /// `live_config` of a join / start payload (the whole payload map), or [defaults] when it has none.
  static LiveConfig fromPayload(Object? payload) {
    if (payload is! Map) return defaults;
    final raw = payload['live_config'];
    return raw is Map ? parse(raw) : defaults;
  }

  /// 15, 24 or 30: the nearest of the three.
  static int snapCameraFps(int fps) {
    if (fps <= 19) return 15;
    if (fps <= 27) return 24;
    return 30;
  }

  /// The last config a join answered with in this app run: the pre-join page (which opens before the join call)
  /// starts the camera with it. Starts as [defaults].
  static LiveConfig lastKnown = defaults;

  /// Keeps [c] as [lastKnown] when it came from a server.
  static void remember(LiveConfig c) {
    if (c.fromServer) lastKnown = c;
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'video_codec': videoCodec.name,
        'weak_network': weakNetwork == LiveWeakNetwork.audioFirst ? 'audio_first' : 'adaptive',
        'camera_max_host': cameraMaxHost.label,
        'camera_max_participant': cameraMaxParticipant.label,
        'camera_fps': cameraFps,
        'camera_fps_host': cameraFpsHost,
        'screen_fps_max': screenFpsMax,
        'screen_bitrate_kbps': screenBitrateKbps,
        'audio_dtx': audioDtx,
        'audio_red': audioRed,
        'participants_camera_default_off': participantsCameraDefaultOff,
        'pause_hidden_video': pauseHiddenVideo,
        if (recordingMode != null) 'recording_mode': recordingMode!.name,
        'server_recording_engine': serverRecordingEngine.name,
      };

  @override
  bool operator ==(Object other) =>
      other is LiveConfig &&
      other.version == version &&
      other.videoCodec == videoCodec &&
      other.weakNetwork == weakNetwork &&
      other.cameraMaxHost == cameraMaxHost &&
      other.cameraMaxParticipant == cameraMaxParticipant &&
      other.cameraFps == cameraFps &&
      other.cameraFpsHost == cameraFpsHost &&
      other.screenFpsMax == screenFpsMax &&
      other.screenBitrateKbps == screenBitrateKbps &&
      other.audioDtx == audioDtx &&
      other.audioRed == audioRed &&
      other.participantsCameraDefaultOff == participantsCameraDefaultOff &&
      other.pauseHiddenVideo == pauseHiddenVideo &&
      other.recordingMode == recordingMode &&
      other.serverRecordingEngine == serverRecordingEngine &&
      other.fromServer == fromServer;

  @override
  int get hashCode => Object.hash(version, videoCodec, weakNetwork, cameraMaxHost, cameraMaxParticipant, cameraFps,
      cameraFpsHost, screenFpsMax, screenBitrateKbps, audioDtx, audioRed, participantsCameraDefaultOff, pauseHiddenVideo,
      recordingMode, serverRecordingEngine, fromServer);

  @override
  String toString() => 'LiveConfig(${toJson()}, fromServer: $fromServer)';
}
