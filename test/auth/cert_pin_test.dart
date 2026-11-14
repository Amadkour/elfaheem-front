// Certificate pinning by public key (D-946, lib/core/cert_pin.dart).
//
// Fixtures in test/fixtures/tls/ are public certificates:
//   nextbrain_site_leaf.pem, root_ye_by_x2.pem, isrg_root_x2_by_x1.pem — served by nextbrain.site on 2026-11-14
//     (`openssl s_client -connect nextbrain.site:443 -servername nextbrain.site -showcerts`);
//   isrg_root_x1.pem, isrg_root_x2.pem — the self-signed roots of the OS CA bundle;
//   root_ye.pem, root_yr.pem, root_yr_by_x1.pem, le/*.pem — github.com/letsencrypt/website static/certs (gen-y/, 2024/),
//     each verified with `openssl verify` against the two ISRG roots above; le/ye1.pem equals the served YE1.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_education_app/core/cert_pin.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _der(String path) {
  final pem = File('test/fixtures/tls/$path').readAsStringSync();
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64Decode(body);
}

String _spkiPin(Uint8List der) =>
    base64Encode(crypto.sha256.convert(ParsedCert.parse(der).spki).bytes);

void main() {
  final leaf = _der('nextbrain_site_leaf.pem');
  final today = DateTime.utc(2026, 11, 14);

  group('SPKI extraction', () {
    test('the leaf key hash is the primary pin', () {
      expect(_spkiPin(leaf), '5sI/tocMhHnqTPDXhhj4nfWavN+crxuYvDX13koLqDM=');
      expect(CertPin.leafSpkiSha256, contains(_spkiPin(leaf)));
    });

    test('the leaf fields', () {
      final c = ParsedCert.parse(leaf);
      expect(c.dnsNames, ['nextbrain.site', 'www.nextbrain.site']);
      expect(c.notBefore, DateTime.utc(2026, 9, 24, 17, 14, 18));
      expect(c.notAfter, DateTime.utc(2026, 12, 23, 17, 14, 17));
      expect(c.issuerMentions("Let's Encrypt"), isTrue);
      expect(c.coversHost('nextbrain.site'), isTrue);
      expect(c.coversHost('api.nextbrain.site'), isFalse);
    });

    test('the legacy pin is the hash of the whole served leaf', () {
      expect(CertPin.legacyLeafCertSha256, contains(crypto.sha256.convert(leaf).toString()));
    });

    test('root key hashes', () {
      expect(_spkiPin(_der('isrg_root_x1.pem')), CertPin.rootSpkiSha256['ISRG Root X1']);
      expect(_spkiPin(_der('isrg_root_x2.pem')), CertPin.rootSpkiSha256['ISRG Root X2']);
      // the cross-signed copies carry the same keys
      expect(_spkiPin(_der('isrg_root_x2_by_x1.pem')), CertPin.rootSpkiSha256['ISRG Root X2']);
      expect(_spkiPin(_der('root_ye.pem')), CertPin.rootSpkiSha256['Root YE']);
      expect(_spkiPin(_der('root_ye_by_x2.pem')), CertPin.rootSpkiSha256['Root YE']);
      expect(_spkiPin(_der('root_yr.pem')), CertPin.rootSpkiSha256['Root YR']);
    });
  });

  group('backup intermediates', () {
    final roots = {
      for (final f in ['isrg_root_x1.pem', 'isrg_root_x2.pem', 'root_ye.pem', 'root_yr.pem'])
        f: ParsedCert.parse(_der(f)).spki,
    };

    test('every pinned intermediate is a committed Let\'s Encrypt certificate signed by an ISRG root', () {
      final files = Directory('test/fixtures/tls/le').listSync().whereType<File>().toList();
      expect(files.length, CertPin.backupIssuers.length);
      for (final issuer in CertPin.backupIssuers) {
        final der = _der('le/${issuer.name.toLowerCase()}.pem');
        final c = ParsedCert.parse(der);
        expect(base64Encode(c.spki), issuer.spki, reason: issuer.name);
        expect(_spkiPin(der), issuer.spkiSha256, reason: issuer.name);
        expect(roots.values.any((r) => verifySignedBy(c, r)), isTrue, reason: '${issuer.name} chains to a root');
      }
    });

    test('the cross-signs chain the Y roots to the ISRG roots (RSA 4096 and ECDSA P-384)', () {
      expect(verifySignedBy(ParsedCert.parse(_der('root_ye_by_x2.pem')), roots['isrg_root_x2.pem']!), isTrue);
      expect(verifySignedBy(ParsedCert.parse(_der('root_yr_by_x1.pem')), roots['isrg_root_x1.pem']!), isTrue);
      expect(verifySignedBy(ParsedCert.parse(_der('isrg_root_x2_by_x1.pem')), roots['isrg_root_x1.pem']!), isTrue);
      // and not by the wrong key
      expect(verifySignedBy(ParsedCert.parse(_der('root_ye_by_x2.pem')), roots['isrg_root_x1.pem']!), isFalse);
    });
  });

  group('evaluate', () {
    PinVerdict eval(Uint8List der, {String host = 'nextbrain.site', DateTime? now, bool noPins = false}) =>
        CertPin.evaluate(der, host,
            apiHost: 'nextbrain.site',
            now: now ?? today,
            leafPins: noPins ? const {} : null,
            legacyPins: noPins ? const {} : null);

    test('the served leaf matches the primary key pin', () {
      expect(eval(leaf), PinVerdict.pinnedKey);
      expect(eval(leaf).accepted, isTrue);
    });

    test('a renewal with the same key (new certificate, same SPKI) still matches, dates are not checked', () {
      expect(eval(leaf, now: DateTime.utc(2027, 6, 1)), PinVerdict.pinnedKey);
    });

    test('with the server key unknown, the backup rule verifies the YE1 signature', () {
      expect(eval(leaf, noPins: true), PinVerdict.letsEncryptIssued);
    });

    test('the backup rule refuses a broken signature, an expired leaf and another host', () {
      final forged = Uint8List.fromList(leaf);
      forged[forged.length - 10] ^= 0x01; // inside the signature
      expect(eval(forged, noPins: true), PinVerdict.rejectedUnknownServerKey);
      expect(eval(leaf, noPins: true, now: DateTime.utc(2026, 12, 24)), PinVerdict.rejectedUnknownServerKey);
      expect(CertPin.evaluate(leaf, 'evil.example', apiHost: 'evil.example', now: today, leafPins: const {}, legacyPins: const {}),
          PinVerdict.rejectedForeign);
      expect(CertPin.evaluate(leaf, 'www.nextbrain.site', apiHost: 'nextbrain.site', now: today, leafPins: const {}, legacyPins: const {}),
          PinVerdict.rejectedForeign);
    });

    test('a certificate that is not ours is refused as foreign (no update prompt)', () {
      expect(eval(_der('isrg_root_x1.pem')), PinVerdict.rejectedForeign);
      expect(eval(_der('le/ye1.pem')), PinVerdict.rejectedForeign);
      expect(eval(Uint8List.fromList([1, 2, 3])), PinVerdict.rejectedForeign);
    });

    test('the legacy leaf hash alone still accepts the old certificate', () {
      expect(CertPin.evaluate(leaf, 'nextbrain.site', apiHost: 'nextbrain.site', now: today, leafPins: const {}),
          PinVerdict.legacyCert);
    });
  });

  // Opt-in (network): PIN_LIVE=1 flutter test test/auth/cert_pin_test.dart --plain-name live
  group('live', () {
    final live = Platform.environment['PIN_LIVE'] == '1';
    HttpClient pinned() => HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = CertPin.check;

    test('nextbrain.site is accepted through the real dart:io callback', () async {
      CertPin.apiHost = 'nextbrain.site';
      final c = pinned();
      final res = await (await c.getUrl(Uri.parse('https://nextbrain.site/api/'))).close();
      await res.drain<void>();
      c.close();
      expect(res.certificate?.subject, contains('nextbrain.site'));
    }, skip: !live);

    test('another host is refused (no system roots to fall back on)', () async {
      CertPin.apiHost = 'nextbrain.site';
      final c = pinned();
      await expectLater(() async => (await c.getUrl(Uri.parse('https://www.google.com/'))).close(),
          throwsA(isA<HandshakeException>()));
      c.close();
      expect(CertPin.updateRequired, isFalse);
    }, skip: !live);
  });

  group('update flag', () {
    setUp(CertPin.debugReset);
    tearDown(CertPin.debugReset);

    test('a handshake failure is an update failure only after our server showed an unknown key', () {
      expect(CertPin.isUpdateFailure(const HandshakeException('x')), isFalse);
      CertPin.updateRequired = true;
      expect(CertPin.isUpdateFailure(const HandshakeException('x')), isTrue);
      expect(CertPin.isUpdateFailure(const SocketException('x')), isFalse);
    });
  });
}
