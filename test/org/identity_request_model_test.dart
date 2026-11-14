// The student's identifier requests (D-150): the real reply shapes (recorded from the backend's e2e test,
// test/org/fixtures/omr_setup_payloads.json) and the rules checked before sending — the same ones and the same
// sentences as services/identity_service.py, Arabic-Indic digits accepted.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show TextInputType;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/identity/identity_requests.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _p(String name) =>
    ((jsonDecode(File('test/org/fixtures/omr_setup_payloads.json').readAsStringSync()) as Map)['payloads'] as Map)[name] as Map<String, dynamic>;

const _nid = IdentityFieldDef(key: 'national_id', labelAr: 'الرقم القومي', labelEn: 'National ID', kind: 'digits', minLen: 14, maxLen: 14);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('GET /me/identity-requests: a paper exam\'s national id, due before exam day', () {
    final items = IdentityRequestItem.listFrom(_p('me_requests_nid'));
    final r = items.single;
    expect(r.id, 1);
    expect(r.examRef, 'exam:501');
    expect(r.examTitle, 'Physics midterm');
    expect(r.paper, isTrue);
    expect(r.dueUtc, DateTime.utc(2026, 11, 20, 7));
    expect((r.field.key, r.field.kind, r.field.minLen, r.field.maxLen), ('national_id', 'digits', 14, 14));
    expect(r.message, 'Your teacher needs your National ID for the upcoming exam. Please enter it before exam day.');
    AppConfig.lang = 'ar';
    expect(r.message, 'يحتاج معلمك إلى الرقم القومي للاختبار القادم. يُرجى إدخاله قبل يوم الاختبار.');
  });

  test('a custom field with a pattern; the sentence is rebuilt when the server sent none', () {
    final r = IdentityRequestItem.listFrom(_p('me_requests_custom')).single;
    expect((r.source, r.key), ('custom', 'passport_no'));
    expect(r.field.pattern, '[A-Z0-9]+');
    expect(r.dueUtc, isNull);
    expect(r.message, 'Your teacher needs your Passport number for the upcoming exam. Please enter it.');
    final bare = IdentityRequestItem.fromJson({'id': 3, 'field': {'key': 'passport_no', 'label_ar': 'رقم الجواز', 'label_en': 'Passport number'}});
    expect(bare.message, 'Your teacher needs your Passport number for the upcoming exam. Please enter it.');
  });

  group('rules (the server\'s validate)', () {
    test('digits: Arabic-Indic and dashes are fine, 13 digits break `length`', () {
      expect(normalizeIdentity('digits', ' ٢٩٩٠١٠١-٠٠٠٠٠٩٠ '), '29901010000090');
      expect(identityRuleBroken(_nid, '٢٩٩٠١٠١-٠٠٠٠٠٩٠'), isNull);
      expect(identityRuleBroken(_nid, '2990101000000'), 'length');
      expect(identityRuleText('length', _nid), 'This must be exactly 14 digits.');
      expect(identityRuleBroken(_nid, '29901O1000000a'), 'digits');
      expect(identityRuleBroken(_nid, '   '), 'required');
      expect(normalizeIdentity('digits', '۱۲۳'), '123', reason: 'Persian digits too');
    });

    test('e-mail, phone, pattern', () {
      const email = IdentityFieldDef(key: 'email', labelAr: 'البريد', labelEn: 'Email', kind: 'email', minLen: 3, maxLen: 254);
      const phone = IdentityFieldDef(key: 'phone', labelAr: 'الهاتف', labelEn: 'Phone number', kind: 'phone', minLen: 7, maxLen: 16);
      const pass = IdentityFieldDef(key: 'passport_no', labelAr: 'رقم الجواز', labelEn: 'Passport number', pattern: '[A-Z0-9]+', minLen: 6, maxLen: 9);
      expect(identityRuleBroken(email, 'A@B.io'), isNull);
      expect(identityRuleBroken(email, 'nope'), 'email');
      expect(identityRuleBroken(phone, '+20 (101) 234-5678'), isNull);
      expect(identityRuleBroken(phone, '12ab'), 'phone');
      expect(identityRuleBroken(pass, 'ab12345'), 'pattern');
      expect(identityRuleBroken(pass, 'AB12345'), isNull);
      expect(identityRuleBroken(pass, 'AB1'), 'length');
      expect(identityRuleText('length', pass), 'This must be 6 to 9 characters.');
      expect(identityRuleBroken(const IdentityFieldDef(key: 'x', labelAr: 'x', labelEn: 'x', pattern: '(['), 'abc'), isNull,
          reason: 'a pattern Dart cannot read is left to the server');
    });

    test('hint and keyboard follow the field', () {
      expect(identityHint(_nid), '14 digits');
      expect(identityKeyboard('digits'), TextInputType.number);
      expect(identityKeyboard('phone'), TextInputType.phone);
      expect(identityKeyboard('email'), TextInputType.emailAddress);
      AppConfig.lang = 'ar';
      expect(identityHint(_nid), '14 رقمًا');
      expect(identityRuleText('length', _nid), 'يجب أن يكون 14 رقمًا بالضبط');
    });
  });

  group('server answers', () {
    EngineResult fail(int status, Map<String, dynamic> body) =>
        EngineResult.fail(status, '${(body['detail'] as Map)['code']}', '${(body['detail'] as Map)['message']}', Map<String, dynamic>.from(body['detail'] as Map));

    test('409 identifier_taken: the server\'s exact sentence in each language', () {
      final r = fail(409, _p('err_taken'));
      expect(identitySubmitError(r, _nid), 'This number is already used by another student. Please check it.');
      AppConfig.lang = 'ar';
      expect(identitySubmitError(r, _nid), 'هذا الرقم مستخدم بالفعل من طالب آخر. يرجى التحقق منه.');
    });

    test('422 identifier_invalid says which rule failed', () {
      final r = fail(422, _p('err_invalid_length'));
      expect(r.detail['rule'], 'length');
      expect(identitySubmitError(r, _nid), 'This must be exactly 14 digits.');
      expect(identitySubmitError(EngineResult.fail(422, 'identifier_invalid', '', const {'rule': 'digits'}), _nid), 'Digits only, please.');
    });

    test('closed / not found requests are skipped; the reply closes every id it names', () {
      expect(identityRequestGone(EngineResult.fail(409, 'identity_request_closed', '')), isTrue);
      expect(identityRequestGone(EngineResult.fail(404, 'identity_request_not_found', '')), isTrue);
      expect(identityRequestGone(EngineResult.fail(409, 'identifier_taken', '')), isFalse);
      expect(closedIds(EngineResult.ok(_p('submit')), 1), {1});
      expect(closedIds(EngineResult.ok({'id': 4, 'closed': [4, 9]}), 4), {4, 9});
    });
  });
}
