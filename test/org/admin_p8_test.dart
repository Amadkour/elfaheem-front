import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_feedback_settings.dart';
import 'package:flutter_education_app/features/admin/admin_money_p8.dart';
import 'package:flutter_education_app/features/org/org_feedback_risk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('numbers', () {
    test('parseNum reads Arabic digits and spaces; a comma only separates thousands', () {
      expect(parseNum('12,5'), isNull);
      expect(parseNum('1,000'), 1000);
      expect(parseNum('1,234.5'), 1234.5);
      expect(parseNum('١٢٫٥'), 12.5);
      expect(parseNum(' 7 '), 7);
      expect(parseNum(''), isNull);
      expect(parseNum('abc'), isNull);
      expect(numText(10), '10');
      expect(numText(2.5), '2.5');
      expect(numText(null), '');
    });
  });

  group('fee policy', () {
    test('parse and defaults', () {
      final p = FeePolicy.fromJson({'fee_bearer': 'split', 'student_share': 0.3, 'vat_on': 'price', 'is_default': false});
      expect((p.feeBearer, p.studentShare, p.vatOn, p.isDefault), ('split', 0.3, 'price', false));
      final d = FeePolicy.fromJson({'fee_bearer': 'nonsense', 'vat_on': 'x'});
      expect((d.feeBearer, d.vatOn, d.isDefault), ('both', 'fee', true));
    });
    test('draft validation and body', () {
      final d = FeePolicyDraft(bearer: 'split', share: '30', vatOn: 'none');
      expect(d.validate(), isNull);
      expect(d.body(), {'fee_bearer': 'split', 'student_share': 0.3, 'vat_on': 'none'});
      d.share = '120';
      expect(d.validate(), 'bad_share');
      d.share = 'x';
      expect(d.validate(), 'bad_share');
      d.bearer = 'student'; // share is ignored unless split
      expect(d.validate(), isNull);
      expect(d.body().containsKey('student_share'), isFalse);
      expect(FeePolicyDraft(bearer: 'nope').validate(), 'bad_choice');
    });
  });

  group('org overrides', () {
    final s = OrgFeeSettings.fromJson({
      'org_id': 4,
      'settings': {'platform_percent': 8, 'platform_fixed': null, 'fee_bearer': 'teacher', 'student_share': 0.25, 'vat_percent': null, 'vat_on': null, 'teacher_vat_percent': 5},
      'effective': {'platform_percent': 8, 'vat_percent': 15}
    });
    test('draft mirrors the own values; empty = inherit', () {
      final d = OrgFeeDraft.of(s);
      expect((d.platformPercent, d.platformFixed, d.bearer, d.share, d.vatPercent, d.teacherVatPercent), ('8', '', 'teacher', '25', '', '5'));
      expect(s.customised, isTrue);
      expect(OrgFeeSettings.fromJson({'org_id': 1, 'settings': {'platform_percent': null}}).customised, isFalse);
    });
    test('body sends every field, null for inherit, share as 0-1', () {
      final b = OrgFeeDraft.of(s).body();
      expect(b['platform_percent'], 8);
      expect(b['platform_fixed'], isNull);
      expect(b['fee_bearer'], 'teacher');
      expect(b['student_share'], 0.25);
      expect(b['vat_on'], isNull);
      expect(b.length, 7);
    });
    test('validation', () {
      expect(OrgFeeDraft(platformPercent: '101').validate(), 'bad_percent');
      expect(OrgFeeDraft(platformFixed: '10001').validate(), 'bad_fixed');
      expect(OrgFeeDraft(share: '-1').validate(), 'bad_share');
      expect(OrgFeeDraft(vatPercent: 'x').validate(), 'bad_percent');
      expect(OrgFeeDraft().validate(), isNull);
    });
  });

  group('refunds', () {
    test('full refund body has only the key', () {
      final d = RefundDraft(key: 'k1');
      expect(d.validate(superAdmin: false), isNull);
      expect(d.body(), {'idempotency_key': 'k1'});
    });
    test('partial amount is checked against what is left', () {
      final d = RefundDraft(amount: '30', remaining: 25, key: 'k');
      expect(d.validate(superAdmin: true), 'amount_exceeds');
      d.amount = '20,5';                           // a comma is never a decimal point (review D-004: 1,000 read as 1)
      expect(d.validate(superAdmin: true), 'bad_amount');
      d.amount = '20٫5';
      expect(d.validate(superAdmin: true), isNull);
      expect(d.body()['amount'], 20.5);
      d.amount = '0';
      expect(d.validate(superAdmin: true), 'bad_amount');
      d.amount = '-3';
      expect(d.validate(superAdmin: true), 'bad_amount');
    });
    test('manual and force are for the super admin; force needs a reason', () {
      final d = RefundDraft(manual: true, key: 'k');
      expect(d.validate(superAdmin: false), 'manual_super_only');
      expect(d.validate(superAdmin: true), isNull);
      d.force = true;
      expect(d.validate(superAdmin: true), 'reason_required');
      d.reason = ' bank paid by hand ';
      expect(d.validate(superAdmin: true), isNull);
      expect(d.body(), {'reason': 'bank paid by hand', 'idempotency_key': 'k', 'manual': true, 'force': true});
      expect((RefundDraft(force: true)..reason = 'x').validate(superAdmin: true), 'bad_choice');
    });
    test('the key is stable per draft and differs between drafts', () {
      final a = RefundDraft(), b = RefundDraft();
      expect(a.key, a.key);
      expect(a.key, isNot(b.key));
    });
    test('outcome: 202 pending with unknown outcome, and a resolved one', () {
      final o = RefundOutcome.fromJson({
        'refund': {'id': 9, 'status': 'pending', 'amount': 12.5, 'currency': 'SAR', 'outcome_unknown': true, 'manual': false},
        'refunded_amount': 0
      });
      expect((o.id, o.pending, o.outcomeUnknown, o.amount, o.refundedAmount), (9, true, true, 12.5, 0.0));
      final done = RefundOutcome.fromJson({'refund': {'id': 9, 'status': 'succeeded', 'amount': 12.5, 'currency': 'SAR'}});
      expect((done.pending, done.refundedAmount), (false, null));
    });
    test('codes map to text, unknown codes keep the server message', () {
      for (final c in [
        'refund_exceeds_remaining',
        'refund_in_progress',
        'refund_manual_forbidden',
        'refund_manual_needs_force',
        'reason_required',
        'refund_failed',
        'refund_key_conflict',
        'refund_gateway_failed',
        'super_admin_required',
        'fee_settings_super_admin_only'
      ]) {
        expect(feeCodeText(c, 'raw'), isNot('raw'), reason: c);
      }
      expect(feeCodeText('weird', 'raw'), 'raw');
      AppConfig.lang = 'ar';
      expect(feeCodeText('reason_required', 'x'), 'اكتب السبب');
    });
  });

  group('ledger', () {
    final json = {
      'group_by': 'org',
      'rows': [
        {'key': 3, 'label': null, 'currency': 'SAR', 'collected': 100, 'refunded': 10, 'teacher_net': 70.5, 'clawback': 0, 'paid_out': 20, 'teacher_balance': 50.5, 'platform': 15, 'tax': 2, 'gateway': 3},
        {'key': 4, 'label': 'Acme', 'currency': 'SAR', 'collected': 50},
      ],
      'totals': {
        'SAR': {'collected': 150, 'teacher_balance': 50.5}
      },
      'integrity': {'groups': 12, 'unbalanced_groups': 0},
    };
    test('parse rows, labels, totals and integrity', () {
      final r = LedgerReport.fromJson(json);
      expect(r.groupBy, 'org');
      expect(r.rows.length, 2);
      expect(r.rows[0].label, '#3');
      expect(r.rows[1].label, 'Acme');
      expect(r.rows[0].values['teacher_net'], 70.5);
      expect(r.rows[1].values['refunded'], 0);
      expect(r.totals['SAR']!['collected'], 150);
      expect((r.groups, r.balanced), (12, true));
      expect(LedgerReport.fromJson({'integrity': {'groups': 2, 'unbalanced_groups': 1}}).balanced, isFalse);
      expect(LedgerReport.fromJson({}).rows, isEmpty);
    });
    test('query params and validation', () {
      final q = LedgerQuery(groupBy: 'month', from: DateTime(2026, 1, 5), to: DateTime(2026, 2, 1), currency: 'sar');
      expect(q.params(), {'group_by': 'month', 'date_from': '2026-01-05', 'date_to': '2026-02-01', 'currency': 'SAR', 'format': 'json'});
      expect(q.params(format: 'csv')['format'], 'csv');
      expect(q.validate(), isNull);
      expect(LedgerQuery(from: DateTime(2026, 3, 1), to: DateTime(2026, 2, 1)).validate(), 'bad_range');
      expect(const LedgerQuery(currency: 'SA').validate(), 'bad_currency');
      expect(const LedgerQuery().params().containsKey('currency'), isFalse);
    });
  });

  group('feedback', () {
    test('settings parse (platform and organization shapes)', () {
      final p = FeedbackSettings.fromJson({'enabled': true, 'org_default': true, 'retention_days': 90, 'records': 12});
      expect((p.enabled, p.orgDefault, p.retentionDays, p.records), (true, true, 90, 12));
      final o = FeedbackSettings.fromJson({'enabled': false, 'retention_days': 365, 'platform_enabled': true, 'effective': true, 'effective_retention_days': 30, 'inherits': true});
      expect((o.platformEnabled, o.effective, o.effectiveDays, o.inherits), (true, true, 30, true));
    });
    test('draft validation and bodies', () {
      final d = FeedbackDraft(enabled: true, orgDefault: true, days: '90');
      expect(d.validate(), isNull);
      expect(d.platformBody(), {'enabled': true, 'org_default': true, 'retention_days': 90});
      expect(d.orgBody(), {'enabled': true, 'retention_days': 90});
      for (final bad in ['0', '3651', '1.5', 'x', '']) {
        expect(FeedbackDraft(days: bad).validate(), 'bad_days', reason: bad);
      }
      expect(FeedbackDraft(days: '3650').validate(), isNull);
    });
    test('since and export file names', () {
      expect(feedbackSince(null), isNull);
      expect(feedbackSince(DateTime(2026, 3, 9, 15)), '2026-03-09T00:00:00.000Z');
      expect(feedbackExportName('csv'), 'feedback-all.csv');
      expect(feedbackExportName('jsonl', orgId: 7), 'feedback-7.jsonl');
    });
  });

  group('risk', () {
    test('parse sorts by highest risk and share never divides by zero', () {
      final items = parseRisk({
        'items': [
          {'exam_id': 1, 'title': 'A', 'risky_attempts': 2, 'max_risk': 10, 'needs_review': 0},
          {'exam_id': 2, 'title': '', 'risky_attempts': 5, 'max_risk': 40.5, 'needs_review': 3},
        ]
      });
      expect(items.first.examId, 2);
      expect(items.first.displayTitle, '#2');
      expect(riskShare(10, 40.5), closeTo(0.2469, 0.001));
      expect(riskShare(5, 0), 0);
      expect(riskShare(99, 10), 1);
      expect(parseRisk({}), isEmpty);
    });
  });

  group('layout', () {
    final policy = FeePolicy.fromJson({'fee_bearer': 'split', 'student_share': 0.4, 'vat_on': 'fee', 'is_default': false});
    final org = OrgFeeSettings.fromJson({
      'org_id': 4,
      'settings': {'platform_percent': 8, 'fee_bearer': 'split', 'student_share': 0.25},
      'effective': {'platform_percent': 8, 'platform_fixed': 2, 'vat_percent': 15, 'student_share': 0.25, 'teacher_vat_percent': 0}
    });
    final report = LedgerReport.fromJson({
      'group_by': 'teacher',
      'rows': [
        for (var i = 0; i < 4; i++)
          {'key': i, 'label': 'A teacher with a very long name number $i that must not overflow', 'currency': 'SAR', 'collected': 1234567.89, 'platform': 12}
      ],
      'totals': {
        'SAR': {'collected': 4938271.56},
        'EGP': {'collected': 10}
      },
      'integrity': {'groups': 3, 'unbalanced_groups': 1},
    });

    testWidgets('fee policy form', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: FeePolicyForm(policy: policy, onSave: (_) {}, onReset: () {})));
      await expectNoLayoutErrors(t, () => FeePolicyForm(policy: policy, readOnly: true, onSave: (_) {}));
    });
    testWidgets('org fee form', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: OrgFeeForm(settings: org, onSave: (_) {}, onReset: () {})));
    });
    testWidgets('ledger report', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: LedgerReportView(report: report)));
      await expectNoLayoutErrors(t, () => LedgerReportView(report: LedgerReport.fromJson({})));
    });
    testWidgets('refund and resolve sheets', (t) async {
      await expectNoLayoutErrors(t, () => const RefundSheet(paymentId: 12, remaining: 99.5, currency: 'SAR', superAdmin: true));
      await expectNoLayoutErrors(t, () => const RefundResolveSheet());
    });
    testWidgets('feedback form and export bar', (t) async {
      const s = FeedbackSettings(enabled: true, orgDefault: true, retentionDays: 90, records: 1200, platformEnabled: false, effective: false, effectiveDays: 30, inherits: true);
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: FeedbackSettingsForm(settings: s, platform: true, onSave: (_) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: FeedbackSettingsForm(settings: s, onSave: (_) {})));
      await expectNoLayoutErrors(t, () => FeedbackExportBar(onExport: (_, _) async {}));
    });
    testWidgets('risk list', (t) async {
      final items = parseRisk({
        'items': [
          for (var i = 0; i < 3; i++) {'exam_id': i, 'title': 'A long exam title for the risk dashboard number $i, which wraps', 'risky_attempts': 5, 'max_risk': 20.0 + i, 'needs_review': i}
        ]
      });
      await expectNoLayoutErrors(t, () => RiskList(items: items));
      await expectNoLayoutErrors(t, () => const RiskList(items: []));
    });
  });
}
