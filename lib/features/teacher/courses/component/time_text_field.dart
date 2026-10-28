import 'package:flutter/material.dart';
import '../../../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class TimeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const TimeField({super.key, required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textAlign: TextAlign.center,
    keyboardType: TextInputType.datetime,
    style: TextStyle(fontFamily: AppFonts.display, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: context.colors.caption,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
  );
}
