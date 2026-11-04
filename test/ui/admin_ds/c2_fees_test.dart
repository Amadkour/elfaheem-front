// Round C (R6, R4): ONE Fees page (Rates + Policy tabs) replaces the Fees tab of Payment methods and the Fee policy
// behind the Payments & payouts icon; the Payouts tab of Payments & payouts is a link to the Payouts page.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_fees_page.dart';
import 'package:flutter_education_app/features/admin/admin_finance_page.dart';
import 'package:flutter_education_app/features/admin/admin_money_p8.dart';
import 'package:flutter_education_app/features/admin/admin_payment_page.dart';
import 'package:flutter_education_app/features/admin/admin_payouts_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'fin_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppConfig.lang = 'en');

  Future<void> wide(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1400, 900);
    addTearDown(t.view.resetPhysicalSize);
  }

  Future<FakeApi> pump(WidgetTester t, Widget page, {Map<String, FakeHandler>? extra}) async {
    await wide(t);
    final api = FakeApi({...finRoutes(), ...?extra}, latency: const Duration(milliseconds: 30));
    final auth = await finSetUp(api);
    await t.pumpWidget(finProviders(auth, layoutHost(page, scaffold: false)));
    await finFrames(t, 10);
    return api;
  }

  int stackIndex(WidgetTester t) =>
      t.widget<IndexedStack>(find.descendant(of: find.byType(AdminFeesPage), matching: find.byType(IndexedStack)).first).index!;

  testWidgets('layout: Rates and Policy tabs at every size', (tester) async {
    final api = FakeApi(finRoutes(), latency: const Duration(milliseconds: 50));
    final auth = await finSetUp(api);
    await expectNoLayoutErrors(tester, () => finProviders(auth, const AdminFeesPage(superAdmin: true)),
        frames: 8, scaffold: false, act: (t) async {
      final policy = find.text(AppConfig.lang == 'ar' ? 'السياسة' : 'Policy').first;
      await t.ensureVisible(policy);
      await t.tap(policy);
      await finFrames(t, 8);
    });
  });

  testWidgets('shows both tabs; the Policy tab keeps the links to organizations and the ledger', (tester) async {
    await pump(tester, const AdminFeesPage(superAdmin: true));
    expect(find.text('Rates'), findsOneWidget);
    expect(find.text('Policy'), findsOneWidget);
    expect(find.text('Platform fee'), findsWidgets);
    expect(stackIndex(tester), 0);
    await tester.tap(find.text('Policy'));
    await finFrames(tester, 6);
    expect(stackIndex(tester), 1);
    expect(find.text('Organization fees'), findsOneWidget);
    expect(find.text('Ledger report'), findsOneWidget);
    await tester.tap(find.text('Ledger report'));
    await finFrames(tester, 8);
    expect(find.byType(AdminMoneyPage), findsOneWidget);
  });

  testWidgets('Rates: a save sends exactly what the old screen sent (PUT /fees/platform)', (tester) async {
    Object? body;
    await pump(tester, const AdminFeesPage(superAdmin: true), extra: {
      'PUT /api/v1/admin/fees/platform': (o) {
        body = o.data;
        return {'percent': 12, 'fixed': 0, 'is_default': false, 'default_percent': 10, 'default_fixed': 0};
      },
    });
    await tester.tap(find.text('Edit details').first);
    await finFrames(tester, 8);
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.tap(find.text('Save'));
    await finFrames(tester, 6);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await finFrames(tester, 8);
    expect(body, {'percent': 12.0, 'fixed': 0.0});
  });

  testWidgets('Policy: a save sends the policy body, and Back asks while the form is unsaved', (tester) async {
    Object? body;
    final api = await pump(tester, const AdminFeesPage(initialTab: 1, superAdmin: true), extra: {
      'PUT /api/v1/admin/fees/policy': (o) {
        body = o.data;
        return {'ok': true};
      },
    });
    expect(stackIndex(tester), 1);
    await tester.tap(find.text('Save').last);
    await finFrames(tester, 6);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await finFrames(tester, 8);
    expect(body, {'fee_bearer': 'both', 'vat_on': 'fee'});
    expect(api.calls.where((c) => c.method == 'PUT' && c.path.endsWith('/fees/policy')), hasLength(1));
  });

  testWidgets('Payment methods: the Fees tab is a link card that opens the Fees page (Rates)', (tester) async {
    await pump(tester, const AdminPaymentsPage());
    await tester.tap(find.text('admin_fee_rates'.tr).first);
    await finFrames(tester, 6);
    expect(find.text('Fees moved to the Fees page'), findsOneWidget);
    expect(find.text('Platform fee'), findsOneWidget, reason: 'only the KPI, no rate editor is drawn here any more');
    await tester.tap(find.text('Open the Fees page'));
    await finFrames(tester, 10);
    expect(find.byType(AdminFeesPage), findsOneWidget);
    expect(stackIndex(tester), 0);
  });

  testWidgets('Payments & payouts: the policy icon opens the Fees page on the Policy tab', (tester) async {
    await pump(tester, const AdminFinancePage(initialTab: 1));
    await tester.tap(find.byTooltip('Fees & fee policy'));
    await finFrames(tester, 10);
    expect(find.byType(AdminFeesPage), findsOneWidget);
    expect(stackIndex(tester), 1);
  });

  testWidgets('Payments & payouts: the Payouts tab is a link card with the pending count, opening the Payouts page',
      (tester) async {
    await pump(tester, const AdminFinancePage(initialTab: 1));
    await tester.tap(find.text('Payouts').first);
    await finFrames(tester, 6);
    expect(find.text('Teacher payouts are handled on the Payouts page.'), findsOneWidget);
    expect(find.text('4 requests waiting'), findsOneWidget);
    await tester.tap(find.text('Open the Payouts page'));
    await finFrames(tester, 10);
    expect(find.byType(AdminPayoutsPage), findsOneWidget);
  });
}
