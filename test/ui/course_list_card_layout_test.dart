// The shared course card and its list parts (lib/features/shared/course/course_list_card.dart) at 320x640 and
// 1400x900, Arabic + English, textScaler 1.3: rows and tiles with very long titles, an organization badge leading
// the meta line, every footer (progress · price with a discount · the teacher's figures), the corner controls, the
// toolbar (search + segments + action), the empty line, the error banner and the skeleton — plus CourseCard over a
// CourseModel in HomeCourseList (rows on a phone, a grid of tiles wider).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/course/course_list_card.dart';
import 'package:flutter_education_app/features/shared/course/course_price_tag.dart';
import 'package:flutter_education_app/features/shared/course/course_scope.dart';
import 'package:flutter_education_app/features/shared/course/course_scope_bar.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'أساسيات البرمجة بلغة بايثون من الصفر حتى الاحتراف مع مشاريع عملية ومراجعات أسبوعية ممتدة';
const longEn = 'Python programming from zero to professional with hands-on projects and long weekly reviews';

const org = CourseOrg(
  id: 4,
  nameAr: 'كلية الهندسة والتكنولوجيا وعلوم الحاسب والذكاء الاصطناعي',
  nameEn: 'Faculty of Engineering, Technology, Computer Science and Artificial Intelligence',
  color: '#8B1E3F',
  path: '/1/4/',
);

String get title => AppConfig.lang == 'ar' ? longAr : longEn;

List<Widget> cards(BuildContext context, CourseCardShape shape) => [
      CourseListCard(
        shape: shape,
        title: title,
        imageUrl: '',
        chip: CourseCoverChip.type(context, live: true),
        corner: const CourseFavoriteMark(),
        meta: [title, courseLessonsLabel(123456)],
        metaLead: const CourseOrgBadge(org: org),
        isPrivate: true,
        footer: const CourseProgressFooter(progress: 100),
        onTap: () {},
      ),
      CourseListCard(
        shape: shape,
        title: title,
        imageUrl: '',
        chip: CourseCoverChip.type(context, live: false),
        meta: [courseHoursLabel(12)],
        footer: CoursePriceFooter(
          price: coursePriceLabel(AppCurrency.egp, 1234567.5),
          original: coursePriceLabel(AppCurrency.egp, 9876543),
          offPercent: 25,
        ),
      ),
      CourseListCard(
        shape: shape,
        title: title,
        imageUrl: '',
        chip: CourseCoverChip.status(context, published: false),
        corner: IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert_rounded)),
        meta: [title, coursePriceLabel(AppCurrency.sar, 0)],
        footer: const CourseStatsFooter(students: 1234567, sessions: 98765, rating: 4.85),
      ),
    ];

CourseModel course(int id, {CourseOrg? o, bool enrolled = true}) => CourseModel(
      id: '$id', imageUrl: '', price: enrolled ? 0 : 450, finalPrice: enrolled ? null : 300, discountActive: !enrolled,
      discountPercentage: 33, type: id.isEven ? 'live' : 'recorded', isEnrolled: enrolled, isPublished: true,
      expectedHours: 10, sessionsCount: 1000 * id, titleEn: '$longEn $id', titleAr: '$longAr $id', org: o,
      progress: 37, isFavorite: id.isOdd,
    );

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  testWidgets('rows: long titles, badge-led meta, every footer, corner controls', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final card in cards(context, CourseCardShape.row)) ...[card, const SizedBox(height: 8)],
          ],
        ),
      ),
    );
  });

  testWidgets('tiles in a grid: the same cards at the computed cell height', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => LayoutBuilder(
        builder: (context, box) => CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: CourseCardSliver(
              width: box.maxWidth - 32,
              count: 3,
              itemBuilder: (context, i, _) => cards(context, CourseCardShape.tile)[i],
            ),
          ),
        ]),
      ),
    );
  });

  testWidgets('a tile at a narrow fixed width (two columns at 600 px)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => Center(
          child: SizedBox(
            width: 280,
            height: CourseListCard.tileHeight(context, 280),
            child: cards(context, CourseCardShape.tile)[2],
          ),
        ),
      ),
    );
  });

  testWidgets('HomeCourseList: enrolled + catalogue courses with badges', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => HomeCourseList(
        hasMore: true,
        courses: [course(1), course(2, o: org), course(3, enrolled: false), course(4, o: org, enrolled: false)],
        onTap: (_) {},
        isTeacher: false,
        pageName: 'list-card-test',
        onLoadMore: () {},
        onRefresh: () async {},
        badgeFor: (c) => CourseOrgBadge(org: c.org),
      ),
    );
  });

  testWidgets('toolbar, empty line, error banner, skeleton', (tester) async {
    final search = TextEditingController(text: longEn);
    addTearDown(search.dispose);
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        CourseListToolbar(
          search: CourseSearchField(controller: search, hint: 'search_course_by_name_description', onChanged: (_) {}),
          filter: CourseSegments<int>(
            selected: 1,
            onSelect: (_) {},
            segments: const [
              CourseSegment(0, 'All the courses I have', count: 123456),
              CourseSegment(1, 'In progress right now', count: 98765),
              CourseSegment(2, 'Completed and certified', count: 4321),
            ],
          ),
          action: FilledButton(onPressed: () {}, child: const Text('New course')),
        ),
        CourseListError(message: '$longEn $longEn', onRetry: () {}),
        SizedBox(
          height: 160,
          child: CourseListEmpty(icon: Icons.search_off_rounded, message: longEn, actionLabel: longEn, onAction: () {}),
        ),
        const Expanded(child: CourseListSkeleton()),
      ]),
    );
  });

  test('prices follow the language; session counts take the Arabic plural forms (the course page says "Session")', () {
    AppConfig.lang = 'en';
    expect(coursePriceLabel(AppCurrency.egp, 450), 'EGP 450');
    expect(coursePriceLabel(AppCurrency.usd, 19.5), '\$19.50');
    expect(coursePriceLabel(AppCurrency.sar, 0), 'Free');
    expect(courseLessonsLabel(1), '1 session');
    expect(courseLessonsLabel(12), '12 sessions');
    AppConfig.lang = 'ar';
    expect(coursePriceLabel(AppCurrency.egp, 450), '450 ج.م');
    expect(courseLessonsLabel(2), 'جلستان');
    expect(courseLessonsLabel(5), '5 جلسات');
    expect(courseLessonsLabel(12), '12 جلسة');
    AppConfig.lang = 'en';
  });
}
