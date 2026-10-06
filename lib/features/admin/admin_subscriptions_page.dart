// lib/features/admin/admin_subscriptions_page.dart
//  • master switch  (default OFF = the app is free)
//  • monthly / yearly price
//  • subscription requests: approve / reject / cancel
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

class AdminSubscriptionsPage extends StatelessWidget {
  const AdminSubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminSubscriptionsProvider()..loadAll(),
        child: const _View(),
      );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminSubscriptionsProvider>();
    final c = context.colors;

    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        // Material (not Container) paints the card colour, so the ListTiles inside can show ink splashes.
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.required ? c.primary : c.divider, width: p.required ? 1.5 : 1),
          ),
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('admin_subscription_required'.tr,
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
              subtitle: Text(
                p.required
                    ? 'admin_students_without_an_active'.tr
                    : 'admin_default_the_app_is_free_for_every'.tr,
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
              ),
              value: p.required,
              activeTrackColor: c.primary,
              onChanged: !p.settingsLoaded
                  ? null
                  : (v) async {
                      final ok = await confirm(context,
                          message: v
                              ? 'admin_require_subscriptions_unsubscribed'.tr
                              : 'admin_make_the_app_free_for_everyone'.tr,
                          danger: v);
                      if (ok) await p.setRequired(v);
                    },
            ),
            const Divider(),
            for (final plan in p.plans) _PlanRow(plan: plan),
          ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      FilterChips<String>(
        value: p.statusFilter ?? 'all',
        options: {
          'pending': 'admin_pending_4'.tr,
          'active': 'admin_active'.tr,
          'expired': 'admin_expired'.tr,
          'rejected': 'admin_rejected'.tr,
          'cancelled': 'admin_cancelled_2'.tr,
          'all': 'filter_all'.tr,
        },
        onChanged: (v) => p.setStatusFilter(v == 'all' ? null : v),
      ),
      const SizedBox(height: 6),
    ]);

    return BasePage(

      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'subscriptions'.tr),
      child:
      PagedList<AdminSubscriptionsProvider>(
          header: header,
          emptyText: 'admin_no_subscription_requests'.tr,
          itemBuilder: (ctx, row) => _SubTile(SubInfo(row)),
        ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan});
  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminSubscriptionsProvider>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(plan.code == 'yearly' ? Icons.calendar_month_rounded : Icons.calendar_today_rounded, color: c.primary),
      title: Text(plan.name, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
      subtitle: Text(
        plan.price <= 0
            ? 'admin_free'.tr
            : '${money(plan.price, plan.currency)} • ${plan.durationDays} ${'admin_days'.tr}',
        style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textMedium),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Switch(
          value: plan.isActive,
          activeTrackColor: c.primary,
          onChanged: (v) => p.savePlan(plan.code, {'is_active': v}),
        ),
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _editPlan(context, p, plan)),
      ]),
    );
  }
}

Future<void> _editPlan(BuildContext context, AdminSubscriptionsProvider p, Plan plan) {
  final price = TextEditingController(text: plan.price == 0 ? '' : plan.price.toString());
  final days = TextEditingController(text: plan.durationDays.toString());
  String currency = plan.currency;
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(builder: (ctx, setS) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(plan.name),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Field(
                controller: price,
                label: 'admin_price_empty_or_0_free'.tr,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              ChoiceRow<String>(
                label: 'currency_label'.tr,
                options: const {'EGP': 'EGP', 'SAR': 'SAR', 'USD': 'USD'},
                value: currency,
                onChanged: (v) => setS(() => currency = v),
              ),
              Field(controller: days, label: 'admin_duration_days'.tr, keyboard: TextInputType.number),
              PrimaryButton(
                label: 'save'.tr,
                busy: busy,
                onPressed: () async {
                  final pr = price.text.trim().isEmpty ? 0.0 : double.tryParse(price.text.trim());
                  final d = int.tryParse(days.text.trim());
                  if (pr == null || pr < 0) {
                    toast('admin_invalid_price'.tr, error: true);
                    return;
                  }
                  if (d == null || d < 1) {
                    toast('admin_invalid_duration'.tr, error: true);
                    return;
                  }
                  setS(() => busy = true);
                  final ok = await p.savePlan(plan.code, {'price': pr, 'currency': currency, 'duration_days': d});
                  if (ctx.mounted) {
                    setS(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                },
              ),
            ]),
          ),
        ),
      ]);
    });
  }).whenComplete(() {
    price.dispose();
    days.dispose();
  });
}

class _SubTile extends StatelessWidget {
  const _SubTile(this.s);
  final SubInfo s;

  Color _color(BuildContext context) {
    final c = context.colors;
    switch (s.status) {
      case 'active':
        return c.success;
      case 'pending':
        return c.warning;
      case 'expired':
        return c.textLight;
      default:
        return c.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminSubscriptionsProvider>();

    return RowCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(s.studentName,
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
          ),
          StatusChip(s.status, _color(context)),
        ]),
        Text(s.studentGmail,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
        const SizedBox(height: 8),
        KeyValue('admin_plan'.tr, '${s.planCode} • ${money(s.amount, s.currency)}'),
        KeyValue('admin_method'.tr, s.grantedByAdmin ? 'admin_admin_grant'.tr : (s.paymentMethod ?? '—')),
        if (s.senderName != null) KeyValue('admin_sender'.tr, '${s.senderName} ${s.senderPhone ?? ''}'),
        if (s.transferReference != null) KeyValue('admin_reference_2'.tr, s.transferReference!),
        if (s.endsAt != null) KeyValue('admin_ends'.tr, shortDate(s.endsAt)),
        if (s.rejectionReason != null) KeyValue('admin_reason'.tr, s.rejectionReason!),
        if (s.proofImageUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(child: Image.network(s.proofImageUrl!, fit: BoxFit.contain)),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  s.proofImageUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 60,
                    color: c.divider,
                    alignment: Alignment.center,
                    child: Text('admin_receipt_failed_to_load'.tr),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (s.status == 'pending')
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: c.success),
                icon: const Icon(Icons.check_rounded, color: Colors.white),
                label: Text('admin_approve'.tr, style: const TextStyle(color: Colors.white, fontFamily: 'tajawal')),
                onPressed: () async {
                  final ok = await confirm(context, message: 'admin_approve_this_subscription'.tr);
                  if (ok) await p.approve(s.id);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                icon: const Icon(Icons.close_rounded),
                label: Text('request_reject'.tr),
                onPressed: () async {
                  final reason = await askText(context,
                      title: 'rejection_reason_title'.tr, multiline: true);
                  if (reason != null) await p.reject(s.id, reason.isEmpty ? null : reason);
                },
              ),
            ),
          ])
        else if (s.status == 'active')
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: c.danger),
              icon: const Icon(Icons.block_rounded),
              label: Text('admin_cancel_subscription'.tr),
              onPressed: () async {
                final ok = await confirm(context,
                    message: 'admin_cancel_this_subscription_now'.tr, danger: true);
                if (ok) await p.cancel(s.id);
              },
            ),
          ),
      ]),
    );
  }
}
