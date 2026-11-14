// "مراجعة الدرجات" of the Exam Hub (contract B3): compare the marks written on papers with a course's Data Lab column or
// the teacher's own Excel sheet, paper by paper, by camera. The system never changes a grade by itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_notice.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_features.dart' show examAutoCorrectAllowed;
import 'package:flutter_education_app/features/exams/marks/marks_links.dart' show openLegacyGradeReview, openLegacyGradeReviewForExam;
import 'package:flutter_education_app/features/exams/hub/revision/revision_wizard.dart';

/// Opens the guided revision for [examId] / [courseId], or a free one (an Excel sheet, or a course chosen in step 1).
/// An older server, with no revision routes, gets the short start form instead.
Future<void> openExamRevision(BuildContext context, {int? examId, int? courseId, int? orgId, String? title}) async {
  if (!examAutoCorrectAllowed()) return;                 // D-301: the Super Admin's switch
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => RevisionWizardScreen(
      examId: examId,
      courseId: courseId,
      orgId: orgId,
      title: title,
      onOlderServer: () {
        if (!context.mounted) return;
        if (examId != null) {
          openLegacyGradeReviewForExam(context, examId, title ?? '');
        } else if (courseId != null) {
          openLegacyGradeReview(context, courseId);
        } else {
          showAppNotice(t('هذه الخدمة غير متاحة على الخادم الحالي بعد', 'This is not available on the current server yet'), error: true);
        }
      },
    ),
  ));
}
