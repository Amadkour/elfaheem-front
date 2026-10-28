// components/currency_selector.dart
//
// Premium horizontal currency picker — SAR / EGP / USD, each translated via
// `.tr` (ar/en depending on AppConfig.lang) with the active one highlighted
// with a gradient fill + shadow. Built with a Wrap so it degrades cleanly
// from a wide web card down to a narrow phone width without overflowing.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../student/models.dart' show AppCurrency, AppCurrencyX;

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
          Text(
            label!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'bahji',
              color: context.colors.heroShade.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            // On very wide (web) layouts, let each chip breathe more;
            // on narrow phone widths, chips wrap onto a second row cleanly.
            final isWide = constraints.maxWidth > 420;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 20 : 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          gradient: isSelected ? context.colors.primaryGradient : null,
          color: isSelected ? null : context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : context.colors.divider,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? context.colors.primaryShadow
              : [
            BoxShadow(
              color: context.colors.heroShade.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? context.colors.cardBg
                    : context.colors.textLight.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              currency.label,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? context.colors.onHero : context.colors.textDark,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              currency.symbol,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? context.colors.onHero.withValues(alpha: 0.85)
                    : context.colors.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}