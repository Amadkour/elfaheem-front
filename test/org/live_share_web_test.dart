// The web screen share's pure parts (share_presets.dart): the same Detail / Motion presets as Android turned into
// getDisplayMedia constraints and a contentHint (W7), the size the browser gave, the tab-audio track's publish
// options (W1), and which browsers can share audio at all.
import 'package:flutter_education_app/features/live/room/widgets/share_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

const _chrome =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const _edge = '$_chrome Edg/130.0.0.0';
const _firefox = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0';
const _safari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const _androidChrome =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

void main() {
  group('getDisplayMedia constraints', () {
    test('detail: 1080p long side, 15 fps, contentHint detail', () {
      final c = SharePreset.detail.webDisplayMediaConstraints(audio: true);
      final video = c['video'] as Map;
      expect(video['width'], {'max': 1920});
      expect(video['height'], {'max': 1920});
      expect(video['frameRate'], {'ideal': 15, 'max': 15});
      expect(SharePreset.detail.contentHint, 'detail');
      expect(SharePreset.detail.degradation, DegradationPreference.maintainResolution);
    });

    test('motion: 720p, 30 fps, contentHint motion', () {
      final c = SharePreset.motion.webDisplayMediaConstraints(audio: false);
      final video = c['video'] as Map;
      expect(video['width'], {'max': 1280});
      expect(video['frameRate'], {'ideal': 30, 'max': 30});
      expect(SharePreset.motion.contentHint, 'motion');
      expect(SharePreset.motion.degradation, DegradationPreference.maintainFramerate);
    });

    test('audio: system audio included and still played locally; the app tab left out; switching allowed', () {
      final on = SharePreset.detail.webDisplayMediaConstraints(audio: true);
      expect(on['audio'], isA<Map>());
      expect((on['audio'] as Map)['suppressLocalAudioPlayback'], isFalse);
      expect((on['audio'] as Map)['echoCancellation'], isFalse);
      expect(on['systemAudio'], 'include');
      expect(on['suppressLocalAudioPlayback'], isFalse);
      expect(on['selfBrowserSurface'], 'exclude');
      expect(on['surfaceSwitching'], 'include');
      final off = SharePreset.detail.webDisplayMediaConstraints(audio: false);
      expect(off['audio'], isFalse);
      expect(off['systemAudio'], 'exclude');
    });

    test('two layers with the preset encoding (shared with Android)', () {
      final o = SharePreset.motion.publishOptions;
      expect(o.simulcast, isTrue);
      expect(o.screenShareEncoding?.maxFramerate, 30);
      expect(o.screenShareEncoding?.maxBitrate, 3000000);
    });

    test('the tab audio track: music quality, no DTX', () {
      const a = SharePreset.screenAudioPublishOptions;
      expect(a.dtx, isFalse);
      expect(a.encoding?.maxBitrate, 128000);
      expect(a.name, 'screen_share_audio');
    });
  });

  group('the size the browser gave', () {
    test('capped by the preset, aspect kept', () {
      expect(SharePreset.detail.sizeFromSettings({'width': 2560, 'height': 1440}), (1920, 1080));
      expect(SharePreset.motion.sizeFromSettings({'width': 1920.0, 'height': 1080.0}), (1280, 720));
      expect(SharePreset.detail.sizeFromSettings({'width': 1366, 'height': 768}), (1366, 768));
    });

    test('nothing reported: a 16:9 frame of the preset', () {
      expect(SharePreset.detail.sizeFromSettings(const {}), (1920, 1080));
      expect(SharePreset.motion.sizeFromSettings({'width': 'x'}), (1280, 720));
    });
  });

  group('which browsers share audio', () {
    test('Chromium yes, Firefox and Safari no, phones never', () {
      expect(webDisplayAudioSupported(userAgent: _chrome, suppressLocalAudioPlaybackSupported: false), isTrue);
      expect(webDisplayAudioSupported(userAgent: _edge, suppressLocalAudioPlaybackSupported: true), isTrue);
      expect(webDisplayAudioSupported(userAgent: _firefox, suppressLocalAudioPlaybackSupported: false), isFalse);
      expect(webDisplayAudioSupported(userAgent: _safari, suppressLocalAudioPlaybackSupported: false), isFalse);
      expect(webDisplayAudioSupported(userAgent: _androidChrome, suppressLocalAudioPlaybackSupported: true), isFalse);
    });

    test('the feature test wins over an unknown user agent', () {
      expect(webDisplayAudioSupported(userAgent: 'SomeBrowser/1.0', suppressLocalAudioPlaybackSupported: true), isTrue);
      expect(webDisplayAudioSupported(userAgent: 'SomeBrowser/1.0', suppressLocalAudioPlaybackSupported: false), isFalse);
    });
  });
}
