// Grade papers (D-660): the Exam Hub's way to grade a pile of papers without opening an exam first. One sheet: the
// course (a run belongs to a course: its students, its results), then how the papers were answered:
//
//   Bubble sheets    the bubble run (`deferredBubbleHome`), kill switches `exam.bubble` + `exam.auto_correct`
//   Written papers   the essay run (`openEssayRun`, D-662), kill switch `exam.essay_run`
//
// What is offered is decided in `hub_logic.dart` (`hubGradeKinds`, `hubGradePlaces`); `GradePapersBody` is plain values
// (the layout harness pumps it).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredBubbleHome;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../exam_all.dart' show NewExamPlace;
import '../../paper/exam_setup_wizard.dart' show SetupChoiceTile;
import '../create/exam_create_parts.dart' show CreateWhereBody;
import '../hub_logic.dart';
import 'essay_run_entry.dart';

/// Opens the chooser, then the run picked. [initialCourseId]: the course the hub is filtered to, preselected.
Future<void> openGradePapers(BuildContext context, {required List<NewExamPlace> courses, Map<int, String> orgNames = const {}, int? initialCourseId}) async {
  final kinds = hubGradeKinds();
  if (kinds.isEmpty) return;
  final pick = await showAppSheet<(NewExamPlace, GradeKind)>(
      context,
      (ctx) => AppSheetContent(title: t('تصحيح أوراق', 'Grade papers'), children: [
            GradePapersBody(
              courses: courses,
              orgNames: orgNames,
              kinds: kinds,
              initial: courses.where((p) => p.courseId == initialCourseId).firstOrNull ?? (courses.length == 1 ? courses.first : null),
              onPick: (p, k) => Navigator.pop(ctx, (p, k)),
            ),
          ]));
  if (pick == null || !context.mounted) return;
  final (place, kind) = pick;
  final id = place.courseId!;
  switch (kind) {
    case GradeKind.bubble:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => deferredBubbleHome(courseId: id, courseTitle: place.name, orgId: place.orgId)));
    case GradeKind.essay:
      await openEssayRun(context, courseId: id, courseTitle: place.name, orgId: place.orgId);
  }
}

IconData gradeKindIcon(GradeKind k) => switch (k) {
      GradeKind.bubble => Icons.grid_on_rounded,
      GradeKind.essay => Icons.history_edu_rounded,
    };

/// The course first (one tap, then it folds to a line with Change), then the kind of papers.
class GradePapersBody extends StatefulWidget {
  const GradePapersBody({super.key, required this.courses, required this.kinds, required this.onPick, this.orgNames = const {}, this.initial});
  final List<NewExamPlace> courses;
  final List<GradeKind> kinds;
  final Map<int, String> orgNames;
  final NewExamPlace? initial;
  final void Function(NewExamPlace, GradeKind) onPick;

  @override
  State<GradePapersBody> createState() => _GradePapersBodyState();
}

class _GradePapersBodyState extends State<GradePapersBody> {
  late NewExamPlace? _course = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.courses.isEmpty) {
      return AppEmpty(
        icon: Icons.menu_book_outlined,
        title: t('لا مقررات بعد', 'No courses yet'),
        message: t('التصحيح يكون داخل مقرر: طلابه ونتائجه. أنشئ مقررًا أو اطلب أن تُضاف إلى واحد.',
            'Grading happens inside a course: its students and its results. Create a course or ask to be added to one.'),
      );
    }
    final course = _course;
    if (course == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('أي مقرر؟', 'Which course?'), style: AppType.section(context)),
        AppSpace.gapSm,
        CreateWhereBody(places: widget.courses, selected: null, orgNames: widget.orgNames, onPick: (p) => setState(() => _course = p)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SetupChoiceTile(
        key: const ValueKey('grade.course'),
        icon: Icons.menu_book_rounded,
        title: course.name,
        subtitle: course.orgId == null ? null : widget.orgNames[course.orgId],
        selected: true,
        onTap: null,
        trailing: widget.courses.length > 1
            ? AppButton.ghost(key: const ValueKey('grade.change'), size: AppButtonSize.sm, label: t('تغيير', 'Change'), onPressed: () => setState(() => _course = null))
            : null,
      ),
      AppSpace.gapLg,
      Text(t('ماذا تصحّح؟', 'What are you grading?'), style: AppType.section(context)),
      AppSpace.gapSm,
      for (var i = 0; i < widget.kinds.length; i++) ...[
        if (i > 0) AppSpace.gapSm,
        SetupChoiceTile(
          key: ValueKey('grade.kind.${widget.kinds[i].name}'),
          icon: gradeKindIcon(widget.kinds[i]),
          title: gradeKindLabel(widget.kinds[i]),
          subtitle: gradeKindHint(widget.kinds[i]),
          selected: false,
          trailing: Icon(Icons.chevron_right_rounded, color: c.textMedium),
          onTap: () => widget.onPick(course, widget.kinds[i]),
        ),
      ],
    ]);
  }
}
