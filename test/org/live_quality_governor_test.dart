// The weak-network fix (D-090, live_quality_governor.dart): straight down on a bad sample, one step up per hold of
// good samples, a doubled hold + a ceiling after a step up that broke the link (no 180p ↔ 720p flapping), audio
// only under audio_first, "Show video". Replays the 2026-10-29 bench shapes (docs/live/NOTES.md).
import 'package:flutter_education_app/features/shared/live/live_quality_governor.dart';
import 'package:flutter_test/flutter_test.dart';

const _good = LiveNetSample(rating: LiveLinkRating.excellent, lossPct: 0);
const _poor = LiveNetSample(rating: LiveLinkRating.poor, lossPct: 12);
const _frozen = LiveNetSample(rating: LiveLinkRating.good, lossPct: 0, frozenTracks: 1);
const _jitter = LiveNetSample(rating: LiveLinkRating.good, lossPct: 4); // reordering looks like a few % loss

void main() {
  final t0 = DateTime(2026, 10, 29, 12);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  group('verdicts', () {
    test('bad / fair / good / unknown', () {
      expect(LiveQualityGovernor.verdictOf(_poor), LiveNetVerdict.bad);
      expect(LiveQualityGovernor.verdictOf(_frozen), LiveNetVerdict.bad);
      expect(LiveQualityGovernor.verdictOf(const LiveNetSample(pausedTracks: 1)), LiveNetVerdict.bad);
      expect(LiveQualityGovernor.verdictOf(const LiveNetSample(rating: LiveLinkRating.lost)), LiveNetVerdict.bad);
      expect(LiveQualityGovernor.verdictOf(const LiveNetSample(rating: LiveLinkRating.excellent, lossPct: 9)), LiveNetVerdict.bad);
      expect(LiveQualityGovernor.verdictOf(_jitter), LiveNetVerdict.fair);
      expect(LiveQualityGovernor.verdictOf(_good), LiveNetVerdict.good);
      expect(LiveQualityGovernor.verdictOf(const LiveNetSample(lossPct: 0.5)), LiveNetVerdict.good);
      expect(LiveQualityGovernor.verdictOf(const LiveNetSample()), LiveNetVerdict.unknown);
    });
  });

  group('adaptive', () {
    test('a freeze drops to LOW at once (the SFU took ~25 s and froze 720p for ~15 s)', () {
      final g = LiveQualityGovernor();
      expect(g.tier, LiveVideoTier.high);
      expect(g.update(at(0), _good), isFalse);
      expect(g.update(at(2), _frozen), isTrue);
      expect(g.tier, LiveVideoTier.low);
      expect(g.lowered, isTrue);
    });

    test('one step up per hold of good samples', () {
      final g = LiveQualityGovernor()..update(at(0), _poor);
      expect(g.tier, LiveVideoTier.low);
      for (var s = 2; s < 14; s += 2) {
        g.update(at(s), _good);
      }
      expect(g.tier, LiveVideoTier.low, reason: 'the hold starts with the first good sample at 2 s');
      g.update(at(14), _good);
      expect(g.tier, LiveVideoTier.medium);
      g.update(at(20), _good);
      expect(g.tier, LiveVideoTier.medium, reason: 'the next step waits a full hold again');
      g.update(at(26), _good);
      expect(g.tier, LiveVideoTier.high);
      expect(g.lowered, isFalse);
    });

    test('fair samples (jitter) hold the tier: no step up, no step down', () {
      final g = LiveQualityGovernor()..update(at(0), _poor);
      for (var s = 2; s < 120; s += 2) {
        g.update(at(s), _jitter);
      }
      expect(g.tier, LiveVideoTier.low);
      final h = LiveQualityGovernor();
      for (var s = 0; s < 60; s += 2) {
        h.update(at(s), _jitter);
      }
      expect(h.tier, LiveVideoTier.high);
    });

    test('a 1 Mbit/s link (720p does not fit, 360p does) settles on MEDIUM instead of flapping', () {
      final g = LiveQualityGovernor();
      // The link: every sample is good unless the tier is HIGH (720p overshoots it).
      LiveNetSample link() => g.tier == LiveVideoTier.high ? _poor : _good;
      final tiers = <LiveVideoTier>[];
      var drops = 0;
      for (var s = 0; s <= 600; s += 2) {
        final before = g.tier;
        g.update(at(s), link());
        if (g.tier.index < before.index) drops++;
        tiers.add(g.tier);
      }
      // The first drop at 0 s, one probe of 720p ~26 s in, 360p inside the 4-minute ceiling, one more probe, then
      // an 8-minute ceiling. At most 3 drops in 10 minutes (the SFU flapped every ~5 s
      // under jitter and stayed on 180p under the cap).
      expect(drops, lessThanOrEqualTo(3));
      final medium = tiers.where((t) => t == LiveVideoTier.medium).length;
      expect(medium / tiers.length, greaterThan(0.8));
      expect(g.ceiling == LiveVideoTier.medium || g.tier == LiveVideoTier.medium, isTrue);
    });

    test('the hold doubles on a flap and resets after a calm period', () {
      final g = LiveQualityGovernor()..update(at(0), _poor);
      expect(g.upHold, const Duration(seconds: 12));
      g.update(at(2), _good);
      g.update(at(14), _good); // → medium
      expect(g.tier, LiveVideoTier.medium);
      g.update(at(16), _poor); // the step up broke it
      expect(g.tier, LiveVideoTier.low);
      expect(g.upHold, const Duration(seconds: 24));
      expect(g.ceiling, LiveVideoTier.low);
      // Good for a long time: the ceiling keeps it at LOW until the calm period ends, then the hold is back to 12 s.
      for (var s = 18; s < 16 + 240; s += 2) {
        g.update(at(s), _good);
      }
      expect(g.tier, LiveVideoTier.low);
      g.update(at(16 + 240), _good);
      expect(g.upHold, const Duration(seconds: 12));
      expect(g.ceiling, LiveVideoTier.high);
      expect(g.tier, LiveVideoTier.medium);
    });

    test('adaptive never goes audio-only', () {
      final g = LiveQualityGovernor();
      for (var s = 0; s < 120; s += 2) {
        g.update(at(s), _poor);
      }
      expect(g.tier, LiveVideoTier.low);
    });
  });

  group('audio first', () {
    test('bad for 8 s at LOW → audio only; recovery climbs back step by step', () {
      final g = LiveQualityGovernor(audioFirst: true);
      g.update(at(0), _poor);
      expect(g.tier, LiveVideoTier.low);
      g.update(at(4), _poor);
      expect(g.tier, LiveVideoTier.low);
      g.update(at(8), _poor);
      expect(g.tier, LiveVideoTier.audioOnly);
      g.update(at(10), _good);
      g.update(at(22), _good);
      expect(g.tier, LiveVideoTier.low);
    });

    test('"Show video" leaves audio only for LOW and turns the audio-only step off', () {
      final g = LiveQualityGovernor(audioFirst: true)
        ..update(at(0), _poor)
        ..update(at(8), _poor);
      expect(g.tier, LiveVideoTier.audioOnly);
      expect(g.forceVideo(at(9)), isTrue);
      expect(g.tier, LiveVideoTier.low);
      expect(g.videoForced, isTrue);
      for (var s = 10; s < 60; s += 2) {
        g.update(at(s), _poor);
      }
      expect(g.tier, LiveVideoTier.low);
      expect(g.forceVideo(at(61)), isFalse);
    });
  });

  group('stats window', () {
    LiveVideoStatsPoint p(num ts, {num frames = 0, num lost = 0, num rx = 0, bool play = true, bool paused = false, bool camera = true}) =>
        LiveVideoStatsPoint(
            sid: 'TR_1',
            timestampMs: ts,
            framesDecoded: frames,
            packetsLost: lost,
            packetsReceived: rx,
            shouldPlay: play,
            paused: paused,
            checkFreeze: camera);

    test('loss over the window and a freeze', () {
      final w = LiveVideoStatsWindow();
      expect(w.sample([p(0, frames: 10, rx: 100)]).lossPct, isNull);
      final s = w.sample([p(2000, frames: 70, lost: 10, rx: 190)], rating: LiveLinkRating.good);
      expect(s.lossPct, closeTo(10, 0.01));
      expect(s.frozenTracks, 0);
      final f = w.sample([p(4000, frames: 70, lost: 10, rx: 200)]);
      expect(f.frozenTracks, 1);
    });

    test('unchanged counters (no SDK refresh) are skipped, not read as a freeze', () {
      final w = LiveVideoStatsWindow()..sample([p(0, frames: 10, rx: 100)]);
      expect(w.sample([p(0, frames: 10, rx: 100)]).frozenTracks, 0);
    });

    test('a screen share or a hidden / settling video never counts as frozen', () {
      final w = LiveVideoStatsWindow()..sample([p(0, frames: 10, camera: false)]);
      expect(w.sample([p(2000, frames: 10, camera: false)]).frozenTracks, 0);
      final h = LiveVideoStatsWindow()..sample([p(0, frames: 10, play: false)]);
      expect(h.sample([p(2000, frames: 10, play: false)]).frozenTracks, 0);
    });

    test('paused by the server counts only while it should play', () {
      final w = LiveVideoStatsWindow();
      expect(w.sample([p(0, paused: true)]).pausedTracks, 1);
      expect(w.sample([p(2000, paused: true, play: false)]).pausedTracks, 0);
    });
  });
}
