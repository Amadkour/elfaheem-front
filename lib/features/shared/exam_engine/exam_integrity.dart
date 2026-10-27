// Integrity signals the PLATFORM can observe during an exam (Phase 5; on-device face / gaze models are Phase 9).
//
// `ExamIntegrity.start(onEvent)` wires what each platform offers and reports event KINDS the server understands
// (FLUTTER_API_CHANGES phase 5): web — visibility / focus (`tab_switch`), full-screen exit, copy / paste; mobile —
// app sent to the background (`background`). It never captures content; it only says that something happened.
// The UI is honest about what cannot be prevented (see the consent text): these are signals for the reviewer.
import 'package:flutter/widgets.dart';

import 'exam_integrity_stub.dart' if (dart.library.js_interop) 'exam_integrity_web.dart' as platform;

typedef IntegrityEvent = void Function(String kind, Map<String, dynamic> meta);

/// One `tab_switch` per real switch: the browser fires `visibilitychange` AND `blur` for a single Alt-Tab, which would
/// have counted twice against a "max 1" rule. Pure, so it is unit-tested.
class IntegrityDedupe {
  IntegrityDedupe({this.window = const Duration(milliseconds: 1500)});
  final Duration window;
  final Map<String, DateTime> _last = {};
  static const deduped = {'tab_switch', 'fullscreen_exit'};

  bool accept(String kind, DateTime at) {
    if (!deduped.contains(kind)) return true;
    final prev = _last[kind];
    _last[kind] = at;
    return prev == null || at.difference(prev) >= window;
  }
}

class ExamIntegrity with WidgetsBindingObserver {
  ExamIntegrity(this.onEvent);
  final IntegrityEvent onEvent;
  final _dedupe = IntegrityDedupe();
  bool _started = false;
  DateTime? _hiddenAt;

  void _emit(String kind, Map<String, dynamic> meta) {
    if (_dedupe.accept(kind, DateTime.now())) onEvent(kind, meta);
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    platform.attach(_emit);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    platform.detach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _hiddenAt = DateTime.now();
      onEvent('background', {'state': state.name});
    } else if (state == AppLifecycleState.resumed && _hiddenAt != null) {
      onEvent('resumed', {'away_ms': DateTime.now().difference(_hiddenAt!).inMilliseconds});
      _hiddenAt = null;
    }
  }

  /// What this platform can and cannot do — shown on the consent screen so the student is told the truth.
  static List<String> capabilities() => platform.capabilities();
}
