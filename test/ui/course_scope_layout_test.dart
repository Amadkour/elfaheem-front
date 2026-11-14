// The course scope parts (lib/features/courses/course_scope_bar.dart) at 320x640 and 1400x900, Arabic +
// English, textScaler 1.3: the teacher's banner (personal / organization, long names, counts, the other sides,
// Switch), the student's chip bar (many organizations, long names) and the card badge, plus the course list with
// badges drawn over its cards.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/courses/course_scope_bar.dart';
import 'package:flutter_education_app/features/courses/home_course_list.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'كلية الهندسة والتكنولوجيا وعلوم الحاسب والذكاء الاصطناعي بجامعة القاهرة الجديدة';
const longEn = 'Faculty of Engineering, Technology, Computer Science and Artificial Intelligence';

CourseOrg org(int id, {String? path, String? color = '#1F6FEB'}) =>
    CourseOrg(id: id, nameAr: '$longAr $id', nameEn: '$longEn $id', color: color, path: path ?? '/$id/');

final counts = [
  const CourseScopeCount(scope: CourseScope.personal, count: 1234),
  for (var i = 1; i <= 6; i++) CourseScopeCount(scope: CourseScope.org(i), count: 100 * i, org: org(i)),
];

CourseModel course(int id, CourseOrg? o) => CourseModel(
      id: '$id', imageUrl: '', price: id.isEven ? 0 : 450, type: 'recorded', isEnrolled: true, isPublished: true,
      expectedHours: 10, titleEn: '$longEn course $id', titleAr: '$longAr كورس $id', org: o,
    );

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  testWidgets('teacher banner: personal with organizations elsewhere, and Switch', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const Padding(
        padding: EdgeInsets.all(16),
        child: CourseScopeBanner(scope: CourseScope.personal, count: 12345, elsewhere: 98765, onSwitch: _noop),
      ),
    );
  });

  testWidgets('teacher banner: an organization with a long name, no logo, unknown count, no Switch', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Padding(
        padding: const EdgeInsets.all(16),
        child: CourseScopeBanner(scope: const CourseScope.org(3), org: org(3), elsewhere: 4),
      ),
    );
  });

  testWidgets('teacher banner: a bare organization id (nothing known yet)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const CourseScopeBanner(scope: CourseScope.org(9), org: CourseOrg(id: 9)),
    );
  });

  testWidgets('student chips: All · Personal · six organizations with long names, one selected', (tester) async {
    final chips = courseScopeChips(counts, selected: const CourseScope.org(3));
    expect(chips.length, 8);
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        CourseScopeChipBar(chips: chips, selected: const CourseScope.org(3), onSelect: (_) {}),
        const SizedBox(height: 8),
        CourseScopeChipBar(chips: chips, selected: CourseScope.all, onSelect: (_) {}),
      ]),
    );
  });

  testWidgets('student chips: one side only draws nothing', (tester) async {
    await tester.pumpWidget(layoutHost(CourseScopeChipBar(
      chips: const [CourseScopeChip(scope: CourseScope.personal, count: 3)],
      selected: CourseScope.personal,
      onSelect: (_) {},
    )));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('badges: personal and a long organization name; a mixed list draws one on every card', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        const CourseOrgBadge(org: null),
        CourseOrgBadge(org: org(2, color: null)),
        Expanded(
          child: HomeCourseList(
            hasMore: false,
            courses: [course(1, null), course(2, org(2)), course(3, org(5, path: '/2/5/'))],
            onTap: (_) {},
            isTeacher: false,
            pageName: 'scope-test',
            onLoadMore: () {},
            onRefresh: () async {},
            badgeFor: (c) => CourseOrgBadge(org: c.org),
          ),
        ),
      ]),
    );
  });

  testWidgets('a chip tap selects its side', (tester) async {
    AppConfig.lang = 'en';
    CourseScope? picked;
    await tester.pumpWidget(layoutHost(CourseScopeChipBar(
      chips: courseScopeChips(counts, selected: CourseScope.personal),
      selected: CourseScope.personal,
      onSelect: (s) => picked = s,
    )));
    await tester.tap(find.bySemanticsLabel(RegExp('^All, ')));
    expect(picked, CourseScope.all);
  });
}

void _noop() {}
