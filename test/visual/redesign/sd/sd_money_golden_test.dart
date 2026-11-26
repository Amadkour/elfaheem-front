// VISUAL review renders of the S-D money screens (redesign phase 2, Stu2Money): the wallet, its buy and help sheets,
// with the CAST.md demo data, at 390x844 and 1360x900, Arabic and English, light, Reduce motion ON. Into
// test/visual/redesign/sd/goldens/; compared by eye with D:/platform/redesign-ref/ref/student/1xx_Stu2Money_*.
//
//   flutter test test/visual/redesign/sd/sd_money_golden_test.dart --update-goldens [--plain-name wallet]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit_golden_harness.dart';
import 'sd_demo.dart';

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  Widget wallet() => SdArea(
        area: AppArea.money,
        child: PointsWalletView(
          wallet: sdWallet(),
          coins: 320,
          nowUtc: sdNow,
          onBuy: () {},
          onWardrobe: () {},
          onCoupons: () {},
        ),
      );

  testWidgets('wallet', (tester) async {
    await kitRender(tester, 'sd_wallet', wallet, storage: storage, modes: const [false]);
  });

  testWidgets('wallet buy sheet', (tester) async {
    await kitRender(
      tester,
      'sd_wallet_buy',
      () => SdArea(
        area: AppArea.money,
        child: Builder(
          builder: (context) => Center(
            child: AppButton.primary(
              label: 'open',
              onPressed: () => showAppSheet<Object>(
                context,
                (_) => TopupForm(wallet: sdWallet(), submit: (a, b, c, d) async => null, checkout: (_) async => throw 0),
              ),
            ),
          ),
        ),
      ),
      storage: storage,
      modes: const [false],
      grow: false,
      act: (t) async {
        await t.tap(find.text('open'));
        await t.pump(const Duration(milliseconds: 600));
        await t.tap(find.byKey(const ValueKey('topup_form.preset.1000')));
      },
    );
  });

  testWidgets('wallet help sheet', (tester) async {
    await kitRender(
      tester,
      'sd_wallet_help',
      () => SdArea(
        area: AppArea.money,
        child: Builder(
          builder: (context) => Center(
            child: AppButton.primary(
              label: 'open',
              onPressed: () => showAppSheet<void>(context, (_) => WalletHelpSheet(wallet: sdWallet())),
            ),
          ),
        ),
      ),
      storage: storage,
      modes: const [false],
      grow: false,
      langs: const ['ar'],
      act: (t) async => t.tap(find.text('open')),
    );
  });
}
