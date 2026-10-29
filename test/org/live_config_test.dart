// The super admin's live media settings (D-090): live_config.dart parses `live_config` from every join / start
// payload; anything missing or unknown is the recommended default.
import 'package:flutter_education_app/features/shared/live/live_config.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart' show JoinOutcome;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaults', () {
    test('an older server (no live_config) gets the recommended values', () {
      final c = LiveConfig.fromPayload({'token': 't', 'ws_url': 'wss://x'});
      expect(c, LiveConfig.defaults);
      expect(c.fromServer, isFalse);
      expect(c.videoCodec, LiveVideoCodec.vp8);
      expect(c.weakNetwork, LiveWeakNetwork.adaptive);
      expect(c.cameraMaxHost, LiveCameraCap.p720);
      expect(c.cameraMaxParticipant, LiveCameraCap.p360);
      expect(c.cameraFps, 24);
      expect(c.screenFpsMax, 30);
      expect(c.screenBitrateKbps, 2500);
      expect(c.audioDtx, isTrue);
      expect(c.audioRed, isTrue);
      expect(c.participantsCameraDefaultOff, isTrue);
      expect(c.pauseHiddenVideo, isTrue);
      expect(c.recordingMode, isNull);
      // An older server: the teacher's device records as it always did.
      expect(c.deviceRecorder, isTrue);
      expect(c.serverRecords, isFalse);
    });

    test('not a map → defaults, never throws', () {
      expect(LiveConfig.parse(null), LiveConfig.defaults);
      expect(LiveConfig.parse('vp9'), LiveConfig.defaults);
      expect(LiveConfig.parse([1, 2]), LiveConfig.defaults);
      expect(LiveConfig.fromPayload({'live_config': 'x'}), LiveConfig.defaults);
    });
  });

  group('parse', () {
    test('the whole v1 contract', () {
      final c = LiveConfig.parse({
        'v': 1,
        'video_codec': 'h264',
        'weak_network': 'audio_first',
        'camera_max_host': '540p',
        'camera_max_participant': '180p',
        'camera_fps': 30,
        'screen_fps_max': 10,
        'screen_bitrate_kbps': 4000,
        'audio_dtx': false,
        'audio_red': false,
        'participants_camera_default_off': false,
        'pause_hidden_video': false,
        'recording_mode': 'server',
        'server_recording_engine': 'media',
      });
      expect(c.fromServer, isTrue);
      expect(c.videoCodec, LiveVideoCodec.h264);
      expect(c.weakNetwork, LiveWeakNetwork.audioFirst);
      expect(c.cameraMaxHost, LiveCameraCap.p540);
      expect(c.cameraMaxParticipant, LiveCameraCap.p180);
      expect(c.cameraFps, 30);
      expect(c.screenFpsMax, 10);
      expect(c.screenBitrateKbps, 4000);
      expect(c.audioDtx, isFalse);
      expect(c.audioRed, isFalse);
      expect(c.participantsCameraDefaultOff, isFalse);
      expect(c.pauseHiddenVideo, isFalse);
      expect(c.recordingMode, LiveRecordingMode.server);
      expect(c.serverRecordingEngine, LiveServerRecordingEngine.media);
      expect(c.deviceRecorder, isFalse);
      expect(c.serverRecords, isTrue);
    });

    test('every field optional: a partial config keeps the defaults for the rest', () {
      final c = LiveConfig.parse({'video_codec': 'vp9'});
      expect(c.videoCodec, LiveVideoCodec.vp9);
      expect(c.cameraMaxHost, LiveConfig.defaults.cameraMaxHost);
      expect(c.recordingMode, isNull);
      expect(c.fromServer, isTrue);
    });

    test('client mode: the device records', () {
      final c = LiveConfig.parse({'recording_mode': 'client'});
      expect(c.recordingMode, LiveRecordingMode.client);
      expect(c.deviceRecorder, isTrue);
      expect(c.serverRecords, isFalse);
    });

    test('tolerant: case, dashes, "720" without p, numbers as strings, bools as strings', () {
      final c = LiveConfig.parse({
        'video_codec': 'H264',
        'weak_network': 'Audio-First',
        'camera_max_host': '720',
        'camera_max_participant': 540,
        'camera_fps': '15',
        'screen_bitrate_kbps': '1500',
        'audio_dtx': 'false',
        'pause_hidden_video': 0,
      });
      expect(c.videoCodec, LiveVideoCodec.h264);
      expect(c.weakNetwork, LiveWeakNetwork.audioFirst);
      expect(c.cameraMaxHost, LiveCameraCap.p720);
      expect(c.cameraMaxParticipant, LiveCameraCap.p540);
      expect(c.cameraFps, 15);
      expect(c.screenBitrateKbps, 1500);
      expect(c.audioDtx, isFalse);
      expect(c.pauseHiddenVideo, isFalse);
    });

    test('out of range is clamped / snapped; unknown values are the defaults', () {
      final c = LiveConfig.parse({
        'video_codec': 'av1',
        'weak_network': 'nope',
        'camera_max_host': '180p', // below the host floor
        'camera_max_participant': '720p', // above the participant ceiling
        'camera_fps': 60,
        'screen_fps_max': 90,
        'screen_bitrate_kbps': 50,
        'recording_mode': 'cloud',
      });
      expect(c.videoCodec, LiveVideoCodec.vp8);
      expect(c.weakNetwork, LiveWeakNetwork.adaptive);
      expect(c.cameraMaxHost, LiveCameraCap.p360);
      expect(c.cameraMaxParticipant, LiveCameraCap.p540);
      expect(c.cameraFps, 30);
      expect(c.screenFpsMax, 30);
      expect(c.screenBitrateKbps, 500);
      expect(c.recordingMode, isNull);
      expect(LiveConfig.parse({'screen_fps_max': 1, 'screen_bitrate_kbps': 99999}).screenFpsMax, 5);
      expect(LiveConfig.parse({'screen_bitrate_kbps': 99999}).screenBitrateKbps, 6000);
    });

    test('camera fps snaps to 15 / 24 / 30', () {
      expect(LiveConfig.snapCameraFps(5), 15);
      expect(LiveConfig.snapCameraFps(19), 15);
      expect(LiveConfig.snapCameraFps(20), 24);
      expect(LiveConfig.snapCameraFps(27), 24);
      expect(LiveConfig.snapCameraFps(28), 30);
    });

    test('toJson round-trips', () {
      final c = LiveConfig.parse({
        'video_codec': 'vp9',
        'weak_network': 'audio_first',
        'camera_max_host': '360p',
        'recording_mode': 'client',
      });
      expect(LiveConfig.parse(c.toJson()), c);
    });
  });

  group('roles', () {
    test('the camera cap and the camera at the start follow the role', () {
      const c = LiveConfig();
      expect(c.cameraCapFor(host: true), LiveCameraCap.p720);
      expect(c.cameraCapFor(host: false), LiveCameraCap.p360);
      expect(c.cameraStartsOn(host: true), isTrue);
      expect(c.cameraStartsOn(host: false), isFalse);
      expect(const LiveConfig(participantsCameraDefaultOff: false).cameraStartsOn(host: false), isTrue);
    });
  });

  group('join payloads', () {
    test('JoinOutcome carries live_config to the room credentials', () {
      final o = JoinOutcome.parse({
        'url': 'wss://lk',
        'token': 't',
        'live_config': {'v': 1, 'video_codec': 'h264', 'recording_mode': 'server'},
      });
      expect(o.liveConfig.videoCodec, LiveVideoCodec.h264);
      final live = o.live(sessionId: -4);
      expect(live.liveConfig.recordingMode, LiveRecordingMode.server);
      expect(live.toJson['live_config'], isA<Map<String, Object?>>());
    });

    test('lastKnown keeps only what a server sent', () {
      final before = LiveConfig.lastKnown;
      addTearDown(() => LiveConfig.lastKnown = before);
      LiveConfig.remember(LiveConfig.defaults);
      expect(LiveConfig.lastKnown, before);
      final c = LiveConfig.parse({'camera_fps': 15});
      LiveConfig.remember(c);
      expect(LiveConfig.lastKnown, c);
    });
  });
}
