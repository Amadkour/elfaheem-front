import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';
import 'username.dart';

class ForgetScreen extends StatefulWidget {
  const ForgetScreen({super.key});

  @override
  State<ForgetScreen> createState() => _ForgetScreenState();
}

class _ForgetScreenState extends State<ForgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MyAuthProvider>().loadPolicy();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<MyAuthProvider>();
    final success = await authProvider.forgotPassword(
      _emailController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: _emailController.text.trim(),
            flow: OtpFlowEnum.forget,
            role: 'student',
          ),
        ),
      );
    } else {
      Helpers.showMessage(
        authProvider.errorMessage ?? 'Request failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'auth_reset_title'.tr,
      subtitle: 'auth_reset_sub'.tr,
      builder: (context, isWide) => _buildForm(),
    );
  }

  Widget _buildForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Email / phone (+ @username when the admin allows it) ───────
            Builder(
              builder: (context) {
                final a = context.watch<MyAuthProvider>();
                final spec = identifierFieldSpec(
                  email: true,
                  phone: a.loginAllowsPhone || a.verifyByPhone,
                  username: a.loginAllowsUsername,
                );
                return IconTextField(
                  controller: _emailController,
                  label: spec.labelKey.tr,
                  icon: spec.icon.data,
                  keyboard: spec.keyboard,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                );
              },
            ),
            const SizedBox(height: 16),

            // ── Hint ───────────────────────────────────────────────────────
            AuthInfoBanner(text: 'reset_link_hint'.tr, icon: Icons.mark_email_unread_outlined),
            const SizedBox(height: 24),

            // ── Send ───────────────────────────────────────────────────────
            AuthButton(
              loading: context.watch<MyAuthProvider>().isLoadingForget,
              label: 'send_reset_link'.tr,
              icon: Icons.send_rounded,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),

            // ── Register link ──────────────────────────────────────────────
            LinkRow(
              message: 'auth_no_account'.tr,
              linkText: 'auth_create_account'.tr,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
            ),
          ],
        ),
      ),
    );
  }
}
