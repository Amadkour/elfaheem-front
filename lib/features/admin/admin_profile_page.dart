// lib/features/admin/admin_profile_page.dart
//
// The signed-in admin's own account. Every field is editable EXCEPT the
// e-mail, which only the super-admin can change (the field is read-only for a
// normal admin and the server must reject an e-mail change from them too).
//
// Uses GET / PUT /api/v1/admin/me (added to admin_panel.py). The server rejects
// an e-mail change from anyone who is not a super-admin.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';

class _ProfileApi {
  static const me = '/api/v1/admin/me';
}

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final _api = ApiClient();
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _dob = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  Map<String, dynamic> _original = {};
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  bool get _isSuper => isSuperNow(context);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _country, _dob, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var data = asMap(await _api.get(_ProfileApi.me));
      if (data['user'] is Map) data = asMap(data['user']);
      _original = data;
      _name.text = asStr(data['name']);
      _email.text = asStr(data['gmail']);
      _phone.text = asStr(data['phone']);
      _country.text = asStr(data['country']);
      _dob.text = _dateOnly(asStrOrNull(data['dob']));
    } catch (e) {
      _failed = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  String _dateOnly(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dob.text) ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) _dob.text = _dateOnly(picked.toIso8601String());
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    final body = <String, dynamic>{};
    void put(String key, String value, String original) {
      if (value.trim() != original.trim()) {
        body[key] = value.trim().isEmpty ? null : value.trim();
      }
    }

    put('name', _name.text, asStr(_original['name']));
    put('phone', _phone.text, asStr(_original['phone']));
    put('country', _country.text, asStr(_original['country']));
    put('dob', _dob.text, _dateOnly(asStrOrNull(_original['dob'])));
    // Only the super-admin may change the e-mail.
    if (_isSuper && _email.text.trim() != asStr(_original['gmail']).trim()) {
      body['gmail'] = _email.text.trim();
    }
    if (_password.text.isNotEmpty) body['password'] = _password.text;

    if (body.isEmpty) {
      toast('admin_nothing_to_update'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      await _api.put(_ProfileApi.me, body: body);
      toast('admin_profile_saved'.tr);
      _password.clear();
      _confirm.clear();
      await _load();
    } catch (e) {
      toast(ApiException.from(e).message, error: true);
    }
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isSuper = _isSuper;
    final name = _name.text;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed) {
      body = ErrorRetry(message: 'admin_could_not_load_data'.tr, onRetry: _load);
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Form(
          key: _form,
          child: Column(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: c.primary.withValues(alpha: 0.15),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              StatusChip(
                asStr(_original['role']) == 'super-admin'
                    ? 'admin_role_super_admin'.tr
                    : 'admin_role_admin'.tr,
                c.primary,
              ),
              const SizedBox(height: 18),
              Field(
                controller: _name,
                label: 'name_label'.tr,
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'admin_name_is_required'.tr
                    : null,
              ),
              Field(
                controller: _email,
                label: 'admin_email'.tr,
                keyboard: TextInputType.emailAddress,
                ltr: true,
                enabled: isSuper,
                validator: (v) =>
                (v == null || !v.contains('@') || !v.contains('.'))
                    ? 'admin_invalid_email'.tr
                    : null,
              ),
              if (!isSuper)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'admin_email_super_only_hint'.tr,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 12,
                        color: c.textLight,
                      ),
                    ),
                  ),
                ),
              Field(
                controller: _phone,
                label: 'admin_phone'.tr,
                keyboard: TextInputType.phone,
                ltr: true,
              ),
              Field(
                controller: _country,
                label: 'admin_country_code'.tr,
                ltr: true,
              ),
              GestureDetector(
                onTap: _pickDob,
                child: AbsorbPointer(
                  child: Field(
                    controller: _dob,
                    label: 'dob_label'.tr,
                    ltr: true,
                  ),
                ),
              ),
              Field(
                controller: _password,
                label: 'admin_new_password_optional'.tr,
                obscure: true,
                validator: (v) => (v == null || v.isEmpty || v.length >= 6)
                    ? null
                    : 'admin_at_least_6_characters'.tr,
              ),
              Field(
                controller: _confirm,
                label: 'confirm_new_password'.tr,
                obscure: true,
                validator: (v) =>
                (v ?? '') == _password.text ? null : 'password_mismatch'.tr,
              ),
              const SizedBox(height: 4),
              PrimaryButton(
                label: 'save_changes'.tr,
                isLoading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 700,
      appBar: ScreenAppBar(title: 'admin_my_account'.tr),
      child: body,
    );
  }
}