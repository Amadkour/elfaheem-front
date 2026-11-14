// Points wallet + live-meeting plan sheet (live-rooms-spec §8 – §9): the plain-values widgets at 320x640 and
// 1400x900, Arabic + English, textScaler 1.3.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/payments/points/live_plan_sheet.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'ملاحظة طويلة جداً من الإدارة حول طلب الشحن والتحويل البنكي والإيصال المرفق مع الطلب';
const longEn = 'A very long note from the admin about the top-up request, the bank transfer and the receipt attached';

final now = DateTime.now().toUtc();

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

PointsWallet wallet({bool empty = false}) => PointsWallet.fromJson({
      'balance': 123456,
      'price_per_point': 1.25,
      'currency': 'SAR',
      'topup_min': 10,
      'methods': ['bank_transfer', 'instapay'],
      'history': empty
          ? []
          : [
              for (final k in ['grant', 'deduct', 'topup', 'spend', 'refund'])
                {
                  'id': k.length,
                  'delta': k == 'spend' || k == 'deduct' ? -30000 : 99999,
                  'balance_after': 123456,
                  'kind': k,
                  'ref_type': k == 'spend' ? 'live_meeting' : null,
                  'note': '$longAr $longEn',
                  'by_user': {'name': longEn},
                  'created_at': iso(now),
                }
            ],
      'topups': empty
          ? []
          : [
              for (final st in ['pending', 'approved', 'rejected'])
                {
                  'id': st.length,
                  'points': 100000,
                  'amount': 125000.5,
                  'currency': 'SAR',
                  'method': st == 'pending' ? 'instapay' : 'bank_transfer',
                  'status': st,
                  'note': st == 'rejected' ? '$longAr $longEn' : null,
                  'created_at': iso(now),
                }
            ],
    });

LivePlan plan({bool active = false, bool needed = true, int balance = 12}) => LivePlan(
    active: active,
    endsAt: active ? now.add(const Duration(days: 29)) : null,
    pricePoints: 30000,
    days: 365,
    freeMinutes: 15,
    balance: balance,
    needed: needed);

Widget sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

PointsWallet cardWallet() => PointsWallet.fromJson({
      'balance': 5,
      'price_per_point': 1.25,
      'currency': 'SAR',
      'topup_min': 10,
      'methods': ['card', 'bank_transfer', 'instapay'],
      'history': [],
      'topups': [
        for (final st in ['pending', 'approved', 'rejected'])
          {
            'id': st.length,
            'points': 100000,
            'amount': 125000.5,
            'currency': 'SAR',
            'method': 'card',
            'provider': 'moyasar',
            'payment_id': 'pay_0123456789abcdef0123456789abcdef',
            'status': st,
            'note': st == 'rejected' ? '$longAr $longEn' : null,
            'created_at': iso(now),
          }
      ],
    });

LivePlan dailyPlan({int left = 12, bool autoRenew = false}) => LivePlan(
    pricePoints: 30000,
    days: 365,
    freeMinutes: 15,
    balance: 12,
    dailyFreeMinutes: 30,
    dailyFreeLeft: left,
    autoRenew: autoRenew);

void main() {
  group('wallet', () {
    testWidgets('loading', (tester) async {
      await expectNoLayoutErrors(tester, () => PointsWalletView(wallet: null, nowUtc: now));
    });

    testWidgets('load error', (tester) async {
      await expectNoLayoutErrors(
          tester, () => PointsWalletView(wallet: null, nowUtc: now, error: '$longAr $longEn', onRetry: () {}));
    });

    testWidgets('full: plan card, balance, top-ups, history', (tester) async {
      await expectNoLayoutErrors(
          tester, () => PointsWalletView(wallet: wallet(), plan: plan(), nowUtc: now, onBuy: () {}, onOpenPlan: () {}));
    });

    testWidgets('active plan, empty history', (tester) async {
      await expectNoLayoutErrors(tester,
          () => PointsWalletView(wallet: wallet(empty: true), plan: plan(active: true), nowUtc: now, onBuy: () {}, onOpenPlan: () {}));
    });

    testWidgets('staff: no plan card', (tester) async {
      await expectNoLayoutErrors(tester, () => PointsWalletView(wallet: wallet(), plan: plan(needed: false), nowUtc: now),
          act: (t) async => expect(find.byType(LivePlanSummary), findsNothing));
    });

    testWidgets('buy points form, then send with no receipt', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => sheet(TopupForm(wallet: wallet(), submit: (_, _, _, _) async => null)),
        act: (t) async {
          await t.ensureVisible(find.byIcon(Icons.send_rounded));
          await t.tap(find.byIcon(Icons.send_rounded));
        },
      );
    });

    testWidgets('buy points form with a picked receipt and a long amount', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => sheet(TopupForm(
            wallet: wallet(),
            submit: (_, _, _, _) async => null,
            pickReceipt: () async => ('${longEn.replaceAll(' ', '_')}.pdf', Uint8List.fromList([1, 2, 3])))),
        act: (t) async {
          await t.enterText(find.byType(TextField).first, '9999999');
          await t.tap(find.byIcon(Icons.upload_file_rounded));
        },
      );
    });
  });

  group('Part 3: card top-ups', () {
    testWidgets('card top-ups in the wallet (waiting for payment / approved / rejected)', (tester) async {
      await expectNoLayoutErrors(tester, () => PointsWalletView(wallet: cardWallet(), nowUtc: now, onBuy: () {}),
          act: (t) async => expect(find.text('Waiting for payment').evaluate().isNotEmpty || find.text('بانتظار الدفع').evaluate().isNotEmpty, isTrue));
    });

    testWidgets('the form with Card: no receipt, Pay by card; a checkout error', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => sheet(TopupForm(
            wallet: cardWallet(),
            submit: (_, _, _, _) async => null,
            checkout: (_) async => throw Exception('$longAr $longEn'))),
        act: (t) async {
          expect(find.byKey(const ValueKey('topup_form.card_note')), findsOneWidget);
          expect(find.byIcon(Icons.upload_file_rounded), findsNothing);
          await t.enterText(find.byType(TextField).first, '9999999');
          await t.pump();
          await t.ensureVisible(find.byKey(const ValueKey('topup_form.pay_card')));
          await t.tap(find.byKey(const ValueKey('topup_form.pay_card')));
        },
      );
    });

    testWidgets('Card hands the checkout back to the page', (tester) async {
      Object? popped;
      AppConfig.lang = 'en';
      await tester.pumpWidget(layoutHost(
        scaffold: false,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popped = await Navigator.of(ctx).push<Object>(MaterialPageRoute(
                      builder: (_) => Scaffold(
                          body: sheet(TopupForm(
                              wallet: cardWallet(),
                              submit: (_, _, _, _) async => null,
                              checkout: (p) async => PointsCheckout(topupId: 7, checkoutUrl: 'https://pay.example/$p', points: p))))));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('topup_form.pay_card')));
      await tester.tap(find.byKey(const ValueKey('topup_form.pay_card')));
      await tester.pumpAndSettle();
      expect(popped, isA<PointsCheckout>());
      expect((popped! as PointsCheckout).checkoutUrl, 'https://pay.example/10');
    });

    for (final phase in CardTopupPhase.values) {
      testWidgets('status sheet: ${phase.name}', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => sheet(CardTopupStatusView(
              phase: phase,
              points: 1000000,
              amountText: '1250000.75 SAR',
              reason: phase == CardTopupPhase.rejected ? '$longAr $longEn' : null,
              error: phase == CardTopupPhase.error ? '$longAr $longEn' : null,
              onCheckAgain: () {},
              onClose: () {})),
          act: (t) async {
            final recheck = phase == CardTopupPhase.waiting || phase == CardTopupPhase.error;
            expect(find.byKey(const ValueKey('card_topup.check_again')), recheck ? findsOneWidget : findsNothing);
          },
        );
      });
    }
  });

  group('Part 3: daily cap and auto-renew', () {
    testWidgets('daily minutes left today + the auto-renew switch', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => sheet(LivePlanView(plan: dailyPlan(autoRenew: true), nowUtc: now, onSubscribe: () {}, onWallet: () {}, onAutoRenew: (_) {})),
        act: (t) async {
          expect(find.byKey(const ValueKey('live_plan.daily_left')), findsOneWidget);
          expect(find.byKey(const ValueKey('live_plan.daily_left_text')), findsOneWidget);
          expect(find.byKey(const ValueKey('live_plan.auto_renew')), findsOneWidget);
          expect(find.byKey(const ValueKey('live_plan.daily_used_up')), findsNothing);
        },
      );
    });

    testWidgets('402 daily_limit: today is used up; renew switch busy', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => sheet(LivePlanView(
            plan: dailyPlan(left: 0),
            nowUtc: now,
            reason: kDailyLimitReason,
            autoRenewBusy: true,
            onSubscribe: () {},
            onWallet: () {},
            onAutoRenew: (_) {})),
        act: (t) async => expect(find.byKey(const ValueKey('live_plan.daily_used_up')), findsOneWidget),
      );
    });

    testWidgets('active plan: days left and renews automatically', (tester) async {
      final p = LivePlan.fromJson({
        'active': true,
        'ends_at': iso(now.add(const Duration(days: 3))),
        'days_left': 3,
        'auto_renew': true,
        'price_points': 30000,
        'days': 365,
        'balance': 99999,
        'needed': true,
        'daily_free_minutes': 30,
        'daily_free_left': 30,
      });
      await expectNoLayoutErrors(
        tester,
        () => sheet(LivePlanView(plan: p, nowUtc: now, onSubscribe: () {}, onWallet: () {}, onAutoRenew: (_) {})),
        act: (t) async {
          // an active plan has no daily cap
          expect(find.byKey(const ValueKey('live_plan.daily_left')), findsNothing);
          expect(find.textContaining(RegExp('3 days left|متبقٍ 3 يوم')), findsOneWidget);
        },
      );
    });
  });

  group('live plan sheet', () {
    testWidgets('loading', (tester) async {
      await expectNoLayoutErrors(tester, () => sheet(LivePlanView(plan: null, nowUtc: now)));
    });

    testWidgets('error', (tester) async {
      await expectNoLayoutErrors(
          tester, () => sheet(LivePlanView(plan: null, nowUtc: now, error: '$longAr $longEn', onRetry: () {})));
    });

    testWidgets('not subscribed', (tester) async {
      await expectNoLayoutErrors(
          tester, () => sheet(LivePlanView(plan: plan(), nowUtc: now, onSubscribe: () {}, onWallet: () {})));
    });

    testWidgets('not enough points', (tester) async {
      await expectNoLayoutErrors(tester,
          () => sheet(LivePlanView(plan: plan(), nowUtc: now, insufficient: true, onSubscribe: () {}, onWallet: () {})),
          act: (t) async => expect(find.byIcon(Icons.add_card_rounded), findsOneWidget));
    });

    testWidgets('active (extend) while busy', (tester) async {
      await expectNoLayoutErrors(tester,
          () => sheet(LivePlanView(plan: plan(active: true, balance: 99999), nowUtc: now, busy: true, onSubscribe: () {}, onWallet: () {})));
    });

    testWidgets('staff: unlimited', (tester) async {
      await expectNoLayoutErrors(tester, () => sheet(LivePlanView(plan: plan(needed: false), nowUtc: now, onClose: () {})));
    });

    testWidgets('subscribe error', (tester) async {
      await expectNoLayoutErrors(
          tester, () => sheet(LivePlanView(plan: plan(), nowUtc: now, error: '$longAr $longEn', onSubscribe: () {})));
    });
  });
}
