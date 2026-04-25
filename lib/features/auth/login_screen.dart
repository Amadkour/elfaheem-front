import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../utils/helpers.dart';
import '../teacher/dashboard/teacher_dashboard_screen.dart';
import 'auth_provider.dart';
import '../../utils/widget/primary_button.dart';
import '../../utils/widget/text_field.dart';
import 'auth_widgets.dart';
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
              : const DashboardScreen(),
        ),
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
    ApiClient().context=context;
    final isWide = MediaQuery.of(context).size.width > 800;

    return Consumer<LangProvider>(
      builder: (context,l,_) {
        return Directionality(
          textDirection: pageDirection,
          child: Scaffold(
            body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
          ),
        );
      }
    );
  }

  // ── Wide (web) layout: sidebar + form panel ──────────────────────────────
  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left sidebar
        AuthSidebar(),
        // Right form panel
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildFormCard(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Narrow (mobile) layout ────────────────────────────────────────────────
  Widget _buildNarrowLayout() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: _buildFormCard(),
      ),
    );
  }

  Widget _buildFormCard() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lang row
          LangRow(),
          const SizedBox(height: 28),

          // Screen icon + title
          AppNetworkImage(url: '',width: 100,height: 100,),
          const SizedBox(height: 16),
          Text(
            'login_welcome'.tr,
            style: const TextStyle(
              fontFamily: 'Bahji',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16181D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'sign_in_subtitle'.tr,
            style: const TextStyle(
              fontFamily: 'Bahji',
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Email
          IconTextField(
            controller: _emailController,
            label: 'email'.tr,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),

          // Password
          IconPasswordField(
            controller: _passwordController,
            label: 'password'.tr,
          ),
          const SizedBox(height: 8),

          // Forgot
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgetScreen()),
              ),
              child: Text(
                'forget_password'.tr,
                style: const TextStyle(
                  fontFamily: 'Bahji',
                  fontSize: 13,
                  color: Color(0xFF1A56C4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Login button
          PrimaryButton(
            isLoading: context.watch<AuthProvider>().isLoadingLogin,
            label: 'login'.tr,
            icon: Icons.arrow_forward_rounded,
            onPressed: _login,
          ),
          const SizedBox(height: 24),

          // Register link
          LinkRow(
            message: "doesn't_have_account".tr,
            linkText: 'register'.tr,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            ),
          ),
        ],
      ),
    );
  }
}