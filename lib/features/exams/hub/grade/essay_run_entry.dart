// Grade Papers, essay path (D-662): grade photographed written papers against a model answer or rubric, without an
// exam created in the app first. Opened from the Hub's Grade papers chooser (`grade_papers_sheet.dart`). The flow
// lives in essay_run_screen.dart (setup → the run → each student → results); the engine side is back D-651.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/exams/hub/grade/essay_run_screen.dart' show openEssayRunFlow;

/// Opens the essay run for [courseId]. Returns when the teacher is back on the caller's page.
Future<void> openEssayRun(BuildContext context, {required int courseId, required String courseTitle, int? orgId}) =>
    openEssayRunFlow(context, courseId: courseId, courseTitle: courseTitle, orgId: orgId);
