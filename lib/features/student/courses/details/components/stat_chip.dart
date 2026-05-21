import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import '../../../../../config/app_theme.dart';

class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? iconBg;
  final double maxHeight;
  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.iconBg, required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? context.colors.primary;
    final bg = iconBg ?? fg.withValues(alpha:0.12);

    return Expanded(
      child: Container(
        height: maxHeight,
        width: maxHeight,
        margin: EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          //borderRadius: BorderRadius.circular(16),
            shape: BoxShape.circle,
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
            Spacer(flex: 2,),
            Container(
              width: maxHeight/3,
              height: maxHeight/3,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: fg),
            ),
            Spacer(),
            Text(
              label,
              style: context.colors.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.colors.textDark,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Spacer(flex: 2,),

          ],
        ),
      ),
    );
  }
}

/// Compact inline chip for lists/cards
class MiniStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const MiniStatChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: (color??context.colors.textLight).withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 11, color: color??context.colors.textLight),
      ),
      const SizedBox(width: 4),
      Text(label, style: context.colors.caption.copyWith(fontSize: 11)),
    ],
  );
}