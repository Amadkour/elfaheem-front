// Joins the paper templates (marks/templates) with grade review (marks/review) for the screens outside this folder:
//   markTemplatePicker(context)                     the template step of a grade review (the org's templates, picking)
//   openGradeReviewForExam(context, examId, title)  "Grade review by camera" on an exam's review screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_notice.dart';

import 'package:flutter_education_app/features/exams/exam_features.dart' show examAutoCorrectAllowed;

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t;
import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show ExamAuthoringApi;
import 'package:flutter_education_app/features/exams/hub/revision/exam_revision_flow.dart' show openExamRevision;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart' show MarkMode;
import 'package:flutter_education_app/features/exams/marks/review/grade_review_entry.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_templates.dart';

/// The org's (or the teacher's own) templates in picking mode; null when the teacher backs out.
Future<({int id, String name, double totalMax})?> markTemplatePicker(BuildContext context) async {
  final m = await openMarkTemplates(context, orgId: AppModeController.instance.currentOrgId, pick: true);
  return m == null ? null : (id: m.id, name: m.name, totalMax: m.totalMax ?? 0);
}

/// "Grade review by camera" on an exam's review screen: the guided revision (which falls back to the short form below
/// on an older server).
Future<void> openGradeReviewForExam(BuildContext context, int examId, String examTitle) => openExamRevision(context, examId: examId, title: examTitle);

/// The short form for the course of exam [examId], with that exam preselected. The gradebook's numeric, writable
/// columns come from the Data Lab; an exam without a course explains itself instead.
Future<void> openLegacyGradeReviewForExam(BuildContext context, int examId, String examTitle) async {
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
  await openGradeReview(context, courseId: courseId, columns: columns, pickTemplate: markTemplatePicker, exams: [GradeExam(examId, examTitle)], legacy: true);
}

/// The short form for a course: mark import, or a review on an older server.
Future<void> openLegacyGradeReview(BuildContext context, int courseId, {MarkMode mode = MarkMode.review}) async {
  final columns = await markColumnsOf(courseId);
  if (!context.mounted || columns == null) return;
  await openGradeReview(context, courseId: courseId, columns: columns, pickTemplate: markTemplatePicker, mode: mode, legacy: true);
}

/// The gradebook's numeric, writable columns; null (after a notice) when the gradebook cannot be opened.
Future<List<GradeColumn>?> markColumnsOf(int courseId) async {
  try {
    final g = await DataLabApi().grid(courseId, limit: 1, lang: AppConfig.lang);
    return [for (final c in g.columns) if (c.isNumber && !c.isCalculated && !c.isLocked) GradeColumn(c.key, c.label, c.maxValue)];
  } catch (_) {
    showAppNotice(t('تعذّر فتح دفتر درجات المقرر', 'The course gradebook could not be opened'), error: true);
    return null;
  }
}
