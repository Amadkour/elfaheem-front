// The public profile page's content (PublicProfileView, D-074) at 320x640 and 1400x900, Arabic + English, textScaler
// 1.3: a teacher with courses and a long name / bio, a teacher without courses, a minimal (non-teacher) card, loading,
// not found, switched off and a failed load.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/profile_link_test.dart' show courseJson, teacherJson;
import 'layout_harness.dart';

const longName = 'عبد الرحمن محمد عبد العزيز الشريف Abdulrahman Mohammed Abdulaziz Alsharif';

PublicProfileResult found(Map<String, dynamic> j) =>
    PublicProfileResult(PublicProfileStatus.found, profile: PublicProfile.fromJson(j));

void main() {
  Future<void> pump(WidgetTester tester, PublicProfileResult? r) => expectNoLayoutErrors(
        tester,
        () => PublicProfileView(result: r, onOpenCourse: (_) {}, onRetry: () {}, onBack: () {}),
      );

  testWidgets('teacher with courses', (tester) async {
    final j = teacherJson()
      ..['name'] = longName
      ..['image_url'] = null
      ..['bio'] = List.filled(12, 'أشرح البرمجة بخطوات واضحة. I explain programming step by step.').join(' ')
      ..['username'] = 'abdulrahman.mohammed_alsharif'
      ..['courses_count'] = 5
      ..['courses'] = [
        for (var i = 1; i <= 5; i++) courseJson(i, name: i.isEven ? 'Data science' : longName, students: i * 1300),
      ];
    await pump(tester, found(j));
  });

  testWidgets('teacher without courses, bio or specialization', (tester) async {
    final j = teacherJson()
      ..remove('bio')
      ..remove('specialization')
      ..remove('headline')
      ..['experience_years'] = 0
      ..['courses_count'] = 0
      ..['courses'] = [];
    await pump(tester, found(j));
  });

  testWidgets('minimal card for another kind', (tester) async {
    await pump(tester, found({'kind': 'person', 'id': 3, 'name': longName, 'username': 'sara'}));
  });

  testWidgets('content: name, @username, courses, empty and not-found texts (en)', (tester) async {
    final prev = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prev);
    AppConfig.lang = 'en';
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = '';
    await tester.pumpWidget(layoutHost(
      PublicProfileView(result: found(teacherJson()), onOpenCourse: (c) => opened = c.id),
      scale: 1,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Ahmed Teacher'), findsOneWidget);
    expect(find.text('@ahmed'), findsOneWidget);
    expect(find.text('I teach Python.'), findsOneWidget);
    expect(find.text('Programming'), findsWidgets);
    expect(find.text('Data science'), findsOneWidget);
    await tester.tap(find.text('Data science'));
    expect(opened, '2');

    await tester.pumpWidget(layoutHost(
      PublicProfileView(result: found(teacherJson()..['courses'] = []..['courses_count'] = 0), onOpenCourse: (_) {}),
      scale: 1,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No public courses yet'), findsOneWidget);

    var back = 0;
    await tester.pumpWidget(layoutHost(
      PublicProfileView(
        result: const PublicProfileResult(PublicProfileStatus.notFound),
        onOpenCourse: (_) {},
        onBack: () => back++,
      ),
      scale: 1,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Profile not found'), findsOneWidget);
    await tester.tap(find.text('Back'));
    expect(back, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loading, not found, disabled, failed', (tester) async {
    await pump(tester, null);
    await pump(tester, const PublicProfileResult(PublicProfileStatus.notFound));
    await pump(tester, const PublicProfileResult(PublicProfileStatus.disabled));
    await pump(tester, const PublicProfileResult(PublicProfileStatus.failed, message: 'Network error'));
  });
}
