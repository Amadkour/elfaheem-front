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
//   AppStatCard(icon:, value:, label:, tone:, footer:, delta:, bars:, barsCaption:, warn:)   the "soft wash" count
//                      card (D-1081): the tone's tint fading into the card, the icon chip and label on top, the big
//                      figure with its hint line under it, an optional mini bar chart of up to 8 values at the end
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
import 'app_gradients.dart' show AppBrandLayer, AppGradientIcon;
import 'app_hero.dart' show AppHeroSurface;
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
  const _Paper({required this.child, this.onTap, this.semanticLabel, this.padding = AppSpace.card, this.gradient});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  /// D-1081: a wash over the paper (AppBrandLayer.statWash); null = the plain card.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final padded = Padding(padding: padding, child: child);
    final body = gradient == null ? padded : Ink(decoration: BoxDecoration(gradient: gradient), child: padded);
    final card = AppLift(
      hover: onTap != null,
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
  const _Delta(this.delta, {this.goodWhenUp = true});

  final double delta;
  final bool goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = delta >= 0;
    final good = up == goodWhenUp;
    final ink = c.blockAccentInk(delta == 0 ? c.textMedium : (good ? c.success : c.danger), c.cardBg);
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

    // the redesign hero surface (KIT_SPEC §5.2): the area / role gradient with the drifting shapes behind
    return AppHeroSurface(
      borderRadius: BorderRadius.circular(AppRadius.block),
      child: Padding(padding: AppSpace.block, child: content),
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

/// A count read at a glance (D-1081, the "soft wash" card): the tone's tint fades into the card from its top start;
/// the icon chip and the label on top; the figure (tabular) with its hint line ([delta] then [footer]) under it; an
/// optional mini bar chart of the last [bars] (up to 8, the latest full, a [barsCaption] under it) at the end.
/// [warn] turns the figure to the danger ink (something is overdue); a "0" reads muted. Its semantics read as one
/// line: label, figure, change, hint, the chart's caption.
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
    this.bars,
    this.barsCaption,
    this.warn = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final AppBlockTone tone;

  /// The hint under the figure ("this week", "1 overdue"); with [delta] the change leads it.
  final String? footer;
  final double? delta;
  final bool deltaGoodWhenUp;
  final VoidCallback? onTap;

  /// The recent values for the mini bar chart (oldest first, at most the last 8 are drawn); null / fewer than 2 = none.
  final List<num>? bars;

  /// What the bars cover ("Last 8 weeks"), drawn under them and read with the card.
  final String? barsCaption;

  /// Something here is late: the figure in the danger ink.
  final bool warn;

  static const int maxBars = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strong = appToneStrong(context, tone);
    final surface = AppBlockColors.of(context, tone == AppBlockTone.paper ? AppBlockTone.emerald : tone).surface;
    final zero = value.trim() == '0';
    final ink = warn ? c.danger : (zero ? c.textLight : c.textDark);
    final raw = bars == null || bars!.length < 2 ? null : bars!.sublist(bars!.length > maxBars ? bars!.length - maxBars : 0);
    // D-1100: a series that is all zeros draws no bars, it says so (eight flat dashes read as a broken chart)
    final idle = raw != null && raw.every((v) => v == 0);
    final series = idle ? null : raw;
    final read = [
      '$label: $value',
      if (delta != null) appDeltaText(delta!),
      if (footer != null) footer!,
      if (series != null && barsCaption != null) '$barsCaption: ${series.join(', ')}',
    ].join(', ');
    return _Paper(
      onTap: onTap,
      semanticLabel: read,
      gradient: AppBrandLayer.statWash(context, surface, strong),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _ToneChip(icon: icon, tone: tone, size: AppTouch.min - AppSpace.md),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Builder(builder: (context) {
          // D-1100: on a phone-size screen the bars sit under the figure, so a 2 × 2 row never squeezes "1.8K"
          // (no LayoutBuilder here: the stat rows measure their cards' intrinsic height)
          final stack = MediaQuery.sizeOf(context).width < AppWidth.phoneMax;
          final figure = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              // a long figure ("Sat 31 October") shrinks to the card instead of being cut at its start edge
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: AppCountUp(value, memoryKey: 'stat:$label', style: _tabular(AppType.figureLarge(context).copyWith(color: ink))),
              ),
              if (delta != null || footer != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (delta != null) _Delta(delta!, goodWhenUp: deltaGoodWhenUp),
                  if (footer != null)
                    Text(footer!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight, height: 1.3)),
                ]),
              ],
            ]);
          final aside = series != null
              ? AppMiniBars(values: series, color: strong, caption: barsCaption)
              : idle
                  ? Text('stat_no_activity'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight))
                  : null;
          if (stack) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              figure,
              if (aside != null) ...[const SizedBox(height: AppSpace.xs), aside],
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: figure),
            if (aside != null) ...[const SizedBox(width: AppSpace.sm), Flexible(child: aside)],
          ]);
        }),
      ]),
    );
  }
}

/// The [AppStatCard] tone for a colour an older stat tile was given (the D-1081 sweep): the primary or success →
/// emerald, warning → gold, danger → peach (pair it with `warn: appStatWarn(...)` so the figure turns red), any other
/// colour → sky.
AppBlockTone appStatToneFor(BuildContext context, Color? color) {
  final c = context.colors;
  if (color == null || color == c.primary || color == c.success) return AppBlockTone.emerald;
  if (color == c.warning) return AppBlockTone.gold;
  if (color == c.danger) return AppBlockTone.peach;
  return AppBlockTone.sky;
}

/// Whether an older stat tile's colour meant "something is wrong" (the danger ink): the stat card's `warn`.
bool appStatWarn(BuildContext context, Color? color) => color != null && color == context.colors.danger;

/// A small bar chart of recent values (oldest first): the latest bar full, the others faint; a caption under it.
/// Decorative inside a card that reads its values aloud (AppStatCard), so it excludes its own semantics.
class AppMiniBars extends StatelessWidget {
  const AppMiniBars({super.key, required this.values, required this.color, this.caption});

  final List<num> values;
  final Color color;
  final String? caption;

  static const double width = AppTouch.min * 2 - AppSpace.md;
  static const double height = AppTouch.min - AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final peak = values.fold<num>(0, (m, v) => v > m ? v : m);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: height,
            // time runs with the reading direction: the latest bar sits at the end (left in Arabic)
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: FractionallySizedBox(
                    heightFactor: peak <= 0 ? 0.08 : (values[i] / peak).clamp(0.08, 1.0).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: i == values.length - 1 ? color : color.withValues(alpha: 0.32),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpace.xxs)),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.overline(context).copyWith(color: c.textLight)),
          ],
        ]),
      ),
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
                    decoration: BoxDecoration(color: c.dangerBase, borderRadius: BorderRadius.circular(AppRadius.pill)),
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
