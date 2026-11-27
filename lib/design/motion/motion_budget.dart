// lib/design/motion/motion_budget.dart
//
// The per-screen motion budget (KIT_SPEC §4.3). AppAreaScope installs one; entrance widgets ask it before they move:
// one hero-move kind per screen, at most 12 entrances on a phone (24 from 700 px), nothing after the first 1.2 s,
// at most 3 decorative loops. No budget above a widget (a dialog, the gallery, a test): every claim is granted.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app_responsive.dart' show Breakpoints;

enum MotionKind { flip, deal, wipe, wobble, pop, slap, ink, squiggle }

extension MotionKindHero on MotionKind {
  /// flip, deal, wipe and wobble are hero moves: one kind per screen.
  bool get isHeroMove =>
      this == MotionKind.flip || this == MotionKind.deal || this == MotionKind.wipe || this == MotionKind.wobble;
}

/// One per screen.
class AppMotionBudget extends StatefulWidget {
  const AppMotionBudget({
    super.key,
    required this.child,
    this.maxEntries,
    this.maxLoops = 3,
    this.window = const Duration(milliseconds: 1200),
  });

  final Widget child;

  /// Null: 12 below [Breakpoints.mobile], 24 from it.
  final int? maxEntries;
  final int maxLoops;
  final Duration window;

  static AppMotionBudgetState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_BudgetScope>()?.state;

  @override
  State<AppMotionBudget> createState() => AppMotionBudgetState();
}

class AppMotionBudgetState extends State<AppMotionBudget> {
  MotionKind? _hero;
  int _entries = 0;
  Duration? _t0;
  final Set<Object> _loops = {};
  bool _warned = false;

  Duration? get _now {
    final b = SchedulerBinding.instance;
    return b.schedulerPhase == SchedulerPhase.idle ? null : b.currentFrameTimeStamp;
  }

  int get _max {
    if (widget.maxEntries != null) return widget.maxEntries!;
    final w = MediaQuery.maybeSizeOf(context)?.width ?? 0;
    return w < Breakpoints.mobile ? 12 : 24;
  }

  /// False = draw the end state at once.
  bool claimEntry(MotionKind kind) {
    final now = _now;
    if (now != null && _t0 != null && now - _t0! > widget.window) return false;
    if (_entries >= _max) return false;
    if (kind.isHeroMove) {
      if (_hero != null && _hero != kind) {
        if (kDebugMode && !_warned) {
          _warned = true;
          debugPrint('AppMotionBudget: ${kind.name} refused, this screen already uses ${_hero!.name}');
        }
        return false;
      }
      _hero = kind;
    }
    _entries++;
    return true;
  }

  /// A loop asks once in initState; refused past [AppMotionBudget.maxLoops].
  bool claimLoop(Object owner) {
    if (_loops.contains(owner)) return true;
    if (_loops.length >= widget.maxLoops) return false;
    _loops.add(owner);
    return true;
  }

  void releaseLoop(Object owner) => _loops.remove(owner);

  @override
  Widget build(BuildContext context) {
    _t0 ??= _now;
    return _BudgetScope(state: this, child: widget.child);
  }
}

class _BudgetScope extends InheritedWidget {
  const _BudgetScope({required this.state, required super.child});

  final AppMotionBudgetState state;

  @override
  bool updateShouldNotify(_BudgetScope old) => false;
}
