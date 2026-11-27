// lib/features/courses/teacher/courses_parts.dart — the plain-values parts of the teacher's "My courses" page (redesign
// T1, Tea1Courses): the toolbar card that rides up over the hero (search + Published / Drafts) and the delete
// (trash) sheet. They read no provider, so the layout harness pumps them as they are.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';

/// The card under the hero: [scope] (the app-mode banner), the search box and the filter, on one paper card.
class TeacherCoursesToolbarCard extends StatelessWidget {
  const TeacherCoursesToolbarCard({super.key, this.scope, this.search, this.filter});

  final Widget? scope;
  final Widget? search;
  final Widget? filter;

  bool get isEmpty => scope == null && search == null && filter == null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.cardFor(MediaQuery.sizeOf(context).width)),
        border: Border.all(color: c.kit.line, width: AppBorder.hairline),
        boxShadow: AppShadow.card(context),
      ),
      child: LayoutBuilder(builder: (context, box) {
        // wide: search and filter side by side, as the reference's web layout
        final wide = box.maxWidth >= 700;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (scope != null) ...[scope!, const SizedBox(height: AppSpace.xs)],
          if (wide && search != null && filter != null)
            Row(children: [
              Expanded(child: search!),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: filter!),
            ])
          else ...[
            ?search,
            if (search != null && filter != null) const SizedBox(height: AppSpace.xs),
            ?filter,
          ],
        ]);
      }),
    );
  }
}

/// The trash question for a course: a red mark, the title, what happens, one line about who is enrolled, and
/// Cancel / Move to trash. Pops `true` on confirm.
class TeacherDeleteCourseSheet extends StatelessWidget {
  const TeacherDeleteCourseSheet({super.key, required this.title, required this.students, this.onCancel, this.onConfirm});

  final String title;

  /// Enrolled students: the line under the note names them.
  final int students;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warn = students > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AppIconBox(icon: Icons.delete_outline_rounded, tone: c.kit.error, size: AppDashSize.glyph + AppSpace.sm)),
        const SizedBox(height: AppSpace.md),
        Text('t1_cs_del_title'.tr.replaceAll('{name}', title),
            textAlign: TextAlign.center, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        Text('t1_cs_del_note'.tr, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.sm),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: warn ? c.kit.warn.tint : c.kit.ok.tint,
            borderRadius: BorderRadius.circular(AppRadius.tile),
          ),
          child: Row(children: [
            Icon(warn ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                size: AppIconSize.md, color: warn ? c.kit.warn.color : c.kit.ok.color),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                warn
                    ? countText(students,
                        ar1: 'فيها طالب مسجّل واحد.',
                        ar2: 'فيها طالبان مسجّلان.',
                        arFew: 'فيها {n} طلاب مسجّلين.',
                        arMany: 'فيها {n} طالبًا مسجّلًا.',
                        en1: '1 student is enrolled.',
                        en: '{n} students are enrolled.')
                    : 't1_cs_del_none'.tr,
                style: AppType.label(context).copyWith(color: c.textDark),
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        Row(children: [
          Expanded(
            child: AppButton.secondary(
              key: const ValueKey('t1_cs.del.cancel'),
              label: 'cancel'.tr,
              expand: true,
              onPressed: onCancel ?? () => Navigator.of(context).pop(false),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: AppButton.danger(
              key: const ValueKey('t1_cs.del.confirm'),
              label: 'course_move_to_trash'.tr,
              expand: true,
              onPressed: onConfirm ?? () => Navigator.of(context).pop(true),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Opens [TeacherDeleteCourseSheet]; true when the teacher confirmed.
Future<bool> showTeacherDeleteCourseSheet(BuildContext context, {required String title, required int students}) async {
  final r = await showAppSheet<bool>(context, (_) => TeacherDeleteCourseSheet(title: title, students: students));
  return r ?? false;
}
