// Fingerprint / Face ID sign-in (D-081), the pure parts of lib/features/auth/biometric.dart:
// - the signed message matches the server's lines (back/services/biometric_service.message);
// - Ed25519 from a stored seed reproduces RFC 8032 test vector 1 (the server verifies with `cryptography`);
// - which kind / label / icon the phone gets, which server codes make the app forget its key;
// - when the quick sign-in shows, when the prompt opens by itself, when the offer is made;
// - the stored record round-trips and rejects anything damaged; the secrets never reach the debug log.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/biometric.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

String _hexToB64url(String hex) {
  final bytes = <int>[for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  return base64Url.encode(bytes).replaceAll('=', '');
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('the signed message', () {
    test('four lines: prefix, credential, challenge, device id (trimmed)', () {
      expect(biometricMessage('cid-1', 'ch-2', ' dev-3 '), 'nextbrain/biometric-login/v1\ncid-1\nch-2\ndev-3');
    });

    test('RFC 8032 vector 1: the public key and the signature from the stored seed', () async {
      final seed = _hexToB64url('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60');
      expect(await biometricPublicKey(seed),
          _hexToB64url('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'));
      expect(
          await signBiometricMessage(seed, ''),
          _hexToB64url('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf'
              '5f0595bbe24655141438e7a100b'));
    });

    test('a new key: 32-byte seed and public key, unpadded base64url, the public key derives from the seed', () async {
      final (seed, pub) = await newBiometricKey();
      expect(seed.contains('='), isFalse);
      expect(base64Url.decode('$seed='), hasLength(32));
      expect(base64Url.decode('$pub='), hasLength(32));
      expect(await biometricPublicKey(seed), pub);
      final (other, _) = await newBiometricKey();
      expect(other, isNot(seed));
    });
  });

  group('kind, label, icon', () {
    test('iOS: Face ID, Touch ID; Android: a strong class is a fingerprint', () {
      expect(biometricKindOf([BiometricType.face], ios: true), BiometricKind.face);
      expect(biometricKindOf([BiometricType.fingerprint], ios: true), BiometricKind.touchId);
      expect(biometricKindOf([BiometricType.strong, BiometricType.weak], ios: false), BiometricKind.fingerprint);
      expect(biometricKindOf([BiometricType.fingerprint], ios: false), BiometricKind.fingerprint);
      expect(biometricKindOf([BiometricType.face], ios: false), BiometricKind.face);
      expect(biometricKindOf([BiometricType.weak], ios: false), BiometricKind.generic);
    });

    test('labels in both languages differ per kind; the face gets its own icon', () {
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        final labels = {for (final k in BiometricKind.values) biometricActionLabel(k)};
        expect(labels, hasLength(4), reason: lang);
        for (final k in BiometricKind.values) {
          expect(biometricSettingLabel(k).startsWith('bio_'), isFalse, reason: '$lang $k has a translation');
          expect(biometricOfferTitle(k).startsWith('bio_'), isFalse, reason: '$lang $k has a translation');
        }
      }
      expect(biometricIcon(BiometricKind.face), isNot(biometricIcon(BiometricKind.fingerprint)));
      expect(biometricIcon(BiometricKind.touchId), Icons.fingerprint_rounded);
    });
  });

  group('decisions', () {
    test('codes that kill the key', () {
      for (final c in ['biometric_invalid', 'biometric_revoked', 'biometric_expired', 'biometric_device_blocked']) {
        expect(biometricCodeForgetsKey(c), isTrue, reason: c);
      }
      for (final c in ['biometric_challenge_invalid', 'too_many_attempts', 'ACCOUNT_DEACTIVATED', null]) {
        expect(biometricCodeForgetsKey(c), isFalse, reason: '$c');
      }
    });

    test('the quick sign-in needs support, the feature and a stored key', () {
      expect(showBiometricButton(supported: true, featureOn: true, hasRecord: true), isTrue);
      expect(showBiometricButton(supported: false, featureOn: true, hasRecord: true), isFalse, reason: 'web / old phone');
      expect(showBiometricButton(supported: true, featureOn: false, hasRecord: true), isFalse, reason: 'kill switch');
      expect(showBiometricButton(supported: true, featureOn: true, hasRecord: false), isFalse);
    });

    test('the prompt opens by itself once, never after a sign-out', () {
      expect(shouldAutoPromptBiometric(visible: true, alreadyPrompted: false, suppressed: false), isTrue);
      expect(shouldAutoPromptBiometric(visible: true, alreadyPrompted: true, suppressed: false), isFalse);
      expect(shouldAutoPromptBiometric(visible: true, alreadyPrompted: false, suppressed: true), isFalse);
      expect(shouldAutoPromptBiometric(visible: false, alreadyPrompted: false, suppressed: false), isFalse);
    });

    test('the offer: once per account, with a fresh enrol token, not for the account that holds the key', () {
      bool offer({bool supported = true, bool on = true, bool token = true, int user = 7, int? enrolled, bool declined = false}) =>
          shouldOfferBiometric(
              supported: supported, featureOn: on, hasEnrollToken: token, userId: user, enrolledUserId: enrolled, declined: declined);
      expect(offer(), isTrue);
      expect(offer(enrolled: 3), isTrue, reason: 'another account holds the key: this one may take it over');
      expect(offer(enrolled: 7), isFalse);
      expect(offer(declined: true), isFalse);
      expect(offer(token: false), isFalse);
      expect(offer(supported: false), isFalse);
      expect(offer(on: false), isFalse);
      expect(offer(user: 0), isFalse, reason: 'the id-0 placeholder of a login in flight');
    });

    test('the enrol token is used for 9 of its 10 minutes', () {
      final t0 = DateTime(2026, 10, 29, 12);
      expect(enrollTokenFresh(t0, t0.add(const Duration(minutes: 8, seconds: 59))), isTrue);
      expect(enrollTokenFresh(t0, t0.add(const Duration(minutes: 9))), isFalse);
      expect(enrollTokenFresh(null, t0), isFalse);
    });
  });

  group('the stored record', () {
    const rec = BiometricRecord(
      credentialId: 'c-1',
      seed: 'c2VlZA',
      userId: 42,
      name: 'Ahmed Hamdy Madkour',
      identifier: '@ahmed',
      imageUrl: 'https://x/y.png',
    );

    test('round-trips through JSON', () {
      final back = BiometricRecord.fromJson(jsonDecode(jsonEncode(rec.toJson())))!;
      expect([back.credentialId, back.seed, back.userId, back.name, back.identifier, back.imageUrl],
          ['c-1', 'c2VlZA', 42, 'Ahmed Hamdy Madkour', '@ahmed', 'https://x/y.png']);
    });

    test('anything damaged is no record', () {
      expect(BiometricRecord.fromJson(null), isNull);
      expect(BiometricRecord.fromJson('x'), isNull);
      expect(BiometricRecord.fromJson({'credential_id': '', 'seed': 's', 'user_id': 1}), isNull);
      expect(BiometricRecord.fromJson({'credential_id': 'c', 'seed': 's', 'user_id': '1'}), isNull);
      expect(BiometricRecord.fromJson({'credential_id': 'c', 'user_id': 1}), isNull);
    });

    test('first name and initials (Latin and Arabic)', () {
      expect(rec.firstName, 'Ahmed');
      expect(rec.initials, 'AM');
      const ar = BiometricRecord(credentialId: 'c', seed: 's', userId: 1, name: 'أحمد حمدي');
      expect(ar.firstName, 'أحمد');
      expect(ar.initials, 'أح');
      const empty = BiometricRecord(credentialId: 'c', seed: 's', userId: 1, name: '  ');
      expect(empty.initials, '?');
      expect(empty.firstName, '');
    });

    test('withProfile keeps the key and refreshes name / photo', () {
      final next = rec.withProfile(name: 'Ahmed M.', imageUrl: 'https://x/z.png');
      expect([next.credentialId, next.seed, next.userId, next.name, next.imageUrl],
          ['c-1', 'c2VlZA', 42, 'Ahmed M.', 'https://x/z.png']);
      expect(rec.withProfile(name: ' ').name, rec.name);
    });
  });

  group('the service state', () {
    final bio = BiometricAuth.instance;
    tearDown(bio.debugReset);

    test('a login answer keeps its enrol token; a sign-out drops it and stops the auto prompt', () {
      bio.debugReset();
      expect(bio.enrollToken, isNull);
      bio.noteLoginAnswer({'access_token': 'a', 'biometric_enroll_token': 'tok'});
      expect(bio.enrollToken, 'tok');
      bio.noteLoginAnswer({'access_token': 'b'});
      expect(bio.enrollToken, 'tok', reason: 'an answer without one (a fingerprint sign-in) keeps the last');
      bio.suppressAutoPrompt();
      expect(bio.enrollToken, isNull);
    });

    test('takeAutoPrompt: true once while the panel shows', () {
      const rec = BiometricRecord(credentialId: 'c', seed: 's', userId: 1, name: 'A');
      bio.debugSet(supported: true, record: rec, autoPrompt: true);
      expect(bio.available, isTrue);
      expect(bio.takeAutoPrompt(), isTrue);
      expect(bio.takeAutoPrompt(), isFalse);
      bio.debugSet(supported: true, record: rec, autoPrompt: true);
      bio.suppressAutoPrompt();
      expect(bio.takeAutoPrompt(), isFalse);
      AppConfig.disableList = [kBiometricFeatureKey];
      bio.debugSet(supported: true, record: rec, autoPrompt: true);
      expect(bio.available, isFalse, reason: 'the kill switch hides it');
      expect(bio.takeAutoPrompt(), isFalse);
    });
  });

  test('the enrol proof, the challenge, its signature and the seed never reach the debug log', () {
    final out = redactForLog({
      'credential_id': 'c-1',
      'challenge': 'raw-challenge',
      'signature': 'sig',
      'biometric_enroll_token': 'tok',
      'enroll_token': 'tok2',
      'seed': 'secret-seed',
      'public_key': 'pub',
    }) as Map;
    for (final k in ['challenge', 'signature', 'biometric_enroll_token', 'enroll_token', 'seed']) {
      expect(out[k], '***', reason: k);
    }
    expect(out['public_key'], 'pub', reason: 'a public key is not a secret');
  });
}
