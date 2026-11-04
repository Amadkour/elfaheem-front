// The pure part of the grade-review capture screen (contract §5): the counters and what the last photo's answer
// means for the screen. No widget, no camera, no network, so it is tested on its own (test/org/grade_capture_test.dart).
// Whether a photo is blurry / dark is the SERVER's call (the quality gate answers 422 with a code); the phone only
// sends and shows the reason.
library;

import '../mark_sessions_api.dart';

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
