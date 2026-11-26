// lib/features/sessions/material/lesson_material_page.dart
//
// The student's lesson page (Stu1Learn material, exam=retry): the learn-area hero ("الدرس ٨", the lesson's name,
// what is inside it), then the lesson content — the video card, the files grid and the lesson quiz
// (SessionMaterialGrid's student view) — and, beside it on a wide window (under it on a phone), "after this lesson":
// the next lesson and whether it is open. The lesson's own rating sits at the foot of the content.
//
// Opened from the course timeline (SessionMaterialCard, a student's tap or "Continue"). Every tap keeps its old
// behaviour: the player, the image viewer, the external file, completion, the exam gate.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/courses/student/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/courses/student/details/session_exam_gate.dart' show SessionExamGate;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/sessions/material/components/session_material_grid.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';

/// Pushes the lesson page for [session], carrying the course page's providers along.
Future<void> openLessonMaterialPage(
  BuildContext context, {
  required TeacherSessionItem session,
  required int number,
  VoidCallback? onOpenExam,
}) {
  final sessions = context.read<TeacherCourseScreenProvider>();
  StudentExamProvider? exams;
  try {
    exams = context.read<StudentExamProvider>();
  } catch (_) {}
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) {
      Widget page = ChangeNotifierProvider.value(
        value: sessions,
        child: LessonMaterialPage(session: session, number: number, onOpenExam: onOpenExam),
      );
      if (exams != null) page = ChangeNotifierProvider.value(value: exams, child: page);
      return page;
    },
  ));
}

/// "فيديو، ملخص، واختبار قصير" from what the lesson holds.
String lessonContentLine(List<SessionMaterialModel> materials, {required bool exam}) {
  final parts = <String>[
    if (materials.any((m) => m.type == SessionMaterialType.video || m.type == SessionMaterialType.recorded))
      'sb_learn_has_video'.tr,
    if (materials.any((m) => m.type == SessionMaterialType.pdf || m.type == SessionMaterialType.document))
      'sb_learn_has_summary'.tr,
    if (materials.any((m) => m.type == SessionMaterialType.image)) 'sb_learn_has_images'.tr,
    if (exam) 'sb_learn_has_quiz'.tr,
  ];
  if (parts.length < 2) return parts.join();
  final ar = AppConfig.lang == 'ar';
  return '${parts.sublist(0, parts.length - 1).join(ar ? '، ' : ', ')}${ar ? '، و' : ' and '}${parts.last}';
}

class LessonMaterialPage extends StatefulWidget {
  const LessonMaterialPage({super.key, required this.session, required this.number, this.onOpenExam});

  final TeacherSessionItem session;
  final int number;
  final VoidCallback? onOpenExam;

  @override
  State<LessonMaterialPage> createState() => _LessonMaterialPageState();
}

class _LessonMaterialPageState extends State<LessonMaterialPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TeacherCourseScreenProvider>().fetchMaterials(widget.session);
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherCourseScreenProvider>();
    final s = widget.session;
    final materials = prov.materialsFor(s.id);
    CourseDetailProvider? cd;
    try {
      cd = context.watch<CourseDetailProvider>();
    } catch (_) {}
    final SessionExamGate? gate = cd?.examGates[s.id];
    final hasExam = gate != null && !gate.isEmpty;
    final next = _next(cd);
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= Breakpoints.desktop;
    final g = AppSpace.gutter(w);
    final title = 'sb_learn_lesson_n'.tr.replaceAll('{n}', appDigits('${widget.number}'));

    final content = SessionMaterialGrid(
      session: s,
      materials: materials,
      columns: 2,
      isTeacher: false,
      isLoading: prov.isLoading && !(prov.materialLoaded[s.id] ?? false),
      examGate: gate,
      onOpenExam: widget.onOpenExam,
    );
    final rating = s.rateSummary == null && s.completeMaterial == 0
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: RateLater(type: RateType.session, sourceId: '${s.id}', rateSummary: s.rateSummary, labelKey: 'session_rate_it'),
          );
    final side = next == null
        ? null
        : LessonNextCard(
            number: next.$2,
            title: next.$1.name,
            open: cd?.isSessionUnlockedById(next.$1.id) ?? false,
          );
    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [content, ?rating]);

    return BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      enableFooterWidget: false,
      appBar: ScreenAppBar(title: title),
      child: AppAreaScope(
        area: AppArea.learn,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpace.xxl),
          children: [
            AppHeroOverlap(
              hero: AppHero(
                kicker: title,
                title: s.name,
                subtitle: lessonContentLine(materials, exam: hasExam),
                icon: Icons.play_lesson_outlined,
                wipe: false,
              ),
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: g),
                child: wide && side != null
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: main),
                        AppSpace.gapMd,
                        SizedBox(width: AppDashSize.courseTile + AppSpace.xxxl + AppSpace.xxl + AppSpace.xs, child: side),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        main,
                        if (side != null) ...[AppSpace.gapMd, side],
                      ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The lesson after this one and its number in the course, or null.
  (SessionModel, int)? _next(CourseDetailProvider? cd) {
    if (cd == null) return null;
    final i = cd.sessions.indexWhere((x) => x.id == widget.session.id);
    if (i < 0 || i + 1 >= cd.sessions.length) return null;
    return (cd.sessions[i + 1], widget.number + 1);
  }
}

/// "بعد هالدرس": the next lesson, locked (dashed) until this one is done.
class LessonNextCard extends StatelessWidget {
  const LessonNextCard({super.key, required this.number, required this.title, required this.open});

  final int number;
  final String title;
  final bool open;

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'sb_learn_after'.tr,
        child: AppTile(
          icon: open ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
          title: '${appDigits('$number')}. $title',
          subtitle: open ? 'sb_learn_next_open'.tr : 'sb_learn_next_locked'.tr,
          locked: !open,
          dense: true,
        ),
      );
}
