// components/currency_selector.dart
//
// Premium horizontal currency picker — SAR / EGP / USD, each translated via
// `.tr` (ar/en depending on AppConfig.lang) with the active one highlighted
// solid in the primary (the selection colour). Built with a Wrap so it degrades cleanly
// from a wide web card down to a narrow phone width without overflowing.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../student/models.dart' show AppCurrency, AppCurrencyX;
import 'package:flutter_education_app/design/app_kit.dart' show AppBorder, AppFieldLabel, AppIconSize, AppMotion, AppRadius, AppSpace, AppTouch, AppType;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;

class CurrencySelector extends StatelessWidget {
  final AppCurrency selected;
  final ValueChanged<AppCurrency> onChanged;

  /// Optional label shown above the chip row (e.g. "currency_label".tr).
  final String? label;

  const CurrencySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.currency',
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          AppFieldLabel(label!),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            // On very wide (web) layouts, let each chip breathe more;
            // on narrow phone widths, chips wrap onto a second row cleanly.
            final isWide = constraints.maxWidth > 420;
            return Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: AppCurrency.values
                  .map((c) => _CurrencyChip(
                currency: c,
                isSelected: c == selected,
                isWide: isWide,
                onTap: () => onChanged(c),
              ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final AppCurrency currency;
  final bool isSelected;
  final bool isWide;
  final VoidCallback onTap;

  const _CurrencyChip({
    required this.currency,
    required this.isSelected,
    required this.isWide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = isSelected ? c.onHero : c.textDark;
    // the chosen one is solid emerald (the selection colour), the others quiet wells; no shadow, no gradient
    return Semantics(
      button: true,
      selected: isSelected,
      child: AnimatedContainer(
        duration: AppMotion.of(context).fast,
        curve: AppEase.out,
        decoration: BoxDecoration(
          color: isSelected ? c.primary : c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: isSelected ? c.primary : c.divider, width: AppBorder.hairline),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isWide ? AppSpace.lg : AppSpace.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected) ...[
                      Icon(Icons.check_rounded, size: AppIconSize.sm, color: ink),
                      const SizedBox(width: AppSpace.xs),
                    ],
                    Flexible(
                      child: Text(
                        currency.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      currency.symbol,
                      style: AppType.meta(context).copyWith(color: isSelected ? c.onHeroMuted : c.textMedium),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
