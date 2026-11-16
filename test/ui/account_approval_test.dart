// Registration modes (D-1121): the waiting page, the admins' queue card and banner, and the super admin's per-role
// mode row — no overflow at 320 and 1400 wide, Arabic and English, text at 130 %; plus the small pure helpers.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_account_approval.dart';
import 'package:flutter_education_app/features/admin/admin_account_fee_widgets.dart';
import 'package:flutter_education_app/features/auth/account_approval_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longReason = 'البيانات غير مكتملة: أرسل صورة البطاقة وشهادة التخرج ثم تواصل مع الإدارة لإعادة المراجعة';

Map<String, dynamic> _user({bool feeDue = false, bool paid = false, bool rejected = false, String role = 'teacher'}) => {
      'id': 7,
      'name': 'أ. محمد عبد الرحمن السيد الشربيني',
      'gmail': 'mohamed.abdelrahman.elsherbiny.teacher@example.com',
      'phone': '+201001234567',
      'role': role,
      'created_at': '2026-11-16T09:30:00',
      'approval_required': true,
      'approved_at': null,
      'rejected_at': rejected ? '2026-11-16T10:00:00' : null,
      'rejection_reason': rejected ? _longReason : null,
      'account_fee_paid_at': paid ? '2026-11-16T09:45:00' : null,
      'fee_due': feeDue,
      'fee_amount': feeDue ? 12500.5 : null,
      'fee_currency': feeDue ? 'EGP' : null,
    };

Widget _waiting({bool rejected = false, String? reason, bool paidFirst = false}) => SingleChildScrollView(
      child: AccountApprovalView(
        rejected: rejected,
        reason: reason,
        paidFirst: paidFirst,
        onCheck: () {},
        onContact: () {},
        onSignOut: () {},
      ),
    );

void main() {
  testWidgets('waiting page: pending, paid first, rejected with a long reason — every state fits', (tester) async {
    for (final w in [
      () => _waiting(),
      () => _waiting(paidFirst: true),
      () => _waiting(rejected: true, reason: _longReason),
      () => _waiting(rejected: true),
    ]) {
      await expectNoLayoutErrors(tester, w);
    }
  });

  testWidgets('waiting page: the reason shows only when rejected; the three actions are there', (tester) async {
    await tester.pumpWidget(layoutHost(_waiting(), scale: 1));
    expect(find.byKey(const ValueKey('account_approval.reason')), findsNothing);
    for (final k in ['account_approval.check', 'account_approval.sign_out', 'account_approval.contact']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
    await tester.pumpWidget(layoutHost(_waiting(rejected: true, reason: 'ناقص'), scale: 1));
    expect(find.byKey(const ValueKey('account_approval.reason')), findsOneWidget);
  });

  testWidgets('queue card: waiting, fee not paid, fee paid, rejected — every state fits', (tester) async {
    for (final u in [_user(), _user(feeDue: true, role: 'parent'), _user(paid: true), _user(rejected: true, role: 'student')]) {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: PendingAccountCard(user: u, onApprove: () {}, onReject: u['rejected_at'] == null ? () {} : null),
              ));
    }
    await expectNoLayoutErrors(tester, () => PendingAccountsBannerView(count: 23, onTap: () {}));
  });

  testWidgets('queue card: a rejected account can still be approved, never rejected twice', (tester) async {
    var approved = 0;
    await tester.pumpWidget(layoutHost(
        SingleChildScrollView(child: PendingAccountCard(user: _user(rejected: true), onApprove: () => approved++)),
        scale: 1));
    expect(find.byKey(const ValueKey('pending_accounts.reject')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pending_accounts.approve')));
    expect(approved, 1);
    await tester.pumpWidget(layoutHost(
        SingleChildScrollView(child: PendingAccountCard(user: _user(feeDue: true), onApprove: () {}, onReject: () {})),
        scale: 1));
    expect(find.byKey(const ValueKey('pending_accounts.fee_due')), findsOneWidget);
  });

  testWidgets('super admin row: every mode of every role fits; a chip picks the mode', (tester) async {
    final drafts = [for (final m in registrationModes) AccountFeeDraft()..mode = m];
    drafts[1].amount.text = '12500.50';
    addTearDown(() {
      for (final d in drafts) {
        d.amount.dispose();
      }
    });
    for (final d in drafts) {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: Column(children: [
                  for (final r in accountFeeRoles)
                    AccountFeeRoleRow(role: r, draft: d, currencies: const ['EGP', 'SAR', 'USD'], enabled: true, onChanged: () {}),
                ]),
              ));
    }
    final d = AccountFeeDraft();
    addTearDown(d.amount.dispose);
    var changed = 0;
    await tester.pumpWidget(layoutHost(
        SingleChildScrollView(
            child: AccountFeeRoleRow(
                role: 'student', draft: d, currencies: const ['EGP'], enabled: true, onChanged: () => changed++)),
        scale: 1));
    await tester.tap(find.byKey(const ValueKey('account_fee.student.paid_approval')));
    expect((d.mode, d.on, changed), ('paid_approval', true, 1));
  });

  test('modes and statuses', () {
    expect(registrationModes.where(modeCharges), ['paid', 'paid_approval']);
    expect(registrationModes.where(modeNeedsApproval), ['approval', 'paid_approval']);
    expect(AccountFeeDraft.modeOf({'required': true}), 'paid'); // a D-1120 server
    expect(AccountFeeDraft.modeOf({'mode': 'approval', 'required': false}), 'approval');
    expect(AccountFeeDraft.modeOf({'mode': 'nonsense'}), 'free');
    expect(approvalStatus(_user()), 'pending');
    expect(approvalStatus(_user(rejected: true)), 'rejected');
    expect(approvalStatus({..._user(), 'approved_at': '2026-11-16T11:00:00'}), isNull);
    expect(approvalStatus({'approval_required': false}), isNull);
  });
}
