// lib/features/home/teacher/t1_home_parts.dart — the pieces of the teacher's redesigned home (Tea1Home.dc.html), plain
// values only (no provider, no network) so the layout harness and the renders draw them as they are.
//
//   T1HomeHero       the hero band: the head (icons, headline, line, the red call to action) · four glass figures · a
//                    sideways row of quick-access chips; the body rides up over its lower edge (AppHeroOverlap)
//   T1Chip           one quick-access chip: a tinted glyph box and a label on a paper pill
//   T1LiveCard       "a meeting is live now": the red card with Join
//   T1CaughtUp       the calm day: the green check, two lines and the pills of what was checked
//   T1FirstSteps     a new teacher: the three numbered first steps
//
// Teacher motion only (M9 presses through the kit's buttons, M10 on the figures, M8 halo on the live card, parked by
// syncMotionLoop). Colours come from `context.colors` and the kit roles; nothing here knows the reference's palette.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeLiveRoom;
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppOdometer, AppPressScale;

/// The hero band of the teacher home: [head] on top (built by the screen: icons, headline, line, call to action),
/// then the figures and the chips, on the role's gradient, with the body riding up over it.
class T1HomeHero extends StatelessWidget {
  const T1HomeHero({super.key, required this.head, this.stats = const [], this.chips = const [], required this.body});

  final Widget head;
  final List<Widget> stats;
  final List<Widget> chips;

  /// What rides up over the hero's lower edge.
  final Widget body;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= Breakpoints.mobile;
        final ride = AppHeroOverlap.defaultOverlap(context);
        final gutter = wide ? AppSpace.lg : AppSpace.md;
        // the page's wide role: the hero's text and the body share one column, the band itself is full-bleed
        final inner = AppWidth.wide.inside(box.maxWidth);
        final side = ((box.maxWidth - inner) / 2).clamp(gutter, double.infinity).toDouble();
        final hero = AppHeroSurface(
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(side, wide ? AppHeroMetrics.padTopWide : AppHeroMetrics.padTopPhone, side, AppHeroMetrics.padBottom(ride)),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: context.colors.onHero),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                head,
                if (stats.isNotEmpty) ...[const SizedBox(height: AppSpace.md), _Figures(stats: stats, wide: wide)],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.xs), chips[i]],
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        );
        return AppHeroOverlap(hero: hero, body: Padding(padding: EdgeInsets.symmetric(horizontal: side), child: body));
      });
}

/// The figures: four across from 360 px (and on wide screens), else two by two.
class _Figures extends StatelessWidget {
  const _Figures({required this.stats, required this.wide});
  final List<Widget> stats;
  final bool wide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final oneRow = wide || box.maxWidth >= 300 || stats.length == 1;
        Widget row(List<Widget> xs) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < xs.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.xs), Expanded(child: xs[i])],
            ]);
        if (oneRow) return row(stats);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < stats.length; r += 2) ...[
            if (r > 0) const SizedBox(height: AppSpace.xs),
            row([stats[r], if (r + 1 < stats.length) stats[r + 1] else const SizedBox.shrink()]),
          ],
        ]);
      });
}

/// One figure on the hero (Tea1Home): a glass tile, the value rolls in (M10), the label under it on one line that
/// shrinks to fit (a 390 px phone shows four across).
class T1Figure extends StatelessWidget {
  const T1Figure({super.key, required this.value, required this.label, this.onTap});

  final String value, label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.tile);
    final tile = Container(
      constraints: const BoxConstraints(minHeight: AppTouch.min + AppSpace.md),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: radius,
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AppOdometer(value, memoryKey: 't1home:$label', style: AppType.figure(context).copyWith(color: c.onHero)),
        ),
        const SizedBox(height: AppSpace.xxs),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: AppType.meta(context).copyWith(color: c.onHeroMuted))),
      ]),
    );
    if (onTap == null) return Semantics(container: true, child: tile);
    return Material(type: MaterialType.transparency, child: InkWell(borderRadius: radius, onTap: onTap, child: tile));
  }
}

/// A quick-access chip on the hero: a tinted glyph box, the label, a count when something waits.
class T1Chip extends StatelessWidget {
  const T1Chip({super.key, required this.icon, required this.label, required this.onTap, this.tone, this.count = 0});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? tone;
  final int count;

  /// A long course name stops here and ellipsizes.
  static const double maxWidth = 280;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tone ?? c.primary;
    return Semantics(
      button: true,
      label: count > 0 ? '$label, $count' : label,
      excludeSemantics: true,
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
          color: c.cardBg,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min, maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: AppSpace.xl,
                    height: AppSpace.xl,
                    decoration: BoxDecoration(color: appTintOn(context, t), shape: BoxShape.circle),
                    child: Icon(icon, size: AppIconSize.sm, color: appInkOn(context, t, appTintOn(context, t))),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: AppSpace.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                      constraints: const BoxConstraints(minWidth: AppSpace.lg),
                      decoration: BoxDecoration(color: t, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text('$count', textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.onHero, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "A meeting is live now" (the meetings I'm invited to): the live red card, who invited me, its title and Join.
class T1LiveCard extends StatefulWidget {
  const T1LiveCard({super.key, required this.room, required this.onJoin});

  final MeLiveRoom room;
  final VoidCallback onJoin;

  @override
  State<T1LiveCard> createState() => _T1LiveCardState();
}

class _T1LiveCardState extends State<T1LiveCard> with SingleTickerProviderStateMixin {
  late final AnimationController _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _halo); // M8 halo: parked under Reduce motion
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.room;
    final host = r.hostName ?? '';
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [c.danger, Color.lerp(c.danger, c.heroShade, .35)!],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AnimatedBuilder(
            animation: _halo,
            builder: (context, _) => Container(
              width: AppSpace.sm,
              height: AppSpace.sm,
              decoration: BoxDecoration(color: c.onHero, shape: BoxShape.circle, boxShadow: [
                BoxShadow(color: c.onHero.withValues(alpha: .45 * (1 - _halo.value)), blurRadius: AppSpace.xs + AppSpace.xs * _halo.value, spreadRadius: AppSpace.xxs * _halo.value),
              ]),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              host.isEmpty ? 't1_hm_live_now'.tr : 't1_hm_live_invited'.tr.replaceAll('{name}', host),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(r.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppPressScale(
            child: Material(
              color: c.onHero,
              shape: const StadiumBorder(),
              child: InkWell(
                key: const ValueKey('t1_home.live_join'),
                onTap: widget.onJoin,
                customBorder: const StadiumBorder(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                    child: Center(
                      widthFactor: 1,
                      child: Text('t1_hm_join_now'.tr, style: AppType.label(context).copyWith(color: ensureInk(c.danger, c.onHero), fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The ink on a light pill that reads against [tone].
Color ensureInk(Color tone, Color pill) => ensureContrast(tone, [pill]);

/// The calm day inside the tasks card: the green check, two lines and the pills of what was checked.
class T1CaughtUp extends StatelessWidget {
  const T1CaughtUp({super.key, required this.message, this.checked = const [], this.payout});

  final String? message;

  /// "Attendance not logged", "Awaiting grading", "Join requests": what has nothing waiting.
  final List<String> checked;

  /// "Pending payout 3,200 SAR" (null = none).
  final String? payout;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ok = c.kit.ok.color;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: appTintOn(context, ok),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: ok.withValues(alpha: .25), width: AppBorder.hairline),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: AppDashSize.disc,
            height: AppDashSize.disc,
            decoration: BoxDecoration(color: ok, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: AppIconSize.xl, color: c.onHero),
          ),
          const SizedBox(height: AppSpace.sm),
          Text('t1_hm_calm_done'.tr, textAlign: TextAlign.center, style: AppType.section(context).copyWith(color: c.textDark)),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(message!, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium, height: 1.4)),
          ],
        ]),
      ),
      if (checked.isNotEmpty || payout != null) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final x in checked) _CheckPill(label: x, icon: Icons.circle, tone: ok, tiny: true),
          if (payout != null) _CheckPill(label: payout!, icon: Icons.account_balance_wallet_outlined, tone: c.primary),
        ]),
      ],
    ]);
  }
}

class _CheckPill extends StatelessWidget {
  const _CheckPill({required this.label, required this.icon, required this.tone, this.tiny = false});
  final String label;
  final IconData icon;
  final Color tone;
  final bool tiny;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: T1Chip.maxWidth),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
        decoration: BoxDecoration(
          color: c.cardBg2,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: AppSpace.lg,
            height: AppSpace.lg,
            decoration: BoxDecoration(color: appTintOn(context, tone), shape: BoxShape.circle),
            child: Icon(icon, size: tiny ? AppIconSize.xs / 2 : AppIconSize.sm, color: appInkOn(context, tone, appTintOn(context, tone))),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark))),
        ]),
      ),
    );
  }
}

/// A new teacher's three first steps, numbered ("Complete your teacher profile · Create a course · Add the first
/// session and publish"). A step with no [onTap] is only a line.
class T1FirstSteps extends StatelessWidget {
  const T1FirstSteps({super.key, required this.steps});

  final List<T1Step> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < steps.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.sm),
        Semantics(
          button: steps[i].onTap != null,
          child: Material(
            color: c.cardBg2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: c.divider, width: AppBorder.hairline),
            ),
            child: InkWell(
              onTap: steps[i].onTap,
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: AppSpace.xxl,
                      height: AppSpace.xl,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: appTintOn(context, c.primary), borderRadius: BorderRadius.circular(AppRadius.control)),
                      child: Text(appDigits('${i + 1}'), style: AppType.label(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(steps[i].title, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                    const SizedBox(height: AppSpace.xxs),
                    Text(steps[i].body, style: AppType.body(context).copyWith(color: c.textMedium)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class T1Step {
  const T1Step({required this.title, required this.body, this.onTap});
  final String title, body;
  final VoidCallback? onTap;
}
