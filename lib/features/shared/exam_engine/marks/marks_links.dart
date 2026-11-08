// Joins the paper templates (marks/templates) with grade review (marks/review) for the screens outside this folder:
//   markTemplatePicker(context)                     the template step of a grade review (the org's templates, picking)
//   openGradeReviewForExam(context, examId, title)  "Grade review by camera" on an exam's review screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_notice.dart';

import '../exam_features.dart' show examAutoCorrectAllowed;

import '../../../admin/admin_common.dart' show asInt, asMap, t;
import '../../../teacher/data_lab/data_lab_api.dart';
import '../exam_authoring.dart' show ExamAuthoringApi;
import 'review/grade_review_entry.dart';
import 'review/grade_review_start.dart';
import 'templates/mark_templates.dart';

/// The org's (or the teacher's own) templates in picking mode; null when the teacher backs out.
Future<({int id, String name, double totalMax})?> markTemplatePicker(BuildContext context) async {
  final m = await openMarkTemplates(context, orgId: AppModeController.instance.currentOrgId, pick: true);
  return m == null ? null : (id: m.id, name: m.name, totalMax: m.totalMax ?? 0);
}

/// Grade review for the course of exam [examId], with that exam preselected. The gradebook's numeric, writable
/// columns come from the Data Lab; an exam without a course explains itself instead.
Future<void> openGradeReviewForExam(BuildContext context, int examId, String examTitle) async {
  if (!examAutoCorrectAllowed()) return;                 // D-301: the Super Admin's switch
  final r = await ExamAuthoringApi().exam(examId);
  final exam = asMap(r.map['exam']).isNotEmpty ? asMap(r.map['exam']) : r.map;
  final courseId = asInt(exam['course_id']);
  if (!r.ok || courseId <= 0) {
    showAppNotice(
        r.ok
            ? t('هذا الاختبار غير مرتبط بمقرر، فلا يوجد عمود درجات لمراجعته', 'This exam is not linked to a course, so there is no grade column to review')
            : r.message,
        error: true);
    return;
  }
  final columns = <GradeColumn>[];
  try {
    final g = await DataLabApi().grid(courseId, limit: 1, lang: AppConfig.lang);
    for (final c in g.columns) {
      if (c.isNumber && !c.isCalculated && !c.isLocked) columns.add(GradeColumn(c.key, c.label, c.maxValue));
    }
  } catch (_) {
    showAppNotice(t('تعذّر فتح دفتر درجات المقرر', 'The course gradebook could not be opened'), error: true);
    return;
  }
  if (!context.mounted) return;
  if (columns.isEmpty) {
    showAppNotice(t('لا يوجد في دفتر الدرجات عمود رقمي قابل للتعديل', 'The gradebook has no editable number column'), error: true);
    return;
  }
  await openGradeReview(context, courseId: courseId, columns: columns, pickTemplate: markTemplatePicker, exams: [GradeExam(examId, examTitle)]);
}
