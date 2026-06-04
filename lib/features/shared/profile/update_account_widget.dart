/// ─────────────────────────────────────────────────────────────────────────────
/// edit_account_screen.dart
/// Shared premium edit-account screen for both student and teacher.
///
/// Layout:
///   Mobile  → scrollable column: hero header (avatar + name) → form card
///   Web     → two-column: left sticky profile card / right scrollable form
///
/// Usage:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const EditAccountScreen(),          // student
///   ));
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const EditAccountScreen(isTeacher: true),  // teacher
///   ));
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/editable_image.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../../utils/widget/text_field.dart';
import '../../auth/auth_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';

class EditAccountScreen extends StatefulWidget {
  final bool isTeacher;
  const EditAccountScreen({super.key, this.isTeacher = false});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl   = TextEditingController();
  final _bioCtrl   = TextEditingController();

  late ProfileProvider _p;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _p = context.read<ProfileProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameCtrl.text  = _p.name;
      _emailCtrl.text = _p.email;
      _phoneCtrl.text = _p.phone;
      _dobCtrl.text   = _p.dob;
      _bioCtrl.text   = _p.bio;
      setState(() {});
    });

    for (final c in [_nameCtrl, _phoneCtrl, _dobCtrl, _bioCtrl]) {
      c.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _phoneCtrl, _dobCtrl, _bioCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Has anything changed? ─────────────────────────────────────────────────
  bool get _isChanged =>
      _nameCtrl.text  != _p.name  ||
          _phoneCtrl.text != _p.phone ||
          _dobCtrl.text   != _p.dob   ||
          _bioCtrl.text   != _p.bio   ||
          _p.imageByte    != null;

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_isChanged || _saving) return;
    if (mounted) setState(() => _saving = true);

    try {
      // 1. Upload image first (if changed)
      if (_p.imageFile != null) {
        final updated = await _p.uploadImage();
        if (updated != null && mounted) {
          await context.read<AuthProvider>().saveUserLocally(updated);
        }
      }

      // 2. Update profile fields (if changed)
      final fieldsChanged =
          _nameCtrl.text  != _p.name  ||
              _phoneCtrl.text != _p.phone ||
              _dobCtrl.text   != _p.dob   ||
              _bioCtrl.text   != _p.bio;

      if (fieldsChanged) {
        final user = await _p.updateProfile(
          name:  _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          dob:   _dobCtrl.text.trim(),
          bio:   _bioCtrl.text.trim(),
        );
        if (user != null && mounted) {
          await context.read<AuthProvider>().saveUserLocally(user);
          _p.initData(context.read<AuthProvider>().currentUser);
        }
      }

      if (mounted) {
        _showSnack('changes_saved'.tr, context.colors.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _showSnack(e.toString(), context.colors.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ));

  @override
  Widget build(BuildContext context) {
    final p      = context.watch<ProfileProvider>();
    final c      = context.colors;
    final isWide = context.showSidebar;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        child: SafeArea(
          child: Column(
            children: [
              // ── App bar ────────────────────────────────────────────────────
              if (isWide) ScreenAppBar(title: 'update_account'.tr),

              // ── Body ───────────────────────────────────────────────────────
              Expanded(
                child: isWide
                    ? _webLayout(p, c)
                    : _mobileLayout(p, c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WEB LAYOUT — left sticky profile card + right scrollable form
  // ══════════════════════════════════════════════════════════════════════════

  Widget _webLayout(ProfileProvider p, AppColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left: sticky profile card ──────────────────────────────────────
        SizedBox(
          width: 300,
          child: _ProfileSideCard(
              p: p, c: c, isTeacher: widget.isTeacher),
        ),

        // ── Divider ────────────────────────────────────────────────────────
        VerticalDivider(width: 1, color: c.divider),

        // ── Right: form ────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _FormCard(
                  p: p,
                  c: c,
                  nameCtrl:  _nameCtrl,
                  emailCtrl: _emailCtrl,
                  phoneCtrl: _phoneCtrl,
                  dobCtrl:   _dobCtrl,
                  bioCtrl:   _bioCtrl,
                  isChanged: _isChanged,
                  isSaving:  _saving,
                  onSave:    _save,
                  onImageChange: (f) async {
                    await p.changeImage(f);
                    setState(() {});
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT — hero header + form
  // ══════════════════════════════════════════════════════════════════════════

  Widget _mobileLayout(ProfileProvider p, AppColors c) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // ── Hero header ────────────────────────────────────────────────
          _MobileHero(
              p: p,
              c: c,
              onImageChange: (f) async {
                await p.changeImage(f);
                setState(() {});
              }),

          // ── Form ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: _FormCard(
              p: p,
              c: c,
              nameCtrl:  _nameCtrl,
              emailCtrl: _emailCtrl,
              phoneCtrl: _phoneCtrl,
              dobCtrl:   _dobCtrl,
              bioCtrl:   _bioCtrl,
              isChanged: _isChanged,
              isSaving:  _saving,
              onSave:    _save,
              showAvatar: false, // avatar is in the hero, not the card
              onImageChange: (f) async {
                await p.changeImage(f);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _ProfileSideCard (web only)
// ═════════════════════════════════════════════════════════════════════════════

class _ProfileSideCard extends StatelessWidget {
  final ProfileProvider p;
  final AppColors c;
  final bool isTeacher;

  const _ProfileSideCard({
    required this.p,
    required this.c,
    required this.isTeacher,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: c.cardBg,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // ── Avatar ──────────────────────────────────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              // Glow ring
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: c.primaryGradient,
                  boxShadow: c.primaryShadow,
                ),
              ),
              // Avatar
              _AvatarCircle(p: p, c: c, size: 96),
            ],
          ),
          const SizedBox(height: 16),

          // ── Name ────────────────────────────────────────────────────────
          Text(
            p.name.isNotEmpty ? p.name : 'your_name_placeholder'.tr,
            style: c.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(p.email, style: c.caption, textAlign: TextAlign.center),
          const SizedBox(height: 12),

          // ── Role badge ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isTeacher ? c.accentTint : c.primaryTint,
              borderRadius: c.brSmall,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isTeacher
                      ? Icons.school_rounded
                      : Icons.person_rounded,
                  size: 14,
                  color: isTeacher ? c.accent : c.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isTeacher ? 'role_teacher'.tr : 'role_student'.tr,
                  style: c.label.copyWith(
                    color: isTeacher ? c.accent : c.primary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Divider(color: c.divider),
          const SizedBox(height: 24),

          // ── Info rows ───────────────────────────────────────────────────
          _InfoRow(icon: Icons.phone_rounded,       label: p.phone, c: c),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.cake_rounded,        label: p.dob,   c: c),
          const SizedBox(height: 12),
          _InfoRow(
              icon: Icons.info_outline_rounded,
              label: p.bio.isNotEmpty ? p.bio : '—',
              c: c),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppColors c;
  const _InfoRow(
      {required this.icon, required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: c.textLight),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label.isNotEmpty ? label : '—',
            style: c.body.copyWith(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _MobileHero
// ═════════════════════════════════════════════════════════════════════════════

class _MobileHero extends StatelessWidget {
  final ProfileProvider p;
  final AppColors c;
  final Future<void> Function(XFile) onImageChange;

  const _MobileHero({
    required this.p,
    required this.c,
    required this.onImageChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary, c.primaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft:  Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Back button ────────────────────────────────────────────────
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: context.colors.cardShadow,
                ),
                child: Icon(
                  CupertinoIcons.back,
                  color: context.colors.textDark,
                  size: 22,
                ),
              ),
            ),
          ),

          Center(
            child: EditableImage(
              onChange: onImageChange,
              imageFile: p.imageFile,
              imageByte: p.imageByte,
              imageUrl:  p.imageUrl,
              size:      context.height / 8,
              isCircle:  true,
            ),
          ),
          const SizedBox(height: 14),

          // ── Name ────────────────────────────────────────────────────────
          Text(
            p.name.isNotEmpty ? p.name : '—',
            style: const TextStyle(
              fontFamily: 'tajawal',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.email,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _AvatarCircle — shows network / picked / initials
// ═════════════════════════════════════════════════════════════════════════════

class _AvatarCircle extends StatelessWidget {
  final ProfileProvider p;
  final AppColors c;
  final double size;

  const _AvatarCircle(
      {required this.p, required this.c, required this.size});

  @override
  Widget build(BuildContext context) {
    if (p.imageByte != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: MemoryImage(p.imageByte!),
      );
    }
    if (p.imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(p.imageUrl),
      );
    }
    // Initials fallback
    final initial = p.name.isNotEmpty ? p.name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c.primary.withValues(alpha: 0.15),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'tajawal',
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: c.primary,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _FormCard — the actual fields + save button (used in both layouts)
// ═════════════════════════════════════════════════════════════════════════════

class _FormCard extends StatelessWidget {
  final ProfileProvider p;
  final AppColors c;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController dobCtrl;
  final TextEditingController bioCtrl;
  final bool isChanged;
  final bool isSaving;
  final Future<void> Function() onSave;
  final Future<void> Function(XFile) onImageChange;
  final bool showAvatar;

  const _FormCard({
    required this.p,
    required this.c,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.dobCtrl,
    required this.bioCtrl,
    required this.isChanged,
    required this.isSaving,
    required this.onSave,
    required this.onImageChange,
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: c.brLarge,
        boxShadow: c.cardShadow,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Avatar (web only — on mobile it's in the hero) ──────────────
          if (showAvatar) ...[
            Center(
              child: EditableImage(
                onChange: onImageChange,
                imageFile: p.imageFile,
                imageByte: p.imageByte,
                imageUrl:  p.imageUrl,
                size:      context.height / 8,
                isCircle:  true,
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── Section: Personal info ───────────────────────────────────────
          _SectionHeader(label: 'personal_info_section'.tr, c: c),
          const SizedBox(height: 16),

          MyTextField(controller: nameCtrl,  label: 'name_label'.tr),
          const SizedBox(height: 14),
          MyTextField(
            controller: emailCtrl,
            label:  'email_label'.tr,
            enable: false, // email cannot be changed
          ),
          const SizedBox(height: 14),
          MyTextField(
            controller: phoneCtrl,
            label:    'phone_label'.tr,
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          MyTextField(controller: dobCtrl, label: 'dob_label'.tr),

          const SizedBox(height: 24),

          // ── Section: Bio ─────────────────────────────────────────────────
          _SectionHeader(label: 'bio_section'.tr, c: c),
          const SizedBox(height: 16),
          MyTextField(
            controller: bioCtrl,
            label:   'bio_label'.tr,
            maxLine: 4,
          ),

          const SizedBox(height: 32),

          // ── Save button ──────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: isChanged ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: MyPrimaryButton(
              label:     'save_changes'.tr,
              isLoading: isSaving,
              onPressed: isChanged ? onSave : null,
            ),
          ),

          // ── "No changes" hint ────────────────────────────────────────────
          if (!isChanged) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'no_changes_yet'.tr,
                style: c.caption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _SectionHeader
// ═════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  final AppColors c;
  const _SectionHeader({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: c.label.copyWith(fontSize: 14, color: c.textDark)),
    ]);
  }
}