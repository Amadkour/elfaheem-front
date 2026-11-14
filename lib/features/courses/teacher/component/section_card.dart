// A list the teacher builds in the course form (appointments, certificates, tools, prerequisites): paper on a warm
// hairline, a quiet glyph and the name in the editorial section face, "Add" as a tonal button, the items as rows
// parted by hairlines with a 48 px remove button each.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBorder, AppButton, AppButtonSize, AppIconSize, AppRadius, AppSpace, AppTouch, AppType;

class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  /// Feature id used to hide this card (see ParentComponent).
  final String? featureKey;

  const SectionCard({super.key,
    this.featureKey,
    required this.icon,
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) =>
      ParentComponent(featureKey: featureKey, child: _buildCard(context));

  Widget _buildCard(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                AppButton.tonal(
                  label: 'sc_add'.tr,
                  icon: Icons.add_rounded,
                  size: AppButtonSize.sm,
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          // Items
          for (final e in items.asMap().entries) ...[
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            _ItemRow(label: e.value, onRemove: () => onRemove(e.key)),
          ],
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
              child: Text('sc_empty'.tr, style: AppType.meta(context)),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xxs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppType.row(context))),
        IconButton(
          tooltip: 'remove'.tr,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: onRemove,
          icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: context.colors.danger),
        ),
      ],
    ),
  );
}
