import 'package:flutter/material.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';

class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  const SectionCard({super.key, 
    required this.icon,
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeConfig.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow: context.themeConfig.cardShadow(isDark:context.colors.isDark),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.themeConfig.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: context.themeConfig.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: context.colors.h3.copyWith(fontSize: 15)),
                ),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.themeConfig.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         Icon(Icons.add,
                            size: 14, color: context.themeConfig.primary),
                        const SizedBox(width: 4),
                        Text('إضافة',
                            style: context.colors.caption.copyWith(
                                color: context.themeConfig.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (items.isNotEmpty) const Divider(height: 1),
          // Items
          ...items.asMap().entries.map((e) => _ItemRow(
            label: e.value,
            onRemove: () => onRemove(e.key),
          )),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text('لم يتم الإضافة بعد',
                  style: context.colors.caption.copyWith(color: context.themeConfig.textLight)),
            ),
        ],
      ),
    );
  }
}
class _ItemRow extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ItemRow({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    title: Text(label,
        style: const TextStyle(fontFamily: 'bahji', fontSize: 13)),
    trailing: GestureDetector(
      onTap: onRemove,
      child:
       Icon(Icons.close_rounded, size: 18, color: context.themeConfig.danger),
    ),
  );
}