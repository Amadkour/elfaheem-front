// ─────────────────────────────────────────────────────────────────────────────
// features/auth/register_screen.dart
// Registration screen with server-driven Terms & Conditions gate.
// User must scroll to the bottom of every section before the accept checkbox
// unlocks — and must tick the checkbox before the submit button activates.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/date_picker_widget.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../utils/widget/primary_button.dart';
import '../shared/profile/about/about_terms_model.dart';
import '../shared/profile/about/about_terms_provider.dart';
import '../shared/profile/change_password_widget.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'auth_widgets.dart';
import 'google_auth_flow.dart';
import 'verify_way.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Register Screen
// ══════════════════════════════════════════════════════════════════════════════

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

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
  final _rolController = ExpansibleController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Whether the user has ticked the "I accept" checkbox after reading terms.
  bool _termsAccepted = false;

  /// The verification way the student picked (null = the first one the admin allows).
  VerifyWay? _pickedWay;

  DateTime selectedDate = DateTime.now().subtract(
    const Duration(days: 360 * 20),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    super.dispose();
  }

  // ── Open terms bottom-sheet ───────────────────────────────────────────────
  Future<void> _openTerms() async {
    context.read<AboutTermsProvider>().clearSelection();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    if (authProvider.verifyByPhone && _phoneController.text.trim().isEmpty) {
      Fluttertoast.showToast(
        msg: 'phone_required'.tr,
        timeInSecForIosWeb: 3,
        backgroundColor: context.colors.danger,
      );
      return;
    }
    final success = await authProvider.register(
      gmail: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      dob: _dobController.text.trim(),
      password: _passwordController.text,
      name: _fullNameController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      // Open the verification page on the way the student chose (they can still switch there).
      final pendingWays = verifyWaysForChannels(authProvider, authProvider.pendingChannels);
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
    final isWide = MediaQuery.of(context).size.width > 800;
    return Consumer<MyAuthProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: BasePage(key: const ValueKey('register'), child: isWide
              ? _buildWideLayout(provider)
              : _buildNarrowLayout(provider),
          ),
        );
      },
    );
  }

  Widget _buildWideLayout(MyAuthProvider provider) => Row(
    children: [
      AuthSidebar(),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
            child: SizedBox(width: 800, child: _buildForm(provider)),
          ),
        ),
      ),
    ],
  );

  Widget _buildNarrowLayout(MyAuthProvider provider) => Center(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: _buildForm(provider),
      ),
    ),
  );

  Widget _buildForm(MyAuthProvider provider) {
    final c = context.colors;
    // Every verification way the admin allows, and the one currently selected.
    final ways = provider.policyLoaded
        ? verifyWaysForChannels(provider, policyChannels(provider))
        : const <VerifyWay>[];
    final selectedWay = ways.contains(_pickedWay)
        ? _pickedWay
        : (ways.isEmpty ? null : ways.first);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressBar(currentStep: 0, totalSteps: 3),
          const SizedBox(height: 28),

          // Back
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back_ios_rounded, size: 14),
                const SizedBox(width: 4),
                Text(
                  'login'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: c.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'create_account'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: c.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'registration_welcome'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 14,
              color: c.secondText,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          // Join with Google: role sheet -> account created -> signed in
          const GoogleAuthSection(joining: true),

          // Full name
          IconTextField(
            controller: _fullNameController,
            label: 'full_name'.tr,
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 20),

          // Email
          IconTextField(
            controller: _emailController,
            label: 'email'.tr,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),

          // Phone — always shown when the admin verifies accounts by phone,
          // otherwise only if the 'register.phone' feature is enabled.
          Builder(builder: (context) {
            final phoneField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTextField(
                  controller: _phoneController,
                  label: context.read<MyAuthProvider>().verifyByPhone
                      ? 'phone_with_country_code'.tr
                      : 'phone'.tr,
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                ),
                const SizedBox(height: 20),
              ],
            );
            return context.watch<MyAuthProvider>().verifyByPhone
                ? phoneField
                : ParentComponent(featureKey: 'register.phone', child: phoneField);
          }),

          // Verification way — everything the admin allows; the student picks one here
          // and can still switch on the verification page.
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ways.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: VerifyWayPicker(
                ways: ways,
                selected: selectedWay,
                provider: provider,
                requireAll: provider.verificationMethod == 'both',
                onChanged: (w) => setState(() => _pickedWay = w),
              ),
            ),
          ),

          // Date of birth
          ParentComponent(featureKey: 'register.dob', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [SectionLabel(label: 'dob'.tr),
            const SizedBox(height: 8),
            MyDatePicker(
              onChange: (picked) => setState(() {
                selectedDate = picked;
                _dobController.text = "${selectedDate.toLocal()}".split(' ')[0];
              }),
              selectedDate: selectedDate,
              controller: _dobController,
              label: 'dob'.tr,
            ),
            const SizedBox(height: 20)])),

          // Role
          ParentComponent(featureKey: 'register.role', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [SectionLabel(label: 'role'.tr),
            const SizedBox(height: 10),
            RolePicker(provider: provider, rolController: _rolController),
            const SizedBox(height: 20)])),

          // Password
          IconPasswordField(
            controller: _passwordController,
            label: 'password'.tr,
            obscure: _obscurePassword,
            onToggle: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          const SizedBox(height: 20),
          if (_passwordController.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            ParentComponent(featureKey: 'register.password_strength', child: StrengthBar(
              strength: _strength,
              strengthColor: _strengthColor(c),
              strengthLabel: _strengthLabel(),
              c: c,
            )),
          ],

          // Confirm password
          IconPasswordField(
            controller: _confirmedPasswordController,
            label: 'confirmed_password'.tr,
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          ParentComponent(featureKey: 'register.password_requirements', child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: c.brMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المتطلبات', style: c.label.copyWith(fontSize: 12)),
                const SizedBox(height: 10),
                PasswordReq(
                  met: _reqMinLength,
                  label: '٦ أحرف على الأقل',
                  c: c,
                ),
                PasswordReq(
                  met: _reqUppercase,
                  label: 'حرف كبير واحد على الأقل (A-Z)',
                  c: c,
                ),
                PasswordReq(
                  met: _reqDigit,
                  label: 'رقم واحد على الأقل (0-9)',
                  c: c,
                ),
                PasswordReq(
                  met: _reqMatch,
                  label: 'تطابق كلمة المرور الجديدة',
                  c: c,
                ),
              ],
            ),
          )),
          const SizedBox(height: 24),

          // ── Terms acceptance row ─────────────────────────────────────
          _TermsAcceptRow(
            accepted: _termsAccepted,
            onReadTap: _openTerms,
            onCheckChanged: (v) {
              // Only allow manual un-tick; tick only via reading the sheet
              if (!v) setState(() => _termsAccepted = false);
            },
          ),
          const SizedBox(height: 20),

          // Submit
          PrimaryButton(
            isLoading: provider.isLoadingRegistration,
            label: 'confirm'.tr,
            icon: Icons.check_rounded,
            onPressed: _register,
            enable: _canSubmit,
          ),
          const SizedBox(height: 20),

          ParentComponent(featureKey: 'register.login_link', child: LinkRow(
            message: 'have_account'.tr,
            linkText: 'login'.tr,
            onTap: () => Navigator.pop(context),
          )),
        ],
      ),
    );
  }

  // ── Password helpers ──────────────────────────────────────────────────────
  bool get _reqMinLength => _passwordController.text.length >= 6;

  bool get _reqUppercase => _passwordController.text.contains(RegExp(r'[A-Z]'));

  bool get _reqDigit => _passwordController.text.contains(RegExp(r'[0-9]'));

  bool get _reqMatch =>
      _passwordController.text.isNotEmpty &&
          _passwordController.text == _confirmedPasswordController.text;

  bool get _canSubmit => _reqMinLength && _reqMatch && _termsAccepted;

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
    4 => c.primary,
    _ => c.divider,
  };

  String _strengthLabel() => switch (_strength) {
    1 => 'ضعيف',
    2 => 'مقبول',
    3 => 'قوي',
    4 => 'قوي جداً',
    _ => '',
  };
}

// ══════════════════════════════════════════════════════════════════════════════
//  Terms Accept Row  (inside the form)
// ══════════════════════════════════════════════════════════════════════════════

class _TermsAcceptRow extends StatelessWidget {
  const _TermsAcceptRow({
    required this.accepted,
    required this.onReadTap,
    required this.onCheckChanged,
  });

  final bool accepted;
  final VoidCallback onReadTap;
  final ValueChanged<bool> onCheckChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accepted
            ? c.success.withValues(alpha: 0.07)
            : c.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accepted
              ? c.success.withValues(alpha: 0.35)
              : c.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Checkbox
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: accepted,
              onChanged: (v) => onCheckChanged(v ?? false),
              activeColor: c.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              side: BorderSide(
                color: accepted ? c.success : c.textLight,
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Text + link
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 13,
                  color: c.textMedium,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'أوافق على '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: onReadTap,
                      child: Text(
                        'الشروط والأحكام',
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 13,
                          color: c.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: c.primary,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' الخاصة بالمنصة'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Read button
          GestureDetector(
            onTap: onReadTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                accepted ? 'إعادة القراءة' : 'اقرأ الآن',
                style: const TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
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
      textDirection: TextDirection.rtl,
      child: Container(
        height: screenH * 0.88,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drag handle ─────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: c.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: c.primaryShadow,
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الشروط والأحكام',
                          style: c.h2.copyWith(fontSize: 17),
                        ),
                        if (p.terms?.meta != null)
                          Text(
                            'آخر تحديث: ${p.terms!.meta!.lastUpdated}',
                            style: c.caption.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  // Close
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: c.textMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── "Scroll to read" hint ────────────────────────────────────
            if (!_hasReadAll)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _ScrollHint(),
              ),

            Divider(color: c.divider, height: 16),

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
            Icon(Icons.wifi_off_rounded, size: 48, color: c.textLight),
            const SizedBox(height: 12),
            Text(
              p.termsError!,
              style: c.body.copyWith(color: c.textMedium),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => p.loadTerms(context, forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'tajawal'),
              ),
            ),
          ],
        ),
      );
    }
    // Empty
    if (p.terms == null || p.terms!.sections.isEmpty) {
      return Center(
        child: Text(
          'لا توجد شروط وأحكام متاحة حالياً',
          style: c.body.copyWith(color: c.textMedium),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: p.terms!.sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
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
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _icon(section.iconName),
                  size: 17,
                  color: c.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(section.title, style: c.h3.copyWith(fontSize: 14)),
              ),
              InkWell(
                onTap: () {
                  onTap.call(section);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.successTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    section.accept
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 17,
                    color: c.success,
                  ),
                ),
              ),
              // Section number
            ],
          ),
          Divider(color: c.divider, height: 20),
          // Body
          Text(
            section.body,
            style: c.body.copyWith(height: 1.85, fontSize: 13.5),
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
    )..repeat(reverse: true);
    _bounce = Tween<double>(
      begin: 0,
      end: 6,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _bounce,
            builder: (_, _) => Transform.translate(
              offset: Offset(0, _bounce.value),
              child: Icon(
                Icons.keyboard_double_arrow_down_rounded,
                size: 18,
                color: c.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'يرجى قراءة جميع الشروط والتمرير إلى الأسفل لتفعيل زر القبول',
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 12,
                color: c.primary,
                fontWeight: FontWeight.w600,
              ),
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
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
      decoration: BoxDecoration(
        color: c.cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
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
              horizontal: 14,
              vertical: 8,
            ),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: c.successTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: c.success.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: c.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لقد قرأت جميع الشروط، يمكنك الموافقة الآن',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      color: c.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Accept button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAccept,
              style: FilledButton.styleFrom(
                backgroundColor: c.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                Icons.verified_outlined,
                color: Colors.white,
              ),
              label: const Text(
                'أوافق على الشروط والأحكام',
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      )
      // ── Locked: nudge user to scroll ─────────────────────────────
          : SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onScrollToEnd,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            side: BorderSide(color: c.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Icon(
            Icons.keyboard_double_arrow_down_rounded,
            color: c.primary,
          ),
          label: Text(
            'انتقل إلى نهاية الشروط',
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.primary,
            ),
          ),
        ),
      ),
    );
  }
}