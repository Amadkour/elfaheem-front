import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/app_theme.dart';
import '../../core/api_client.dart';
import '../../utils/helpers.dart';
import '../teacher/dashboard/teacher_dashboard_screen.dart';
import 'auth_provider.dart';
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
        authProvider.errorMessage ?? 'Login failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Consumer<LangProvider>(builder: (context, l, _) {
      return BasePage(
        background: context.colors.isDark?null:context.colors.cardBg,
        child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
      );
    });
  }

  // ── Wide (web) layout: sidebar + form panel ──────────────────────────────
  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left sidebar
        AuthSidebar(),
        // Right form panel
        Expanded(
          child: Row(
            children: [
              Spacer(),
              Container(
                constraints: const BoxConstraints(maxWidth: 600),
                margin: EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(0.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(context.colors.radiusXL),
                  color:context.colors.isDark? context.colors.cardBg: context.colors.background,
                ),
                child: ClipRRect(
                  borderRadius:
                      BorderRadiusGeometry.circular(context.colors.radiusXL),
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _buildFormCard(),
                    ),
                  ),
                ),
              ),
              Spacer(),

            ],
          ),
        )
      ],
    );
  }

  // ── Narrow (mobile) layout ────────────────────────────────────────────────
  Widget _buildNarrowLayout() {
    return Center(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: _buildFormCard(),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    final provider = context.watch<ProfileProvider>();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lang row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppNetworkImage(
                url: '',
                width: 100,
                height: 100,
                heroTag: "logo-login",
                color: context.colors.background,
              ),
              LangDropdown(),

              // Screen icon + title
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'login'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: context.colors.textDark,
            ),
          ),
          Text(
            'login_welcome'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.colors.secondText,
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
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 13,
                  color: context.colors.primaryBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
           SizedBox(height: context.height/10),

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
          SizedBox(height: context.height/50),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  provider.changeMode(!provider.darkMode);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 72,
                  height: 38,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    gradient: provider.darkMode
                        ? const LinearGradient(
                            colors: [
                              Color(0xff0F172A),
                              Color(0xff1E293B),
                            ],
                          )
                        : const LinearGradient(
                            colors: [
                              Color(0xffFFE082),
                              Color(0xffFFB300),
                            ],
                          ),
                  ),
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        alignment: provider.darkMode
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return RotationTransition(
                              turns: animation,
                              child: child,
                            );
                          },
                          child: Container(
                            key: ValueKey(provider.darkMode),
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              provider.darkMode
                                  ? Icons.dark_mode_rounded
                                  : Icons.wb_sunny_rounded,
                              color: provider.darkMode
                                  ? Colors.indigo
                                  : Colors.orange,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
