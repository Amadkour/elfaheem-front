// lib/features/admin/consoles/admin_markets_page.dart
//
// The super admin's "Payment markets" console (docs/redesign/api/payments.md §2 – §4, parent_payments.md §4): three
// tabs over the payments package's admin routes.
//   Rates    GET|PUT /api/v1/admin/payments/currency-rates   {rates: [{base, quote, rate}], max_age_days}
//                                                            (rate null deletes a pair)
//   Methods  GET|PUT /api/v1/admin/payments/catalog          {methods: {key: {enabled, countries}}, bnpl: {…}}
//   VAT      GET|PUT /api/v1/admin/payments/vat-rules        {seller_country, rules: {CC: {percent, scope}}, tax_number}
// Every PUT sends the whole tab (the rules sent replace the stored ones). Kill switch `admin.payment_markets`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show AppConfig, Trans;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin_common.dart' show trp;
import '../cfg_common.dart';
import '../sup/sup_kit.dart';
import 'console_parts.dart';

const kAdminPaymentMarketsKey = 'admin.payment_markets';

class _RateRow {
  _RateRow({String base = '', String quote = '', String rate = '', this.updatedAt, this.stored})
      : base = TextEditingController(text: base),
        quote = TextEditingController(text: quote),
        rate = TextEditingController(text: rate);

  final TextEditingController base, quote, rate;
  final DateTime? updatedAt;

  /// "BASE/QUOTE" of the pair the server holds (null for a new row).
  final String? stored;

  String get pair => '${base.text.trim().toUpperCase()}/${quote.text.trim().toUpperCase()}';

  void dispose() {
    base.dispose();
    quote.dispose();
    rate.dispose();
  }
}

class _VatRow {
  _VatRow({this.country, String percent = '', this.scope = 'all'}) : percent = TextEditingController(text: percent);

  String? country;
  final TextEditingController percent;
  String scope;
}

class AdminPaymentMarketsPage extends StatefulWidget {
  const AdminPaymentMarketsPage({super.key, this.initialTab = 0});

  /// The tab the page opens on.
  final int initialTab;

  @override
  State<AdminPaymentMarketsPage> createState() => _AdminPaymentMarketsPageState();
}

class _AdminPaymentMarketsPageState extends State<AdminPaymentMarketsPage> {
  final _api = ApiClient();
  late int _tab = widget.initialTab;
  bool _loaded = false;
  Object? _error;
  bool _saving = false;

  // rates
  final _rates = <_RateRow>[];
  final _maxAge = TextEditingController();
  String _ratesBase = '';

  // catalog
  List<Map<String, dynamic>> _methods = [];
  List<Map<String, dynamic>> _bnpl = [];
  final _countryCtrls = <String, TextEditingController>{};
  String _catalogBase = '';

  // vat
  String? _seller;
  final _tax = TextEditingController();
  final _vat = <_VatRow>[];
  String _vatBase = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rates) {
      r.dispose();
    }
    for (final c in _countryCtrls.values) {
      c.dispose();
    }
    for (final v in _vat) {
      v.percent.dispose();
    }
    _maxAge.dispose();
    _tax.dispose();
    super.dispose();
  }

  // ── bodies (the dirty check compares them with what was loaded) ─────────────────────────────────────────────

  Map<String, dynamic> _ratesBody() {
    final now = {for (final r in _rates) r.pair};
    return {
      'rates': [
        for (final r in _rates)
          {'base': r.base.text.trim().toUpperCase(), 'quote': r.quote.text.trim().toUpperCase(), 'rate': cNum(r.rate.text)},
      ],
      'max_age_days': cInt(_maxAge.text),
      '_gone': [for (final r in _stored) if (!now.contains(r)) r],
    };
  }

  final _stored = <String>{};

  List<String> _countriesOf(String part, String key) => [
        for (final x in (_countryCtrls['$part:$key']?.text ?? '').split(RegExp(r'[,\s]+')))
          if (x.trim().length == 2) x.trim().toUpperCase(),
      ];

  Map<String, dynamic> _catalogBody() => {
        'methods': {
          for (final m in _methods) cStr(m['key']): {'enabled': m['enabled'] == true, 'countries': _countriesOf('methods', cStr(m['key']))},
        },
        'bnpl': {
          for (final m in _bnpl) cStr(m['key']): {'enabled': m['enabled'] == true, 'countries': _countriesOf('bnpl', cStr(m['key']))},
        },
      };

  Map<String, dynamic> _vatBody() => {
        'seller_country': _seller,
        'rules': {
          for (final v in _vat)
            if (v.country != null) v.country!: {'percent': cNum(v.percent.text), 'scope': v.scope},
        },
        'tax_number': _tax.text.trim(),
      };

  bool get _ratesDirty => _loaded && jsonEncode(_ratesBody()) != _ratesBase;
  bool get _catalogDirty => _loaded && jsonEncode(_catalogBody()) != _catalogBase;
  bool get _vatDirty => _loaded && jsonEncode(_vatBody()) != _vatBase;
  bool get _dirty => _ratesDirty || _catalogDirty || _vatDirty;
  bool get _tabDirty => switch (_tab) { 0 => _ratesDirty, 1 => _catalogDirty, _ => _vatDirty };

  // ── load ────────────────────────────────────────────────────────────────────────────────────────────────────

  void _takeRates(Map<String, dynamic> r) {
    for (final x in _rates) {
      x.dispose();
    }
    _rates
      ..clear()
      ..addAll([
        for (final x in cList(r['rates']))
          _RateRow(
            base: cStr(x['base']),
            quote: cStr(x['quote']),
            rate: cNumText(x['rate']),
            updatedAt: DateTime.tryParse(cStr(x['updated_at']))?.toUtc(),
            stored: '${cStr(x['base'])}/${cStr(x['quote'])}',
          ),
      ]);
    _stored
      ..clear()
      ..addAll([for (final x in _rates) x.stored!]);
    _maxAge.text = cNumText(r['max_age_days'] ?? 30);
    _ratesBase = jsonEncode(_ratesBody());
  }

  void _takeCatalog(Map<String, dynamic> r) {
    _methods = cList(r['methods']);
    _bnpl = cList(r['bnpl']);
    for (final c in _countryCtrls.values) {
      c.dispose();
    }
    _countryCtrls.clear();
    for (final (part, list) in [('methods', _methods), ('bnpl', _bnpl)]) {
      for (final m in list) {
        final cs = (m['countries'] is List) ? [for (final x in m['countries'] as List) cStr(x)] : const <String>[];
        _countryCtrls['$part:${cStr(m['key'])}'] = TextEditingController(text: cs.join(', '));
      }
    }
    _catalogBase = jsonEncode(_catalogBody());
  }

  void _takeVat(Map<String, dynamic> r) {
    _seller = cStr(r['seller_country']).isEmpty ? null : cStr(r['seller_country']).toUpperCase();
    _tax.text = cStr(r['tax_number']);
    for (final v in _vat) {
      v.percent.dispose();
    }
    _vat
      ..clear()
      ..addAll([
        for (final e in cMap(r['rules']).entries)
          _VatRow(country: e.key.toUpperCase(), percent: cNumText(cMap(e.value)['percent']), scope: cStr(cMap(e.value)['scope'], 'all')),
      ]);
    _vatBase = jsonEncode(_vatBody());
  }

  Future<void> _load() async {
    if (_loaded && _dirty) {
      final ok = await appConfirm(context, message: 'a2_discard_q'.tr);
      if (!ok || !mounted) return;
    }
    try {
      final res = await Future.wait([
        _api.get('/api/v1/admin/payments/currency-rates'),
        _api.get('/api/v1/admin/payments/catalog'),
        _api.get('/api/v1/admin/payments/vat-rules'),
      ]);
      if (!mounted) return;
      setState(() {
        _takeRates(cMap(res[0]));
        _takeCatalog(cMap(res[1]));
        _takeVat(cMap(res[2]));
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!_loaded) {
        setState(() => _error = e);
      } else {
        showAppNotice(cfgErrorMessage(e), error: true);
      }
    }
  }

  // ── save ────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      switch (_tab) {
        case 0:
          final b = _ratesBody();
          final rows = b['rates'] as List;
          if (rows.any((x) => (x as Map)['rate'] == null || cStr(x['base']).length != 3 || cStr(x['quote']).length != 3) ||
              b['max_age_days'] == null) {
            showAppNotice('a2_mk_rates_invalid'.tr, error: true);
            return;
          }
          final gone = [
            for (final p in b['_gone'] as List) {'base': cStr(p).split('/').first, 'quote': cStr(p).split('/').last, 'rate': null},
          ];
          final r = cMap(await _api.put('/api/v1/admin/payments/currency-rates',
              body: {'rates': [...rows, ...gone], 'max_age_days': b['max_age_days']}));
          if (mounted) setState(() => _takeRates(r));
        case 1:
          final r = cMap(await _api.put('/api/v1/admin/payments/catalog', body: _catalogBody()));
          if (mounted) setState(() => _takeCatalog(r));
        default:
          if (_vat.any((v) => v.country == null)) {
            showAppNotice('a2_mk_vat_country_missing'.tr, error: true);
            return;
          }
          final r = cMap(await _api.put('/api/v1/admin/payments/vat-rules', body: _vatBody()));
          if (mounted) setState(() => _takeVat(r));
      }
      showAppNotice('a2_saved'.tr);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── tabs ────────────────────────────────────────────────────────────────────────────────────────────────────

  void _changed([_]) => setState(() {});

  Widget _ratesTab(BuildContext context) {
    return ListView(padding: SupPage.bodyPadding(context), children: [
      SupCard(
        title: 'a2_mk_rates'.tr,
        subtitle: 'a2_mk_rates_d'.tr,
        icon: Icons.currency_exchange_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_rates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text('a2_mk_rates_empty'.tr, style: AppType.meta(context)),
            ),
          for (final r in _rates)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: AppField(controller: r.base, label: 'a2_mk_base'.tr, ltr: true, maxLength: 3, onChanged: _changed)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AppField(controller: r.quote, label: 'a2_mk_quote'.tr, ltr: true, maxLength: 3, onChanged: _changed)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: AppField(
                        controller: r.rate,
                        label: 'a2_mk_rate'.tr,
                        ltr: true,
                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: _changed),
                  ),
                  IconButton(
                    tooltip: 'a2_remove'.tr,
                    icon: Icon(Icons.delete_outline_rounded, color: appKitTone(context, AppTone.danger).ink),
                    onPressed: () => setState(() {
                      _rates.remove(r);
                    }),
                  ),
                ]),
                if (r.updatedAt != null)
                  Text(trp('a2_mk_updated', {'date': AppTime.date(r.updatedAt!)}), style: AppType.meta(context)),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              label: 'a2_mk_add_rate'.tr,
              icon: Icons.add_rounded,
              onPressed: () => setState(() => _rates.add(_RateRow())),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          ConsoleNumberField(controller: _maxAge, label: 'a2_mk_max_age'.tr, helper: 'a2_mk_max_age_d'.tr, onChanged: _changed),
        ]),
      ),
    ]);
  }

  Widget _methodRow(BuildContext context, String part, Map<String, dynamic> m) {
    final key = cStr(m['key']);
    final label = AppConfig.lang == 'ar' ? cStr(m['label_ar'], key) : cStr(m['label_en'], key);
    final meta = [
      if (cStr(m['kind']).isNotEmpty) cStr(m['kind']),
      if (m['providers'] is List && (m['providers'] as List).isNotEmpty) (m['providers'] as List).join(' · '),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSwitchTile(
          padding: EdgeInsets.zero,
          title: label,
          subtitle: meta.isEmpty ? null : meta,
          value: m['enabled'] == true,
          onChanged: (v) => setState(() => m['enabled'] = v),
        ),
        AppField(
          controller: _countryCtrls['$part:$key']!,
          label: 'a2_mk_countries'.tr,
          helper: 'a2_mk_countries_d'.tr,
          ltr: true,
          onChanged: _changed,
        ),
      ]),
    );
  }

  Widget _catalogTab(BuildContext context) => ListView(padding: SupPage.bodyPadding(context), children: [
        SupCard(
          title: 'a2_mk_methods'.tr,
          subtitle: 'a2_mk_methods_d'.tr,
          icon: Icons.credit_card_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_methods.isEmpty) Text('a2_mk_none'.tr, style: AppType.meta(context)),
            for (final m in _methods) _methodRow(context, 'methods', m),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        SupCard(
          title: 'a2_mk_bnpl'.tr,
          subtitle: 'a2_mk_bnpl_d'.tr,
          icon: Icons.schedule_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_bnpl.isEmpty) Text('a2_mk_none'.tr, style: AppType.meta(context)),
            for (final m in _bnpl) _methodRow(context, 'bnpl', m),
          ]),
        ),
      ]);

  Widget _vatTab(BuildContext context) {
    return ListView(padding: SupPage.bodyPadding(context), children: [
      SupCard(
        title: 'a2_mk_seller'.tr,
        subtitle: 'a2_mk_seller_d'.tr,
        icon: Icons.store_mall_directory_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConsoleCountryField(value: _seller, label: 'a2_mk_seller_country'.tr, onChanged: (v) => setState(() => _seller = v)),
          const SizedBox(height: AppSpace.sm),
          AppField(
            controller: _tax,
            label: 'a2_mk_tax_number'.tr,
            helper: 'a2_mk_tax_number_d'.tr,
            ltr: true,
            maxLength: 40,
            onChanged: _changed,
          ),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      SupCard(
        title: 'a2_mk_vat'.tr,
        subtitle: 'a2_mk_vat_d'.tr,
        icon: Icons.percent_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_vat.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text('a2_mk_vat_empty'.tr, style: AppType.meta(context)),
            ),
          for (final v in _vat)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: ConsoleCountryField(
                        value: v.country, label: 'a2_mk_country'.tr, onChanged: (x) => setState(() => v.country = x)),
                  ),
                  IconButton(
                    tooltip: 'a2_remove'.tr,
                    icon: Icon(Icons.delete_outline_rounded, color: appKitTone(context, AppTone.danger).ink),
                    onPressed: () => setState(() => _vat.remove(v)),
                  ),
                ]),
                const SizedBox(height: AppSpace.xs),
                AppField(
                  controller: v.percent,
                  label: 'a2_mk_percent'.tr,
                  helper: 'a2_mk_percent_d'.tr,
                  ltr: true,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: _changed,
                ),
                const SizedBox(height: AppSpace.xs),
                AppDropdown<String>(
                  decoration: InputDecoration(labelText: 'a2_mk_scope'.tr),
                  value: v.scope,
                  items: [
                    DropdownMenuItem(value: 'domestic', child: Text('a2_mk_scope_domestic'.tr)),
                    DropdownMenuItem(value: 'all', child: Text('a2_mk_scope_all'.tr)),
                  ],
                  onChanged: (x) => setState(() => v.scope = x ?? v.scope),
                ),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              label: 'a2_mk_add_rule'.tr,
              icon: Icons.add_rounded,
              onPressed: () => setState(() => _vat.add(_VatRow())),
            ),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _methods.where((m) => m['enabled'] == true).length;
    return SupPage(
      pageKey: const ValueKey(kAdminPaymentMarketsKey),
      title: 'a2_mk_title'.tr,
      kicker: 'a2_mk_kicker'.tr,
      headline: 'a2_mk_head'.tr,
      line: 'a2_mk_line'.tr,
      onRefresh: _load,
      dirty: _dirty,
      width: AppWidth.form,
      stats: _loaded
          ? [
              AppHeroStat(value: '${_rates.length}', label: 'a2_mk_stat_rates'.tr),
              AppHeroStat(value: '$enabled', label: 'a2_mk_stat_methods'.tr),
              AppHeroStat(value: _seller ?? '—', label: 'a2_mk_stat_seller'.tr),
            ]
          : const [],
      tabs: [supTab('a2_mk_tab_rates'.tr), supTab('a2_mk_tab_methods'.tr), supTab('a2_mk_tab_vat'.tr)],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      actions: [if (_loaded) cfgSaveButton(dirty: _tabDirty, busy: _saving, onSave: _save)],
      body: _error != null && !_loaded
          ? cfgErrorState(_error, onRetry: _load)
          : !_loaded
              ? const AppListSkeleton(items: 4, withAvatar: false)
              : SupTabStack(index: _tab, children: [_ratesTab(context), _catalogTab(context), _vatTab(context)]),
    );
  }
}
