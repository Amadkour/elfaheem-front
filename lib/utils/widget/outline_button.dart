import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    this.onPressed,
    required this.label,
    required this.color,
    required this.icon,
  });

  final void Function()? onPressed;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        onPressed: onPressed,
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.all(color.withValues(alpha: 0.12)),
          side: WidgetStateProperty.all(BorderSide(color: color, width: AppBorder.hairline)),
          minimumSize: WidgetStateProperty.all(const Size(AppTouch.min, AppTouch.min)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card))),
        ),
      ),
    );
  }
}
