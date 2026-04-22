import 'package:flutter/material.dart';
import '../../../../../config/app_theme.dart';

class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? iconBg;

  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.iconBg,
  });

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? AppTheme.primary;
    final bg = iconBg ?? fg.withValues(alpha:0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha:0.12)),
        boxShadow: [
          BoxShadow(
            color: fg.withValues(alpha:0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Compact inline chip for lists/cards
class MiniStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const MiniStatChip({
    super.key,
    required this.icon,
    required this.label,
    this.color = AppTheme.textLight,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 11, color: color),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppTheme.caption.copyWith(fontSize: 11)),
    ],
  );
}