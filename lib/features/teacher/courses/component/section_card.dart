import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';

class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  const SectionCard({
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
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: AppTheme.cardShadow,
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
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: AppTheme.h3.copyWith(fontSize: 15)),
                ),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text('إضافة',
                            style: AppTheme.caption.copyWith(
                                color: AppTheme.primary,
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
                  style: AppTheme.caption.copyWith(color: AppTheme.textLight)),
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
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
    trailing: GestureDetector(
      onTap: onRemove,
      child:
      const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
    ),
  );
}