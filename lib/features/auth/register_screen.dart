import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:flutter_education_app/utils/widget/date_picker_widget.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:flutter_education_app/utils/widget/primary_menue.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../utils/widget/primary_button.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmedPasswordController = TextEditingController();
  final _dobController = TextEditingController();
  final _rolController = ExpansibleController();
  bool _obscurePassword = true;
  DateTime selectedDate =
      DateTime.now().subtract(const Duration(days: 360 * 20));

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _emailController.text = 'Ahmed.Madkour@it-ranks.com';
    _fullNameController.text = 'Ahmed Madkour';
    _phoneController.text = '01110672232';
    _passwordController.text = 'Aa@@aA2291996';
    _confirmedPasswordController.text = 'Aa@@aA2291996';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _confirmedPasswordController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmedPasswordController.text) {
      Fluttertoast.showToast(msg: 'password must be identical');
      return;
    }
    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.register(
      gmail: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      dob: _dobController.text.trim(),
      password: _passwordController.text,
      name: _fullNameController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
                  phoneNumber: _phoneController.text.trim(),
                  email: _emailController.text.trim(),
                  role: authProvider.selectedRole!['text'],
                )),
        (route) => false,
      );
    } else {
      Helpers.showMessage(
        context,
        authProvider.errorMessage ?? 'Registration failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(builder: (context, provider, child) {
      return Directionality(
        textDirection: pageDirection,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            centerTitle: false,
            shadowColor: AppTheme.background,
            title: Text(
              'create_account'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji',
                  fontWeight: FontWeight.w100,
                  fontSize: 17),
            ),
          ),
          body: SafeArea(
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
                      'registration_welcome'.tr,
                      style: const TextStyle(
                          fontFamily: 'Bahji',
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    MyTextField(
                      controller: _fullNameController,
                      label: 'full_name'.tr,
                    ),
                    const SizedBox(height: 30),

                    // Email
                    MyTextField(
                      controller: _emailController,
                      keyboard: TextInputType.emailAddress,
                      label: 'email'.tr,
                    ),

                    const SizedBox(height: 30),

                    // phone
                    MyTextField(
                      controller: _phoneController,
                      label: 'phone'.tr,
                      keyboard: TextInputType.phone,
                    ),
                    const SizedBox(height: 30),

                    // Password
                    MyPasswordTextField(
                      controller: _passwordController,
                      label: 'password'.tr,
                      obscurePassword: _obscurePassword,
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    const SizedBox(height: 30),

                    MyPasswordTextField(
                      controller: _confirmedPasswordController,
                      label: 'confirmed_password'.tr,
                      obscurePassword: _obscurePassword,
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    const SizedBox(height: 30),
                    MyDatePicker(
                        onChange: (picked) {
                          setState(() {
                            selectedDate = picked;
                            _dobController.text =
                                "${selectedDate.toLocal()}".split(' ')[0];
                          });
                        },
                        selectedDate: selectedDate,
                        controller: _dobController,
                        label: 'dob'.tr),
                    const SizedBox(height: 30),
                    //role
                    MyPrimaryMenu(
                        label: 'role'.tr,
                        controller: _rolController,
                        initValue: provider.selectedRole,
                        options: provider.roles,
                        haveLogo: false,
                        onChange: (i) {
                          provider.onChangeRole(i, _rolController);
                        }),
                    const SizedBox(height: 30),

                    // Register Button
                    MyPrimaryButton(
                        isLoading: provider.isLoadingRegistration,
                        label: 'confirm'.tr,
                        onPressed: _register),

                    const SizedBox(height: 16),

                    // Login Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('have_account'.tr),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('login'.tr),
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
    });
  }
}
