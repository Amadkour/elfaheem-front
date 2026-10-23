// lib/features/org/org_application_screen.dart — an institution asks to join the platform (no login yet).
//
// POST /api/v1/org/applications creates an UNVERIFIED org-admin account and a PENDING organization and e-mails a code.
// Next: verify the e-mail (OtpVerificationScreen) → log in → the dashboard shows the review status
// (OrgStatusScreen) until the platform team approves; no management screen opens before that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppEmpty;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../admin/admin_common.dart';
import 'org_common.dart';
import 'org_creation_fee.dart';
import 'org_ui.dart';
import 'org_v3.dart';

/// Local password rule = the server's (8+ characters, letters AND digits).
String? orgPasswordProblem(String p) {
  if (p.length < 8) return t('8 أحرف على الأقل', 'At least 8 characters');
  if (!RegExp(r'[A-Za-z؀-ۿ]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
    return orgCodeText('weak_password');
  }
  return null;
}

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
  // creation fee (super-admin setting): the request can be sent only once a usable payment exists
  bool _feeOk = true;
  String? _feeToken;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _pass, _pass2, _ar, _en, _desc, _license, _orgEmail, _orgPhone, _website, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _check() {
    if (_name.text.trim().length < 2) return t('اكتب اسمك', 'Enter your name');
    if (!_email.text.contains('@')) return t('أدخل بريداً صحيحاً', 'Enter a valid e-mail');
    final pw = orgPasswordProblem(_pass.text);
    if (pw != null) return pw;
    if (_pass.text != _pass2.text) return t('كلمتا المرور غير متطابقتين', 'The passwords don\'t match');
    if (_ar.text.trim().isEmpty && _en.text.trim().isEmpty) return t('اكتب اسم المؤسسة', 'Enter the organization\'s name');
    if (!_feeOk) return orgCodeText('org_fee_required');
    return null;
  }

  Future<void> _submit() async {
    final local = _check();
    if (local != null) return setState(() => _error = local);
    setState(() {
      _busy = true;
      _error = null;
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
    if (!r.ok) return setState(() => _error = orgErrorText(r.error!));
    if (r.map['verification_sent'] != true) {
      toast(t('أُرسل الطلب، لكن تعذّر إرسال كود التحقق الآن — اطلب كوداً جديداً في الشاشة التالية.',
          'Application sent, but the code could not be e-mailed right now — ask for a new one on the next screen.'));
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(email: email, role: 'org-admin', channels: const ['email'])));
  }

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
    Text label(String s) => Text(s, style: orgText(context, size: 13, w: FontWeight.w800, color: c.textMedium));
    return BasePage(
      useWebCard: true,
      maxWith: 720,
      appBar: ScreenAppBar(title: t('تسجيل مؤسسة تعليمية', 'Register an institution')),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18)),
          child: Text(
              t('١) أرسل الطلب  ٢) أكّد بريدك بالكود  ٣) يراجع فريق المنصة بيانات المؤسسة. لا تُفتح لوحة الإدارة قبل الاعتماد، ويمكنك تعديل الطلب أثناء المراجعة.',
                  '1) Send the application  2) Confirm your e-mail with the code  3) The platform team reviews the institution. The dashboard opens only after approval; you can edit the application meanwhile.'),
              style: orgText(context, size: 12.5)),
        ),
        const SizedBox(height: 16),
        label(t('بياناتك (مدير المؤسسة)', 'You (the organization admin)')),
        const SizedBox(height: 8),
        Field(controller: _name, label: t('الاسم الكامل', 'Full name')),
        AppEmailField(controller: _email, label: t('البريد الإلكتروني', 'E-mail')),
        AppPhoneField(controller: _phone, label: t('الهاتف (اختياري)', 'Phone (optional)')),
        Field(controller: _pass, label: t('كلمة المرور (حروف وأرقام، 8+)', 'Password (letters and digits, 8+)'), obscure: true, ltr: true),
        Field(controller: _pass2, label: t('تأكيد كلمة المرور', 'Confirm the password'), obscure: true, ltr: true),
        const SizedBox(height: 12),
        label(t('المؤسسة', 'The institution')),
        const SizedBox(height: 8),
        Field(controller: _ar, label: t('الاسم بالعربية', 'Arabic name')),
        Field(controller: _en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
        ChoiceRow<String>(label: t('النوع', 'Type'), options: orgTypeLabels(), value: _type, onChanged: (v) => setState(() => _type = v)),
        const SizedBox(height: 10),
        Field(controller: _desc, label: t('نبذة (اختياري)', 'About (optional)'), maxLines: 3),
        Text(t('بيانات رسمية — تسرّع الاعتماد', 'Official details — they speed up approval'), style: orgText(context, size: 12, color: c.textLight)),
        const SizedBox(height: 6),
        Field(controller: _license, label: t('رقم القرار / الترخيص', 'Decree / licence number')),
        AppEmailField(controller: _orgEmail, label: t('البريد الرسمي', 'Official e-mail')),
        AppPhoneField(controller: _orgPhone, label: t('هاتف التواصل', 'Contact phone')),
        Field(controller: _website, label: t('الموقع الإلكتروني', 'Website'), ltr: true),
        Field(controller: _address, label: t('العنوان', 'Address')),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Text(_error!, style: orgText(context, size: 12.5, color: c.danger)),
          ),
        OrgCreationFeePanel(
          email: () => _email.text,
          onReady: (ok, token) {
            if (!mounted) return;
            setState(() {
              _feeOk = ok;
              _feeToken = token;
            });
          },
        ),
        PrimaryButton(isLoading: _busy, label: t('إرسال الطلب', 'Send the application'), icon: Icons.send_rounded, iconBefore: true, onPressed: _busy ? null : _submit),
      ]),
    );
  }
}

const orgApplicationsPath = '/api/v1/org/applications';
