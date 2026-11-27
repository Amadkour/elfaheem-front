// T1 courses: the hero with its space strip, the search + filter card, the trash sheet and the teacher's course card
// at 320x640 and 1400x900, ar / en, textScaler 1.3, with worst-case text.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/teacher/courses_parts.dart';
import 'package:flutter_education_app/features/home/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppHeroStat;
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'الرياضيات ٣ ثانوي، مجموعة أ مع شرح موسّع وتدريب مكثف على أسئلة التحصيلي — Maths 3 secondary, group A, extended';

void main() {
  for (final space in TeacherSpace.values) {
    testWidgets('hero: ${space.name}, with stats and the new-course button', (t) async {
      await expectNoLayoutErrors(
        t,
        () => T2Scope(
          child: SingleChildScrollView(
            child: TeacherSpaceHero(
              space: space,
              onSelect: (_) {},
              overlap: false,
              stats: space == TeacherSpace.courses
                  ? const [
                      AppHeroStat(value: '12480', label: 'دورات'),
                      AppHeroStat(value: '4', label: 'منشورة'),
                      AppHeroStat(value: '74', label: 'طالب'),
                      AppHeroStat(value: '4.8', label: 'التقييم'),
                    ]
                  : const [],
              action: space == TeacherSpace.courses ? const FilledButton(onPressed: null, child: Text('دورة جديدة New course')) : null,
            ),
          ),
        ),
      );
    });
  }

  testWidgets('toolbar card: scope, search and filter', (t) async {
    await expectNoLayoutErrors(
      t,
      () => const SingleChildScrollView(
        child: TeacherCoursesToolbarCard(
          scope: Text(_long),
          search: TextField(),
          filter: Row(children: [Expanded(child: Text(_long, maxLines: 1, overflow: TextOverflow.ellipsis))]),
        ),
      ),
    );
  });

  testWidgets('trash sheet: with and without students', (t) async {
    for (final n in [0, 1, 2, 5, 12]) {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: TeacherDeleteCourseSheet(title: _long, students: n)));
    }
  });

  testWidgets('teacher course card: row and tile', (t) async {
    for (final shape in CourseCardShape.values) {
      await expectNoLayoutErrors(
        t,
        () => T2Scope(
          child: SingleChildScrollView(
            child: SizedBox(
              width: shape == CourseCardShape.row ? 320 : 360,
              child: CourseListCard(
                shape: shape,
                title: _long,
                imageUrl: '',
                chip: const CourseCoverChip(label: 'منشورة'),
                corner: const SizedBox.square(dimension: 40, child: Icon(Icons.more_vert_rounded)),
                meta: const ['بث مباشر', 'رياضيات'],
                priceLine: '450 ريال سنويًا، أو 85 شهريًا',
                footer: const CourseStatsFooter(students: 12480, sessions: 24, rating: 4.8),
              ),
            ),
          ),
        ),
      );
    }
  });
}
