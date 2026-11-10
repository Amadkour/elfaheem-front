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
//
// Performance: the moving part of each widget sits between two RepaintBoundaries, so a frame re-records only that
// widget, never the page around it; nothing loops.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

/// The Super Admin's switch for every account (feature catalog). In the disable list = animations OFF for all.
const String kAnimationsFeatureKey = 'app.animations';

/// True while the Super Admin has switched animations off for every account.
bool get appAnimationsOffForAll => AppConfig.disableList.contains(kAnimationsFeatureKey);

/// True when this subtree must not move (the person's Reduce motion, the system's, or the platform switch).
bool appMotionOff(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
  const AppCountUp(this.value, {super.key, this.style, this.memoryKey, this.textAlign, this.textDirection, this.maxLines = 1});

  final String value;
  final TextStyle? style;

  /// Remembers the last value shown under this key (e.g. the tile's label): a rebuilt or revisited tile glides from
  /// it, or stays still when it is the same, instead of counting from zero again.
  final String? memoryKey;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int maxLines;

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
    final parts = AppNumberText.parse(widget.value);
    _parts = parts;
    if (parts == null) {
      _c.value = 1;
      return;
    }
    final key = widget.memoryKey;
    final from = previous ?? (key != null ? AppCountUp._memo[key] : null) ?? 0;
    AppCountUp._remember(key, parts.number);
    if (appMotionOff(context) || from == parts.number) {
      _from = parts.number;
      _c.value = 1;
      return;
    }
    _from = from;
    _c.duration = Duration(milliseconds: initial ? 900 : 600);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Text _text(String s) => Text(s,
      style: widget.style, maxLines: widget.maxLines, textAlign: widget.textAlign, textDirection: widget.textDirection, softWrap: false);

  @override
  Widget build(BuildContext context) {
    final finalText = _text(widget.value);
    final p = _parts;
    if (p == null) return finalText;
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

  static final Expando<Set<String>> _played = Expando('AppReveal');
  static final Object _noRoute = Object();

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
    final owner = ModalRoute.of(context) ?? AppReveal._noRoute;
    final played = AppReveal._played[owner] ??= <String>{};
    if (!played.add('${w.group}:${w.index}')) return;
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
class AppTilt extends StatefulWidget {
  const AppTilt({
    super.key,
    required this.child,
    this.radius = 16,
    this.maxTilt = 4,
    this.glare = false,
    this.shadow = true,
    this.enabled = true,
  });

  final Widget child;
  final double radius;
  final double maxTilt;
  final bool glare;
  final bool shadow;
  final bool enabled;

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
    final deep = [
      BoxShadow(color: shade.withValues(alpha: dark ? 0.42 : 0.12), blurRadius: 34, offset: const Offset(0, 16), spreadRadius: -6),
      BoxShadow(color: shade.withValues(alpha: dark ? 0.30 : 0.07), blurRadius: 10, offset: const Offset(0, 4), spreadRadius: -2),
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
          _aim(_poseAt(e.localPosition, strength: touch ? 0.55 : 1, scale: 0.985, depth: touch ? 0 : 0.6), ms: 110);
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
