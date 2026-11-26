import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_charts.dart' show appInk;
import '../../design/app_area.dart' show AppAreaScope;
import '../../design/app_kit.dart' show appConfirm;
import '../../design/app_motion_kit.dart' show AppFeedback, AppFeedbackController;
import '../../design/app_tokens.dart';
import '../../design/app_notice.dart';
import '../../utils/helpers.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart';
import 'biometric.dart';
import 'biometric_widgets.dart';
import 'forget_screen.dart';
import 'kid_code/kid_code_api.dart' show kKidCodeFeature;
import 'kid_code/kid_code_screen.dart';
import 'google_auth_flow.dart';
import 'mfa.dart';
import 'mfa_verify_screen.dart';
import 'register_screen.dart';
import 'username.dart' show IdentifierIconData;
import '../../utils/widget/parent_component.dart';
import '../org/org_application_screen.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_logic.dart' show kCertVerifyFeature;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show openCertVerify;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bio = BiometricAuth.instance;

  /// M15: the fields shake on a wrong sign-in.
  final _shake = AppFeedbackController();

  @override
  void initState() {
    super.initState();
    _emailController.clear();
    _passwordController.clear();
    // Which identifiers the admin allows (email / phone / either).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MyAuthProvider>().loadPolicy();
      _initBiometric();
    });
  }

  /// A remembered fingerprint account (D-082): its identifier stands in for the field, and the system prompt opens by
  /// itself once per app run (never right after a sign-out).
  Future<void> _initBiometric() async {
    await _bio.load();
    if (!mounted) return;
    if (_bio.takeAutoPrompt()) await _biometricLogin();
  }

  /// The identifier of the remembered account shown at the top of the card, or null (the field is shown then).
  String? _rememberedIdentifier(BiometricRecord? rec) {
    final id = rec?.identifier?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  String get _identifier =>
      _rememberedIdentifier(_bio.available ? _bio.record : null) ?? _emailController.text.trim();

  Future<void> _biometricLogin() async {
    final auth = context.read<MyAuthProvider>();
    final out = await auth.loginWithBiometric();
    if (!mounted) return;
    switch (out) {
      case BiometricOutcome.session:
        auth.loadCachedUser();
        Navigator.of(context).pushNamedAndRemoveUntil(auth.homeRoute, (_) => false); // no sign-in page under the home (D-170)
      case BiometricOutcome.mfa:
        await openMfaStep(Navigator.of(context), auth);
      default:
        final m = biometricOutcomeNotice(out, message: auth.biometricError);
        if (m != null) showAppNotice(m, error: out != BiometricOutcome.gone);
    }
  }

  Future<void> _forgetBiometric() async {
    final ok = await appConfirm(context, message: 'bio_forget_body'.tr, confirmLabel: 'bio_forget'.tr);
    if (!ok || !mounted) return;
    await _bio.forget();
    _emailController.clear();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<MyAuthProvider>();
    final success = await authProvider.login(
      gmail: _identifier,
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      // lets the platform's password manager offer to save the sign-in
      TextInput.finishAutofillContext();
      authProvider.loadCachedUser();
      // "Sign in with your fingerprint next time?" — once per account on this phone (D-082)
      await maybeOfferBiometric(context, authProvider, identifier: _identifier);
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(authProvider.homeRoute, (_) => false); // no sign-in page under the home (D-170)
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
            email: authProvider.pendingGmail ?? _identifier,
            channels: authProvider.pendingChannels,
            phoneNumber: authProvider.pendingPhoneMasked,
            role: authProvider.pendingRole ?? 'student',
            flow: OtpFlowEnum.registration,
          ),
        ),
      );
    } else {
      _shake.shake();
      Helpers.showMessage(
        authProvider.errorMessage ?? 'incorrect_email_or_password'.tr,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _bio,
      builder: (context, _) {
        final rec = _bio.available ? _bio.record : null;
        final first = rec?.firstName ?? '';
        return AuthScaffold(
          kicker: 'sa_login_kicker'.tr,
          heroTitle: 'sa_login_hero'.tr,
          squiggle: 'sa_login_squiggle'.tr,
          heroSubtitle: 'sa_login_hero_sub'.tr,
          title: first.isNotEmpty ? 'bio_welcome_name'.tr.replaceAll('{name}', first) : 'sa_login_title'.tr,
          // the 5-second rule: no line under the welcome unless a remembered account needs one
          subtitle: rec != null ? 'bio_login_sub'.tr : null,
          builder: (context, isWide) => _buildForm(rec),
        );
      },
    );
  }

  Widget _buildForm(BiometricRecord? rec) {
    final c = context.colors;
    // the readable ink of the primary on the card (the raw primary was 3:1 on it, light and dark)
    final link = appInk(context, c.primary);
    final guestEnabled = !AppConfig.disableList.contains('guest_mode');

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── A remembered fingerprint / Face ID account (D-082) ─────────
            if (rec != null)
              BiometricQuickSignIn(
                name: rec.name,
                initials: rec.initials,
                identifier: rec.identifier,
                imageUrl: rec.imageUrl,
                kind: _bio.kind,
                busy: context.watch<MyAuthProvider>().isLoadingBiometric,
                onSignIn: _biometricLogin,
                onForget: _forgetBiometric,
              ),
            // ── Email / phone / either (+ @username) — controlled by the admin ─
            // (a remembered account already shows who signs in: its identifier is used, "Not you?" brings the field back)
            AppFeedback(
              controller: _shake,
              borderRadius: AppRadius.controlAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_rememberedIdentifier(rec) == null) ...[
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
                    const SizedBox(height: AppSpace.md),
                  ],

                  // ── Password, "forgot it?" at the end of its label row ─────
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconPasswordField(
                        controller: _passwordController,
                        label: 'password'.tr,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                      ),
                      PositionedDirectional(
                        end: 0,
                        top: -AppSpace.sm,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgetScreen())),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(AppTouch.min, AppTouch.min),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                            foregroundColor: link,
                          ),
                          child: Text('sa_login_forgot'.tr, style: AppType.label(context).copyWith(color: link, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),

            // ── Sign in ────────────────────────────────────────────────────
            AuthButton(
              loading: context.watch<MyAuthProvider>().isLoadingLogin,
              label: 'sa_login_enter'.tr,
              onPressed: _login,
            ),
            const SizedBox(height: AppSpace.lg),

            // ── or · Continue with Google ──────────────────────────────────
            const GoogleAuthSection(joining: true, smallIcon: true),
            const SizedBox(height: AppSpace.md),

            // ── The child's first sign-in with the parent's code (WP7) ──────
            ParentComponent(
              featureKey: kKidCodeFeature,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: KidCodeEntryTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KidCodeScreen())),
                ),
              ),
            ),

            // ── New here? Create an account • continue as a guest ─────────
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('sa_login_new'.tr, style: AppType.body(context).copyWith(color: c.textMedium)),
                _LoginLink(
                  label: 'sa_login_create'.tr,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                ),
                if (guestEnabled) ...[
                  ExcludeSemantics(child: Text('•', style: AppType.meta(context).copyWith(color: c.textLight))),
                  _LoginLink(label: 'sa_login_guest'.tr, onTap: () => startGuest(Navigator.of(context))),
                ],
              ],
            ),

            // ── Verify a certificate · institutions apply (kept, quiet) ─────
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                // the public check (D-420): no account, no authenticated call
                ParentComponent(
                  featureKey: kCertVerifyFeature,
                  child: AuthTextAction(
                    icon: Icons.verified_user_outlined,
                    label: 'cv_entry_title'.tr,
                    onTap: () => openCertVerify(context),
                  ),
                ),
                // institutions apply here; the platform team approves them before any dashboard opens
                ParentComponent(
                  featureKey: 'register.organization',
                  child: AuthTextAction(
                    icon: Icons.domain_add_rounded,
                    label: 'register_organization'.tr,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgApplicationScreen())),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A link of the login card's last row: the area's ink, 48 dp.
class _LoginLink extends StatelessWidget {
  const _LoginLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = appInk(context, AppAreaScope.of(context).ink);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(AppTouch.min, AppTouch.min),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        foregroundColor: ink,
      ),
      child: Text(label, style: AppType.bodyStrong(context).copyWith(color: ink)),
    );
  }
}
