import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/primary_button.dart';
import '../../../utils/widget/text_field.dart';
import 'profile_provider.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  late TextEditingController _nameCtrl=TextEditingController();
  late TextEditingController _emailCtrl=TextEditingController();
  late TextEditingController _dobCtrl=TextEditingController();
  late TextEditingController _phoneCtrl=TextEditingController();
  late TextEditingController _bioCtrl=TextEditingController();
  late ProfileProvider p;
  @override
  void initState() {
    super.initState();
     p = context.read<ProfileProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameCtrl.text=p.name;
      _emailCtrl.text= p.email;
      _dobCtrl.text= p.dob;
      _phoneCtrl.text= p.phone;
      _bioCtrl.text= p.bio;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }
  bool get isChanged=>
  p.name!=_nameCtrl.text ||
      p.dob!=_dobCtrl.text ||
      p.email!=_emailCtrl.text ||
      p.phone!=_phoneCtrl.text ||
      p.imageByte!=null;
  Future<void> _save() async {
    try {
      await context.read<ProfileProvider>().updateProfile(
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            dob: _dobCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('تم حفظ التغييرات',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: context.colors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString(),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    return BasePage(
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'update_account'.tr),
            provider.isLoading?
                Center(child: CircularProgressIndicator(),):
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  children: [
                    EditableImage(
                      onChange: provider.changeImage,
                      imageFile: provider.imageFile,
                      imageByte: provider.imageByte,
                      imageUrl: provider.imageUrl,
                      size: context.height/6,
                      isCircle: true,
                    ),
                    MyTextField(controller: _nameCtrl, label: 'الاسم'),
                    const SizedBox(height: 16),
                    MyTextField(
                        controller: _emailCtrl,
                        label: 'الإيميل',
                        enable: false),
                    const SizedBox(height: 16),
                    MyTextField(
                        controller: _phoneCtrl,
                        label: 'رقم الهاتف',
                        keyboard: TextInputType.phone),
                    const SizedBox(height: 16),
                    MyTextField(controller: _dobCtrl, label: 'تاريخ الميلاد'),
                    const SizedBox(height: 16),
                    MyTextField(
                        controller: _bioCtrl, label: 'نبذة عنك', maxLine: 3),
                    const SizedBox(height: 32),
                    if(isChanged)
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
    );
  }
}
