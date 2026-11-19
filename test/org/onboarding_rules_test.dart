// Member onboarding rules (contract §5): national ID, phone, name, `when`, required / missing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/org/onboarding/onboarding_models.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_rules.dart';
import 'package:flutter_test/flutter_test.dart';

OnbType _type() => OnbType.fromJson(Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/onboarding_type.json').readAsStringSync())['payload'] as Map));

void main() {
  final now = DateTime(2026, 11, 19);

  group('national ID', () {
    test('a valid ID gives the birth date, gender and governorate', () {
      final r = parseEgyptianNid('30503140101234', now: now);
      expect(r.ok, isTrue);
      expect(r.info!.birthIso, '2005-03-14');
      expect(r.info!.gender, 'm');
      expect(r.info!.governorate, '01');
      expect(egyptGovernorates['01']!.en, 'Cairo');
    });

    test('digit 13 even is female; century 2 is the 1900s', () {
      expect(parseEgyptianNid('30503140101224', now: now).info!.gender, 'f');
      expect(parseEgyptianNid('28001012101234', now: now).info!.birthIso, '1980-01-01');
    });

    test('Arabic-Indic digits, spaces and dashes are accepted', () {
      expect(parseEgyptianNid('٣٠٥٠٣١٤٠١٠١٢٣٤', now: now).ok, isTrue);
      expect(parseEgyptianNid('3 0503 14 01 0123-4', now: now).ok, isTrue);
      expect(normalizeDigits('۰۱۲'), '012');
    });

    test('format, date and governorate errors', () {
      expect(parseEgyptianNid('3050314010123', now: now).error, 'nid_format');
      expect(parseEgyptianNid('abc', now: now).error, 'nid_format');
      expect(parseEgyptianNid('10503140101234', now: now).error, 'nid_format'); // century digit 1
      expect(parseEgyptianNid('30513140101234', now: now).error, 'nid_date'); // month 13
      expect(parseEgyptianNid('30502300101234', now: now).error, 'nid_date'); // 30 February
      expect(parseEgyptianNid('39901010101234', now: now).error, 'nid_date'); // 2099: the future
      expect(parseEgyptianNid('30503140501234', now: now).error, 'nid_gov');
      expect(parseEgyptianNid('30503148801234', now: now).ok, isTrue); // 88 = born abroad
    });

    test('prefill gives the form its fields', () {
      expect(prefillFromNid('30503140101234', now: now), {'birth_date': '2005-03-14', 'gender': 'm', 'governorate': '01'});
      expect(prefillFromNid('123', now: now), isEmpty);
    });

    test('passport: 5 to 20 letters or digits', () {
      expect(validPassport('A1234567'), isTrue);
      expect(validPassport('A12'), isFalse);
      expect(validPassport('A1234-567'), isFalse);
    });
  });

  group('phone, e-mail, names', () {
    test('Egyptian mobiles normalise to the local form', () {
      expect(normalizeContactPhone('٠١٠١٢٣٤٥٦٧٨'), '01012345678');
      expect(normalizeContactPhone('+20 101 234 5678'), '01012345678');
      expect(normalizeContactPhone('0020 101 234 5678'), '01012345678');
      expect(normalizeContactPhone('1012345678'), '01012345678');
      expect(normalizeContactPhone('01512345678'), '01512345678');
    });

    test('other numbers are E.164, the rest is refused', () {
      expect(normalizeContactPhone('+966 50 123 4567'), '+966501234567');
      expect(normalizeContactPhone('00966501234567'), '+966501234567');
      expect(normalizeContactPhone('123'), isNull);
      expect(normalizeContactPhone('01312345678'), isNull);
      expect(normalizeContactPhone(''), isNull);
    });

    test('e-mail', () {
      expect(validEmail('a@x.org'), isTrue);
      expect(validEmail('a@x'), isFalse);
    });

    test('the Arabic name normaliser', () {
      expect(normalizeArName('أحمد  عبد الرحمن'), 'احمد عبدالرحمن');
      expect(normalizeArName('مُحَمَّد'), 'محمد');
      expect(normalizeArName('فاطمة'), 'فاطمه');
      expect(normalizeArName('على'), 'علي');
      expect(normalizeArName('إبراهيم آل ياسر'), 'ابراهيم ال ياسر');
      expect(normalizeArName('مـحمـد'), 'محمد');
      expect(normalizeArName('YOUSEF  Ali'), 'yousef ali');
      expect(normalizeArName('مؤمن'), 'مومن');
    });
  });

  group('when', () {
    final military = {'gender': 'm', 'nationality': 'EG', 'age_min': 18, 'age_max': 30};

    test('every key must match; the age comes from the birth date', () {
      final v = {'gender': 'm', 'nationality': 'EG', 'birth_date': '2000-01-01'};
      expect(whenMatches(military, v, now: now), isTrue);
      expect(whenMatches(military, {...v, 'gender': 'f'}, now: now), isFalse);
      expect(whenMatches(military, {...v, 'birth_date': '2010-01-01'}, now: now), isFalse, reason: '16 years old');
      expect(whenMatches(military, {...v, 'birth_date': '1990-01-01'}, now: now), isFalse, reason: '36 years old');
      expect(whenMatches(military, {'gender': 'm', 'nationality': 'EG'}, now: now), isFalse, reason: 'no birth date');
    });

    test('the age is a full year on the birthday', () {
      expect(ageOn(DateTime(2008, 11, 19), on: now), 18);
      expect(ageOn(DateTime(2008, 11, 20), on: now), 17);
    });

    test('nationality "!EG" means anyone not Egyptian', () {
      expect(whenMatches({'nationality': '!EG'}, {'nationality': 'SA'}), isTrue);
      expect(whenMatches({'nationality': '!EG'}, {'nationality': 'EG'}), isFalse);
      expect(whenMatches({'nationality': '!EG'}, {}), isFalse);
    });

    test('an empty when always matches; other keys compare for equality', () {
      expect(whenMatches(null, {}), isTrue);
      expect(whenMatches(const {}, {}), isTrue);
      expect(whenMatches({'level': '2'}, {'level': 2}), isTrue);
    });

    test('required levels', () {
      expect(onbIsRequired('mandatory', null, {}), isTrue);
      expect(onbIsRequired('optional', null, {}), isFalse);
      expect(onbIsRequired('conditional', null, {}), isFalse);
      expect(onbIsRequired('conditional', {'gender': 'm'}, {'gender': 'm'}), isTrue);
      expect(onbIsRequired('conditional', {'gender': 'm'}, {'gender': 'f'}), isFalse);
    });
  });

  group('missing', () {
    final type = _type();
    final base = {'full_name': 'Ali', 'national_id': '30503140101234', 'nationality': 'EG', 'birth_date': '2005-03-14', 'gender': 'm', 'phone': '01012345678'};

    test('a complete Egyptian male of 21 lacks only his documents', () {
      final m = computeMissing(type, base, const [], now: now);
      expect(m.fields, isEmpty);
      expect(m.documents, ['photo', 'military_form']);
      expect(m.later, ['military_form'], reason: 'allow_later');
      expect(m.blockingDocuments, ['photo']);
      expect(m.canSubmit, isFalse);
    });

    test('a woman is not asked for the military form; passport only for foreigners', () {
      final m = computeMissing(type, {...base, 'gender': 'f'}, const [], now: now);
      expect(m.documents, ['photo']);
      expect(m.fields, isEmpty);
      final foreign = computeMissing(type, {'full_name': 'Ali', 'nationality': 'SA', 'birth_date': '2000-01-01', 'gender': 'm', 'phone': '01012345678'}, const [], now: now);
      expect(foreign.fields, ['passport_no'], reason: 'national_id is for Egyptians only');
    });

    test('empty required fields are listed; the guardian only for minors', () {
      final m = computeMissing(type, {'nationality': 'EG'}, const [], now: now);
      expect(m.fields, containsAll(['full_name', 'national_id', 'birth_date', 'gender', 'phone']));
      expect(m.fields, isNot(contains('guardian_name')));
      final minor = computeMissing(type, {...base, 'birth_date': '2012-05-05'}, const [], now: now);
      expect(minor.fields, ['guardian_name']);
    });

    test('a verified photo and a late-allowed form let the case submit; a rejected photo does not count', () {
      const photo = OnbDocRecord(id: 1, reqKey: 'photo', status: 'verified');
      expect(computeMissing(type, base, const [photo], now: now).canSubmit, isTrue);
      const bad = OnbDocRecord(id: 1, reqKey: 'photo', status: 'rejected');
      expect(computeMissing(type, base, const [bad], now: now).documents, contains('photo'));
      const waived = OnbDocRecord(id: 2, reqKey: 'military_form', status: 'waived');
      expect(computeMissing(type, base, const [photo, waived], now: now).isEmpty, isTrue);
    });

    test('hasValue', () {
      expect(hasValue(''), isFalse);
      expect(hasValue('  '), isFalse);
      expect(hasValue(const []), isFalse);
      expect(hasValue(false), isFalse);
      expect(hasValue(0), isTrue);
      expect(hasValue('x'), isTrue);
    });
  });
}
