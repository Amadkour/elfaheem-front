// lib/features/admin/admin_payments_page.dart
// One premium screen for everything about payments, split into two clear tabs:
//
//  Hero (always visible): active methods · default gateway · platform fee
//
//  Tab 1 · Methods  → default card gateway (tap to switch, saves instantly)
//                   → card / bank transfer / InstaPay, each expands into its full editor
//  Tab 2 · Fees     → platform fee, student VAT, teacher VAT and the gateway fee of every
//                     method (AdminFeeRatesSection — percent, fixed amount, or both)
//
// The platform fee % is edited ONLY in the Fees tab (one place = no stale overwrites).
// Devices live in admin_devices_page.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_fee_rates.dart';
import 'admin_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Small helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Inline AR / EN text for strings that have no translation key yet.
String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Arabic-Indic digits → ASCII so "٥٠٫٥" parses as 50.5.
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

/// 10.0 → "10", 1.9 → "1.9"
String _pct(Object? v) {
  final d = (v as num?)?.toDouble();
  if (d == null) return '—';
  return d.truncateToDouble() == d ? d.toStringAsFixed(0) : d.toString();
}

IconData _methodIcon(String m) => switch (m) {
  'card' => Icons.credit_card_rounded,
  'bank_transfer' => Icons.account_balance_rounded,
  'apple_pay' => Icons.apple,
  'google_pay' => Icons.account_balance_wallet_rounded,
  _ => Icons.qr_code_2_rounded,
};

BoxDecoration _cardDecoration(BuildContext context, {Color? border}) {
  final c = context.colors;
  return BoxDecoration(
    color: c.cardBg,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: border ?? c.divider),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: .045), blurRadius: 16, offset: const Offset(0, 6)),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Page
// ─────────────────────────────────────────────────────────────────────────────

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
  int _tab = 0;

  // Gateway choice saves the moment it is tapped; this shows the new value while the request runs.
  bool _gwBusy = false;
  bool _hasPending = false;
  String? _pending;

  Future<void> _pickGateway(AdminSettingsProvider s, String? value) async {
    if (_gwBusy || value == s.defaultProvider) return;
    setState(() {
      _pending = value;
      _hasPending = true;
      _gwBusy = true;
    });
    await s.save({'default_payment_provider': value});
    if (mounted) {
      setState(() {
        _hasPending = false;
        _gwBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AdminSettingsProvider>();
    final pm = context.watch<AdminPaymentMethodsProvider>();
    final fr = context.watch<AdminFeeRatesProvider>();

    Widget body;
    if (s.values.isEmpty && s.isLoading) {
      body = const Center(child: AppLoadingIndicator());
    } else if (s.values.isEmpty) {
      body = ErrorRetry(message: s.error ?? 'admin_could_not_load_data'.tr, onRetry: s.load);
    } else {
      final gateway = _hasPending ? _pending : s.defaultProvider;
      final enabledCount = pm.items.where((m) => asBool(m['enabled'])).length;
      final platformPct = fr.platform.isNotEmpty ? fr.platform['percent'] : s.platformFee;

      body = ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 32), children: [
        _Hero(
          stats: [
            _Stat(Icons.check_circle_rounded, 'apm_enabled'.tr, '$enabledCount/${pm.items.length}'),
            _Stat(Icons.payments_rounded, _t('البوابة', 'Gateway'), _gatewayName(gateway)),
            _Stat(Icons.percent_rounded, _t('رسوم المنصة', 'Platform fee'),
                platformPct == null ? 'admin_server_default'.tr : '${_pct(platformPct)}%'),
          ],
        ),
        const SizedBox(height: 16),
        _Segments(
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
          items: [
            (Icons.credit_card_rounded, 'admin_payment_methods'.tr),
            (Icons.receipt_long_rounded, 'admin_fee_rates'.tr),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: _tab == 0
                ? _MethodsTab(gateway: gateway, busy: _gwBusy, onPick: (v) => _pickGateway(s, v))
                : const _FeesTab(),
          ),
        ),
      ]);
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'admin_payments'.tr),
      child: body,
    );
  }

  String _gatewayName(String? g) =>
      g == null ? 'admin_server_default'.tr : (g == 'moyasar' ? 'Moyasar' : 'Paymob');
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero + segmented tabs
// ─────────────────────────────────────────────────────────────────────────────

class _Stat {
  const _Stat(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _Hero extends StatelessWidget {
  const _Hero({required this.stats});
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.primary.withValues(alpha: .7)],
        ),
        boxShadow: [
          BoxShadow(color: c.primary.withValues(alpha: .3), blurRadius: 26, offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(children: [
        // soft decorative circles
        PositionedDirectional(
          top: -40,
          end: -30,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .08)),
          ),
        ),
        PositionedDirectional(
          bottom: -50,
          start: -20,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .06)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('admin_payments'.tr,
                      style: const TextStyle(
                          fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('admin_payments_hero_hint'.tr,
                      style: TextStyle(
                          fontFamily: 'tajawal', fontSize: 12.5, color: Colors.white.withValues(alpha: .85))),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _StatTile(stats[i])),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.s);
  final _Stat s;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(s.icon, size: 14, color: Colors.white.withValues(alpha: .9)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: Colors.white.withValues(alpha: .85))),
        ),
      ]),
      const SizedBox(height: 6),
      Text(s.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontFamily: 'tajawal', fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
    ]),
  );
}

class _Segments extends StatelessWidget {
  const _Segments({required this.index, required this.onChanged, required this.items});
  final int index;
  final ValueChanged<int> onChanged;
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Material(
              color: i == index ? c.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(items[i].$1, size: 18, color: i == index ? Colors.white : c.textLight),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(items[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'tajawal',
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: i == index ? Colors.white : c.textLight)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 16, color: c.textDark)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 1 · Methods
// ─────────────────────────────────────────────────────────────────────────────

class _MethodsTab extends StatelessWidget {
  const _MethodsTab({required this.gateway, required this.busy, required this.onPick});
  final String? gateway;
  final bool busy;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final pm = context.watch<AdminPaymentMethodsProvider>();
    final c = context.colors;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle('admin_default_card_gateway'.tr,
          subtitle: _t('اضغط لتغيير البوابة — يُحفظ فوراً. يمكن لكل كورس تخصيصها.',
              'Tap to switch — saved instantly. Each course can override it.')),
      Row(children: [
        for (final (i, g) in <(String?, IconData, String)>[
          (null, Icons.dns_rounded, 'admin_server_default'.tr),
          ('moyasar', Icons.payments_rounded, 'Moyasar'),
          ('paymob', Icons.account_balance_wallet_rounded, 'Paymob'),
        ].indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _GatewayTile(
              icon: g.$2,
              label: g.$3,
              selected: gateway == g.$1,
              loading: busy && gateway == g.$1,
              onTap: () => onPick(g.$1),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 22),
      _SectionTitle('admin_payment_methods'.tr,
          subtitle: _t('فعّل الطريقة أو اضغط على البطاقة لتعديل كل تفاصيلها.',
              'Switch a method on/off, or tap a card to edit all its details.')),
      if (pm.items.isEmpty && pm.isLoading)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: AppLoadingIndicator()))
      else if (pm.items.isEmpty)
        ErrorRetry(message: pm.error ?? 'admin_could_not_load'.tr, onRetry: pm.load)
      else
        for (final m in pm.items) _MethodCard(m),
      const SizedBox(height: 4),
      Text(
        _t('إنستاباي يظهر للطلاب بالجنيه المصري فقط. Apple Pay / Google Pay تظهر على الجوال فقط، وعندما تدعمها بوابة الدفع. رسومها من تبويب الرسوم.',
            'InstaPay is only shown to students paying in EGP. Apple Pay / Google Pay show on mobile only, and only when the gateway supports them. Set their fees in the Fees tab.'),
        style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.textLight),
      ),
    ]);
  }
}

class _GatewayTile extends StatelessWidget {
  const _GatewayTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.loading,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primary.withValues(alpha: .1) : c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 26,
              child: loading
                  ? const Center(child: SizedBox(width: 18, height: 18, child: AppLoadingIndicator()))
                  : Icon(selected ? Icons.check_circle_rounded : icon,
                  color: selected ? c.primary : c.textLight, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    color: selected ? c.primary : c.textDark)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 2 · Fees
// ─────────────────────────────────────────────────────────────────────────────

class _FeesTab extends StatelessWidget {
  const _FeesTab();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.primary.withValues(alpha: .2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 20, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _t('كل رسم يمكن ضبطه كنسبة مئوية، أو مبلغ ثابت، أو الاثنين معاً. '
                  'لكل رسم قيمة افتراضية يمكنك الرجوع إليها.',
                  'Every fee can be set as a percent, a fixed amount, or both. '
                      'Each one has a default you can reset to.'),
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, height: 1.45, color: c.textDark),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      const AdminFeeRatesSection(),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Method card: header (icon, summary, status, switch) that expands into the editor
// ─────────────────────────────────────────────────────────────────────────────

class _MethodCard extends StatefulWidget {
  const _MethodCard(this.m);
  final Map<String, dynamic> m;

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _open = false;

  /// One-line, human summary + whether required details are missing.
  ({String text, bool incomplete}) _summary(Map<String, dynamic> m, String method) {
    String tail(String v) => v.length <= 4 ? v : '•••• ${v.substring(v.length - 4)}';
    switch (method) {
      case 'bank_transfer':
        final iban = asStr(m['iban']).trim();
        if (iban.isEmpty) return (text: 'admin_method_details_required'.tr, incomplete: true);
        final bank = asStr(m['bank_name']).trim();
        return (text: [if (bank.isNotEmpty) bank, tail(iban)].join('  ·  '), incomplete: false);
      case 'instapay':
        final id = asStr(m['instapay_id']).trim();
        if (id.isEmpty) return (text: 'admin_method_details_required'.tr, incomplete: true);
        return (text: id, incomplete: false);
      case 'apple_pay' || 'google_pay':
        return (
        text: _t('محفظة رقمية — تظهر فقط إذا كانت البوابة تدعمها', 'Digital wallet — shown only when the gateway supports it'),
        incomplete: false,
        );
      default:
        return (text: _t('عبر البوابة الافتراضية', 'Via the default gateway'), incomplete: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminPaymentMethodsProvider>();
    final m = widget.m;
    final method = asStr(m['method']);
    final enabled = asBool(m['enabled']);
    final summary = _summary(m, method);
    final warn = Colors.amber.shade800;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(context, border: enabled ? c.primary.withValues(alpha: .4) : null),
      // Transparent Material = ink surface for the InkWell / SwitchListTiles inside the decorated box.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (enabled ? c.primary : c.textLight).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(_methodIcon(method), color: enabled ? c.primary : c.textLight, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(asStr(m['label']),
                        style: TextStyle(
                            fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 15.5, color: c.textDark)),
                    const SizedBox(height: 3),
                    Row(children: [
                      if (summary.incomplete) ...[
                        Icon(Icons.warning_amber_rounded, size: 14, color: warn),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(summary.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: method == 'card' || summary.incomplete ? null : TextDirection.ltr,
                            style: TextStyle(
                                fontFamily: 'tajawal',
                                fontSize: 12.5,
                                color: summary.incomplete ? warn : c.textLight)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    _StatusPill(enabled: enabled),
                  ]),
                ),
                Switch(
                  value: enabled,
                  activeTrackColor: c.primary,
                  onChanged: (v) {
                    if (v && summary.incomplete) {
                      toast('admin_method_details_required'.tr, error: true);
                      setState(() => _open = true);
                      return;
                    }
                    p.save(method, {'enabled': v});
                  },
                ),
                AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded, color: c.textLight),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Column(children: [
              Divider(height: 1, color: c.divider),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _MethodForm(key: ValueKey('form_$method'), method: method, item: m),
              ),
            ])
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = enabled ? c.success : c.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(enabled ? 'apm_enabled'.tr : 'apm_disabled'.tr,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full editor (grouped, AR/EN side by side on wide screens)
//  All     : name students see (AR + EN), "how to pay" instructions (AR + EN)
//  Bank    : bank name, account holder, IBAN, SWIFT
//  InstaPay: InstaPay address
//  Manual  : require sender phone / transfer reference, min + max amount,
//            time to send the proof (0 = no timer)
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
  bool get _isWallet => widget.method == 'apple_pay' || widget.method == 'google_pay';

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

  Widget _field(
      TextEditingController ctrl,
      String labelKey, {
        int maxLines = 1,
        TextInputType? keyboard,
        String? Function(String?)? validator,
        String? helperKey,
        bool ltr = false,
        IconData? icon,
      }) =>
      TextFormField(
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
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          alignLabelWithHint: maxLines > 1,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  Widget _switchTile(String labelKey, bool value, ValueChanged<bool> onChanged) {
    final c = context.colors;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      value: value,
      activeTrackColor: c.primary,
      onChanged: onChanged,
      tileColor: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.divider),
      ),
      title: Text(labelKey.tr, style: const TextStyle(fontFamily: 'tajawal', fontSize: 13.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const number = TextInputType.numberWithOptions(decimal: true);

    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Group(
          icon: Icons.edit_note_rounded,
          title: 'apm_section_display'.tr,
          children: [
            _Pair(
              _field(_labelAr, 'apm_label_ar'),
              _field(_labelEn, 'apm_label_en', ltr: true),
            ),
            if (!_isWallet)
              _Pair(
                _field(_insAr, 'apm_instructions_ar', maxLines: 5),
                _field(_insEn, 'apm_instructions_en', maxLines: 5, ltr: true),
              ),
          ],
        ),
        if (_isBank) ...[
          const SizedBox(height: 14),
          _Group(
            icon: Icons.account_balance_rounded,
            title: 'apm_section_receiving'.tr,
            children: [
              _Pair(
                _field(_bankName, 'apm_bank_name'),
                _field(_accountName, 'apm_account_name'),
              ),
              _Pair(
                _field(_iban, 'apm_iban', ltr: true),
                _field(_swift, 'apm_swift', ltr: true),
              ),
            ],
          ),
        ],
        if (_isInstapay) ...[
          const SizedBox(height: 14),
          _Group(
            icon: Icons.qr_code_2_rounded,
            title: 'apm_section_receiving'.tr,
            children: [
              _field(_instapayId, 'apm_instapay_id', ltr: true),
              Text('apm_instapay_egp_note'.tr,
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
            ],
          ),
        ],
        if (_isManual) ...[
          const SizedBox(height: 14),
          _Group(
            icon: Icons.rule_rounded,
            title: 'apm_section_requirements'.tr,
            children: [
              _Pair(
                _switchTile('apm_require_phone', _reqPhone, (v) => setState(() => _reqPhone = v)),
                _switchTile('apm_require_reference', _reqRef, (v) => setState(() => _reqRef = v)),
              ),
              _Pair(
                _field(_min, 'apm_min_amount',
                    keyboard: number, validator: _optionalAmount, helperKey: 'apm_amount_hint'),
                _field(_max, 'apm_max_amount',
                    keyboard: number, validator: _maxAmount, helperKey: 'apm_amount_hint'),
              ),
              _field(_window, 'apm_window',
                  keyboard: TextInputType.number,
                  validator: _windowMinutes,
                  helperKey: 'apm_window_hint',
                  icon: Icons.timer_outlined),
            ],
          ),
        ],
        const SizedBox(height: 16),
        PrimaryButton(label: 'apm_save'.tr, isLoading: _busy, onPressed: _save),
      ]),
    );
  }
}

/// A soft, titled block that groups related fields (children are spaced 12px apart).
class _Group extends StatelessWidget {
  const _Group({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: c.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 14, color: c.textDark)),
          ),
        ]),
        for (final w in children) ...[const SizedBox(height: 12), w],
      ]),
    );
  }
}

/// Two widgets side by side on wide screens, stacked on phones.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
    if (box.maxWidth < 560) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ]);
  });
}