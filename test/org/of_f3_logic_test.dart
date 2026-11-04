// Org flow overhaul, agent f3: the pure logic behind the Super Admin organizations page, the typed-name confirmation,
// the application form's field errors, the status page, the setup checklist (C5) and the billing page (C3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_organizations_page.dart';
import 'package:flutter_education_app/features/org/home/org_setup_checklist.dart';
import 'package:flutter_education_app/features/org/org_application_screen.dart';
import 'package:flutter_education_app/features/org/org_billing_page.dart';
import 'package:flutter_education_app/features/org/org_danger_zone.dart';
import 'package:flutter_education_app/features/org/org_status_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  group('organizations list filters', () {
    test('a filter becomes the status query, an unknown one falls back to pending', () {
      expect(orgFilterQuery('all'), {'status': 'all'});
      expect(orgFilterQuery('suspended'), {'status': 'suspended'});
      expect(orgFilterQuery('nope'), {'status': 'pending'});
      expect(orgStatusFilters, contains('all'));
    });

    test('counts come from /stats; "all" is the total, else the sum of the live statuses', () {
      expect(orgFilterCounts({'pending': 3, 'approved': 10, 'rejected': 1, 'suspended': 2, 'total': 20}),
          {'pending': 3, 'approved': 10, 'rejected': 1, 'suspended': 2, 'all': 20});
      expect(orgFilterCounts({'pending': 3, 'approved': 10, 'rejected': 1, 'suspended': 2, 'deleted': 4})['all'], 16);
      expect(orgFilterCounts({'pending': 2}), {'pending': 2, 'all': 2});
      expect(orgFilterCounts(null), isEmpty);
      expect(orgFilterCounts({}), isEmpty);
    });

    test('the detail panel offers the right actions per status', () {
      expect(orgAdminActions('pending'), containsAll(['approve', 'reject', 'edit', 'delete']));
      expect(orgAdminActions('pending'), isNot(contains('suspend')));
      expect(orgAdminActions('approved'), containsAll(['suspend', 'change_admin', 'open_dashboard', 'delete']));
      expect(orgAdminActions('suspended'), containsAll(['reactivate', 'change_admin']));
      // a deleted organization can only be restored
      expect(orgAdminActions('deleted'), {'restore'});
    });

    test('profile diff sends only the changed fields', () {
      final org = {'name_ar': 'جامعة', 'name_en': 'Uni', 'description': null, 'contact_email': 'a@b.co'};
      expect(orgProfileDiff(org, {'name_ar': 'جامعة', 'name_en': 'Uni ', 'description': '', 'contact_email': 'x@y.co'}),
          {'contact_email': 'x@y.co'});
      expect(orgProfileDiff(org, {'name_en': 'University'}), {'name_en': 'University'});
      expect(orgProfileDiff(org, {'contact_email': ''}), {'contact_email': ''});
    });
  });

  group('typed-name confirmation', () {
    final org = {'name_ar': 'جامعة النيل', 'name_en': 'Nile University'};

    test('the Arabic or English name, trimmed and case-insensitive', () {
      expect(orgNameConfirmed('Nile University', org), isTrue);
      expect(orgNameConfirmed('  nile   university ', org), isTrue);
      expect(orgNameConfirmed('جامعة النيل', org), isTrue);
    });

    test('anything else is refused, including an empty name', () {
      expect(orgNameConfirmed('Nile', org), isFalse);
      expect(orgNameConfirmed('', org), isFalse);
      expect(orgNameConfirmed('   ', {'name_ar': '', 'name_en': ''}), isFalse);
    });

    test('a reason needs 5 characters', () {
      expect(orgReasonOk('abcd'), isFalse);
      expect(orgReasonOk(' abcde '), isTrue);
    });

    test('the transfer body keeps the old admin choice or falls back to staff', () {
      expect(orgTransferBody(userId: 7, oldAdmin: 'remove', reason: ' moved '), {'user_id': 7, 'old_admin': 'remove', 'reason': 'moved'});
      expect(orgTransferBody(userId: 7, oldAdmin: 'x', reason: 'r')['old_admin'], 'staff');
    });
  });

  group('application form', () {
    Map<String, String> errors({String name = 'Sara Ali', String email = 'a@b.co', String pw = 'abcdefg1', String pw2 = 'abcdefg1', String ar = 'جامعة', String en = '', String orgEmail = '', bool fee = true}) =>
        orgApplicationErrors(name: name, email: email, password: pw, password2: pw2, nameAr: ar, nameEn: en, orgEmail: orgEmail, feeOk: fee);

    test('a good form has no errors', () => expect(errors(), isEmpty));

    test('each problem lands on its own field', () {
      expect(errors(name: 'x').keys, ['name']);
      expect(errors(email: 'nope').keys, ['email']);
      expect(errors(pw: 'short', pw2: 'short').keys, ['password']);
      expect(errors(pw2: 'different1').keys, ['password2']);
      expect(errors(ar: '', en: '').keys, ['org_name']);
      expect(errors(en: 'Uni', ar: '').isEmpty, isTrue);
      expect(errors(orgEmail: 'bad').keys, ['org_email']);
      expect(errors(fee: false).keys, ['fee']);
    });

    test('several problems are all reported', () {
      expect(errors(name: '', email: '', ar: '', fee: false).keys, containsAll(['name', 'email', 'org_name', 'fee']));
    });

    test('server codes map to a field', () {
      expect(orgApplicationErrorField('email_taken'), 'email');
      expect(orgApplicationErrorField('weak_password'), 'password');
      expect(orgApplicationErrorField('org_fee_required'), 'fee');
      expect(orgApplicationErrorField('boom'), isNull);
    });
  });

  group('status page', () {
    test('what is offered per status', () {
      expect(orgStatusActions('pending'), (edit: true, resubmit: false, contact: false));
      expect(orgStatusActions('rejected'), (edit: true, resubmit: true, contact: true));
      expect(orgStatusActions('suspended'), (edit: false, resubmit: false, contact: true));
    });

    test('the fee state', () {
      expect(orgFeeState(null), isNull);
      expect(orgFeeState({'required': false}), 'free');
      expect(orgFeeState({'required': true, 'payment': {'usable': true}}), 'paid');
      expect(orgFeeState({'required': true, 'payment': {'status': 'review', 'usable': false}}), 'review');
      expect(orgFeeState({'required': true}), 'unpaid');
    });
  });

  group('setup checklist (C5)', () {
    Map<String, dynamic> payload({bool dismissed = false, List<String> done = const []}) => {
          'dismissed': dismissed,
          'steps': [
            // the server's order is not trusted: they arrive shuffled, with a key we do not know
            for (final k in ['courses', 'profile', 'future_step', 'timetable', 'departments', 'people', 'term', 'join_method'])
              {'key': k, 'done': done.contains(k), 'count': done.contains(k) ? 2 : null},
          ],
        };

    test('steps follow the fixed order and unknown keys are dropped', () {
      final d = OrgSetupData.fromJson(payload());
      expect(d.steps.map((s) => s.key), orgSetupOrder);
    });

    test('progress and the next step', () {
      final d = OrgSetupData.fromJson(payload(done: ['profile', 'departments']));
      expect(d.doneCount, 2);
      expect(d.progress, closeTo(2 / 7, 1e-9));
      expect(d.next?.key, 'join_method');
      expect(d.allDone, isFalse);
    });

    test('shown only to admins, when not dismissed and something is left', () {
      final open = OrgSetupData.fromJson(payload(done: ['profile']));
      expect(orgSetupShow(open, isAdmin: true), isTrue);
      expect(orgSetupShow(open, isAdmin: false), isFalse);
      expect(orgSetupShow(null, isAdmin: true), isFalse);
      expect(orgSetupShow(OrgSetupData.fromJson(payload(dismissed: true)), isAdmin: true), isFalse);
      expect(orgSetupShow(open.dismissedCopy(), isAdmin: true), isFalse);
      expect(orgSetupShow(OrgSetupData.fromJson(payload(done: orgSetupOrder)), isAdmin: true), isFalse);
      expect(orgSetupShow(const OrgSetupData(dismissed: false, steps: []), isAdmin: true), isFalse);
    });

    test('every step has a target the home can open', () {
      for (final k in orgSetupOrder) {
        final to = orgSetupTarget(k);
        expect(to.section != null || to.action != null, isTrue, reason: k);
        expect(orgSetupTitle(k), isNot(k));
        expect(orgSetupActionLabel(k), isNotEmpty);
      }
      expect(orgSetupTarget('profile').action, 'edit_profile');
      expect(orgSetupTarget('join_method').action, 'join_code');
      expect(orgSetupTarget('courses'), (section: 'academics', sub: 'courses', action: null));
      expect(orgSetupTarget('timetable').section, 'timetable');
    });
  });

  group('billing page (C3)', () {
    final json = {
      'configured': false,
      'plans': [
        {'code': 'yearly', 'label_ar': 'سنوي', 'label_en': 'Yearly', 'price': 1200, 'currency': 'EGP'},
      ],
      'applies_to': {'students': 'per_account', 'staff': 'charged', 'admins': 'free'},
      'notice': 'unset_yearly_default',
      'creation_fee': {'paid': true, 'amount': 500.5, 'currency': 'EGP', 'paid_at': '2026-10-01T10:00:00', 'method': 'card'},
      'payments': [
        {'id': 9, 'kind': 'creation_fee', 'amount': 500.5, 'currency': 'EGP', 'status': 'paid', 'method': 'card', 'created_at': '2026-10-01T10:00:00'},
      ],
    };

    test('parses the contract', () {
      final d = OrgBillingData.fromJson(json);
      expect(d.configured, isFalse);
      expect(d.plans.single.label, 'Yearly');
      expect(d.hasFee, isTrue);
      expect(d.feePaid, isTrue);
      expect(d.payments.single.id, '9');
      expect(d.notice, 'unset_yearly_default');
    });

    test('no creation fee / no payments / an older shape', () {
      final d = OrgBillingData.fromJson({'configured': true, 'plans': [], 'applies_to': {}, 'creation_fee': null, 'payments': []});
      expect(d.hasFee, isFalse);
      expect(d.payments, isEmpty);
      expect(d.notice, isNull);
    });

    test('who pays, in plain words', () {
      expect(orgPaysText('free'), 'Free');
      expect(orgPaysText(true), 'Free');
      expect(orgPaysText('per_course'), 'Pays per course');
      expect(orgPaysText('per_account'), 'Pays a subscription');
      expect(orgPaysText('charged'), 'Pays a subscription');
      expect(orgPaysText(null), '—');
    });

    test('the unset_yearly_default notice is explained, nothing else says anything', () {
      expect(orgBillingNotice('unset_yearly_default'), contains('yearly plan'));
      AppConfig.lang = 'ar';
      expect(orgBillingNotice('unset_yearly_default'), contains('الاشتراك السنوي'));
      expect(orgBillingNotice(null), isNull);
    });
  });
}
