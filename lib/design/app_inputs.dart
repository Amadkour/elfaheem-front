// lib/design/app_inputs.dart
//
// The app's ONE set of identity inputs — same look as registration (label above, icon, tinted fill, 14 radius),
// with real validation and bilingual messages:
//
//   AppEmailField     e-mail · live ✓ / error · LTR · autofill
//   AppPasswordField  show / hide · optional strength checklist · optional "must match" for confirmations
//   AppPhoneField     the registration phone field (country picker + length validation)
//   AppUrlField       website · https:// added when missing
//
// Login / forgot-password keep their single IDENTIFIER field (e-mail OR phone): that is the right pattern and the
// admin chooses which identifiers are allowed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart';

export 'package:flutter_education_app/utils/widget/phone_field.dart' show PhoneInputField;

typedef AppPhoneField = PhoneInputField;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

final RegExp kEmailRegex = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$");

String? validateEmail(String? v, {bool required = true}) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return required ? _t('البريد الإلكتروني مطلوب', 'E-mail is required') : null;
  if (!kEmailRegex.hasMatch(s)) return _t('اكتب بريداً صحيحاً مثل name@example.com', 'Enter a valid e-mail like name@example.com');
  return null;
}

/// Shared decoration — identical to the registration fields, but from the live theme.
InputDecoration appInputDecoration(BuildContext context, {required String hint, required IconData icon, Widget? suffix}) {
  final c = context.colors;
  OutlineInputBorder b(Color col, [double w = 1.5]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: col, width: w));
  return InputDecoration(
    prefixIcon: Icon(icon, size: 18, color: c.textLight),
    suffixIcon: suffix,
    hintText: hint,
    hintStyle: TextStyle(fontFamily: 'tajawal', fontSize: 14, color: c.textLight),
    filled: true,
    fillColor: c.inputBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: b(c.divider),
    enabledBorder: b(c.divider),
    focusedBorder: b(c.primary.withValues(alpha: 0.7)),
    errorBorder: b(c.danger.withValues(alpha: 0.7)),
    focusedErrorBorder: b(c.danger),
    errorStyle: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.danger),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, fontWeight: FontWeight.w700, color: context.colors.textMedium)),
      );
}

class AppEmailField extends StatefulWidget {
  const AppEmailField({
    super.key,
    required this.controller,
    this.label,
    this.required = true,
    this.enabled = true,
    this.readOnly = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final bool required, enabled, readOnly;
  final ValueChanged<String>? onChanged;

  @override
  State<AppEmailField> createState() => _AppEmailFieldState();
}

class _AppEmailFieldState extends State<AppEmailField> {
  bool _touched = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = widget.label ?? _t('البريد الإلكتروني', 'E-mail');
    final value = widget.controller.text.trim();
    final valid = kEmailRegex.hasMatch(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label(label),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          style: TextStyle(fontFamily: 'tajawal', fontSize: 14, color: c.textDark),
          autovalidateMode: _touched ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          validator: (v) => validateEmail(v, required: widget.required),
          onChanged: (v) {
            setState(() => _touched = true);
            widget.onChanged?.call(v);
          },
          decoration: appInputDecoration(context,
              hint: 'name@example.com',
              icon: Icons.alternate_email_rounded,
              suffix: value.isEmpty
                  ? null
                  : Icon(valid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 19, color: valid ? c.success : c.warning)),
        ),
      ]),
    );
  }
}

class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    super.key,
    required this.controller,
    this.label,
    this.showStrength = false,
    this.mustMatch,
    this.minLength = 6,
    this.required = true,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final bool showStrength, required, enabled;
  final TextEditingController? mustMatch; // confirmation field
  final int minLength;
  final ValueChanged<String>? onChanged;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.controller.text;
    final rules = <(bool, String)>[
      (v.length >= widget.minLength, _t('${widget.minLength} أحرف على الأقل', 'At least ${widget.minLength} characters')),
      (RegExp(r'[A-Z]').hasMatch(v), _t('حرف كبير واحد على الأقل (A-Z)', 'One uppercase letter (A-Z)')),
      (RegExp(r'\d').hasMatch(v), _t('رقم واحد على الأقل', 'One number')),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label(widget.label ?? _t('كلمة المرور', 'Password')),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: _hidden,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          style: TextStyle(fontFamily: 'tajawal', fontSize: 14, color: c.textDark),
          validator: (s) {
            final x = s ?? '';
            if (x.isEmpty) return widget.required ? _t('كلمة المرور مطلوبة', 'Password is required') : null;
            if (x.length < widget.minLength) return _t('${widget.minLength} أحرف على الأقل', 'At least ${widget.minLength} characters');
            if (widget.mustMatch != null && x != widget.mustMatch!.text) return _t('كلمتا المرور غير متطابقتين', "Passwords don't match");
            return null;
          },
          onChanged: (s) {
            setState(() {});
            widget.onChanged?.call(s);
          },
          decoration: appInputDecoration(context,
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19, color: c.textLight),
              )),
        ),
        if (widget.showStrength && v.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final (ok, text) in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 15, color: ok ? c.success : c.textLight),
                const SizedBox(width: 6),
                Text(text, style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: ok ? c.success : c.textMedium)),
              ]),
            ),
        ],
      ]),
    );
  }
}

class AppUrlField extends StatelessWidget {
  const AppUrlField({super.key, required this.controller, this.label, this.required = false});
  final TextEditingController controller;
  final String? label;
  final bool required;

  static String normalize(String v) {
    final s = v.trim();
    if (s.isEmpty || s.startsWith(RegExp(r'https?://'))) return s;
    return 'https://$s';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Label(label ?? _t('الموقع الإلكتروني', 'Website')),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 14, color: context.colors.textDark),
            validator: (v) {
              final s = normalize(v ?? '');
              if (s.isEmpty) return required ? _t('الرابط مطلوب', 'The link is required') : null;
              final u = Uri.tryParse(s);
              return (u == null || !u.hasAuthority || !u.host.contains('.')) ? _t('رابط غير صحيح', 'Invalid link') : null;
            },
            onEditingComplete: () => controller.text = normalize(controller.text),
            decoration: appInputDecoration(context, hint: 'https://example.com', icon: Icons.language_rounded),
          ),
        ]),
      );
}
