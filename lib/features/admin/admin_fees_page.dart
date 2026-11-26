// lib/features/admin/admin_fees_page.dart
//
// ONE place to edit fees (Round C, R6). It used to be two: a Fees tab inside Payment methods (the per-method /
// platform / VAT / teacher-VAT rates) and the Fee policy behind an icon in Payments & payouts. Both editors are
// reused as they were (same calls, same confirms), as the two tabs of this page:
//
//   Rates   → AdminFeeRatesSection   GET /admin/fees · PUT /admin/fees/{method|platform|vat|teacher-vat}
//   Policy  → FeePolicyTab           GET /admin/fees · PUT /admin/fees/policy (read-only unless super admin;
//                                    hidden while the kill switch `admin.fee_policy` is on)
//
// Organization fees and the ledger report (AdminMoneyPage) stay one tap away from the Policy tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_fee_rates.dart';
import 'admin_money_p8.dart';
import 'admin_page.dart';
import 'sup/sup_kit.dart';

class AdminFeesPage extends StatelessWidget {
  const AdminFeesPage({super.key, this.initialTab = 0, this.superAdmin});

  /// 0 Rates · 1 Policy
  final int initialTab;

  /// null = decided from the session (a super admin who is not "viewing as" an admin)
  final bool? superAdmin;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminFeeRatesProvider()..load(),
    child: _View(initialTab: initialTab, superAdmin: superAdmin),
  );
}

class _View extends StatefulWidget {
  const _View({required this.initialTab, this.superAdmin});
  final int initialTab;
  final bool? superAdmin;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  late int _tab = widget.initialTab;
  bool _policyDirty = false;
  final _policyKey = GlobalKey<FeePolicyTabState>();

  /// The super admin can switch the fee policy screen off (the same key the old screen carried).
  bool get _policyOn => !AppConfig.disableList.contains('admin.fee_policy');

  Future<void> _refresh() async {
    final rates = context.read<AdminFeeRatesProvider>();
    final policy = _policyKey.currentState;
    await Future.wait([rates.load(), if (_policyOn && policy != null) policy.reload()]);
  }

  void _setDirty(bool v) {
    if (v == _policyDirty || !mounted) return;
    setState(() => _policyDirty = v);
  }

  @override
  Widget build(BuildContext context) {
    final sup = widget.superAdmin ?? isSuperNow(context);
    final policyOn = _policyOn;
    final tab = policyOn ? _tab.clamp(0, 1) : 0;
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    return SupPage(
      title: t('الرسوم', 'Fees'),
      kicker: 'a2_fees_kicker'.tr,
      headline: 'a2_fees_head'.tr,
      line: 'a2_fees_line'.tr,
      onRefresh: _refresh,
      dirty: _policyDirty,
      tabs: policyOn ? [supTab(t('النسب', 'Rates')), supTab(t('السياسة', 'Policy'))] : null,
      tab: tab,
      onTab: (i) => setState(() => _tab = i),
      body: Column(children: [
        if (policyOn && !sup && tab == 1)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.sm, gutter, 0),
            child: AppBanner(
                icon: Icons.lock_outline_rounded,
                text: t('عرض فقط — تعديل الرسوم للمشرف العام', 'Read-only — only the super admin can change fees')),
          ),
        Expanded(
          // both stay built so an edit in the policy form survives a visit to the other tab
          child: SupTabStack(index: tab, children: [
            const _RatesTab(),
            if (policyOn)
              FeePolicyTab(
                key: _policyKey,
                superAdmin: sup,
                onDirty: _setDirty,
                footer: [
                  AppSpace.gapMd,
                  _MoreLinks(superAdmin: sup),
                ],
              )
            else
              const SizedBox.shrink(),
          ]),
        ),
      ]),
    );
  }
}

class _RatesTab extends StatelessWidget {
  const _RatesTab();

  @override
  Widget build(BuildContext context) => ListView(padding: AdminPage.bodyPadding(context), children: [
    AppBanner(
      icon: Icons.info_outline_rounded,
      text: t(
        'كل رسم يمكن ضبطه كنسبة مئوية، أو مبلغ ثابت، أو الاثنين معاً. لكل رسم قيمة افتراضية يمكنك الرجوع إليها.',
        'Every fee can be set as a percent, a fixed amount, or both. Each one has a default you can reset to.',
      ),
    ),
    AppSpace.gapMd,
    const AdminFeeRatesSection(showPolicyLink: false),
  ]);
}

/// Organization fees and the ledger report still live in [AdminMoneyPage]; two buttons keep them reachable.
class _MoreLinks extends StatelessWidget {
  const _MoreLinks({required this.superAdmin});
  final bool superAdmin;

  void _open(BuildContext context, int tab) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => AdminMoneyPage(initialTab: tab, superAdmin: superAdmin)));

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('المؤسسات ودفتر الأستاذ', 'Organizations & ledger'), style: AppType.section(context)),
      AppSpace.gapXs,
      Text(
        t('رسوم خاصة بكل مؤسسة، وتقرير مالي مفصّل.', 'Per-organization fee overrides, and the detailed financial report.'),
        style: AppType.meta(context),
      ),
      AppSpace.gapSm,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (superAdmin)
          AppButton.secondary(
            label: t('رسوم المؤسسات', 'Organization fees'),
            icon: Icons.apartment_rounded,
            size: AppButtonSize.sm,
            onPressed: () => _open(context, 1),
          ),
        AppButton.secondary(
          label: t('دفتر الأستاذ', 'Ledger report'),
          icon: Icons.menu_book_rounded,
          size: AppButtonSize.sm,
          onPressed: () => _open(context, 2),
        ),
      ]),
    ]),
  );
}
