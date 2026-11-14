// lib/utils/widget/password_text_field.dart
//
// The older password field (change password): the kit's well with a show / hide button in a 48 px target. The
// screens that use it draw their own label above, so its [label] is the placeholder. New screens use
// AppPasswordField.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../config/theme/theme_config_provider.dart';
import '../validators.dart';

class MyPasswordTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscurePassword;
  final VoidCallback? onPressed;

  const MyPasswordTextField(
      {super.key,
      required this.controller,
      required this.label,
      required this.obscurePassword,
      this.onPressed});

  @override
  Widget build(
    BuildContext context,
  ) {
    final c = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: TextFormField(
        textDirection: pageDirection,
        controller: controller,
        textInputAction: TextInputAction.next,
        obscureText: obscurePassword,
        autocorrect: false,
        enableSuggestions: false,
        style: appFieldTextStyle(context),
        decoration: appFieldDecoration(
          context,
          hint: label,
          icon: Icons.lock_outline_rounded,
          suffix: IconButton(
            tooltip: AppConfig.lang == 'ar' ? 'إظهار أو إخفاء كلمة المرور' : 'Show or hide the password',
            icon: Icon(
              obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: AppIconSize.md,
              color: c.textLight,
            ),
            onPressed: onPressed,
          ),
        ).copyWith(hintTextDirection: pageDirection, floatingLabelBehavior: FloatingLabelBehavior.never),
        validator: Validators.validatePassword,
      ),
    );
  }
}
