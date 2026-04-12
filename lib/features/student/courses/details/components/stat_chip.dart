import 'package:flutter/cupertino.dart';

import '../../../../../config/app_theme.dart';

class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: iconColor ?? AppTheme.primary),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.caption.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
