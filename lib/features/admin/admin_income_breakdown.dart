// lib/features/admin/admin_income_breakdown.dart  (NEW FILE)
//
// "Show the break pricing": opened by tapping any income card on the overview.
//   GET /api/v1/admin/overview/income-breakdown
// Money is shown PER CURRENCY (EGP / SAR / USD are never added together):
//   course income (after discounts)  +  platform fee  +  VAT  +  payment fee  =  what the students paid
// then split by plan, by payment method, and by course.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import 'admin_common.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/core/display/app_fonts.dart';

Future<void> showIncomeBreakdown(BuildContext context) =>
    showAdminSheet(context, (_) => const _BreakdownSheet());

class _BreakdownSheet extends StatefulWidget {
  const _BreakdownSheet();

  @override
  State<_BreakdownSheet> createState() => _BreakdownSheetState();
}

class _BreakdownSheetState extends State<_BreakdownSheet> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await ApiClient().get('/api/v1/admin/overview/income-breakdown');
      data = r is Map ? Map<String, dynamic>.from(r) : null;
      if (data == null) error = 'admin_could_not_load_data'.tr;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  static String _planLabel(String plan) => switch (plan) {
    'monthly' => 'plan_monthly'.tr,
    'six_months' => 'plan_six_months'.tr,
    'yearly' => 'plan_yearly'.tr,
    _ => 'admin_inc_before_plans'.tr,
  };

  static String _methodLabel(String m) => switch (m) {
    'instapay' => 'transfer_instapay_title'.tr,
    'bank_transfer' => 'transfer_bank_title'.tr,
    _ => m,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return const SizedBox(height: 260, child: AppListSkeleton(items: 3, withAvatar: false));
    }
    if (data == null) {
      return SizedBox(height: 260, child: ErrorRetry(message: error ?? 'admin_could_not_load_data'.tr, onRetry: _load));
    }

    final currencies = asMapList(data!['currencies']);
    final byPlan = asMapList(data!['by_plan']);
    final byMethod = asMapList(data!['by_method']);
    final top = asMapList(data!['top_courses']);
    final subs = asMapList(data!['subscriptions']);

    Widget hint(String text) =>
        Text(text, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textLight));

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('admin_inc_title'.tr),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            hint('admin_inc_hint'.tr),
            const SizedBox(height: 8),
            if (currencies.isEmpty) EmptyState('admin_inc_empty'.tr),
            for (final r in currencies)
              Section(
                title: asStr(r['currency']),
                child: Column(children: [
                  KeyValue('admin_inc_payments'.tr, '${asInt(r['count'])}'),
                  KeyValue('admin_course_income_after_discounts'.tr, money(asDouble(r['course_income']), asStr(r['currency']))),
                  KeyValue('admin_inc_platform_fee'.tr, money(asDouble(r['platform_fee']), asStr(r['currency']))),
                  KeyValue('admin_inc_vat'.tr, money(asDouble(r['vat']), asStr(r['currency']))),
                  KeyValue('admin_inc_gateway_fee'.tr, money(asDouble(r['gateway_fee']), asStr(r['currency']))),
                  if (asDouble(r['other_fees']) > 0)
                    KeyValue('admin_inc_other_fees'.tr, money(asDouble(r['other_fees']), asStr(r['currency']))),
                  const Divider(),
                  KeyValue('admin_collected_incl_fees'.tr, money(asDouble(r['collected']), asStr(r['currency']))),
                  KeyValue('admin_refunded'.tr, money(asDouble(r['refunded']), asStr(r['currency']))),
                  KeyValue('admin_inc_teacher_net'.tr, money(asDouble(r['teacher_net']), asStr(r['currency']))),
                ]),
              ),
            if (byPlan.isNotEmpty)
              Section(
                title: 'admin_inc_by_plan'.tr,
                child: Column(children: [
                  for (final r in byPlan)
                    KeyValue(
                      '${_planLabel(asStr(r['plan']))} • ${asStr(r['currency'])} (${asInt(r['count'])})',
                      '${money(asDouble(r['course_income']), asStr(r['currency']))} → ${money(asDouble(r['collected']), asStr(r['currency']))}',
                    ),
                ]),
              ),
            if (byMethod.isNotEmpty)
              Section(
                title: 'admin_inc_by_method'.tr,
                child: Column(children: [
                  for (final r in byMethod)
                    KeyValue(
                      '${_methodLabel(asStr(r['method']))} • ${asStr(r['currency'])} (${asInt(r['count'])})',
                      '${money(asDouble(r['collected']), asStr(r['currency']))}  (${'admin_inc_gateway_fee'.tr} ${money(asDouble(r['gateway_fee']), asStr(r['currency']))})',
                    ),
                ]),
              ),
            if (top.isNotEmpty)
              Section(
                title: 'admin_inc_top_courses'.tr,
                child: Column(children: [
                  for (final r in top)
                    KeyValue(
                      asStr(r['name']),
                      '${money(asDouble(r['collected']), asStr(r['currency']))} (${asInt(r['count'])})',
                    ),
                ]),
              ),
            if (subs.isNotEmpty)
              Section(
                title: 'admin_subscription_income'.tr,
                child: Column(children: [
                  for (final r in subs)
                    KeyValue(
                      '${asStr(r['plan'], '—')} (${asInt(r['count'])})',
                      money(asDouble(r['amount']), asStr(r['currency'])),
                    ),
                ]),
              ),
          ],
        ),
      ),
    ]);
  }
}