// Behaviour of the Finance hub fixes: the payout currency, quiet reloads, the request guard, the money-moving confirm,
// the server's reason on a failed action, Arabic digits in amounts, the failed-save text of the fee rates.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_fee_rates.dart';
import 'package:flutter_education_app/features/admin/admin_finance_provider.dart';
import 'package:flutter_education_app/features/admin/admin_models.dart';
import 'package:flutter_education_app/features/admin/admin_money_p8.dart';
import 'package:flutter_education_app/features/admin/admin_payouts_page.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'fin_support.dart';
import 'people_support.dart' show peopleRoutes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppConfig.lang = 'en');

  group('Withdrawal.currency', () {
    test('reads payout_currency, upper-cased; absent = null', () {
      expect(Withdrawal(finWithdrawal(0, currency: 'sar')).currency, 'SAR');
      expect(Withdrawal({...finWithdrawal(0), 'payout_currency': null}).currency, isNull);
      expect(Withdrawal({...finWithdrawal(0)}..remove('payout_currency')).currency, isNull);
      expect(Withdrawal({...finWithdrawal(0), 'payout_currency': '  '}).currency, isNull);
    });
  });

  group('parseAmountLoose', () {
    test('Arabic digits, decimal comma, thousands', () {
      expect(parseAmountLoose('2,5'), 2.5);
      expect(parseAmountLoose('٢،٥'), 2.5);
      expect(parseAmountLoose('١٢٫٥'), 12.5);
      expect(parseAmountLoose('1,000'), 1000);
      expect(parseAmountLoose('250'), 250);
      expect(parseAmountLoose('abc'), isNull);
      expect(parseAmountLoose(''), isNull);
    });
  });

  group('payout requests provider', () {
    test('a reload keeps the rows on screen until the new page arrives, then counts the money waiting', () async {
      final api = FakeApi(finRoutes(), latency: const Duration(milliseconds: 40));
      await finSetUp(api);
      final p = AdminPayoutRequestsProvider();
      await p.refresh();
      expect(p.rows.length, 5);
      expect(p.loaded, isTrue);
      // pending money: 1250.5 * (1+2+3+4+5)
      expect(p.pendingMoney, {'EGP': 1250.5 * 15});
      expect(p.pendingCount, 5);

      final reload = p.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(p.rows.length, 5, reason: 'rows must not be cleared while the reload is in flight');
      expect(p.loaded, isTrue, reason: 'no skeleton flash');
      await reload;
      expect(p.rows.length, 5);
    });

    test('a slow answer for an old status filter is dropped, not appended', () async {
      final api = FakeApi(finRoutes(), latency: const Duration(milliseconds: 40));
      await finSetUp(api);
      final p = AdminPayoutRequestsProvider();
      final first = p.setStatus('approved');
      final second = p.setStatus('paid');
      await Future.wait([first, second]);
      expect(p.status, 'paid');
      expect(p.rows.length, 5, reason: 'only the last filter answer is kept');
      expect(p.items.every((w) => w.status == 'paid'), isTrue);
    });

    test('search narrows by teacher name or e-mail', () async {
      final api = FakeApi(finRoutes(), latency: const Duration(milliseconds: 20));
      await finSetUp(api);
      final p = AdminPayoutRequestsProvider();
      await p.refresh();
      await p.setQuery('omar');
      expect(p.visible.map((w) => w.teacherName).toSet(), {'Omar Khaled'});
      await p.setQuery('teacher3@');
      expect(p.visible.single.teacherGmail, 'teacher3@example.test');
      await p.setQuery('');
      expect(p.visible.length, 5);
    });
  });

  group('shared paged provider', () {
    test('refresh() keeps the rows until the new page arrives', () async {
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 40));
      await finSetUp(api);
      final p = AdminUsersProvider('student');
      await p.refresh();
      final before = p.rows.length;
      expect(before, greaterThan(0));
      final reload = p.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(p.rows.length, before);
      expect(p.loaded, isTrue);
      await reload;
      expect(p.rows.length, before);
    });

    test('a failed load after a filter change does not leave the old filter\'s rows on screen', () async {
      var fail = false;
      final routes = {
        ...peopleRoutes(),
        'GET /api/v1/admin/users': (o) => fail ? const FakeResponse(500, {'detail': 'boom'}) : peopleRoutes()['GET /api/v1/admin/users']!(o),
      };
      final api = FakeApi(routes, latency: const Duration(milliseconds: 20));
      await finSetUp(api);
      final p = AdminUsersProvider('student');
      await p.refresh();
      expect(p.rows, isNotEmpty);
      fail = true;
      await p.setAdv('status', 'active');
      expect(p.rows, isEmpty);
      expect(p.error, isNotNull);
    });
  });

  group('payments hub', () {
    test('a failed approve keeps the SERVER\'s reason', () async {
      final api = FakeApi({
        ...finRoutes(),
        'POST /api/v1/admin/finance/transfers/*': (_) => const FakeResponse(409, {'detail': 'This transfer was already approved'}),
      }, latency: const Duration(milliseconds: 20));
      await finSetUp(api);
      final p = AdminFinanceProvider();
      addTearDown(p.dispose);
      expect(await p.approve(901), isFalse);
      expect(p.lastError, contains('already approved'));
      expect(await p.reject(901, 'blurry'), isFalse);
      expect(p.lastError, contains('already approved'));
    });

    test('a failed load-more is kept apart so the list can show Retry', () async {
      var calls = 0;
      final api = FakeApi({
        ...finRoutes(payments: 45),
        'GET /api/v1/admin/finance/payments': (o) {
          calls++;
          return calls == 2 ? const FakeResponse(500, {'detail': 'timeout'}) : paymentsRoute(o, total: 45);
        },
      }, latency: const Duration(milliseconds: 20));
      await finSetUp(api);
      final p = AdminFinanceProvider();
      addTearDown(p.dispose);
      await p.load(1);
      expect(p.history.items.length, 20);
      await p.loadMore(1);
      expect(p.history.items.length, 20);
      expect(p.history.moreError, isNotNull);
      expect(p.history.error, isNull, reason: 'the list itself is fine');
      await p.loadMore(1);
      expect(p.history.items.length, 40);
      expect(p.history.moreError, isNull);
    });

    test('fetchEvery walks every page (50 per request) for the export', () async {
      final api = FakeApi(finRoutes(payments: 120), latency: const Duration(milliseconds: 10));
      await finSetUp(api);
      final p = AdminFinanceProvider();
      addTearDown(p.dispose);
      final rows = await p.fetchEvery(1);
      expect(rows.length, 120);
    });
  });

  group('fee rates', () {
    test('a failed save keeps the server\'s message (never "could not load")', () async {
      final api = FakeApi({
        ...finRoutes(),
        'PUT /api/v1/admin/fees/*': (_) => const FakeResponse(409, {'detail': 'Percent must be between 0 and 100'}),
      }, latency: const Duration(milliseconds: 20));
      await finSetUp(api);
      final p = AdminFeeRatesProvider();
      await p.load();
      expect(await p.savePlatform(percent: 120), isFalse);
      expect(p.saveError, contains('between 0 and 100'));
    });
  });

  group('payouts: the approve question moves real money', () {
    testWidgets('names the teacher, the amount WITH its currency and the method', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetPhysicalSize);
      final api = FakeApi(finRoutes(), latency: const Duration(milliseconds: 30));
      final auth = await finSetUp(api);
      await tester.pumpWidget(layoutHost(finProviders(auth, const AdminPayoutsPage()), scaffold: false));
      await finFrames(tester, 10);
      expect(find.textContaining('EGP'), findsWidgets, reason: 'every amount carries its currency');

      await tester.tap(find.byIcon(Icons.check_rounded).first);
      await finFrames(tester, 6);
      // teacher · amount + currency · method (the first row is an automatic Moyasar payout)
      expect(find.textContaining('سارة أحمد'), findsWidgets);
      expect(find.textContaining('EGP'), findsWidgets);
      expect(find.byType(AlertDialog), findsOneWidget);
      // Cancel: nothing is sent
      await tester.tap(find.text('exam_cancel'.tr));
      await finFrames(tester, 4);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });
  });
}

