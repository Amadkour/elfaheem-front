 library;

import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart' as Helpers;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../auth/auth_provider.dart';
import '../../auth/auth_widgets.dart';
import '../../auth/reauth_sheet.dart';
import '../../auth/verified_screen.dart';
import '../../auth/teacher_document_model.dart';
import '../../auth/teacher_document_provider.dart';
import '../../auth/username.dart';
import '../../auth/username_field.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import '../../student/courses/details/components/app_responsive.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class EditAccountScreen extends StatefulWidget {
  final bool isTeacher;

  const EditAccountScreen({super.key, this.isTeacher = false});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  /// Where the @username check stands, and the save's USERNAME_* error (shown on the field).
  UsernameStatus _usernameStatus = UsernameStatus.current;
  UsernameError? _usernameError;

  // Teacher-only registration fields (everything except email + documents)
  final _experienceCtrl = TextEditingController();
  final _specCtrl = ExpansibleController();
  final _teachCtrl = ExpansibleController();
  final _payCtrl = ExpansibleController();

  late ProfileProvider _p;
  bool _saving = false;

  // 0 = Personal Info, 1 = Documents (teachers only — students never see the tab bar)
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _p = context.read<ProfileProvider>();
    final auth = context.read<MyAuthProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _nameCtrl.text = _p.name;
      _emailCtrl.text = _p.email;
      _phoneCtrl.text = _p.phone;
      _dobCtrl.text = _p.dob;
      _bioCtrl.text = _p.bio;
      _usernameCtrl.text = _p.username;

      if (widget.isTeacher) {
        // Specializations must be loaded before loadTeacherProfileExtras()
        // can match the teacher's current specialization_id to an entry.
        await auth.loadSpecialization(context);
        await auth.loadTeacherProfileExtras();
        _experienceCtrl.text = auth.teacherExperienceYears?.toString() ?? '';
      }
      if (mounted) setState(() {});
    });

    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _dobCtrl,
      _bioCtrl,
      _experienceCtrl,
      _usernameCtrl,
    ]) {
      c.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _dobCtrl,
      _bioCtrl,
      _experienceCtrl,
      _usernameCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Has anything changed? ─────────────────────────────────────────────────
  bool get _teacherExtrasChanged {
    if (!widget.isTeacher) return false;
    final auth = context.read<MyAuthProvider>();
    final experience = int.tryParse(_experienceCtrl.text.trim());
    return experience != auth.teacherExperienceYears ||
        auth.selectedSpecialization?['id'] != auth.teacherSpecializationId ||
        auth.selectedTeachingType?['text'] != auth.teacherTeachingType ||
        auth.selectedPaymentType?['text'] != auth.teacherPaymentType;
  }

  /// The username field is shown (kill switch `auth.username` off).
  bool get _usernameOn => !Helpers.AppConfig.disableList.contains(kUsernameFeatureKey);

  /// Set, changed or removed ('' = remove).
  bool get _usernameChanged =>
      _usernameOn && UsernameRules.normalize(_usernameCtrl.text) != _p.username;

  bool get _isChanged =>
      _usernameChanged ||
      _nameCtrl.text != _p.name ||
      _phoneCtrl.text != _p.phone ||
      _dobCtrl.text != _p.dob ||
      _bioCtrl.text != _p.bio ||
      _p.imageByte != null ||
      _teacherExtrasChanged;

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_isChanged || _saving) return;
    if (_usernameChanged && _usernameStatus.blocksSubmit) {
      showAppNotice(
        _usernameStatus == UsernameStatus.checking
            ? 'username_wait_check'.tr
            : 'username_fix_first'.tr,
        error: _usernameStatus != UsernameStatus.checking,
      );
      return;
    }
    if (mounted) setState(() => _saving = true);

    try {
      // 1. Upload image first (if changed)
      if (_p.imageFile != null) {
        final updated = await _p.uploadImage();
        if (updated != null && mounted) {
          await context.read<MyAuthProvider>().saveUserLocally(updated);
        }
      }

      // 2. Update profile fields (if changed)
      final fieldsChanged =
          _usernameChanged ||
          _nameCtrl.text != _p.name ||
          _phoneCtrl.text != _p.phone ||
          _dobCtrl.text != _p.dob ||
          _bioCtrl.text != _p.bio;

      UserModel? verifyPhoneFor; // a changed number is verified again right after the save (S1)
      if (fieldsChanged) {
        // A new phone number needs the current password (the server resets its verification and asks for
        // an OTP again, S1 / S9); the sheet is skipped when the number did not change.
        final newPhone = _phoneCtrl.text.trim();
        final phoneChanged = newPhone.isNotEmpty && newPhone != _p.phone.trim();
        Reauth? re;
        if (phoneChanged) {
          re = await askReauth(context);
          if (re == null || !mounted) return;
        }
        final user = await _p.updateProfile(
          name: _nameCtrl.text.trim(),
          phone: newPhone,
          dob: _dobCtrl.text.trim(),
          bio: _bioCtrl.text.trim(),
          password: re?.password,
          mfaCode: re?.mfaCode,
          username: _usernameChanged ? _usernameCtrl.text : null,
        );
        if (user == null) {
          // taken / reserved / invalid: the field shows why, with the server's suggestions
          if (mounted && _p.usernameError != null) setState(() => _usernameError = _p.usernameError);
          if (mounted) _showSnack(_p.errorMessage ?? 'generic_error'.tr, context.colors.danger);
          return;
        }
        if (mounted) {
          await context.read<MyAuthProvider>().saveUserLocally(user);
          _p.initData(context.read<MyAuthProvider>().currentUser);
        }
        if (phoneChanged) verifyPhoneFor = user;
      }

      // 3. Update teacher-only registration fields (if changed)
      if (_teacherExtrasChanged) {
        final auth = context.read<MyAuthProvider>();
        await auth.updateTeacherProfileExtras(
          experienceYears: int.tryParse(_experienceCtrl.text.trim()),
          specializationId: auth.selectedSpecialization?['id'] as int?,
          teachingType: auth.selectedTeachingType?['text'] as String?,
          paymentType: auth.selectedPaymentType?['text'] as String?,
        );
      }

      if (mounted) {
        final u = verifyPhoneFor;
        if (u != null) {
          _showSnack('phone_change_verify'.tr, context.colors.success);
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              email: u.gmail,
              role: u.role,
              phoneNumber: u.phone,
              channels: const ['phone'],
              flow: OtpFlowEnum.phoneChange,
            ),
          ));
          return;
        }
        _showSnack('changes_saved'.tr, context.colors.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _showSnack(ApiException.from(e).message, context.colors.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, Color color) =>
      showAppNotice(msg, error: color == context.colors.danger);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileProvider>();
    final c = context.colors;
    final isWide = context.showSidebar;

    return BasePage(
      useWebCard: true,
      maxWith: 1200,
      child: SafeArea(
        child: Column(
          children: [
            // ── App bar ────────────────────────────────────────────────────
            if (isWide) ScreenAppBar(title: 'update_account'.tr),

            // ── Premium tab switcher (teachers only) ─────────────────────────

            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: (!widget.isTeacher || _tab == 0)
                  ? _mobileLayout(p, c)
                  : Column(
                      children: [
                        _PremiumTabSwitcher(
                          selected: _tab,
                          onChanged: (i) => setState(() => _tab = i),
                          tabs: [
                            (
                              icon: Icons.person_outline_rounded,
                              label: 'tab_personal_info'.tr,
                            ),
                            (
                              icon: Icons.description_outlined,
                              label: 'tab_documents'.tr,
                            ),
                          ],
                        ),
                        const _DocumentsTabView(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT — hero header + form
  // ══════════════════════════════════════════════════════════════════════════

  Widget _mobileLayout(ProfileProvider p, ThemeConfigProvider c) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          if (widget.isTeacher) ...[
            _PremiumTabSwitcher(
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
              tabs: [
                (
                  icon: Icons.person_outline_rounded,
                  label: 'tab_personal_info'.tr,
                ),
                (icon: Icons.description_outlined, label: 'tab_documents'.tr),
              ],
            ),
          ],
          // ── Hero header ────────────────────────────────────────────────
          _MobileHero(
            p: p,
            c: c,
            onImageChange: (f) async {
              await p.changeImage(f);
              setState(() {});
            },
          ),

          // ── Form ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: _FormCard(
              p: p,
              c: c,
              isTeacher: widget.isTeacher,
              nameCtrl: _nameCtrl,
              emailCtrl: _emailCtrl,
              phoneCtrl: _phoneCtrl,
              dobCtrl: _dobCtrl,
              bioCtrl: _bioCtrl,
              experienceCtrl: _experienceCtrl,
              specCtrl: _specCtrl,
              payCtrl: _payCtrl,
              teachCtrl: _teachCtrl,
              usernameField: ParentComponent(
                featureKey: kUsernameFeatureKey,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: UsernameField(
                    controller: _usernameCtrl,
                    currentUsername: _p.username,
                    error: _usernameError,
                    label: 'username_label'.tr,
                    onStatusChanged: (s) => setState(() => _usernameStatus = s),
                  ),
                ),
              ),
              isChanged: _isChanged,
              isSaving: _saving,
              onSave: _save,
              showAvatar: false,
              // avatar is in the hero, not the card
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
// _PremiumTabSwitcher — pill-shaped segmented control with an animated
// sliding indicator, used to switch between Personal Info and Documents.
// ═════════════════════════════════════════════════════════════════════════════

class _PremiumTabSwitcher extends StatelessWidget {
  const _PremiumTabSwitcher({
    required this.selected,
    required this.onChanged,
    required this.tabs,
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final List<({IconData icon, String label})> tabs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(0),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == selected;
          final tab = tabs[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: isActive ? c.primaryGradient : null,
                  color: isActive ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: isActive ? c.primaryShadow : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 17,
                      color: isActive ? context.colors.onHero : c.textLight,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isActive ? context.colors.onHero : c.textLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _DocumentsTabView — full-page premium wrapper around _TeacherDocumentsManager
// ═════════════════════════════════════════════════════════════════════════════

class _DocumentsTabView extends StatelessWidget {
  const _DocumentsTabView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: c.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.description_outlined,
                        color: context.colors.onHero,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('required_documents_section'.tr, style: c.h3),
                          const SizedBox(height: 2),
                          Text(
                            'documents_manage_subtitle'.tr,
                            style: c.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _TeacherDocumentsManager(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _MobileHero
// ═════════════════════════════════════════════════════════════════════════════

class _MobileHero extends StatelessWidget {
  final ProfileProvider p;
  final ThemeConfigProvider c;
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
          colors: [c.primary, c.primary],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
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
            alignment: AlignmentDirectional.topStart,
            child: Semantics(
              button: true,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 48,                       // 48 px touch target, the visible well stays 42
                height: 48,
                padding: const EdgeInsets.all(3),
                child: Container(
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
            ),
          ),

          Center(
            child: EditableImage(
              onChange: onImageChange,
              imageFile: p.imageFile,
              imageByte: p.imageByte,
              imageUrl: p.imageUrl,
              size: context.height / 8,
              isCircle: true,
            ),
          ),
          const SizedBox(height: 14),

          // ── Name ────────────────────────────────────────────────────────
          Text(
            p.name.isNotEmpty ? p.name : '—',
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.onHero,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.email,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 13,
              color: context.colors.onHero.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _FormCard — the actual fields + save button (used in both layouts)
// ═════════════════════════════════════════════════════════════════════════════

class _FormCard extends StatelessWidget {
  final ProfileProvider p;
  final ThemeConfigProvider c;
  final bool isTeacher;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController dobCtrl;
  final TextEditingController bioCtrl;
  final TextEditingController experienceCtrl;
  final ExpansibleController specCtrl;
  final ExpansibleController payCtrl;
  final ExpansibleController teachCtrl;
  final bool isChanged;
  final bool isSaving;
  final Future<void> Function() onSave;
  final Future<void> Function(XFile) onImageChange;
  final bool showAvatar;

  /// The @username field, under the e-mail (null = not shown).
  final Widget? usernameField;

  const _FormCard({
    required this.p,
    required this.c,
    required this.isTeacher,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.dobCtrl,
    required this.bioCtrl,
    required this.experienceCtrl,
    required this.specCtrl,
    required this.payCtrl,
    required this.teachCtrl,
    required this.isChanged,
    required this.isSaving,
    required this.onSave,
    required this.onImageChange,
    this.showAvatar = true,
    this.usernameField,
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
                imageUrl: p.imageUrl,
                size: context.height / 8,
                isCircle: true,
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── Section: Personal info ───────────────────────────────────────
          _SectionHeader(label: 'personal_info_section'.tr, c: c),
          const SizedBox(height: 16),

          MyTextField(controller: nameCtrl, label: 'name_label'.tr),
          const SizedBox(height: 14),
          MyTextField(
            controller: emailCtrl,
            label: 'email_label'.tr,
            enable: false, // email cannot be changed
          ),
          ?usernameField,
          const SizedBox(height: 14),
          MyTextField(
            controller: phoneCtrl,
            label: 'phone_label'.tr,
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          MyTextField(controller: dobCtrl, label: 'dob_label'.tr),

          const SizedBox(height: 24),

          // ── Section: Bio ─────────────────────────────────────────────────
          _SectionHeader(label: 'bio_section'.tr, c: c),
          const SizedBox(height: 16),
          MyTextField(controller: bioCtrl, label: 'bio_label'.tr, maxLine: 4),

          // ── Section: Teaching Details (teachers only, everything from
          //    registration except email + documents) ─────────────────────
          if (isTeacher) ...[
            const SizedBox(height: 24),
            _SectionHeader(label: 'teaching_details_section'.tr, c: c),
            const SizedBox(height: 16),
            Consumer<MyAuthProvider>(
              builder: (context, auth, _) {
                if (auth.isLoadingTeacherExtras) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: AppLoadingIndicator()),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconTextField(
                      controller: experienceCtrl,
                      label: 'experience'.tr,
                      icon: Icons.schedule_rounded,
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                    SectionLabel(label: 'specialization'.tr),
                    const SizedBox(height: 8),
                    StyledDropdown(
                      icon: Icons.science_outlined,
                      label: 'specialization'.tr,
                      controller: specCtrl,
                      initValue: auth.selectedSpecialization,
                      options: auth.specializations,
                      onChange: (i) => auth.onChangeSpecialization(i, specCtrl),
                    ),
                    const SizedBox(height: 14),
                    SectionLabel(label: 'payment_method'.tr),
                    const SizedBox(height: 8),
                    StyledDropdown(
                      icon: Icons.credit_card_outlined,
                      label: 'payment_method'.tr,
                      controller: payCtrl,
                      initValue: auth.selectedPaymentType,
                      options: auth.paymentTypes,
                      onChange: (i) => auth.onChangePaymentMethod(i, payCtrl),
                    ),
                    const SizedBox(height: 14),
                    SectionLabel(label: 'teaching_style'.tr),
                    const SizedBox(height: 8),
                    StyledDropdown(
                      icon: Icons.cast_for_education_outlined,
                      label: 'teaching_style'.tr,
                      controller: teachCtrl,
                      initValue: auth.selectedTeachingType,
                      options: auth.teachingTypes,
                      onChange: (i) => auth.onChangeTeachingType(i, teachCtrl),
                    ),
                  ],
                );
              },
            ),
          ],

          const SizedBox(height: 32),

          // ── Save button ──────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: isChanged ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: PrimaryButton(
              label: 'save_changes'.tr,
              isLoading: isSaving,
              onPressed: isChanged ? onSave : null,
            ),
          ),

          // ── "No changes" hint ────────────────────────────────────────────
          if (!isChanged) ...[
            const SizedBox(height: 10),
            Center(child: Text('no_changes_yet'.tr, style: c.caption)),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _TeacherDocumentsManager — lets a teacher view/upload/replace/delete their
// required + custom verification documents from the account settings screen
// (same data as the registration flow, but no "finalize" gate here since
// registration is already complete by the time this screen is reachable).
// ═════════════════════════════════════════════════════════════════════════════

class _TeacherDocumentsManager extends StatefulWidget {
  const _TeacherDocumentsManager();

  @override
  State<_TeacherDocumentsManager> createState() =>
      _TeacherDocumentsManagerState();
}

class _TeacherDocumentsManagerState extends State<_TeacherDocumentsManager> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final email = context.read<ProfileProvider>().email;
      context.read<TeacherDocumentProvider>().loadOverview(email);
    });
  }

  String get _email => context.read<ProfileProvider>().email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final docs = context.watch<TeacherDocumentProvider>();
    final overview = docs.overview;

    if (docs.isLoadingOverview && overview == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: AppLoadingIndicator()),
      );
    }

    if (overview == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('documents_load_failed'.tr, style: c.caption),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Predefined requirements ────────────────────────────────────────
        ...overview.requirements.map(
          (req) => _ManagedRequirementRow(
            requirement: req,
            docs: docs,
            email: _email,
          ),
        ),

        // ── Already-uploaded custom documents ──────────────────────────────
        if (overview.customDocuments.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...overview.customDocuments.map(
            (doc) => _ManagedCustomDocRow(doc: doc, docs: docs, email: _email),
          ),
        ],

        // ── In-progress "add a custom document" form rows ──────────────────
        ...docs.customEntries.asMap().entries.map(
          (e) =>
              _ManagedCustomEntryRow(index: e.key, docs: docs, email: _email),
        ),

        const SizedBox(height: 10),
        GestureDetector(
          onTap: docs.addCustomEntry,
          child: Row(
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: c.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'add_custom_document'.tr,
                style: c.label.copyWith(color: c.primary, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManagedRequirementRow extends StatelessWidget {
  const _ManagedRequirementRow({
    required this.requirement,
    required this.docs,
    required this.email,
  });

  final DocumentRequirementStatus requirement;
  final TeacherDocumentProvider docs;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final doc = requirement.document;
    final uploading = docs.isUploadingFor('req_${requirement.typeId}');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            doc == null
                ? Icons.upload_file_outlined
                : (doc.isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined),
            size: 20,
            color: c.textLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        requirement.title,
                        style: c.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (requirement.isRequired) ...[
                      const SizedBox(width: 6),
                      Text(
                        '*',
                        style: TextStyle(
                          color: c.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                _StatusChip(doc: doc),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (uploading)
            const SizedBox(width: 20, height: 20, child: AppLoadingIndicator())
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: doc == null
                      ? 'upload_document'.tr
                      : 'replace_document'.tr,
                  icon: Icon(
                    doc == null
                        ? Icons.add_circle_outline_rounded
                        : Icons.refresh_rounded,
                    color: c.primary,
                  ),
                  onPressed: () => _showPicker(context),
                ),
                if (doc != null)
                  IconButton(
                    tooltip: 'delete_document'.tr,
                    icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                    onPressed: () => docs.deleteDocument(doc.id, email: email),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Gallery/camera don't make sense as separate concepts on
              // web — the browser file picker (below) already covers it.
              if (!kIsWeb)
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: c.primary),
                  title: Text(
                    'pick_from_gallery'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    docs.pickAndUploadRequired(
                      requiredTypeId: requirement.typeId,
                      source: ImageSource.gallery,
                      email: email,
                    );
                  },
                ),
              if (!kIsWeb)
                ListTile(
                  leading: Icon(Icons.camera_alt_outlined, color: c.accent),
                  title: Text(
                    'take_photo'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    docs.pickAndUploadRequired(
                      requiredTypeId: requirement.typeId,
                      source: ImageSource.camera,
                      email: email,
                    );
                  },
                ),
              ListTile(
                leading: Icon(Icons.folder_open_outlined, color: c.textLight),
                title: Text(
                  'browse_file_pdf_or_image'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600,
                    color: c.textDark,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  docs.pickAndUploadRequiredFile(
                    requirement.typeId,
                    email: email,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagedCustomDocRow extends StatelessWidget {
  const _ManagedCustomDocRow({
    required this.doc,
    required this.docs,
    required this.email,
  });

  final TeacherDocumentModel doc;
  final TeacherDocumentProvider docs;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            doc.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
            size: 20,
            color: c.textLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: c.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _StatusChip(doc: doc),
              ],
            ),
          ),
          IconButton(
            tooltip: 'delete_document'.tr,
            icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            onPressed: () => docs.deleteDocument(doc.id, email: email),
          ),
        ],
      ),
    );
  }
}

class _ManagedCustomEntryRow extends StatelessWidget {
  const _ManagedCustomEntryRow({
    required this.index,
    required this.docs,
    required this.email,
  });

  final int index;
  final TeacherDocumentProvider docs;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entry = docs.customEntries[index];
    final uploading = docs.isUploadingFor('custom_$index');
    final hasTitle = entry.title.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: entry.title,
              onChanged: (v) => docs.setCustomEntryTitle(index, v),
              style: c.body.copyWith(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'custom_document_title_hint'.tr,
                hintStyle: c.caption,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (uploading)
            const SizedBox(width: 20, height: 20, child: AppLoadingIndicator())
          else ...[
            IconButton(
              tooltip: 'upload_document'.tr,
              icon: Icon(
                Icons.upload_rounded,
                color: hasTitle ? c.primary : c.textLight,
              ),
              onPressed: hasTitle ? () => _showPicker(context) : null,
            ),
            IconButton(
              tooltip: 'remove'.tr,
              icon: Icon(Icons.close_rounded, color: c.textLight),
              onPressed: () => docs.removeCustomEntry(index),
            ),
          ],
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Gallery doesn't make sense as a separate concept on web —
              // the browser file picker (below) already covers it.
              if (!kIsWeb)
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: c.primary),
                  title: Text(
                    'pick_from_gallery'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    docs.pickAndUploadCustom(index, email: email);
                  },
                ),
              ListTile(
                leading: Icon(Icons.folder_open_outlined, color: c.textLight),
                title: Text(
                  'browse_file_pdf_or_image'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600,
                    color: c.textDark,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  docs.pickAndUploadCustomFile(index, email: email);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.doc});

  final TeacherDocumentModel? doc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    late final String label;
    late final Color color;
    if (doc == null) {
      label = 'status_not_uploaded'.tr;
      color = c.textLight;
    } else if (doc!.isApproved) {
      label = 'status_approved'.tr;
      color = c.success;
    } else if (doc!.isRejected) {
      label = 'status_rejected'.tr;
      color = c.danger;
    } else {
      label = 'status_pending_review'.tr;
      color = const Color(
        0xFFF59E0B,
      ); // amber — no confirmed "warning" token elsewhere in this codebase
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (doc?.isRejected == true && doc?.rejectionReason != null) ...[
          const SizedBox(height: 4),
          Text(
            doc!.rejectionReason!,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 11,
              color: c.danger,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ThemeConfigProvider c;

  const _SectionHeader({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: c.label.copyWith(fontSize: 14, color: c.textDark)),
      ],
    );
  }
}
