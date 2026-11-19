// Member onboarding models parse the contract's sample payloads (test/fixtures/payloads/onboarding_*.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/$name.json').readAsStringSync())['payload'] as Map);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('TypeOut: fields, documents, chain, settings, intake', () {
    final ty = OnbType.fromJson(_fx('onboarding_type'));
    expect(ty.key, 'student_new');
    expect(ty.label, 'New student');
    expect(ty.module, 'students');
    expect(ty.fields, hasLength(10));
    expect(ty.field('national_id')!.when, {'nationality': 'EG'});
    expect(ty.field('gender')!.options.map((o) => o.value), ['m', 'f']);
    expect(ty.field('full_name')!.system, isTrue);
    expect(ty.doc('photo')!.isPhoto, isTrue);
    expect(ty.doc('photo')!.photoMinPx, 600);
    expect(ty.doc('military_form')!.allowLater, isTrue);
    expect(ty.doc('military_form')!.when!['age_max'], 30);
    expect(ty.chain.single.need, {'module': 'students', 'action': 'approve'});
    expect(ty.settings.autoActivate, isTrue);
    expect(ty.intake.enabled, isFalse);
    AppConfig.lang = 'ar';
    expect(ty.label, 'طالب مستجد');
  });

  test('a type survives a round trip to the PUT body', () {
    final ty = OnbType.fromJson(_fx('onboarding_type'));
    final back = OnbType.fromJson(ty.toJson());
    expect(back.toJson(), ty.toJson());
    expect(ty.toJson().keys, containsAll(['key', 'label_ar', 'label_en', 'base_role', 'module', 'fields', 'documents', 'chain', 'settings', 'active', 'sort']));
    expect(ty.copyWith(active: false).toJson()['active'], isFalse);
  });

  test('CaseOut: row, detail, documents, events, corrections, can', () {
    final c = OnbCase.fromJson(_fx('onboarding_case'));
    expect(c.id, 41);
    expect(c.status, 'under_review');
    expect(c.stepLabel, 'Student affairs');
    expect(c.nidMasked, '2••••••••••1234');
    expect(c.birthDate, '2005-03-14');
    expect(c.submittedAt, isNotNull);
    expect(c.missingCount, 1);
    expect(c.missingDocs, ['military_form']);
    expect(c.requiredDocs, ['photo', 'military_form']);
    expect(c.correctionFields.single.note, 'wrong number');
    expect(c.docFor('photo')!.status, 'verified');
    expect(c.docFor('photo')!.isImage, isTrue);
    expect(c.docFor('photo')!.filePath, endsWith('/documents/90/file'));
    expect(c.events.map((e) => e.kind), ['created', 'submitted']);
    expect(c.events.last.text, 'Submitted');
    expect(c.lockedFields, ['national_id']);
    expect(c.can.approve && c.can.unmask && c.can.viewDocuments, isTrue);
    expect(c.can.activate, isFalse);
    expect(c.detailed, isTrue);
    expect(c.isOpen, isTrue);
    expect(c.type, isNull);
    expect(c.generatedPassword, isNull);
  });

  test('values merges data and the system columns; the ID stays masked', () {
    final v = OnbCase.fromJson(_fx('onboarding_case')).values;
    expect(v['seat_no'], '123456');
    expect(v['full_name'], 'أحمد محمد علي');
    expect(v['national_id'], '2••••••••••1234');
    expect(v['gender'], 'm');
    expect(v['program_id'], 7);
    expect(v.containsKey('dept_id'), isFalse);
  });

  test('a case row (no detail keys) and the one-time password parse', () {
    final row = OnbCase.fromJson({'id': 5, 'type_key': 'x', 'status': 'submitted', 'full_name': 'A', 'overdue': true, 'generated_password': 'Zk3-pass'});
    expect(row.detailed, isFalse);
    expect(row.overdue, isTrue);
    expect(row.can.approve, isFalse);
    expect(row.generatedPassword, 'Zk3-pass');
    expect(row.nationality, 'EG');
  });

  test('summary counts feed the stage tabs', () {
    final s = OnbSummary.fromJson({
      'counts': {'draft': 2, 'submitted': 3, 'under_review': 4, 'needs_correction': 1, 'approved': 1, 'active': 10, 'rejected': 2},
      'overdue': 2,
      'by_type': {'student_new': {'submitted': 3}},
    });
    expect(s.toReview, 7);
    expect(s.needsCorrection, 1);
    expect(s.drafts, 2);
    expect(s.done, 13);
    expect(s.conditional, isNull, reason: 'not in the contract counts');
    expect(s.overdue, 2);
    expect(s.byType['student_new']!['submitted'], 3);
  });

  test('presets and reject reasons', () {
    final p = OnbPreset.fromJson({'key': 'egypt_public', 'label_ar': 'حكومية', 'label_en': 'Public', 'types': ['student_new', 'faculty']});
    expect(p.types, ['student_new', 'faculty']);
    expect(OnbRejectReason.fromJson({'key': 'dup', 'label_ar': 'مكرر', 'label_en': 'Duplicate'}).label, 'Duplicate');
  });

  test('unknown or missing keys never throw', () {
    expect(OnbCase.fromJson(const {}).id, 0);
    expect(OnbType.fromJson(const {}).fields, isEmpty);
    expect(OnbSummary.fromJson(const {}).done, 0);
  });
}
