// lib/design/motion/motion_burst.dart
//
// M11 AppBurst (KIT_SPEC §4.2, §4.4): ten confetti pieces fly from a point and fade while they turn. ONE OverlayEntry
// in the root overlay, removed when done. Only for the four moments of [BurstMoment] (the allow-list), at most once
// per route per moment, student areas only, nothing under Reduce motion.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent, KitColors;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_area.dart';
import '../app_motion_kit.dart' show appMotionOff, appPlayOnce;
import 'motion_gate.dart' show kDeg;
import 'motion_spec.dart';

enum BurstMoment { bookingConfirmed, examPassed, levelUp, attendanceDone }

/// One piece: its flight (dx, dy; y up negative), size, shape and colour role.
typedef _Piece = ({double dx, double dy, double w, double h, bool circle, Color Function(KitColors k) color});

final List<_Piece> _pieces = [
  (dx: -70, dy: -58, w: 8, h: 8, circle: false, color: (k) => k.accent(AppAccent.sun).color),
  (dx: 62, dy: -66, w: 8, h: 8, circle: true, color: (k) => k.live.color),
  (dx: 84, dy: -8, w: 12, h: 5, circle: false, color: (k) => k.accent(AppAccent.mint).color),
  (dx: -88, dy: 6, w: 8, h: 8, circle: true, color: (k) => k.accent(AppAccent.grape).color),
  (dx: -40, dy: -88, w: 5, h: 12, circle: false, color: (k) => k.partner),
  (dx: 30, dy: -92, w: 8, h: 8, circle: false, color: (k) => k.accent(AppAccent.pink).color),
  (dx: 70, dy: 46, w: 8, h: 8, circle: true, color: (k) => k.accent(AppAccent.lime).color),
  (dx: -64, dy: 52, w: 12, h: 5, circle: false, color: (k) => k.warm),
  (dx: 8, dy: 70, w: 8, h: 8, circle: false, color: (k) => k.accent(AppAccent.sky).color),
  (dx: -12, dy: -104, w: 8, h: 8, circle: true, color: (k) => k.accent(AppAccent.sun).color),
];

abstract final class AppBurst {
  /// Entries on screen now (tests).
  static int get debugLive => _live;
  static int _live = 0;

  /// Fires the burst for [moment] from the centre of [anchor] (or [at], global; default the screen centre).
  static void fire(BuildContext context, BurstMoment moment, {GlobalKey? anchor, Offset? at}) {
    if (appMotionOff(context) || !AppAreaScope.playful(context)) return;
    if (!appPlayOnce(context, 'burst:${moment.name}')) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    var origin = at;
    final box = anchor?.currentContext?.findRenderObject();
    if (origin == null && box is RenderBox && box.hasSize) origin = box.localToGlobal(box.size.center(Offset.zero));
    origin ??= (MediaQuery.maybeSizeOf(context) ?? Size.zero).center(Offset.zero);
    final kit = context.colors.kit;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Burst(
        origin: origin!,
        kit: kit,
        // called once: when the flight ends, or when the overlay goes first (the page left mid-flight)
        onDone: (bool removed) {
          if (!removed) entry.remove();
          _live--;
        },
      ),
    );
    _live++;
    overlay.insert(entry);
  }
}

class _Burst extends StatefulWidget {
  const _Burst({required this.origin, required this.kit, required this.onDone});

  final Offset origin;
  final KitColors kit;
  /// [removed]: the entry is already gone (disposed before the end).
  final void Function(bool removed) onDone;

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotionSpec.burstDelay + AppMotionSpec.burst,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish(removed: false);
    });
  bool _done = false;

  void _finish({required bool removed}) {
    if (_done) return;
    _done = true;
    widget.onDone(removed);
  }
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      AppMotionSpec.burstDelay.inMicroseconds / (AppMotionSpec.burstDelay + AppMotionSpec.burst).inMicroseconds,
      1,
      curve: AppMotionSpec.burstCurve,
    ),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _finish(removed: true);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final t = _t.value;
              return Stack(children: [
                for (var i = 0; i < _pieces.length; i++)
                  Positioned(
                    left: widget.origin.dx + _pieces[i].dx * t - _pieces[i].w / 2,
                    top: widget.origin.dy + _pieces[i].dy * t - _pieces[i].h / 2,
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: (i == 8 ? -200 : 220) * t * kDeg,
                        child: Container(
                          width: _pieces[i].w,
                          height: _pieces[i].h,
                          decoration: BoxDecoration(
                            color: _pieces[i].color(widget.kit),
                            shape: _pieces[i].circle ? BoxShape.circle : BoxShape.rectangle,
                            borderRadius: _pieces[i].circle ? null : const BorderRadius.all(Radius.circular(_r)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      );
}

const double _r = 2;
