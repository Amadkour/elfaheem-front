// Group A2 review renders (tag visual, not a CI suite): the Super Admin frame (SupPage) with CAST.md-style demo data
// at 390x844 and 1360x900, Arabic and English, light. Compare by eye with
// D:/platform/redesign-ref/ref/super/011_SupFinance_screen-payouts.{phone,web}.png (colours differ by brand only).
//
//   flutter test test/visual/redesign/a2 --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/sup/sup_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit_golden_harness.dart';

Widget _payouts() => Builder(
      builder: (context) => SupPage(
        title: 'مدفوعات المعلمين',
        kicker: 'مدفوعات المعلمين',
        headline: '٧ طلبات سحب تنتظرك',
        line: 'التحويل التلقائي يطلع من حساب المنصة فورًا بعد موافقتك.',
        actions: [SupHeroButton(label: 'تصدير', icon: Icons.download_rounded, onTap: () {})],
        stats: const [
          AppHeroStat(value: '7', label: 'طلبات تنتظر قرارك'),
          AppHeroStat(value: '28,600 EGP', label: 'بانتظار الاعتماد'),
        ],
        tabs: [supTab('الطلبات', count: 7), supTab('المعلمون'), supTab('الإعدادات')],
        body: ListView(padding: SupPage.bodyPadding(context), children: [
          for (final n in ['أ. ماجد الشهري', 'أ. فهد المطيري', 'أ. خالد العتيبي'])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: SupCard(
                title: n,
                icon: Icons.account_balance_wallet_rounded,
                trailing: const AppStatusBadge(label: 'قيد الانتظار', tone: AppTone.warning),
                child: Text('4,200 EGP', style: AppType.figure(context)),
              ),
            ),
        ]),
      ),
    );

void main() {
  testWidgets('a2 sup frame', (tester) async {
    final storage = await kitGoldenSetUp();
    await kitRender(tester, 'a2_sup_payouts', _payouts, storage: storage, modes: const [false], grow: false);
  });
}
