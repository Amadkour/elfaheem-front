// Debug request/response logs never show credentials (review R3 L2). Requirements:
// - passwords, tokens, the TOTP seed (`secret`, `otpauth_uri`), recovery codes and typed codes are masked, at any
//   depth, in maps and lists, and in a JSON body that arrives as text;
// - server error codes in `code` (mfa_code_invalid, DEVICE_MISMATCH) stay readable for debugging;
// - everything else is left as it is.
import 'dart:convert';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MFA setup answer: the seed and the otpauth URI are masked', () {
    final out = redactForLog({
      'secret': 'JBSWY3DPEHPK3PXP',
      'otpauth_uri': 'otpauth://totp/Alfaheem:a@b.c?secret=JBSWY3DPEHPK3PXP&issuer=Alfaheem',
      'issuer': 'Alfaheem',
      'digits': 6,
    }) as Map;
    expect(out['secret'], '***');
    expect(out['otpauth_uri'], '***');
    expect(out['issuer'], 'Alfaheem');
    expect(out['digits'], 6);
    expect(jsonEncode(out), isNot(contains('JBSWY3DPEHPK3PXP')));
  });

  test('confirm / regenerate answers: every recovery code is masked; tokens too', () {
    final out = redactForLog({
      'access_token': 'a.b.c',
      'refresh_token': 'r',
      'recovery_codes': ['ABCD-EFGH-JKLM-NPQR', 'STUV-WXYZ-2345-6789'],
      'user': {'id': 1, 'name': 'x'},
    });
    final text = jsonEncode(out);
    expect(text, isNot(contains('ABCD-EFGH')));
    expect(text, isNot(contains('a.b.c')));
    expect((out as Map)['user'], {'id': 1, 'name': 'x'});
  });

  test('typed codes in requests are masked: TOTP, recovery code, password', () {
    final verify = redactForLog({'mfa_token': 't', 'code': '123456'}) as Map;
    expect(verify, {'mfa_token': '***', 'code': '***'});
    final disable = redactForLog({'password': 'pw', 'recovery_code': 'ABCD-EFGH-JKLM-NPQR'}) as Map;
    expect(disable, {'password': '***', 'recovery_code': '***'});
    expect(redactForLog({'code': 'ABCD-EFGH-JKLM-NPQR'}), {'code': '***'});
    expect(redactForLog({'code': 123456}), {'code': '***'});
    expect(redactForLog({'Code': '654321'}), {'Code': '***'});
  });

  test('server error codes stay readable', () {
    final err = redactForLog({
      'detail': {'code': 'mfa_code_invalid', 'message': 'رمز التحقق غير صحيح', 'attempts_left': 3}
    });
    expect(err, {
      'detail': {'code': 'mfa_code_invalid', 'message': 'رمز التحقق غير صحيح', 'attempts_left': 3}
    });
    expect(redactForLog({'code': 'DEVICE_MISMATCH'}), {'code': 'DEVICE_MISMATCH'});
    expect(redactForLog({'code': null}), {'code': null});
  });

  test('a JSON body delivered as text is masked as well; other text is untouched', () {
    final out = redactForLog('{"secret":"S3CR3T","recovery_codes":["X"],"ok":true}');
    expect(out, {'secret': '***', 'recovery_codes': '***', 'ok': true});
    expect(redactForLog('plain text'), 'plain text');
    expect(redactForLog('{not json'), '{not json');
    expect(redactForLog(42), 42);
  });

  test('nested lists of maps are walked', () {
    final out = redactForLog([
      {'token': 'x', 'items': [{'password': 'p', 'n': 1}]}
    ]);
    expect(out, [
      {'token': '***', 'items': [{'password': '***', 'n': 1}]}
    ]);
  });

  test('S8: the Google id token, the SSE ticket, a passcode and a PIN are masked', () {
    final out = redactForLog({
      'id_token': 'eyJhbGciOi.google.sig',
      'ticket': 'sse-ticket-123',
      'passcode': '9182',
      'pin': '4321',
      'nested': {'Passcode': '1111', 'PIN': '2222'},
      'name': 'kept',
    }) as Map;
    expect(out['id_token'], '***');
    expect(out['ticket'], '***');
    expect(out['passcode'], '***');
    expect(out['pin'], '***');
    expect(out['nested'], {'Passcode': '***', 'PIN': '***'});
    expect(out['name'], 'kept');
    for (final k in ['id_token', 'ticket', 'passcode', 'pin']) {
      expect(logSensitiveKeys, contains(k), reason: k);
    }
  });
}
