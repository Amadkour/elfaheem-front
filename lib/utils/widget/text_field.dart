import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// The outline of the older text fields, in the kit's look (a calm hairline, the brand on focus).
OutlineInputBorder myFieldBorder(BuildContext context, {bool focused = false, bool error = false}) {
  final c = context.colors;
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    borderSide: BorderSide(
      color: error ? c.danger : (focused ? c.primary : c.divider),
      width: focused ? AppBorder.strong : AppBorder.hairline,
    ),
  );
}

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
      type: MaterialType.transparency,
      child: TextFormField(
        textDirection: pageDirection,
        validator: validator,
        maxLines: maxLine,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        controller: controller,
        style:  TextStyle(
            fontFamily: AppFonts.family,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          color: context.colors.textDark,
        ),
        decoration: InputDecoration(
          hintTextDirection: pageDirection,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          filled: true,
          fillColor: context.colors.inputBg,
          alignLabelWithHint: true,
          hint: Text(
            label,
            style:  TextStyle(
                fontFamily: AppFonts.family,
                fontWeight: FontWeight.w600,
              color: context.colors.textDark,
            ),
            textDirection: pageDirection,
          ),
          border: myFieldBorder(context),
          enabledBorder: myFieldBorder(context),
          focusedBorder: myFieldBorder(context, focused: true),
          errorBorder: myFieldBorder(context, error: true),
          focusedErrorBorder: myFieldBorder(context, focused: true, error: true),
        ),
      ),
    );
  }
}
