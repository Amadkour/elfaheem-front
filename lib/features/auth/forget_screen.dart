import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/app_theme.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'register_screen.dart';
import 'auth_widgets.dart';

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
    _emailController.text = 'ahmed@gmail.com';
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.forgotPassword(
      _emailController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) =>
            OtpVerificationScreen(email: _emailController.text.trim(),
              flow: OtpFlowEnum.forget,
              role: 'student',)),
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
    final isWide = MediaQuery
        .of(context)
        .size
        .width > 800;

    return BasePage(
      appBar: isWide ?null:ScreenAppBar(title: 'forget_password'.tr),
      child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        AuthSidebar(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildForm(true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Center(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: _buildForm(false),
        ),
      ),
    );
  }

  Widget _buildForm(bool isWeb) {
    Widget form=Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          if(isWeb)
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
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 50),


          Text(
            'forget'.tr,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: context.colors.textDark,),
          ),
          const SizedBox(height: 6),
          Text(
            'forget_welcome'.tr,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              color: context.colors.secondText,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 50),

          IconTextField(
            controller: _emailController,
            label: 'email'.tr,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          // Hint
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13,
                color: context.colors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                'reset_link_hint'.tr,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: context.colors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 100),

          PrimaryButton(
            isLoading: context
                .watch<AuthProvider>()
                .isLoadingForget,
            label: 'send_reset_link'.tr,
            icon: Icons.send_rounded,
            onPressed: _submit,
          ),
          const SizedBox(height: 24),

          LinkRow(
            message: "doesn't_have_account".tr,
            linkText: 'register'.tr,
            onTap: () =>
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
          ),
        ],
      ),);
    if (isWeb) {
      return Container(
      width: context.width > 800 ? 500 : context.width,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.colors.radiusXL),
        color: context.colors.cardBg,
      ),
      child: form
    );
    }

    return form;
  }
}