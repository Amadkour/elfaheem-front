// exam_ui.dart
//
// Shared premium UI kit for every student exam / flags screen.
// Same visual language as StudentCourseAnalyticsScreen:
// gradient hero, glass icon buttons, soft rounded cards, segmented tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

const kFont = 'bahji';
const kDeep = Color(0xFF0D47A1);
const kDanger = Color(0xFFEF4444);
const kAmber = Color(0xFFF59E0B);
const kViolet = Color(0xFF6C5CE7);

TextStyle examT(double size,
        {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    TextStyle(
        fontFamily: kFont, fontSize: size, fontWeight: w, color: c, height: h);

Color examScoreColor(BuildContext context, double v) => v >= 75
    ? context.colors.success
    : v >= 50
        ? kAmber
        : kDanger;

/// Replaces `{name}` placeholders in an already translated string.
String examFill(String text, Map<String, Object?> params) {
  var out = text;
  params.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

// ══════════════════════════════════════════════════════════════════════════════
// Cards
// ══════════════════════════════════════════════════════════════════════════════

class ExamCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double radius;

  const ExamCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.borderColor,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? c.divider.withValues(alpha: 0.5),
          width: borderColor != null ? 1 : 0.6,
        ),
      ),
      child: child,
    );
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: onTap == null
          ? box
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: box,
              ),
            ),
    );
  }
}

class ExamSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;
  final Color? accent;

  const ExamSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExamCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 19, color: accent ?? c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: examT(14.5, w: FontWeight.w800, c: c.textDark)),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Hero
// ══════════════════════════════════════════════════════════════════════════════

class ExamHero extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;

  const ExamHero({super.key, required this.child, this.colors});

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final cs = colors ?? [kDeep, primary];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: cs,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: cs.last.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
          child: child,
        ),
      ),
    );
  }
}

/// Top row of a hero: back button, title/subtitle, optional trailing actions.
class ExamHeroBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;

  const ExamHeroBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        if (showBack && Navigator.of(context).canPop()) ...[
          GlassIcon(
            icon: Icons.arrow_back_ios_rounded,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: examT(18, w: FontWeight.w800, c: Colors.white)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: examT(12, c: Colors.white70)),
              ],
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 8), a],
      ]);
}

class GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const GlassIcon({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.16),
        shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      );
}

class HeroStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;

  const HeroStat({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: examT(16, w: FontWeight.w800, c: Colors.white)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: examT(10, c: Colors.white70)),
          ]),
        ),
      );
}

class HeroPill extends StatelessWidget {
  final IconData? icon;
  final String text;
  const HeroPill({super.key, required this.text, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: examT(12.5, w: FontWeight.w700, c: Colors.white)),
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Ring
// ══════════════════════════════════════════════════════════════════════════════

class ExamRing extends StatelessWidget {
  final double value; // 0..100
  final double size;
  final double stroke;
  final Color color;
  final Color? track;
  final Widget? center;
  final bool showPercent;

  const ExamRing({
    super.key,
    required this.value,
    required this.size,
    this.stroke = 10,
    this.color = Colors.white,
    this.track,
    this.center,
    this.showPercent = true,
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (value / 100).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: 1,
                strokeWidth: stroke,
                color: track ?? color.withValues(alpha: 0.16),
              ),
            ),
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                color: color,
              ),
            ),
            center ??
                (showPercent
                    ? Text('${(v * 100).round()}%',
                        style: examT(size * 0.24,
                            w: FontWeight.w800, c: color))
                    : const SizedBox.shrink()),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Chips / badges / rows
// ══════════════════════════════════════════════════════════════════════════════

class ExamChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const ExamChip(this.icon, this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: examT(11, w: FontWeight.w700, c: color)),
        ]),
      );
}

class ExamBadge extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const ExamBadge(this.text, this.color, {super.key, this.filled = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? null : color.withValues(alpha: 0.10),
          gradient: filled
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.75)])
              : null,
          borderRadius: BorderRadius.circular(20),
          border: filled ? null : Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: filled
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: Text(text,
            style: examT(12,
                w: filled ? FontWeight.w900 : FontWeight.w700,
                c: filled ? Colors.white : color)),
      );
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconTile(this.icon, this.color, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

class ExamInfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;

  const ExamInfoRow(this.icon, this.label, this.value, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        IconTile(icon, color, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: examT(13, c: context.colors.textMedium)),
        ),
        const SizedBox(width: 8),
        Text(value, style: examT(13.5, w: FontWeight.w800, c: color)),
      ]);
}

class ExamStatBox extends StatelessWidget {
  final String value, label;
  final Color color;

  const ExamStatBox(this.value, this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: examT(19, w: FontWeight.w800, c: color)),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: examT(10.5, c: context.colors.textMedium)),
          ]),
        ),
      );
}

class ExamBar extends StatelessWidget {
  final double pct;
  final Color color;
  final double height;

  const ExamBar({super.key, required this.pct, required this.color, this.height = 7});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (pct / 100).clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Buttons
// ══════════════════════════════════════════════════════════════════════════════

class GradientButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final Color? color;
  final double height;
  final Widget? loader;

  const GradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.subtitle,
    this.loading = false,
    this.color,
    this.height = 54,
    this.loader,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? context.colors.primary;
    final disabled = onTap == null && !loading;
    final cs = disabled
        ? [context.colors.divider, context.colors.textLight]
        : [color ?? kDeep, base];
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: subtitle != null ? height + 10 : height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: cs,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: base.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: loading
              ? (loader ??
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  ))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: examT(15.5,
                                  w: FontWeight.w800, c: Colors.white)),
                        ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: examT(11, c: Colors.white70)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class SoftButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  const SoftButton({super.key, required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.divider),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: c.textMedium),
            const SizedBox(width: 8),
          ],
          Text(label, style: examT(14.5, w: FontWeight.w700, c: c.textMedium)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tabs
// ══════════════════════════════════════════════════════════════════════════════

Widget examTab(IconData icon, String text) => Tab(
      height: 42,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(text),
      ]),
    );

class ExamTabBar extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;
  final bool scrollable;

  const ExamTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: controller,
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : null,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(12),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(colors: [kDeep, c.primary]),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: c.textMedium,
        labelStyle: examT(12.5, w: FontWeight.w700),
        unselectedLabelStyle: examT(12.5),
        tabs: tabs,
      ),
    );
  }
}

class ExamTabsDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  final List<Widget> tabs;
  final bool scrollable;

  ExamTabsDelegate({
    required this.controller,
    required this.tabs,
    this.scrollable = false,
  });

  @override
  double get minExtent => 66;
  @override
  double get maxExtent => 66;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: context.colors.background,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: ExamTabBar(
            controller: controller, tabs: tabs, scrollable: scrollable),
      );

  @override
  bool shouldRebuild(covariant ExamTabsDelegate old) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
// Empty / error
// ══════════════════════════════════════════════════════════════════════════════

class ExamEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const ExamEmpty({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 42,
                  color: context.colors.primary.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: examT(14, c: context.colors.textMedium, h: 1.6)),
          ]),
        ),
      );
}

class ExamError extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const ExamError({
    super.key,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off_rounded,
                  size: 40, color: kDanger.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: examT(13.5, c: context.colors.textMedium, h: 1.6)),
            const SizedBox(height: 18),
            SizedBox(
              width: 200,
              child: GradientButton(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                height: 48,
                onTap: onRetry,
              ),
            ),
          ]),
        ),
      );
}

class ExamBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const ExamBanner(
      {super.key, required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: examT(12.5, c: color, h: 1.6)),
          ),
        ]),
      );
}
