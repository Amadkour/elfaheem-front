// The teacher's pieces of the shared course page at 320×640 and 1400×900, ar / en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/teacher_course_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين — A complete, very long introduction';

TeacherCourse _course({bool published = true, bool rich = true, String type = 'live'}) => TeacherCourse.fromJson({
  'id': 7,
  'image_url': '',
  'name_ar': _long,
  'name_en': _long,
  if (rich) 'description_ar': '$_long $_long $_long',
  if (rich) 'description_en': '$_long $_long $_long',
  'students_count': 12480,
  'sessions_count': 148,
  'total_hours': 42.5,
  'expected_hours': rich ? 60.0 : 0.0,
  'price': 1500,
  'final_price': 999.0,
  'discount_active': true,
  'discount_percentage': 33.0,
  'type': type,
  'is_published': published,
  if (rich) ...{
    'schedules': [
      for (final d in ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday'])
        {'id': 1, 'day': d, 'start_time': '09:00', 'end_time': '11:30'},
    ],
    'certificates': [
      {'id': 3, 'title': 'شهادة إتمام المقرر مع مرتبة الشرف — Certificate of completion with honours', 'description': _long},
      {'id': 4, 'title': 'شهادة حضور'},
    ],
    'tools': [
      {'id': 4, 'title': 'Visual Studio Code with a very long tool name that has to wrap on a phone', 'description': _long},
    ],
    'prerequisites': [
      {'id': 5, 'title': 'أساسيات البرمجة', 'description': _long},
    ],
  },
});

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('status side card: published and draft', (t) async {
    for (final published in [true, false]) {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: SizedBox(
            width: kCourseAsideW,
            child: TeacherCourseStatusCard(course: _course(published: published), onAddSession: () {}, onEdit: () {}),
          ),
        ),
      );
    }
  });

  testWidgets('details tab: everything, long Arabic data', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: TeacherCourseDetails(
          course: _course(),
          rating: const SizedBox(height: 40),
          onManageSchedule: () {},
          onManageCertificate: (_) {},
        ),
      ),
    );
  });

  testWidgets('details tab: empty live course asks for a schedule', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(child: TeacherCourseDetails(course: _course(rich: false), onManageSchedule: () {})),
      act: (t) async => expect(find.byIcon(Icons.add_rounded), findsOneWidget),
    );
  });

  testWidgets('details tab: empty recorded course says there is nothing yet', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(child: TeacherCourseDetails(course: _course(rich: false, type: 'recorded'))),
    );
  });

  testWidgets('sessions header (with and without sessions) and the empty state', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: Column(
          children: [
            TeacherSessionsHeader(count: 148, onAdd: () {}),
            TeacherSessionsHeader(count: 0, onAdd: () {}),
            Padding(
              padding: const EdgeInsets.all(kCourseGutter),
              child: TeacherSessionsEmpty(onAdd: () {}),
            ),
          ],
        ),
      ),
    );
  });
}
