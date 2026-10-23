import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../utils/helpers.dart';
import '../../utils/widget/primary_button.dart';
import '../shared/guest/guest_state.dart';
import 'auth_provider.dart';
import 'auth_widgets.dart';
import 'forget_screen.dart';
import 'google_auth_flow.dart';
import 'register_screen.dart';
import '../../utils/widget/parent_component.dart';
import '../org/org_application_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController.clear();
    _passwordController.clear();
    // Which identifiers the admin allows (email / phone / either).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MyAuthProvider>().loadPolicy();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<MyAuthProvider>();
    final success = await authProvider.login(
      gmail: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      authProvider.loadCachedUser();
      if (mounted) {
        Navigator.of(context).pushNamed(authProvider.homeRoute);
      }
    } else if (authProvider.needsVerification) {
      Helpers.showMessage('account_not_verified'.tr, isError: false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            // Always the account e-mail from the server (the user may have typed a phone).
            email: authProvider.pendingGmail ?? _emailController.text.trim(),
            channels: authProvider.pendingChannels,
            phoneNumber: authProvider.pendingPhoneMasked,
            role: authProvider.pendingRole ?? 'student',
            flow: OtpFlowEnum.registration,
          ),
        ),
      );
    } else {
      Helpers.showMessage(
        authProvider.errorMessage ?? 'incorrect_email_or_password'.tr,
        isError: true,
      );
    }
  }

  // ── Language switch ──────────────────────────────────────────────────────
  bool get _isArabic => AppConfig.lang == 'ar';

  Future<void> _toggleLang() async {
    await context.read<LangProvider>().changeLang(_isArabic ? 'en' : 'ar');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LangProvider>(
      builder: (context, l, _) {
        return BasePage(
          child: MediaQuery.of(context).size.width > 800
              ? _buildWideLayout()
              : _buildNarrowLayout(),
        );
      },
    );
  }

  // ── Wide (web) layout: sidebar + centered form panel ─────────────────────
  Widget _buildWideLayout() {
    return Row(
      children: [
        AuthSidebar(),
        Spacer(),
        Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ClipRRect(
            borderRadius: BorderRadiusGeometry.circular(
              context.colors.radiusXL,
            ),
            child: ColoredBox(
              color: context.colors.isDark
                  ? context.colors.cardBg
                  : context.colors.primary.withAlpha(30),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 32,
                    ),
                    child: _buildFormCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Spacer(),

      ],
    );
  }

  // ── Narrow (mobile) layout ───────────────────────────────────────────────
  Widget _buildNarrowLayout() {
    return Center(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildFormCard(),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    final c = context.colors;
    final provider = context.read<ProfileProvider>();
    final heightUnit = context.height / 100;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top bar: logo on the start side, both switches on the end ────
          Row(
            children: [
              AppNetworkImage(
                url: 'assets/images/logo.png',
                width: 130,
                height: 130,
                heroTag: "logo-login",
                fit: BoxFit.scaleDown,
                color: c.background,
              ),
              const Spacer(),
              Column(
                children: [
                  _langSwitch(provider),
                  const SizedBox(height: 10),
                  _themeSwitch(provider),
                ],
              ),
            ],
          ),

          // ── Title block ──────────────────────────────────────────────────
          Container(
            width: 100,
            height: 5,
            decoration: BoxDecoration(
              gradient: c.accentGradient,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'login'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: c.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'login_welcome'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.secondText,
            ),
          ),
          SizedBox(height: heightUnit * 2.5),

          // ── Email / phone / either — controlled by the admin ─────────────
          Builder(
            builder: (context) {
              final a = context.watch<MyAuthProvider>();
              final phoneOnly = !a.loginAllowsEmail;
              final both = a.loginAllowsEmail && a.loginAllowsPhone;
              return IconTextField(
                controller: _emailController,
                label: phoneOnly
                    ? 'phone'.tr
                    : both
                    ? 'email_or_phone'.tr
                    : 'email'.tr,
                icon: phoneOnly
                    ? Icons.phone_outlined
                    : both
                    ? Icons.person_outline
                    : Icons.email_outlined,
                keyboard: phoneOnly
                    ? TextInputType.phone
                    : both
                    ? TextInputType.text
                    : TextInputType.emailAddress,
              );
            },
          ),
          SizedBox(height: heightUnit),

          // ── Password ─────────────────────────────────────────────────────
          IconPasswordField(
            controller: _passwordController,
            label: 'password'.tr,
          ),
          const SizedBox(height: 10),

          // ── Forgot password (end aligned) ────────────────────────────────
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ForgetScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'forget_password'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 13.5,
                    color: c.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: heightUnit * 3),

          // ── Login button ─────────────────────────────────────────────────
          PrimaryButton(
            isLoading: context.watch<MyAuthProvider>().isLoadingLogin,
            label: 'login'.tr,
            icon: Icons.arrow_forward_rounded,
            onPressed: _login,
          ),

          SizedBox(height: heightUnit * 2),
          LinkRow(
            message: "doesn't_have_account".tr,
            linkText: 'register'.tr,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
          ),
          // institutions apply here; the platform team approves them before any dashboard opens
          ParentComponent(
            featureKey: 'register.organization',
            child: Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgApplicationScreen())),
                icon: const Icon(Icons.domain_add_rounded, size: 18),
                label: Text('register_organization'.tr),
              ),
            ),
          ),
          SizedBox(height: heightUnit * 1.5),

          // ── Continue with Google ─────────────────────────────────────────
          const GoogleAuthSection(joining: true, smallIcon: true),
          SizedBox(height: heightUnit * 1.5),

          // ── Register + guest on ONE row (saves a full row of height) ─────
          Center(
            child: Builder(
              builder: (context) {
                final guestEnabled = !AppConfig.disableList.contains(
                  'guest_mode',
                );
                if (!guestEnabled) return SizedBox.shrink();
                return _guestButton();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _guestButton() {
    final c = context.colors;
    return Material(
      color: c.primary.withAlpha(c.isDark ? 28 : 18),
      borderRadius: BorderRadius.circular(40),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () => startGuest(Navigator.of(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, size: 16, color: c.primary),
              const SizedBox(width: 6),
              Text(
                'continue_as_guest'.tr,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Switches (same look for theme and language) ──────────────────────────
  Widget _themeSwitch(ProfileProvider provider) {
    final dark = provider.darkMode;
    return _PillSwitch(
      tooltip: dark ? 'Light' : 'Dark',
      isEnd: dark,
      dark: dark,
      gradient: dark
          ? const LinearGradient(colors: [Color(0xff0F172A), Color(0xff1E293B)])
          : context.colors.accentGradient,
      knob: Icon(
        dark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
        key: ValueKey(dark),
        color: dark ? Colors.indigo : Colors.orange,
        size: 18,
      ),
      onTap: () => provider.changeMode(!provider.darkMode),
    );
  }

  Widget _langSwitch(ProfileProvider provider) {
    final ar = _isArabic;
    final dark = provider.darkMode;
    return _PillSwitch(
      tooltip: ar ? 'English' : 'العربية',
      // Physical positions: EN on the left, AR on the right.
      isEnd: ar,
      physical: true,
      dark: dark,
      gradient: dark
          ? const LinearGradient(colors: [Color(0xff0F172A), Color(0xff1E293B)])
          : context.colors.accentGradient,
      knob: Text(
        ar ? 'ع' : 'EN',
        key: ValueKey(ar),
        style: TextStyle(
          fontFamily: 'tajawal',
          fontSize: ar ? 17 : 12,
          fontWeight: FontWeight.w800,
          color: dark ? Colors.indigo : context.colors.primary,
        ),
      ),
      onTap: _toggleLang,
    );
  }
}

/// Animated pill toggle shared by the theme and language switches.
class _PillSwitch extends StatelessWidget {
  final bool isEnd;
  final bool dark;
  final bool physical;
  final Gradient gradient;
  final Widget knob;
  final VoidCallback onTap;
  final String tooltip;

  const _PillSwitch({
    required this.isEnd,
    required this.dark,
    required this.gradient,
    required this.knob,
    required this.onTap,
    required this.tooltip,
    this.physical = false,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isEnd ? Alignment.centerRight : Alignment.centerLeft;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 72,
          height: 38.0,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(dark ? 80 : 30),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          // Force LTR inside so the knob always slides the same physical way.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              alignment: alignment,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Container(
                  key: ValueKey('$isEnd$dark'),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: knob,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
