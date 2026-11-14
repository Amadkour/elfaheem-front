// lib/features/parent/parent_child_marks.dart
// "Marks from the teachers" inside a parent's report — the child's analytics profile, i.e. EXACTLY what the child
// sees in the student app: per course, the child next to the class average (progress, attendance, exams) and every
// mark the teacher published from the Data Lab. Built with the shared analytics design system.
library;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import 'package:flutter_education_app/features/analytics/analytics_ui.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'parent_report_widgets.dart';
import 'parent_widgets.dart';

class ParentChildMarksSection extends StatelessWidget {
  const ParentChildMarksSection({super.key, required this.profile, this.courseId});

  final DlProfile profile;

  /// Only one course (null = every course with something to show).
  final int? courseId;

  static double? _avg(DlCourseBlock b, String key) {
    for (final c in b.columns) {
      if (c.key == key) return c.classAvg;
    }
    return null;
  }

  static bool _hasContent(DlCourseBlock b) =>
      b.extraColumns.isNotEmpty || ['progress', 'attendance', 'exam_avg'].any((k) => _avg(b, k) != null);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = profile.courses.where((b) => (courseId == null || b.courseId == courseId) && _hasContent(b)).toList();
    if (blocks.isEmpty) return const SizedBox.shrink();
    return PlSection(
      icon: Icons.workspace_premium_rounded,
      title: anTr('pl_sec_marks', 'Marks from the teachers'),
      hint: anTr('pl_sec_marks_hint', 'What the teachers shared, next to the class average — the same view your child has.'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) Divider(color: c.divider, height: 28),
          _CourseMarks(block: blocks[i], showTitle: blocks.length > 1 || courseId == null),
        ],
      ]),
    );
  }
}

class _CourseMarks extends StatelessWidget {
  const _CourseMarks({required this.block, required this.showTitle});

  final DlCourseBlock block;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = block;
    final rows = <(String, double?, double?)>[
      ('dl_progress'.tr, b.progress, ParentChildMarksSection._avg(b, 'progress')),
      ('dl_attendance'.tr, b.attendance, ParentChildMarksSection._avg(b, 'attendance')),
      ('dl_exams'.tr, b.examAvg, ParentChildMarksSection._avg(b, 'exam_avg')),
    ];
    final marks = b.extraColumns;
    final attention = _needsAttention(b.attendance, b.examAvg);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTitle)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.menu_book_rounded, size: 16, color: c.primary),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(14, w: FontWeight.w800, c: c.textDark))),
            if (attention) AnTag(anTr('an_needs_attention', 'Needs attention'), c.warning, icon: Icons.volunteer_activism_rounded),
          ]),
        ),
      AnVsClassCard(rows: rows, bare: true),
      if (marks.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (var i = 0; i < marks.length; i++) ...[
          if (i > 0) Divider(color: c.divider.withValues(alpha: 0.6), height: 22),
          AnMarkRow(col: marks[i]),
        ],
      ],
    ]);
  }
}

bool _needsAttention(double? attendance, double? exams) =>
    (attendance != null && attendance < 60) || (exams != null && exams < 50);
