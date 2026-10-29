// lib/features/shared/live/live_media_plan.dart
//
// What the room publishes and receives, from the super admin's LiveConfig (D-090). Pure: no Room, no channels —
// LiveKit's option classes are plain values, so the plan is unit-tested (test/org/live_media_plan_test.dart).
//
//   camera      capture = the role's cap (host 720p / participant 360p by default) at camera_fps; simulcast layers
//               180p @ ≤15 fps · 360p · the cap (the SDK keeps the layers that fit under the capture: 720p → 3,
//               540p → 3, 360p → 2, 180p → 1), each with an explicit max bitrate (cameraBitrateKbps).
//   codec       video_codec, with VP8 as the backup codec for H.264 / VP9 (a subscriber that cannot decode the
//               primary gets VP8; LiveKit encodes the backup only while someone needs it). VP9 is not used on
//               Safari / iOS (no reliable SVC encoder there): VP8 instead.
//   audio       Opus mono: 48 kbps for the host (their mic may carry shared device audio, D-080), 24 kbps speech for
//               everyone else; DTX and RED from the config.
//   receiving   wantVideoSubscription (audio-only tier, a hidden app, the board's recording track) and
//               liveVideoBudget (how many remote videos a screen decodes at once).
library;

import 'dart:math' as math;

import 'package:livekit_client/livekit_client.dart';

import 'live_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Camera
// ─────────────────────────────────────────────────────────────────────────────

/// One simulcast layer as plain numbers (for tests, the notes and the estimates).
class LiveCameraLayer {
  const LiveCameraLayer(this.width, this.height, this.fps, this.kbps);

  final int width;
  final int height;
  final int fps;
  final int kbps;

  VideoParameters get parameters => VideoParameters(
        dimensions: VideoDimensions(width, height),
        encoding: VideoEncoding(maxBitrate: kbps * 1000, maxFramerate: fps),
      );

  @override
  bool operator ==(Object other) =>
      other is LiveCameraLayer && other.width == width && other.height == height && other.fps == fps && other.kbps == kbps;

  @override
  int get hashCode => Object.hash(width, height, fps, kbps);

  @override
  String toString() => '${height}p@$fps ${kbps}kbps';
}

/// The top bitrate (kbps) of a [height]p camera layer at [fps] for [codec]. VP8 at 30 fps: 180p 160 · 360p 450 ·
/// 540p 800 · 720p 1500 (a talking head; LiveKit's own presets are 1700 for 720p); 24 fps × 0.85, 15 fps × 0.65;
/// H.264 × 1.1 (phone hardware encoders need a little more for the same picture); VP9 × 0.75 (SVC, all layers).
int cameraBitrateKbps(int height, int fps, LiveVideoCodec codec) {
  final base30 = switch (height) {
    <= 180 => 160,
    <= 360 => 450,
    <= 540 => 800,
    _ => 1500,
  };
  final f = fps <= 15 ? 0.65 : (fps <= 24 ? 0.85 : 1.0);
  final c = switch (codec) {
    LiveVideoCodec.vp8 => 1.0,
    LiveVideoCodec.h264 => 1.1,
    LiveVideoCodec.vp9 => 0.75,
  };
  return ((base30 * f * c) / 10).round() * 10;
}

/// The layers a [cap] camera sends at [fps]: 180p at ≤ 15 fps always (what a weak downlink falls back to), 360p
/// when the cap is above it, and the cap itself.
List<LiveCameraLayer> cameraLayersFor(LiveCameraCap cap, {required int fps, LiveVideoCodec codec = LiveVideoCodec.vp8}) {
  final lowFps = math.min(15, fps);
  final low = LiveCameraLayer(320, 180, lowFps, cameraBitrateKbps(180, lowFps, codec));
  if (cap == LiveCameraCap.p180) return [low];
  final mid = LiveCameraLayer(640, 360, fps, cameraBitrateKbps(360, fps, codec));
  if (cap == LiveCameraCap.p360) return [low, mid];
  return [low, mid, LiveCameraLayer(cap.width, cap.height, fps, cameraBitrateKbps(cap.height, fps, codec))];
}

/// The upload of a camera when every layer is wanted (dynacast stops the ones nobody watches), in kbps.
int cameraUploadKbps(LiveCameraCap cap, {required int fps, LiveVideoCodec codec = LiveVideoCodec.vp8}) =>
    cameraLayersFor(cap, fps: fps, codec: codec).fold(0, (s, l) => s + l.kbps);

/// The camera this role captures (the cap's frame at camera_fps): the pre-join preview, the room's default for a
/// camera turned on later, and therefore what a muted camera restarts with.
CameraCaptureOptions cameraCaptureFor(LiveConfig c, {required bool host, String? deviceId}) {
  final cap = c.cameraCapFor(host: host);
  final top = cameraLayersFor(cap, fps: c.cameraFps, codec: c.videoCodec).last;
  return CameraCaptureOptions(
    deviceId: deviceId,
    cameraPosition: CameraPosition.front,
    maxFrameRate: c.cameraFps.toDouble(),
    params: VideoParameters(dimensions: VideoDimensions(cap.width, cap.height), encoding: top.parameters.encoding),
  );
}

/// True when a capture made with [current] is not the one the plan wants (the pre-join track is made again).
bool cameraCaptureDiffers(VideoCaptureOptions current, CameraCaptureOptions want) =>
    current.params.dimensions.width != want.params.dimensions.width ||
    current.params.dimensions.height != want.params.dimensions.height ||
    (current.maxFrameRate ?? 30) != (want.maxFrameRate ?? 30);

// ─────────────────────────────────────────────────────────────────────────────
// Codec
// ─────────────────────────────────────────────────────────────────────────────

/// What this device can encode well. Plain flags so the rule is testable.
class LiveCodecPlatform {
  const LiveCodecPlatform({this.web = false, this.safari = false, this.firefox = false, this.ios = false});

  final bool web;
  final bool safari;
  final bool firefox;
  final bool ios;

  /// The running device (lkPlatformIs / lkBrowser are safe on every platform).
  static LiveCodecPlatform current() {
    final web = lkPlatformIs(PlatformType.web);
    final browser = web ? lkBrowser() : null;
    return LiveCodecPlatform(
      web: web,
      safari: browser == BrowserType.safari,
      firefox: browser == BrowserType.firefox,
      ios: lkPlatformIs(PlatformType.iOS),
    );
  }
}

/// The codec string LiveKit gets: VP9 falls back to VP8 on Safari / iOS (its encoder there is slow or missing and
/// SVC publishing is unreliable); H.264 falls back to VP8 on Firefox (no H.264 simulcast).
String effectiveVideoCodec(LiveVideoCodec want, LiveCodecPlatform p) {
  switch (want) {
    case LiveVideoCodec.vp9:
      if (p.ios || p.safari) return 'vp8';
      return 'vp9';
    case LiveVideoCodec.h264:
      if (p.firefox) return 'vp8';
      return 'h264';
    case LiveVideoCodec.vp8:
      return 'vp8';
  }
}

/// VP8 behind H.264 / VP9 (Android's software decoders have no H.264; old browsers no VP9); none behind VP8.
BackupVideoCodec backupCodecFor(String codec) =>
    BackupVideoCodec(enabled: codec != 'vp8', codec: 'vp8', simulcast: true);

/// The room's video publish defaults: the camera layers of the role's cap, the codec + backup, and the screen
/// share's encoding (the screen-share paths that publish their own track pass their own options).
VideoPublishOptions videoPublishFor(LiveConfig c, {required bool host, required String codec, VideoEncoding? screenEncoding}) {
  final cap = c.cameraCapFor(host: host);
  final layers = cameraLayersFor(cap, fps: c.cameraFps, codec: c.videoCodec);
  return VideoPublishOptions(
    videoCodec: codec,
    simulcast: true,
    videoEncoding: layers.last.parameters.encoding,
    // The two lower presets; the SDK adds the capture's own frame on top (and drops what does not fit under it).
    videoSimulcastLayers: [
      cameraLayersFor(LiveCameraCap.p360, fps: c.cameraFps, codec: c.videoCodec)[0].parameters,
      cameraLayersFor(LiveCameraCap.p360, fps: c.cameraFps, codec: c.videoCodec)[1].parameters,
    ],
    screenShareEncoding: screenEncoding,
    backupVideoCodec: backupCodecFor(codec),
    // null = the SDK's per-source default: camera keeps the frame rate (the layers carry resolution), a screen
    // share keeps the resolution (text).
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio
// ─────────────────────────────────────────────────────────────────────────────

/// Opus mono. The host gets music-grade 48 kbps (an Android share mixes device audio into the mic, D-080); everyone
/// else speech-grade 24 kbps. DTX (no packets in silence) and RED (redundant audio against loss) from the config.
AudioPublishOptions audioPublishFor(LiveConfig c, {required bool host}) => AudioPublishOptions(
      encoding: host ? AudioEncoding.presetMusic : AudioEncoding.presetSpeech,
      dtx: c.audioDtx,
      red: c.audioRed,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Receiving
// ─────────────────────────────────────────────────────────────────────────────

/// The whiteboard's recording track (published only while a server recording runs, D-090) is named this: other
/// apps ignore and unsubscribe it (they draw the board from its vectors).
const String kBoardVideoTrackName = 'whiteboard';

/// A publication that is the whiteboard's recording track.
bool isBoardVideoName(String? name) => name == kBoardVideoTrackName;

/// Whether this device publishes its presented board as the recording track: server recording mode, a server
/// recording running now, this device presenting a board, and a platform that can feed a track (web, Android).
bool wantBoardVideo({
  required LiveConfig config,
  required bool roomRecording,
  required bool presentingBoard,
  required bool supported,
}) =>
    config.serverRecords && roomRecording && presentingBoard && supported;

/// Whether a remote video should be received now. [screen]: a screen share; [board]: the whiteboard's recording
/// track; [audioOnly]: the weak-network governor dropped to audio (screen shares stay, at the lowest layer);
/// [hiddenApp]: the app is in the background and pause_hidden_video is on.
bool wantVideoSubscription({required bool screen, bool board = false, bool audioOnly = false, bool hiddenApp = false}) {
  if (board || hiddenApp) return false;
  if (audioOnly && !screen) return false;
  return true;
}

/// How many remote videos a screen [width] logical px wide decodes at once (the stage + the strip): a phone 4, a
/// tablet 6, a desktop 9. Tiles past the budget show the avatar (no renderer = adaptive stream pauses them).
int liveVideoBudget(double width) {
  if (width < 600) return 4;
  if (width < 1100) return 6;
  return 9;
}
