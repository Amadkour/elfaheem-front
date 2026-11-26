// VISUAL review renders of the teacher's account pages (redesign T2b, Tea2Account account / edit / docs / public and
// complaints): 390x844 and 1360x900, Arabic and English, light, CAST demo data. Compared by eye with
// D:/platform/redesign-ref/ref/teacher/060_* … 063_*, 101_*, 102_*. Not a CI suite.
//
//   flutter test test/visual/redesign/t2b/t2b_account_golden_test.dart --update-goldens [--plain-name account]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart' show CategoryModel;
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherProfileData, TeacherProfileDetail;
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_page.dart';
import 'package:flutter_education_app/features/profile/compalints/new_complaint_screen.dart';
import 'package:flutter_education_app/features/profile/profile_screen.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile_page.dart' show MyProfileScreen;
import 'package:flutter_education_app/features/profile/update_account_widget.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/t2b_parts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t2b_fakes.dart';
import '../kit_golden_harness.dart';

class _Home extends TeacherHomeProvider {
  @override
  TeacherStats get stats => TeacherStats(
        totalCourses: 4,
        totalStudents: 56,
        overallRating: 4.8,
        teacher: TeacherProfileData(
          id: 7,
          name: 'ماجد الشهري',
          gmail: 'teacher@example.test',
          role: 'teacher',
          isVerified: true,
          isActive: true,
          loginTimes: 1,
          registrationStep: 'done',
          createdAt: DateTime(2024),
          teacherProfile: TeacherProfileDetail(
            id: 1,
            userId: 7,
            experienceYears: 12,
            teachingType: 'online',
            paymentType: 'course',
            createdAt: DateTime(2024),
            specialization: const CategoryModel(id: '3', nameAr: 'رياضيات، ثانوي', nameEn: 'Maths, secondary', imageUrl: null, description: ''),
          ),
        ),
      );
}

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build, {List<String> langs = const ['ar', 'en']}) async {
    await t2bSetUp();
    final auth = MyAuthProvider(storage: storage)..loadCachedUser();
    await kitRender(
      tester,
      name,
      () => MultiProvider(
        providers: [
          ChangeNotifierProvider<MyAuthProvider>.value(value: auth),
          ChangeNotifierProvider<ProfileProvider>(create: (_) => ProfileProvider(storage: storage)),
          ChangeNotifierProvider<TeacherHomeProvider>(create: (_) => _Home()),
          ChangeNotifierProvider<TeacherDeviceRequestsProvider>(create: (_) => TeacherDeviceRequestsProvider()),
        ],
        child: build(),
      ),
      storage: storage,
      modes: const [false],
      langs: langs,
      scaffold: false,
    );
  }

  testWidgets('account', (t) => render(t, 't2b_account', () => const ProfileScreen()));
  testWidgets('public', (t) => render(t, 't2b_public', () => const MyProfileScreen()));
  testWidgets('complaints', (t) => render(t, 't2b_complaints', () => const ComplaintsHubPage()));
  testWidgets('new complaint', (t) => render(t, 't2b_new_complaint', () => ChangeNotifierProvider<ComplaintProvider>(create: (_) => ComplaintProvider(), child: const NewComplaintScreen(formOnly: true)), langs: const ['ar']));
  testWidgets('edit', (t) => render(t, 't2b_edit', () => const EditAccountScreen(isTeacher: true)));
  testWidgets('edit docs', (t) async {
    await t2bSetUp();
    final auth = MyAuthProvider(storage: storage)..loadCachedUser();
    await kitRender(
      t,
      't2b_edit_docs',
      () => MultiProvider(providers: [
        ChangeNotifierProvider<MyAuthProvider>.value(value: auth),
        ChangeNotifierProvider<ProfileProvider>(create: (_) => ProfileProvider(storage: storage)),
        ChangeNotifierProvider<TeacherDocumentProvider>(create: (_) => TeacherDocumentProvider()),
      ], child: const EditAccountScreen(isTeacher: true)),
      storage: storage,
      modes: const [false],
      langs: const ['ar'],
      scaffold: false,
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('edit.tab.documents')));
      },
    );
  });
}
