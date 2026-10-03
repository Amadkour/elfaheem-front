// lib/features/admin/admin_system_page.dart
//  • devices per student + device-switch period (days; default 30)
//  • default card gateway (Moyasar / Paymob) + default platform fee %
//  • the three payment methods (card / bank transfer / InstaPay)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

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
  final _days = TextEditingController();
  final _fee = TextEditingController();
  String? provider;
  bool _filled = false;
  bool busy = false;

  @override
  void dispose() {
    _devices.dispose();
    _days.dispose();
    _fee.dispose();
    super.dispose();
  }

  void _fill(AdminSettingsProvider s) {
    if (_filled || s.values.isEmpty) return;
    _filled = true;
    _devices.text = '${s.maxDevices}';
    _days.text = '${s.switchDays}';
    _fee.text = s.platformFee?.toString() ?? '';
    provider = s.defaultProvider;
  }

  Future<void> _save(AdminSettingsProvider s) async {
    final dev = int.tryParse(_devices.text.trim());
    final days = int.tryParse(_days.text.trim());
    final feeText = _fee.text.trim();
    final fee = feeText.isEmpty ? null : double.tryParse(feeText);
    if (dev == null || dev < 1 || dev > 10) {
      toast(t('عدد الأجهزة من 1 إلى 10', 'Devices must be 1–10'), error: true);
      return;
    }
    if (days == null || days < 1 || days > 365) {
      toast(t('المدة من 1 إلى 365 يوماً', 'Period must be 1–365 days'), error: true);
      return;
    }
    if (feeText.isNotEmpty && (fee == null || fee < 0 || fee > 100)) {
      toast(t('النسبة من 0 إلى 100', 'Fee must be 0–100'), error: true);
      return;
    }
    setState(() => busy = true);
    await s.save({
      'max_devices': dev,
      'device_switch_days': days,
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
      body = ErrorRetry(message: s.error ?? t('تعذر تحميل البيانات', 'Could not load data'), onRetry: s.load);
    } else {
      body = ListView(padding: const EdgeInsets.all(14), children: [
        Section(
          title: t('أجهزة الطالب', 'Student devices'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Field(controller: _devices, label: t('عدد الأجهزة المسموحة لكل طالب', 'Devices allowed per student'), keyboard: TextInputType.number),
            Field(controller: _days, label: t('المدة بين تبديل جهاز وآخر (أيام) — الافتراضي 30', 'Days between device switches — default 30'), keyboard: TextInputType.number),
            Text(
              t('يمكن للطالب طلب تبديل جهاز مرة كل هذه المدة بعد موافقة المعلم.',
                  'A student may request one device switch per period, approved by the teacher.'),
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
            ),
          ]),
        ),
        Section(
          title: t('الدفع', 'Payments'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ChoiceRow<String?>(
              label: t('بوابة البطاقة الافتراضية', 'Default card gateway'),
              options: {null: t('من إعدادات الخادم', 'Server default'), 'moyasar': 'Moyasar', 'paymob': 'Paymob'},
              value: provider,
              onChanged: (v) => setState(() => provider = v),
            ),
            Field(
              controller: _fee,
              label: t('نسبة المنصة الافتراضية % (فارغ = من إعدادات الخادم)', 'Default platform fee % (empty = server default)'),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            Text(
              t('كل كورس يمكنه تجاوز هذه القيم من صفحة الكورس.', 'Each course can override these on its own page.'),
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
            ),
          ]),
        ),
        PrimaryButton(label: t('حفظ الإعدادات', 'Save settings'), busy: busy, onPressed: () => _save(s)),
        const SizedBox(height: 18),
        Text(t('طرق الدفع', 'Payment methods'),
            style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 16, color: c.textDark)),
        const SizedBox(height: 8),
        if (pm.items.isEmpty && pm.isLoading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (pm.items.isEmpty)
          ErrorRetry(message: pm.error ?? t('تعذر التحميل', 'Could not load'), onRetry: pm.load)
        else
          for (final m in pm.items) _MethodCard(m),
      ]);
    }

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(t('الأجهزة والدفع', 'Devices & payments'), style: const TextStyle(fontFamily: 'tajawal'))),
        body: body,
      ),
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
          KeyValue(t('البنك', 'Bank'), asStr(m['bank_name'])),
          KeyValue(t('اسم الحساب', 'Account name'), asStr(m['account_name'])),
          KeyValue('IBAN', asStr(m['iban'])),
        ],
        if (method == 'instapay') KeyValue('InstaPay ID', asStr(m['instapay_id'])),
        if (method == 'card')
          Text(t('الدفع بالبطاقة عبر البوابة المحددة.', 'Card payment through the selected gateway.'),
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textLight)),
        if (method != 'card')
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(t('تعديل البيانات', 'Edit details')),
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
                Field(controller: bank, label: t('اسم البنك', 'Bank name')),
                Field(controller: acc, label: t('اسم الحساب', 'Account name')),
                Field(controller: iban, label: 'IBAN', ltr: true),
                Field(controller: swift, label: 'SWIFT', ltr: true),
              ],
              if (method == 'instapay') Field(controller: insta, label: 'InstaPay ID', ltr: true),
              Field(controller: insAr, label: t('التعليمات بالعربية', 'Instructions (Arabic)'), maxLines: 3),
              Field(controller: insEn, label: t('التعليمات بالإنجليزية', 'Instructions (English)'), maxLines: 3, ltr: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('رقم المرسل مطلوب', 'Require sender phone'), style: const TextStyle(fontFamily: 'tajawal')),
                value: needPhone,
                onChanged: (v) => setS(() => needPhone = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('رقم العملية مطلوب', 'Require transfer reference'), style: const TextStyle(fontFamily: 'tajawal')),
                value: needRef,
                onChanged: (v) => setS(() => needRef = v),
              ),
              PrimaryButton(
                label: t('حفظ', 'Save'),
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
