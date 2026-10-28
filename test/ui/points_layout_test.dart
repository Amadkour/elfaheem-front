// Points wallet + live-meeting plan sheet (live-rooms-spec §8 – §9): the plain-values widgets at 320x640 and
// 1400x900, Arabic + English, textScaler 1.3.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/points/live_plan_sheet.dart';
import 'package:flutter_education_app/features/shared/points/points_api.dart';
import 'package:flutter_education_app/features/shared/points/points_wallet_page.dart';
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
