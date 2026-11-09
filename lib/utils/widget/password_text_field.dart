import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../config/theme/theme_config_provider.dart';
import '../validators.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
    return Material(
      type: MaterialType.transparency,
      child: TextFormField(
        textDirection: pageDirection,
        controller: controller,
        textInputAction: TextInputAction.next,
        obscureText: obscurePassword,
        style:  TextStyle(
            fontFamily: AppFonts.family,
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: context.colors.textDark),
        decoration: InputDecoration(
          hintTextDirection: pageDirection,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          filled: true,
          fillColor: context.colors.inputBg,
          hint: Text(
            label,
            style:  TextStyle(
                fontFamily: AppFonts.family,
                fontWeight: FontWeight.w600,
                color:  context.colors.textDark),
            textDirection: pageDirection,
          ),
          suffixIcon: IconButton(
            tooltip: AppConfig.lang == 'ar' ? 'إظهار أو إخفاء كلمة المرور' : 'Show or hide the password',
            icon: Icon(
              obscurePassword ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: onPressed,
          ),
          border: myFieldBorder(context),
          enabledBorder: myFieldBorder(context),
          focusedBorder: myFieldBorder(context, focused: true),
          errorBorder: myFieldBorder(context, error: true),
          focusedErrorBorder: myFieldBorder(context, focused: true, error: true),
        ),
        validator: Validators.validatePassword,
      ),
    );
  }
}
