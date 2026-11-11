// lib/features/admin/admin_premium_widgets.dart
//
// Shared "premium" building blocks for the admin pages:
//   • AdminPalette      – colour pairs (light → base) read from the live theme; the base tints feature marks
//   • ServiceIcon       – an icon on a faint opaque tint of its colour (text-safe ink)
//   • PremiumHero       – the page's one tinted block (sky) with an editorial headline
//   • HeroPill          – small fact chip in the block's faint tint
//   • PremiumCard       – titled card (icon + title + hint) that holds children
//   • PremiumSelectTile – selectable row (multi-select or radio style)
//   • PremiumSwitchRow  – label + switch row
//   • PremiumSaveBar    – sticky bottom "Save" bar (use as BasePage.bottomNavigationBar)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../design/app_switch.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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

  /// Ink over the palette's gradients (the theme's on-hero role; the default card surface before attach()).
  static Color get ink => _t?.onHero ?? AppTheme.surfaceCard;

  /// base → soft light version of itself (friendlier than a flat colour).
  static List<Color> soft(Color base, [double amount = 0.22]) => [
    Color.lerp(base, ink, amount)!,
    base,
  ];

  static List<Color> _of(List<Color>? fromTheme, Color fallback) =>
      (fromTheme != null && fromTheme.length >= 2) ? fromTheme : soft(fallback);

  // Fallbacks = the built-in default theme, used only before attach().
  static List<Color> get blue =>
      _of(_t?.successGradient.colors.map((e)=>e.withAlpha(150)).toList(), AppTheme.primary);

  static List<Color> get violet =>
      _of(_t?.goldCharcoalGradient.colors, AppTheme.purple);

  static List<Color> get green =>
      _of(_t?.successGradient.colors, AppTheme.success);

  static List<Color> get rose =>
      _of(_t?.dangerGradient.colors, AppTheme.danger);

  static List<Color> get teal =>
      _of(_t == null ? null : [_t!.accent2, _t!.primary], AppTheme.accent2);

  static List<Color> get orange => soft(_t?.warning ?? AppTheme.warning);

  static List<Color> get indigo => [
    _t?.primaryLight ?? AppTheme.primaryLight,
    _t?.primary ?? AppTheme.primary,
  ];

  static List<Color> get slate =>
      soft(_t?.charcoalLight ?? AppTheme.charcoalLight, 0.18);

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
  fontFamily: AppFonts.family,
  fontSize: size,
  fontWeight: weight,
  color: color ?? context.colors.textDark,
  height: height,
);

/// The tint a palette pair carries: its base colour (the last stop).
Color _base(List<Color> colors) => colors.isEmpty ? AppTheme.primary : colors.last.withValues(alpha: 1);

// ── icon ─────────────────────────────────────────────────────────────────────
/// A feature mark: the icon in its colour's text-safe ink on a faint opaque tint of the same colour (D-612: the
/// icon's tint carries the colour, never a gradient wash). [colors] is a palette pair; its base tone is used.
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
    final c = context.colors;
    final base = _base(colors);
    final tint = Color.alphaBlend(base.withValues(alpha: 0.14), c.cardBg);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(size >= AppTouch.min ? AppRadius.control : AppRadius.chip),
      ),
      child: Icon(icon, color: c.blockAccentInk(base, tint), size: size * 0.5),
    );
  }
}

// ── hero banner ──────────────────────────────────────────────────────────────
/// The page's one tinted block (sky, the admin's tone): an editorial headline in the block's ink, one line of
/// direction and optional [HeroPill]s. [colors] tints only the mark beside the title.
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppBlock(
        tone: AppBlockTone.sage,
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: AppTouch.min,
                    height: AppTouch.min,
                    decoration: BoxDecoration(color: b.faint, borderRadius: AppRadius.controlAll),
                    child: Icon(icon, color: b.accentInk(_base(colors)), size: AppIconSize.lg),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.headline(context).copyWith(color: b.ink),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpace.xxs),
                          Text(
                            subtitle!,
                            style: AppType.body(context).copyWith(color: b.muted, height: 1.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (footer != null) ...[const SizedBox(height: AppSpace.md), footer!],
            ],
          );
        }),
      ),
    );
  }
}

/// A small fact chip inside a [PremiumHero]: the block's faint tint with its ink (never white glass on a light block).
class HeroPill extends StatelessWidget {
  const HeroPill(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 1),
      decoration: BoxDecoration(
        color: b.faint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.xs, color: b.muted),
            const SizedBox(width: AppSpace.xxs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: b.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── card ─────────────────────────────────────────────────────────────────────
/// Paper on a warm hairline (no resting shadow, D-612) with an editorial section title beside its mark.
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
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      // Transparent Material so InkWell splashes inside are painted above the
      // decorated container instead of being hidden behind it.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ServiceIcon(icon: icon, colors: colors, size: AppIconSize.hero),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                    ),
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(hint!, style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.5)),
              ],
              const SizedBox(height: AppSpace.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// ── selectable tile ──────────────────────────────────────────────────────────
/// A selectable row on the input well; the chosen one takes a faint tint of [color] and a 1.5 px ring of it.
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
    final motion = AppMotion.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AnimatedContainer(
        duration: motion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: selected ? Color.alphaBlend(color.withValues(alpha: 0.08), c.cardBg) : c.inputBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(
            color: selected ? color : c.divider,
            width: selected ? AppBorder.strong : AppBorder.hairline,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: AppSpace.sm)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpace.xxs / 2),
                            Text(
                              subtitle!,
                              style: AppType.meta(context).copyWith(color: subtitleColor ?? c.textMedium, height: 1.4),
                            ),
                          ],
                          if (footer != null) ...[
                            const SizedBox(height: AppSpace.xs),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: AppSpace.xs),
                      trailing!,
                    ],
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
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: c.textMedium, size: AppIconSize.md),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(subtitle!, style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          AppSwitch(value: value, onChanged: onChanged, semanticLabel: title),
        ],
      ),
    );
  }
}

// ── save bar ─────────────────────────────────────────────────────────────────
/// The sticky bottom action: paper over a warm hairline holding ONE solid primary button (56 px, the kit's busy
/// spinner keeps its width).
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
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.form.max),
              child: AppButton.primary(
                label: label,
                icon: icon,
                busy: loading,
                expand: true,
                size: AppButtonSize.lg,
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
