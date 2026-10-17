import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import '../../utils/widget/primary_button.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';

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
        title: 'forget'.tr,
        builder: (context, isWide) => _buildForm());
  }

  Widget _buildForm() {
    final heightUnit = context.height / 100;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top bar: back + logo + switches ──────────────────────────────
          const AuthTopBar(showBack: false,),
          SizedBox(height: heightUnit*2),

          // ── Title block ──────────────────────────────────────────────────
          AuthHeader(
            title: 'forget'.tr,
            subtitle: 'forget_welcome'.tr,
          ),
          SizedBox(height: heightUnit * 3.5),

          // ── Email / phone ────────────────────────────────────────────────
          Builder(
            builder: (context) {
              final a = context.watch<MyAuthProvider>();
              final phoneOk = a.loginAllowsPhone || a.verifyByPhone;
              return IconTextField(
                controller: _emailController,
                label: phoneOk ? 'email_or_phone'.tr : 'email'.tr,
                icon: phoneOk ? Icons.person_outline : Icons.email_outlined,
                keyboard: phoneOk
                    ? TextInputType.text
                    : TextInputType.emailAddress,
              );
            },
          ),
          SizedBox(height: heightUnit * 1.5),

          // ── Hint ─────────────────────────────────────────────────────────
          AuthInfoBanner(text: 'reset_link_hint'.tr),
          SizedBox(height: heightUnit * 4),

          // ── Send button ──────────────────────────────────────────────────
          PrimaryButton(
            isLoading: context.watch<MyAuthProvider>().isLoadingForget,
            label: 'send_reset_link'.tr,
            icon: Icons.send_rounded,
            onPressed: _submit,
          ),
          SizedBox(height: heightUnit * 2.5),

          // ── Register link ────────────────────────────────────────────────
          LinkRow(
            message: "doesn't_have_account".tr,
            linkText: 'register'.tr,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
          ),
        ],
      ),
    );
  }
}
