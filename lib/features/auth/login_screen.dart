import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import '../teacher/dashboard/teacher_dashboard_screen.dart';
import 'auth_provider.dart';
import '../../utils/widget/primary_button.dart';
import '../../utils/widget/text_field.dart';
import 'forget_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // _emailController.text = 'hamdymadkour@ci.menofia.edu.eg';
    _emailController.text = 'Ahmed.Madkour@it-ranks.com';
    _passwordController.text = 'Aa@@aA2291996';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.login(
      gmail: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => authProvider.isTeacher
                ? const TeacherDashboardScreen()
                : const DashboardScreen()),
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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo/Title

                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 150,
                        height: 130,
                      ),
                      const Spacer(),
                      // Inside your build method:
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Image.asset(
                              'assets/images/lang.png',
                              width: 20,
                              height: 20,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                          DropdownMenu(
                            initialSelection: lang,
                            textStyle: const TextStyle(
                                fontSize: 14, fontFamily: 'bahji'),
                            width: context.width / 3,
                            trailingIcon: const Icon(
                              Icons.keyboard_arrow_down,
                              weight: 10,
                            ),
                            onSelected: (String? item) {
                              context.read<LangProvider>().changeLang(item);
                              setState(() {});
                            },
                            inputDecorationTheme:
                                const InputDecorationThemeData(
                                    border: InputBorder.none),
                            dropdownMenuEntries: context
                                .read<LangProvider>()
                                .languages
                                .map<DropdownMenuEntry<String>>((String item) {
                              return DropdownMenuEntry<String>(
                                value: item,
                                label: item.tr,
                                labelWidget: Text(
                                  item.tr,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'bahji'), // Custom text style
                                ),
                                leadingIcon: Image.asset(
                                  'assets/images/lang.png',
                                  width: 20,
                                  height: 20,
                                ), // Built-in icon support
                              );
                            }).toList(),
                          )
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'login_welcome'.tr,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                  const SizedBox(height: 16),

                  // Password field
                  MyPasswordTextField(
                    controller: _passwordController,
                    label: 'password'.tr,
                    obscurePassword: _obscurePassword,
                  ),
                  const SizedBox(height: 24),

                  // Login button
                  MyPrimaryButton(
                      isLoading: context.read<AuthProvider>().isLoadingLogin,
                      label: 'login'.tr,
                      onPressed: _login),
                  const SizedBox(height: 25),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgetScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'forget_password'.tr,
                          style: const TextStyle(
                              color: Color.fromRGBO(21, 140, 234, 1),
                              fontFamily: 'bahji'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "doesn't_have_account".tr,
                        style: const TextStyle(fontFamily: 'bahji'),
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
            ),
          ),
        ),
      ),
    );
  }
}
