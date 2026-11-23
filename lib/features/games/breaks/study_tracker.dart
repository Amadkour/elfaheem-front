// lib/features/games/breaks/study_tracker.dart — Games v4 T75: wraps course content / the video player and counts
// foreground study time; after the admin's minutes it suggests ONE short game break per session.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/breaks/breaks_service.dart';
import 'package:flutter_education_app/features/games/breaks/study_timer.dart';

class StudyTracker extends StatefulWidget {
  const StudyTracker({super.key, required this.child, this.courseId, this.enabled = true});

  final Widget child;
  final int? courseId;

  /// False (a teacher, a guest): nothing is counted.
  final bool enabled;

  @override
  State<StudyTracker> createState() => _StudyTrackerState();
}

class _StudyTrackerState extends State<StudyTracker> with WidgetsBindingObserver {
  StudyTimer? _timer;
  Timer? _tick;
  bool _foreground = true;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) _load();
  }

  Future<void> _load() async {
    final cfg = await BreaksService.instance.config();
    if (!mounted || !cfg.breakReminders || cfg.studyMinutes <= 0) return;
    _timer = StudyTimer(limit: Duration(minutes: cfg.studyMinutes));
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _foreground = s == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // a route pushed above this one turns TickerMode off: the learner left the content
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    final t = _timer;
    if (t == null) return;
    if (_foreground && _visible) {
      t.resume();
      _tick ??= Timer.periodic(const Duration(seconds: 20), (_) => _check());
    } else {
      t.pause();
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _check() async {
    final t = _timer;
    if (t == null || !mounted || !t.consumeDue()) return;
    final cfg = await BreaksService.instance.config();
    await BreaksService.instance.suggestBreak(widget.courseId, cfg);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _timer?.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
