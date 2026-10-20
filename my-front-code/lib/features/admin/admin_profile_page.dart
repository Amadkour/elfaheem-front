// lib/features/admin/admin_profile_page.dart
//
// The signed-in admin's own account. Every field is editable EXCEPT the
// e-mail, which only the super-admin can change (the field is read-only for a
// normal admin and the server must reject an e-mail change from them too).
//
// The profile PICTURE works exactly like the normal user's: it is picked with
// EditableImage, held by ProfileProvider and uploaded with
// ProfileProvider.uploadImage() (same endpoint as students / teachers).
//
// Text fields use GET / PUT /api/v1/admin/me (admin_panel.py). The server
// rejects an e-mail change from anyone who is not a super-admin.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/editable_image.dart';
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

  late final List<TextEditingController> _all = [
    _name,
    _email,
    _phone,
    _country,
    _dob,
    _password,
    _confirm,
  ];

  Map<String, dynamic> _original = {};
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  bool get _isSuper => isSuperNow(context);

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().initData(
        context.read<MyAuthProvider>().currentUser,
      );
    });
    _load();
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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

  // ── What changed? ─────────────────────────────────────────────────────────
  /// Only the text fields that differ from what the server returned.
  Map<String, dynamic> _changedFields() {
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
    return body;
  }

  bool get _hasNewImage => context.read<ProfileProvider>().imageByte != null;

  bool get _dirty => !_loading && !_failed && (_changedFields().isNotEmpty || _hasNewImage);

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;

    final p = context.read<ProfileProvider>();
    final auth = context.read<MyAuthProvider>();
    final body = _changedFields();
    final hasImage = p.imageByte != null;

    if (body.isEmpty && !hasImage) {
      toast('admin_nothing_to_update'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      // 1. Picture first (same call the normal user's edit screen makes).
      if (p.imageFile != null) {
        final updated = await p.uploadImage();
        if (updated != null) {
          await auth.saveUserLocally(updated);
          p.initData(auth.currentUser);
        }
      }

      // 2. Text fields.
      if (body.isNotEmpty) {
        await _api.put(_ProfileApi.me, body: body);
        _password.clear();
        _confirm.clear();
        await _load();
      }
      toast('admin_profile_saved'.tr);
    } catch (e) {
      toast(ApiException.from(e).message, error: true);
    }
    if (!mounted) return;
    setState(() => _saving = false);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;

    Widget body;
    if (_loading) {
      body = const Center(child: AppLoadingIndicator());
    } else if (_failed) {
      body = ErrorRetry(message: 'admin_could_not_load_data'.tr, onRetry: _load);
    } else {
      body = Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    _buildHero(context),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      child: Column(
                        children: [
                          _buildPersonalCard(context),
                          const SizedBox(height: 16),
                          _buildContactCard(context),
                          const SizedBox(height: 16),
                          _buildSecurityCard(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildSaveBar(context, dirty),
        ],
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 700,
      appBar: ScreenAppBar(title: 'admin_my_account'.tr),
      child: body,
    );
  }

  // Gradient header: picture (tap to change), name, e-mail, role.
  Widget _buildHero(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    final name = _name.text.trim();
    final isSuperRole = asStr(_original['role']) == 'super-admin';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // White ring around the picture.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: EditableImage(
              onChange: (f) async {
                await p.changeImage(f);
                if (mounted) setState(() {});
              },
              imageFile: p.imageFile,
              imageByte: p.imageByte,
              imageUrl: p.imageUrl,
              size: 104,
              isCircle: true,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name.isEmpty ? '—' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'tajawal',
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _email.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuperRole
                      ? Icons.verified_user_rounded
                      : Icons.admin_panel_settings_rounded,
                  size: 15,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  isSuperRole
                      ? 'admin_role_super_admin'.tr
                      : 'admin_role_admin'.tr,
                  style: const TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'admin_tap_photo_to_change'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalCard(BuildContext context) {
    final isSuper = _isSuper;
    final c = context.colors;
    return _SectionCard(
      icon: Icons.person_rounded,
      title: 'admin_section_personal'.tr,
      children: [
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
          validator: (v) => (v == null || !v.contains('@') || !v.contains('.'))
              ? 'admin_invalid_email'.tr
              : null,
        ),
        if (!isSuper)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: c.textLight),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'admin_email_super_only_hint'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      color: c.textLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        GestureDetector(
          onTap: _pickDob,
          child: AbsorbPointer(
            child: Field(controller: _dob, label: 'dob_label'.tr, ltr: true),
          ),
        ),
      ],
    );
  }

  Widget _buildContactCard(BuildContext context) {
    return _SectionCard(
      icon: Icons.call_rounded,
      title: 'admin_section_contact'.tr,
      children: [
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
      ],
    );
  }

  Widget _buildSecurityCard(BuildContext context) {
    return _SectionCard(
      icon: Icons.lock_rounded,
      title: 'admin_section_security'.tr,
      children: [
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
      ],
    );
  }

  // Sticky save bar: enabled only when something actually changed.
  Widget _buildSaveBar(BuildContext context, bool dirty) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              opacity: dirty || _saving ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: PrimaryButton(
                label: 'save_changes'.tr,
                isLoading: _saving,
                onPressed: dirty ? _save : null,
              ),
            ),
            if (!dirty && !_saving) ...[
              const SizedBox(height: 6),
              Text('no_changes_yet'.tr, style: c.caption),
            ],
          ],
        ),
      ),
    );
  }
}

// ── A titled card that groups related fields ─────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: c.brLarge,
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: c.primary),
              ),
              const SizedBox(width: 10),
              Text(title, style: c.h3),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}