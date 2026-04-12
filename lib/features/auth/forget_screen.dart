import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import 'auth_provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import '../../utils/helpers.dart';
import '../../utils/widget/primary_button.dart';
import '../../utils/widget/text_field.dart';
import 'register_screen.dart';

class ForgetScreen extends StatefulWidget {
  const ForgetScreen({super.key});

  @override
  State<ForgetScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<ForgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _emailController.text = 'ahmed@gmail.com';
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.forgotPassword(
      _emailController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      Helpers.showMessage(
        context,
        authProvider.errorMessage ?? 'Login failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: pageDirection,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          shadowColor: AppTheme.background,
          title: Text(
            'forget'.tr,
            style: const TextStyle(
                fontFamily: 'bahji', fontWeight: FontWeight.w100, fontSize: 17),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo/Title
                        SizedBox(
                          width: context.width / 4,
                        ),
                        Image.asset(
                          'assets/images/logo.png',
                          width: 150,
                          height: 130,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'forget_welcome'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  fontFamily: 'bahji',
                                  height: 1.6),
                        ),
                        const SizedBox(height: 35),

                        // Username field
                        MyTextField(
                          controller: _emailController,
                          label: 'email'.tr,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // Login button
                    MyPrimaryButton(
                        isLoading: context.read<AuthProvider>().isLoadingLogin,
                        label: 'login'.tr,
                        onPressed: _login),
                    const SizedBox(height: 16),
                    // Register link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "doesn't_have_account".tr,
                          style: TextStyle(fontFamily: 'bahji'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'register'.tr,
                              style: const TextStyle(
                                  color: Color.fromRGBO(21, 140, 234, 1),
                                  fontFamily: 'bahji'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
