// Entry points of grade review by camera / mark import (contract §5):
//   openGradeReview(...)            the Data Lab's action: start sheet → session → capture → results.
//   openMarkSessionFromNotice(id)   a `mark_session_done` push / live notice (AppNavigator): the results of that session.
// The template picker is injected (agent FB1's `openMarkTemplates(context, orgId:, pick: true)`); until the app wires
// it, [GradeReviewHooks.templatePicker] holds it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;

import '../../../../admin/admin_common.dart' show t;
import '../../paper/scan/omr_camera.dart' show OmrCamera;
import '../mark_sessions_api.dart';
import 'grade_review_capture.dart';
import 'grade_review_screen.dart';
import 'grade_review_start.dart';

/// Set once at app start by the integration (the templates screen in picking mode).
abstract final class GradeReviewHooks {
  static MarkTemplatePicker? templatePicker;
}

/// Starts a review / import for [courseId]. [columns] are the gradebook's numeric, writable columns.
Future<void> openGradeReview(
  BuildContext context, {
  required int courseId,
  required List<GradeColumn> columns,
  MarkTemplatePicker? pickTemplate,
  List<GradeStudent>? students,
  List<GradeExam> exams = const [],
  MarkMode mode = MarkMode.review,
  MarkSessionsApi? api,
  OmrCamera Function()? camera,
}) async {
  final picker = pickTemplate ?? GradeReviewHooks.templatePicker;
  if (picker == null) {
    showAppNotice(t('قائمة نماذج الأوراق غير متاحة بعد', 'The paper templates list is not available yet'), error: true);
    return;
  }
  final a = api ?? MarkSessionsApi();
  // the open sessions of this course, to continue one instead of starting again (a failure just hides the list)
  final earlier = <MarkSession>[];
  final listed = await a.list(courseId);
  if (listed.ok) {
    for (final i in (listed.map['items'] ?? listed.map['sessions']) as List? ?? const []) {
      if (i is Map) {
        final s = MarkSession.fromJson(Map<String, dynamic>.from(i));
        if (s.open) earlier.add(s);
      }
    }
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  await showAppSheet<void>(
    context,
    (ctx) => AppSheetContent(
      title: t('مراجعة الدرجات بالكاميرا', 'Review grades by camera'),
      children: [
        GradeStartForm(
          columns: columns,
          exams: exams,
          pickTemplate: picker,
          initialMode: mode,
          earlier: earlier.take(5).toList(),
          onOpenEarlier: (s) {
            Navigator.pop(ctx);
            nav.push(MaterialPageRoute<void>(builder: (_) => GradeReviewScreen(sessionId: s.id, api: a, students: students, camera: camera)));
          },
          onStart: (p) async {
            final r = await a.create(
              courseId: courseId,
              mode: p.mode,
              templateId: p.templateId,
              columnKey: p.column.key,
              examId: p.examId,
              roundingStep: p.roundingStep,
            );
            if (!r.ok) {
              showAppNotice(r.message.isNotEmpty ? r.message : t('تعذّر بدء الجلسة', 'The session could not be started'), error: true);
              return;
            }
            final s = MarkSession.fromJson(r.map);
            if (ctx.mounted) Navigator.pop(ctx);
            nav.push(MaterialPageRoute<void>(
              builder: (_) => GradeCaptureScreen(
                session: s,
                api: a,
                camera: camera,
                onDone: (c) => Navigator.of(c).pushReplacement(MaterialPageRoute<void>(builder: (_) => GradeReviewScreen(sessionId: s.id, api: a, students: students, camera: camera))),
              ),
            ));
          },
        ),
      ],
    ),
  );
}

/// The results of session [sessionId] (a `mark_session_done` notice tap).
Future<void> openMarkSessionFromNotice(int sessionId) async {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  await nav.push(MaterialPageRoute<void>(builder: (_) => GradeReviewScreen(sessionId: sessionId)));
}
