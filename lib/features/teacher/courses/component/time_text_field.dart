import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';

class TimeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const TimeField({super.key, required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textAlign: TextAlign.center,
    keyboardType: TextInputType.datetime,
    style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: context.colors.caption,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
  );
}
