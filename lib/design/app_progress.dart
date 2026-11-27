// lib/design/app_progress.dart
//
// Progress of the redesign kit (KIT_SPEC §5.7):
//
//   AppProgressRing(value: .38)                     a ring that inks itself in (M2) with the percent counted up in it;
//                                                   sizes 28 (inline, showPercent: false) · 44 (a course row) · 76
//   AppCountdown(until: startUtc, onDone: …)        days · hours · minutes · seconds boxes whose digits roll (M10);
//                                                   leading zero boxes are dropped
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';

import 'app_area.dart';
import 'app_motion_kit.dart';
import 'app_tokens.dart';

class AppProgressRing extends StatelessWidget {
  const AppProgressRing({
    super.key,
    required this.value,
    this.size = AppDashSize.ringSm,
    this.stroke = 5,
    this.tone,
    this.label,
    this.showPercent = true,
    this.semanticLabel,
  });

  /// 0..1 (clamped).
  final double value;
  final double size;
  final double stroke;

  /// Default: the area set's tone.
  final KitTone? tone;

  /// Replaces the percent in the centre.
  final String? label;
  final bool showPercent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? AppAreaScope.of(context).tone;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final percent = '${(v * 100).round()}%';
    final style = AppType.overline(context).copyWith(color: t.ink, letterSpacing: 0);
    final Widget? center = label != null
        ? Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: style, textAlign: TextAlign.center)
        : showPercent
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: AppCountUp(percent, style: style, textDirection: TextDirection.ltr),
              )
            : null;
    return Semantics(
      label: semanticLabel,
      value: appDigits(percent),
      excludeSemantics: true,
      child: AppInkRing(
        value: v,
        color: t.color,
        track: t.tint,
        size: size,
        stroke: stroke,
        center: center == null
            ? null
            : Padding(padding: EdgeInsets.all(stroke + AppBorder.focus), child: center),
      ),
    );
  }
}

/// A countdown to [until] (a UTC instant).
class AppCountdown extends StatefulWidget {
  const AppCountdown({super.key, required this.until, this.onHero = false, this.onDone});

  final DateTime until;
  final bool onHero;

  /// Called once when the time is up.
  final VoidCallback? onDone;

  /// A box's minimum width.
  static const double boxMin = 58;

  @override
  State<AppCountdown> createState() => _AppCountdownState();
}

class _AppCountdownState extends State<AppCountdown> {
  Timer? _timer;
  bool _done = false;

  Duration get _left {
    final d = widget.until.toUtc().difference(DateTime.now().toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDone());
  }

  void _tick() {
    if (!mounted) return;
    // a page under another route keeps quiet; it catches up when it is shown again
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current) setState(() {});
    _checkDone();
  }

  void _checkDone() {
    if (!mounted || _done || _left > Duration.zero) return;
    _done = true;
    _timer?.cancel();
    _timer = null;
    widget.onDone?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final left = _left;
    final d = left.inDays, h = left.inHours % 24, m = left.inMinutes % 60, s = left.inSeconds % 60;
    final parts = <(int, String)>[
      (d, countText(d, ar1: 'يوم', ar2: 'يومان', arFew: 'أيام', arMany: 'يومًا', en1: 'day', en: 'days')),
      (h, countText(h, ar1: 'ساعة', ar2: 'ساعتان', arFew: 'ساعات', arMany: 'ساعة', en1: 'hour', en: 'hours')),
      (m, countText(m, ar1: 'دقيقة', ar2: 'دقيقتان', arFew: 'دقائق', arMany: 'دقيقة', en1: 'minute', en: 'minutes')),
      (s, countText(s, ar1: 'ثانية', ar2: 'ثانيتان', arFew: 'ثوانٍ', arMany: 'ثانية', en1: 'second', en: 'seconds')),
    ];
    // drop the leading zero boxes ("0 days"), keep at least the seconds
    var first = 0;
    while (first < parts.length - 1 && parts[first].$1 == 0) {
      first++;
    }
    final fill = widget.onHero ? c.heroGlass : set.tint;
    final ink = widget.onHero ? c.onHero : set.ink;
    final figure = AppType.figure(context).copyWith(color: ink, fontFeatures: const [FontFeature.tabularFigures()]);
    final label = AppType.meta(context).copyWith(color: widget.onHero ? c.onHeroMuted : ink);
    return Semantics(
      liveRegion: false,
      label: [for (final p in parts.skip(first)) '${appDigits('${p.$1}')} ${p.$2}'].join(', '),
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: [
          for (final (i, p) in parts.skip(first).indexed)
            Container(
              constraints: const BoxConstraints(minWidth: AppCountdown.boxMin),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: widget.onHero ? Border.all(color: c.heroGlassBorder, width: AppBorder.hairline) : null,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppOdometer(p.$1.toString().padLeft(i == 0 && first == 0 ? 1 : 2, '0'),
                    style: figure, textDirection: TextDirection.ltr),
                Text(p.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
              ]),
            ),
        ],
      ),
    );
  }
}

