// lib/features/certificates/issue/cert_verify_logic.dart
//
// Pure part of public certificate verification (D-420, unit-tested in test/org/cert_verify_test.dart): what a typed or
// scanned value means. A QR code is untrusted input, so a URL counts as ours only when it is https on our own host and
// its path is exactly `/verify/<token>` (or `/app/verify/<token>`). Nothing here, or anywhere after it, opens a scanned
// URL: the token is taken out of it and sent to our own API.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

const String kCertLookupBase = '/api/v1/public/certificates/lookup';
const Set<String> kCertVerifyHosts = {'alfheemacademy.com', 'www.alfheemacademy.com'};
const String kCertVerifyFeature = 'certificates.verify';

/// The camera path exists on phones only: on the web and on a desktop the page offers typing alone.
bool get certScanAvailable =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

enum CertCodeKind {
  /// The unguessable token of our verification link.
  token,

  /// A certificate number in one of the two printed formats.
  number,

  /// A link somewhere else: never opened, never sent anywhere.
  foreign,

  /// Text that is neither of the above.
  malformed,
}

class CertCode {
  const CertCode(this.kind, [this.value = '']);

  final CertCodeKind kind;

  /// The token, the normalised number, or the host of a foreign link ('' when it has none).
  final String value;
}

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');
final _token = RegExp(r'^[A-Za-z0-9_-]{16,64}$');
final _nb = RegExp(r'^NB-\d{4}-[A-HJ-NP-Z2-9]{6,10}$');
final _ef = RegExp(r'^EF-\d{4,10}-\d{3,10}-\d{5,10}$');
final _whitespace = RegExp(r'\s');

bool _isDash(int c) => c == 0x5F || (c >= 0x2010 && c <= 0x2015) || c == 0x2212 || c == 0x0640;

bool _isFormatMark(int c) =>
    c == 0x200E || c == 0x200F || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069);

/// A number as a person types it, the way the server reads it (`normalize_serial`): Arabic digits, other dashes,
/// spaces, direction marks and lower case are forgiven.
String normalizeCertNumber(String raw) {
  final out = StringBuffer();
  for (final c in raw.runes) {
    if (_isFormatMark(c) || _whitespace.hasMatch(String.fromCharCode(c))) continue;
    if (c >= 0x0660 && c <= 0x0669) {
      out.writeCharCode(0x30 + c - 0x0660);
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      out.writeCharCode(0x30 + c - 0x06F0);
    } else if (_isDash(c)) {
      out.write('-');
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString().toUpperCase();
}

CertCode _fromUri(Uri? uri) {
  if (uri == null) return const CertCode(CertCodeKind.foreign);
  final host = uri.host.toLowerCase();
  final ours = uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      kCertVerifyHosts.contains(host);
  if (!ours) return CertCode(CertCodeKind.foreign, host);
  final seg = uri.pathSegments;
  final token = switch (seg) {
    ['verify', final t] => t,
    ['app', 'verify', final t] => t,
    _ => null,
  };
  if (token == null || !_token.hasMatch(token)) return CertCode(CertCodeKind.foreign, host);
  return CertCode(CertCodeKind.token, token);
}

/// What a typed or scanned value is. Only [CertCodeKind.token] and [CertCodeKind.number] ever reach the server.
CertCode parseCertCode(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty || s.length > 600) return const CertCode(CertCodeKind.malformed);
  final lower = s.toLowerCase();
  if (kCertVerifyHosts.any((h) => lower.startsWith('$h/'))) return _fromUri(Uri.tryParse('https://$s'));
  if (_scheme.hasMatch(s) && !_nb.hasMatch(s)) return _fromUri(Uri.tryParse(s));
  final number = normalizeCertNumber(s);
  if (_nb.hasMatch(number) || _ef.hasMatch(number)) return CertCode(CertCodeKind.number, number);
  return const CertCode(CertCodeKind.malformed);
}

/// `/verify` (no token): the page where a number is typed or a QR code scanned.
bool isCertVerifyHomeRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return false;
  final uri = Uri.tryParse(routeName);
  if (uri == null) return false;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return seg.length == 1 && seg[0] == 'verify';
}
