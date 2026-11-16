// The account fee (D-1120): the pay page's content, the super admin's per-role row and the admin's
// paid / waived / pays-later choice — no overflow at 320 and 1400 wide, Arabic and English, text at 130 %.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_account_fee_widgets.dart';
import 'package:flutter_education_app/features/auth/account_fee_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _status({String role = 'teacher', Map<String, dynamic>? payment, bool methods = true}) => {
      'due': true,
      'required': true,
      'amount': 12500.5,
      'currency': 'EGP',
      'role': role,
      'methods': methods
          ? [
              {'id': 'paymob', 'label_ar': 'بطاقة أو محفظة (باي موب)', 'label_en': 'Card or wallet (Paymob)', 'kind': 'card'},
              {'id': 'instapay', 'label_ar': 'إنستاباي', 'label_en': 'InstaPay', 'kind': 'transfer'},
              {'id': 'bank_transfer', 'label_ar': 'تحويل بنكي', 'label_en': 'Bank transfer', 'kind': 'transfer'},
            ]
          : <Map<String, dynamic>>[],
      'payment': payment,
    };

Widget _view(Map<String, dynamic> s, {String? method = 'paymob', void Function(String)? onMethod}) => SingleChildScrollView(
      child: AccountFeeView(
        status: s,
        method: method,
        busy: false,
        onMethod: onMethod ?? (_) {},
        onPayCard: () {},
        onPayTransfer: () {},
        onCheck: () {},
        onSignOut: () {},
      ),
    );

void main() {
  testWidgets('pay page: every state fits', (tester) async {
    for (final s in [
      _status(),
      _status(role: 'parent', methods: false),
      _status(payment: {'status': 'review'}),
      _status(payment: {'status': 'rejected', 'review_note': 'الصورة غير واضحة، أعد الإرسال بصورة أوضح للإيصال كاملاً'}),
      _status(payment: {'status': 'failed'}),
    ]) {
      await expectNoLayoutErrors(tester, () => _view(s));
    }
  });

  testWidgets('pay page: card → Pay <price>, transfer → receipt; a method chip reports its id', (tester) async {
    String? picked;
    await tester.pumpWidget(layoutHost(_view(_status(), onMethod: (m) => picked = m), scale: 1));
    expect(find.textContaining('12500.50 EGP'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('account_fee.method.instapay')));
    expect(picked, 'instapay');
    await tester.pumpWidget(layoutHost(_view(_status(), method: 'instapay'), scale: 1));
    expect(find.byKey(const ValueKey('account_fee.pay')), findsOneWidget);
    expect(find.byKey(const ValueKey('account_fee.sign_out')), findsOneWidget);
    await tester.pumpWidget(layoutHost(_view(_status(payment: {'status': 'review'})), scale: 1));
    expect(find.byKey(const ValueKey('account_fee.pay')), findsNothing); // under review: nothing to pay
  });

  testWidgets('super admin row: off, on with amount; admin choice', (tester) async {
    final off = AccountFeeDraft();
    final on = AccountFeeDraft()
      ..on = true
      ..amount.text = '200';
    addTearDown(() {
      off.amount.dispose();
      on.amount.dispose();
    });
    for (final d in [off, on]) {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: Column(children: [
                  for (final r in accountFeeRoles)
                    AccountFeeRoleRow(role: r, draft: d, currencies: const ['EGP', 'SAR', 'USD'], enabled: true, onChanged: () {}),
                ]),
              ));
    }
    await expectNoLayoutErrors(
        tester, () => AccountFeeChoice(value: 'pay_later', feeLabel: '12500.50 EGP', onChanged: (_) {}));
  });

  test('draft body / differs and the status of a row', () {
    final d = AccountFeeDraft()..take({'required': true, 'amount': 200, 'currency': 'SAR'});
    expect(d.body, {'required': true, 'amount': 200.0, 'currency': 'SAR'});
    expect(d.differs({'required': true, 'amount': 200, 'currency': 'SAR'}), isFalse);
    d.amount.text = '250';
    expect(d.differs({'required': true, 'amount': 200, 'currency': 'SAR'}), isTrue);
    d.amount.dispose();
    expect(accountFeeStatus({'account_fee_paid_at': '2026-11-16T10:00:00'}, feeOn: true), 'paid');
    expect(accountFeeStatus({'account_fee_waived': true}, feeOn: true), 'waived');
    expect(accountFeeStatus({'account_fee_required': true}, feeOn: true), 'due');
    expect(accountFeeStatus({'account_fee_required': true}, feeOn: false), isNull); // fee off: released
    expect(accountFeeStatus({}, feeOn: true), isNull); // never asked
  });
}
