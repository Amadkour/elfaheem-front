// lib/features/games/core/flame_host.dart — the one place a Flame game is drawn (Games v4 T11).
//
//   FlameHost   wraps Flame's GameWidget for any FlameGame: pauses the engine while the app is in the background or
//               the route is covered (TickerMode off), tells the game about Reduce motion through [onReduceMotion]
//               (the game parks decorative effects, like syncMotionLoop does for widgets), carries a Semantics label,
//               and fills its constraints (a Flame canvas has no intrinsic size, so no overflow is possible)
//   tiltStream  accelerometer values as (x, y) for tilt games; an empty stream on web and desktop
library;

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class FlameHost extends StatefulWidget {
  const FlameHost({
    super.key,
    required this.game,
    required this.semanticLabel,
    this.onReduceMotion,
  });

  final FlameGame game;
  final String semanticLabel;

  /// Called with the current Reduce motion state when the host is first built and each time it changes.
  final ValueChanged<bool>? onReduceMotion;

  @override
  State<FlameHost> createState() => _FlameHostState();
}

class _FlameHostState extends State<FlameHost> with WidgetsBindingObserver {
  bool _appActive = true;
  bool _routeActive = true;
  bool? _reduced;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _apply();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = TickerMode.valuesOf(context).enabled;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced != _reduced) {
      _reduced = reduced;
      widget.onReduceMotion?.call(reduced);
    }
    _apply();
  }

  @override
  void didUpdateWidget(FlameHost old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      widget.onReduceMotion?.call(_reduced ?? false);
      _apply();
    }
  }

  void _apply() {
    final game = widget.game;
    if (_appActive && _routeActive) {
      game.resumeEngine();
    } else {
      game.pauseEngine();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.expand(child: GameWidget<FlameGame>(game: widget.game)),
      ),
    );
  }
}

/// Tilt as (x, y) from the accelerometer, a few updates a second apart enough for a game; empty where there is
/// no sensor access (web, desktop).
Stream<({double x, double y})> tiltStream() {
  if (kIsWeb) return const Stream.empty();
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .map((e) => (x: e.x, y: e.y))
          .handleError((_) {});
    default:
      return const Stream.empty();
  }
}
