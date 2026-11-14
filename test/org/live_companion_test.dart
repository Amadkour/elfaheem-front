import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/features/live/companion/companion_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identities (D-520)', () {
    test('a companion belongs to its person', () {
      expect(isCompanionIdentity('companion:meet_12'), isTrue);
      expect(isCompanionIdentity('student_12'), isFalse);
      expect(companionPrimaryOf('companion:student_3'), 'student_3');
      expect(companionPrimaryOf('guest:abc'), isNull);
      expect(companionIdentityFor('meet_12'), 'companion:meet_12');
    });

    test('the roster has no phones, each phone is found by its person', () {
      final ids = ['meet_1', 'companion:meet_1', 'meet_2'];
      expect(withoutCompanions(ids, (s) => s), ['meet_1', 'meet_2']);
      expect(companionsByPrimary(ids, (s) => s), {'meet_1': 'companion:meet_1'});
    });
  });

  group('wire', () {
    test('a request parses, sources in any shape', () {
      final r = CompanionRequest.fromJson({
        'id': 7,
        'status': 'pending',
        'kind': 'meeting',
        'ref_id': 9,
        'sources': 'camera,speaker',
        'origin_label': 'Chrome on Windows',
        'expires_in': 95,
        'pushed': false,
      });
      expect(r.pending, isTrue);
      expect(r.sources, {CompanionSource.camera, CompanionSource.speaker});
      expect(r.pushed, isFalse);
      expect(r.ref.isMeeting, isTrue);
      expect(CompanionSource.parseAll(['microphone', 'nope']), {CompanionSource.microphone});
    });

    test('the QR link goes through the one link scheme', () {
      const link = AppLink.companion('abcDEF_123-xy');
      expect(link.route, '/s/companion/abcDEF_123-xy');
      expect(AppLink.parse(link.url('https://alfheemacademy.com')), link);
      expect(AppLink.parse('/s/companion/short'), isNull);
    });
  });

  group('handover', () {
    test('the phone taking the mic turns this device off and a dropped phone restores it', () {
      final h = CompanionHandover();
      final a = h.sync(phoneHasMic: true, phoneHasCam: false, phoneSpeaker: false, webMicOn: true, webCamOn: false);
      expect(a.webMic, isFalse);
      expect(h.micHeld, isTrue);
      // The person mutes on the phone: this device's mic stays off.
      expect(h.sync(phoneHasMic: true, phoneHasCam: false, phoneSpeaker: false, webMicOn: false, webCamOn: false).isEmpty, isTrue);
      final back = h.sync(phoneHasMic: false, phoneHasCam: false, phoneSpeaker: false, webMicOn: false, webCamOn: false);
      expect(back.webMic, isTrue);
      expect(h.micHeld, isFalse);
    });

    test('a device that was off stays off when the phone goes', () {
      final h = CompanionHandover();
      final a = h.sync(phoneHasMic: true, phoneHasCam: true, phoneSpeaker: false, webMicOn: false, webCamOn: false);
      expect(a.webMic, isNull);
      expect(a.webCam, isNull);
      final back = h.release();
      expect(back.webMic, isNull);
      expect(back.webCam, isNull);
    });

    test('the camera is handed over and back, the speaker likewise', () {
      final h = CompanionHandover();
      final a = h.sync(phoneHasMic: false, phoneHasCam: true, phoneSpeaker: true, webMicOn: false, webCamOn: true);
      expect(a.webCam, isFalse);
      expect(a.roomAudioMuted, isTrue);
      final back = h.release();
      expect(back.webCam, isTrue);
      expect(back.roomAudioMuted, isFalse);
    });
  });

  test('a split sound path is called out, a whole one is not', () {
    expect(companionSplitsAudio({CompanionSource.microphone}), isTrue);
    expect(companionSplitsAudio({CompanionSource.speaker, CompanionSource.camera}), isTrue);
    expect(companionSplitsAudio({CompanionSource.microphone, CompanionSource.speaker}), isFalse);
    expect(companionSplitsAudio({CompanionSource.camera}), isFalse);
  });
}
