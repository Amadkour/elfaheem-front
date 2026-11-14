// lib/utils/widget/text_field.dart
//
// The older text field. It wears the kit's well (appFieldDecoration, lib/design/app_inputs.dart): warm fill, radius
// 14, a hairline at rest, the 2 px ring on focus, the error under the well. Its one [label] is the placeholder: the
// screens that use it draw their own label above (`_Labeled`, a section label), so the field adds none. New screens
// use AppField (label above, hint inside).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../config/theme/theme_config_provider.dart';

/// The outline of the older text fields, in the kit's look (a calm hairline, the 2 px focus ring).
OutlineInputBorder myFieldBorder(BuildContext context, {bool focused = false, bool error = false}) {
  final c = context.colors;
  return OutlineInputBorder(
    borderRadius: AppRadius.controlAll,
    borderSide: BorderSide(
      color: error ? c.danger : (focused ? c.primary : c.divider),
      width: focused ? AppBorder.focus : AppBorder.hairline,
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
        enabled: enable,
        style: appFieldTextStyle(context),
        decoration: appFieldDecoration(context, hint: label, enabled: enable ?? true).copyWith(
          hintTextDirection: pageDirection,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}
