import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../utils/helpers.dart';
import '../shared/guest/guest_state.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart';
import 'forget_screen.dart';
import 'google_auth_flow.dart';
import 'mfa.dart';
import 'mfa_verify_screen.dart';
import 'register_screen.dart';
import 'username.dart' show IdentifierIconData;
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
      // lets the platform's password manager offer to save the sign-in
      TextInput.finishAutofillContext();
      authProvider.loadCachedUser();
      if (mounted) {
        Navigator.of(context).pushNamed(authProvider.homeRoute);
      }
    } else if (authProvider.mfaStep.kind != MfaStepKind.none) {
      // two-step verification: the code (or, when the role requires it, the enrollment) comes first
      await openMfaStep(Navigator.of(context), authProvider);
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'auth_welcome_back'.tr,
      subtitle: 'auth_login_sub'.tr,
      builder: (context, isWide) => _buildForm(),
    );
  }

  Widget _buildForm() {
    final c = context.colors;
    final link = c.isDark ? c.primaryLight : c.primary;
    final guestEnabled = !AppConfig.disableList.contains('guest_mode');

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Email / phone / either (+ @username) — controlled by the admin ─
            Builder(
              builder: (context) {
                final spec = context.watch<MyAuthProvider>().identifierSpec;
                return IconTextField(
                  controller: _emailController,
                  label: spec.labelKey.tr,
                  icon: spec.icon.data,
                  keyboard: spec.keyboard,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  textInputAction: TextInputAction.next,
                );
              },
            ),
            const SizedBox(height: 16),

            // ── Password ───────────────────────────────────────────────────
            IconPasswordField(
              controller: _passwordController,
              label: 'password'.tr,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),

            // ── Forgot password (end aligned) ──────────────────────────────
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgetScreen())),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  foregroundColor: link,
                ),
                child: Text('auth_forgot'.tr, style: authText(13.5, w: FontWeight.w700, c: link)),
              ),
            ),
            const SizedBox(height: 8),

            // ── Sign in ────────────────────────────────────────────────────
            AuthButton(
              loading: context.watch<MyAuthProvider>().isLoadingLogin,
              label: 'auth_sign_in'.tr,
              icon: Icons.arrow_forward_rounded,
              onPressed: _login,
            ),
            const SizedBox(height: 24),

            // ── or · Continue with Google ──────────────────────────────────
            const GoogleAuthSection(joining: true, smallIcon: true),
            const SizedBox(height: 16),

            LinkRow(
              message: 'auth_no_account'.tr,
              linkText: 'auth_create_account'.tr,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
            ),
            const SizedBox(height: 8),

            // ── Institutions apply · explore as a guest ────────────────────
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // institutions apply here; the platform team approves them before any dashboard opens
                ParentComponent(
                  featureKey: 'register.organization',
                  child: AuthTextAction(
                    icon: Icons.domain_add_rounded,
                    label: 'register_organization'.tr,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgApplicationScreen())),
                  ),
                ),
                if (guestEnabled)
                  AuthTextAction(
                    icon: Icons.explore_outlined,
                    label: 'continue_as_guest'.tr,
                    onTap: () => startGuest(Navigator.of(context)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
