// lib/features/courses/student/details/subject_page_glue.dart
//
// What the enrolled student's subject page (SubjectSpace) needs from the course screen's providers: the path's
// steps from the sessions and their exam gates, and the pages and panels it opens (a lesson panel, the lessons
// page, one of the course's other tabs as its own page). The providers the course screen creates for its subtree
// (StudentExamProvider, TeacherCourseScreenProvider) are handed into every pushed route and sheet.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppAreaScope;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppArea;
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_lesson_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_lessons_page.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_course_exams_widget.dart' show openStudentExam;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';

/// Wraps [child] in the course screen's own providers (read from [context]), so a pushed route or a sheet keeps them.
Widget subjectProviders(BuildContext context, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentExamProvider>.value(value: context.read<StudentExamProvider>()),
        ChangeNotifierProvider<TeacherCourseScreenProvider>.value(value: context.read<TeacherCourseScreenProvider>()),
      ],
      child: child,
    );

/// Whether [s] is finished for the path (the timeline's own rule, N1).
bool subjectSessionDone(SessionModel s) => courseStudentSessionDone(
      serverDone: s.isCompleted,
      materials: s.totalMaterial,
      materialsDone: s.completeMaterial,
      when: s.scheduledAt?.toUtc(),
      minutes: s.durationMinutes,
    );

/// "بدأت قبل ٥ دقايق", from a live session's start; null when it has none or it is in the future.
String? subjectStartedAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final m = (now ?? DateTime.now()).toUtc().difference(at.toUtc()).inMinutes;
  if (m < 1) return null;
  return sbFill('sb_subj_started', {'time': sbMinutes(m)});
}

/// "الثلاثاء ١ ديسمبر، ٧:٣٠ م" (or "… ٧:٣٠ إلى ٨:٢٠ م" with [minutes]), in the viewer's time zone.
String subjectWhen(DateTime at, {int? minutes}) {
  final day = AppTime.date(at.toUtc(), pattern: 'EEEE d MMMM');
  final from = AppTime.time(at.toUtc());
  if (minutes == null || minutes <= 0) return '$day، $from';
  final to = AppTime.time(at.toUtc().add(Duration(minutes: minutes)));
  return '$day، ${sbFill('sb_subj_time_range', {'from': from, 'to': to})}';
}

/// The path: every session of the course in order, each session's gating exam right after it.
List<SubjectStep> subjectStepsOf(
  CourseDetailProvider p, {
  required String teacher,
  required void Function(SessionModel s, int number) onOpenLesson,
  required void Function(SessionModel s) onJoinLive,
  required Future<void> Function(int examId) onOpenExam,
}) {
  final next = p.nextPlayable;
  final steps = <SubjectStep>[];
  var n = 0;
  for (final s in p.sessions) {
    n++;
    final number = n;
    final unlocked = p.isSessionUnlockedById(s.id);
    final done = subjectSessionDone(s);
    final state = s.isLiveActive
        ? SubjectStepState.live
        : !unlocked
        ? SubjectStepState.locked
        : done
        ? SubjectStepState.done
        : s.id == next?.id
        ? SubjectStepState.current
        : SubjectStepState.todo;
    final minutes = s.durationMinutes;
    final String meta;
    String? chip;
    if (s.isLiveActive) {
      meta = sbFill('sb_subj_live_with', {'teacher': teacher});
    } else if (s.isLive) {
      final at = s.scheduledAt;
      final future = at != null && at.toUtc().isAfter(DateTime.now().toUtc());
      meta = future
          ? '${'sb_subj_meta_live'.tr}${(AppConfig.lang == 'ar' ? '، ' : ', ')}${AppTime.date(at.toUtc(), pattern: 'EEEE')} ${AppTime.time(at.toUtc())}'
          : minutes > 0
          ? '${'sb_subj_meta_live'.tr}${(AppConfig.lang == 'ar' ? '، ' : ', ')}${sbMinutes(minutes)}'
          : 'sb_subj_meta_live'.tr;
    } else {
      meta = minutes > 0 ? '${'sb_subj_meta_lesson'.tr}${(AppConfig.lang == 'ar' ? '، ' : ', ')}${sbMinutes(minutes)}' : 'sb_subj_meta_lesson'.tr;
    }
    steps.add(SubjectStep(
      id: 's${s.id}',
      number: number,
      title: s.name,
      meta: meta,
      kind: s.isLive ? SubjectStepKind.live : SubjectStepKind.lesson,
      state: state,
      chip: chip,
      onTap: () => s.isLiveActive ? onJoinLive(s) : onOpenLesson(s, number),
      onJoin: s.isLiveActive ? () => onJoinLive(s) : null,
    ));
    final gate = p.examGates[s.id];
    if (gate == null || gate.isEmpty) continue;
    final e = gate.firstPending ?? gate.exams.first;
    n++;
    final end = e.endDate;
    steps.add(SubjectStep(
      id: 'e${e.id}',
      number: n,
      title: e.name,
      meta: e.questionCount > 0 ? '${'sb_subj_meta_exam'.tr}${(AppConfig.lang == 'ar' ? '، ' : ', ')}${sbQuestions(e.questionCount)}' : 'sb_subj_meta_exam'.tr,
      kind: SubjectStepKind.exam,
      state: !unlocked ? SubjectStepState.locked : (e.passed ? SubjectStepState.done : SubjectStepState.todo),
      chip: !e.passed && end != null && end.toUtc().isAfter(DateTime.now().toUtc())
          ? AppTime.date(end.toUtc(), pattern: 'EEEE')
          : null,
      onTap: unlocked && e.canStart ? () => onOpenExam(e.id) : null,
    ));
  }
  return steps;
}

/// Opens [examId] the way the sessions timeline does (passcode first when protected); falls back to [onExamsPage]
/// when the exam is not in the course's list (an engine exam, a closed one).
Future<void> openSubjectExam(BuildContext context, CourseDetailProvider p, int examId, {VoidCallback? onExamsPage}) async {
  final prov = context.read<StudentExamProvider>();
  final cid = p.course.id.toString();
  if (!prov.courseExamsLoadedFor(cid)) await prov.loadCourseExams(cid);
  if (!context.mounted) return;
  final exam = prov.courseExamsFor(cid).where((e) => e.id == examId).firstOrNull;
  if (exam == null) {
    onExamsPage?.call();
    return;
  }
  final sessionId = exam.sessionId;
  await openStudentExam(context, prov, exam, () => sessionId == null ? p.refresh() : p.onSessionExamPassed(sessionId));
}

/// The lesson panel of [s] ("الدرس ٢: …").
Future<void> openSubjectLessonPanel(
  BuildContext context,
  CourseDetailProvider p,
  SessionModel s, {
  required int number,
  Future<void> Function(int examId)? onOpenExam,
  VoidCallback? onNext,
}) {
  if (!p.isSessionUnlockedById(s.id)) {
    showAppNotice('sb_subj_locked'.tr);
    return Future.value();
  }
  return showSubjectPanel<void>(
    context,
    title: sbFill('sb_lesson_title', {'n': sbDigits(number), 'name': s.name}),
    wide: true,
    child: (_) => subjectProviders(
      context,
      AppAreaScope(
        area: AppArea.learn,
        child: SubjectLessonPanel(
          session: s.toTeacher,
          gate: p.examGates[s.id],
          onOpenExam: onOpenExam,
          onNext: onNext,
        ),
      ),
    ),
  );
}

/// "دروس المادة": the path on its own page, rebuilt from the provider as sessions page in.
Future<void> pushSubjectLessonsPage(
  BuildContext context, {
  required String teacher,
  String? kicker,
  required List<SubjectStep> Function(BuildContext context) steps,
  required int Function() done,
  required int Function() total,
}) {
  final p = context.read<CourseDetailProvider>();
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => subjectProviders(
      context,
      ChangeNotifierProvider<CourseDetailProvider>.value(
        value: p,
        child: Consumer<CourseDetailProvider>(
          builder: (ctx, prov, _) => SubjectLessonsPage(
            steps: steps(ctx),
            teacher: teacher,
            kicker: kicker,
            done: done(),
            total: total(),
            loading: prov.isLoading,
            loadingMore: prov.isLoadingMoreSessions,
            onNearEnd: prov.hasMoreSessions ? prov.loadMoreSessions : null,
            onBack: () => Navigator.of(ctx).maybePop(),
            onRefresh: prov.refresh,
          ),
        ),
      ),
    ),
  ));
}

/// One of the course's other tabs (exams, announcements, progress, the archive, the path, about …) as its own page.
Future<void> pushSubjectTabPage(BuildContext context, CourseSpaceTab tab) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => subjectProviders(context, _SubjectTabPage(tab: tab)),
    ));

class _SubjectTabPage extends StatelessWidget {
  const _SubjectTabPage({required this.tab});

  final CourseSpaceTab tab;

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: AppArea.learn,
        child: Scaffold(
          backgroundColor: context.colors.background,
          appBar: AppHeader(title: tab.label),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(child: Builder(builder: tab.builder)),
          ),
        ),
      );
}
