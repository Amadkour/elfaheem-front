/// TLS pinning for the API host by PUBLIC KEY (SPKI SHA-256), D-946.
///
/// Why public keys: the old pin was the SHA-256 of the whole leaf certificate, which changes at every renewal (new
/// serial, new dates), so each certbot run cut every installed app off. A key outlives its certificates: the server
/// renews with `certbot renew --reuse-key` (same key pair, new certificate), and the pin below keeps matching.
///
/// What dart:io gives the check: with `SecurityContext(withTrustedRoots: false)` no chain is ever trusted, so the
/// `badCertificateCallback` decides every connection, and it is handed ONLY THE LEAF certificate — never the
/// intermediates the server sent. Read from the Dart SDK source (2026-11): BoringSSL platforms (Android, Windows,
/// Linux) call it from `SSLCertContext::CertificateCallback` with `X509_STORE_CTX_get0_cert` (the leaf being
/// verified); iOS / macOS call it from `secure_socket_patch.dart` after `SecTrust` failed, with `leaf_cert =
/// chain[0]` (`security_context_macos.cc`). Checked on this machine too: one call, subject `CN=nextbrain.site`.
/// So "pin an intermediate" cannot mean "look for its hash in the chain"; it means: verify the leaf's signature
/// with that intermediate's public key, which this file carries.
///
/// A leaf is accepted when ANY of these holds (checked in this order):
///   1. its SPKI SHA-256 is in [CertPin.leafSpkiSha256] — the server's own key (primary). No date or host check:
///      only the holder of the private key can finish the handshake, and the renewal keeps that key;
///   2. its DER SHA-256 is in [CertPin.legacyLeafCertSha256] — the certificate pinned before D-946 (transition);
///   3. backup, for a renewal that had to change the key: the leaf is for the host asked for (subjectAltName),
///      inside its validity dates, the host is the API host, and its signature verifies with one of the Let's
///      Encrypt intermediates in [CertPin.backupIssuers] (each one checked against the ISRG roots in
///      test/auth/cert_pin_test.dart). That is as narrow as pinning those intermediates: only Let's Encrypt can
///      sign with them, and only for someone who controls the domain.
/// Nothing else is accepted: there is no fall back to the system's trusted roots, so a CA the device trusts (a
/// proxy, a user-installed CA) still cannot read the traffic.
///
/// The blocking "update the app" prompt ([CertPin.updateRequired]) is raised only by a refused leaf that looks like
/// OUR real key rotation onto a Let's Encrypt intermediate this build does not carry: in date, for the API host,
/// not signed by any bundled key, not self-signed, issuer exactly `C=US, O=Let's Encrypt` with a CN in Let's
/// Encrypt's naming (E5, R12, YE1, …) that is NOT one of the bundled intermediates (a bundled name whose key does
/// not verify the signature is a forgery), and a lifetime of at most 200 days. Anything else — a self-signed
/// certificate with our host and "Let's Encrypt" written in it, a home-made CA called YE1, an expired leaf — is
/// refused quietly, so a network in the middle cannot push the app into the update dialog with a few strings.
///
/// When Let's Encrypt starts a new generation of intermediates (Gen Y expires 2028-09-02, the 2024 set
/// 2027-03-12), add them here; the primary key pin does not depend on the issuer at all.
library;

import 'dart:convert';
import 'dart:io' show HandshakeException, TlsException, X509Certificate;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart' as pc;

/// The server code an [ApiException] carries when the API host's certificate is not one this build knows.
const String kPinUpdateCode = 'APP_UPDATE_REQUIRED';

/// One Let's Encrypt intermediate the backup rule trusts: its name, its expiry (documentation), the SHA-256 of its
/// SubjectPublicKeyInfo (base64, the HPKP / `openssl … | base64` form) and the SubjectPublicKeyInfo itself (base64
/// DER), which is what verifies the leaf's signature.
class LetsEncryptIssuer {
  const LetsEncryptIssuer(this.name, this.expires, this.spkiSha256, this.spki);

  final String name;
  final String expires;
  final String spkiSha256;
  final String spki;
}

/// How [CertPin.evaluate] judged a leaf.
enum PinVerdict {
  /// The server's own key (primary pin).
  pinnedKey,

  /// The certificate pinned before D-946.
  legacyCert,

  /// A valid certificate for the API host, signed by a pinned Let's Encrypt intermediate (backup).
  letsEncryptIssued,

  /// Refused, but it looks like our server's real certificate (for the API host, from Let's Encrypt): the server
  /// moved to a key this build does not know, so the app needs an update.
  rejectedUnknownServerKey,

  /// Refused: anything else (a proxy, a captive portal, another host).
  rejectedForeign;

  bool get accepted => this == pinnedKey || this == legacyCert || this == letsEncryptIssued;
}

class CertPin {
  CertPin._();

  // ALFAHEEM (sync/identity.env, A-002): the pin sets come from CERT_PIN_SPKI_SHA256 / CERT_PIN_LEGACY_SHA256.
  // Both are empty until the alfheemacademy.com certificate exists, so only the Let's Encrypt backup rule
  // accepts the API host. TODO(owner): add the server key's SPKI SHA-256 to identity.env and re-run apply.
  /// SPKI SHA-256 (base64) of the server's public key; read it on the server with
  ///   openssl x509 -in /etc/letsencrypt/live/nextbrain.site/cert.pem -pubkey -noout \
  ///     | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
  /// Hex of the same: e6c23fb6870c8479ea4cf0d78618f89df59abcdf9caf1b98bc35f5de4a0ba833 (EC P-256 key of the
  /// certificate valid 2026-09-24 .. 2026-12-23). The code compares the base64 form.
  static const leafSpkiSha256 = <String>{
    'H/Cbms/WWS6LMgVcAQMAwcETwnleV0UNtcT3znv8V8o=',
  };

  /// SHA-256 (hex) of the whole leaf certificate DER, the pin before D-946. Kept during the transition; drop it once
  /// that certificate has expired (2026-12-23).
  static const legacyLeafCertSha256 = <String>{};

  /// SPKI SHA-256 (base64) of the roots the backup intermediates chain to — not used at run time (dart:io never shows
  /// the chain), the test checks every backup intermediate's signature against these keys.
  static const rootSpkiSha256 = <String, String>{
    'ISRG Root X1': 'C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=',
    'ISRG Root X2': 'diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=',
    'Root YE': 'sCkq5UWXjg+7mKu9lMhhYF5bGLsy7VI/UNW3tccdR7w=',
    'Root YR': 'fk6IOKit1ild5647BH06ujSIq5XbCgqlbYl6ANhhi88=',
  };

  /// The Let's Encrypt intermediates of the backup rule (Gen Y under Root YE / Root YR, the 2024 set under ISRG Root
  /// X2 / X1). Source: github.com/letsencrypt/website static/certs, each verified with openssl against the ISRG roots
  /// of the OS bundle; YE1 is byte-identical to the one nextbrain.site serves.
  static const backupIssuers = <LetsEncryptIssuer>[
  LetsEncryptIssuer('YE1', '2028-09-02', 'brzvtCELCIZUo4sD/qPX0ccRtPsd3DY6RfmxpOU9oB4=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEB2VQdf5oppWtoX0rq8pUnIzzGWjiVy8/zZwHNrMpZvFg8oVPQnKfswEkIub0sBhiY0hpJZA/X3T0fBqcgyDiIwhH6527f7/mUhDyyxBm2jOhHHA2ze6fcbXiJtgL3/q8'),
  LetsEncryptIssuer('YE2', '2028-09-02', 's/tdAOmUzd8syaTuqfgGvFcn6DzA5Cmb+Vby1ST+U3Y=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEcZq0M5HWxBC9zKl7d3SULbWHOO2sZHQ0x7neUz6jNs+bkg+XJpNFqx5Vl755b6gS6ogd+JJbsSG5jMgIqt/2A+nvNP71dufSvF0CHYxV5aGDmtJiFO9X+x0NPT72A5cP'),
  LetsEncryptIssuer('YE3', '2028-09-02', 'ppiiCCS+BOR6GjPE+kiHMb6SAR8jox6QDiyibJwqz84=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEux2grwzPWN2mD1voh+rlEytihVGMdL8nucStSjU1mVIJaIltm7nas7wkGmq5iUzbo4lfma1qzqaMfjeJE7IgnnOsn8O1RphKywuWUqtl+HdryXNYPFSFN32+wrsyf2wz'),
  LetsEncryptIssuer('YR1', '2028-09-02', 'LoMHBotttiDko50Gi13uXW71eIy7LAttI+rYT8wXF4w=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoVi8X2xCYgMXvJxNPKp/oF13UMgmPABB07VCLNDtoXmt9luEZNJSBV10VyT1Pz6LD8Zq1d2gc43WNl1AdRrj4sEnazbOiz0nPpmGBp2hui49oZtDIY6wdKeZAi5BbNU20CH6RSBBMLSQ9cXrH8dxdv4PAJ45ssGML68USE3BsjC2a6cAN9L5CgXVIQi5tfNiTPoFZZ3S0OlXqLmmtdV95udWAb5b6e/F49DiCsH0Y00Ag72BVIb1hzynmKe+X0mERBTtsb3BwmpV9ipeBjMLoR/D9cHxHQCWoi5lTmXwY015J5rGelz1nZjJuxc2kioaX29XJBnhMkP531rSdG5uMwIDAQAB'),
  LetsEncryptIssuer('YR2', '2028-09-02', 'nWN7PSep5XDQdge5zK24CnCRXHr3KvzhKEGxsdqCX9E=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2dC8cAaaaofOJbqjHq1f3ni/310O5i0EL9S56VimW8rxqcesIegH57JQJxensE5HBwPoEjqAb5tw35tOgLhohfikbreHwHKMKpwEEAlvfPkDz/3jr/8LoOyMpODZDsX9iOoNn+eU+pyaDkyxXLpHkavNCRkBGGp/nTxa/ThlIECtoRioDZFvO6WqabDgLlCXK6GIUbeblIrOKmmYq3orHrt9oMwyTQQIirbL3eh1+L9uW6ZETXEvwfxrXPZFW1KQ/tjyz8XXot04pueZOLXwBF8A9qsoj08a0zaupTfgDK+YNnNXTapDk8I8Xlei+ZaT9axomLy50Wj5TqsmUT1vuQIDAQAB'),
  LetsEncryptIssuer('YR3', '2028-09-02', 'UaqofZhLVZrGnpKfiIoCLYMuCJ/026CkErUQG8pLx5k=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyUtPkMn62ZvFNJ17oCSoPt562h6MSjfTTrBrx0/TbXHYE4Vro+oIswzKp/VUIpcjyfqiiu644ATP1yt6IMetRD24EGPC4lTZ+J7JkdVBVHWpW/3C/5mLV6N5bt6qKe5OjpfqTi875QSDYZfjKu5fVcVAjO9e1KWLpjSsRjUYwCxoOR9egvd1EJVvCoEaVufH2OQXt3C6r9uG2ykRYrG+0vxzwPeu6VuqwDvwxRSm4t+TXxyhBtIyBqsbbG2Gyvv9KntteO6faFDv0jXLmk/aaCxVipnGPdFEdIVysvqokeir+/3uYAivwRpIy1zNQH19QkQ8DoiDz7CvkSTiI9NIpQIDAQAB'),
  LetsEncryptIssuer('E5', '2027-03-12', 'NYbU7PBwV4y9J67c4guWTki8FJ+uudrXL0a4V4aRcrg=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEDQs6imthjrbv3F9Y58ZCRVSrY/ZmYUgKLll1tIECN1C3PxZ53JjsoSiXciAcLM/VfFIgTlR4W4QUa8CQroXswFFBPFqHfwZN1P5g0fpsLeF9lRCIoghUD5kaTObqCqzY'),
  LetsEncryptIssuer('E6', '2027-03-12', '0Bbh/jEZSKymTy3kTOhsmlHKBB32EDu1KojrP3YfV9c=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE2fGeRof4IXFgqCbro/q56toduRKn1CbZURSxYXx1lr8iCzkf1b7RCkaqLTxKCYQuvkCVVekZQDdmde0yTncESfhwe8MY5873cRD+rHTYANTtbRxzFjMQnDqy6mxi9L24'),
  LetsEncryptIssuer('E7', '2027-03-12', 'y7xVm0TVJNahMr2sZydE2jQH8SquXV9yLF9seROHHHU=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEQegEkwhYf743MAzAoEHq/lbahJM+yQDbq2cSz/lPUwnoqC+rKeWfFUb0W2JOD9SDQZm3n0ByRRwsXEoypsLbxgVqZf/a2vB1tEA7FGiVtqjianHidGVRU94W1B4nwTP9'),
  LetsEncryptIssuer('E8', '2027-03-12', 'iFvwVyJSxnQdyaUvUERIf+8qk7gRze3612JMwoO3zdU=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE0WXyXtxLtAwCnNKy+u7pbKs6rjih9NQ5MjPFQtTMMww0xyEgkHBc6GIvHHGzQtd5vkYNwdtHoROgx9+BJmM71I0d9j2CMzL29Cvn9ZY6tBNnGHtrPo1I2ere7a5tPodM'),
  LetsEncryptIssuer('E9', '2027-03-12', '8UQKm3bh5B5TpMtGEym/Yze0GXJr5RPkLhnxxpHF1LI=',
      'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEoFzcRZ87rOYCqVhJXQwVOiICfOmmjVlIl9tcaOmuMGTJ0VtgF6RyCuUkSa3nvztHg/WCts+2B3ehQGV+gzNYeKGmNdaSiO+Vx4yZRiq9VtBzf2kIPdGJiMMKvtam4ipz'),
  LetsEncryptIssuer('R10', '2027-03-12', 'K7rZOrXHknnsEhUH8nLL4MZkejquUuIvOIr6tCa0rbo=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz1fl5sRUEu20R/7JJ1h2RlAojB0+iN8FndW1GCm93bVav/r2zqO+rwAhS2JaWjwBL8VYA/aJ/44RQ+vBteAUB5aPbx/X57qBOQl1ZbfCrxhbNyYo56P0ByttGv+rWLyVrkD/6ctXxLVbf3gNGGG8F+dUxrtJkc1uGNGAhe6mZTa8dOq8UEzq/CHzOBaTlLqw02s4Bs0WEnrKUnXIrXaywpxdmEVcb2F7xi3uPBNShgHZV+Y4HN+NtR+SkZrnShzMRahyVfCw5qMH7P2nG2aeP0iLcYRxWMk6+u9e8ltEKzx054+yR8EHas2atw2W9xKBJlFUCuxh9vf14vKKyJUNjQIDAQAB'),
  LetsEncryptIssuer('R11', '2027-03-12', 'bdrBhpj38ffhxpubzkINl0rG+UyossdhcBYj+Zx2fcc=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuoe8XBsAOcvKCs3UZxD5ATylTqVhyybKUvsVAbe5KPUoHu0nsyQYOWcJDAjs4DqwO3cOvfPlOVRBDE6uQdaZdN5R2+97/1i9qLcT9t4x1fJyyXJqC4N0lZxGAGQUmfOx2SLZzaiSqhwmej/+71gFewiVgdtxD4774zEJuwm+UE1fj5F2PVqdnoPy6cRms+EGZkNIGIBloDcYmpuEMpexsr3E+BUAnSeI++JjF5ZsmydnS8TbKF5pwnnwSVzgJFDhxLyhBax7QG0AtMJBP6dYuC/FXJuluwme8f7rsIU5/agK70XEeOtlKsLPXzze41xNG/cLJyuqC0J3U095ah2H2QIDAQAB'),
  LetsEncryptIssuer('R12', '2027-03-12', 'kZwN96eHtZftBWrOZUsd6cA4es80n3NzSk/XtYz2EqQ=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2pgodK2+lP474B7i5Ut1qywSf+2nAzJ+Npfs6DGPpRONC5kuHs0BUT1M5ShuCVUxqqUiXXL0LQfCTUA83wEjuXg39RplMjTmhnGdBO+ECFu9AhqZ66YBAJpzkG2Pogeg0JfT2kVhgTU9FPnEwF9q3AuWGrCf4yrqvSrWmMebcas7dA8827JgvlpLThjp2ypzXIlhZZ7+7Tymy05v5J75AEaz/xlNKmOzjmbGGIVwx1Blbzt05UiDDwhYXS0jnV6j/ujbAKHS9OMZTfLuevYnnuXNnC2i8n+cF63vEzc50bTILEHWhsDp7CH4WRt/uTp8n1wBnWIEwii9Cq08yhDsGwIDAQAB'),
  LetsEncryptIssuer('R13', '2027-03-12', 'AlSQhgtJirc8ahLyekmtX+Iw+v46yPYRLJt9Cq1GlB0=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApWdwjdBWgWQVF2HNuQbUrRmQjCZQN5gWY5JU29nMhAWT7NPsCBugYFFDSH0rx0iWnrQt2p3IJztXoZ+r8NYO1A4wym+bsdHWpJ0yPlhONW9FWGhxF/w+2F2CoC+yUWywGl24Wc41ZciLoa8QN//jnF3CSRc0/4wri43wvHEskwwdBcS6x82qyV580ckB95wD9vwKXfTae+bbdkJw6/RNItoAd2/WyV8X/dp1LqVXDPbqXLbgc6Voz6F04nWCfhCfwfWi6wHpOLEKRMzTwon1STWCCjSzHOmIwkdOgg4KNvBHT4rxKQR12s3hmlz/Xp2YlbqaQ9BKohcFAQQw0zKzjwIDAQAB'),
  LetsEncryptIssuer('R14', '2027-03-12', '8WR6XuPvrFTIkukwWE/keXm3rNHHbBJxvKHFB22GmIg=',
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzWhUbJkv1MTfFF7ihLylp5jaitXVng6yEeruE71/c0TLq/bZ438PLiPNr3I1qp66HaqOANbQ6ETg0SjuBbWng7VLHG4M1vQnx40EyXb4MnqeiwIucbyfErasGfTsS7E0ulC7uJ3G80OeAGQl76Rvq/qOYOR8n9VofZfbSKiQkHjUE4yP18YKub7Ey8L0i7+WibZd7OYLtcGDxZwgr56r5iSYSVFl6c4ihop2I81g2BkBGPYLygDSktVWVz1/cnjHH+u7ubt5hhlw/GwsOaJfIjrFhw3KafQJyvJxanpfCSSTShzR9whLTSKVlH2A1761dHaceWkBRqcV3HkuFIGIlQIDAQAB'),
  ];

  /// The API host ([check] uses it; set by ApiClient from AppConfig.baseUrl).
  static String apiHost = '';

  /// True after the API host showed a certificate that looks like ours but is not pinned: the app must be updated.
  /// Cleared by the next accepted connection.
  static bool updateRequired = false;

  static final Map<String, PinVerdict> _cache = {};

  /// The `HttpClient.badCertificateCallback` of every client that talks to the API host.
  static bool check(X509Certificate cert, String host, int port) => checkDer(cert.der, host);

  /// [check] on a DER leaf (tests pass [now] and empty pin sets to reach the backup rules).
  @visibleForTesting
  static bool checkDer(Uint8List der, String host, {DateTime? now, Set<String>? leafPins, Set<String>? legacyPins}) {
    final verdict = leafPins == null && legacyPins == null
        ? evaluateCached(der, host, now: now)
        : evaluate(der, host, apiHost: apiHost, now: now, leafPins: leafPins, legacyPins: legacyPins);
    if (verdict.accepted) {
      updateRequired = false;
    } else if (verdict == PinVerdict.rejectedUnknownServerKey) {
      updateRequired = true;
    }
    return verdict.accepted;
  }

  /// [evaluate] with a small cache keyed by the certificate's hash (a connection pool re-sees the same leaf).
  static PinVerdict evaluateCached(Uint8List der, String host, {DateTime? now}) {
    final key = '${crypto.sha256.convert(der)}|$host';
    final hit = _cache[key];
    if (hit != null && now == null) return hit;
    final verdict = evaluate(der, host, apiHost: apiHost, now: now);
    if (_cache.length > 16) _cache.clear();
    _cache[key] = verdict;
    return verdict;
  }

  /// [leafPins] / [legacyPins] default to the constants above (a test empties them to reach the backup rule).
  static PinVerdict evaluate(Uint8List der, String host,
      {required String apiHost, DateTime? now, Set<String>? leafPins, Set<String>? legacyPins}) {
    final ParsedCert cert;
    try {
      cert = ParsedCert.parse(der);
    } catch (_) {
      return PinVerdict.rejectedForeign;
    }
    if ((leafPins ?? leafSpkiSha256).contains(base64Encode(crypto.sha256.convert(cert.spki).bytes))) return PinVerdict.pinnedKey;
    if ((legacyPins ?? legacyLeafCertSha256).contains(crypto.sha256.convert(der).toString())) return PinVerdict.legacyCert;

    final h = host.toLowerCase();
    final forUs = h.isNotEmpty && h == apiHost.toLowerCase() && cert.coversHost(h);
    if (!forUs) return PinVerdict.rejectedForeign;
    final t = (now ?? DateTime.now()).toUtc();
    final inDates =
        !t.isBefore(cert.notBefore.subtract(const Duration(minutes: 5))) && !t.isAfter(cert.notAfter);
    if (!inDates) return PinVerdict.rejectedForeign;
    if (backupIssuers.any((i) => verifySignedBy(cert, base64Decode(i.spki)))) return PinVerdict.letsEncryptIssued;
    return looksLikeRotation(cert) ? PinVerdict.rejectedUnknownServerKey : PinVerdict.rejectedForeign;
  }

  /// Let's Encrypt's intermediate names: E5, R10, YE1, YR3, …
  static final _leIntermediateName = RegExp(r'^(E|R|YE|YR)[0-9]{1,2}$');

  /// A leaf already in date, for the API host and signed by none of the bundled keys: does it look like our server
  /// moved to a Let's Encrypt intermediate this build does not know (see the library comment)?
  static bool looksLikeRotation(ParsedCert cert) {
    if (_sameBytes(cert.issuer, cert.subject) || verifySignedBy(cert, cert.spki)) return false; // self-signed
    if (cert.issuerAttr('2.5.4.6') != 'US' || cert.issuerAttr('2.5.4.10') != "Let's Encrypt") return false;
    final cn = cert.issuerAttr('2.5.4.3') ?? '';
    if (!_leIntermediateName.hasMatch(cn)) return false;
    if (backupIssuers.any((i) => i.name == cn)) return false; // a bundled name its own key does not verify: forged
    return cert.notAfter.difference(cert.notBefore) <= const Duration(days: 200);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// True when [error] (a Dio error's inner error) is a TLS handshake refused while [updateRequired] is set.
  static bool isUpdateFailure(Object? error) =>
      updateRequired && (error is HandshakeException || error is TlsException);

  @visibleForTesting
  static void debugReset() {
    updateRequired = false;
    _cache.clear();
  }
}

// ── X.509 reading (the few fields the pin needs) ───────────────────────────────

/// A DER element: [tag], the whole element `bytes[start, end)` and its content `bytes[content, end)`.
class _Der {
  _Der(this.bytes, this.tag, this.start, this.content, this.end);

  final Uint8List bytes;
  final int tag;
  final int start;
  final int content;
  final int end;

  static _Der at(Uint8List b, int pos) {
    final tag = b[pos];
    var i = pos + 1;
    var len = b[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n == 0 || n > 4) throw const FormatException('DER length');
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | b[i++];
      }
    }
    if (i + len > b.length) throw const FormatException('DER overrun');
    return _Der(b, tag, pos, i, i + len);
  }

  Uint8List get whole => Uint8List.sublistView(bytes, start, end);
  Uint8List get value => Uint8List.sublistView(bytes, content, end);

  List<_Der> get children {
    final out = <_Der>[];
    var p = content;
    while (p < end) {
      final c = at(bytes, p);
      out.add(c);
      p = c.end;
    }
    return out;
  }

  /// Dotted form of an OBJECT IDENTIFIER.
  String get oid {
    final v = value;
    final parts = <int>[v[0] ~/ 40, v[0] % 40];
    var acc = 0;
    for (var k = 1; k < v.length; k++) {
      acc = (acc << 7) | (v[k] & 0x7f);
      if (v[k] & 0x80 == 0) {
        parts.add(acc);
        acc = 0;
      }
    }
    return parts.join('.');
  }

  /// The bytes of a BIT STRING (its first content byte, the unused-bit count, is 0 in every certificate).
  Uint8List get bits => Uint8List.sublistView(bytes, content + 1, end);

  BigInt get unsigned {
    var r = BigInt.zero;
    for (final x in value) {
      r = (r << 8) | BigInt.from(x);
    }
    return r;
  }

  DateTime get time {
    final s = ascii.decode(value);
    final full = tag == 0x18 ? s : '${int.parse(s.substring(0, 2)) >= 50 ? '19' : '20'}$s';
    return DateTime.utc(int.parse(full.substring(0, 4)), int.parse(full.substring(4, 6)),
        int.parse(full.substring(6, 8)), int.parse(full.substring(8, 10)), int.parse(full.substring(10, 12)),
        int.parse(full.substring(12, 14)));
  }
}

/// The fields of a certificate the pin reads.
class ParsedCert {
  ParsedCert._(this.tbs, this.sigAlg, this.signature, this.issuer, this.subject, this.notBefore, this.notAfter,
      this.spki, this.dnsNames);

  /// The signed part (`tbsCertificate`, whole DER element).
  final Uint8List tbs;
  final String sigAlg;
  final Uint8List signature;
  final Uint8List issuer;

  /// The subject Name, whole DER element.
  final Uint8List subject;
  final DateTime notBefore;
  final DateTime notAfter;

  /// SubjectPublicKeyInfo, whole DER element (what the SPKI SHA-256 is taken over).
  final Uint8List spki;
  final List<String> dnsNames;

  static ParsedCert parse(Uint8List der) {
    final top = _Der.at(der, 0).children;
    final tbsEl = top[0];
    final f = tbsEl.children;
    var i = f[0].tag == 0xa0 ? 1 : 0; // [0] version
    i++; // serial
    i++; // signature algorithm (repeated outside)
    final issuer = f[i++];
    final validity = f[i++].children;
    final subject = f[i++];
    final spki = f[i++];
    final names = <String>[];
    for (; i < f.length; i++) {
      if (f[i].tag != 0xa3) continue; // [3] extensions
      for (final ext in f[i].children.first.children) {
        final parts = ext.children;
        if (parts.first.oid != '2.5.29.17') continue; // subjectAltName
        final san = _Der.at(parts.last.value, 0);
        for (final g in san.children) {
          if (g.tag == 0x82) names.add(ascii.decode(g.value).toLowerCase()); // dNSName
        }
      }
    }
    return ParsedCert._(tbsEl.whole, top[1].children.first.oid, top[2].bits, issuer.whole, subject.whole,
        validity[0].time, validity[1].time, spki.whole, names);
  }

  /// [host] matches a subjectAltName exactly, or one `*.` wildcard label.
  bool coversHost(String host) => dnsNames.any((n) {
        if (n == host) return true;
        if (!n.startsWith('*.')) return false;
        final suffix = n.substring(1);
        return host.length > suffix.length &&
            host.endsWith(suffix) &&
            !host.substring(0, host.length - suffix.length).contains('.');
      });

  /// The value of the issuer's attribute [oid] (`2.5.4.3` CN, `2.5.4.10` O, `2.5.4.6` C), or null.
  String? issuerAttr(String oid) {
    try {
      for (final rdn in _Der.at(issuer, 0).children) {
        for (final atv in rdn.children) {
          final parts = atv.children;
          if (parts.length == 2 && parts[0].oid == oid) return utf8.decode(parts[1].value, allowMalformed: true);
        }
      }
    } catch (_) {}
    return null;
  }

  bool issuerMentions(String text) {
    final needle = utf8.encode(text);
    outer:
    for (var k = 0; k + needle.length <= issuer.length; k++) {
      for (var j = 0; j < needle.length; j++) {
        if (issuer[k + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }
}

/// True when [cert]'s signature verifies with the public key [issuerSpki] (DER SubjectPublicKeyInfo). ECDSA on
/// P-256 / P-384 and RSA PKCS#1 v1.5, with SHA-256 / 384 / 512 — what Let's Encrypt and the ISRG roots use.
bool verifySignedBy(ParsedCert cert, Uint8List issuerSpki) {
  try {
    final spki = _Der.at(issuerSpki, 0).children;
    final alg = spki[0].children;
    final keyBits = spki[1].bits;
    final digest = switch (cert.sigAlg) {
      '1.2.840.10045.4.3.2' || '1.2.840.113549.1.1.11' => 'SHA-256',
      '1.2.840.10045.4.3.3' || '1.2.840.113549.1.1.12' => 'SHA-384',
      '1.2.840.10045.4.3.4' || '1.2.840.113549.1.1.13' => 'SHA-512',
      _ => null,
    };
    if (digest == null) return false;
    final ecdsaSig = cert.sigAlg.startsWith('1.2.840.10045.4.3.');
    final keyOid = alg[0].oid;

    if (keyOid == '1.2.840.10045.2.1' && ecdsaSig) {
      final curve = switch (alg[1].oid) {
        '1.2.840.10045.3.1.7' => pc.ECCurve_secp256r1(),
        '1.3.132.0.34' => pc.ECCurve_secp384r1(),
        _ => null,
      };
      if (curve == null) return false;
      final q = curve.curve.decodePoint(keyBits);
      final rs = _Der.at(cert.signature, 0).children;
      final signer = pc.ECDSASigner(pc.Digest(digest))
        ..init(false, pc.PublicKeyParameter<pc.ECPublicKey>(pc.ECPublicKey(q, curve)));
      return signer.verifySignature(cert.tbs, pc.ECSignature(rs[0].unsigned, rs[1].unsigned));
    }
    if (keyOid == '1.2.840.113549.1.1.1' && !ecdsaSig) {
      final ne = _Der.at(keyBits, 0).children;
      final prefix = switch (digest) {
        'SHA-256' => '0609608648016503040201',
        'SHA-384' => '0609608648016503040202',
        _ => '0609608648016503040203',
      };
      final signer = pc.RSASigner(pc.Digest(digest), prefix)
        ..init(false, pc.PublicKeyParameter<pc.RSAPublicKey>(pc.RSAPublicKey(ne[0].unsigned, ne[1].unsigned)));
      return signer.verifySignature(cert.tbs, pc.RSASignature(cert.signature));
    }
    return false;
  } catch (_) {
    return false;
  }
}
