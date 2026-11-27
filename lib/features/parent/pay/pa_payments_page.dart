// lib/features/parent/pay/pa_payments_page.dart — "Payments and invoices" (Pa2Pay `screen=payments|invoice`, phase 4).
//
// Only what the server has today: GET /api/v1/my-payments, the payments THIS account made (amount, status, method,
// the course, when). There is no parent-scoped payments route (what each child's course cost when the parent paid
// it), no invoice number, VAT breakdown, seller tax number or PDF yet (WP13, not built): the page says so and draws
// nothing it was not sent. The receipt sheet shows the payment as the server returned it.
//   hero    payments and invoices: paid · in review · refunded (counts)
//   list    All / Paid / In review / Refunded (the kit's pill), one row per payment → the receipt sheet
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../pa_kit.dart';

/// One row of GET /my-payments.
class PaPayment {
  const PaPayment({required this.id, required this.amount, required this.status, this.method = '', this.courseId, this.at, this.currency = '', this.transactionId = ''});

  final int id;
  final double amount;
  final String status, method, currency, transactionId;
  final int? courseId;
  final DateTime? at;

  /// paid · review · refunded · other (failed, cancelled …).
  String get group => switch (status.toLowerCase()) {
        'completed' || 'paid' || 'success' || 'succeeded' => 'paid',
        'pending' || 'review' || 'under_review' || 'processing' => 'review',
        'refunded' || 'refund' => 'refunded',
        _ => 'other',
      };

  static PaPayment? tryParse(Object? v) {
    if (v is! Map || v['id'] is! num) return null;
    final meta = v['meta_data'] is Map ? v['meta_data'] as Map : const {};
    final at = DateTime.tryParse('${v['paid_at'] ?? v['created_at'] ?? ''}');
    return PaPayment(
      id: (v['id'] as num).toInt(),
      amount: (v['amount'] as num?)?.toDouble() ?? 0,
      status: '${v['status'] ?? ''}',
      method: '${v['payment_method'] ?? ''}',
      courseId: (v['course_id'] as num?)?.toInt(),
      at: at == null ? null : (at.isUtc ? at : DateTime.utc(at.year, at.month, at.day, at.hour, at.minute, at.second)),
      currency: '${meta['currency'] ?? ''}',
      transactionId: '${v['transaction_id'] ?? ''}',
    );
  }
}

String _money(PaPayment p) => appDigits('${p.amount.toStringAsFixed(p.amount == p.amount.roundToDouble() ? 0 : 2)}${p.currency.isEmpty ? '' : ' ${p.currency}'}');

AppTone _tone(String group) => switch (group) {
      'paid' => AppTone.success,
      'review' => AppTone.warning,
      'refunded' => AppTone.info,
      _ => AppTone.danger,
    };

class ParentPaymentsPage extends StatefulWidget {
  const ParentPaymentsPage({super.key, this.api});

  final ApiClient? api;

  @override
  State<ParentPaymentsPage> createState() => _ParentPaymentsPageState();
}

class _ParentPaymentsPageState extends State<ParentPaymentsPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  List<PaPayment>? _items;
  String? _error;
  int _tab = 0;

  static const _tabs = ['all', 'paid', 'review', 'refunded'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/v1/my-payments', queryParams: {'limit': 100});
      final list = r is Map ? (r['items'] as List? ?? const []) : (r is List ? r : const []);
      if (mounted) setState(() => _items = [for (final x in list) ?PaPayment.tryParse(x)]);
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    int count(String g) => items?.where((p) => p.group == g).length ?? 0;
    final hero = AppHero(
      kicker: 'pa_payments'.tr,
      title: items == null || items.isEmpty ? 'pa_pay_title_empty'.tr : paFmt('pa_pay_title', {'n': appDigits('${count('paid')}')}),
      subtitle: 'pa_pay_sub'.tr,
      stats: [
        AppHeroStat(label: 'pa_pay_paid'.tr, value: items == null ? '—' : appDigits('${count('paid')}')),
        AppHeroStat(label: 'pa_pay_review'.tr, value: items == null ? '—' : appDigits('${count('review')}')),
        AppHeroStat(label: 'pa_pay_refunded'.tr, value: items == null ? '—' : appDigits('${count('refunded')}')),
      ],
    );
    final shown = items == null ? const <PaPayment>[] : (_tab == 0 ? items : items.where((p) => p.group == _tabs[_tab]).toList());
    final Widget list = _error != null && items == null
        ? ErrorRetry(message: _error!, onRetry: _load)
        : items == null
            ? const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
            : shown.isEmpty
                ? AppEmpty(icon: Icons.receipt_long_outlined, title: 'pa_pay_none'.tr, message: 'pa_pay_none_sub'.tr)
                : Column(children: [
                    for (final (i, p) in shown.indexed) ...[
                      if (i > 0) Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: context.colors.kit.line),
                      _PaymentRow(payment: p, onTap: () => showAppSheet<void>(context, (_) => paRole(PaReceiptSheet(payment: p)))),
                    ],
                  ]);
    return BasePage(
      appBar: ScreenAppBar(title: 'pa_payments'.tr),
      child: PaHeroPage(
        onRefresh: _load,
        width: AppWidth.reading,
        hero: hero,
        body: PaStack(children: [
          AppCard(
            title: 'pa_pay_list'.tr,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTabs(
                expand: true,
                items: [for (final t in _tabs) AppTabItem('pa_pay_tab_$t'.tr)],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: AppSpace.sm),
              list,
            ]),
          ),
          PaNote(icon: Icons.info_outline_rounded, text: 'pa_pay_scope_note'.tr),
        ]),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.onTap});

  final PaPayment payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(appDigits('#${p.id}'), textDirection: TextDirection.ltr, style: AppType.tileTitle(context)),
                if (p.at != null) Text(AppTime.date(p.at!), style: AppType.meta(context)),
                if (p.method.isNotEmpty) Text(p.method, style: AppType.meta(context)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_money(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              AppStatusBadge(label: 'pa_pay_status_${p.group}'.tr, tone: _tone(p.group)),
            ])),
          ]),
        ),
      ),
    );
  }
}

/// The receipt of one payment (Pa2Pay `screen=invoice`), as the server sent it: no tax lines it did not send.
class PaReceiptSheet extends StatelessWidget {
  const PaReceiptSheet({super.key, required this.payment});

  final PaPayment payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final c = context.colors;
    Widget box(List<Widget> children) => Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: c.kit.well,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: c.kit.line, width: AppBorder.strong),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(children: [
            Expanded(child: Text(label, style: AppType.meta(context))),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
          ]),
        );
    return AppSheetContent(
      title: 'pa_receipt'.tr,
      icon: Icons.receipt_long_outlined,
      children: [
        box([
          AppStatusBadge(label: 'pa_pay_status_${p.group}'.tr, tone: _tone(p.group)),
          const SizedBox(height: AppSpace.xs),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('pa_receipt_no'.tr, style: AppType.meta(context)),
                Text(appDigits('#${p.id}'), textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
                if (p.at != null) Text(AppTime.dateTime(p.at!), style: AppType.meta(context)),
          ]),
        ]),
        const SizedBox(height: AppSpace.sm),
        box([
          line('pa_receipt_amount'.tr, _money(p)),
          if (p.method.isNotEmpty) line('pa_receipt_method'.tr, p.method),
          if (p.transactionId.isNotEmpty) line('pa_receipt_ref'.tr, p.transactionId),
        ]),
        const SizedBox(height: AppSpace.sm),
        PaNote(icon: Icons.info_outline_rounded, text: 'pa_receipt_note'.tr),
        const SizedBox(height: AppSpace.md),
        AppButton.secondary(label: 'pa_close'.tr, expand: true, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

