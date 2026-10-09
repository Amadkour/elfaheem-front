// lib/features/admin/admin_payments_page.dart  (NEW FILE)
// One premium screen for everything about payments:
//  • hero summary (enabled methods, default gateway)
//  • default card gateway (Moyasar / Paymob) + default platform fee %
//  • payment methods: card / bank transfer / InstaPay
//  • gateway fee (percent + fixed) of every method
// Each method card expands into the FULL configuration (same fields as the old
// admin_payment_methods_screen.dart). Devices live in admin_devices_page.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_fee_rates.dart';
import 'admin_providers.dart';

class AdminPaymentsPage extends StatelessWidget {
  const AdminPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AdminSettingsProvider()..load()),
      ChangeNotifierProvider(create: (_) => AdminPaymentMethodsProvider()..load()),
      ChangeNotifierProvider(create: (_) => AdminFeeRatesProvider()..load()),
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
  final _fee = TextEditingController();
  String? _provider;
  bool _filled = false;
  bool _busy = false;

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  void _fill(AdminSettingsProvider s) {
    if (_filled || s.values.isEmpty) return;
    _filled = true;
    _fee.text = s.platformFee?.toString() ?? '';
    _provider = s.defaultProvider;
  }

  Future<void> _save(AdminSettingsProvider s) async {
    final feeText = _fee.text.trim();
    final fee = feeText.isEmpty ? null : double.tryParse(feeText);
    if (feeText.isNotEmpty && (fee == null || fee < 0 || fee > 100)) {
      toast('admin_fee_must_be_0_100'.tr, error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await s.save({
      'default_payment_provider': _provider,
      'platform_fee_percent': fee,
    });
    if (mounted) setState(() => _busy = false);
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
      final enabledCount = pm.items.where((m) => asBool(m['enabled'])).length;
      body = ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
        _Hero(
          enabled: enabledCount,
          total: pm.items.length,
          gateway: s.defaultProvider == null
              ? 'admin_server_default'.tr
              : (s.defaultProvider == 'moyasar' ? 'Moyasar' : 'Paymob'),
        ),
        const SizedBox(height: 18),
        Section(
          title: 'admin_payments'.tr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ChoiceRow<String?>(
              label: 'admin_default_card_gateway'.tr,
              options: {null: 'admin_server_default'.tr, 'moyasar': 'Moyasar', 'paymob': 'Paymob'},
              value: _provider,
              onChanged: (v) => setState(() => _provider = v),
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
            const SizedBox(height: 12),
            PrimaryButton(
                label: 'admin_save_settings'.tr, isLoading: _busy, onPressed: () => _save(s)),
          ]),
        ),
        const SizedBox(height: 10),
        Text('admin_payment_methods'.tr,
            style: TextStyle(
                fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 16, color: c.textDark)),
        const SizedBox(height: 10),
        if (pm.items.isEmpty && pm.isLoading)
          const Padding(
              padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (pm.items.isEmpty)
          ErrorRetry(message: pm.error ?? 'admin_could_not_load'.tr, onRetry: pm.load)
        else
          for (final m in pm.items) _MethodCard(m),
        const SizedBox(height: 18),
        const AdminFeeRatesSection(),
      ]);
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'admin_payments'.tr),
      child: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.enabled, required this.total, required this.gateway});
  final int enabled;
  final int total;
  final String gateway;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.primary.withValues(alpha: .72)],
        ),
        boxShadow: [
          BoxShadow(
              color: c.primary.withValues(alpha: .28), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('admin_payments'.tr,
                  style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text('admin_payments_hero_hint'.tr,
                  style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: .85))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Chip(icon: Icons.check_circle_rounded, text: '$enabled/$total ${'apm_enabled'.tr}'),
          _Chip(icon: Icons.payments_rounded, text: gateway),
        ]),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: Colors.white),
      const SizedBox(width: 6),
      Text(text,
          style: const TextStyle(
              fontFamily: 'tajawal', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers (Arabic-Indic digits → ASCII so "٥٠٫٥" parses as 50.5)
// ─────────────────────────────────────────────────────────────────────────────

String _digits(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.trim().split('')) {
    final i = arabic.indexOf(ch);
    b.write(i >= 0 ? '$i' : (ch == '٫' ? '.' : ch));
  }
  return b.toString();
}

double? _num(String? s) {
  final t = _digits(s ?? '');
  return t.isEmpty ? null : double.tryParse(t);
}

int? _int(String? s) {
  final t = _digits(s ?? '');
  return t.isEmpty ? null : int.tryParse(t);
}

IconData _methodIcon(String m) => switch (m) {
  'card' => Icons.credit_card_rounded,
  'bank_transfer' => Icons.account_balance_rounded,
  _ => Icons.qr_code_2_rounded,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Method card: header (icon, status, switch) that expands into the full editor
// ─────────────────────────────────────────────────────────────────────────────

class _MethodCard extends StatefulWidget {
  const _MethodCard(this.m);
  final Map<String, dynamic> m;

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminPaymentMethodsProvider>();
    final m = widget.m;
    final method = asStr(m['method']);
    final enabled = asBool(m['enabled']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: enabled ? c.primary.withValues(alpha: .35) : c.divider),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .04), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      // The card's DecoratedBox paints a background; this transparent Material gives the InkWell /
      // SwitchListTiles inside their own ink surface so splashes stay visible (and fixes the
      // "ListTile background color or ink splashes may be invisible" assertion).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_methodIcon(method), color: c.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(asStr(m['label']),
                        style: TextStyle(
                            fontFamily: 'tajawal',
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: c.textDark)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: enabled ? c.success : c.danger),
                      ),
                      const SizedBox(width: 6),
                      Text(enabled ? 'apm_enabled'.tr : 'apm_disabled'.tr,
                          style: TextStyle(
                              fontFamily: 'tajawal',
                              fontSize: 12,
                              color: enabled ? c.success : c.danger)),
                    ]),
                  ]),
                ),
                Switch(
                  value: enabled,
                  activeTrackColor: c.primary,
                  onChanged: (v) {
                    final missing =
                        (method == 'bank_transfer' && asStr(m['iban']).trim().isEmpty) ||
                            (method == 'instapay' && asStr(m['instapay_id']).trim().isEmpty);
                    if (v && missing) {
                      toast('admin_method_details_required'.tr, error: true);
                      setState(() => _open = true);
                      return;
                    }
                    p.save(method, {'enabled': v});
                  },
                ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: c.textLight),
              ]),
            ),
          ),
          if (_open) ...[
            Divider(height: 1, color: c.divider),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _MethodForm(key: ValueKey('form_$method'), method: method, item: m),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full editor
//  All    : name students see (AR + EN), "how to pay" instructions (AR + EN)
//  Bank   : bank name, account holder, IBAN, SWIFT
//  InstaPay: InstaPay address
//  Manual : require sender phone / transfer reference, min + max amount,
//           time to send the proof (0 = no timer)
// ─────────────────────────────────────────────────────────────────────────────

class _MethodForm extends StatefulWidget {
  const _MethodForm({super.key, required this.method, required this.item});
  final String method;
  final Map<String, dynamic> item;

  @override
  State<_MethodForm> createState() => _MethodFormState();
}

class _MethodFormState extends State<_MethodForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelAr, _labelEn, _insAr, _insEn;
  late final TextEditingController _bankName, _accountName, _iban, _swift, _instapayId;
  late final TextEditingController _min, _max, _window;
  late bool _reqPhone, _reqRef;
  bool _busy = false;

  bool get _isBank => widget.method == 'bank_transfer';
  bool get _isInstapay => widget.method == 'instapay';
  bool get _isManual => _isBank || _isInstapay;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    final r = asMap(i['requirements']);
    String s(Object? v) => v == null ? '' : '$v';
    String n(Object? v) =>
        v is num ? (v == v.roundToDouble() ? v.toInt().toString() : v.toString()) : s(v);

    _labelAr = TextEditingController(text: s(i['label']));
    _labelEn = TextEditingController(text: s(i['label_en']));
    _insAr = TextEditingController(text: s(i['instructions_ar']));
    _insEn = TextEditingController(text: s(i['instructions_en']));
    _bankName = TextEditingController(text: s(i['bank_name']));
    _accountName = TextEditingController(text: s(i['account_name']));
    _iban = TextEditingController(text: s(i['iban']));
    _swift = TextEditingController(text: s(i['swift_code']));
    _instapayId = TextEditingController(text: s(i['instapay_id']));
    _min = TextEditingController(text: n(r['min_amount']));
    _max = TextEditingController(text: n(r['max_amount']));
    _window = TextEditingController(text: n(r['transfer_window_minutes']));
    _reqPhone = r['require_sender_phone'] == true;
    _reqRef = r['require_transfer_reference'] == true;
  }

  @override
  void dispose() {
    for (final x in [
      _labelAr, _labelEn, _insAr, _insEn, _bankName, _accountName,
      _iban, _swift, _instapayId, _min, _max, _window,
    ]) {
      x.dispose();
    }
    super.dispose();
  }

  // ── validation ──────────────────────────────────────────────────────────

  String? _optionalAmount(String? v) {
    if (_digits(v ?? '').isEmpty) return null;
    final x = _num(v);
    return (x == null || x < 0) ? 'apm_invalid_number'.tr : null;
  }

  String? _maxAmount(String? v) {
    final bad = _optionalAmount(v);
    if (bad != null) return bad;
    final mx = _num(v), mn = _num(_min.text);
    return (mx != null && mn != null && mn > mx) ? 'apm_min_gt_max'.tr : null;
  }

  String? _windowMinutes(String? v) {
    if (_digits(v ?? '').isEmpty) return null; // empty = server default
    final x = _int(v);
    return (x == null || x < 0 || x > 1440) ? 'apm_window_invalid'.tr : null;
  }

  // ── save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final body = <String, dynamic>{
      'label_ar': _labelAr.text.trim(),
      'label_en': _labelEn.text.trim(),
      'instructions_ar': _insAr.text.trim(),
      'instructions_en': _insEn.text.trim(),
    };
    if (_isBank) {
      body.addAll({
        'bank_name': _bankName.text.trim(),
        'account_name': _accountName.text.trim(),
        'iban': _iban.text.trim(),
        'swift_code': _swift.text.trim(),
      });
    }
    if (_isInstapay) body['instapay_id'] = _instapayId.text.trim();
    if (_isManual) {
      body['requirements'] = {
        'require_sender_phone': _reqPhone,
        'require_transfer_reference': _reqRef,
        'min_amount': _num(_min.text), // null = no limit
        'max_amount': _num(_max.text),
        'transfer_window_minutes': _int(_window.text), // null = default, 0 = no timer
      };
    }
    setState(() => _busy = true);
    await context.read<AdminPaymentMethodsProvider>().save(widget.method, body);
    if (mounted) setState(() => _busy = false);
  }

  // ── builders ────────────────────────────────────────────────────────────

  Widget _heading(String key) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 12),
    child: Text(key.tr,
        style: TextStyle(
            fontFamily: 'tajawal',
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: context.colors.textDark)),
  );

  Widget _field(
      TextEditingController ctrl,
      String labelKey, {
        int maxLines = 1,
        TextInputType? keyboard,
        String? Function(String?)? validator,
        String? helperKey,
        bool ltr = false,
      }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 3 : 1,
          keyboardType: keyboard,
          validator: validator,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(
            labelText: labelKey.tr,
            helperText: helperKey?.tr,
            helperMaxLines: 2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const number = TextInputType.numberWithOptions(decimal: true);

    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('apm_section_display'),
        _field(_labelAr, 'apm_label_ar'),
        _field(_labelEn, 'apm_label_en', ltr: true),
        _field(_insAr, 'apm_instructions_ar', maxLines: 5),
        _field(_insEn, 'apm_instructions_en', maxLines: 5, ltr: true),
        if (_isBank) ...[
          _heading('apm_section_receiving'),
          _field(_bankName, 'apm_bank_name'),
          _field(_accountName, 'apm_account_name'),
          _field(_iban, 'apm_iban', ltr: true),
          _field(_swift, 'apm_swift', ltr: true),
        ],
        if (_isInstapay) ...[
          _heading('apm_section_receiving'),
          _field(_instapayId, 'apm_instapay_id', ltr: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('apm_instapay_egp_note'.tr,
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
          ),
        ],
        if (_isManual) ...[
          _heading('apm_section_requirements'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _reqPhone,
            activeTrackColor: c.primary,
            onChanged: (v) => setState(() => _reqPhone = v),
            title: Text('apm_require_phone'.tr, style: const TextStyle(fontFamily: 'tajawal')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _reqRef,
            activeTrackColor: c.primary,
            onChanged: (v) => setState(() => _reqRef = v),
            title: Text('apm_require_reference'.tr, style: const TextStyle(fontFamily: 'tajawal')),
          ),
          const SizedBox(height: 8),
          _field(_min, 'apm_min_amount',
              keyboard: number, validator: _optionalAmount, helperKey: 'apm_amount_hint'),
          _field(_max, 'apm_max_amount',
              keyboard: number, validator: _maxAmount, helperKey: 'apm_amount_hint'),
          _field(_window, 'apm_window',
              keyboard: TextInputType.number,
              validator: _windowMinutes,
              helperKey: 'apm_window_hint'),
        ],
        const SizedBox(height: 4),
        PrimaryButton(label: 'apm_save'.tr, isLoading: _busy, onPressed: _save),
      ]),
    );
  }
}