// lib/features/admin/admin_system_page.dart
//  • devices per student + device-switch period (days; default 30)
//  • default card gateway (Moyasar / Paymob) + default platform fee %
//  • the three payment methods (card / bank transfer / InstaPay)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_providers.dart';

class AdminSystemPage extends StatelessWidget {
  const AdminSystemPage({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AdminSettingsProvider()..load()),
          ChangeNotifierProvider(create: (_) => AdminPaymentMethodsProvider()..load()),
        ],
        child: const _View(),
      );
}

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _devices = TextEditingController();
  final _videos = TextEditingController();
  final _days = TextEditingController();
  final _fee = TextEditingController();
  String? provider;
  bool _filled = false;
  bool busy = false;

  @override
  void dispose() {
    _devices.dispose();
    _videos.dispose();
    _days.dispose();
    _fee.dispose();
    super.dispose();
  }

  void _fill(AdminSettingsProvider s) {
    if (_filled || s.values.isEmpty) return;
    _filled = true;
    _devices.text = '${s.maxDevices}';
    _videos.text = '${s.maxVideos}';
    _days.text = '${s.switchDays}';
    _fee.text = s.platformFee?.toString() ?? '';
    provider = s.defaultProvider;
  }

  Future<void> _save(AdminSettingsProvider s) async {
    final dev = int.tryParse(_devices.text.trim());
    final videos = int.tryParse(_videos.text.trim());
    final days = int.tryParse(_days.text.trim());
    final feeText = _fee.text.trim();
    final fee = feeText.isEmpty ? null : double.tryParse(feeText);
    if (dev == null || dev < 1 || dev > 10) {
      toast('admin_devices_must_be_1_10'.tr, error: true);
      return;
    }
    if (videos == null || videos < 1 || videos > 1000) {
      toast('admin_videos_must_be_1_1000'.tr, error: true);
      return;
    }
    if (days == null || days < 1 || days > 365) {
      toast('admin_period_must_be_1_365_days'.tr, error: true);
      return;
    }
    if (feeText.isNotEmpty && (fee == null || fee < 0 || fee > 100)) {
      toast('admin_fee_must_be_0_100'.tr, error: true);
      return;
    }
    setState(() => busy = true);
    await s.save({
      'max_devices': dev,
      'device_switch_days': days,
      'max_monthly_view': videos,
      'default_payment_provider': provider,
      'platform_fee_percent': fee,
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AdminSettingsProvider>();
    final pm = context.watch<AdminPaymentMethodsProvider>();
    final c = context.colors;
    _fill(s);

    Widget body;
    if (s.values.isEmpty && s.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.values.isEmpty) {
      body = ErrorRetry(message: s.error ?? 'admin_could_not_load_data'.tr, onRetry: s.load);
    } else {
      body = ListView(padding: const EdgeInsets.all(14), children: [
        Section(
          title: 'admin_student_devices'.tr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Field(controller: _devices, label: 'admin_devices_allowed_per_student'.tr, keyboard: TextInputType.number),
            Field(controller: _days, label: 'admin_days_between_device_switches_default'.tr, keyboard: TextInputType.number),
            Field(controller: _videos, label: 'max_monthly_view'.tr, keyboard: TextInputType.number),
            Text(
              'admin_a_student_may_request_one_device'.tr,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
            ),
          ]),
        ),
        Section(
          title: 'admin_payments'.tr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ChoiceRow<String?>(
              label: 'admin_default_card_gateway'.tr,
              options: {null: 'admin_server_default'.tr, 'moyasar': 'Moyasar', 'paymob': 'Paymob'},
              value: provider,
              onChanged: (v) => setState(() => provider = v),
            ),
            Field(
              controller: _fee,
              label: 'admin_default_platform_fee_empty_server'.tr,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            Text(
              'admin_each_course_can_override_these_on_its'.tr,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
            ),
          ]),
        ),
        PrimaryButton(label: 'admin_save_settings'.tr, busy: busy, onPressed: () => _save(s)),
        const SizedBox(height: 18),
        Text('admin_payment_methods'.tr,
            style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 16, color: c.textDark)),
        const SizedBox(height: 8),
        if (pm.items.isEmpty && pm.isLoading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (pm.items.isEmpty)
          ErrorRetry(message: pm.error ?? 'admin_could_not_load'.tr, onRetry: pm.load)
        else
          for (final m in pm.items) _MethodCard(m),
      ]);
    }

    return BasePage(

      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'devices_and_payments'.tr),
      child: body,

    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard(this.m);
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminPaymentMethodsProvider>();
    final method = asStr(m['method']);
    final enabled = asBool(m['enabled']);

    return Section(
      title: asStr(m['label']),
      trailing: Switch(
        value: enabled,
        activeTrackColor: c.primary,
        onChanged: (v) => p.save(method, {'enabled': v}),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (method == 'bank_transfer') ...[
          KeyValue('bank_name_row_label'.tr, asStr(m['bank_name'])),
          KeyValue('admin_account_name'.tr, asStr(m['account_name'])),
          KeyValue('IBAN', asStr(m['iban'])),
        ],
        if (method == 'instapay') KeyValue('InstaPay ID', asStr(m['instapay_id'])),
        if (method == 'card')
          Text('admin_card_payment_through_the_selected'.tr,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textLight)),
        if (method != 'card')
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text('admin_edit_details'.tr),
              onPressed: () => _edit(context, p, m),
            ),
          ),
      ]),
    );
  }
}

Future<void> _edit(BuildContext context, AdminPaymentMethodsProvider p, Map<String, dynamic> m) {
  final method = asStr(m['method']);
  final bank = TextEditingController(text: asStr(m['bank_name']));
  final acc = TextEditingController(text: asStr(m['account_name']));
  final iban = TextEditingController(text: asStr(m['iban']));
  final swift = TextEditingController(text: asStr(m['swift_code']));
  final insta = TextEditingController(text: asStr(m['instapay_id']));
  final insAr = TextEditingController(text: asStr(m['instructions_ar']));
  final insEn = TextEditingController(text: asStr(m['instructions_en']));
  final req = asMap(m['requirements']);
  bool needPhone = asBool(req['require_sender_phone']);
  bool needRef = asBool(req['require_transfer_reference']);
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(builder: (ctx, setS) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(asStr(m['label'])),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(children: [
              if (method == 'bank_transfer') ...[
                Field(controller: bank, label: 'admin_bank_name'.tr),
                Field(controller: acc, label: 'admin_account_name'.tr),
                Field(controller: iban, label: 'IBAN', ltr: true),
                Field(controller: swift, label: 'SWIFT', ltr: true),
              ],
              if (method == 'instapay') Field(controller: insta, label: 'InstaPay ID', ltr: true),
              Field(controller: insAr, label: 'admin_instructions_arabic'.tr, maxLines: 3),
              Field(controller: insEn, label: 'admin_instructions_english'.tr, maxLines: 3, ltr: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('admin_require_sender_phone'.tr, style: const TextStyle(fontFamily: 'tajawal')),
                value: needPhone,
                onChanged: (v) => setS(() => needPhone = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('admin_require_transfer_reference'.tr, style: const TextStyle(fontFamily: 'tajawal')),
                value: needRef,
                onChanged: (v) => setS(() => needRef = v),
              ),
              PrimaryButton(
                label: 'save'.tr,
                busy: busy,
                onPressed: () async {
                  setS(() => busy = true);
                  final ok = await p.save(method, {
                    if (method == 'bank_transfer') ...{
                      'bank_name': bank.text.trim(),
                      'account_name': acc.text.trim(),
                      'iban': iban.text.trim(),
                      'swift_code': swift.text.trim(),
                    },
                    if (method == 'instapay') 'instapay_id': insta.text.trim(),
                    'instructions_ar': insAr.text.trim(),
                    'instructions_en': insEn.text.trim(),
                    'requirements': {'require_sender_phone': needPhone, 'require_transfer_reference': needRef},
                  });
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
    for (final x in [bank, acc, iban, swift, insta, insAr, insEn]) {
      x.dispose();
    }
  });
}
