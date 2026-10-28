// features/auth/phone_field.dart
// ─────────────────────────────────────────────────────────────────────────────
// Premium phone input: [ flag +code ▾ ] [ phone number ]
// Countries: Egypt, Saudi Arabia, UAE.
//
// The widget keeps `controller` equal to the FULL international number
// (e.g. +201012345678), or '' while the number part is empty — so the code that
// already reads the phone controller (register, OTP screen) works unchanged.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../features/auth/auth_widgets.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class PhoneCountry {
  final String nameEn;
  final String nameAr;
  final String dial; // with '+'
  final String flag;
  final int length; // digits after the code, without a leading 0
  final String hint;

  const PhoneCountry({
    required this.nameEn,
    required this.nameAr,
    required this.dial,
    required this.flag,
    required this.length,
    required this.hint,
  });

  String get name => AppConfig.lang == 'ar' ? nameAr : nameEn;
}

const List<PhoneCountry> kPhoneCountries = [
  PhoneCountry(
    nameEn: 'Egypt',
    nameAr: 'مصر',
    dial: '+20',
    flag: '🇪🇬',
    length: 10,
    hint: '1X XXXX XXXX',
  ),
  PhoneCountry(
    nameEn: 'Saudi Arabia',
    nameAr: 'السعودية',
    dial: '+966',
    flag: '🇸🇦',
    length: 9,
    hint: '5X XXX XXXX',
  ),
  PhoneCountry(
    nameEn: 'United Arab Emirates',
    nameAr: 'الإمارات',
    dial: '+971',
    flag: '🇦🇪',
    length: 9,
    hint: '5X XXX XXXX',
  ),
];

class PhoneInputField extends StatefulWidget {
  const PhoneInputField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.countries = kPhoneCountries,
  });

  /// Receives the full international number (or '' when empty).
  final TextEditingController controller;
  final String label;

  /// true = an empty number fails validation.
  final bool required;
  final List<PhoneCountry> countries;

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {

  final _local = TextEditingController();
  late PhoneCountry _country;

  @override
  void initState() {
    super.initState();
    _country = widget.countries.first;
    // Restore an existing full number (e.g. coming back to the screen).
    final existing = widget.controller.text.trim();
    if (existing.startsWith('+')) {
      for (final k in widget.countries) {
        if (existing.startsWith(k.dial)) {
          _country = k;
          _local.text = existing.substring(k.dial.length);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }

  /// Digits of the number part: no spaces, no leading 0, and a pasted
  /// "+20…" / "0020…" prefix is removed.
  String get _digits {
    var d = _local.text.replaceAll(RegExp(r'\D'), '');
    final dialDigits = _country.dial.substring(1);
    if (d.startsWith('00$dialDigits')) {
      d = d.substring(2 + dialDigits.length);
    } else if (d.startsWith(dialDigits) && d.length > _country.length) {
      d = d.substring(dialDigits.length);
    }
    if (d.startsWith('0')) d = d.substring(1);
    return d;
  }

  void _sync() {
    final d = _digits;
    widget.controller.text = d.isEmpty ? '' : '${_country.dial}$d';
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountrySheet(
        countries: widget.countries,
        selected: _country,
      ),
    );
    if (picked != null && picked != _country) {
      setState(() => _country = picked);
      _sync();
    }
  }

  String? _validate(String? _) {
    final d = _digits;
    if (d.isEmpty) return widget.required ? '${widget.label} *' : null;
    if (d.length != _country.length) {
      return AppConfig.lang == 'ar'
          ? 'رقم الهاتف غير صحيح'
          : 'Invalid phone number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The auth field look (D-073): one filled box, radius 16, hairline border, a primary stroke + halo on focus.
    // The country code sits inside it as the prefix, so the halo wraps code and number together.
    final code = Semantics(
      button: true,
      label: _country.name,
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        onTap: _pickCountry,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_country.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Text(
                  _country.dial,
                  style: authText(15, w: FontWeight.w700, c: c.textDark),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                const SizedBox(width: 6),
                Container(width: 1, height: 24, color: c.divider.withValues(alpha: c.isDark ? 0.9 : 0.75)),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: widget.label),
        const SizedBox(height: 8),
        // Phone numbers always read left-to-right: [ code ▾ | number ]
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextFormField(
            controller: _local,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              LengthLimitingTextInputFormatter(18),
            ],
            onChanged: (_) => _sync(),
            validator: _validate,
            style: authFieldText(context).copyWith(letterSpacing: 0.6),
            cursorColor: c.primary,
            decoration: authInputDecoration(context, hint: _country.hint).copyWith(
              prefixIcon: code,
              prefixIconConstraints: const BoxConstraints(minHeight: 48),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Country bottom sheet ─────────────────────────────────────────────────────
class _CountrySheet extends StatelessWidget {
  const _CountrySheet({required this.countries, required this.selected});

  final List<PhoneCountry> countries;
  final PhoneCountry selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection:
          AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConfig.lang == 'ar' ? 'اختر الدولة' : 'Select country',
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textDark,
              ),
            ),
            const SizedBox(height: 12),
            for (final k in countries)
              _CountryTile(
                country: k,
                selected: k == selected,
                onTap: () => Navigator.pop(context, k),
              ),
          ],
        )),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  final PhoneCountry country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? c.primary.withAlpha(c.isDark ? 34 : 20)
            : c.inputBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? c.primary : c.divider,
                width: selected ? 1.8 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Text(country.flag, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    country.name,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.textDark,
                    ),
                  ),
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    country.dial,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? c.primary : c.secondText,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, size: 20, color: c.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
