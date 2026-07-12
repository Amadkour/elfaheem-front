import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

class MyPrimaryButton extends StatelessWidget {
  const MyPrimaryButton(
      {super.key,
      required this.isLoading,
      required this.label,
      this.child,
       this.onPressed});

  final bool isLoading;
  final String label;
  final Widget? child;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.accent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
