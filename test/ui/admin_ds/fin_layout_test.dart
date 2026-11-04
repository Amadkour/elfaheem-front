// Layout of the Finance hub pages (Payouts, Payments & payouts, Payment methods, Points, Fees & reports): no overflow
// at 320x640 / 1400x900, Arabic + English, text x1.3, over a FakeApi that answers the finance routes like the server.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_finance_page.dart';
import 'package:flutter_education_app/features/admin/admin_money_p8.dart';
import 'package:flutter_education_app/features/admin/admin_payment_page.dart';
import 'package:flutter_education_app/features/admin/admin_payouts_page.dart';
import 'package:flutter_education_app/features/admin/admin_points_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'fin_support.dart';

void main() {
  /// A tab strip scrolls sideways on a phone: bring the tab into view, then tap it.
  Future<void> tapTab(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
  }

  Future<void> layoutOf(WidgetTester tester, Widget Function() page,
      {Map<String, FakeHandler>? extra, Future<void> Function(WidgetTester)? act}) async {
    final api = FakeApi({...finRoutes(), ...?extra}, latency: const Duration(milliseconds: 50));
    final auth = await finSetUp(api);
    await expectNoLayoutErrors(tester, () => finProviders(auth, page()), frames: 8, scaffold: false, act: act);
  }

  testWidgets('Payouts: requests, teachers and settings tabs lay out', (tester) async {
    await layoutOf(tester, () => const AdminPayoutsPage(), act: (t) async {
      await tapTab(t, find.text('admin_teachers'.tr).first);
      await finFrames(t, 6);
      await tapTab(t, find.text('admin_settings'.tr).first);
      await finFrames(t, 6);
    });
  });

  testWidgets('Payouts: many requests (a long list) lay out', (tester) async {
    await layoutOf(tester, () => const AdminPayoutsPage(), extra: finRoutes(withdrawals: 45));
  });

  testWidgets('Payouts: nothing waiting', (tester) async {
    await layoutOf(tester, () => const AdminPayoutsPage(), extra: finRoutes(withdrawals: 0));
  });

  testWidgets('Payments & payouts: pending, history and payouts tabs', (tester) async {
    await layoutOf(tester, () => const AdminFinancePage(initialTab: 1), act: (t) async {
      await tapTab(t, find.text(AppConfig.lang == 'ar' ? 'السحوبات' : 'Payouts').first);
      await finFrames(t, 6);
      await tapTab(t, find.text(AppConfig.lang == 'ar' ? 'بانتظار المراجعة' : 'Pending').first);
      await finFrames(t, 6);
    });
  });

  testWidgets('Payments & payouts: a failed list shows the error, not a blank page', (tester) async {
    await layoutOf(tester, () => const AdminFinancePage(initialTab: 1), extra: {
      'GET /api/v1/admin/finance/payments': (_) => const FakeResponse(500, {'detail': 'The finance service is down'}),
    });
  });

  testWidgets('Payment methods page lays out', (tester) async {
    await layoutOf(tester, () => const AdminPaymentsPage(), act: (t) async {
      await tapTab(t, find.text('admin_fee_rates'.tr).first);
      await finFrames(t, 6);
    });
  });

  testWidgets('Points & wallets lays out', (tester) async {
    await layoutOf(tester, () => const AdminPointsPage(), act: (t) async {
      await tapTab(t, find.text(AppConfig.lang == 'ar' ? 'المستخدمون' : 'Users').first);
      await finFrames(t, 6);
      await tapTab(t, find.text(AppConfig.lang == 'ar' ? 'الإعدادات' : 'Settings').first);
      await finFrames(t, 6);
    });
  });

  testWidgets('Fees & financial reports: policy and ledger tabs', (tester) async {
    await layoutOf(tester, () => const AdminMoneyPage(superAdmin: true), act: (t) async {
      await tapTab(t, find.text(AppConfig.lang == 'ar' ? 'دفتر الأستاذ' : 'Ledger').first);
      await finFrames(t, 8);
    });
  });
}
