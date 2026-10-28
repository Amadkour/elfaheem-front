// The student's course page pieces (buy card / bar, enrolled card, spotlight cards, About tab) at 320×640 and
// 1400×900, ar / en, textScaler 1.3, with long Arabic data.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/student/courses/details/components/about.dart';
import 'package:flutter_education_app/features/student/courses/details/components/course_detail_parts.dart';
import 'package:flutter_education_app/features/student/courses/details/components/issued_certificate.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction to AI';

CourseModel _course({bool enrolled = false, bool discount = false, double price = 1499.5, String type = 'live'}) =>
    CourseModel(
      id: '42',
      imageUrl: '',
      price: price,
      finalPrice: discount ? price * 0.6 : price,
      discountActive: discount,
      discountPercentage: discount ? 40 : 0,
      discountEndsAt: discount ? DateTime.now().add(const Duration(days: 3)) : null,
      type: type,
      isEnrolled: enrolled,
      isPublished: true,
      expectedHours: 120,
      totalHours: 96.5,
      sessionsCount: 148,
      studentsCount: 12480,
      certificates: const [CourseCertificate(id: 1, courseId: 42, title: _long)],
      schedules: [
        for (var i = 0; i < 4; i++) CourseSchedule(id: i, courseId: 42, day: 'wednesday', startTime: '09:00', endTime: '10:30'),
      ],
      titleAr: _long,
      titleEn: _long,
    );

Widget _side(Widget child) => SingleChildScrollView(
  child: Center(child: SizedBox(width: kCourseAsideW - kCourseGutter * 2, child: child)),
);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('CourseBuyCard: paid, discounted, free + a payment notice', (t) async {
    for (final c in [_course(), _course(discount: true), _course(price: 0, type: 'recorded')]) {
      await expectNoLayoutErrors(
        t,
        () => _side(CourseBuyCard(course: c, onEnroll: () {}, status: const Text('$_long $_long'))),
      );
    }
  });

  testWidgets('CourseEnrolledCard', (t) async {
    await expectNoLayoutErrors(t, () => _side(CourseEnrolledCard(course: _course(enrolled: true))));
  });

  testWidgets('CourseBuyBar: paid, discounted, free', (t) async {
    for (final c in [_course(), _course(discount: true), _course(price: 0)]) {
      await expectNoLayoutErrors(
        t,
        () => Column(
          children: [
            const Spacer(),
            CourseBuyBar(course: c, onEnroll: () {}, status: const Text(_long)),
          ],
        ),
      );
    }
  });

  testWidgets('spotlight: live now · start · continue · completed', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(kCourseGutter),
        child: CourseSpotlightStack(
          children: [
            courseLiveNowCard(sessionName: _long, onJoin: () {}),
            courseLearningCard(progress: 0, done: 0, total: 30, nextLesson: _long, hasCertificates: true, onContinue: () {}),
            courseLearningCard(progress: 0.42, done: 13, total: 30, nextLesson: _long, hasCertificates: false, onContinue: () {}),
            courseLearningCard(
              progress: 1,
              done: 30,
              total: 30,
              hasCertificates: true,
              onContinue: () {},
              onCertificates: () {},
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('CourseAboutView with everything filled in', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: CourseAboutView(
          description: List.filled(12, _long).join(' '),
          teacherName: 'د. عبد الرحمن محمد عبد الله الحسيني Dr. Abdelrahman',
          category: 'البرمجة وعلوم الحاسب',
          onTeacher: () {},
          rating: const Text('★★★★☆ 4.6'),
          myCertificates: const [
            IssuedCertificate(id: 1, certificateId: 1, title: _long, urlEn: ''),
          ],
          schedules: [
            for (var i = 0; i < 4; i++)
              CourseSchedule(id: i, courseId: 42, day: 'wednesday', startTime: '09:00', endTime: '10:30'),
          ],
          certificates: const [CourseCertificate(id: 1, courseId: 42, title: _long, description: '$_long $_long')],
          tools: const [CourseTool(id: 1, courseId: 42, name: _long, description: _long)],
          prerequisites: const [CoursePrerequisite(id: 1, courseId: 42, title: _long, description: _long)],
        ),
      ),
    );
  });

  testWidgets('CourseAboutView: a long description folds behind "Show more"', (t) async {
    AppConfig.lang = 'en';
    await t.pumpWidget(
      layoutHost(SingleChildScrollView(child: CourseAboutView(description: List.filled(300, 'word').join(' ')))),
    );
    expect(find.text('Show more'), findsOneWidget);
    await t.tap(find.text('Show more'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Show less'), findsOneWidget);
  });
}
