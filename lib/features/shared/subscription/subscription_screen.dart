// lib/features/subscription/subscription_screen.dart
//
// The student paywall. Opened at '/subscription' — automatically by ApiClient
// when the server answers 402 SUBSCRIPTION_REQUIRED, and from the profile page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'subscription_provider.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => SubscriptionProvider()..load(),
        child: const _View(),
      );
}

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  String? planCode;
  String method = 'bank_transfer';
  final _sender = TextEditingController();
  final _phone = TextEditingController();
  final _ref = TextEditingController();
  XFile? _proof;
  bool busy = false;

  @override
  void dispose() {
    _sender.dispose();
    _phone.dispose();
    _ref.dispose();
    super.dispose();
  }

  SubPlan? _plan(SubscriptionProvider p) {
    for (final x in p.plans) {
      if (x.code == planCode) return x;
    }
    return null;
  }

  void _goHome() => Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);

  Future<void> _submit(SubscriptionProvider p) async {
    final plan = _plan(p);
    if (plan == null) {
      toast(t('اختر خطة', 'Choose a plan'), error: true);
      return;
    }
    if (!plan.isFree) {
      if (_sender.text.trim().isEmpty) {
        toast(t('أدخل اسم المرسل', 'Enter the sender name'), error: true);
        return;
      }
      if (_proof == null) {
        toast(t('أرفق صورة الإيصال', 'Attach the receipt image'), error: true);
        return;
      }
    }
    setState(() => busy = true);
    final bytes = _proof == null ? null : await _proof!.readAsBytes();
    final err = await p.subscribe(
      planCode: plan.code,
      method: plan.isFree ? null : method,
      senderName: _sender.text.trim().isEmpty ? null : _sender.text.trim(),
      senderPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      proofBytes: bytes,
      proofName: _proof?.name,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      toast(err, error: true);
    } else if (p.hasAccess) {
      toast(t('تم تفعيل اشتراكك', 'Your subscription is active'));
      _goHome();
    } else {
      toast(t('تم إرسال طلبك للمراجعة', 'Request sent for review'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionProvider>();
    final c = context.colors;
    final plan = _plan(p);
    final isAr = AppConfig.lang == 'ar';

    Widget body;
    if (!p.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.error != null && p.plans.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else if (p.hasAccess && p.required && p.active != null) {
      body = _Status(
        icon: Icons.verified_rounded,
        color: c.success,
        title: t('اشتراكك فعّال', 'Your subscription is active'),
        subtitle: '${t('ينتهي في', 'Ends on')} ${shortDate('${p.active!['ends_at']}')}',
        action: PrimaryButton(label: t('متابعة', 'Continue'), onPressed: _goHome),
      );
    } else if (p.pending != null) {
      body = _Status(
        icon: Icons.hourglass_top_rounded,
        color: c.warning,
        title: t('طلبك قيد المراجعة', 'Your request is under review'),
        subtitle: t('سيتم تفعيل الاشتراك بعد موافقة الإدارة.', 'It will be activated once an admin approves it.'),
        action: OutlinedButton.icon(
          onPressed: p.load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(t('تحديث الحالة', 'Refresh status')),
        ),
      );
    } else if (!p.required) {
      body = _Status(
        icon: Icons.celebration_rounded,
        color: c.success,
        title: t('التطبيق مجاني حالياً', 'The app is currently free'),
        subtitle: t('لا حاجة لاشتراك.', 'No subscription needed.'),
        action: PrimaryButton(label: t('متابعة', 'Continue'), onPressed: _goHome),
      );
    } else {
      final transferEnabled = p.transfer['bank_transfer_enabled'] == true || p.transfer['instapay_enabled'] == true;
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Icon(Icons.workspace_premium_rounded, size: 56, color: c.primary),
        const SizedBox(height: 8),
        Text(t('اشترك للمتابعة', 'Subscribe to continue'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 22, color: c.textDark)),
        if (p.last != null && '${p.last!['status']}' == 'rejected')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${t('تم رفض طلبك السابق', 'Your previous request was rejected')}${p.last!['rejection_reason'] != null ? ': ${p.last!['rejection_reason']}' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', color: c.danger, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 16),
        for (final x in p.plans)
          GestureDetector(
            onTap: () {
              setState(() => planCode = x.code);
              p.loadTransferDetails(x.code);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: x.code == planCode ? c.primary : c.divider, width: x.code == planCode ? 2 : 1),
              ),
              child: Row(children: [
                Icon(x.code == planCode ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: c.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isAr ? x.nameAr : x.nameEn,
                        style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 16, color: c.textDark)),
                    Text('${x.durationDays} ${t('يوم', 'days')}',
                        style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
                  ]),
                ),
                Text(x.isFree ? t('مجاني', 'Free') : money(x.price, x.currency),
                    style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 18, color: c.primary)),
              ]),
            ),
          ),
        if (plan != null && !plan.isFree) ...[
          const SizedBox(height: 6),
          if (!transferEnabled)
            Text(t('طرق الدفع غير متاحة حالياً. تواصل مع الإدارة.', 'No payment method is available right now. Contact support.'),
                style: TextStyle(fontFamily: 'tajawal', color: c.danger))
          else ...[
            ChoiceRow<String>(
              label: t('طريقة الدفع', 'Payment method'),
              options: {
                if (p.transfer['bank_transfer_enabled'] == true) 'bank_transfer': t('تحويل بنكي', 'Bank transfer'),
                if (p.transfer['instapay_enabled'] == true) 'instapay': 'InstaPay',
              },
              value: method == 'instapay' && p.transfer['instapay_enabled'] != true
                  ? 'bank_transfer'
                  : (method == 'bank_transfer' && p.transfer['bank_transfer_enabled'] != true ? 'instapay' : method),
              onChanged: (v) => setState(() => method = v),
            ),
            Section(
              title: t('حوّل المبلغ إلى', 'Transfer the amount to'),
              child: Column(children: [
                if (method == 'bank_transfer') ...[
                  KeyValue(t('البنك', 'Bank'), '${p.transfer['bank_name'] ?? ''}'),
                  KeyValue(t('اسم الحساب', 'Account'), '${p.transfer['account_name'] ?? ''}'),
                  KeyValue('IBAN', '${p.transfer['iban'] ?? ''}'),
                  if (p.transfer['bank_instructions'] != null) KeyValue(t('تعليمات', 'Notes'), '${p.transfer['bank_instructions']}'),
                ] else ...[
                  KeyValue('InstaPay', '${p.transfer['instapay_id'] ?? ''}'),
                  if (p.transfer['instapay_instructions'] != null) KeyValue(t('تعليمات', 'Notes'), '${p.transfer['instapay_instructions']}'),
                ],
                KeyValue(t('المبلغ', 'Amount'), money(plan.price, plan.currency)),
              ]),
            ),
            Field(controller: _sender, label: t('اسم المرسل', 'Sender name')),
            Field(controller: _phone, label: t('رقم المرسل (اختياري)', 'Sender phone (optional)'), keyboard: TextInputType.phone, ltr: true),
            Field(controller: _ref, label: t('رقم العملية (اختياري)', 'Transfer reference (optional)'), ltr: true),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (f != null) setState(() => _proof = f);
              },
              icon: Icon(_proof == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
                  color: _proof == null ? null : c.success),
              label: Text(_proof == null ? t('إرفاق صورة الإيصال', 'Attach receipt image') : _proof!.name),
            ),
            const SizedBox(height: 14),
          ],
        ],
        PrimaryButton(
          label: plan == null
              ? t('اختر خطة', 'Choose a plan')
              : (plan.isFree ? t('تفعيل مجاناً', 'Activate for free') : t('إرسال الطلب', 'Send request')),
          busy: busy,
          onPressed: plan == null ? null : () => _submit(p),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => context.read<ProfileProvider>().logout(context),
          child: Text(t('تسجيل الخروج', 'Log out'), style: TextStyle(color: c.textMedium)),
        ),
      ]);
    }

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(t('الاشتراك', 'Subscription'), style: const TextStyle(fontFamily: 'tajawal'))),
        body: body,
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.color, required this.title, required this.subtitle, required this.action});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 20, color: c.textDark)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          const SizedBox(height: 22),
          action,
        ]),
      ),
    );
  }
}
