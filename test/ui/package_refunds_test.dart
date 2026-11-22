// Refunds due (D-1640): the admin list of package payments that arrived with no seat. The server's shape parsed
// (GET /admin/packages/refunds-due), and the tab's body on a phone and a wide window, ar / en, text 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teachers/teacher_review_admin.dart' show PackageRefundsList;
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> refundJson({int id = 5, String reason = 'left'}) => {
      'payment_id': id,
      'package': {'id': 11, 'title': 'أحكام النون الساكنة والتنوين والميم الساكنة مع التطبيق على جزء عمّ كاملاً', 'teacher_id': 7},
      'student': {'user_id': 42, 'name': 'عبد الرحمن محمد أحمد الأنصاري الحافظ لكتاب الله'},
      'amount': 12345.5,
      'currency': 'SAR',
      'provider': 'moyasar',
      'gateway_id': 'pay_abc',
      'reason': reason,
      'paid_at': '2026-11-20T10:00:00',
    };

void main() {
  test('parses the refunds-due answer', () {
    AppConfig.lang = 'en';
    final l = packageRefundsFromJson({'items': [refundJson(), refundJson(id: 6, reason: 'duplicate')], 'total': 2});
    expect(l.length, 2);
    final r = l.first;
    expect((r.paymentId, r.packageId, r.studentId, r.amount, r.currency, r.reason), (5, 11, 42, 12345.5, 'SAR', 'left'));
    expect(r.gatewayId, 'pay_abc');
    expect(r.paidAt, DateTime.utc(2026, 11, 20, 10));
    expect(packageRefundReasonText('closed'), contains('closed'));
    expect(packageRefundReasonText(l.last.reason), contains('already paid'));
    expect(packageRefundsFromJson(null), isEmpty);
  });

  testWidgets('refunds list: loading, empty and rows', (tester) async {
    final rows = [for (final (i, why) in [(1, 'left'), (2, 'closed'), (3, 'duplicate')]) PackageRefundDue.fromJson(refundJson(id: i, reason: why))];
    for (final items in <List<PackageRefundDue>?>[null, const [], rows]) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(child: PackageRefundsList(items: items, busyId: 2, onDone: (_) {})),
      );
    }
  });
}
