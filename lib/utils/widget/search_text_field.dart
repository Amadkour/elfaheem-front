import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';

class MySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final void Function(String)? onChanged;

  const MySearchBar(
      {super.key, required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: controller,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: 'tajawal',
          fontSize: 14,
          color: context.themeConfig.textDark,
        ),
        decoration: InputDecoration(
          hintText: hint.tr,
          hintStyle: TextStyle(
            fontFamily: 'tajawal',
            color: context.themeConfig.textMedium,
            fontSize: 13,
          ),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: context.themeConfig.textMedium),
          filled: true,
          fillColor: context.themeConfig.surfaceCard,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.themeConfig.divider, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.themeConfig.divider, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.themeConfig.primary, width: 1),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}