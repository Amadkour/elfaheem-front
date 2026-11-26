// The subject page's demo data (CAST.md): Faisal's maths with أ. ماجد الشهري, الصف الثاني الثانوي, the live
// class "الدوال الأسية" 7:30 – 8:20 pm, and a lesson's materials over FakeApi.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent;
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';

import '../fake_api.dart';

String sbT(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The path: lesson 1 done, the live class now (or lesson 1 current when [live] is false), a quiz, more ahead.
List<SubjectStep> demoSubjectSteps({bool live = true, int extra = 0}) {
  final steps = <(String, String, String, String, SubjectStepKind)>[
    ('الدوال: المجال والمدى', 'Functions: domain and range', 'درس، ٢٣ دقيقة مع ملخص', 'Lesson, 23 minutes with a summary', SubjectStepKind.lesson),
    ('الدوال الأسية', 'Exponential functions', 'حصة مباشرة، ٥٠ دقيقة', 'Live class, 50 minutes', SubjectStepKind.live),
    ('اختبار قصير', 'Short quiz', 'اختبار، ١٠ أسئلة', 'Quiz, 10 questions', SubjectStepKind.exam),
    ('اللوغاريتمات', 'Logarithms', 'حصة مباشرة، ٥٠ دقيقة', 'Live class, 50 minutes', SubjectStepKind.live),
    ('مراجعة الوحدة', 'Unit review', 'درس، فيديو وملخص', 'Lesson, video and summary', SubjectStepKind.lesson),
    ('اختبار الوحدة', 'Unit test', 'اختبار، ٢٠ سؤال', 'Quiz, 20 questions', SubjectStepKind.exam),
    for (var i = 0; i < extra; i++)
      ('خصائص اللوغاريتمات ${i + 1}', 'Log properties ${i + 1}', 'درس، ٣٢ دقيقة', 'Lesson, 32 minutes', SubjectStepKind.lesson),
  ];
  return [
    for (final (i, s) in steps.indexed)
      SubjectStep(
        id: 'd$i',
        number: i + 1,
        title: sbT(s.$1, s.$2),
        meta: live && i == 1 ? sbT('حصة مباشرة الحين مع أ. ماجد', 'Live now with Mr Majed') : sbT(s.$3, s.$4),
        kind: s.$5,
        state: live
            ? (i == 0 ? SubjectStepState.done : i == 1 ? SubjectStepState.live : i > 3 ? SubjectStepState.locked : SubjectStepState.todo)
            : (i == 0 ? SubjectStepState.current : i > 3 ? SubjectStepState.locked : SubjectStepState.todo),
        chip: s.$5 == SubjectStepKind.exam && i == 5 ? sbT('الخميس', 'Thursday') : null,
        onTap: () {},
        onJoin: live && i == 1 ? () {} : null,
      ),
  ];
}

/// The subject page with the live class on (or the next class on Tuesday).
Widget demoSubjectSpace({bool live = true}) => SubjectSpace(
      title: sbT('الرياضيات', 'Mathematics'),
      subject: 'math',
      grade: sbT('الصف الثاني الثانوي', 'Grade 11'),
      teacher: sbT('أ. ماجد الشهري', 'Mr Majed Alshehri'),
      teacherYears: 9,
      teacherBio: sbT(
        'يدرّس الرياضيات بأسلوب بسيط، ويحب يربط الدرس بأمثلة من حياة الطالب. يرد على أسئلتك بعد كل حصة.',
        'Teaches maths simply and links each lesson to examples from your life. Answers your questions after every class.',
      ),
      mode: sbT('مجموعة، عن بعد', 'Group, remote'),
      lessonsCount: 24,
      rating: '4.8',
      facts: [
        SubjectFact(icon: Icons.menu_book_outlined, value: '24', label: sbT('درس', 'lessons'), accent: AppAccent.pink),
        SubjectFact(icon: Icons.schedule_rounded, value: '50', label: sbT('دقيقة لكل حصة', 'minutes a class'), accent: AppAccent.grape),
        SubjectFact(icon: Icons.hourglass_bottom_rounded, value: '20', label: sbT('ساعة', 'hours'), accent: AppAccent.mint),
        SubjectFact(icon: Icons.star_rounded, value: '4.8', label: sbT('تقييم الطلاب', 'student rating')),
      ],
      scheduleNote: sbT('كل أحد وثلاثاء، ٧:٣٠ م', 'Every Sunday and Tuesday, 7:30 pm'),
      live: live
          ? SubjectLive(title: sbT('الدوال الأسية', 'Exponential functions'), startedAgo: sbT('بدأت قبل ٥ دقايق', 'Started 5 minutes ago'), onJoin: () {})
          : null,
      next: live
          ? null
          : SubjectNext(
              when: sbT('الثلاثاء ١ ديسمبر، ٧:٣٠ إلى ٨:٢٠ م', 'Tuesday 1 December, 7:30 to 8:20 pm'),
              until: DateTime.now().toUtc().add(const Duration(days: 2, hours: 3, minutes: 45)),
            ),
      steps: demoSubjectSteps(live: live, extra: 4),
      done: live ? 1 : 0,
      total: 24,
      onAllLessons: () {},
      onChat: () {},
      onBot: () {},
      onNotes: () {},
      onSchedule: () {},
      onExams: () {},
      examsNote: sbT('٢ قريب', '2 soon'),
      onAttendance: () {},
      attendanceNote: live ? sbT('حاضر الحين', 'Present now') : sbT('أول حصة الثلاثاء', 'First class Tuesday'),
      more: [
        CourseSpaceAction(icon: Icons.campaign_outlined, label: sbT('الإعلانات', 'Announcements'), badge: '2', onTap: () {}),
        CourseSpaceAction(icon: Icons.insights_rounded, label: sbT('تقدّمي', 'My progress'), onTap: () {}),
        CourseSpaceAction(icon: Icons.info_outline_rounded, label: sbT('عن الدورة', 'About'), onTap: () {}),
      ],
      menu: [CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: sbT('شارك', 'Share'), onTap: () {})],
      onBack: () {},
    );

/// Session 7 of course 41: "الدوال" with three chapter videos, a PDF and two summary pictures.
SessionModel demoLessonSession() => SessionModel(
      id: 7,
      courseId: 41,
      name: sbT('الدوال', 'Functions'),
      type: 'recorded',
      durationMinutes: 23,
      order: 1,
      createdAt: DateTime.utc(2026, 11, 1),
      isLiveActive: false,
      totalMaterial: 6,
      completeMaterial: 2,
      progress: 30,
    );

TeacherCourse demoTeacherCourse() => TeacherCourse.fromJson({
      'id': 41,
      'image_url': '',
      'name_ar': 'الرياضيات',
      'name_en': 'Mathematics',
      'sessions_count': 24,
      'total_hours': 20.0,
      'expected_hours': 20.0,
      'price': 199,
      'type': 'live',
      'is_published': true,
    });

Map<String, dynamic> _mat(int id, String type, String ar, String en, {int? seconds}) => {
      'id': id,
      'session_id': 7,
      'name': sbT(ar, en),
      'type': type,
      'order': id,
      'created_at': '2026-11-01T10:00:00',
      'completed': id < 3,
      'url': 'https://example.invalid/m$id',
      'url_low': 'https://example.invalid/m$id',
      if (seconds != null) 'duration_seconds': seconds,
    };

/// `GET /api/v1/sessions/7/materials`.
Map<String, FakeHandler> lessonMaterialRoutes() => {
      'GET /api/v1/sessions/7/materials': (_) => [
            _mat(1, 'video', 'وش هي الدالة؟', 'What is a function?', seconds: 480),
            _mat(2, 'video', 'المجال والمدى', 'Domain and range', seconds: 480),
            _mat(3, 'video', 'أمثلة محلولة', 'Worked examples', seconds: 420),
            _mat(4, 'pdf', 'كتاب الدرس: الدوال', 'Lesson book: functions'),
            _mat(5, 'image', 'سبورة الدرس: تعريف الدالة', 'Board: what a function is'),
            _mat(6, 'image', 'ملخص المجال والمدى', 'Summary: domain and range'),
          ],
    };
