// The pure part of the grade-review capture screen (contract §5): the counters and what the last photo's answer
// means for the screen. No widget, no camera, no network, so it is tested on its own (test/org/grade_capture_test.dart).
// Whether a photo is blurry / dark is the SERVER's call (the quality gate answers 422 with a code); the phone only
// sends and shows the reason.
library;

import 'package:flutter/foundation.dart';

import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';

/// What a screen wrapped around the capture needs (the Exam Hub's revision run): it holds the camera while a result is
/// on screen, hears each page the server accepted, and knows when the camera is between papers.
class GradeCaptureBridge extends ChangeNotifier {
  bool _hold = false, _busy = false;
  VoidCallback? _rearm;

  /// Called with the id the server gave a queued page and the photo that was sent.
  void Function(int pageId, Uint8List photo)? onQueued;

  bool get hold => _hold;

  /// A shot is under way or a steady run towards auto-capture has begun.
  bool get busy => _busy;

  set hold(bool v) {
    if (v == _hold) return;
    _hold = v;
    notifyListeners();
  }

  /// Called by the capture screen when its state moves.
  void report({required bool busy}) {
    if (busy == _busy) return;
    _busy = busy;
    notifyListeners();
  }

  /// Set by the capture screen.
  void attach(VoidCallback rearm) => _rearm = rearm;

  /// The next paper may fire at once (after Retake: the same paper is still under the camera).
  void rearm() => _rearm?.call();
}

/// What the capture screen is doing, in the order the person sees it.
enum GradeCaptureStage {
  /// Waiting for the next sheet.
  idle,

  /// A photo is being taken / sent / checked by the quality gate.
  checking,

  /// The gate refused the photo as unclear (blurry, glare, page not found …): a retake card is up.
  retake,

  /// The gate refused the photo as too dark / too bright: a retake card is up.
  retakeLight,

  /// The server already has this sheet.
  duplicate,
}

/// The codes of a 422 that are about the light, not the framing or focus.
const gradeLightCodes = {'too_dark', 'too_bright'};

/// The counters ("12 sheets · 9 read · 2 waiting") and the pending problem of one capture session.
class GradeCaptureTally {
  GradeCaptureTally({int read = 0, int waiting = 0})
      : read = read,
        waiting = waiting,
        sent = read + waiting;

  /// Sheets the server holds for this session (read + waiting, and every photo queued here).
  int sent;
  int read;
  int waiting;

  /// A photo is on its way (taking, sending, gate check).
  bool capturing = false;

  /// The last photo needs the person (retake / already scanned): hints and auto-capture wait.
  MarkPageOutcome? problem;

  /// A photo was queued: it counts as a sheet and as waiting.
  void queued() {
    capturing = false;
    sent++;
    waiting++;
    problem = null;
  }

  /// A photo was not queued. A plain error (network, 5xx) leaves no card: the person just shoots again; a refusal
  /// (retake / duplicate) holds the camera until acknowledged.
  void refused(MarkPageOutcome o) {
    capturing = false;
    problem = o.kind == MarkPageKind.error ? null : o;
  }

  /// The server's counts (event or slow poll). Never lowers [sent] below what the server already holds.
  void synced(int serverRead, int serverPending) {
    read = serverRead;
    waiting = serverPending;
    if (sent < read + waiting) sent = read + waiting;
  }

  GradeCaptureStage get stage {
    final p = problem;
    if (p != null) {
      if (p.kind == MarkPageKind.duplicate) return GradeCaptureStage.duplicate;
      if (p.kind == MarkPageKind.retake) return gradeLightCodes.contains(p.code) ? GradeCaptureStage.retakeLight : GradeCaptureStage.retake;
    }
    return capturing ? GradeCaptureStage.checking : GradeCaptureStage.idle;
  }
}
