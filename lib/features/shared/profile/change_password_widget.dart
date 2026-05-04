import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/primary_button.dart';
import 'profile_provider.dart';

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConf = true;

  @override
  void initState() {
    super.initState();
    _oldCtrl.addListener(_onFieldChanged);
    _newCtrl.addListener(_onFieldChanged);
    _confCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  /// Button is enabled only when:
  /// - All fields are non-empty
  /// - New password != old password
  /// - New password == confirm password
  bool get _canSubmit {
    final old = _oldCtrl.text.trim();
    final nw = _newCtrl.text.trim();
    final conf = _confCtrl.text.trim();
    return old.isNotEmpty &&
        nw.isNotEmpty &&
        conf.isNotEmpty &&
        nw != old &&
        nw == conf;
  }

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final old = _oldCtrl.text.trim();
    final nw = _newCtrl.text.trim();
    final conf = _confCtrl.text.trim();

    if (old.isEmpty || nw.isEmpty || conf.isEmpty) {
      _showSnack('fill_all_fields'.tr, Colors.orange);
      return;
    }
    if (nw.length < 6) {
      _showSnack('password_min_length'.tr, Colors.orange);
      return;
    }
    if (nw == old) {
      _showSnack('password_same_as_old'.tr, Colors.orange);
      return;
    }
    if (nw != conf) {
      _showSnack('new_password_mismatch'.tr, Colors.orange);
      return;
    }

    try {
      String? result = await context.read<ProfileProvider>().changePassword(
        oldPassword: old,
        newPassword: nw,
      );
      if (mounted && result != null) {
        _showSnack('change_password_success'.tr, context.colors.success);
        Navigator.of(context).pop();
      } else {
        if (mounted) _showSnack('change_password_error'.tr, Colors.red);
      }
    } catch (e) {
      if (mounted) _showSnack('change_password_error'.tr, Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'change_password'.tr),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    children: [
                      // Old password
                      MyPasswordTextField(
                        controller: _oldCtrl,
                        label: 'current_password'.tr,
                        obscurePassword: _obscureOld,
                        onPressed: () =>
                            setState(() => _obscureOld = !_obscureOld),
                      ),
                      const SizedBox(height: 16),

                      // New password
                      MyPasswordTextField(
                        controller: _newCtrl,
                        label: 'new_password'.tr,
                        obscurePassword: _obscureNew,
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                      const SizedBox(height: 16),

                      // Confirm new password
                      MyPasswordTextField(
                        controller: _confCtrl,
                        label: 'confirm_new_password'.tr,
                        obscurePassword: _obscureConf,
                        onPressed: () =>
                            setState(() => _obscureConf = !_obscureConf),
                      ),
                      const SizedBox(height: 32),

                      MyPrimaryButton(
                        label: 'change_password'.tr,
                        isLoading: provider.isLoading,
                        onPressed: _canSubmit ? _submit : null,
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