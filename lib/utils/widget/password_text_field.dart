import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
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
    return Material(
      shadowColor: Color.fromRGBO(0, 0, 0, 0.25),
      color: AppTheme.textFieldBackground,
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: TextFormField(
        textDirection: TextDirection.rtl,
        controller: controller,
        textInputAction: TextInputAction.next,
        obscureText: obscurePassword,
        style: const TextStyle(
            fontFamily: 'bahji',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: AppTheme.textDark),
        decoration: InputDecoration(
          hintTextDirection: TextDirection.rtl,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          fillColor: AppTheme.textFieldBackground,
          hint: Text(
            label,
            style: const TextStyle(
                fontFamily: 'bahji',
                fontWeight: FontWeight.w600,
                color: AppTheme.textMedium),
            textDirection: TextDirection.rtl,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              obscurePassword ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: onPressed,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        validator: Validators.validatePassword,
      ),
    );
  }
}
