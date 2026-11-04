// lib/features/org/org_application_screen.dart — an institution asks to join the platform (no login yet).
//
// POST /api/v1/org/applications creates an UNVERIFIED org-admin account and a PENDING organization and e-mails a code.
// Next: verify the e-mail (OtpVerificationScreen) → log in → the dashboard shows the review status
// (OrgStatusScreen) until the platform team approves; no management screen opens before that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart';
import 'org_common.dart';
import 'org_creation_fee.dart';
import 'org_v3.dart';

/// Local password rule = the server's (8+ characters, letters AND digits).
String? orgPasswordProblem(String p) {
  if (p.length < 8) return t('8 أحرف على الأقل', 'At least 8 characters');
  if (!RegExp(r'[A-Za-z؀-ۿ]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
    return orgCodeText('weak_password');
  }
  return null;
}

/// Field-level problems of the application, keyed by field (`name`, `email`, `password`, `password2`, `org_name`,
/// `org_email`, `fee`). Empty = the form may be sent. Pure: the screen only draws it.
Map<String, String> orgApplicationErrors({
  required String name,
  required String email,
  required String password,
  required String password2,
  required String nameAr,
  required String nameEn,
  required String orgEmail,
  required bool feeOk,
}) {
  final e = <String, String>{};
  if (name.trim().length < 2) e['name'] = t('اكتب اسمك', 'Enter your name');
  if (validateEmail(email) != null) e['email'] = t('أدخل بريداً صحيحاً', 'Enter a valid e-mail');
  final pw = orgPasswordProblem(password);
  if (pw != null) e['password'] = pw;
  if (password != password2) e['password2'] = t('كلمتا المرور غير متطابقتين', 'The passwords don\'t match');
  if (nameAr.trim().isEmpty && nameEn.trim().isEmpty) e['org_name'] = t('اكتب اسم المؤسسة', 'Enter the organization\'s name');
  if (orgEmail.trim().isNotEmpty && validateEmail(orgEmail) != null) e['org_email'] = t('أدخل بريداً رسمياً صحيحاً', 'Enter a valid official e-mail');
  if (!feeOk) e['fee'] = orgCodeText('org_fee_required');
  return e;
}

/// The field a refused submit belongs to (so the server's text shows under it, not only at the bottom).
String? orgApplicationErrorField(String? code) => switch (code) {
      'email_taken' || 'email_exists' || 'invalid_email' => 'email',
      'weak_password' => 'password',
      'org_fee_required' => 'fee',
      _ => null,
    };

class OrgApplicationScreen extends StatefulWidget {
  const OrgApplicationScreen({super.key});

  @override
  State<OrgApplicationScreen> createState() => _OrgApplicationScreenState();
}

class _OrgApplicationScreenState extends State<OrgApplicationScreen> {
  final _name = TextEditingController(), _email = TextEditingController(), _phone = TextEditingController();
  final _pass = TextEditingController(), _pass2 = TextEditingController();
  final _ar = TextEditingController(), _en = TextEditingController(), _desc = TextEditingController();
  final _license = TextEditingController(), _orgEmail = TextEditingController(), _orgPhone = TextEditingController();
  final _website = TextEditingController(), _address = TextEditingController();
  String _type = 'university';
  bool _busy = false;
  String? _error;
  Map<String, String> _errors = {};
  final _keys = <String, GlobalKey>{};
  // creation fee (super-admin setting): the request can be sent only once a usable payment exists
  bool _feeOk = true;
  String? _feeToken;

  GlobalKey _k(String f) => _keys.putIfAbsent(f, GlobalKey.new);

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _pass, _pass2, _ar, _en, _desc, _license, _orgEmail, _orgPhone, _website, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _check() => orgApplicationErrors(
      name: _name.text, email: _email.text, password: _pass.text, password2: _pass2.text,
      nameAr: _ar.text, nameEn: _en.text, orgEmail: _orgEmail.text, feeOk: _feeOk);

  void _showErrors(Map<String, String> errs, {String? summary}) {
    setState(() {
      _errors = errs;
      _error = summary ?? (errs.isEmpty ? null : t('راجع الحقول المعلَّمة بالأحمر', 'Check the fields marked in red'));
    });
    // bring the first problem into view
    const order = ['name', 'email', 'password', 'password2', 'org_name', 'org_email', 'fee'];
    for (final f in order) {
      final ctx = errs.containsKey(f) ? _keys[f]?.currentContext : null;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: AppMotion.of(context).base, alignment: 0.1);
        break;
      }
    }
  }

  Future<void> _submit() async {
    final local = _check();
    if (local.isNotEmpty) return _showErrors(local);
    setState(() {
      _busy = true;
      _error = null;
      _errors = {};
    });
    String? txt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final email = _email.text.trim().toLowerCase();
    final r = await orgCall(
        () => ApiClient().post(orgApplicationsPath, auth: false, body: {
              'name': _name.text.trim(),
              'email': email,
              'phone': ?txt(_phone),
              'password': _pass.text,
              'organization': {
                'name_ar': ?txt(_ar),
                'name_en': ?txt(_en),
                'type': _type,
                'description': ?txt(_desc),
                'license_no': ?txt(_license),
                'contact_email': ?txt(_orgEmail),
                'contact_phone': ?txt(_orgPhone),
                'website': ?txt(_website),
                'address': ?txt(_address),
              },
              'fee_token': ?_feeToken,
            }),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      final text = orgErrorText(r.error!);
      final field = orgApplicationErrorField(r.code);
      return _showErrors(field == null ? {} : {field: text}, summary: text);
    }
    if (r.map['verification_sent'] != true) {
      toast(t('أُرسل الطلب، لكن تعذّر إرسال كود التحقق الآن — اطلب كوداً جديداً في الشاشة التالية.',
          'Application sent, but the code could not be e-mailed right now — ask for a new one on the next screen.'));
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(email: email, role: 'org-admin', channels: const ['email'])));
  }

  Widget _err(String f) {
    final m = _errors[f];
    if (m == null) return SizedBox.shrink(key: _k(f));
    return Padding(
      key: _k(f),
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Text(m, style: AppType.meta(context).copyWith(color: context.colors.danger)),
    );
  }

  Widget _section(String title, String? subtitle, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSection(title: title, subtitle: subtitle, child: const SizedBox.shrink()),
            AppSpace.gapSm,
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!AppConfig.orgsEnabled) {
      return BasePage(
        appBar: ScreenAppBar(title: t('تسجيل مؤسسة تعليمية', 'Register an institution')),
        child: AppEmpty(
            icon: Icons.domain_disabled_rounded,
            title: t('تسجيل المؤسسات متوقف حالياً', 'Institution sign-up is paused'),
            message: t('أوقفت إدارة المنصة خدمة المؤسسات مؤقتاً. جرّب لاحقاً.', 'The platform team has paused organizations for now. Please try again later.')),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 720,
      appBar: ScreenAppBar(title: t('تسجيل مؤسسة تعليمية', 'Register an institution')),
      child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
        AppBanner(
            icon: Icons.info_outline_rounded,
            text: t('١) أرسل الطلب  ٢) أكّد بريدك بالكود  ٣) يراجع فريق المنصة بيانات المؤسسة. لا تُفتح لوحة الإدارة قبل الاعتماد، ويمكنك تعديل الطلب أثناء المراجعة.',
                '1) Send the application  2) Confirm your e-mail with the code  3) The platform team reviews the institution. The dashboard opens only after approval; you can edit the application meanwhile.')),
        AppSpace.gapMd,
        _section(t('بياناتك (مدير المؤسسة)', 'You (the organization admin)'), null, [
          _LabeledInput(controller: _name, label: t('الاسم الكامل', 'Full name'), icon: Icons.person_outline_rounded, error: _errors['name'], fieldKey: _k('name')),
          AppEmailField(controller: _email, label: t('البريد الإلكتروني', 'E-mail')),
          _err('email'),
          // the phone field has no space under it of its own (M21: phone / password / confirm were glued together)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppPhoneField(controller: _phone, label: t('الهاتف (اختياري)', 'Phone (optional)')),
          ),
          AppPasswordField(controller: _pass, label: t('كلمة المرور (حروف وأرقام، 8+)', 'Password (letters and digits, 8+)')),
          _err('password'),
          AppPasswordField(controller: _pass2, mustMatch: _pass, label: t('تأكيد كلمة المرور', 'Confirm the password')),
          _err('password2'),
        ]),
        _section(t('المؤسسة', 'The institution'), t('اكتب الاسم بلغة واحدة على الأقل', 'The name in at least one language'), [
          _LabeledInput(controller: _ar, label: t('الاسم بالعربية', 'Arabic name'), icon: Icons.account_balance_outlined, error: _errors['org_name'], fieldKey: _k('org_name')),
          _LabeledInput(controller: _en, label: t('الاسم بالإنجليزية', 'English name'), icon: Icons.account_balance_outlined, ltr: true),
          ChoiceRow<String>(label: t('النوع', 'Type'), options: orgTypeLabels(), value: _type, onChanged: (v) => setState(() => _type = v)),
          AppSpace.gapSm,
          _LabeledInput(controller: _desc, label: t('نبذة (اختياري)', 'About (optional)'), icon: Icons.notes_rounded, maxLines: 3),
        ]),
        _section(t('بيانات رسمية', 'Official details'), t('اختيارية — لكنها تسرّع الاعتماد', 'Optional — but they speed up approval'), [
          _LabeledInput(controller: _license, label: t('رقم القرار / الترخيص', 'Decree / licence number'), icon: Icons.verified_outlined),
          AppEmailField(controller: _orgEmail, label: t('البريد الرسمي', 'Official e-mail'), required: false),
          _err('org_email'),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppPhoneField(controller: _orgPhone, label: t('هاتف التواصل', 'Contact phone')),
          ),
          _LabeledInput(controller: _website, label: t('الموقع الإلكتروني', 'Website'), icon: Icons.language_rounded, ltr: true),
          _LabeledInput(controller: _address, label: t('العنوان', 'Address'), icon: Icons.place_outlined),
        ]),
        OrgCreationFeePanel(
          email: () => _email.text,
          onReady: (ok, token) {
            if (!mounted) return;
            setState(() {
              _feeOk = ok;
              _feeToken = token;
              if (ok) _errors = {..._errors}..remove('fee');
            });
          },
        ),
        _err('fee'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
          ),
        AppButton.primary(label: t('إرسال الطلب', 'Send the application'), icon: Icons.send_rounded, expand: true, busy: _busy, onPressed: _busy ? null : _submit),
      ]),
    );
  }
}

/// A text field with its name above it, the same shape as [AppEmailField] / [AppPasswordField] (M21), with an
/// inline error under it.
class _LabeledInput extends StatelessWidget {
  const _LabeledInput({required this.controller, required this.label, required this.icon, this.ltr = false, this.maxLines = 1, this.error, this.fieldKey});

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool ltr;
  final int maxLines;
  final String? error;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(label, style: AppType.label(context)),
        ),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          textDirection: ltr ? TextDirection.ltr : null,
          style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, color: c.textDark),
          decoration: appInputDecoration(context, hint: label, icon: icon).copyWith(errorText: error),
        ),
      ]),
    );
  }
}

const orgApplicationsPath = '/api/v1/org/applications';
