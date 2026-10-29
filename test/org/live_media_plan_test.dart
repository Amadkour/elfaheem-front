// What the room publishes and receives (D-090, live_media_plan.dart): camera layers and bitrates per role cap,
// the codec rule, audio options, the receive rules.
import 'package:flutter_education_app/features/shared/live/live_config.dart';
import 'package:flutter_education_app/features/shared/live/live_media_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

void main() {
  group('camera layers', () {
    test('host 720p @ 24: 180p@15 · 360p · 720p, explicit bitrates', () {
      final l = cameraLayersFor(LiveCameraCap.p720, fps: 24);
      expect(l, const [
        LiveCameraLayer(320, 180, 15, 100),
        LiveCameraLayer(640, 360, 24, 380),
        LiveCameraLayer(1280, 720, 24, 1280),
      ]);
      // The whole camera upload when everything is watched (dynacast stops what nobody watches): ~1.8 Mbit/s,
      // was 1080p60 at 5 Mbit/s + two lower layers (~5.6 Mbit/s).
      expect(cameraUploadKbps(LiveCameraCap.p720, fps: 24), 1760);
    });

    test('participant 360p @ 24: two layers, under 0.5 Mbit/s', () {
      expect(cameraLayersFor(LiveCameraCap.p360, fps: 24), const [
        LiveCameraLayer(320, 180, 15, 100),
        LiveCameraLayer(640, 360, 24, 380),
      ]);
      expect(cameraUploadKbps(LiveCameraCap.p360, fps: 24), 480);
    });

    test('540p has three layers, 180p one', () {
      expect(cameraLayersFor(LiveCameraCap.p540, fps: 30).map((e) => e.height), [180, 360, 540]);
      expect(cameraLayersFor(LiveCameraCap.p180, fps: 30), const [LiveCameraLayer(320, 180, 15, 100)]);
    });

    test('bitrate per fps and codec', () {
      expect(cameraBitrateKbps(720, 30, LiveVideoCodec.vp8), 1500);
      expect(cameraBitrateKbps(720, 15, LiveVideoCodec.vp8), 980);
      expect(cameraBitrateKbps(720, 30, LiveVideoCodec.h264), 1650);
      expect(cameraBitrateKbps(720, 30, LiveVideoCodec.vp9), 1130);
      expect(cameraBitrateKbps(360, 30, LiveVideoCodec.vp8), 450);
      expect(cameraBitrateKbps(180, 30, LiveVideoCodec.vp8), 160);
    });

    test('capture options: the cap at camera_fps, front camera', () {
      final host = cameraCaptureFor(const LiveConfig(), host: true, deviceId: 'cam1');
      expect(host.params.dimensions.width, 1280);
      expect(host.params.dimensions.height, 720);
      expect(host.maxFrameRate, 24);
      expect(host.deviceId, 'cam1');
      expect(host.cameraPosition, CameraPosition.front);
      final student = cameraCaptureFor(const LiveConfig(), host: false);
      expect(student.params.dimensions.height, 360);
      expect(cameraCaptureDiffers(host, student), isTrue);
      expect(cameraCaptureDiffers(host, cameraCaptureFor(const LiveConfig(), host: true)), isFalse);
    });

    test('publish options: the top encoding, the two lower presets, backup VP8 behind H.264', () {
      final o = videoPublishFor(const LiveConfig(cameraFps: 30), host: true, codec: 'h264');
      expect(o.simulcast, isTrue);
      expect(o.videoCodec, 'h264');
      expect(o.videoEncoding?.maxBitrate, 1500000);
      expect(o.videoEncoding?.maxFramerate, 30);
      expect(o.videoSimulcastLayers.map((p) => p.dimensions.height), [180, 360]);
      expect(o.videoSimulcastLayers.first.encoding?.maxFramerate, 15);
      expect(o.backupVideoCodec.enabled, isTrue);
      expect(o.backupVideoCodec.codec, 'vp8');
      expect(o.degradationPreference, isNull); // the SDK's per-source default
      expect(videoPublishFor(const LiveConfig(), host: false, codec: 'vp8').backupVideoCodec.enabled, isFalse);
    });
  });

  group('codec', () {
    test('VP9 falls back to VP8 on Safari / iOS; H.264 on Firefox', () {
      expect(effectiveVideoCodec(LiveVideoCodec.vp9, const LiveCodecPlatform()), 'vp9');
      expect(effectiveVideoCodec(LiveVideoCodec.vp9, const LiveCodecPlatform(ios: true)), 'vp8');
      expect(effectiveVideoCodec(LiveVideoCodec.vp9, const LiveCodecPlatform(web: true, safari: true)), 'vp8');
      expect(effectiveVideoCodec(LiveVideoCodec.h264, const LiveCodecPlatform(ios: true)), 'h264');
      expect(effectiveVideoCodec(LiveVideoCodec.h264, const LiveCodecPlatform(web: true, firefox: true)), 'vp8');
      expect(effectiveVideoCodec(LiveVideoCodec.vp8, const LiveCodecPlatform(web: true, firefox: true)), 'vp8');
    });
  });

  group('audio', () {
    test('host 48 kbps, everyone else 24 kbps speech; DTX / RED from the config', () {
      final h = audioPublishFor(const LiveConfig(), host: true);
      expect(h.encoding?.maxBitrate, 48000);
      expect(h.dtx, isTrue);
      expect(h.red, isTrue);
      final s = audioPublishFor(const LiveConfig(audioDtx: false, audioRed: false), host: false);
      expect(s.encoding?.maxBitrate, 24000);
      expect(s.dtx, isFalse);
      expect(s.red, isFalse);
    });
  });

  group('receiving', () {
    test('subscription rules', () {
      expect(wantVideoSubscription(screen: false), isTrue);
      expect(wantVideoSubscription(screen: false, audioOnly: true), isFalse);
      expect(wantVideoSubscription(screen: true, audioOnly: true), isTrue, reason: 'a share stays (at LOW)');
      expect(wantVideoSubscription(screen: true, hiddenApp: true), isFalse);
      expect(wantVideoSubscription(screen: true, board: true), isFalse, reason: 'the board is drawn from vectors');
      expect(isBoardVideoName(kBoardVideoTrackName), isTrue);
      expect(isBoardVideoName('screenshare'), isFalse);
    });

    test('video budget per screen width', () {
      expect(liveVideoBudget(390), 4);
      expect(liveVideoBudget(800), 6);
      expect(liveVideoBudget(1440), 9);
    });

    test('the board goes into a recording only in server mode, while recording and presenting, where supported', () {
      final server = LiveConfig.parse({'recording_mode': 'server'});
      expect(wantBoardVideo(config: server, roomRecording: true, presentingBoard: true, supported: true), isTrue);
      expect(wantBoardVideo(config: server, roomRecording: false, presentingBoard: true, supported: true), isFalse);
      expect(wantBoardVideo(config: server, roomRecording: true, presentingBoard: false, supported: true), isFalse);
      expect(wantBoardVideo(config: server, roomRecording: true, presentingBoard: true, supported: false), isFalse);
      final client = LiveConfig.parse({'recording_mode': 'client'});
      expect(wantBoardVideo(config: client, roomRecording: true, presentingBoard: true, supported: true), isFalse);
      expect(wantBoardVideo(config: LiveConfig.defaults, roomRecording: true, presentingBoard: true, supported: true), isFalse);
    });
  });
}
