// lib/features/subscription/subscription_screen.dart
//
// The student paywall. Opened at '/subscription' — automatically by ApiClient
// when the server answers 402 SUBSCRIPTION_REQUIRED, and from the profile page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../utils/widget/app_loading_indicator.dart';
import '../../../utils/widget/primary_button.dart';
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
      toast('sub_choose_plan'.tr, error: true);
      return;
    }
    if (!plan.isFree) {
      if (_sender.text.trim().isEmpty) {
        toast('sub_enter_sender'.tr, error: true);
        return;
      }
      if (_proof == null) {
        toast('sub_attach_receipt_error'.tr, error: true);
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
      toast('sub_activated_toast'.tr);
      _goHome();
    } else {
      toast('sub_request_sent'.tr);
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
      body = const Center(child: AppLoadingIndicator());
    } else if (p.error != null && p.plans.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else if (p.hasAccess && p.required && p.active != null) {
      body = _Status(
        icon: Icons.verified_rounded,
        color: c.success,
        title: 'sub_active_title'.tr,
        subtitle: '${'sub_ends_on'.tr} ${shortDate('${p.active!['ends_at']}')}',
        action: PrimaryButton(label: 'sub_continue'.tr, onPressed: _goHome, isLoading: false,),
      );
    } else if (p.pending != null) {
      body = _Status(
        icon: Icons.hourglass_top_rounded,
        color: c.warning,
        title: 'sub_under_review'.tr,
        subtitle: 'sub_review_subtitle'.tr,
        action: OutlinedButton.icon(
          onPressed: p.load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('sub_refresh_status'.tr),
        ),
      );
    } else if (!p.required) {
      body = _Status(
        icon: Icons.celebration_rounded,
        color: c.success,
        title: 'sub_app_free'.tr,
        subtitle: 'sub_no_subscription_needed'.tr,
        action: PrimaryButton(label: 'sub_continue'.tr, onPressed: _goHome, isLoading: false,),
      );
    } else {
      final transferEnabled = p.transfer['bank_transfer_enabled'] == true || p.transfer['instapay_enabled'] == true;
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Icon(Icons.workspace_premium_rounded, size: 56, color: c.primary),
        const SizedBox(height: 8),
        Text('sub_subscribe_to_continue'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 22, color: c.textDark)),
        if (p.last != null && '${p.last!['status']}' == 'rejected')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${'sub_prev_rejected'.tr}${p.last!['rejection_reason'] != null ? ': ${p.last!['rejection_reason']}' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', color: c.danger, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 16),
        for (final x in p.plans)
          ParentComponent(
            featureKey: 'subscription.plans',
            child: GestureDetector(
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
                      Text('${x.durationDays} ${'sub_days'.tr}',
                          style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
                    ]),
                  ),
                  Text(x.isFree ? 'sub_free'.tr : money(x.price, x.currency),
                      style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 18, color: c.primary)),
                ]),
              ),
            ),
          ),
        if (plan != null && !plan.isFree) ...[
          const SizedBox(height: 6),
          if (!transferEnabled)
            Text('sub_no_payment_methods'.tr,
                style: TextStyle(fontFamily: 'tajawal', color: c.danger))
          else ...[
            ParentComponent(
                featureKey: 'subscription.payment_method',
                child: ChoiceRow<String>(
                  label: 'sub_payment_method'.tr,
                  options: {
                    if (p.transfer['bank_transfer_enabled'] == true) 'bank_transfer': 'sub_bank_transfer'.tr,
                    if (p.transfer['instapay_enabled'] == true) 'instapay': 'InstaPay',
                  },
                  value: method == 'instapay' && p.transfer['instapay_enabled'] != true
                      ? 'bank_transfer'
                      : (method == 'bank_transfer' && p.transfer['bank_transfer_enabled'] != true ? 'instapay' : method),
                  onChanged: (v) => setState(() => method = v),
                )),
            ParentComponent(
                featureKey: 'subscription.transfer_details',
                child: Section(
                  title: 'sub_transfer_to'.tr,
                  child: Column(children: [
                    if (method == 'bank_transfer') ...[
                      KeyValue('sub_bank'.tr, '${p.transfer['bank_name'] ?? ''}'),
                      KeyValue('sub_account'.tr, '${p.transfer['account_name'] ?? ''}'),
                      KeyValue('IBAN', '${p.transfer['iban'] ?? ''}'),
                      if (p.transfer['bank_instructions'] != null) KeyValue('sub_notes'.tr, '${p.transfer['bank_instructions']}'),
                    ] else ...[
                      KeyValue('InstaPay', '${p.transfer['instapay_id'] ?? ''}'),
                      if (p.transfer['instapay_instructions'] != null) KeyValue('sub_notes'.tr, '${p.transfer['instapay_instructions']}'),
                    ],
                    KeyValue('sub_amount'.tr, money(plan.price, plan.currency)),
                  ]),
                )),
            ParentComponent(featureKey: 'subscription.sender_info', child: Field(controller: _sender, label: 'sub_sender_name'.tr)),
            ParentComponent(featureKey: 'subscription.sender_info', child: Field(controller: _phone, label: 'sub_sender_phone'.tr, keyboard: TextInputType.phone, ltr: true)),
            ParentComponent(featureKey: 'subscription.sender_info', child: Field(controller: _ref, label: 'sub_reference'.tr, ltr: true)),
            ParentComponent(
                featureKey: 'subscription.receipt',
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                    if (f != null) setState(() => _proof = f);
                  },
                  icon: Icon(_proof == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
                      color: _proof == null ? null : c.success),
                  label: Text(_proof == null ? 'sub_attach_receipt'.tr : _proof!.name),
                )),
            const SizedBox(height: 14),
          ],
        ],
        PrimaryButton(
          label: plan == null
              ? 'sub_choose_plan'.tr
              : (plan.isFree ? 'sub_activate_free'.tr : 'sub_send_request'.tr),
        isLoading: busy,
          onPressed: plan == null ? null : () => _submit(p),
        ),
        const SizedBox(height: 10),
        ParentComponent(
            featureKey: 'subscription.logout',
            child: TextButton(
              onPressed: () => context.read<ProfileProvider>().logout(context),
              child: Text('sub_logout'.tr, style: TextStyle(color: c.textMedium)),
            )),
      ]);
    }

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text('sub_title'.tr, style: const TextStyle(fontFamily: 'tajawal'))),
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