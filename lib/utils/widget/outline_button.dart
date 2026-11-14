// lib/utils/widget/outline_button.dart
//
// The older outlined action in a Row (it expands): the kit's secondary geometry (48 high, radius 14, the label at
// 15 · 600, icon 20) in the caller's [color]. New screens use AppButton.secondary / AppButton.danger(dangerOutline:).
library;

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
        icon: Icon(icon, color: color, size: AppIconSize.md),
        label: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.row(context).copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        onPressed: onPressed,
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.all(color.withValues(alpha: 0.12)),
          side: WidgetStateProperty.resolveWith((s) => BorderSide(
              color: color, width: s.contains(WidgetState.focused) ? AppBorder.focus : AppBorder.hairline)),
          minimumSize: WidgetStateProperty.all(const Size(AppTouch.min, AppTouch.min)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.md)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: AppRadius.controlAll)),
        ),
      ),
    );
  }
}
