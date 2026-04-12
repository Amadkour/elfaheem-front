import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/primary_menue.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../category/categories_provider.dart';
import 'auth_provider.dart';
import '../../utils/helpers.dart';
import 'login_screen.dart';
class AdditionalRegisterScreen extends StatefulWidget {
  const AdditionalRegisterScreen({super.key, required this.email});

  final String email;

  @override
  State<AdditionalRegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<AdditionalRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _yearController = TextEditingController();
  final _payController = ExpansibleController();
  final _specializationController = ExpansibleController();
  final _teachingController = ExpansibleController();

  DateTime selectedDate =
  DateTime.now().subtract(const Duration(days: 360 * 20));

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().loadSpecialization(context);
    });
    super.initState();
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
    return Consumer<AuthProvider>(builder: (context, provider, child) {
      if (context
          .read<CategoriesProvider>()
          .isLoadingCategory) {
        return const Center(child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white)),);
      }
      return Directionality(
        textDirection: pageDirection,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            centerTitle: false,
            shadowColor: AppTheme.background,
            title: Text(
              'complete_profile'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji',
                  fontWeight: FontWeight.w100,
                  fontSize: 17),
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
                            'additional_registration_welcome'.tr,
                            style: const TextStyle(
                                fontFamily: 'Bahji',
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 30),
                          MyTextField(
                            controller: _yearController,
                            label: 'experience'.tr,
                            keyboard: TextInputType.number,
                          ),
                          const SizedBox(height: 30),

                          //specialization
                          context
                              .read<CategoriesProvider>()
                              .isLoadingCategory ?
                          CircularProgressIndicator() :
                          MyPrimaryMenu(
                              label: 'Specialization'.tr,
                              controller: _specializationController,
                              initValue: provider.selectedSpecialization,
                              options: provider.specializations,
                              haveLogo: false,
                              onChange: (i) {
                                provider.onChangeSpecialization(
                                    i, _specializationController);
                              }),
                          const SizedBox(height: 30),

                          //payment method
                          MyPrimaryMenu(
                              label: 'payment_method'.tr,
                              controller: _payController,
                              initValue: provider.selectedPaymentType,
                              options: provider.paymentTypes,
                              haveLogo: false,
                              onChange: (i) {
                                provider.onChangePaymentMethod(
                                    i, _payController);
                              }),
                          const SizedBox(height: 30),

                          //teaching
                          MyPrimaryMenu(
                              label: 'teaching_style'.tr,
                              controller: _teachingController,
                              initValue: provider.selectedTeachingType,
                              options: provider.teachingTypes,
                              haveLogo: false,
                              onChange: (i) {
                                provider.onChangeTeachingType(
                                    i, _teachingController);
                              }),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),

                // Register Button
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: MyPrimaryButton(
                      isLoading: false,
                      label: 'confirm'.tr,
                      onPressed: _register),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
