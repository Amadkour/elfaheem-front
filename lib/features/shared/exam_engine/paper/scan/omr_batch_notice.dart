// "Grading finished: X graded, Y to review" — the notice of a finished scan batch, and the push that opens the exam's
// scan / review screen (`exam.notify kind batch_done`, wired into AppNavigator by the lead).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;

import '../../../../admin/admin_common.dart' show t;
import '../../exam_scan_review.dart' show ExamScansScreen;

/// The sentence: "Grading finished: 12 graded, 3 to review".
String omrBatchDoneText(int graded, int review) =>
    t('انتهى التصحيح: تم تصحيح $graded، و$review للمراجعة', 'Grading finished: $graded graded, $review to review');

/// The notice with an "Open review" action ([onOpen]).
void showOmrBatchDone(int graded, int review, VoidCallback onOpen) =>
    showAppNotice(omrBatchDoneText(graded, review), actionLabel: t('فتح المراجعة', 'Open review'), onAction: onOpen);

/// A push of kind batch_done (`exam_id`, optional `title`): opens the exam's scan / review screen.
void examNoticeBatchDone(BuildContext? ctx, Map<String, dynamic> data) {
  final id = int.tryParse('${data['exam_id'] ?? data['id'] ?? ''}');
  if (id == null) return;
  final nav = (ctx != null && ctx.mounted ? Navigator.maybeOf(ctx) : null) ?? navigatorKey.currentState;
  nav?.push(MaterialPageRoute<void>(builder: (_) => ExamScansScreen(examId: id, examTitle: '${data['title'] ?? data['exam_title'] ?? ''}')));
}
