// lib/features/admin/admin_premium_widgets.dart
//
// Shared "premium" building blocks for the admin pages:
//   • AdminPalette      – gradient pairs (light → dark) used for feature icons
//   • ServiceIcon       – gradient rounded-square icon with a soft glow
//   • PremiumHero       – gradient banner at the top of a page
//   • HeroPill          – small translucent chip shown inside the hero
//   • PremiumCard       – titled card (icon + title + hint) that holds children
//   • PremiumSelectTile – selectable row (multi-select or radio style)
//   • PremiumSwitchRow  – label + switch row
//   • PremiumSaveBar    – sticky bottom "Save" bar (use as BasePage.bottomNavigationBar)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

/// Gradient pairs (light → base) for the feature icons / hero banners.
///
/// They are NOT fixed colours: every role is read from YOUR theme
/// (`context.colors` = ThemeConfigProvider, the palette the admin edits in the
/// Theme page), so changing the theme recolours the whole admin area.
///
///   blue   → primary gradient        violet → purple gradient
///   green  → success gradient        rose   → danger gradient
///   teal   → accent2 gradient        orange → warning (softened)
///   indigo → primaryLight → primary  slate  → charcoal (softened)
///
/// Call [attach] once (the dashboard does). The provider is a long-lived
/// singleton whose getters always return the current palette, so the lists
/// below stay live when the theme changes.
class AdminPalette {
  AdminPalette._();

  static ThemeConfigProvider? _t;

  static void attach(BuildContext context) => _t = context.colors;

  /// base → soft light version of itself (friendlier than a flat colour).
  static List<Color> soft(Color base, [double amount = 0.22]) => [
    Color.lerp(base, Colors.white, amount)!,
    base,
  ];

  static List<Color> _of(List<Color>? fromTheme, Color fallback) =>
      (fromTheme != null && fromTheme.length >= 2) ? fromTheme : soft(fallback);

  // Fallbacks = the built-in default theme, used only before attach().
  static List<Color> get blue =>
      _of(_t?.successGradient.colors.map((e)=>e.withAlpha(150)).toList(), const Color(0xFF2F3E9E));

  static List<Color> get violet =>
      _of(_t?.goldCharcoalGradient.colors, const Color(0xFF7C5CFF));

  static List<Color> get green =>
      _of(_t?.successGradient.colors, const Color(0xFF2FB67C));

  static List<Color> get rose =>
      _of(_t?.dangerGradient.colors, const Color(0xFFF0435F));

  static List<Color> get teal =>
      _of([_t!.accent2, _t!.primary], const Color(0xFFC9A227));

  static List<Color> get orange => soft(_t?.warning ?? const Color(0xFFF2A93B));

  static List<Color> get indigo => [
    _t?.primaryLight ?? const Color(0xFF5C6BD6),
    _t?.primary ?? const Color(0xFF2F3E9E),
  ];

  static List<Color> get slate =>
      soft(_t?.charcoalLight ?? const Color(0xFF4B4F6B), 0.18);

  static List<List<Color>> get all => [
    blue,
    violet,
    green,
    orange,
    rose,
    teal,
    indigo,
    slate,
  ];
}

TextStyle adminText(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? height,
}) => TextStyle(
  fontFamily: 'tajawal',
  fontSize: size,
  fontWeight: weight,
  color: color ?? context.colors.textDark,
  height: height,
);

// ── icon ─────────────────────────────────────────────────────────────────────
class ServiceIcon extends StatelessWidget {
  const ServiceIcon({
    super.key,
    required this.icon,
    required this.colors,
    this.size = 44,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(size * 0.36),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

// ── hero banner ──────────────────────────────────────────────────────────────
class PremiumHero extends StatelessWidget {
  const PremiumHero({
    super.key,
    required this.icon,
    required this.colors,
    required this.title,
    this.subtitle,
    this.footer,
  });

  final IconData icon;
  final List<Color> colors;
  final String title;
  final String? subtitle;
  final Widget? footer;

  Widget _blob(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            PositionedDirectional(end: -30, top: -30, child: _blob(130, 0.10)),
            PositionedDirectional(
              start: -24,
              bottom: -44,
              child: _blob(110, 0.08),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(icon, color: Colors.white, size: 29),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'tajawal',
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontFamily: 'tajawal',
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (footer != null) ...[const SizedBox(height: 14), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeroPill extends StatelessWidget {
  const HeroPill(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'tajawal',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── card ─────────────────────────────────────────────────────────────────────
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.icon,
    required this.colors,
    required this.title,
    required this.children,
    this.hint,
  });

  final IconData icon;
  final List<Color> colors;
  final String title;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      // Transparent Material so InkWell splashes inside are painted above the
      // decorated container instead of being hidden behind it.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ServiceIcon(icon: icon, colors: colors, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: adminText(
                        context,
                        size: 16,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: 10),
                Text(
                  hint!,
                  style: adminText(
                    context,
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: c.textMedium,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// ── selectable tile ──────────────────────────────────────────────────────────
class PremiumSelectTile extends StatelessWidget {
  const PremiumSelectTile({
    super.key,
    required this.selected,
    required this.color,
    required this.onTap,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.leading,
    this.trailing,
    this.footer,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? leading;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : c.inputBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : c.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: adminText(
                            context,
                            size: 14.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: adminText(
                              context,
                              size: 12,
                              weight: FontWeight.w500,
                              color: subtitleColor ?? c.textMedium,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (footer != null) ...[
                          const SizedBox(height: 6),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── switch row ───────────────────────────────────────────────────────────────
class PremiumSwitchRow extends StatelessWidget {
  const PremiumSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: c.primary, size: 22),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: adminText(
                    context,
                    size: 14.5,
                    weight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: adminText(
                      context,
                      size: 12,
                      weight: FontWeight.w500,
                      color: c.textMedium,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: c.primary,
            thumbColor: const WidgetStatePropertyAll(Colors.white),
          ),
        ],
      ),
    );
  }
}

// ── save bar ─────────────────────────────────────────────────────────────────
class PremiumSaveBar extends StatelessWidget {
  const PremiumSaveBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.check_rounded,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: loading ? null : onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: const TextStyle(
                                fontFamily: 'tajawal',
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
