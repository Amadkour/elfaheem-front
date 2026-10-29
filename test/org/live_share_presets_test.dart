// The Android share's pure rules (share_presets.dart): the Detail / Motion presets (D14), the
// capture size, the mic while device audio rides on the mic track, and the native answers.
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/share_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

void main() {
  group('presets', () {
    test('detail: 1080p long side, 15 fps, 2.5 Mbps, keeps resolution', () {
      final p = SharePreset.of(ShareQuality.detail);
      expect(p.maxLongSide, 1920);
      expect(p.maxFps, 15);
      expect(p.maxBitrate, 2500000);
      expect(p.degradation, DegradationPreference.maintainResolution);
    });

    test('motion: 720p, 30 fps, 3 Mbps, keeps frame rate', () {
      final p = SharePreset.of(ShareQuality.motion);
      expect(p.maxLongSide, 1280);
      expect(p.maxFps, 30);
      expect(p.maxBitrate, 3000000);
      expect(p.degradation, DegradationPreference.maintainFramerate);
    });

    test('size keeps the aspect, never upscales, even numbers', () {
      expect(SharePreset.motion.sizeFor(1440, 3120), (590, 1280));
      expect(SharePreset.detail.sizeFor(1440, 3120), (886, 1920));
      expect(SharePreset.motion.sizeFor(3120, 1440), (1280, 590));
      expect(SharePreset.detail.sizeFor(1080, 1920), (1080, 1920));
      expect(SharePreset.detail.sizeFor(721, 1001), (720, 1000));
      expect(SharePreset.detail.sizeFor(0, 100), (0, 0));
    });

    test('publish options: one layer with the preset encoding', () {
      final o = SharePreset.detail.publishOptions;
      expect(o.simulcast, isFalse);
      expect(o.screenShareEncoding?.maxBitrate, 2500000);
      expect(o.screenShareEncoding?.maxFramerate, 15);
      expect(o.degradationPreference, DegradationPreference.maintainResolution);
      final c = SharePreset.motion.captureOptions(590, 1280);
      expect(c.params.dimensions.width, 590);
      expect(c.params.dimensions.height, 1280);
      expect(c.maxFrameRate, 30);
    });

    test('native args', () {
      expect(SharePreset.motion.nativeArgs(deviceAudio: true), {'maxLongSide': 1280, 'fps': 30, 'deviceAudio': true});
    });
  });

  group('mic policy', () {
    const on = ShareMicState(trackEnabled: true, softMuted: false);
    const off = ShareMicState(trackEnabled: false, softMuted: false);
    const soft = ShareMicState(trackEnabled: true, softMuted: true);

    test('a share without device audio never touches the mic', () {
      expect(ShareMicPolicy.onShareStart(micOn: false, deviceAudio: false), off);
      expect(ShareMicPolicy.onShareStart(micOn: true, deviceAudio: false), on);
    });

    test('with device audio a muted mic stays inaudible (track on, samples zeroed)', () {
      final s = ShareMicPolicy.onShareStart(micOn: false, deviceAudio: true);
      expect(s, soft);
      expect(s.micAudible, isFalse);
      expect(ShareMicPolicy.onShareStart(micOn: true, deviceAudio: true), on);
    });

    test('toggling during device audio flips only the soft mute', () {
      expect(ShareMicPolicy.onToggle(on, deviceAudio: true), soft);
      expect(ShareMicPolicy.onToggle(soft, deviceAudio: true), on);
      expect(ShareMicPolicy.onToggle(on, deviceAudio: false), off);
      expect(ShareMicPolicy.onToggle(off, deviceAudio: false), on);
    });

    test('share end turns a soft mute into a real mute', () {
      expect(ShareMicPolicy.onShareStop(soft), off);
      expect(ShareMicPolicy.onShareStop(on), on);
      expect(ShareMicPolicy.onShareStop(off), off);
    });

    test('start → mute → stop → the mic ends muted, never audible in between', () {
      var s = ShareMicPolicy.onShareStart(micOn: true, deviceAudio: true);
      s = ShareMicPolicy.onToggle(s, deviceAudio: true);
      expect(s.micAudible, isFalse);
      s = ShareMicPolicy.onShareStop(s);
      expect(s, off);
    });
  });

  group('native answers', () {
    test('start outcome', () {
      final ok = ShareStartOutcome.parse({'ok': true, 'width': 1440, 'height': 3120, 'deviceAudio': 'started'});
      expect(ok.ok, isTrue);
      expect(ok.width, 1440);
      expect(ok.deviceAudioOn, isTrue);
      expect(ShareStartOutcome.parse({'ok': false, 'denied': true}).denied, isTrue);
      expect(ShareStartOutcome.parse({'ok': true, 'deviceAudio': 'no_permission'}).deviceAudioFailed, isTrue);
      expect(ShareStartOutcome.parse({'ok': true, 'deviceAudio': 'failed: x'}).deviceAudioFailed, isTrue);
      expect(ShareStartOutcome.parse({'ok': true, 'deviceAudio': 'unsupported'}).deviceAudioFailed, isFalse);
      expect(ShareStartOutcome.parse(null).ok, isFalse);
      expect(ShareStartOutcome.parse(true).ok, isTrue);
    });

    test('events', () {
      expect(LiveNativeEvent.parse({'event': 'shareStopped', 'reason': 'system'})!.stoppedOutside, isTrue);
      expect(LiveNativeEvent.parse({'event': 'shareStopped', 'reason': 'task_removed'})!.stoppedOutside, isTrue);
      expect(LiveNativeEvent.parse({'event': 'shareStopped', 'reason': 'user'})!.stoppedOutside, isFalse);
      expect(LiveNativeEvent.parse({'event': 'audioInterruption', 'active': true})!.interruption, isTrue);
      expect(LiveNativeEvent.parse({'event': 'audioInterruption', 'active': false})!.interruption, isFalse);
      expect(LiveNativeEvent.parse({'event': 'shareStarted'})!.interruption, isNull);
      expect(LiveNativeEvent.parse('x'), isNull);
      expect(LiveNativeEvent.parse({'event': ''}), isNull);
    });
  });
}
