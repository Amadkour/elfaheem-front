import 'package:flutter/material.dart';
import '../../../../config/theme/theme_config_provider.dart';

class TimeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const TimeField({super.key, required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textAlign: TextAlign.center,
    keyboardType: TextInputType.datetime,
    style: const TextStyle(fontFamily: 'bahji', fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: context.colors.caption,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
  );
}
