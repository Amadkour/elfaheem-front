// lib/features/profile/teacher/t2b_parts.dart
//
// The hero pieces of the teacher's T2b pages (redesign: schedule, account, complaints, messages), as drawn in
// Tea2Schedule / Tea2Account / Tea2Chat: glass pills that switch the page's view on the hero's lower edge, and a
// glass hero button beside the page's one filled button. Teacher motion only: M9 presses, M13 on the selected pill.
//
//   T2bHeroPills(items: [T2bPill('Calendar', icon: …), T2bPill('Scheduled', count: 2)], index: i, onChanged: …)
//   T2bHeroButton(label: 'Share', icon: Icons.share_outlined, onTap: …)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppJelly;

/// One pill of [T2bHeroPills].
class T2bPill {
  const T2bPill(this.label, {this.icon, this.count, this.key});

  final String label;
  final IconData? icon;

  /// A small red count after the label (unread, waiting for you); nothing when null or 0.
  final int? count;
  final String? key;
}

/// The hero's view switch: a row of glass pills, the chosen one in the card colour with the text ink. It scrolls
/// sideways when the pills do not fit (a phone with five filters).
class T2bHeroPills extends StatelessWidget {
  const T2bHeroPills({super.key, required this.items, required this.index, required this.onChanged});

  final List<T2bPill> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final pills = [
      for (var i = 0; i < items.length; i++) _HeroPill(item: items[i], selected: i == index, onTap: () => onChanged(i)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(children: [
        for (var i = 0; i < pills.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.xs), pills[i]],
      ]),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.item, required this.selected, required this.onTap});

  final T2bPill item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? c.textDark : c.onHero;
    final radius = BorderRadius.circular(AppRadius.pill);
    final n = item.count ?? 0;
    return Semantics(
      button: true,
      selected: selected,
      label: n > 0 ? '${item.label}, $n' : item.label,
      excludeSemantics: true,
      child: AppJelly(
        child: AnimatedContainer(
          key: item.key == null ? null : ValueKey(item.key),
          duration: AppMotion.of(context).base,
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: selected ? c.cardBg : c.heroGlass,
            borderRadius: radius,
            border: Border.all(color: selected ? c.cardBg : c.heroGlassBorder, width: AppBorder.hairline),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: AppIconSize.md, color: ink),
                      const SizedBox(width: AppSpace.xs),
                    ],
                    Text(item.label,
                        maxLines: 1,
                        style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w700)),
                    if (n > 0) ...[
                      const SizedBox(width: AppSpace.xs),
                      Container(
                        constraints: const BoxConstraints(minWidth: AppSpace.lg),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2),
                        height: AppSpace.lg,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.danger, borderRadius: radius),
                        child: Text('$n',
                            style: AppType.overline(context).copyWith(color: appInkOnFill(context, c.danger))),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero's figures (up to four glass tiles): one row from 560 px or for three, else two rows of two (a phone keeps the
/// labels whole).
class T2bHeroFigures extends StatelessWidget {
  const T2bHeroFigures({super.key, required this.stats});

  final List<AppHeroStat> stats;

  static const double _oneRowFrom = 560;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        Widget row(List<AppHeroStat> s) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < s.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.xs), Expanded(child: s[i])],
            ]);
        if (box.maxWidth >= _oneRowFrom || stats.length <= 3) return row(stats);
        final half = (stats.length / 2).ceil();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          row(stats.sublist(0, half)),
          const SizedBox(height: AppSpace.xs),
          row(stats.sublist(half)),
        ]);
      });
}

/// A button on the hero: glass with the on-hero ink (the reference's light button), jelly press (M9).
class T2bHeroButton extends StatelessWidget {
  const T2bHeroButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: AppJelly(
        enabled: onTap != null,
        child: Material(
          color: c.heroGlass,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon, size: AppIconSize.md, color: c.onHero),
                    const SizedBox(width: AppSpace.xs),
                  ],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
