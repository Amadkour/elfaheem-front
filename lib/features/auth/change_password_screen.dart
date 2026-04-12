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
  const ChangePasswordScreen(
      {super.key, this.phoneNumber, required this.email});

  final String? phoneNumber;
  final String email;

  @override
  State<ChangePasswordScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmedPasswordController = TextEditingController();

  bool _obscurePassword = true;
  DateTime selectedDate =
      DateTime.now().subtract(const Duration(days: 360 * 20));
@override
  void initState() {
    super.initState();
    _passwordController.text='Aa@@aA2291996';
    _confirmedPasswordController.text='Aa@@aA2291996';
  }
  @override
  void dispose() {
    _passwordController.dispose();
    _confirmedPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmedPasswordController.text) {
      Fluttertoast.showToast(msg: 'password must be identical');
      return;
    }
    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.changePassword(
      email: widget.email,
      newPassword: _passwordController.text,
      oldPassword: _passwordController.text,
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
    AuthProvider provider = context.read<AuthProvider>();
    return Directionality(
      textDirection: pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          centerTitle: false,
          shadowColor: AppTheme.background,
          title: Text(
            'reset_password'.tr,
            style: const TextStyle(
                fontFamily: 'bahji', fontWeight: FontWeight.w100, fontSize: 17),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header

                        const SizedBox(height: 16),
                        Text(
                          'reset_password_welcome'.tr,
                          style: const TextStyle(
                              fontFamily: 'Bahji',
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        // Password
                        MyPasswordTextField(
                          controller: _passwordController,
                          label: 'password'.tr,
                          obscurePassword: _obscurePassword,
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        const SizedBox(height: 30),

                        MyPasswordTextField(
                          controller: _confirmedPasswordController,
                          label: 'confirmed_password'.tr,
                          obscurePassword: _obscurePassword,
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Register Button
              MyPrimaryButton(
                  isLoading: provider.isLoadingRegistration,
                  label: 'confirm'.tr,
                  onPressed: _register),
            ],
          ),
        ),
      ),
    );
  }
}
