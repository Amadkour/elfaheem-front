import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/utils/widget/date_picker_widget.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/app_theme.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'auth_widgets.dart';

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
  bool _obscureConfirm = true;

  DateTime selectedDate =
  DateTime.now().subtract(const Duration(days: 360 * 20));

  @override
  void initState() {
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
          ),
        ),
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
    final isWide = MediaQuery.of(context).size.width > 800;

    return Consumer<AuthProvider>(builder: (context, provider, child) {
      return Directionality(
        textDirection: pageDirection,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FB),
          body: isWide
              ? _buildWideLayout(provider)
              : _buildNarrowLayout(provider),
        ),
      );
    });
  }

  Widget _buildWideLayout(AuthProvider provider) {
    return Row(
      children: [
        AuthSidebar(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildForm(provider),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(AuthProvider provider) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: _buildForm(provider),
      ),
    );
  }

  Widget _buildForm(AuthProvider provider) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          ProgressBar(currentStep: 0, totalSteps: 3),
          const SizedBox(height: 28),

          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back_ios_rounded, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 4),
                Text(
                  'create_account'.tr,
                  style: const TextStyle(
                    fontFamily:  'Tajawal',
                    fontSize: 16,
                    color: Color(0xFF16181D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SizedBox(height: 16),
          Text(
            'create_account'.tr,
            style: const TextStyle(
              fontFamily:  'Tajawal',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16181D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'registration_welcome'.tr,
            style:  TextStyle(
              fontFamily:  'Tajawal',
              fontSize: 14,
              color: AppTheme.scondeText,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          // Full name
          IconTextField(
            controller: _fullNameController,
            label: 'full_name'.tr,
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 20),

          // Email
          IconTextField(
            controller: _emailController,
            label: 'email'.tr,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),

          // Phone
          IconTextField(
            controller: _phoneController,
            label: 'phone'.tr,
            icon: Icons.phone_outlined,
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 20),

          // Password
          IconPasswordField(
            controller: _passwordController,
            label: 'password'.tr,
            obscure: _obscurePassword,
            onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
          const SizedBox(height: 20),

          // Confirm password
          IconPasswordField(
            controller: _confirmedPasswordController,
            label: 'confirmed_password'.tr,
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          const SizedBox(height: 20),

          // Date of birth
          SectionLabel(label: 'dob'.tr),
          const SizedBox(height: 8),
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
            label: 'dob'.tr,
          ),
          const SizedBox(height: 20),

          // Role picker
          SectionLabel(label: 'role'.tr),
          const SizedBox(height: 10),
          RolePicker(provider: provider, rolController: _rolController),
          const SizedBox(height: 28),

          PrimaryButton(
            isLoading: provider.isLoadingRegistration,
            label: 'confirm'.tr,
            icon: Icons.check_rounded,
            onPressed: _register,
          ),
          const SizedBox(height: 20),

          LinkRow(
            message: 'have_account'.tr,
            linkText: 'login'.tr,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}