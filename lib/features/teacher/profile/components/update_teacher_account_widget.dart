import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../../utils/widget/text_field.dart';
import '../../../student/profile/profile_provider.dart';

class TeacherEditAccountScreen extends StatefulWidget {
  const TeacherEditAccountScreen({super.key});

  @override
  State<TeacherEditAccountScreen> createState() =>
      _TeacherEditAccountScreenState();
}

class _TeacherEditAccountScreenState extends State<TeacherEditAccountScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _dobCtrl;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileProvider>();
    _nameCtrl = TextEditingController(text: p.name);
    _emailCtrl = TextEditingController(text: p.email);
    _dobCtrl = TextEditingController(text: p.dob);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<ProfileProvider>().updateProfile(
      name: _nameCtrl.text.trim(),
      phone: context.read<ProfileProvider>().phone,
      dob: _dobCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تم حفظ التغييرات',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'update_account'.tr),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    children: [
                      // Phone display
                      Text(provider.phone, style: AppTheme.caption),
                      const SizedBox(height: 24),
                      MyTextField(controller: _nameCtrl, label: 'الاسم'),
                      const SizedBox(height: 16),
                      MyTextField(
                          controller: _emailCtrl,
                          label: 'الإيميل',
                          enable: false),
                      const SizedBox(height: 16),
                      MyTextField(
                        controller: _dobCtrl,
                        label: 'تاريخ الميلاد',),
                      const SizedBox(height: 32),
                      MyPrimaryButton(
                        label: 'حفظ التغييرات',
                        isLoading: provider.isLoading,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
