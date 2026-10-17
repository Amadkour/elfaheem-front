/// features/attendance/attendance_crypto.dart
///
/// Mirrors services/attendance_service.py — the strings MUST stay identical.
///   request signature : HMAC-SHA256(student_key, "req|<request_id>|<att_id>|<code>")
///   result  signature : HMAC-SHA256(student_key, "res|<request_id>|<status>|<confirmed_at>")
///
/// Why this makes relaying safe:
///   • the relay never has the student's key, so it cannot forge or alter a request;
///   • the relay never has the key to sign a "result", so it cannot fake an acceptance —
///     the app only shows success after [verifyResult] passes.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String _hmac(String key, String msg) =>
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(msg)).toString();

String signRequest(String studentKey, String requestId, int attId, String code) =>
    _hmac(studentKey, 'req|$requestId|$attId|$code');

String signResult(String studentKey, String requestId, String status, String confirmedAt) =>
    _hmac(studentKey, 'res|$requestId|$status|$confirmedAt');

/// A classmate vouches "student [studentId] was next to me at [ts]" (seconds since epoch, UTC).
/// Signed with the CLASSMATE'S own key; the server checks it, so it cannot be forged.
String signWitness(String witnessKey, int attId, int studentId, int ts) =>
    _hmac(witnessKey, 'wit|$attId|$studentId|$ts');

/// Constant-time comparison.
bool _safeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

bool verifyResult({
  required String studentKey,
  required String requestId,
  required String status,
  required String confirmedAt,
  required String signature,
}) =>
    _safeEquals(signResult(studentKey, requestId, status, confirmedAt), signature);

/// 32 hex chars from a CSPRNG — matches the backend's `^[A-Za-z0-9_-]{8,64}$`.
String newRequestId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
