import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../category/categories_provider.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'auth_widgets.dart';
import 'login_screen.dart';

class AdditionalRegisterScreen extends StatefulWidget {
  const AdditionalRegisterScreen({super.key, required this.email});

  final String email;

  @override
  State<AdditionalRegisterScreen> createState() =>
      _AdditionalRegisterScreenState();
}

class _AdditionalRegisterScreenState extends State<AdditionalRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _yearController = TextEditingController();
  final _payController = ExpansibleController();
  final _specializationController = ExpansibleController();
  final _teachingController = ExpansibleController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().loadSpecialization(context);
    });
  }

  @override
  void dispose() {
    _yearController.dispose();
    _payController.dispose();
    _specializationController.dispose();
    _teachingController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.completeTeacherProfile(
      experienceYears: int.parse(_yearController.text),
      email: widget.email,
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
        authProvider.errorMessage ?? 'Registration failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Consumer<AuthProvider>(builder: (context, provider, child) {
      final isLoadingCategories =
          context.read<CategoriesProvider>().isLoadingCategory;

      if (isLoadingCategories) {
        return const Scaffold(
          backgroundColor: Color(0xFFF8F9FB),
          body: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF1A56C4),
            ),
          ),
        );
      }

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
          ProgressBar(currentStep: 2, totalSteps: 3),
          const SizedBox(height: 28),

          ScreenIcon(icon: Icons.badge_outlined),
          const SizedBox(height: 16),

          Text(
            'complete_profile'.tr,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16181D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'additional_registration_welcome'.tr,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          // Experience years
          IconTextField(
            controller: _yearController,
            label: 'experience'.tr,
            icon: Icons.schedule_rounded,
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 20),

          // Specialization
          SectionLabel(label: 'Specialization'.tr),
          const SizedBox(height: 8),
          context.read<CategoriesProvider>().isLoadingCategory
              ? const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF1A56C4),
            ),
          )
              : StyledDropdown(
            icon: Icons.science_outlined,
            label: 'Specialization'.tr,
            controller: _specializationController,
            initValue: provider.selectedSpecialization,
            options: provider.specializations,
            onChange: (i) => provider.onChangeSpecialization(
                i, _specializationController),
          ),
          const SizedBox(height: 20),

          // Payment method
          SectionLabel(label: 'payment_method'.tr),
          const SizedBox(height: 8),
          StyledDropdown(
            icon: Icons.credit_card_outlined,
            label: 'payment_method'.tr,
            controller: _payController,
            initValue: provider.selectedPaymentType,
            options: provider.paymentTypes,
            onChange: (i) =>
                provider.onChangePaymentMethod(i, _payController),
          ),
          const SizedBox(height: 20),

          // Teaching style
          SectionLabel(label: 'teaching_style'.tr),
          const SizedBox(height: 8),
          StyledDropdown(
            icon: Icons.cast_for_education_outlined,
            label: 'teaching_style'.tr,
            controller: _teachingController,
            initValue: provider.selectedTeachingType,
            options: provider.teachingTypes,
            onChange: (i) =>
                provider.onChangeTeachingType(i, _teachingController),
          ),
          const SizedBox(height: 32),

          PrimaryButton(
            isLoading: false,
            label: 'confirm'.tr,
            icon: Icons.check_circle_outline_rounded,
            onPressed: _register,
          ),
        ],
      ),
    );
  }
}