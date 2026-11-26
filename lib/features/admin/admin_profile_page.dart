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
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/editable_image.dart';
import 'admin_common.dart';
import 'admin_page.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppCard, AppListSkeleton;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_states.dart' show AppErrorState, appErrorMessage;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'sup/sup_kit.dart';

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
  String? _error;

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
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var data = asMap(await _api.get(_ProfileApi.me));
      // the page may have been closed while the request was in flight: the controllers are disposed then
      if (!mounted) return;
      if (data['user'] is Map) data = asMap(data['user']);
      _original = data;
      _name.text = asStr(data['name']);
      _email.text = asStr(data['gmail']);
      _phone.text = asStr(data['phone']);
      _country.text = asStr(data['country']);
      _dob.text = _dateOnly(asStrOrNull(data['dob']));
    } catch (e) {
      if (!mounted) return;
      _failed = true;
      _error = appErrorMessage(e);
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
        if (!mounted) return; // closed meanwhile: the controllers are disposed
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
      body = const AppListSkeleton();
    } else if (_failed) {
      body = AppErrorState(message: _error, onRetry: _load);
    } else {
      body = SingleChildScrollView(
        padding: AdminPage.bodyPadding(context),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIdentity(context),
              const SizedBox(height: AppSpace.md),
              _buildPersonalCard(context),
              const SizedBox(height: AppSpace.md),
              _buildContactCard(context),
              const SizedBox(height: AppSpace.md),
              _buildSecurityCard(context),
            ],
          ),
        ),
      );
    }

    return SupPage(
        kicker: 'a2_account_kicker'.tr, headline: 'a2_account_head'.tr,
        title: 'admin_my_account'.tr,
        dirty: dirty,
        body: body,
        actions: [?(_loading || _failed
          ? null
          : AppButton.primary(
              key: const ValueKey('profile_save'),
              label: 'save_changes'.tr,
              icon: Icons.check_rounded,
              busy: _saving,
              onPressed: dirty ? _save : null,
            ))],
      );
  }

  // Picture (tap to change), name, e-mail and role on a calm card.
  Widget _buildIdentity(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    final name = _name.text.trim();
    final isSuperRole = asStr(_original['role']) == 'super-admin';

    return AppCard(
      child: Column(
        children: [
          EditableImage(
            onChange: (f) async {
              await p.changeImage(f);
              if (mounted) setState(() {});
            },
            imageFile: p.imageFile,
            imageByte: p.imageByte,
            imageUrl: p.imageUrl,
            size: 104,
            isCircle: true,
            name: name, // no photo: the initial, as every other avatar
            onRemove: () async {
              // Remove picture (D-880): a stored one is deleted at once, the account saved for every avatar
              final auth = context.read<MyAuthProvider>();
              try {
                final updated = await p.removeImage();
                if (updated != null) await auth.saveUserLocally(updated);
                showAppNotice('avatar_removed'.tr);
              } catch (e) {
                showAppNotice(ApiException.from(e).message, error: true);
              }
              if (mounted) setState(() {});
            },
            removeMessage: 'avatar_remove_confirm'.tr,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            name.isEmpty ? '—' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.section(context),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            _email.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: AppType.meta(context),
          ),
          const SizedBox(height: AppSpace.xs),
          AppStatusBadge(
            label: isSuperRole ? 'admin_role_super_admin'.tr : 'admin_role_admin'.tr,
            tone: isSuperRole ? AppTone.brand : AppTone.info,
            icon: isSuperRole ? Icons.verified_user_rounded : Icons.admin_panel_settings_rounded,
          ),
          const SizedBox(height: AppSpace.xs),
          Text('admin_tap_photo_to_change'.tr, style: AppType.meta(context).copyWith(color: c.textLight)),
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
        AppEmailField(controller: _email, label: 'admin_email'.tr, enabled: isSuper),
        if (!isSuper)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: AppIconSize.xs, color: c.textLight),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text('admin_email_super_only_hint'.tr, style: AppType.meta(context))),
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
        AppPhoneField(controller: _phone, label: 'admin_phone'.tr),
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
        AppPasswordField(controller: _password, label: 'admin_new_password_optional'.tr, required: false),
        AppPasswordField(controller: _confirm, label: 'confirm_new_password'.tr, mustMatch: _password),
      ],
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Icon(icon, size: AppIconSize.md, color: c.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: Text(title, style: AppType.section(context))),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          ...children,
        ],
      ),
    );
  }
}
