// ─────────────────────────────────────────────────────────────────────────────
// features/auth/register_screen.dart
// Registration screen with server-driven Terms & Conditions gate.
// User must scroll to the bottom of every section before the accept checkbox
// unlocks — and must tick the checkbox before the submit button activates.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../shared/legal/legal_links.dart' show openLegalPage;
import '../shared/profile/about/about_terms_model.dart';
import '../shared/profile/about/about_terms_provider.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'auth_shell.dart';
import '../../design/app_tokens.dart';
import 'auth_widgets.dart';
import 'google_auth_flow.dart';
import 'verify_way.dart';
import 'username.dart';
import 'username_field.dart';
import '../shared/study_profile/study_profile_model.dart';
import '../shared/study_profile/study_profile_pages.dart' show StudyProfileStepPage;
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton, AppButtonSize;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;

// ══════════════════════════════════════════════════════════════════════════════
//  Register Screen
// ══════════════════════════════════════════════════════════════════════════════

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialRole});

  /// 'teacher' / 'student' / 'parent': preselects that role (the landing's "teach on NextBrain" link).
  final String? initialRole;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmedPasswordController = TextEditingController();
  final _dobController = TextEditingController();
  final _usernameController = TextEditingController();
  final _rolController = ExpansibleController();

  /// The optional @username: where its check stands, and the submit's USERNAME_* error (shown on the field).
  UsernameStatus _usernameStatus = UsernameStatus.empty;
  UsernameError? _usernameError;

  /// The username field is shown (kill switch `auth.username` off).
  bool get _usernameOn => !AppConfig.disableList.contains(kUsernameFeatureKey);

  /// A typed username that is still being checked, or is taken / reserved / invalid.
  bool get _usernameBlocks => _usernameOn && _usernameStatus.blocksSubmit;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Whether the user has ticked the "I accept" checkbox after reading terms.
  bool _termsAccepted = false;

  /// The verification way the student picked (null = the first one the admin allows).
  VerifyWay? _pickedWay;

  /// The study step's values (D-790), kept when the student goes back to the form; and the submit's busy state the
  /// step page shows.
  StudyProfile _study = StudyProfile.empty;
  final _busy = ValueNotifier<bool>(false);

  DateTime selectedDate = DateTime.now().subtract(
    const Duration(days: 360 * 20),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pre = widget.initialRole;
      if (pre != null) {
        final a = context.read<MyAuthProvider>();
        final i = a.roles.indexWhere((r) => r['text'] == pre);
        if (i >= 0) setState(() => a.selectedRole = a.roles[i]);
      }
      context.read<MyAuthProvider>().loadSpecialization(context);
      context.read<MyAuthProvider>().loadPolicy();
      context.read<AboutTermsProvider>().loadTerms(context);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _confirmedPasswordController.dispose();
    _dobController.dispose();
    _usernameController.dispose();
    _busy.dispose();
    super.dispose();
  }

  // ── Open terms bottom-sheet ───────────────────────────────────────────────
  Future<void> _openTerms() async {
    context.read<AboutTermsProvider>().clearSelection();
    final accepted = await showAppSideSheet<bool>(
      context,
      withCloseBar: false, // the sheet's own header carries the close button
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AboutTermsProvider>(),
        child: const _TermsBottomSheet(),
      ),
    );
    if (mounted &&
            (context.read<AboutTermsProvider>().terms!.sections.every(
              (e) => e.accept,
            )) ||
        accepted == true) {
      setState(() => _termsAccepted = true);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmedPasswordController.text) {
      Fluttertoast.showToast(
        msg: 'password must be identical',
        timeInSecForIosWeb: 3,
        backgroundColor: context.colors.danger,
      );
      return;
    }
    if (_dobController.text.isEmpty) {
      Fluttertoast.showToast(
        msg: 'please select your birth of date',
        timeInSecForIosWeb: 3,
        backgroundColor: context.colors.danger,
      );
      return;
    }
    if (_usernameBlocks) {
      showAppNotice(
        _usernameStatus == UsernameStatus.checking
            ? 'username_wait_check'.tr
            : 'username_fix_first'.tr,
        error: _usernameStatus != UsernameStatus.checking,
      );
      return;
    }
    final authProvider = context.read<MyAuthProvider>();
    if (authProvider.selectedRole == null) {
      Fluttertoast.showToast(
        msg: 'please select your role',
        timeInSecForIosWeb: 3,
        backgroundColor: context.colors.danger,
      );
      return;
    }
    if (!_termsAccepted) {
      Fluttertoast.showToast(
        msg: 'يجب قراءة والموافقة على الشروط والأحكام',
        timeInSecForIosWeb: 3,
        backgroundColor: context.colors.danger,
      );
      return;
    }
    // The way the student picked (or the first one of the priority list).
    final allWays = verifyWaysForChannels(
      authProvider,
      policyChannels(authProvider),
    );
    final pickedWay = allWays.contains(_pickedWay)
        ? _pickedWay
        : (allWays.isEmpty ? null : allWays.first);
    // A phone is needed when the picked way uses it, or when the admin requires it anyway.
    final mustPhone =
        authProvider.verifyByPhone || (pickedWay?.isPhone ?? false);
    if (mustPhone && _phoneController.text.trim().isEmpty) {
      Fluttertoast.showToast(
        msg: 'phone_required'.tr,
        timeInSecForIosWeb: 3,
        backgroundColor: context.colors.danger,
      );
      return;
    }
    // A new student answers ONE short study step first (stage + grade, D-790), unless the super admin switched it off
    // or the kill switch hides it; its button creates the account.
    final studyStep = authProvider.selectedRole!['text'] == 'student' &&
        authProvider.studySettings.signupStep &&
        !AppConfig.disableList.contains(kStudyProfileFeatureKey);
    if (studyStep) {
      await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: '/register/study'),
        builder: (_) => StudyProfileStepPage(
          initial: _study,
          settings: authProvider.studySettings,
          busy: _busy,
          onChanged: (v) => _study = v,
          onSubmit: (v) => _submit(authProvider, pickedWay, study: v),
        ),
      ));
      return;
    }
    await _submit(authProvider, pickedWay);
  }

  Future<void> _submit(MyAuthProvider authProvider, VerifyWay? pickedWay, {StudyProfile? study}) async {
    _busy.value = true;
    final success = await authProvider.register(
      gmail: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      dob: _dobController.text.trim(),
      password: _passwordController.text,
      name: _fullNameController.text.trim(),
      way: pickedWay?.name,
      username: _usernameOn ? _usernameController.text : null,
      studyProfile: study?.toJson(withDob: false),
    );
    _busy.value = false;
    if (!mounted) return;
    // taken / reserved / invalid at submit: the field shows why, with the server's suggestions
    if (!success && authProvider.usernameError != null) {
      setState(() => _usernameError = authProvider.usernameError);
    }
    if (success) {
      // Open the verification page on the way the student chose (they can still switch there).
      final pendingWays = verifyWaysForChannels(
        authProvider,
        authProvider.pendingChannels,
      );
      final chosen = pendingWays.contains(_pickedWay) ? _pickedWay : null;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            initialWay: chosen,
            channels: authProvider.pendingChannels,
            phoneNumber: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            role: authProvider.selectedRole!['text'],
          ),
        ),
        (route) => false,
      );
    } else {
      Helpers.showMessage(
        authProvider.errorMessage ?? 'Registration failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MyAuthProvider>(
      builder: (context, provider, _) {
        return AuthScaffold(
          title: 'auth_register_title'.tr,
          subtitle: 'auth_register_sub'.tr,
          pageKey: const ValueKey('register'),
          // the longest form of the module: a wider card on desktop (phones are limited by the screen anyway)
          maxWidth: 640,
          builder: (context, isWide) => _buildForm(provider),
        );
      },
    );
  }

  Widget _buildForm(MyAuthProvider provider) {
    final c = context.colors;
    // Every verification way the admin allows, and the one currently selected.
    final ways = provider.policyLoaded
        ? verifyWaysForChannels(provider, policyChannels(provider))
        : const <VerifyWay>[];
    final selectedWay = ways.contains(_pickedWay)
        ? _pickedWay
        : (ways.isEmpty ? null : ways.first);
    const gap = SizedBox(height: AppSpace.md);
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ProgressBar(currentStep: 0, totalSteps: 3),
            const SizedBox(height: AppSpace.lg),

            // Join with Google: role sheet -> account created -> signed in
            const GoogleAuthSection(joining: true),

            // Full name
            IconTextField(
              controller: _fullNameController,
              label: 'full_name'.tr,
              icon: Icons.person_outline_rounded,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            gap,

            // Email
            AuthEmailField(controller: _emailController, label: 'email'.tr),
            gap,

            // @username — optional, checked while typing (kill switch auth.username)
            ParentComponent(
              featureKey: kUsernameFeatureKey,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: UsernameField(
                  controller: _usernameController,
                  error: _usernameError,
                  onStatusChanged: (s) => setState(() => _usernameStatus = s),
                ),
              ),
            ),

            // Phone — always shown when the admin verifies accounts by phone,
            // otherwise only if the 'register.phone' feature is enabled.
            Builder(
              builder: (context) {
                final needsPhone =
                    provider.verifyByPhone || (selectedWay?.isPhone ?? false);
                final phoneField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhoneInputField(
                      controller: _phoneController,
                      label: needsPhone
                          ? 'phone_with_country_code'.tr
                          : 'phone'.tr,
                      required: needsPhone,
                    ),
                    gap,
                  ],
                );
                // shown whenever a phone way is allowed (required only when the picked way needs it)
                return provider.hasPhoneWays
                    ? phoneField
                    : ParentComponent(
                        featureKey: 'register.phone',
                        child: phoneField,
                      );
              },
            ),
            // Date of birth
            ParentComponent(
              featureKey: 'register.dob',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SectionLabel(label: 'dob'.tr),
                  const SizedBox(height: AppSpace.xs),
                  AuthDateField(
                    onChange: (picked) => setState(() {
                      selectedDate = picked;
                      _dobController.text = "${selectedDate.toLocal()}".split(
                        ' ',
                      )[0];
                    }),
                    selectedDate: selectedDate,
                    controller: _dobController,
                    label: 'dob'.tr,
                  ),
                  gap,
                ],
              ),
            ),

            // Role
            ParentComponent(
              featureKey: 'register.role',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SectionLabel(label: 'auth_i_am'.tr),
                  const SizedBox(height: AppSpace.xs),
                  RolePicker(provider: provider, rolController: _rolController),
                  const SizedBox(height: AppSpace.lg),
                ],
              ),
            ),

            // Password
            IconPasswordField(
              controller: _passwordController,
              label: 'password'.tr,
              obscure: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              onChange: (v) {
                setState(() {});
              },
              onToggle: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            AnimatedSize(
              duration: AppMotion.of(context).base,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: _passwordController.text.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpace.sm),
                      child: ParentComponent(
                        featureKey: 'register.password_strength',
                        child: AuthPasswordStrength(
                          strength: _strength,
                          color: _strengthColor(c),
                          label: _strengthLabel(),
                          title: 'pw_strength_title'.tr,
                        ),
                      ),
                    ),
            ),
            gap,

            // Confirm password
            IconPasswordField(
              controller: _confirmedPasswordController,
              label: 'auth_confirm_password'.tr,
              obscure: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onChange: (v) {
                setState(() {});
              },
              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: AppSpace.sm),
            ParentComponent(
              featureKey: 'register.password_requirements',
              // a paper checklist with a warm hairline (the wells above are the input fill)
              child: Container(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: AppRadius.cardAll,
                  border: Border.all(color: c.divider, width: AppBorder.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('pw_req_title'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpace.xxs),
                    AuthRequirement(met: _reqMinLength, label: 'pw_req_min8'.tr),
                    AuthRequirement(met: _reqUppercase, label: 'pw_req_upper'.tr),
                    AuthRequirement(met: _reqDigit, label: 'pw_req_digit'.tr),
                    AuthRequirement(met: _reqMatch, label: 'pw_req_match'.tr),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),

            // Verification way — everything the admin allows; the student picks one here
            // and can still switch on the verification page.
            AnimatedSize(
              duration: AppMotion.of(context).slow,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: ways.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.lg),
                      child: VerifyWayPicker(
                        ways: ways,
                        selected: selectedWay,
                        provider: provider,
                        requireAll: provider.requireAll,
                        onChanged: (w) => setState(() => _pickedWay = w),
                      ),
                    ),
            ),

            // ── Terms acceptance row ─────────────────────────────────────
            AuthTermsRow(
              accepted: _termsAccepted,
              onReadTap: _openTerms,
              onPrivacyTap: () => openLegalPage(context, privacy: true),
              onCheckChanged: (v) {
                // Only allow manual un-tick; tick only via reading the sheet
                if (!v) setState(() => _termsAccepted = false);
              },
            ),
            const SizedBox(height: AppSpace.lg),

            // Submit
            AuthButton(
              loading: provider.isLoadingRegistration,
              label: 'auth_create_my_account'.tr,
              onPressed: _register,
              enabled: _canSubmit,
            ),
            const SizedBox(height: AppSpace.sm),

            ParentComponent(
              featureKey: 'register.login_link',
              child: LinkRow(
                message: 'have_account'.tr,
                linkText: 'auth_sign_in'.tr,
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Password helpers ──────────────────────────────────────────────────────
  bool get _reqMinLength => _passwordController.text.length >= 8;

  bool get _reqUppercase => _passwordController.text.contains(RegExp(r'[A-Z]'));

  bool get _reqDigit => _passwordController.text.contains(RegExp(r'[0-9]'));

  bool get _reqMatch =>
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmedPasswordController.text;

  bool get _canSubmit =>
      _reqMinLength && _reqMatch && _termsAccepted && !_usernameBlocks;

  int get _strength {
    if (_passwordController.text.isEmpty) return 0;
    int s = 0;
    if (_reqMinLength) s++;
    if (_reqUppercase) s++;
    if (_reqDigit) s++;
    if (_passwordController.text.length >= 10) s++;
    return s;
  }

  Color _strengthColor(ThemeConfigProvider c) => switch (_strength) {
    1 => c.danger,
    2 => c.warning,
    3 => c.success,
    4 => c.success,
    _ => c.divider,
  };

  String _strengthLabel() => switch (_strength) {
    1 => 'pw_strength_weak'.tr,
    2 => 'pw_strength_fair'.tr,
    3 => 'pw_strength_strong'.tr,
    4 => 'pw_strength_very_strong'.tr,
    _ => '',
  };
}

// ══════════════════════════════════════════════════════════════════════════════
//  Terms Accept Row  (inside the form) — plain values, pumped by the layout tests
// ══════════════════════════════════════════════════════════════════════════════

class AuthTermsRow extends StatelessWidget {
  const AuthTermsRow({
    super.key,
    required this.accepted,
    required this.onReadTap,
    required this.onCheckChanged,
    this.onPrivacyTap,
  });

  final bool accepted;
  final VoidCallback onReadTap;
  final ValueChanged<bool> onCheckChanged;

  /// "… and the Privacy policy" (D-308): the privacy link after the terms link.
  final VoidCallback? onPrivacyTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final link = appInk(context, c.primary); // AA on the row and on the Read button's tint, both modes
    final text = AppType.label(context).copyWith(height: 1.5);
    return AnimatedContainer(
      duration: AppMotion.of(context).base,
      curve: AppMotion.curve,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      // accepted = done: the success tint and line (emerald means done, D-610); otherwise paper on a hairline
      decoration: BoxDecoration(
        color: accepted ? c.successTint : c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: accepted ? c.success.withValues(alpha: 0.45) : c.divider,
          width: AppBorder.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Checkbox (48 dp target), named for screen readers
          MergeSemantics(
            child: Semantics(
              label: AppConfig.lang == 'ar' ? 'أوافق على الشروط والأحكام' : 'I agree to the terms and conditions',
              child: Checkbox(
                value: accepted,
                onChanged: (v) => onCheckChanged(v ?? false),
                activeColor: c.success,
                checkColor: c.onHero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.xxs + 2)),
                side: BorderSide(color: accepted ? c.success : c.textLight, width: AppBorder.strong),
              ),
            ),
          ),
          // Text + link
          Expanded(
            child: Text.rich(
              TextSpan(
                style: text,
                children: [
                  TextSpan(text: 'terms_agree_prefix'.tr),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    // a link (D-308, like the privacy link): an inline link is exempt from the 48 dp target rule
                    child: Semantics(
                      link: true,
                      child: GestureDetector(
                        onTap: onReadTap,
                        child: Text(
                          'terms_link'.tr,
                          style: text.copyWith(
                            fontWeight: FontWeight.w600,
                            color: link,
                            decoration: TextDecoration.underline,
                            decorationColor: link,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onPrivacyTap == null)
                    TextSpan(text: 'terms_agree_suffix'.tr)
                  else ...[
                    TextSpan(text: 'terms_agree_and'.tr),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: Semantics(
                        link: true,
                        child: GestureDetector(
                          onTap: onPrivacyTap,
                          child: Text(
                            'privacy_policy'.tr,
                            style: text.copyWith(
                              fontWeight: FontWeight.w600,
                              color: link,
                              decoration: TextDecoration.underline,
                              decorationColor: link,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          // Read button
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: TextButton(
            onPressed: onReadTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(AppTouch.min, AppTouch.min - AppSpace.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              backgroundColor: c.primaryTint,
              foregroundColor: link,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
            ),
            child: Text(
              accepted ? 'terms_read_again'.tr : 'terms_read_now'.tr,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: link, height: 1.2),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Terms Bottom Sheet
//  • Fetches sections from AboutTermsProvider
//  • Tracks scroll progress per section
//  • "Accept" button unlocks only after user scrolls to the end
// ══════════════════════════════════════════════════════════════════════════════

class _TermsBottomSheet extends StatefulWidget {
  const _TermsBottomSheet();

  @override
  State<_TermsBottomSheet> createState() => _TermsBottomSheetState();
}

class _TermsBottomSheetState extends State<_TermsBottomSheet> {
  final _scrollCtrl = ScrollController();
  bool _hasReadAll = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_hasReadAll) return;
    final pos = _scrollCtrl.position;
    // Consider "read" when within 48 px of the bottom
    if ((pos.pixels >= pos.maxScrollExtent - 48) ||
        context.read<AboutTermsProvider>().terms!.sections.every(
          (e) => e.accept,
        )) {
      setState(() => _hasReadAll = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AboutTermsProvider>();
    final c = context.colors;
    final screenH = MediaQuery.of(context).size.height;

    return Directionality(
      textDirection: pageDirection,
      child: SizedBox(
        height: screenH * 0.88,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.md),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: Row(
                children: [
                  const AuthMark(icon: Icons.description_outlined, size: AppTouch.min - AppSpace.xxs),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'terms_and_conditions'.tr,
                          style: AppType.pageTitle(context),
                        ),
                        if (p.terms?.meta != null)
                          Text(
                            '${'terms_last_updated'.tr}: ${p.terms!.meta!.lastUpdated}',
                            style: AppType.meta(context),
                          ),
                      ],
                    ),
                  ),
                  // Close
                  IconButton(
                    tooltip: 'close'.tr,
                    onPressed: () => Navigator.pop(context, false),
                    icon: Container(
                      width: AppTouch.min - AppSpace.xs,
                      height: AppTouch.min - AppSpace.xs,
                      decoration: BoxDecoration(
                        color: c.cardBg,
                        borderRadius: AppRadius.chipAll,
                        border: Border.all(color: c.divider, width: AppBorder.hairline),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: AppIconSize.md,
                        color: c.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xxs),

            // ── "Scroll to read" hint ────────────────────────────────────
            if (!_hasReadAll)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, 0),
                child: _ScrollHint(),
              ),

            Divider(color: c.divider, height: AppSpace.md, thickness: AppBorder.hairline),

            // ── Content ──────────────────────────────────────────────────
            Expanded(child: _buildContent(p, c)),

            // ── Bottom bar ───────────────────────────────────────────────
            _BottomBar(
              hasReadAll: _hasReadAll,
              onScrollToEnd: _scrollToEnd,
              onAccept: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AboutTermsProvider p, ThemeConfigProvider c) {
    // Loading
    if (p.isLoadingTerms) {
      return const Center(child: AppLoadingIndicator());
    }
    // Error
    if (p.termsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: AppIconSize.hero, color: c.textLight),
            const SizedBox(height: AppSpace.sm),
            Text(
              p.termsError!,
              style: AppType.body(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.md),
            AppButton.secondary(
              onPressed: () => p.loadTerms(context, forceRefresh: true),
              icon: Icons.refresh_rounded,
              label: 'retry'.tr,
            ),
          ],
        ),
      );
    }
    // Empty
    if (p.terms == null || p.terms!.sections.isEmpty) {
      return Center(
        child: Text(
          'terms_empty'.tr,
          style: AppType.body(context),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
      itemCount: p.terms!.sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (_, i) => _SectionCard(
        section: p.terms!.sections[i],
        index: i,
        onTap: (TermsSectionModel t) {
          t.toggle();
          setState(() {});
        },
      ),
    );
  }

  void _scrollToEnd() {
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: authReduceMotion(context) ? const Duration(milliseconds: 1) : const Duration(milliseconds: 600),
      curve: AppMotion.emphasized,
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.index,
    required this.onTap,
  });

  final TermsSectionModel section;
  final int index;
  final void Function(TermsSectionModel t) onTap;

  // icon resolver
  static IconData _icon(String name) => _iconMap[name] ?? Icons.circle_outlined;
  static const _iconMap = <String, IconData>{
    'gavel': Icons.gavel_rounded,
    'person': Icons.person_outline_rounded,
    'school': Icons.school_outlined,
    'payment': Icons.payment_outlined,
    'shield': Icons.shield_outlined,
    'block': Icons.block_outlined,
    'update': Icons.update_rounded,
    'description': Icons.description_outlined,
    'lock': Icons.lock_outline_rounded,
    'verified': Icons.verified_outlined,
    'help': Icons.help_outline_rounded,
    'info': Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: AppTouch.min - AppSpace.sm,
                height: AppTouch.min - AppSpace.sm,
                decoration: BoxDecoration(
                  color: c.inputBg,
                  borderRadius: AppRadius.chipAll,
                ),
                child: Icon(
                  _icon(section.iconName),
                  size: AppIconSize.sm,
                  color: c.textDark,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(section.title, style: AppType.bodyStrong(context)),
              ),
              InkWell(
                onTap: () {
                  onTap.call(section);
                },
                borderRadius: AppRadius.chipAll,
                child: SizedBox(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  child: Icon(
                    section.accept
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: AppIconSize.md,
                    color: section.accept ? c.success : c.textLight,
                  ),
                ),
              ),
              // Section number
            ],
          ),
          Divider(color: c.divider, height: AppSpace.md, thickness: AppBorder.hairline),
          // Body
          Text(
            section.body,
            style: AppType.body(context).copyWith(height: 1.75),
          ),
        ],
      ),
    );
  }
}

// ── Scroll hint banner ────────────────────────────────────────────────────────

class _ScrollHint extends StatefulWidget {
  @override
  State<_ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<_ScrollHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _bounce = Tween<double>(
      begin: 0,
      end: 6,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _anim, reverse: true, rest: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = AppBlockColors.of(context, AppBlockTone.sky);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: AppRadius.controlAll,
        border: tone.border == null ? null : Border.all(color: tone.border!, width: AppBorder.hairline),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _bounce,
            builder: (_, _) => Transform.translate(
              offset: Offset(0, _bounce.value),
              child: Icon(
                Icons.keyboard_double_arrow_down_rounded,
                size: AppIconSize.md,
                color: tone.ink,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              'terms_scroll_hint'.tr,
              style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.hasReadAll,
    required this.onScrollToEnd,
    required this.onAccept,
  });

  final bool hasReadAll;
  final VoidCallback onScrollToEnd;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm + bottom),
      // a warm hairline over the bar (tone first, no shadow)
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child:
          hasReadAll ||
              context.read<AboutTermsProvider>().terms!.sections.every(
                (e) => e.accept,
              )
          // ── Unlocked: show accept button ─────────────────────────────
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success hint
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: AppSpace.xs,
                  ),
                  margin: const EdgeInsets.only(bottom: AppSpace.sm),
                  decoration: BoxDecoration(
                    color: c.successTint,
                    borderRadius: AppRadius.controlAll,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: AppIconSize.md,
                        color: c.success,
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          'terms_read_all_done'.tr,
                          style: AppType.label(context).copyWith(
                            color: appInk(context, c.success),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Accept button: the sheet's one primary action
                AuthButton(
                  onPressed: onAccept,
                  icon: Icons.verified_outlined,
                  iconBefore: true,
                  label: 'terms_accept_button'.tr,
                ),
              ],
            )
          // ── Locked: nudge user to scroll ─────────────────────────────
          : AppButton.secondary(
              onPressed: onScrollToEnd,
              expand: true,
              size: AppButtonSize.lg,
              icon: Icons.keyboard_double_arrow_down_rounded,
              label: 'terms_jump_to_end'.tr,
            ),
    );
  }
}
