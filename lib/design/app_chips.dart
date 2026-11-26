// lib/design/app_chips.dart
//
// The kit's chip (KIT_SPEC §5.5, the reference's `.k-chip`): 34 high inside a 48 hit area, a full pill on the card
// colour with the kit line. Selected: the ink fill with the on-hero label (dark mode: the area tint and ink).
// `onHero` is the glass chip of a top bar (a parent's child switcher). A row of filter chips is a plain `Wrap` or a
// horizontal `ListView`; the selection does not slide.
//
//   AppChip(label: 'Math', selected: i == 0, onTap: () => pick(0))
//   AppChip(label: 'Sara', leading: avatar, onHero: true, selected: true)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';

import 'app_area.dart';
import 'app_motion_kit.dart';
import 'app_tokens.dart';

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.onHero = false,
    this.leading,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// The glass chip of a top bar or a hero.
  final bool onHero;

  /// A 26 px avatar before the label (wins over [icon]).
  final Widget? leading;

  /// A trailing number.
  final int? count;

  static const double height = 34;
  static const double avatar = 26;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final set = AppAreaScope.of(context);
    final Color fill, edge, ink;
    if (onHero) {
      fill = selected ? c.cardBg : c.heroGlass;
      edge = selected ? c.cardBg : c.heroGlassBorder;
      ink = selected ? c.textDark : c.onHero;
    } else if (selected) {
      fill = c.isDark ? set.tint : kit.ink;
      edge = fill;
      ink = c.isDark ? set.ink : c.onHero;
    } else {
      fill = c.cardBg;
      edge = kit.line;
      ink = c.textDark;
    }
    final style = AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600, height: 1.2);
    final radius = BorderRadius.circular(AppRadius.pill);
    final chip = AnimatedContainer(
      duration: AppMotion.of(context).fast,
      constraints: const BoxConstraints(minHeight: height),
      padding: EdgeInsetsDirectional.only(
        start: leading != null ? AppSpace.xxs : AppSpace.sm,
        end: AppSpace.sm,
      ),
      decoration: BoxDecoration(color: fill, borderRadius: radius, border: Border.all(color: edge, width: AppBorder.strong)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[
          SizedBox.square(dimension: avatar, child: ClipOval(child: leading)),
          AppSpace.gapXs,
        ] else if (icon != null) ...[
          Icon(icon, size: AppIconSize.sm, color: ink),
          const SizedBox(width: AppSpace.xxs + AppSpace.xxs / 2),
        ],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        if (count != null) ...[
          const SizedBox(width: AppSpace.xxs + AppSpace.xxs / 2),
          Text(appDigits('$count'), maxLines: 1, style: style.copyWith(color: ink.withValues(alpha: .75))),
        ],
      ]),
    );
    final tappable = onTap != null;
    return Semantics(
      button: tappable,
      selected: selected,
      label: count == null ? label : '$label, ${appDigits('$count')}',
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            mouseCursor: tappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: Center(widthFactor: 1, child: AppJelly(enabled: tappable, child: chip)),
          ),
        ),
      ),
    );
  }
}
