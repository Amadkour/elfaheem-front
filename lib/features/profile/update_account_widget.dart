 library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/design/app_area.dart' show AppArea;
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart' as Helpers;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart';
import 'package:flutter_education_app/features/auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/features/auth/teacher_document_model.dart';
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_education_app/features/auth/username_field.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/courses/student/details/components/app_responsive.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBlock, AppBlockTone, AppButton, AppButtonSize, AppCard, AppSettingsTile, AppSkeletonBox, AppStatusBadge, AppTabItem,
        AppTabs, AppTone, AppType, appInkOn, appTintOn;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_back_button.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_number_field.dart';

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

  /// The fields hold the account's values (a skeleton is drawn until then, M17).
  bool _ready = false;

  // 0 = Personal Info, 1 = Documents (teachers only — students never see the tab bar)
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _p = context.read<ProfileProvider>();
    final auth = context.read<MyAuthProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Opened straight from the avatar menu the profile provider may still be empty (or hold another account):
      // fill it from the signed-in user first, so the fields never start blank (M17).
      final u = auth.currentUser;
      if (u != null && (_p.email.isEmpty || _p.id != u.id)) _p.initData(u);
      _nameCtrl.text = _p.name;
      _emailCtrl.text = _p.email;
      _phoneCtrl.text = _p.phone;
      _dobCtrl.text = _p.dob;
      _bioCtrl.text = _p.bio;
      _usernameCtrl.text = _p.username;
      if (mounted) setState(() => _ready = true);

      if (widget.isTeacher) {
        // Specializations must be loaded before loadTeacherProfileExtras()
        // can match the teacher's current specialization_id to an entry.
        // Either call may fail (an older server answers 404): the page keeps its fields and the extras stay empty.
        try {
          await auth.loadSpecialization(context);
          await auth.loadTeacherProfileExtras();
        } catch (_) {}
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

  /// The end of the username change cooldown while it runs (the field then only keeps or removes the name): the
  /// account's `username_change_available_at`, or the `retry_at` of a 429 USERNAME_CHANGE_TOO_SOON just received.
  DateTime? get _usernameLockedUntil {
    if (_p.username.isEmpty) return null;
    final err = _usernameError;
    final at = (err != null && err.tooSoon ? err.retryAt : null) ?? _p.usernameChangeAvailableAt;
    if (at == null || !at.isAfter(DateTime.now().toUtc())) return null;
    return at;
  }

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
          if (mounted && _p.usernameError != null) {
            setState(() => _usernameError = _p.usernameError);
            // changed too soon: put the current name back, the field locks and says when it can change again
            if (_p.usernameError!.tooSoon) _usernameCtrl.text = _p.username;
          }
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

    return SdArea(area: AppArea.me, child: BasePage(
      useWebCard: true,
      width: AppWidth.content,
      appBar: isWide ? ScreenAppBar(helpPageId: 'account.edit', title: 'update_account'.tr) : null,
      // The same hero for every role; a teacher's Personal info / Documents switch sits under it (M18). A wide page
      // keeps the hero beside the form instead of above it.
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 860) return _mobileLayout(p, c, showBack: !isWide);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: _heroWidth,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.md),
                child: _hero(p, c, showBack: false, card: true),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(children: _formArea(p, c)),
              ),
            ),
          ]);
        }),
      ),
    ));
  }

  /// The hero column's width beside the form on a wide page.
  static const double _heroWidth = 320;

  Widget _hero(ProfileProvider p, ThemeConfigProvider c, {required bool showBack, bool card = false}) => _MobileHero(
        p: p,
        c: c,
        showBack: showBack,
        card: card,
        onImageChange: (f) async {
          await p.changeImage(f);
          setState(() {});
        },
        onImageRemove: () => _removeImage(p),
      );

  /// Remove picture (D-880): the confirm is EditableImage's; a stored picture is deleted at once and the account
  /// saved, so every avatar (headers, chat, the public profile) shows the initial.
  Future<void> _removeImage(ProfileProvider p) async {
    try {
      final updated = await p.removeImage();
      if (updated != null && mounted) await context.read<MyAuthProvider>().saveUserLocally(updated);
      showAppNotice('avatar_removed'.tr);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
    if (mounted) setState(() {});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT — hero header + form
  // ══════════════════════════════════════════════════════════════════════════

  Widget _mobileLayout(ProfileProvider p, ThemeConfigProvider c, {required bool showBack}) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // ── Hero header ────────────────────────────────────────────────
          _hero(p, c, showBack: showBack),
          ..._formArea(p, c),
        ],
      ),
    );
  }

  List<Widget> _formArea(ProfileProvider p, ThemeConfigProvider c) => [
          if (widget.isTeacher)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
              child: _PremiumTabSwitcher(
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
                tabs: [
                  (icon: Icons.person_outline_rounded, label: 'tab_personal_info'.tr),
                  (icon: Icons.description_outlined, label: 'tab_documents'.tr),
                ],
              ),
            ),

          if (widget.isTeacher && _tab == 1)
            const _DocumentsTabView()
          else if (!_ready)
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
              child: _FormSkeleton(),
            )
          else
          // ── Form ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
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
                  padding: const EdgeInsets.only(top: AppSpace.md),
                  child: UsernameField(
                    controller: _usernameCtrl,
                    currentUsername: _p.username,
                    error: _usernameError,
                    lockedUntil: _usernameLockedUntil,
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
              onImageRemove: () => _removeImage(p),
            ),
          ),
        ];
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
  Widget build(BuildContext context) => AppTabs(
        expand: true,
        index: selected,
        onChanged: onChanged,
        items: [for (final t in tabs) AppTabItem(t.label, icon: t.icon)],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// _DocumentsTabView — full-page premium wrapper around _TeacherDocumentsManager
// ═════════════════════════════════════════════════════════════════════════════

class _DocumentsTabView extends StatelessWidget {
  const _DocumentsTabView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final well = appTintOn(context, c.primary, surface: c.cardBg);
    // Inside the page's scroll view, under the hero and the tab switch (M18).
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: AppSettingsTile.well,
                      height: AppSettingsTile.well,
                      decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
                      child: Icon(Icons.description_rounded, size: AppIconSize.md, color: appInkOn(context, c.primary, well)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('required_documents_section'.tr, style: AppType.section(context)),
                          const SizedBox(height: AppSpace.xxs / 2),
                          Text('documents_manage_subtitle'.tr, style: AppType.meta(context)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
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
  final Future<void> Function()? onImageRemove;

  /// Off when an [AppHeader] above already carries the back button.
  final bool showBack;

  /// A free-standing card beside the form, rather than the phone's banner under the status bar.
  final bool card;

  const _MobileHero({
    required this.p,
    required this.c,
    required this.onImageChange,
    this.onImageRemove,
    this.showBack = true,
    this.card = false,
  });

  @override
  Widget build(BuildContext context) {
    // the page's one tinted block (D-613): on a phone it sits under the status bar with the page gutter, beside the
    // form on a wide page
    final hero = AppBlock(
      tone: AppBlockTone.identity,
      hero: true,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBack)
                const Align(
                  alignment: AlignmentDirectional.topStart,
                  child: AppBackButton(),
                ),
              Center(
                child: EditableImage(
                  onChange: onImageChange,
                  imageFile: p.imageFile,
                  imageByte: p.imageByte,
                  imageUrl: p.imageUrl,
                  size: context.height / 8,
                  isCircle: true,
                  name: p.name, // no photo: the initial, as everywhere else (N10)
                  onRemove: onImageRemove,
                  removeMessage: 'avatar_remove_confirm'.tr,
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // ── Name ────────────────────────────────────────────────────────
              Text(
                p.name.isNotEmpty ? p.name : '—',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.headline(context).copyWith(color: b.ink),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                p.email,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: AppType.label(context).copyWith(color: b.muted),
              ),
            ],
          ),
        );
      }),
    );
    if (card) return hero;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: SafeArea(bottom: false, child: hero),
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
  final Future<void> Function()? onImageRemove;
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
    this.onImageRemove,
    this.showAvatar = true,
    this.usernameField,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
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
                name: p.name, // no photo: the initial, as everywhere else (N10)
                onRemove: onImageRemove,
                removeMessage: 'avatar_remove_confirm'.tr,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
          ],

          // ── Section: Personal info ───────────────────────────────────────
          _SectionHeader(label: 'personal_info_section'.tr, c: c),
          const SizedBox(height: AppSpace.md),

          _Labeled(label: 'name_label'.tr, child: MyTextField(controller: nameCtrl, label: 'name_label'.tr)),
          const SizedBox(height: AppSpace.md),
          _Labeled(
            label: 'email_label'.tr,
            child: MyTextField(
              controller: emailCtrl,
              label: 'email_label'.tr,
              enable: false, // email cannot be changed
            ),
          ),
          ?usernameField,
          const SizedBox(height: AppSpace.md),
          _Labeled(
            label: 'phone_label'.tr,
            child: MyTextField(
              controller: phoneCtrl,
              label: 'phone_label'.tr,
              keyboard: TextInputType.phone,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _Labeled(label: 'dob_label'.tr, child: MyTextField(controller: dobCtrl, label: 'dob_label'.tr)),

          const SizedBox(height: AppSpace.xl),

          // ── Section: Bio ─────────────────────────────────────────────────
          _SectionHeader(label: 'bio_section'.tr, c: c),
          const SizedBox(height: AppSpace.md),
          _Labeled(label: 'bio_label'.tr, child: MyTextField(controller: bioCtrl, label: 'bio_label'.tr, maxLine: 4)),

          // ── Section: Teaching Details (teachers only, everything from
          //    registration except email + documents) ─────────────────────
          if (isTeacher) ...[
            const SizedBox(height: AppSpace.xl),
            _SectionHeader(label: 'teaching_details_section'.tr, c: c),
            const SizedBox(height: AppSpace.md),
            Consumer<MyAuthProvider>(
              builder: (context, auth, _) {
                if (auth.isLoadingTeacherExtras) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                    child: Center(child: AppLoadingIndicator()),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppNumberField(controller: experienceCtrl, label: 'experience'.tr, min: 0),
                    const SizedBox(height: AppSpace.md),
                    SectionLabel(label: 'specialization'.tr),
                    const SizedBox(height: AppSpace.xs),
                    StyledDropdown(
                      icon: Icons.science_outlined,
                      label: 'specialization'.tr,
                      controller: specCtrl,
                      initValue: auth.selectedSpecialization,
                      options: auth.specializations,
                      onChange: (i) => auth.onChangeSpecialization(i, specCtrl),
                    ),
                    const SizedBox(height: AppSpace.md),
                    SectionLabel(label: 'payment_method'.tr),
                    const SizedBox(height: AppSpace.xs),
                    StyledDropdown(
                      icon: Icons.credit_card_outlined,
                      label: 'payment_method'.tr,
                      controller: payCtrl,
                      initValue: auth.selectedPaymentType,
                      options: auth.paymentTypes,
                      onChange: (i) => auth.onChangePaymentMethod(i, payCtrl),
                    ),
                    const SizedBox(height: AppSpace.md),
                    SectionLabel(label: 'teaching_style'.tr),
                    const SizedBox(height: AppSpace.xs),
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

          const SizedBox(height: AppSpace.xl),

          // ── Save button ──────────────────────────────────────────────────
          // the kit's button draws its own disabled look (no extra fade on top, L10)
          AppButton.primary(
            expand: true,
            size: AppButtonSize.lg,
            label: 'save_changes'.tr,
            busy: isSaving,
            onPressed: isChanged ? onSave : null,
          ),

          // ── "No changes" hint ────────────────────────────────────────────
          if (!isChanged) ...[
            const SizedBox(height: AppSpace.xs),
            Center(child: Text('no_changes_yet'.tr, style: AppType.meta(context))),
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
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
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
                        style: AppType.bodyStrong(context),
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
    showAppModalSheet(
      useSafeArea: true,
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
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
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: entry.title,
              onChanged: (v) => docs.setCustomEntryTitle(index, v),
              style: AppType.body(context),
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
    showAppModalSheet(
      useSafeArea: true,
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
    late final AppTone tone;
    if (doc == null) {
      label = 'status_not_uploaded'.tr;
      tone = AppTone.neutral;
    } else if (doc!.isApproved) {
      label = 'status_approved'.tr;
      tone = AppTone.success;
    } else if (doc!.isRejected) {
      label = 'status_rejected'.tr;
      tone = AppTone.danger;
    } else {
      label = 'status_pending_review'.tr;
      tone = AppTone.warning;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStatusBadge(label: label, tone: tone, dense: true),
        if (doc?.isRejected == true && doc?.rejectionReason != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(
            doc!.rejectionReason!,
            style: AppType.meta(context).copyWith(color: c.blockAccentInk(c.danger, c.inputBg)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// A field with its name above it: [MyTextField] only shows its label as a hint, which disappears once the field
/// holds a value (M17).
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, bottom: AppSpace.xs),
          child: SectionLabel(label: label),
        ),
        child,
      ],
    );
  }
}

/// The form's shape while the account loads (M17): labels and boxes, no spinner.
class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  /// The label bones' widths (a little uneven, like real labels) and a field's height.
  static const List<double> _labels = [AppSpace.xxl * 2, AppSpace.xxxl + AppSpace.lg, AppSpace.xxl * 2 + AppSpace.md, AppSpace.xxxl];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in _labels) ...[
            AppSkeletonBox(width: w, height: AppSpace.sm),
            const SizedBox(height: AppSpace.xs),
            const AppSkeletonBox(width: double.infinity, height: AppTouch.min, radius: AppRadius.control),
            const SizedBox(height: AppSpace.md),
          ],
        ],
      ),
    );
  }
}

/// A form section's heading: the editorial section face in ink (no gradient bar).
class _SectionHeader extends StatelessWidget {
  final String label;
  final ThemeConfigProvider c;

  const _SectionHeader({required this.label, required this.c});

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(label, style: AppType.section(context)));
}
