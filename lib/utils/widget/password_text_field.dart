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
      color: context.colors.inputBg,
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: TextFormField(
        textDirection: TextDirection.rtl,
        controller: controller,
        textInputAction: TextInputAction.next,
        obscureText: obscurePassword,
        style:  TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: context.colors.textDark),
        decoration: InputDecoration(
          hintTextDirection: TextDirection.rtl,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          fillColor: context.colors.inputBg,
          hint: Text(
            label,
            style:  TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w600,
                color: context.colors.textMedium),
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
