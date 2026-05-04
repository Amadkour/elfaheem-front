import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/app_theme.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'login_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.phoneNumber, required this.email});

  final String? phoneNumber;
  final String email;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmedPasswordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _passwordController.text = 'Aa@@aA2291996';
    _confirmedPasswordController.text = 'Aa@@aA2291996';
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmedPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmedPasswordController.text) {
      Fluttertoast.showToast(msg: 'password_mismatch'.tr);
      return;
    }
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.changePassword(
      email: widget.email,
      newPassword: _passwordController.text,
      oldPassword: _passwordController.text, // adjust if backend expects old password
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    } else {
      Helpers.showMessage(
        context,
        authProvider.errorMessage ?? 'Change failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: Text('reset_password'.tr),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.colors.radiusXL),
                  ),
                  color: context.colors.cardBg,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'reset_password_welcome'.tr,
                            style: context.colors.h1,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'choose_new_password'.tr,
                            style: context.colors.body,
                          ),
                          const SizedBox(height: 32),
                          MyPasswordTextField(
                            controller: _passwordController,
                            label: 'new_password'.tr,
                            obscurePassword: _obscurePassword,
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          const SizedBox(height: 20),
                          MyPasswordTextField(
                            controller: _confirmedPasswordController,
                            label: 'confirm_new_password'.tr,
                            obscurePassword: _obscurePassword,
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          const SizedBox(height: 32),
                          MyPrimaryButton(
                            isLoading: context.watch<AuthProvider>().isLoadingRegistration,
                            label: 'confirm'.tr,
                            onPressed: _resetPassword,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}