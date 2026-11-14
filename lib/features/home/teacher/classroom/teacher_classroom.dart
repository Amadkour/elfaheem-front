// lib/features/home/teacher/classroom/teacher_classroom.dart — the teacher's people and their work (D-290, phase 7): three
// configurations of the shared list (entity_list_page.dart), nothing of their own.
//
//   My students    GET /entities/teachers/{me}/students      de-duplicated over my courses, who needs attention first
//   Submissions    GET /entities/teachers/{me}/submissions   every exam, engine result and assignment in my courses
//   Reviews        GET /entities/teachers/{me}/reviews       what students said about my courses
//
// A row opens the student's panel: their progress and history in THIS teacher's courses only (the server scopes it),
// with Message. The tabs live beside the course list ([TeacherCoursesScreen]). The app has no Q&A: reviews are the
// students' voice here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart';
import 'package:flutter_education_app/design/master_detail/entity_exports.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_tools.dart';

/// The sub-list of [section] of teacher [teacherId], narrowed to the rows of type [T].
Future<EntityPage<T>> _rows<T extends EntityItem>(int teacherId, String section, EntityListQuery q) async {
  final p = await EntitiesApi.instance.page(EntityRef(EntityKind.teacher, teacherId), section, query: q);
  return EntityPage<T>(items: p.items.whereType<T>().toList(), total: p.total, page: p.page, size: p.size, pages: p.pages);
}

/// An avatar and a name, for a table cell.
Widget _personCell(BuildContext context, EntityRef? person, {String? sub}) {
  final name = person?.name ?? '—';
  return Row(children: [
    if (person != null) AppAvatar(name: name, url: person.imageUrl, size: 32),
    AppSpace.gapXs,
    Flexible(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
        if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      ]),
    ),
  ]);
}

// ── My students ──────────────────────────────────────────────────────────────

EntityListConfig<PersonRow> teacherStudentsList(int teacherId) => EntityListConfig<PersonRow>(
      id: 'teacher_students',
      title: 'md_p7_my_students'.tr,
      rowKind: EntityKind.student,
      load: (q) => _rows<PersonRow>(teacherId, 'students', q),
      idOf: (r) => r.person.id,
      refOf: (r) => r.person,
      searchHint: 'md_p7_search_students'.tr,
      sorts: const ['activity_desc', 'progress_desc', 'name'],
      filter: EntityListFilter('attention', 'md_p7_status'.tr, [('true', 'md_p7_needs_attention'.tr)]),
      empty: EntityListEmpty(Icons.groups_outlined, 'md_p7_empty_students'.tr, message: 'md_p7_empty_students_hint'.tr),
      columns: [
        AppTableColumn(
          key: 'student',
          label: 'md_kind_student'.tr,
          primary: true,
          flex: 3,
          cell: (context, r) => _personCell(context, r.person, sub: r.username == null ? null : '@${r.username}'),
        ),
        AppTableColumn.text(key: 'courses', label: 'md_stat_courses'.tr, text: (r) => '${r.courses}', numeric: true),
        AppTableColumn(
          key: 'progress',
          label: 'md_stat_avg_progress'.tr,
          flex: 2,
          cell: (context, r) => EntityProgress(r.avgProgress),
        ),
        AppTableColumn.text(
          key: 'activity',
          label: 'md_stat_last_activity'.tr,
          flex: 2,
          text: (r) => r.lastActivityAt == null ? 'md_no_activity'.tr : mdAgo(r.lastActivityAt),
        ),
        AppTableColumn(
          key: 'attention',
          label: 'md_p7_status'.tr,
          flex: 2,
          cell: (context, r) => r.attention
              ? AppStatusBadge(label: 'md_p7_needs_attention'.tr, tone: AppTone.warning, dense: true)
              : AppStatusBadge(label: 'md_p7_on_track'.tr, tone: AppTone.success, dense: true),
        ),
      ],
      card: (context, r) => entityRowFor(context, r, link: false),
      export: entityPersonExport(),
      bulk: [entityMessageBulk<PersonRow>((r) => r.person)],
    );

// ── Submissions ──────────────────────────────────────────────────────────────

EntityListConfig<GradeRow> teacherSubmissionsList(int teacherId) => EntityListConfig<GradeRow>(
      id: 'teacher_submissions',
      title: 'md_p7_sec_submissions'.tr,
      rowKind: EntityKind.student,
      load: (q) => _rows<GradeRow>(teacherId, 'submissions', q),
      idOf: (r) => '${r.source}:${r.id}',
      refOf: (r) => r.student,
      searchHint: 'md_p7_search_submissions'.tr,
      sorts: const ['newest', 'oldest', 'score_desc', 'score_asc'],
      filter: EntityListFilter('state', 'md_p7_status'.tr, [
        for (final s in gradeStates) (s, 'md_p7_grade_$s'.tr),
      ]),
      empty: EntityListEmpty(Icons.assignment_turned_in_outlined, 'md_p7_empty_submissions'.tr),
      columns: [
        AppTableColumn(
          key: 'title',
          label: 'md_p7_assessment'.tr,
          primary: true,
          flex: 3,
          cell: (context, r) => Row(children: [
            entityToneIcon(context, gradeIcon(r.source), r.passed == false ? AppTone.warning : AppTone.info),
            AppSpace.gapXs,
            Flexible(
              child: Text(r.title.isEmpty ? 'md_p7_grade_untitled'.tr : r.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            ),
          ]),
        ),
        AppTableColumn(
          key: 'student',
          label: 'md_kind_student'.tr,
          flex: 2,
          cell: (context, r) => _personCell(context, r.student),
        ),
        AppTableColumn(
          key: 'course',
          label: 'md_kind_course'.tr,
          flex: 2,
          cell: (context, r) => r.course == null ? const SizedBox.shrink() : EntityChip(r.course!.ref),
        ),
        AppTableColumn(key: 'score', label: 'md_p7_score'.tr, cell: (context, r) => gradeBadge(r)),
        AppTableColumn.text(key: 'at', label: 'md_p7_date'.tr, text: (r) => mdDate(r.at)),
      ],
      card: (context, r) => gradeRowFor(context, r, ownerKind: EntityKind.teacher, link: false),
      export: entityGradeExport(),
      bulk: [entityMessageBulk<GradeRow>((r) => r.student)],
    );

// ── Reviews ──────────────────────────────────────────────────────────────────

EntityListConfig<ReviewRow> teacherReviewsList(int teacherId) => EntityListConfig<ReviewRow>(
      id: 'teacher_reviews',
      title: 'md_p7_sec_reviews'.tr,
      rowKind: EntityKind.student,
      load: (q) => _rows<ReviewRow>(teacherId, 'reviews', q),
      idOf: (r) => r.id,
      refOf: (r) => r.student,
      searchHint: 'md_p7_search_reviews'.tr,
      sorts: const ['newest', 'lowest', 'highest'],
      filter: EntityListFilter('stars', 'md_p7_rating'.tr, [
        for (var i = 5; i >= 1; i--) ('$i', '$i ★'),
      ]),
      empty: EntityListEmpty(Icons.reviews_outlined, 'md_p7_empty_reviews'.tr),
      columns: [
        AppTableColumn(
          key: 'student',
          label: 'md_kind_student'.tr,
          primary: true,
          flex: 2,
          cell: (context, r) => _personCell(context, r.student),
        ),
        AppTableColumn(key: 'stars', label: 'md_p7_rating'.tr, cell: (context, r) => EntityStars(r.value)),
        AppTableColumn(
          key: 'course',
          label: 'md_kind_course'.tr,
          flex: 2,
          cell: (context, r) => r.course == null ? const SizedBox.shrink() : EntityChip(r.course!.ref),
        ),
        AppTableColumn.text(key: 'review', label: 'md_p7_review'.tr, flex: 3, text: (r) => r.review ?? '—'),
        AppTableColumn.text(key: 'at', label: 'md_p7_date'.tr, text: (r) => mdDate(r.at)),
      ],
      card: (context, r) => reviewRowFor(context, r, ownerKind: EntityKind.teacher, link: false),
      export: entityReviewExport(),
    );

// ── The tabs ─────────────────────────────────────────────────────────────────

/// What the teacher's "My courses" tab shows.
enum TeacherSpace {
  courses('my_courses', Icons.auto_stories_rounded),
  students('md_p7_my_students', Icons.groups_rounded),
  submissions('md_p7_sec_submissions', Icons.assignment_turned_in_outlined),
  reviews('md_p7_sec_reviews', Icons.reviews_outlined);

  const TeacherSpace(this.labelKey, this.icon);

  final String labelKey;
  final IconData icon;

  static TeacherSpace? tryParse(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// The strip above the page: Courses · My students · Submissions · Reviews.
class TeacherSpaceTabs extends StatelessWidget {
  const TeacherSpaceTabs({super.key, required this.selected, required this.onSelect});

  final TeacherSpace selected;
  final ValueChanged<TeacherSpace> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxs),
        child: AppUnderlineTabs(
          items: [for (final s in TeacherSpace.values) AppTabItem(s.labelKey.tr, icon: s.icon)],
          index: selected.index,
          onChanged: (i) => onSelect(TeacherSpace.values[i]),
        ),
      );
}

/// The list of [space] (courses are the screen's own).
class TeacherSpaceList extends StatelessWidget {
  const TeacherSpaceList({super.key, required this.space, required this.teacherId});

  final TeacherSpace space;
  final int teacherId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget list = switch (space) {
      TeacherSpace.students => EntityListPage<PersonRow>(
          key: const ValueKey('teacher.students'), config: teacherStudentsList(teacherId)),
      TeacherSpace.submissions => EntityListPage<GradeRow>(
          key: const ValueKey('teacher.submissions'), config: teacherSubmissionsList(teacherId)),
      TeacherSpace.reviews =>
        EntityListPage<ReviewRow>(key: const ValueKey('teacher.reviews'), config: teacherReviewsList(teacherId)),
      TeacherSpace.courses => const SizedBox.shrink(),
    };
    return ColoredBox(color: c.background, child: list);
  }
}
