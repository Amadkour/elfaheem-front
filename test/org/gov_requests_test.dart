// Requests for someone else, attachments and the approval chain (D-140 / D-141), the pure parts: the beneficiary
// draft validates like the server (../back/services/organization/governance/beneficiary.py) and builds the request
// body; the item / entity JSON of the new blocks parses; an uploaded attachment is sent back by id only; every new
// server code has a text in both languages.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gov_filter_test.dart' show sampleEntityJson, sampleItemJson;

/// An item filed by staff for an outside person, at step 2 of 3 of its chain, in its second round.
Map<String, dynamic> sampleRequestItemJson() => {
      ...sampleItemJson(),
      'beneficiary': {
        'kind': 'external',
        'name': 'منى سعيد',
        'relation': 'ولية أمر',
        'user': null,
        'phone': '+20 100 123 4567',
        'email': 'mona@example.com',
        'national_id': '29901011234567',
        'student_number': null,
      },
      'chain_step': {'index': 1, 'count': 3, 'kind': 'entity', 'round': 2},
      'chain': {
        'round': 2,
        'current': 1,
        'dept_id': 5,
        'steps': [
          {'kind': 'manager', 'status': 'approved', 'by': {'id': 11, 'name': 'Prof. Huda'}, 'at': '2026-11-01T09:00:00', 'note': 'ok', 'via': 'head', 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
          {'kind': 'entity', 'dept_id': 2, 'status': 'current', 'at': '2026-11-01T09:00:00', 'label_ar': 'شؤون الطلاب', 'label_en': 'Student affairs', 'dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'kind': 'service'}},
          {'kind': 'council', 'status': 'waiting', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
        ],
        'rounds': [
          {
            'round': 1,
            'steps': [
              {'kind': 'manager', 'status': 'approved', 'by': {'id': 11, 'name': 'Prof. Huda'}, 'at': '2026-10-30T09:00:00', 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
              {'kind': 'entity', 'dept_id': 2, 'status': 'rejected', 'by': {'id': 7, 'name': 'Dr. Omar'}, 'at': '2026-10-31T09:00:00', 'note': 'Missing the signed form — please attach it', 'label_ar': 'شؤون الطلاب', 'label_en': 'Student affairs'},
              {'kind': 'council', 'status': 'waiting', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
            ],
          },
        ],
      },
      'attachments': [
        {'id': 31, 'name': 'signed form.pdf', 'type': 'application/pdf', 'ext': 'pdf', 'size': 182000, 'kind': 'file', 'preview': true},
        {'id': 32, 'name': 'photo.png', 'type': 'image/png', 'ext': 'png', 'size': 90000, 'kind': 'file', 'preview': true},
        {'name': 'old link', 'url': 'https://nextbrain.site/api/v1/org/files/abc.0123456789abcdef0123456789abcdef'},
      ],
      'can': {'view': true, 'route': true, 'decide': true, 'comment': true, 'edit': true, 'export': true, 'resubmit': false},
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('BeneficiaryDraft', () {
    test('self needs nothing and sends nothing', () {
      final d = BeneficiaryDraft();
      expect(d.validate(), isEmpty);
      expect(d.toJson(), isNull);
    });

    test('a member must be picked; relation optional', () {
      final d = BeneficiaryDraft(kind: 'member');
      expect(d.validate().keys, ['user_id']);
      d.member = const GovPerson(id: 9, name: 'Sara');
      d.relation = '  my   advisee ';
      expect(d.validate(), isEmpty);
      expect(d.toJson(), {'kind': 'member', 'user_id': 9, 'relation': 'my advisee'});
    });

    test('an outside person: the name rules', () {
      for (final bad in ['', 'x', '12345', 'Ali <b>']) {
        expect((BeneficiaryDraft(kind: 'external', name: bad)).validate().keys, contains('name'), reason: bad);
      }
      expect(BeneficiaryDraft(kind: 'external', name: 'منى سعيد').validate(), isEmpty);
    });

    test('optional fields are checked only when filled, like the server', () {
      Map<String, String> v(BeneficiaryDraft d) => d.validate();
      BeneficiaryDraft ok() => BeneficiaryDraft(kind: 'external', name: 'Ali Hassan');
      expect(v(ok()..phone = 'abc').keys, ['phone']);
      expect(v(ok()..phone = '+12').keys, ['phone']);
      expect(v(ok()..phone = '+20 (100) 123-4567'), isEmpty);
      expect(v(ok()..phone = '٠١٠٠١٢٣٤٥٦٧'), isEmpty, reason: 'Arabic digits are accepted');
      expect(v(ok()..email = 'not-an-email').keys, ['email']);
      expect(v(ok()..email = 'a@b.co'), isEmpty);
      expect(v(ok()..nationalId = '12').keys, ['national_id']);
      expect(v(ok()..nationalId = '٢٩٩٠١٠١١٢٣٤٥٦٧'), isEmpty);
      expect(v(ok()..studentNumber = 'a b<c').keys, ['student_number']);
      expect(v(ok()..studentNumber = '2021/0042'), isEmpty);
      expect(v(ok()..relation = '<script>').keys, ['relation']);
    });

    test('the body: trimmed, empty fields left out', () {
      final d = BeneficiaryDraft(kind: 'external', name: '  Mona   Saeed ', phone: ' +20 100 ', email: '', relation: 'mother');
      expect(d.toJson(), {'kind': 'external', 'name': 'Mona Saeed', 'phone': '+20 100', 'relation': 'mother'});
    });

    test('Arabic messages too', () {
      AppConfig.lang = 'ar';
      expect(BeneficiaryDraft(kind: 'external').validate()['name'], contains('الاسم'));
    });
  });

  test('item JSON: beneficiary, chain with rounds, the list card step', () {
    final it = WorkItem.fromJson(sampleRequestItemJson());
    final b = it.beneficiary!;
    expect((b.kind, b.name, b.relation, b.isExternal, b.hasContact), ('external', 'منى سعيد', 'ولية أمر', true, true));
    expect(b.studentNumber, isNull);
    final ch = it.chain!;
    expect((ch.round, ch.current, ch.steps.length, ch.rounds.length), (2, 1, 3, 1));
    expect(ch.currentStep!.kind, 'entity');
    expect(ch.currentStep!.label, 'Student affairs');
    expect(ch.steps.first.by!.name, 'Prof. Huda');
    expect(ch.rounds.first.$2[1].note, startsWith('Missing'));
    expect(it.chainStep!.label, 'Step 2/3 · Another entity');
    final plain = WorkItem.fromJson(sampleItemJson());
    expect((plain.beneficiary, plain.chain, plain.chainStep), (null, null, null));
  });

  test('attachments: an upload goes back by id, an older entry as it was', () {
    final it = WorkItem.fromJson(sampleRequestItemJson());
    final pdf = it.attachments[0], png = it.attachments[1], old = it.attachments[2];
    expect((pdf.isFile, pdf.isPdf, pdf.isImage, pdf.preview), (true, true, false, true));
    expect(png.isImage, isTrue);
    expect(pdf.toJson(), {'id': 31});
    expect(old.isFile, isFalse);
    expect(old.toJson(), {'name': 'old link', 'url': old.url});
  });

  test('entity: the for-others right and the chain from the member route', () {
    final e = Entity.fromJson({
      ...sampleEntityJson(),
      'can_submit_for_others': true,
      'chain': [
        {'kind': 'manager', 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
        {'kind': 'council', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
      ],
    });
    expect(e.canSubmitForOthers, isTrue);
    expect([for (final s in e.chain) s.kind], ['manager', 'council']);
    expect(Entity.fromJson(sampleEntityJson()).canSubmitForOthers, isFalse);
    expect(const ChainStep(kind: 'entity', deptId: 4).toSettingsJson(), {'kind': 'entity', 'dept_id': 4});
    expect(const ChainStep(kind: 'council').toSettingsJson(), {'kind': 'council'});
  });

  test('every new server code has a text in both languages', () {
    const codes = [
      'on_behalf_forbidden', 'beneficiary_invalid', 'beneficiary_not_member', 'beneficiary_anonymous', 'file_type', 'file_too_big',
      'attachment_invalid', 'too_many_attachments', 'attachment_not_found', 'storage_unavailable', 'ids_invalid', 'reason_required',
      'chain_invalid',
    ];
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      final texts = govCodeTexts();
      for (final c in codes) {
        expect(texts[c], isNotNull, reason: '$c ($lang)');
      }
    }
  });
}
