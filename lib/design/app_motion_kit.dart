// lib/design/app_motion_kit.dart
//
// The app's motion, in one place (D-580 .. D-586). Everything here is one-shot (it plays and stops), honours Reduce
// motion (the person's, the system's, and the Super Admin's `app.animations` switch, which all end up in
// MediaQuery.disableAnimations through AppDisplayScope), and is applied through the shared kit widgets so a page
// gets it without code of its own:
//
//   AppPageTransitionsBuilder   every route: the new page fades in while it glides 24 px from the reading end
//                               (right in English, left in Arabic); iOS keeps the native slide and its back swipe
//   AppTabEntrance              a shell tab that comes to the front fades in and rises 8 px
//   AppCountUp('1,240')         a number counts up the first time it is shown and glides old -> new on a change;
//                               prefix / suffix / grouping / decimals kept ("EGP 1,200", "84%", "1.2K"); a text with
//                               no number, or with two ("3/5", "12:30"), is drawn as is. The screen reader hears the
//                               final value only. [memoryKey] remembers the last value across rebuilds, refreshes
//                               and revisits, so a number never counts up from zero twice
//   AppReveal(index: i)         a section or one of the first 8 items of a list fades in and rises 12 px, staggered;
//                               each (group, index) plays once per route: never again on a refresh or a scroll back
//   AppDrawIn(builder: (c, t))  a chart draws in (t 0 -> 1, once)
//   AppFill(value:, builder:)   a progress value fills from 0 the first time and glides on a change
//   AppSkeletonSwitch           the skeleton crossfades into the content
//   AppPressScale               press feedback (0.98) on a tappable card
//   AppPopIn                    a dialog's panel settles from 96 %
//   AppBump(trigger: n)         a count badge pops once when its number changes
//   AppTilt / AppTiltLayer      the 3D treatment of the hero surfaces: a perspective tilt that follows the mouse,
//                               a press depth on touch, a grounded shadow that deepens on hover, an optional soft
//                               glare, and layers inside that shift for parallax. At rest the transform is the
//                               identity, so text is drawn exactly as without it
//   AppTilt.subtle              the same for a card in a scrolling list (a featured course / image card, the key KPI):
//                               2 degrees under the mouse, no glare, a lighter shadow, and touch gets the press depth
//                               only (D-620)
//   AppCountUp(roll: true)      the digits of a key figure roll like an odometer, with a slight drum perspective
//   / AppOdometer               (streak, points, score; D-620); same memory and final-value semantics as AppCountUp
//   AppEase                     the kit's curves: `out` (a strong ease-out for entrances and exits) and `drawer` (the
//                               iOS sheet curve); `AppEase.sheet` is the bottom sheet's AnimationStyle (D-621)
//
// More depth and motion pieces (flip, parallax image, expanding card, slide-in panel) live in app_depth.dart.
//
// Performance: the moving part of each widget sits between two RepaintBoundaries, so a frame re-records only that
// widget, never the page around it; nothing loops.
library;

export 'motion/motion.dart';

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';

import 'motion/motion_spec.dart' show AppMotionSpec;

/// The Super Admin's switch for every account (feature catalog). In the disable list = animations OFF for all.
const String kAnimationsFeatureKey = 'app.animations';

/// True while the Super Admin has switched animations off for every account.
bool get appAnimationsOffForAll => AppConfig.disableList.contains(kAnimationsFeatureKey);

/// True when this subtree must not move (the person's Reduce motion, the system's, or the platform switch).
bool appMotionOff(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The kit's curves (D-621). Entrances and exits are ease-out (they start fast, at the moment the eye is on them);
/// never ease-in on UI.
abstract final class AppEase {
  /// A strong ease-out: panels, expanding cards, a feedback panel, both ways.
  static const Curve out = Cubic(0.23, 1, 0.32, 1);

  /// The iOS sheet curve: steep at the start, a long gentle settle that reads like a spring (Vaul / Ionic).
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  /// [out] played backwards in time: an exit that leaves fast (a route's reverse curve).
  static const Curve outReversed = FlippedCurve(out);

  /// A bottom sheet: 280 ms in on [drawer], 200 ms out. A drag that lets go short of the dismiss point settles on the
  /// same curve from where the finger left it (Flutter splits the curve there), so the settle reads as a spring.
  static const AnimationStyle sheet = AnimationStyle(
    duration: Duration(milliseconds: 280),
    reverseDuration: Duration(milliseconds: 200),
    curve: drawer,
    reverseCurve: outReversed,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Page transitions
// ─────────────────────────────────────────────────────────────────────────────

/// The app's page transition (all platforms but iOS): the incoming page fades in over the first 70 % while it
/// glides [distance] px in from the reading end; the page under it stays still (nothing shows behind a page).
/// Back reverses it. 300 ms in, 240 ms back.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder({this.distance = 24});

  final double distance;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (appMotionOff(context)) return child;
    return AppPageTransition(animation: animation, distance: distance, child: child);
  }
}

/// The transition itself (also used by routes that build their own, e.g. PageRouteBuilder).
class AppPageTransition extends StatelessWidget {
  const AppPageTransition({super.key, required this.animation, required this.child, this.distance = 24});

  final Animation<double> animation;
  final Widget child;
  final double distance;

  static final Animatable<double> _fade = CurveTween(curve: const Interval(0, 0.7, curve: Curves.easeOut));
  static final Animatable<double> _glide = CurveTween(curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    // from the reading end: the right in English, the left in Arabic
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final glide = animation.drive(_glide);
    return FadeTransition(
      opacity: animation.drive(_fade),
      child: AnimatedBuilder(
        animation: glide,
        child: child,
        builder: (_, child) => Transform.translate(offset: Offset(sign * distance * (1 - glide.value), 0), child: child),
      ),
    );
  }
}

/// No transition at all: Reduce motion. A zero duration, so a page also appears and leaves at once.
class AppNoPageTransitions extends PageTransitionsBuilder {
  const AppNoPageTransitions();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}

/// The theme's page transitions: [reduced] = none anywhere; otherwise the app's on every platform, with iOS
/// keeping the native slide (it carries the edge back swipe).
PageTransitionsTheme appPageTransitionsTheme({required bool reduced}) => reduced
    ? const PageTransitionsTheme(builders: {
        TargetPlatform.android: AppNoPageTransitions(),
        TargetPlatform.iOS: AppNoPageTransitions(),
        TargetPlatform.macOS: AppNoPageTransitions(),
        TargetPlatform.windows: AppNoPageTransitions(),
        TargetPlatform.linux: AppNoPageTransitions(),
        TargetPlatform.fuchsia: AppNoPageTransitions(),
      })
    : const PageTransitionsTheme(builders: {
        TargetPlatform.android: AppPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: AppPageTransitionsBuilder(),
        TargetPlatform.windows: AppPageTransitionsBuilder(),
        TargetPlatform.linux: AppPageTransitionsBuilder(),
        TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
      });

// ─────────────────────────────────────────────────────────────────────────────
//  Tab switches
// ─────────────────────────────────────────────────────────────────────────────

/// A shell tab's body: when [active] turns true it fades in and rises 8 px (220 ms). [enterNow]: play on the first
/// build too (a tab opened for the first time after another one).
class AppTabEntrance extends StatefulWidget {
  const AppTabEntrance({super.key, required this.active, required this.child, this.enterNow = false});

  final bool active;
  final bool enterNow;
  final Widget child;

  @override
  State<AppTabEntrance> createState() => _AppTabEntranceState();
}

class _AppTabEntranceState extends State<AppTabEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  bool _first = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_first) {
      _first = false;
      if (widget.active && widget.enterNow && !appMotionOff(context)) _c.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(AppTabEntrance old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (appMotionOff(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static final Animatable<double> _ease = CurveTween(curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final t = _c.drive(_ease);
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: widget.child,
        builder: (_, child) => Transform.translate(offset: Offset(0, 8 * (1 - t.value)), child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated numbers
// ─────────────────────────────────────────────────────────────────────────────

/// The number inside a display string: prefix · number · suffix, with its grouping and decimals.
@immutable
class AppNumberText {
  const AppNumberText._(this.prefix, this.number, this.suffix, this.decimals, this.grouped);

  final String prefix, suffix;
  final double number;
  final int decimals;
  final bool grouped;

  static final RegExp _token = RegExp(r'\d[\d,]*(?:\.\d+)?');
  static final RegExp _groups = RegExp(r'^\d{1,3}(?:,\d{3})+$');

  /// Null when [s] holds no number or more than one (a time, a fraction, a date): those are drawn as they are.
  static AppNumberText? parse(String s) {
    final all = _token.allMatches(s).toList();
    if (all.length != 1) return null;
    final m = all.first;
    final raw = m.group(0)!;
    if (raw.length > 15) return null;
    final dot = raw.indexOf('.');
    final whole = dot < 0 ? raw : raw.substring(0, dot);
    final grouped = whole.contains(',');
    if (grouped && !_groups.hasMatch(whole)) return null;
    if (whole.endsWith(',')) return null;
    final n = double.tryParse(raw.replaceAll(',', ''));
    if (n == null) return null;
    return AppNumberText._(s.substring(0, m.start), n, s.substring(m.end), dot < 0 ? 0 : raw.length - dot - 1, grouped);
  }

  String format(double v) {
    var t = v.toStringAsFixed(decimals);
    if (grouped) {
      final dot = t.indexOf('.');
      final whole = dot < 0 ? t : t.substring(0, dot);
      final rest = dot < 0 ? '' : t.substring(dot);
      final b = StringBuffer();
      for (var i = 0; i < whole.length; i++) {
        if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
        b.write(whole[i]);
      }
      t = '$b$rest';
    }
    return '$prefix$t$suffix';
  }
}

/// A figure that counts. Draws [value] with [style] like a Text; while it counts, the final value is laid out
/// invisibly underneath (it holds the size, so nothing around it moves, and it is what the screen reader reads).
class AppCountUp extends StatefulWidget {
  const AppCountUp(this.value,
      {super.key, this.style, this.memoryKey, this.textAlign, this.textDirection, this.maxLines = 1, this.roll = false});

  final String value;
  final TextStyle? style;

  /// Remembers the last value shown under this key (e.g. the tile's label): a rebuilt or revisited tile glides from
  /// it, or stays still when it is the same, instead of counting from zero again.
  final String? memoryKey;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int maxLines;

  /// Odometer mode (D-620): instead of counting through every value, each digit rolls on its own column from the old
  /// digit to the new one (up when the number grows, down when it shrinks), the ones first and the higher places a
  /// beat later, with a slight drum perspective. Digits are tabular so the figure keeps its width. For a few key
  /// figures (streak, points, a score), not for every number on a page.
  final bool roll;

  /// Last values by memory key (bounded).
  static final LinkedHashMap<String, double> _memo = LinkedHashMap();

  static void _remember(String? key, double v) {
    if (key == null) return;
    _memo.remove(key);
    _memo[key] = v;
    while (_memo.length > 400) {
      _memo.remove(_memo.keys.first);
    }
  }

  /// Tests: forget every remembered value.
  @visibleForTesting
  static void resetMemory() => _memo.clear();

  @override
  State<AppCountUp> createState() => _AppCountUpState();
}

class _AppCountUpState extends State<AppCountUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: 1);
  AppNumberText? _parts;
  double _from = 0;
  bool _started = false;

  // Odometer mode: one column per digit of the target, counted from the LAST digit (0 = the ones, or the last
  // decimal), and whether it is moving (the only thing that rebuilds; the digits repaint on the controller).
  List<_RollColumn> _cols = const [];
  final ValueNotifier<bool> _moving = ValueNotifier(false);
  _DigitGlyphs? _glyphs;

  @override
  void initState() {
    super.initState();
    void sync() => _moving.value = _c.isAnimating;
    _c
      ..addListener(sync)
      ..addStatusListener((_) => sync());
  }

  double get _shown {
    final p = _parts;
    if (p == null) return 0;
    return _from + (p.number - _from) * Curves.easeOutCubic.transform(_c.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start(initial: true);
    }
  }

  @override
  void didUpdateWidget(AppCountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _start(initial: false);
  }

  void _start({required bool initial}) {
    final previous = initial ? null : _shown;
    final live = !initial && _c.isAnimating;
    final parts = AppNumberText.parse(widget.value);
    _parts = parts;
    if (parts == null) {
      _cols = const [];
      _c.value = 1;
      return;
    }
    final key = widget.memoryKey;
    final from = previous ?? (key != null ? AppCountUp._memo[key] : null) ?? 0;
    AppCountUp._remember(key, parts.number);
    if (appMotionOff(context) || from == parts.number) {
      _from = parts.number;
      _cols = const [];
      _c.value = 1;
      return;
    }
    if (widget.roll) _planRoll(parts, from, live: live);
    _from = from;
    // M10 (KIT_SPEC §4.2): a roll runs 900 ms per column, 80 ms between columns, after a 200 ms start delay
    _c.duration = widget.roll ? _rollTotal(_cols.length) : Duration(milliseconds: initial ? 900 : 600);
    _c.forward(from: 0);
  }

  /// The digits of [n] written as [parts] writes its number, last digit first.
  static List<int> _digits(AppNumberText parts, double n) {
    final s = parts.format(n);
    final token = s.substring(parts.prefix.length, s.length - parts.suffix.length);
    return [
      for (final ch in token.split('').reversed)
        if (_isDigit(ch)) ch.codeUnitAt(0) - 48,
    ];
  }

  static bool _isDigit(String ch) => ch.length == 1 && ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  void _planRoll(AppNumberText parts, double from, {required bool live}) {
    final to = _digits(parts, parts.number);
    final old = _digits(parts, from);
    // interrupted: every column carries on from where it is on screen now (a fraction between two digits)
    final t = _c.value;
    final up = parts.number >= from;
    final cols = <_RollColumn>[];
    for (var i = 0; i < to.length; i++) {
      final double a;
      final bool appear;
      if (live && i < _cols.length) {
        a = _cols[i].at(t) % 10;
        appear = _cols[i].appear && _cols[i].fade(t) < 1;
      } else {
        a = i < old.length ? old[i].toDouble() : 0;
        appear = i >= old.length;
      }
      final b = to[i].toDouble();
      final delta = up ? (b - a) % 10 : -((a - b) % 10);
      cols.add(_RollColumn(from: a, to: a + delta, delay: 0, appear: appear));
    }
    final total = _rollTotal(cols.length).inMicroseconds;
    final span = AppMotionSpec.odometer.inMicroseconds / total;
    _cols = [
      for (var i = 0; i < cols.length; i++)
        _RollColumn(
          from: cols[i].from,
          to: cols[i].to,
          delay: (AppMotionSpec.odometerDelay + AppMotionSpec.odometerColumn * math.min(i, 4)).inMicroseconds / total,
          span: span,
          appear: cols[i].appear,
        ),
    ];
  }

  static Duration _rollTotal(int columns) =>
      AppMotionSpec.odometerDelay + AppMotionSpec.odometer + AppMotionSpec.odometerColumn * math.min(math.max(columns - 1, 0), 4);

  @override
  void dispose() {
    _c.dispose();
    _moving.dispose();
    _glyphs?.dispose();
    super.dispose();
  }

  TextStyle? get _style {
    if (!widget.roll) return widget.style;
    final s = widget.style ?? const TextStyle();
    return s.copyWith(fontFeatures: [...?s.fontFeatures, const FontFeature.tabularFigures()]);
  }

  Text _text(String s) => Text(appDigits(s),
      style: _style, maxLines: widget.maxLines, textAlign: widget.textAlign, textDirection: widget.textDirection, softWrap: false);

  @override
  Widget build(BuildContext context) {
    final finalText = _text(widget.value);
    final p = _parts;
    if (p == null) return finalText;
    if (widget.roll) {
      return RepaintBoundary(
        child: ValueListenableBuilder<bool>(
          valueListenable: _moving,
          builder: (context, moving, _) => moving && _cols.isNotEmpty ? _rolling(context, finalText, p) : finalText,
        ),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (_c.value >= 1) return finalText;
          return Stack(fit: StackFit.passthrough, children: [
            Visibility.maintain(visible: false, child: finalText),
            ExcludeSemantics(child: _text(p.format(_shown))),
          ]);
        },
      ),
    );
  }

  /// The rolling figure: the final text holds the size and is what a screen reader reads; over it, the prefix, one
  /// painted column per digit (separators as text) and the suffix. Built once per change; the columns repaint.
  Widget _rolling(BuildContext context, Text finalText, AppNumberText p) {
    final style = DefaultTextStyle.of(context).style.merge(_style);
    final scaler = MediaQuery.textScalerOf(context);
    var glyphs = _glyphs;
    if (glyphs == null || glyphs.style != style || glyphs.scaler != scaler) {
      glyphs?.dispose();
      glyphs = _glyphs = _DigitGlyphs(style, scaler);
    }
    final s = widget.value;
    final token = s.substring(p.prefix.length, s.length - p.suffix.length);
    final chars = token.split('');
    var column = chars.where(_isDigit).length;
    final number = Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
      for (final ch in chars)
        if (_isDigit(ch))
          CustomPaint(size: glyphs.size, painter: _RollPainter(this, --column, glyphs))
        else
          Text(ch, style: _style, softWrap: false),
    ]);
    final AlignmentGeometry align = switch (widget.textAlign) {
      TextAlign.center => AlignmentDirectional.center,
      TextAlign.end => AlignmentDirectional.centerEnd,
      TextAlign.right => Alignment.centerRight,
      TextAlign.left => Alignment.centerLeft,
      _ => AlignmentDirectional.centerStart,
    };
    return Stack(fit: StackFit.passthrough, clipBehavior: Clip.none, children: [
      Visibility.maintain(visible: false, child: finalText),
      Positioned.fill(
        child: ExcludeSemantics(
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: align,
            child: Row(mainAxisSize: MainAxisSize.min, textDirection: widget.textDirection, children: [
              if (p.prefix.isNotEmpty) Text(p.prefix, style: _style, softWrap: false),
              number,
              if (p.suffix.isNotEmpty) Text(p.suffix, style: _style, softWrap: false),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// One odometer column: a position in digits (it may run past 9 or below 0; drawn mod 10), from [from] to [to],
/// starting [delay] (a fraction of the run) after the ones.
@immutable
class _RollColumn {
  const _RollColumn({required this.from, required this.to, required this.delay, required this.appear, this.span = 1});

  final double from, to, delay;

  /// The share of the run one column takes (M10: 900 ms of the whole).
  final double span;

  /// A column the old number did not have: it fades in while it rolls.
  final bool appear;

  double _k(double t) => t <= delay ? 0 : ((t - delay) / math.max(math.min(span, 1 - delay), 1e-6)).clamp(0.0, 1.0);

  double at(double t) => from + (to - from) * AppMotionSpec.odometerCurve.transform(_k(t));

  double fade(double t) => appear ? Curves.easeOut.transform(_k(t)) : 1;
}

/// The ten digits laid out once for a style and text scale: painted, never laid out again while they roll.
class _DigitGlyphs {
  _DigitGlyphs(this.style, this.scaler) {
    var w = 0.0, h = 0.0;
    for (var d = 0; d < 10; d++) {
      final tp = TextPainter(
        text: TextSpan(text: appDigits('$d'), style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      w = math.max(w, tp.width);
      h = math.max(h, tp.height);
      painters.add(tp);
    }
    size = Size(w, h);
  }

  final TextStyle style;
  final TextScaler scaler;
  final List<TextPainter> painters = [];
  late final Size size;

  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
  }
}

class _RollPainter extends CustomPainter {
  _RollPainter(this.state, this.index, this.glyphs) : super(repaint: state._c);

  final _AppCountUpState state;
  final int index;
  final _DigitGlyphs glyphs;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = state._cols;
    if (index < 0 || index >= cols.length) return;
    final col = cols[index];
    final t = state._c.value;
    final pos = col.at(t);
    final base = pos.floor();
    final frac = pos - base;
    final fade = col.fade(t);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (fade < 1) canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, fade));
    _digit(canvas, size, base % 10, -frac);
    if (frac > 0.001) _digit(canvas, size, (base + 1) % 10, 1 - frac);
    if (fade < 1) canvas.restore();
    canvas.restore();
  }

  /// Digit [d] [off] line heights below its rest place, turned a little on the drum the further it is from it.
  void _digit(Canvas canvas, Size size, int d, double off) {
    final g = glyphs.painters[d];
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + off * size.height);
    if (off != 0) {
      final m = Matrix4.identity()
        ..setEntry(3, 2, 0.12 / math.max(size.height, 1))
        ..rotateX(-off * 0.9);
      canvas.transform(m.storage);
    }
    g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RollPainter old) => old.index != index || old.glyphs != glyphs || old.state != state;
}

/// A key figure whose digits roll on a change (streak, points, a score): [AppCountUp] in odometer mode (D-620), with
/// the same [memoryKey] memory and a screen reader that hears the final value only.
class AppOdometer extends StatelessWidget {
  const AppOdometer(this.value, {super.key, this.style, this.memoryKey, this.textAlign, this.textDirection});

  final String value;
  final TextStyle? style;
  final String? memoryKey;
  final TextAlign? textAlign;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => AppCountUp(value,
      style: style, memoryKey: memoryKey, textAlign: textAlign, textDirection: textDirection, roll: true);
}

/// A count that pops (1 -> 1.18 -> 1) once each time [trigger] changes; never on the first build.
class AppBump extends StatefulWidget {
  const AppBump({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<AppBump> createState() => _AppBumpState();
}

class _AppBumpState extends State<AppBump> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  static final Animatable<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 60),
  ]);

  @override
  void didUpdateWidget(AppBump old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !appMotionOff(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _c.drive(_scale), child: widget.child);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Entrances
// ─────────────────────────────────────────────────────────────────────────────

final Expando<Set<String>> _playedOnRoute = Expando('appPlayOnce');
final Object _noRoute = Object();

/// True the first time [key] is asked for on this route (the route of [context]; none: one app-wide set), false on
/// every later call: a one-shot entrance plays once per route and is simply there when rebuilt, refreshed or scrolled
/// back into view. Shared by [AppReveal] and the redesign motion library (KIT_SPEC §4.2 "Played once").
bool appPlayOnce(BuildContext context, String key) {
  final owner = ModalRoute.of(context) ?? _noRoute;
  final played = _playedOnRoute[owner] ??= <String>{};
  return played.add(key);
}

/// A one-shot staggered entrance: fade in + rise [rise] px, [index] x 50 ms later than the first (capped). Only the
/// first [cap] indexes move (a long list's later items just appear), and each `group:index` plays once per route:
/// rebuilt, refreshed or scrolled back into view, it is simply there.
class AppReveal extends StatefulWidget {
  const AppReveal({super.key, required this.index, required this.child, this.group = '', this.rise = 12, this.cap = 8});

  final int index;
  final String group;
  final double rise;
  final int cap;
  final Widget child;


  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final w = widget;
    if (w.index >= w.cap || appMotionOff(context)) return;
    if (!appPlayOnce(context, '${w.group}:${w.index}')) return;
    final delay = math.min(w.index, 7) * 50;
    final total = 380 + delay;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: total));
    _c = c;
    _t = CurvedAnimation(parent: c, curve: Interval(delay / total, 1, curve: Curves.easeOutCubic));
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return RepaintBoundary(
      child: FadeTransition(
        opacity: t,
        child: AnimatedBuilder(
          animation: t,
          child: RepaintBoundary(child: widget.child),
          builder: (_, child) => Transform.translate(offset: Offset(0, widget.rise * (1 - t.value)), child: child),
        ),
      ),
    );
  }
}

/// A panel that settles from 96 % and fades in once (a dialog's card; the route fades the scrim).
class AppPopIn extends StatelessWidget {
  const AppPopIn({super.key, required this.child, this.from = 0.96});

  final Widget child;
  final double from;

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: math.min(1, t * 1.6),
        child: Transform.scale(scale: from + (1 - from) * t, child: child),
      ),
    );
  }
}

/// A chart drawing in: [builder] gets t from 0 to 1 once (520 ms), 1 at once under Reduce motion.
class AppDrawIn extends StatelessWidget {
  const AppDrawIn({super.key, required this.builder, this.duration = const Duration(milliseconds: 620)});

  final Widget Function(BuildContext context, double t) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return builder(context, 1);
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => builder(context, t),
      ),
    );
  }
}

/// A fraction that fills: from 0 on the first build, from the old value on a change (the bar, the ring).
class AppFill extends StatelessWidget {
  const AppFill({super.key, required this.value, required this.builder, this.duration = const Duration(milliseconds: 700)});

  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return builder(context, value);
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => builder(context, v),
      ),
    );
  }
}

/// The skeleton crossfades into the content (and back, when a load starts from nothing). Only the switch between
/// the two fades: a change inside the content never remounts it.
class AppSkeletonSwitch extends StatelessWidget {
  const AppSkeletonSwitch({super.key, required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey<bool>(loading), child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Press feedback
// ─────────────────────────────────────────────────────────────────────────────

/// Presses in to [scale] while a finger or the mouse is down on it (released when the pointer moves away, i.e. a
/// scroll started). Passive: the child's own InkWell still gets the tap.
class AppPressScale extends StatefulWidget {
  const AppPressScale({super.key, required this.child, this.scale = 0.98, this.enabled = true});

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  bool _down = false;
  Offset? _at;

  void _set(bool v) {
    // a pointer up / cancel can arrive after a long press rebuilt the list and took this card away
    if (mounted && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && !appMotionOff(context);
    return Listener(
      onPointerDown: on
          ? (e) {
              _at = e.localPosition;
              _set(true);
            }
          : null,
      onPointerMove: on
          ? (e) {
              if (_at != null && (e.localPosition - _at!).distance > 10) _set(false);
            }
          : null,
      onPointerUp: on ? (_) => _set(false) : null,
      onPointerCancel: on ? (_) => _set(false) : null,
      child: AnimatedScale(
        scale: _down && on ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  3D
// ─────────────────────────────────────────────────────────────────────────────

/// Where an [AppTilt] is: its rotation, press scale, hover depth (0..1) and the pointer, -1..1 on each axis.
@immutable
class AppTiltPose {
  const AppTiltPose({this.rx = 0, this.ry = 0, this.scale = 1, this.depth = 0, this.nx = 0, this.ny = 0});

  final double rx, ry, scale, depth, nx, ny;

  static const AppTiltPose rest = AppTiltPose();

  bool get isRest => rx == 0 && ry == 0 && scale == 1 && depth == 0;

  static AppTiltPose lerp(AppTiltPose a, AppTiltPose b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return AppTiltPose(
        rx: l(a.rx, b.rx), ry: l(a.ry, b.ry), scale: l(a.scale, b.scale), depth: l(a.depth, b.depth), nx: l(a.nx, b.nx), ny: l(a.ny, b.ny));
  }
}

class _TiltScope extends InheritedWidget {
  const _TiltScope({required this.pose, required super.child});

  final ValueListenable<AppTiltPose> pose;

  @override
  bool updateShouldNotify(_TiltScope old) => old.pose != pose;
}

/// The 3D treatment of a hero surface (the home's hero card, KPI tiles, course cards).
///
/// Mouse: the surface tilts up to [maxTilt] degrees (less on a wide one) so the side under the pointer sinks, lifts
/// a little, and a deeper grounded shadow fades in under it; with [glare] a soft light follows the pointer. Touch: a
/// press sinks it 1.5 % toward the finger. [AppTiltLayer]s inside shift against the tilt (parallax). Nothing moves
/// under Reduce motion. [radius] shapes the shadow and the glare.
///
/// In a scrolling list use [AppTilt.subtle] (D-620). Either way nothing is laid out again while it moves: the pose
/// is a ValueListenable that only repaints the transform, the shadow and the glare.
class AppTilt extends StatefulWidget {
  const AppTilt({
    super.key,
    required this.child,
    this.radius = 16,
    this.maxTilt = 4,
    this.glare = false,
    this.shadow = true,
    this.enabled = true,
    this.touchTilt = true,
    this.shadowStrength = 1,
  });

  /// The quiet preset for a card in a scrolling list: a featured course card, an image card, the key KPI (D-620).
  /// At most 2 degrees under the mouse, no glare, the hover shadow at 60 %, and on touch a press depth only (it
  /// sinks 1.5 %, it does not turn toward the finger, so a list being scrolled never wobbles).
  const AppTilt.subtle({super.key, required this.child, this.radius = 16, this.enabled = true})
      : maxTilt = 2,
        glare = false,
        shadow = true,
        touchTilt = false,
        shadowStrength = 0.6;

  final Widget child;
  final double radius;
  final double maxTilt;
  final bool glare;
  final bool shadow;
  final bool enabled;

  /// Touch: also turn toward the finger (the hero surfaces); false = the press depth only.
  final bool touchTilt;

  /// The hover shadow's strength, 0..1.
  final double shadowStrength;

  @override
  State<AppTilt> createState() => _AppTiltState();
}

class _AppTiltState extends State<AppTilt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  final ValueNotifier<AppTiltPose> _pose = ValueNotifier(AppTiltPose.rest);
  AppTiltPose _from = AppTiltPose.rest, _to = AppTiltPose.rest;
  bool _hover = false;
  Offset? _down;
  Offset _last = Offset.zero;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => _pose.value = AppTiltPose.lerp(_from, _to, Curves.easeOutCubic.transform(_c.value)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = appMotionOff(context);
    if (_still) {
      _c.stop();
      _pose.value = AppTiltPose.rest;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _pose.dispose();
    super.dispose();
  }

  bool get _on => widget.enabled && !_still;

  void _aim(AppTiltPose to, {int ms = 180}) {
    if (!_on) return;
    _from = _pose.value;
    _to = to;
    _c.duration = Duration(milliseconds: ms);
    _c.forward(from: 0);
  }

  AppTiltPose _poseAt(Offset local, {double strength = 1, double scale = 1, double depth = 0}) {
    final s = context.size;
    if (s == null || s.isEmpty) return AppTiltPose.rest;
    final nx = (local.dx / s.width * 2 - 1).clamp(-1.0, 1.0);
    final ny = (local.dy / s.height * 2 - 1).clamp(-1.0, 1.0);
    // a wide surface tilts less: 4 degrees on a 300 px tile, about 1.5 on a full-width hero
    final deg = math.min(widget.maxTilt, 1300 / s.width) * strength;
    final rad = deg * math.pi / 180;
    return AppTiltPose(rx: ny * rad, ry: -nx * rad, scale: scale, depth: depth, nx: nx, ny: ny);
  }

  double get _lift {
    final w = context.size?.width ?? 400;
    return 1 + math.min(0.012, 5 / w); // a few pixels at most
  }

  AppTiltPose _hoverPose(Offset p) => _poseAt(p, scale: _lift, depth: 1);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(widget.radius);
    final dark = c.isDark;
    final shade = dark ? Colors.black : c.textDark;
    final k = widget.shadowStrength.clamp(0.0, 1.0);
    final deep = [
      BoxShadow(color: shade.withValues(alpha: (dark ? 0.42 : 0.12) * k), blurRadius: 34, offset: const Offset(0, 16), spreadRadius: -6),
      BoxShadow(color: shade.withValues(alpha: (dark ? 0.30 : 0.07) * k), blurRadius: 10, offset: const Offset(0, 4), spreadRadius: -2),
    ];
    final glareInk = c.onHero;
    return MouseRegion(
      onEnter: (e) {
        _hover = true;
        _last = e.localPosition;
        _aim(_hoverPose(e.localPosition), ms: 220);
      },
      onHover: (e) {
        _last = e.localPosition;
        if (_down == null) _aim(_hoverPose(e.localPosition), ms: 140);
      },
      onExit: (_) {
        _hover = false;
        _aim(AppTiltPose.rest, ms: 360);
      },
      child: Listener(
        onPointerDown: (e) {
          _down = e.localPosition;
          final touch = e.kind != PointerDeviceKind.mouse;
          if (touch && !widget.touchTilt) {
            _aim(const AppTiltPose(scale: 0.985), ms: 110); // press depth only
          } else {
            _aim(_poseAt(e.localPosition, strength: touch ? 0.55 : 1, scale: 0.985, depth: touch ? 0 : 0.6), ms: 110);
          }
        },
        onPointerMove: (e) {
          final d = _down;
          if (d != null && (e.localPosition - d).distance > 10) {
            _down = null; // a scroll: let go
            _aim(_hover ? _hoverPose(e.localPosition) : AppTiltPose.rest, ms: 200);
          }
        },
        onPointerUp: (_) {
          _down = null;
          _aim(_hover ? _hoverPose(_last) : AppTiltPose.rest, ms: 240);
        },
        onPointerCancel: (_) {
          _down = null;
          _aim(_hover ? _hoverPose(_last) : AppTiltPose.rest, ms: 240);
        },
        child: RepaintBoundary(
          child: ValueListenableBuilder<AppTiltPose>(
            valueListenable: _pose,
            child: _TiltScope(pose: _pose, child: RepaintBoundary(child: widget.child)),
            builder: (context, p, child) {
              final m = Matrix4.identity();
              if (!p.isRest) {
                m
                  ..setEntry(3, 2, 0.0011)
                  ..rotateX(p.rx)
                  ..rotateY(p.ry)
                  ..multiply(Matrix4.diagonal3Values(p.scale, p.scale, 1));
              }
              Widget surface = child!;
              if (widget.glare) {
                surface = Stack(fit: StackFit.passthrough, children: [
                  surface,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: p.depth.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: r,
                            gradient: RadialGradient(
                              center: Alignment(p.nx, p.ny),
                              radius: 0.9,
                              colors: [glareInk.withValues(alpha: 0.16), glareInk.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]);
              }
              return Stack(fit: StackFit.passthrough, clipBehavior: Clip.none, children: [
                if (widget.shadow)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: p.depth.clamp(0.0, 1.0),
                        child: DecoratedBox(decoration: BoxDecoration(borderRadius: r, boxShadow: deep)),
                      ),
                    ),
                  ),
                Transform(transform: m, alignment: Alignment.center, child: surface),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// A layer inside an [AppTilt] that shifts against the tilt by up to [depth] x 6 px (parallax): a cover picture,
/// an ornament. [overscan] enlarges it a little so a shifted picture never shows its edge. Outside an AppTilt it
/// is just the child.
class AppTiltLayer extends StatelessWidget {
  const AppTiltLayer({super.key, required this.child, this.depth = 1, this.overscan = false});

  final Widget child;
  final double depth;
  final bool overscan;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TiltScope>();
    if (scope == null) return child;
    return ValueListenableBuilder<AppTiltPose>(
      valueListenable: scope.pose,
      child: child,
      builder: (_, p, child) {
        if (p.isRest) return Transform.translate(offset: Offset.zero, child: child);
        final k = 6 * depth * p.depth.clamp(0.0, 1.0);
        final m = Matrix4.translationValues(-p.nx * k, -p.ny * k, 0);
        if (overscan) m.multiply(Matrix4.diagonal3Values(1.04, 1.04, 1));
        return Transform(transform: m, alignment: Alignment.center, child: child);
      },
    );
  }
}
