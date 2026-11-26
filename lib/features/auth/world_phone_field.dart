// features/auth/world_phone_field.dart — the phone field for ANY country (RULES §3, WP5).
//
//   WorldCountries.instance   GET /api/v1/countries?lang= (public, cached for the app run): every country with its
//                             dial code and fixed lengths, the featured ones first; offline it falls back to the
//                             app's short list (utils/widget/phone_field.dart)
//   WorldPhoneField(controller:, label:)   [ SA +966 ▾ | number ]: `controller` holds the E.164 number ('' while
//                             empty); the picker is a searchable sheet; [onCountry] reports the phone's country
//                             (sent as `phone_country`, never taken as the person's residence or nationality)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart' show kPhoneCountries;

import 'auth_widgets.dart';

class WorldCountry {
  const WorldCountry({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.dial,
    this.minLen,
    this.maxLen,
    this.featured = false,
  });

  final String code, nameAr, nameEn, dial;
  final int? minLen, maxLen;
  final bool featured;

  String get name => AppConfig.lang == 'ar' ? nameAr : nameEn;

  static WorldCountry? fromJson(Map<dynamic, dynamic> j) {
    final code = '${j['code'] ?? ''}'.toUpperCase();
    final dial = '${j['dial_code'] ?? ''}';
    if (code.length != 2 || !dial.startsWith('+')) return null;
    final lens = j['phone_lengths'];
    return WorldCountry(
      code: code,
      nameAr: '${j['name_ar'] ?? j['name_en'] ?? code}',
      nameEn: '${j['name_en'] ?? j['name_ar'] ?? code}',
      dial: dial,
      minLen: lens is List && lens.length == 2 ? (lens[0] as num?)?.toInt() : null,
      maxLen: lens is List && lens.length == 2 ? (lens[1] as num?)?.toInt() : null,
      featured: j['featured'] == true,
    );
  }

  /// [digits] (after the dial code) is a valid length: the country's fixed lengths, else E.164 (8–15 in all).
  bool validLength(String digits) {
    if (minLen != null && maxLen != null) return digits.length >= minLen! && digits.length <= maxLen!;
    final total = dial.length - 1 + digits.length;
    return total >= 8 && total <= 15;
  }
}

/// The world list, loaded once per run (and again after a language switch, for the order by name).
class WorldCountries extends ChangeNotifier {
  WorldCountries._();
  static final WorldCountries instance = WorldCountries._();

  List<WorldCountry> _list = _fallback();
  String? _defaultCode;
  String? _lang;
  bool _loading = false;

  List<WorldCountry> get countries => _list;

  /// The platform's default country (the picker's first choice).
  WorldCountry get initial =>
      _list.firstWhere((c) => c.code == _defaultCode, orElse: () => _list.firstWhere((c) => c.featured, orElse: () => _list.first));

  static List<WorldCountry> _fallback() => [
        for (final k in kPhoneCountries)
          WorldCountry(
            code: switch (k.dial) { '+20' => 'EG', '+966' => 'SA', '+971' => 'AE', _ => '??' },
            nameAr: k.nameAr,
            nameEn: k.nameEn,
            dial: k.dial,
            minLen: k.length,
            maxLen: k.length,
            featured: true,
          ),
      ];

  Future<void> ensure({ApiClient? api}) async {
    if (_loading || _lang == AppConfig.lang) return;
    _loading = true;
    try {
      final r = await (api ?? ApiClient()).get('/api/v1/countries', queryParams: {'lang': AppConfig.lang}, auth: false);
      if (r is Map && r['countries'] is List) {
        final list = [for (final x in r['countries'] as List) if (x is Map) WorldCountry.fromJson(x)].whereType<WorldCountry>().toList();
        if (list.isNotEmpty) {
          _list = list;
          _defaultCode = r['default_country']?.toString();
          _lang = AppConfig.lang;
          notifyListeners();
        }
      }
    } catch (_) {
      // offline / an older server: the short list stays
    } finally {
      _loading = false;
    }
  }
}

class WorldPhoneField extends StatefulWidget {
  const WorldPhoneField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.onCountry,
    this.fieldKey,
  });

  /// Receives the E.164 number (or '' when empty).
  final TextEditingController controller;
  final String label;
  final bool required;
  final ValueChanged<WorldCountry>? onCountry;
  final Key? fieldKey;

  @override
  State<WorldPhoneField> createState() => _WorldPhoneFieldState();
}

class _WorldPhoneFieldState extends State<WorldPhoneField> {
  final _local = TextEditingController();
  WorldCountry? _picked;
  final _w = WorldCountries.instance;

  WorldCountry get _country => _picked ?? _w.initial;

  @override
  void initState() {
    super.initState();
    _w.addListener(_onList);
    _w.ensure();
    _restore();
  }

  void _onList() {
    if (!mounted) return;
    _restore();
    setState(() {});
  }

  /// An existing full number (coming back to the screen): its country and the rest.
  void _restore() {
    final existing = widget.controller.text.trim();
    if (!existing.startsWith('+') || _local.text.isNotEmpty) return;
    final byLen = [..._w.countries]..sort((a, b) => b.dial.length.compareTo(a.dial.length));
    for (final k in byLen) {
      if (existing.startsWith(k.dial)) {
        _picked = k;
        _local.text = existing.substring(k.dial.length);
        return;
      }
    }
  }

  @override
  void dispose() {
    _w.removeListener(_onList);
    _local.dispose();
    super.dispose();
  }

  /// The number part's digits: Arabic-Indic digits mapped, no spaces, a pasted dial code and one trunk 0 dropped.
  String get _digits {
    final b = StringBuffer();
    for (final r in _local.text.runes) {
      if (r >= 0x30 && r <= 0x39) b.writeCharCode(r);
      if (r >= 0x0660 && r <= 0x0669) b.writeCharCode(0x30 + r - 0x0660);
    }
    var d = b.toString();
    final dialDigits = _country.dial.substring(1);
    if (d.startsWith('00$dialDigits')) {
      d = d.substring(2 + dialDigits.length);
    } else if (_local.text.trim().startsWith('+') && d.startsWith(dialDigits)) {
      d = d.substring(dialDigits.length);
    }
    if (d.startsWith('0')) d = d.substring(1);
    return d;
  }

  void _sync() {
    final d = _digits;
    widget.controller.text = d.isEmpty ? '' : '${_country.dial}$d';
  }

  Future<void> _pick() async {
    final picked = await showAppSheet<WorldCountry>(context, (_) => _CountrySheet(selected: _country));
    if (picked != null && picked.code != _country.code) {
      setState(() => _picked = picked);
      _sync();
      widget.onCountry?.call(picked);
    }
  }

  String? _validate(String? _) {
    final d = _digits;
    if (d.isEmpty) return widget.required ? 'sa_phone_required'.tr : null;
    if (!_country.validLength(d)) return 'sa_phone_invalid'.tr;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final code = Semantics(
      button: true,
      label: '${'sa_phone_country'.tr}: ${_country.name}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppRadius.control)),
        onTap: _pick,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.sm, end: AppSpace.xxs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_country.code, style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
              const SizedBox(width: AppSpace.xxs),
              Text(_country.dial, style: appFieldTextStyle(context).copyWith(fontWeight: FontWeight.w600)),
              const Icon(Icons.keyboard_arrow_down_rounded, size: AppIconSize.md),
              const SizedBox(width: AppSpace.xxs),
              Container(width: AppBorder.hairline, height: AppIconSize.lg, color: c.divider),
              const SizedBox(width: AppSpace.xxs),
            ]),
          ),
        ),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SectionLabel(label: widget.label),
      const SizedBox(height: AppSpace.xs),
      // a phone number reads left to right: [ code ▾ | number ]
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextFormField(
          key: widget.fieldKey,
          controller: _local,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩+ ]')),
            LengthLimitingTextInputFormatter(20),
          ],
          onChanged: (_) => _sync(),
          validator: _validate,
          style: authFieldText(context).copyWith(letterSpacing: .6),
          cursorColor: c.primary,
          decoration: authInputDecoration(context, hint: 'sa_phone_hint'.tr).copyWith(
            prefixIcon: code,
            prefixIconConstraints: const BoxConstraints(minHeight: AppTouch.min),
          ),
        ),
      ),
    ]);
  }
}

/// The country sheet: a search box, the featured countries first, then everyone by name.
class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.selected});

  final WorldCountry selected;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.trim().toLowerCase();
    final all = WorldCountries.instance.countries;
    final list = q.isEmpty
        ? all
        : all
            .where((k) =>
                k.nameAr.contains(q) || k.nameEn.toLowerCase().contains(q) || k.dial.contains(q) || k.code.toLowerCase() == q)
            .toList();
    return AppSheetContent(
      title: 'sa_phone_country'.tr,
      children: [
        AppSearchField(hint: 'sa_phone_search'.tr, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: AppSpace.sm),
        if (list.isEmpty) Text('sa_phone_none'.tr, style: AppType.meta(context)),
        for (final k in list.take(60))
          AppTile(
            dense: true,
            leading: SizedBox(
              width: AppDashSize.glyph,
              child: Text(k.code, textAlign: TextAlign.center, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
            ),
            title: k.name,
            selected: k.code == widget.selected.code,
            trailing: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(k.dial, style: AppType.label(context).copyWith(color: c.textMedium)),
            ),
            onTap: () => Navigator.of(context).pop(k),
          ),
      ],
    );
  }
}
