// lib/features/home/teacher/todo/teacher_todo_actions.dart — where a to-do item is done (D-303). Loaded as a deferred
// part (the exam screens behind it are not in the home's first download).
//
//   course       the teacher's course screen (the home's course list knows it), else the one course page
//   transfers    Payment requests (TeacherTransfersScreen)
//   complaints   the Complaints page (AppNavigator module `support`)
//   calendar     the meeting in the calendar; a clash of two lessons → the calendar
//   exam_review  the exam's review queue · exam_appeals its appeals · omr_review the scanned sheets' questions
// Anything else (a newer server) → the full to-do page stays where it is.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredTeacherSessionsScreen;
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart' show TeacherTransfersScreen;
import 'package:flutter_education_app/features/exams/exam_insights_screen.dart' show ExamAppealsScreen;
import 'package:flutter_education_app/features/exams/exam_review_screen.dart' show ExamReviewScreen;
import 'package:flutter_education_app/features/exams/paper/review/omr_review_page.dart' show OmrReviewPage;
import 'package:flutter_education_app/features/home/teacher/add_class_materials_page.dart' show openAddClassMaterials;
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart' show TeacherCourseScreenProvider;
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';

/// Opens the screen where [item] is done. Returns false when this app version knows no place for it.
Future<bool> openTodoAction(BuildContext context, TodoItem item) async {
  final a = item.action;
  int? n(String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse('${a[k] ?? ''}');
  final nav = Navigator.of(context);
  final examId = n('exam_id') ?? item.examId;
  final examTitle = '${a['exam_title'] ?? item.courseName ?? ''}';
  // Owner 2026-11-27: a class without materials opens "Add materials to the class" on that course / class.
  if (item.kind == 'materials_missing') {
    await openAddClassMaterials(context,
        courses: context.read<TeacherHomeProvider>().homeCourses, courseId: n('course_id') ?? item.courseId, sessionId: n('session_id'));
    return true;
  }
  switch (item.actionType) {
    case 'course':
      final id = n('course_id') ?? item.courseId;
      if (id == null) return false;
      final course = context.read<TeacherHomeProvider>().homeCourses.where((c) => c.id == id).firstOrNull;
      if (course == null) {
        await AppNavigator.openModule('course_profile', targetId: id);
      } else {
        await nav.push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => TeacherCourseScreenProvider(initialCourse: course),
            child: deferredTeacherSessionsScreen(),
          ),
        ));
      }
      return true;
    case 'transfers':
      await nav.push(MaterialPageRoute(builder: (_) => const TeacherTransfersScreen()));
      return true;
    case 'complaints':
      await AppNavigator.openModule('support');
      return true;
    case 'calendar':
      await AppNavigator.openModule('calendar', targetId: n('meeting_id'));
      return true;
    case 'exam_review' when examId != null:
      await nav.push(MaterialPageRoute(
          settings: const RouteSettings(name: '/exam-review'),
          builder: (_) => ExamReviewScreen(examId: examId, examTitle: examTitle)));
      return true;
    case 'exam_appeals' when examId != null:
      await nav.push(MaterialPageRoute(
          settings: const RouteSettings(name: '/exam-appeals'),
          builder: (_) => ExamAppealsScreen(examId: examId, examTitle: examTitle)));
      return true;
    case 'omr_review' when examId != null:
      await nav.push(MaterialPageRoute(settings: const RouteSettings(name: '/omr-review'), builder: (_) => OmrReviewPage(examId: examId)));
      return true;
  }
  return false;
}
