// lib/design/app_inputs.dart
//
// THE field language of the design system (system.md §4, Warm Editorial): a warm inset well (`inputBg`), radius 14,
// a warm hairline at rest, a crisp 2 px emerald ring on focus, the label ABOVE the well (never placeholder-only), the
// error UNDER it, a 48 px prefix / suffix target. Every field in the kit draws from the three helpers here, so a
// text field, a dropdown, a picker, a number field and a search box sit in one row without a seam:
//
//   AppFieldLabel('E-mail')                                   the label above a well (AppType.label)
//   appFieldDecoration(context, hint:, icon:, suffix:, …)      the ONE InputDecoration (for a raw TextFormField too)
//   appFieldTextStyle(context)                                 the text typed into a well
//
// The fields:
//
//   AppField          plain text (the kit's `Field`): label above, hint, helper / error under, optional icon
//   AppEmailField     e-mail · live ✓ / error · LTR · autofill
//   AppPasswordField  show / hide · optional strength checklist · optional "must match" for confirmations
//   AppPhoneField     the registration phone field (country picker + length validation)
//   AppUrlField       website · https:// added when missing
//
// Login / forgot-password keep their single IDENTIFIER field (e-mail OR phone): that is the right pattern and the
// admin chooses which identifiers are allowed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart';

import 'app_contrast.dart' show ensureContrast;
import 'app_tokens.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
//  The language
// ─────────────────────────────────────────────────────────────────────────────

/// The focus ring's colour: the primary, lifted until it separates from the well at 3:1 (a dark theme's deep
/// emerald would sink into the dark well).
Color appFieldFocusInk(BuildContext context) {
  final c = context.colors;
  return ensureContrast(c.primary, [c.inputBg, c.cardBg], min: 3);
}

/// What the person types: the row style (the person's font, 400 – 600 weights) a step larger, so a value reads
/// above its label.
TextStyle appFieldTextStyle(BuildContext context) =>
    AppType.row(context).copyWith(fontSize: 15, height: 1.35, color: context.colors.textDark);

/// THE decoration of every well in the kit — and of a raw `TextFormField` that wants the same look.
///
/// Warm fill, radius 14, a hairline at rest, the 2 px ring on focus, the danger hairline (2 px when focused) on an
/// error. The prefix icon and the suffix each sit in a 48 px box. [helper] and [errorText] are drawn under the well
/// (two lines at most); the label is NOT part of it — put an [AppFieldLabel] above the field instead.
InputDecoration appFieldDecoration(
  BuildContext context, {
  String? hint,
  IconData? icon,
  Widget? prefix,
  Widget? suffix,
  String? helper,
  String? errorText,
  bool dense = false,
  bool enabled = true,
}) {
  final c = context.colors;
  final focus = appFieldFocusInk(context);
  OutlineInputBorder border(Color col, [double w = AppBorder.hairline]) =>
      OutlineInputBorder(borderRadius: AppRadius.controlAll, borderSide: BorderSide(color: col, width: w));
  return InputDecoration(
    prefixIcon: prefix ?? (icon == null ? null : Icon(icon, size: AppIconSize.md)),
    prefixIconColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.error)
        ? c.danger
        : s.contains(WidgetState.focused)
            ? focus
            : c.textLight),
    prefixIconConstraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
    suffixIcon: suffix,
    suffixIconColor: c.textLight,
    suffixIconConstraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
    hintText: hint,
    hintStyle: appFieldTextStyle(context).copyWith(fontWeight: FontWeight.w400, color: c.textLight),
    helperText: helper,
    helperStyle: AppType.meta(context),
    helperMaxLines: 2,
    errorText: errorText,
    errorStyle: AppType.meta(context).copyWith(color: c.danger, fontWeight: FontWeight.w500),
    errorMaxLines: 2,
    enabled: enabled,
    filled: true,
    fillColor: enabled ? c.inputBg : Color.alphaBlend(c.inputBg.withValues(alpha: 0.5), c.background),
    isDense: dense,
    // 48 high with a 15 px line at rest (a dense well is 40)
    contentPadding: EdgeInsetsDirectional.symmetric(
        horizontal: AppSpace.md, vertical: dense ? AppSpace.xs + 1 : AppSpace.sm + 1),
    border: border(c.fieldEdge),
    enabledBorder: border(c.fieldEdge),
    disabledBorder: border(c.divider.withValues(alpha: 0.6)),
    focusedBorder: border(focus, AppBorder.focus),
    errorBorder: border(c.danger),
    focusedErrorBorder: border(c.danger, AppBorder.focus),
  );
}

/// The older name of [appFieldDecoration] (kept for the identity fields' callers).
InputDecoration appInputDecoration(BuildContext context, {required String hint, required IconData icon, Widget? suffix}) =>
    appFieldDecoration(context, hint: hint, icon: icon, suffix: suffix);

/// The label ABOVE a well: `label` role (13 · 500, muted ink), 8 px under it. [required] adds a danger mark after
/// the text. Excluded from semantics: the field carries the label itself.
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel(this.text, {super.key, this.required = false, this.trailing});

  final String text;
  final bool required;

  /// A small widget at the end of the label line (a counter, a help button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppType.label(context);
    final label = Text.rich(
      TextSpan(text: text, children: [
        if (required) TextSpan(text: ' *', style: style.copyWith(color: c.danger, fontWeight: FontWeight.w600)),
      ]),
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: ExcludeSemantics(
        child: trailing == null
            ? label
            : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: label),
                const SizedBox(width: AppSpace.xs),
                trailing!,
              ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The fields
// ─────────────────────────────────────────────────────────────────────────────

/// The kit's plain text field: a label above the well, an optional hint inside it, helper / error under it, a
/// 12 px gap under the whole thing so fields stack with the form rhythm. [ltr] pins the text direction (an e-mail,
/// a code). [onSubmitted] is Enter (a multi-line field: Ctrl+Enter on web / desktop, see app_keyboard.dart).
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboard,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.ltr = false,
    this.icon,
    this.suffix,
    this.helper,
    this.errorText,
    this.required = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.obscureText = false,
    this.maxLength,
    this.inputFormatters,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool ltr;
  final IconData? icon;
  final Widget? suffix;
  final String? helper;

  /// Shown under the well in the danger ink (the well's border turns too).
  final String? errorText;
  final bool required;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool obscureText;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Semantics(
        container: true,
        label: label,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppFieldLabel(label, required: required),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            enabled: enabled,
            readOnly: readOnly,
            keyboardType: keyboard,
            maxLines: obscureText ? 1 : maxLines,
            maxLength: maxLength,
            obscureText: obscureText,
            inputFormatters: inputFormatters,
            autofillHints: autofillHints,
            textCapitalization: textCapitalization,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: textInputAction,
            textDirection: ltr ? TextDirection.ltr : null,
            style: appFieldTextStyle(context),
            decoration: appFieldDecoration(context,
                hint: hint, icon: icon, suffix: suffix, helper: helper, errorText: errorText, enabled: enabled),
          ),
        ]),
      ),
    );
  }
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
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Semantics(
        container: true,
        label: label,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppFieldLabel(label, required: widget.required),
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
            style: appFieldTextStyle(context),
            autovalidateMode: _touched ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            validator: (v) => validateEmail(v, required: widget.required),
            onChanged: (v) {
              setState(() => _touched = true);
              widget.onChanged?.call(v);
            },
            decoration: appFieldDecoration(context,
                hint: 'name@example.com',
                icon: Icons.alternate_email_rounded,
                enabled: widget.enabled,
                // a live check while typing: ✓ once it parses, a hint of attention before (never the danger tone,
                // the validator says what is wrong once the person leaves the field)
                suffix: value.isEmpty
                    ? null
                    : AnimatedSwitcher(
                        duration: AppMotion.of(context).fast,
                        child: Icon(
                          valid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          key: ValueKey(valid),
                          size: AppIconSize.md,
                          color: valid ? ensureContrast(c.success, [c.inputBg]) : ensureContrast(c.warning, [c.inputBg]),
                        ),
                      )),
          ),
        ]),
      ),
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
    this.minLength = 8,
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
    final label = widget.label ?? _t('كلمة المرور', 'Password');
    final okInk = ensureContrast(c.success, [c.background, c.cardBg]);
    final rules = <(bool, String)>[
      (v.length >= widget.minLength, _t('${widget.minLength} أحرف على الأقل', 'At least ${widget.minLength} characters')),
      (RegExp(r'[A-Z]').hasMatch(v), _t('حرف كبير واحد على الأقل (A-Z)', 'One uppercase letter (A-Z)')),
      (RegExp(r'\d').hasMatch(v), _t('رقم واحد على الأقل', 'One number')),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Semantics(
        container: true,
        label: label,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppFieldLabel(label, required: widget.required),
          TextFormField(
            controller: widget.controller,
            enabled: widget.enabled,
            obscureText: _hidden,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            style: appFieldTextStyle(context),
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
            decoration: appFieldDecoration(context,
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                enabled: widget.enabled,
                suffix: IconButton(
                  tooltip: _hidden ? _t('إظهار كلمة المرور', 'Show password') : _t('إخفاء كلمة المرور', 'Hide password'),
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: AppIconSize.md, color: c.textLight),
                )),
          ),
          if (widget.showStrength && v.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            for (final (ok, text) in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                child: Row(children: [
                  AnimatedSwitcher(
                    duration: AppMotion.of(context).fast,
                    child: Icon(
                      ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(ok),
                      size: AppIconSize.sm,
                      color: ok ? okInk : c.textLight,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(text, style: AppType.meta(context).copyWith(color: ok ? okInk : c.textMedium))),
                ]),
              ),
          ],
        ]),
      ),
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
  Widget build(BuildContext context) {
    final text = label ?? _t('الموقع الإلكتروني', 'Website');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Semantics(
        container: true,
        label: text,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppFieldLabel(text, required: required),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            style: appFieldTextStyle(context),
            validator: (v) {
              final s = normalize(v ?? '');
              if (s.isEmpty) return required ? _t('الرابط مطلوب', 'The link is required') : null;
              final u = Uri.tryParse(s);
              return (u == null || !u.hasAuthority || !u.host.contains('.')) ? _t('رابط غير صحيح', 'Invalid link') : null;
            },
            onEditingComplete: () => controller.text = normalize(controller.text),
            decoration: appFieldDecoration(context, hint: 'https://example.com', icon: Icons.language_rounded),
          ),
        ]),
      ),
    );
  }
}
