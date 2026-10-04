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
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.required ? c.primary : c.divider, width: p.required ? 1.5 : 1),
          ),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('الاشتراك إجباري', 'Subscription required'),
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
              subtitle: Text(
                p.required
                    ? t('الطلاب بدون اشتراك فعّال لا يستطيعون استخدام التطبيق.',
                        'Students without an active subscription cannot use the app.')
                    : t('الافتراضي: التطبيق مجاني لكل الطلاب.', 'Default: the app is free for every student.'),
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
              ),
              value: p.required,
              activeTrackColor: c.primary,
              onChanged: !p.settingsLoaded
                  ? null
                  : (v) async {
                      final ok = await confirm(context,
                          message: v
                              ? t('تفعيل الاشتراك الإجباري؟ سيُمنع الطلاب غير المشتركين فوراً.',
                                  'Require subscriptions? Unsubscribed students are blocked immediately.')
                              : t('جعل التطبيق مجانياً للجميع؟', 'Make the app free for everyone?'),
                          danger: v);
                      if (ok) await p.setRequired(v);
                    },
            ),
            const Divider(),
            for (final plan in p.plans) _PlanRow(plan: plan),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      FilterChips<String>(
        value: p.statusFilter ?? 'all',
        options: {
          'pending': t('معلّقة', 'Pending'),
          'active': t('نشطة', 'Active'),
          'expired': t('منتهية', 'Expired'),
          'rejected': t('مرفوضة', 'Rejected'),
          'cancelled': t('ملغاة', 'Cancelled'),
          'all': t('الكل', 'All'),
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
          emptyText: t('لا توجد طلبات اشتراك', 'No subscription requests'),
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
            ? t('مجانية', 'Free')
            : '${money(plan.price, plan.currency)} • ${plan.durationDays} ${t('يوم', 'days')}',
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
                label: t('السعر (فارغ أو 0 = مجاني)', 'Price (empty or 0 = free)'),
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              ChoiceRow<String>(
                label: t('العملة', 'Currency'),
                options: const {'EGP': 'EGP', 'SAR': 'SAR', 'USD': 'USD'},
                value: currency,
                onChanged: (v) => setS(() => currency = v),
              ),
              Field(controller: days, label: t('المدة بالأيام', 'Duration (days)'), keyboard: TextInputType.number),
              PrimaryButton(
                label: t('حفظ', 'Save'),
                busy: busy,
                onPressed: () async {
                  final pr = price.text.trim().isEmpty ? 0.0 : double.tryParse(price.text.trim());
                  final d = int.tryParse(days.text.trim());
                  if (pr == null || pr < 0) {
                    toast(t('سعر غير صحيح', 'Invalid price'), error: true);
                    return;
                  }
                  if (d == null || d < 1) {
                    toast(t('مدة غير صحيحة', 'Invalid duration'), error: true);
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
        KeyValue(t('الخطة', 'Plan'), '${s.planCode} • ${money(s.amount, s.currency)}'),
        KeyValue(t('الطريقة', 'Method'), s.grantedByAdmin ? t('منحة من المدير', 'Admin grant') : (s.paymentMethod ?? '—')),
        if (s.senderName != null) KeyValue(t('المرسل', 'Sender'), '${s.senderName} ${s.senderPhone ?? ''}'),
        if (s.transferReference != null) KeyValue(t('المرجع', 'Reference'), s.transferReference!),
        if (s.endsAt != null) KeyValue(t('ينتهي', 'Ends'), shortDate(s.endsAt)),
        if (s.rejectionReason != null) KeyValue(t('سبب الرفض', 'Reason'), s.rejectionReason!),
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
                    child: Text(t('تعذر تحميل الإيصال', 'Receipt failed to load')),
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
                label: Text(t('قبول', 'Approve'), style: const TextStyle(color: Colors.white, fontFamily: 'tajawal')),
                onPressed: () async {
                  final ok = await confirm(context, message: t('قبول الاشتراك؟', 'Approve this subscription?'));
                  if (ok) await p.approve(s.id);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                icon: const Icon(Icons.close_rounded),
                label: Text(t('رفض', 'Reject')),
                onPressed: () async {
                  final reason = await askText(context,
                      title: t('سبب الرفض', 'Rejection reason'), multiline: true);
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
              label: Text(t('إلغاء الاشتراك', 'Cancel subscription')),
              onPressed: () async {
                final ok = await confirm(context,
                    message: t('إلغاء هذا الاشتراك فوراً؟', 'Cancel this subscription now?'), danger: true);
                if (ok) await p.cancel(s.id);
              },
            ),
          ),
      ]),
    );
  }
}
