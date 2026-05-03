import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../config/app_theme.dart';

class MyTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int? maxLine;
  final TextInputType keyboard;
  final String? Function(String?)? validator;
  final bool? enable;
  const MyTextField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboard = TextInputType.text,
    this.validator, this.maxLine, this.enable,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.25),
      color: AppTheme.textFieldBackground,
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: TextFormField(
        textDirection: pageDirection,
        validator: validator,
        maxLines: maxLine,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        controller: controller,
        style:  TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: AppTheme.textDark),
        decoration: InputDecoration(
          hintTextDirection: pageDirection,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          fillColor: AppTheme.textFieldBackground,
          alignLabelWithHint: true,
          hint: Text(
            label,
            style: const TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w600,
                color: AppTheme.textMedium),
            textDirection: TextDirection.rtl,
          ),
          border: const OutlineInputBorder(borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
