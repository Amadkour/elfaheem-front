import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';

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
      color: context.themeConfig.inputBg(isDark:context.colors.isDark),
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
            fontFamily: 'tajawal',
            fontWeight: FontWeight.w500,
            fontSize: 15,
          color: context.themeConfig.textDark,
        ),
        decoration: InputDecoration(
          hintTextDirection: pageDirection,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          fillColor: context.themeConfig.inputBg(isDark:context.colors.isDark),

          alignLabelWithHint: true,
          hint: Text(
            label,
            style:  TextStyle(
                fontFamily: 'tajawal',
                fontWeight: FontWeight.w600,
              color: context.themeConfig.textDark,
            ),
            textDirection: TextDirection.rtl,
          ),
          border: const OutlineInputBorder(borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
