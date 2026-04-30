import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  const GradientButton(
      {super.key, required this.label, required this.isLoading, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isLoading ? null : onTap,
    child: Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: AppTheme.primaryShadow,
      ),
      child: Center(
        child: isLoading
            ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white))
            : Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                fontFamily: 'Cairo')),
      ),
    ),
  );
}