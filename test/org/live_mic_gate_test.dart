// LiveMicGate (android_share.dart): the Android share's mic gate over a fake mic and a fake native
// soft mute — the order of the real mute and the native clear (L1 / L2), the native clear on every
// reset (H1), device audio only when the mic may be published (M2) and "muted by the call" owned
// by the gate (M3).
import 'package:flutter_education_app/features/live/room/widgets/android_share.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMic implements LiveMic {
  _FakeMic(this.log, {this.enabled = true, this.allowed = true});

  final List<String> log;

  @override
  bool enabled;

  @override
  bool allowed;

  /// The next [failures] calls to setEnabled throw.
  int failures = 0;

  @override
  Future<void> setEnabled(bool on) async {
    if (failures > 0) {
      failures--;
      log.add('mic $on failed');
      throw Exception('publish failed');
    }
    enabled = on;
    log.add('mic $on');
  }
}

void main() {
  late List<String> log;
  late LiveMicGate gate;

  setUp(() {
    log = [];
    gate = LiveMicGate.withNative((muted) async => log.add('native $muted'));
  });

  group('device audio available', () {
    test('needs API 29, the mic and the share audio', () {
      expect(shareDeviceAudioAvailable(apiLevel: 29, micAllowed: true, shareAudioAllowed: true), isTrue);
      expect(shareDeviceAudioAvailable(apiLevel: 34, micAllowed: true, shareAudioAllowed: true), isTrue);
      expect(shareDeviceAudioAvailable(apiLevel: 28, micAllowed: true, shareAudioAllowed: true), isFalse);
      expect(shareDeviceAudioAvailable(apiLevel: 34, micAllowed: false, shareAudioAllowed: true), isFalse);
      expect(shareDeviceAudioAvailable(apiLevel: 34, micAllowed: true, shareAudioAllowed: false), isFalse);
    });

    test('the scope note exists in both languages', () {
      expect(shareDeviceAudioScopeNote(arabic: false), contains('single app'));
      expect(shareDeviceAudioScopeNote(arabic: true), isNotEmpty);
      expect(shareDeviceAudioScopeNote(arabic: true), isNot(shareDeviceAudioScopeNote(arabic: false)));
    });
  });

  group('begin (M2)', () {
    test('a mic that may not be published: nothing changes, the share goes on without it', () async {
      final mic = _FakeMic(log, enabled: false, allowed: false);
      expect(await gate.begin(mic), isFalse);
      expect(gate.deviceAudioActive, isFalse);
      expect(log, isEmpty);
    });

    test('a muted mic: soft mute first, then the track comes on', () async {
      final mic = _FakeMic(log, enabled: false);
      expect(await gate.begin(mic), isTrue);
      expect(log, ['native true', 'mic true']);
      expect(gate.isOn(mic), isFalse);
    });

    test('the track cannot come on: no device audio, the soft mute cleared', () async {
      final mic = _FakeMic(log, enabled: false)..failures = 1;
      expect(await gate.begin(mic), isFalse);
      expect(gate.deviceAudioActive, isFalse);
      expect(gate.softMuted, isFalse);
      expect(log, ['native true', 'mic true failed', 'native false']);
    });
  });

  group('end (L2)', () {
    test('a soft-muted mic is muted for real BEFORE the soft mute is cleared', () async {
      final mic = _FakeMic(log, enabled: false);
      await gate.begin(mic);
      log.clear();
      await gate.end(mic);
      expect(log, ['mic false', 'native false']);
      expect(gate.isOn(mic), isFalse);
    });

    test('the real mute is retried once', () async {
      final mic = _FakeMic(log, enabled: false);
      await gate.begin(mic);
      log.clear();
      mic.failures = 1;
      await gate.end(mic);
      expect(log, ['mic false failed', 'mic false', 'native false']);
    });

    test('the real mute fails twice: the soft mute stays on, the mic stays silent', () async {
      final mic = _FakeMic(log, enabled: false);
      await gate.begin(mic);
      log.clear();
      mic.failures = 2;
      await gate.end(mic);
      expect(log, ['mic false failed', 'mic false failed']);
      expect(gate.softMuted, isTrue);
      expect(gate.isOn(mic), isFalse);
      // The next tap settles it: muted for real, then cleared.
      await gate.userSet(mic, false);
      expect(log.sublist(2), ['mic false', 'native false']);
      expect(gate.softMuted, isFalse);
    });

    test('an audible mic stays on', () async {
      final mic = _FakeMic(log);
      await gate.begin(mic);
      await gate.end(mic);
      expect(log, isEmpty);
      expect(gate.isOn(mic), isTrue);
    });
  });

  group('release / reset (H1, L1)', () {
    test('release mutes a soft-muted mic before clearing the native flag', () async {
      final mic = _FakeMic(log);
      await gate.begin(mic);
      await gate.userSet(mic, false);
      log.clear();
      await gate.releaseMic(mic);
      expect(log, ['mic false', 'native false']);
      expect(gate.deviceAudioActive, isFalse);
    });

    test('release keeps the native flag when the real mute failed', () async {
      final mic = _FakeMic(log);
      await gate.begin(mic);
      await gate.userSet(mic, false);
      log.clear();
      mic.failures = 2;
      await gate.releaseMic(mic);
      expect(log, ['mic false failed', 'mic false failed']);
    });

    test('release and reset clear the native flag even when the Dart flags are clean', () async {
      await gate.releaseMic(null);
      expect(log, ['native false']);
      log.clear();
      gate.reset();
      await Future<void>.delayed(Duration.zero);
      expect(log, ['native false']);
    });
  });

  group('phone calls (M3)', () {
    test('the call mutes an audible mic and gives it back', () async {
      final mic = _FakeMic(log);
      expect(await gate.callStarted(mic), isTrue);
      expect(gate.mutedByCall, isTrue);
      expect(mic.enabled, isFalse);
      expect(await gate.callEnded(mic), isTrue);
      expect(mic.enabled, isTrue);
      expect(gate.mutedByCall, isFalse);
    });

    test('a muted mic is left alone', () async {
      final mic = _FakeMic(log, enabled: false);
      expect(await gate.callStarted(mic), isFalse);
      expect(await gate.callEnded(mic), isFalse);
      expect(mic.enabled, isFalse);
    });

    test('a tap during the call: the call end does not touch the mic', () async {
      final mic = _FakeMic(log);
      await gate.callStarted(mic);
      await gate.userSet(mic, true); // the person turned it back on
      await gate.userSet(mic, false); // and off again
      expect(await gate.callEnded(mic), isFalse);
      expect(mic.enabled, isFalse);
    });

    test('with device audio the call uses the soft mute', () async {
      final mic = _FakeMic(log);
      await gate.begin(mic);
      log.clear();
      await gate.callStarted(mic);
      expect(log, ['native true']);
      expect(gate.isOn(mic), isFalse);
      await gate.callEnded(mic);
      expect(log, ['native true', 'native false']);
      expect(gate.isOn(mic), isTrue);
    });

    test('a mic taken away during the call is not given back', () async {
      final mic = _FakeMic(log);
      await gate.callStarted(mic);
      mic.allowed = false;
      expect(await gate.callEnded(mic), isFalse);
      expect(mic.enabled, isFalse);
    });

    test('reset forgets the call', () async {
      final mic = _FakeMic(log);
      await gate.callStarted(mic);
      gate.reset();
      expect(gate.mutedByCall, isFalse);
      expect(await gate.callEnded(mic), isFalse);
    });
  });
}
