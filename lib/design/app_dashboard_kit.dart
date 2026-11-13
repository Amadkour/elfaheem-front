// lib/design/app_dashboard_kit.dart
//
// The premium dashboard pieces (D-631): the shapes of a modern admin dashboard (a greeting hero, stat cards with a
// coloured footer band, KPI cards with a sparkline, ring stats, shortcut tiles, section cards with period tabs)
// drawn in the Warm Editorial palette — the forest primary, cream paper, the peach / sky / gold / emerald block
// tones (AppBlockTone) — never a borrowed purple. Plain values in, no provider: a role home maps its own data in.
//
//   AppGreetingHero(greeting:, summary:, avatar:, ring:, cta:, actions:, illustration:, centered:)
//                      the forest hero of a home: time chip, avatar in a progress ring, the greeting in the display
//                      face, one summary line, ONE call to action (AppGreetingHeroButton), soft drawn shapes
//   AppGreetingHeroButton(label:, onTap:, icon:)   the hero's one paper pill
//   AppStatCard(icon:, value:, label:, tone:, footer:, delta:)   icon chip + big tone figure + label; an optional
//                      tinted footer band ("+12% this week") in the tone's block colour
//   AppKpiSpark(label:, value:, values:, icon:, delta:, tone:)   a figure beside a small sparkline
//   AppRingStat(label:, value:, progress:, caption:, delta:, tone:)   text at the start, a progress ring at the end
//   AppShortcutTile(icon:, label:, onTap:, tone:, badge:)   a square-ish tile, label on top, a large soft icon in a
//                      tinted disc at the bottom end; AppShortcutGrid lays them out (2 columns on phones, 4 wide)
//   AppSectionCard(title:, subtitle:, actions:, tabs:, child:)   paper card with a header row and a tabs slot
//   AppBreadcrumb(parts:)   home glyph / part / part — the last one in the primary ink (text only, no links)
//
// Figures are tabular in the UI sans; headings in the editorial face (AppType). Colours from context.colors only.
// Motion: figures count up once (AppCountUp), rings and lines draw in once (AppDrawIn), tappables press in
// (AppPressScale) — all off under Reduce motion. Layout test: test/ui/app_dashboard_kit_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_blocks.dart';
import 'app_charts.dart' show AppSparkline;
import 'app_gradients.dart' show AppBrandLayer, AppDoodleScope, AppGradientIcon;
import 'app_kpi.dart' show appDeltaText;
import 'app_motion_kit.dart';
import 'app_tokens.dart';
import 'chrome_button.dart' show ChromeBar;
import '../core/app_time.dart';

/// The strong colour of a block tone: the figure, the icon and the ring of a dashboard card.
Color appToneStrong(BuildContext context, AppBlockTone tone) {
  final c = context.colors;
  final raw = switch (tone) {
    AppBlockTone.peach => c.accent,
    // sky / sage (one tone since D-630): accent3 is a pale block colour, so its strong colour is it darkened toward
    // a readable grey-green (blockAccentInk below takes it to AA)
    AppBlockTone.sky => HSLColor.fromColor(c.accent3).withLightness(0.38).toColor(),
    AppBlockTone.gold => c.accent2,
    AppBlockTone.emerald => c.primary,
    AppBlockTone.paper => c.textDark,
    AppBlockTone.forest => c.heroInk,
    AppBlockTone.identity => c.primary,
  };
  // as TEXT on the card surface it must read (AA): darkened in light mode, lifted in dark mode
  return c.blockAccentInk(raw, c.cardBg);
}

TextStyle _tabular(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// A tone's icon in a soft disc of its block colour.
class _ToneChip extends StatelessWidget {
  const _ToneChip({required this.icon, required this.tone, this.size = 40});

  final IconData icon;
  final AppBlockTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = AppBlockColors.of(context, tone == AppBlockTone.paper ? AppBlockTone.emerald : tone);
    // D-650: the tone's colour on paper, a primary-tinted grey in dark mode (never the browned warm tone)
    final disc = AppBrandLayer.toneDisc(context, b.surface);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: disc, borderRadius: BorderRadius.circular(AppRadius.control)),
        alignment: Alignment.center,
        // D-650: the glyph wears the green → cream family on its tinted chip
        child: AppGradientIcon(icon, size: size * 0.5, on: [Color.alphaBlend(disc, context.colors.cardBg)]),
      ),
    );
  }
}

/// The paper surface of every card here: the white card, one soft shadow, a near-invisible edge (D-632), radius
/// `card`; a press depth when tappable.
class _Paper extends StatelessWidget {
  const _Paper({required this.child, this.onTap, this.semanticLabel, this.padding = AppSpace.card});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = AppDoodleScope(on: false, child: Padding(padding: padding, child: child));
    final card = AppLift(
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: AppShadow.cardEdge(context)),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
    final labelled = semanticLabel == null
        ? card
        : Semantics(container: true, button: onTap != null, label: semanticLabel, excludeSemantics: true, child: card);
    return AppPressScale(enabled: onTap != null, child: labelled);
  }
}

/// "▲ +12%" in the success / danger ink (or the reverse when lower is better).
class _Delta extends StatelessWidget {
  const _Delta(this.delta, {this.goodWhenUp = true, this.onSurface});

  final double delta;
  final bool goodWhenUp;
  final Color? onSurface;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = delta >= 0;
    final good = up == goodWhenUp;
    final ink = c.blockAccentInk(delta == 0 ? c.textMedium : (good ? c.success : c.danger), onSurface ?? c.cardBg);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: AppIconSize.sm, color: ink),
      const SizedBox(width: AppSpace.xxs),
      Text(appDeltaText(delta), maxLines: 1, style: _tabular(AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Greeting hero
// ─────────────────────────────────────────────────────────────────────────────

/// The forest hero of a home (the reference's greeting card, in our primary): a time chip, an avatar in a progress
/// ring, the greeting in the display face, one summary line and ONE call to action, over soft drawn shapes.
///
/// [centered]: the desktop card beside a side card (avatar on top, everything centred); otherwise the phone
/// layout — text at the start, the avatar (or [illustration]) at the end. [actions] are small glass buttons at the
/// top end (ChromeIconButtons draw as glass inside, through [ChromeBar]). [footer] sits under the call to action
/// (the context switcher).
class AppGreetingHero extends StatelessWidget {
  const AppGreetingHero({
    super.key,
    required this.greeting,
    this.summary,
    this.avatar,
    this.initials,
    this.ring,
    this.timeLabel,
    this.showTime = true,
    this.cta,
    this.actions = const [],
    this.illustration,
    this.footer,
    this.centered = false,
    this.greetingMaxLines = 2,
  });

  /// The one big line: "Good evening, Mona".
  final String greeting;

  /// One line under it: "2 sessions today · 3 to do".
  final String? summary;

  /// The picture inside the ring (an AppNetworkImage, a CircleAvatar …); null draws [initials].
  final Widget? avatar;
  final String? initials;

  /// The ring's progress, 0..1 (the week's goal, a course's progress); null = a closed quiet ring.
  final double? ring;

  /// The chip's text; null = the time now, in the effective timezone (AppTime).
  final String? timeLabel;
  final bool showTime;

  /// The ONE call to action ([AppGreetingHeroButton]).
  final Widget? cta;
  final List<Widget> actions;

  /// Drawn at the bottom end (phone layout only; a large soft icon, an asset). Null = the drawn shapes alone.
  final Widget? illustration;
  final Widget? footer;
  final bool centered;
  final int greetingMaxLines;

  static const double _avatar = AppDashSize.avatar, _avatarSmall = AppDashSize.avatarSm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final time = timeLabel ?? AppTime.time(DateTime.now().toUtc());
    final titleStyle = AppType.display(context).copyWith(color: c.onHero);
    final summaryStyle = AppType.body(context).copyWith(color: c.onHeroMuted, height: 1.5);

    Widget avatarRing(double size) => _AvatarRing(size: size, progress: ring, initials: initials, child: avatar);

    // the time at the start, the buttons at the end; on a narrow phone the buttons take a line of their own (a Wrap,
    // not a LayoutBuilder: the hero may sit in an equal-height row that asks for its intrinsic height)
    final topRow = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpace.xs,
      children: [
        if (showTime) _GlassChip(icon: Icons.schedule_rounded, label: time) else const SizedBox.shrink(),
        if (actions.isNotEmpty) ChromeBar(child: Wrap(children: actions)),
      ],
    );

    final greetingText = Semantics(
      header: true,
      child: Text(greeting,
          maxLines: greetingMaxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: titleStyle),
    );
    final summaryText = summary == null || summary!.isEmpty
        ? null
        : Text(summary!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: summaryStyle);

    final Widget content;
    if (centered) {
      content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        topRow,
        const SizedBox(height: AppSpace.md),
        Center(child: avatarRing(_avatar)),
        const SizedBox(height: AppSpace.md),
        greetingText,
        if (summaryText != null) ...[const SizedBox(height: AppSpace.xs), summaryText],
        if (cta != null) ...[const SizedBox(height: AppSpace.lg), Center(child: cta!)],
        if (footer != null) ...[const SizedBox(height: AppSpace.md), Center(child: footer!)],
      ]);
    } else {
      content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        topRow,
        const SizedBox(height: AppSpace.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              greetingText,
              if (summaryText != null) ...[const SizedBox(height: AppSpace.xs), summaryText],
            ]),
          ),
          const SizedBox(width: AppSpace.md),
          illustration ?? avatarRing(_avatarSmall),
        ]),
        if (cta != null) ...[
          const SizedBox(height: AppSpace.md),
          Align(alignment: AlignmentDirectional.centerStart, child: cta!),
        ],
        if (footer != null) ...[
          const SizedBox(height: AppSpace.md),
          Align(alignment: AlignmentDirectional.centerStart, child: footer!),
        ],
      ]);
    }

    return DecoratedBox(
      // the home's ONE forest block (D-630): forest → emerald with a soft gold glow (D-649, static); dark mode keeps a
      // cream hairline for an edge
      decoration: BoxDecoration(
        gradient: AppBrandLayer.forest(context),
        borderRadius: BorderRadius.circular(AppRadius.block),
        border: c.isDark ? Border.all(color: c.heroInk.withValues(alpha: 0.10), width: AppBorder.hairline) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.block),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: AppBrandLayer.forestGlow(context)),
          child: CustomPaint(
            painter: _HeroShapesPainter(ink: c.onHero, rtl: rtl),
            child: Padding(padding: AppSpace.block, child: content),
          ),
        ),
      ),
    );
  }
}

/// A small glass pill on the hero: an icon and a short label (the time).
class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.sm, color: c.onHero),
        const SizedBox(width: AppSpace.xxs),
        Text(label, maxLines: 1, style: _tabular(AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// The avatar inside a ring: a faint closed track and, when [progress] is given, the arc of it drawn in once.
class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.size, this.progress, this.initials, this.child});

  final double size;
  final double? progress;
  final String? initials;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inner = size - 2 * AppSpace.xs;
    final face = child ??
        Center(
          child: Text(
            (initials ?? '').trim().isEmpty ? '' : initials!.trim(),
            maxLines: 1,
            style: AppType.headline(context).copyWith(color: c.onHero, height: 1.1),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: AppDrawIn(
          builder: (context, t) => CustomPaint(
            painter: _RingPainter(
              progress: (progress ?? 1).clamp(0.0, 1.0) * t,
              track: c.heroGlassBorder,
              arc: progress == null ? c.heroGlassBorder : c.onHero,
              stroke: AppSpace.xxs - 1,
            ),
            child: Center(
              child: Container(
                width: inner,
                height: inner,
                decoration: BoxDecoration(color: c.heroGlass, shape: BoxShape.circle),
                clipBehavior: Clip.antiAlias,
                child: face,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero's own paper pill: the ONE call to action on the forest surface.
class AppGreetingHeroButton extends StatelessWidget {
  const AppGreetingHeroButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.blockAccentInk(c.primary, c.onHero);
    return AppPressScale(
      child: Material(
        color: c.onHero,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: AppIconSize.md, color: ink), const SizedBox(width: AppSpace.xs)],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero's drawn decoration: one large soft disc leaving the top end, a thin ring, a few small dots — the
/// reference's ribbons and confetti as calm vector shapes in the on-hero ink at a low alpha.
class _HeroShapesPainter extends CustomPainter {
  _HeroShapesPainter({required this.ink, required this.rtl});

  final Color ink;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double f) => rtl ? size.width * (1 - f) : size.width * f;
    final soft = Paint()..color = ink.withValues(alpha: 0.07);
    final softer = Paint()..color = ink.withValues(alpha: 0.05);
    final line = Paint()
      ..color = ink.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.strong;
    final r = math.max(size.shortestSide * 0.55, 80.0);
    canvas.drawCircle(Offset(x(1.02), -r * 0.25), r, soft);
    canvas.drawCircle(Offset(x(0.92), size.height * 1.05), r * 0.55, softer);
    canvas.drawCircle(Offset(x(0.08), size.height * 0.92), r * 0.32, line);
    final dot = Paint()..color = ink.withValues(alpha: 0.18);
    for (final (fx, fy, d) in const [(0.62, 0.16, 3.0), (0.72, 0.30, 2.0), (0.18, 0.72, 2.5), (0.86, 0.62, 2.0)]) {
      canvas.drawCircle(Offset(x(fx), size.height * fy), d, dot);
    }
  }

  @override
  bool shouldRepaint(_HeroShapesPainter old) => old.ink != ink || old.rtl != rtl;
}

/// A ring: a closed [track] and an [arc] of [progress] from the top, clockwise in either direction.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.arc, required this.stroke});

  final double progress;
  final Color track, arc;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (progress > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, p..color = arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.arc != arc || old.stroke != stroke;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stat card (figure + label + footer band)
// ─────────────────────────────────────────────────────────────────────────────

/// A stat: the figure large in the tone's strong ink, its label under it, the icon chip at the end, and an optional
/// footer band in the tone's block colour carrying the change ("+12% this week").
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.tone = AppBlockTone.emerald,
    this.footer,
    this.delta,
    this.deltaGoodWhenUp = true,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final AppBlockTone tone;

  /// The band's text ("this week", "of 40 seats"); with [delta] the change leads it.
  final String? footer;
  final double? delta;
  final bool deltaGoodWhenUp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strong = appToneStrong(context, tone);
    final band = AppBlockColors.of(context, tone == AppBlockTone.paper ? AppBlockTone.emerald : tone);
    final hasBand = footer != null || delta != null;
    final read = [
      '$label: $value',
      if (delta != null) appDeltaText(delta!),
      if (footer != null) footer!,
    ].join(', ');
    return _Paper(
      onTap: onTap,
      semanticLabel: read,
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: AppSpace.card,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppCountUp(value, memoryKey: 'stat:$label', style: _tabular(AppType.figureLarge(context).copyWith(color: strong))),
                const SizedBox(height: AppSpace.xxs),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
              ]),
            ),
            const SizedBox(width: AppSpace.sm),
            _ToneChip(icon: icon, tone: tone),
          ]),
        ),
        if (hasBand)
          Container(
            color: band.surface,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
            child: Row(children: [
              if (delta != null) ...[
                _Delta(delta!, goodWhenUp: deltaGoodWhenUp, onSurface: band.surface),
                const SizedBox(width: AppSpace.xs),
              ],
              if (footer != null)
                Expanded(
                  child: Text(footer!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: band.muted)),
                )
              else
                const Spacer(),
            ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  KPI with a sparkline
// ─────────────────────────────────────────────────────────────────────────────

/// A KPI read at a glance: the icon chip and the label on top, the figure and its change, then a small sparkline of
/// its recent [values] in the tone's ink.
class AppKpiSpark extends StatelessWidget {
  const AppKpiSpark({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    this.icon,
    this.delta,
    this.deltaGoodWhenUp = true,
    this.tone = AppBlockTone.emerald,
    this.onTap,
  });

  final String label;
  final String value;
  final List<double> values;
  final IconData? icon;
  final double? delta;
  final bool deltaGoodWhenUp;
  final AppBlockTone tone;
  final VoidCallback? onTap;

  static const double _sparkH = 44;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strong = appToneStrong(context, tone);
    return _Paper(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (icon != null) ...[_ToneChip(icon: icon!, tone: tone, size: AppTouch.min - AppSpace.md), const SizedBox(width: AppSpace.sm)],
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        // the figure and its change on one line, the line under them across the card (no LayoutBuilder: the card
        // sits in equal-height grids that ask for its intrinsic height)
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppCountUp(value, memoryKey: 'kpi:$label', style: _tabular(AppType.figureLarge(context).copyWith(color: c.textDark))),
            if (delta != null) _Delta(delta!, goodWhenUp: deltaGoodWhenUp),
          ],
        ),
        if (values.length >= 2) ...[
          const SizedBox(height: AppSpace.xs),
          AppSparkline(values, color: strong, height: _sparkH, label: label),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ring stat
// ─────────────────────────────────────────────────────────────────────────────

/// A share read as a ring: the label, the figure, the change and a caption at the start; the ring (with its
/// percentage in the middle) at the end.
class AppRingStat extends StatelessWidget {
  const AppRingStat({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    this.caption,
    this.delta,
    this.tone = AppBlockTone.emerald,
    this.onTap,
  });

  final String label;
  final String value;

  /// 0..1; the ring's centre shows it as a percentage.
  final double progress;
  final String? caption;
  final double? delta;
  final AppBlockTone tone;
  final VoidCallback? onTap;

  static const double _ring = AppDashSize.ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strong = appToneStrong(context, tone);
    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final pct = '${(p * 100).round()}%';
    return _Paper(
      onTap: onTap,
      semanticLabel: [label, value, pct, if (caption != null) caption!].join(', '),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xxs),
            AppCountUp(value, memoryKey: 'ring:$label', style: _tabular(AppType.figureLarge(context).copyWith(color: strong))),
            if (delta != null) _Delta(delta!),
            if (caption != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
            ],
          ]),
        ),
        const SizedBox(width: AppSpace.md),
        SizedBox.square(
          dimension: _ring,
          child: AppDrawIn(
            builder: (context, t) => CustomPaint(
              painter: _RingPainter(progress: p * t, track: c.divider, arc: strong, stroke: AppSpace.xs - 2),
              child: Center(
                child: Text(pct, maxLines: 1, style: _tabular(AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shortcut tile + grid
// ─────────────────────────────────────────────────────────────────────────────

/// A shortcut: its label at the top start, a large soft icon in a tinted disc at the bottom end (the reference's
/// line illustrations as one big calm glyph), an optional count.
class AppShortcutTile extends StatelessWidget {
  const AppShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = AppBlockTone.emerald,
    this.badge = 0,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final AppBlockTone tone;
  final int badge;
  final String? subtitle;

  static const double minHeight = 112;
  static const double _disc = AppDashSize.disc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlockColors.of(context, tone == AppBlockTone.paper ? AppBlockTone.emerald : tone);
    final read = badge > 0 ? '$label, $badge' : label;
    return _Paper(
      onTap: onTap,
      semanticLabel: read,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Stack(children: [
          // a whole soft disc in the bottom-end corner (never clipped by the tile's edge), the glyph at its centre
          PositionedDirectional(
            end: AppSpace.sm,
            bottom: AppSpace.sm,
            child: Container(
              width: _disc,
              height: _disc,
              decoration: BoxDecoration(color: AppBrandLayer.toneDisc(context, b.surface), shape: BoxShape.circle),
              alignment: Alignment.center,
              // D-650: the glyph wears the green → cream family on its tinted disc (a primary-tinted grey in dark mode)
              child: AppGradientIcon(icon,
                  size: AppIconSize.xl, on: [Color.alphaBlend(AppBrandLayer.toneDisc(context, b.surface), c.cardBg)]),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, _disc + AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: AppSpace.xxs),
                  Container(
                    constraints: const BoxConstraints(minWidth: AppIconSize.md, minHeight: AppIconSize.md),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(badge > 99 ? '99+' : '$badge',
                        maxLines: 1, style: _tabular(AppType.overline(context).copyWith(color: c.onHero, height: 1.1, letterSpacing: 0))),
                  ),
                ],
              ]),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Shortcut tiles in equal columns: 2 on phones, 3 on tablets, 4 wide; each row as tall as its tallest tile. A
/// short last row stretches its tiles across the full width, so no slot is ever left empty.
class AppShortcutGrid extends StatelessWidget {
  const AppShortcutGrid({super.key, required this.children, this.maxColumns = 4, this.gap = AppSpace.sm});

  final List<Widget> children;
  final int maxColumns;
  final double gap;

  static int columnsFor(double width, int maxColumns) =>
      math.min(maxColumns, width < 520 ? 2 : (width < 900 ? 3 : 4)).clamp(1, 4);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // fewer tiles than columns (gating hid some): one row of equal tiles, never empty slots
        final cols = math.min(columnsFor(box.maxWidth, maxColumns), math.max(1, children.length));
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          // a short last row shares the full width (3 tiles on a phone: the third spans the row), so an odd count
          // looks intended rather than leaving a hole
          final n = math.min(cols, children.length - i);
          final cells = <Widget>[];
          for (var j = 0; j < n; j++) {
            if (j > 0) cells.add(SizedBox(width: gap));
            cells.add(Expanded(child: children[i + j]));
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
        }
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section card
// ─────────────────────────────────────────────────────────────────────────────

/// A paper card for one section of a dashboard: the title (editorial) and an optional subtitle at the start, its
/// [actions] at the end, an optional [tabs] row under them (period tabs: an AppTabs), then [child].
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.tabs,
    this.padding = AppSpace.card,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? tabs;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
        ]),
      ),
      if (actions.isNotEmpty) ...[
        const SizedBox(width: AppSpace.xs),
        Wrap(spacing: AppSpace.xxs, children: actions),
      ],
    ]);
    return _Paper(
      padding: padding,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (tabs != null) ...[
          const SizedBox(height: AppSpace.sm),
          Align(alignment: AlignmentDirectional.centerStart, child: tabs!),
        ],
        const SizedBox(height: AppSpace.md),
        child,
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Breadcrumb
// ─────────────────────────────────────────────────────────────────────────────

/// Where a page sits: a home glyph, then [parts] separated by slashes; the last part in the primary ink. Text only
/// (it is orientation, not navigation), read out as one line.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({super.key, required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = parts.where((p) => p.trim().isNotEmpty).toList();
    final style = AppType.label(context).copyWith(color: c.textMedium);
    final last = style.copyWith(color: c.blockAccentInk(c.primary, c.background), fontWeight: FontWeight.w600);
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      child: Text('/', style: style.copyWith(color: c.textLight)),
    );
    return Semantics(
      container: true,
      label: '${'breadcrumb_path'.tr}: ${shown.join(' / ')}',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.home_outlined, size: AppIconSize.sm, color: c.textMedium),
        for (var i = 0; i < shown.length; i++) ...[
          sep,
          Flexible(child: Text(shown[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: i == shown.length - 1 ? last : style)),
        ],
      ]),
    );
  }
}
