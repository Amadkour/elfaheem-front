// lib/core/live_focus.dart
//
// Screens the app must never interrupt with a blocking card (D-977: an organization's must-acknowledge message is
// never shown inside a live exam or a live room). The live room has its own signal (`LiveRoomHost.isOpen` /
// `listenable`); a live exam had none, so the exam-taking screens (online and offline sittings) register here in
// initState / dispose with themselves as the owner. Owners, not a counter: one screen's dispose never clears another's.
//
//   LiveFocus.enterExam(this);   // initState
//   LiveFocus.leaveExam(this);   // dispose
//   LiveFocus.examOpen           // ValueListenable<bool> — listeners must defer their setState (it flips in dispose)
library;

import 'package:flutter/foundation.dart';

class LiveFocus {
  LiveFocus._();

  static final Set<Object> _exams = <Object>{};
  static final ValueNotifier<bool> _examOpen = ValueNotifier<bool>(false);

  /// True while at least one exam-taking screen is open.
  static ValueListenable<bool> get examOpen => _examOpen;

  static bool get isExamOpen => _exams.isNotEmpty;

  static void enterExam(Object owner) {
    _exams.add(owner);
    _examOpen.value = true;
  }

  static void leaveExam(Object owner) {
    _exams.remove(owner);
    _examOpen.value = _exams.isNotEmpty;
  }

  @visibleForTesting
  static void debugReset() {
    _exams.clear();
    _examOpen.value = false;
  }
}
