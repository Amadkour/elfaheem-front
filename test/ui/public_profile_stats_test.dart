// The ONE profile page (D-850 – D-855): parsing the teacher's figures, the student's opt-in summary and the owner's
// answer; `/app/@name` links; and the page's new parts at 320x640 and 1400x900, Arabic + English, textScaler 1.3 —
// a teacher with every figure, growth and most joined; a young teacher ("New", no zeros); a student with the learning
// summary and finished courses; the owner panel (teacher live, student blocked); the guest's join card.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile_page.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/profile_link_test.dart' show courseJson, teacherJson;
import 'layout_harness.dart';

const longName = 'عبد الرحمن محمد عبد العزيز الشريف Abdulrahman Mohammed Abdulaziz Alsharif';

Map<String, dynamic> statsJson({bool young = false}) => young
    ? {'students_taught': 0, 'courses': 1, 'is_new': true, 'since': 2026, 'top_courses': <Object?>[]}
    : {
        'students_taught': 12840,
        'active_learners': 930,
        'courses': 5,
        'lessons': 214,
        'hours': 186.5,
        'rating': 4.83,
        'ratings_count': 1204,
        'reviews_count': 318,
        'completion_rate': 78,
        'certificates': 2410,
        'live_sessions': 96,
        'response_hours': 2.4,
        'since': 2024,
        'is_new': false,
        'top_courses': [
          {'id': 1, 'name_ar': longName, 'name_en': longName, 'students': 8200},
          {'id': 2, 'name_ar': 'علوم البيانات', 'name_en': 'Data science', 'students': 3100},
          {'id': 3, 'name_ar': 'بايثون', 'name_en': 'Python', 'students': 1540},
        ],
      };

List<Map<String, dynamic>> growthJson() => [
      for (var i = 1; i <= 12; i++) {'month': '2026-${i.toString().padLeft(2, '0')}', 'students': i * 37 % 400},
    ];

Map<String, dynamic> richTeacher() => teacherJson()
  ..['name'] = longName
  ..['stats'] = statsJson()
  ..['growth'] = growthJson()
  ..['courses'] = [for (var i = 1; i <= 3; i++) courseJson(i, students: i * 1300)]
  ..['sections'] = {'bio': true, 'stats': true, 'courses': true, 'growth': true, 'reviews': true};

Map<String, dynamic> studentJson() => {
      'kind': 'student',
      'id': 41,
      'name': longName,
      'username': 'sara.learns',
      'bio': 'I love math and physics. أحب الرياضيات.',
      'learning': {'streak_days': 23, 'courses_completed': 4, 'courses_in_progress': 2, 'certificates': 3, 'since': 2025},
      'completed_courses': [
        {'id': 5, 'name_ar': 'جبر', 'name_en': 'Algebra'},
        {'id': 6, 'name_ar': longName, 'name_en': longName},
      ],
      'sections': {'bio': true, 'learning': true, 'completed_courses': true},
    };

PublicProfileResult found(Map<String, dynamic> j) =>
    PublicProfileResult(PublicProfileStatus.found, profile: PublicProfile.fromJson(j));

MyPublicProfile owner({bool student = false}) => MyPublicProfile.fromJson({
      'settings': {
        'is_public': !student,
        'fields': student
            ? {'bio': true, 'learning': false, 'completed_courses': false}
            : {'bio': true, 'stats': true, 'courses': true, 'growth': false, 'reviews': true},
      },
      'available': student ? ['bio', 'learning', 'completed_courses'] : ['bio', 'stats', 'courses', 'growth', 'reviews'],
      'username': student ? null : 'abdulrahman.mohammed_alsharif',
      'username_confirmed': !student,
      'live': !student,
      'link': student ? null : 'https://nextbrain.site/@abdulrahman.mohammed_alsharif',
      'blocked': student ? 'username_unconfirmed' : null,
      'profile': student ? studentJson() : richTeacher(),
    })!;

void main() {
  group('parsing', () {
    test('/app/@name links (the web base path)', () {
      expect(profileLinkFrom('/app/@Ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('https://nextbrain.site/app/@ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('/other/@ahmed'), isNull);
      expect(profileLinkFrom('/app/x/@ahmed'), isNull);
    });

    test('teacher figures, growth and sections', () {
      final p = PublicProfile.fromJson(richTeacher())!;
      final s = p.stats!;
      expect(s.studentsTaught, 12840);
      expect(s.rating, 4.83);
      expect(s.completionRate, 78);
      expect(s.responseHours, 2.4);
      expect(s.topCourses.map((c) => c.students), [8200, 3100, 1540]);
      expect(p.growth.length, 12);
      expect(p.growth.first.date, DateTime.utc(2026, 1, 15));
      expect(p.sections['growth'], isTrue);
    });

    test('a young teacher and a student; an older server without figures', () {
      final y = PublicProfile.fromJson(teacherJson()..['stats'] = statsJson(young: true))!;
      expect(y.stats!.isNew, isTrue);
      expect(y.stats!.rating, isNull);
      expect(y.stats!.completionRate, isNull);
      final s = PublicProfile.fromJson(studentJson())!;
      expect(s.isStudent, isTrue);
      expect(s.learning!.streakDays, 23);
      expect(s.completedCourses.map((c) => c.id), [5, 6]);
      final old = PublicProfile.fromJson(teacherJson())!;
      expect(old.stats, isNull);
      expect(old.growth, isEmpty);
    });

    test('the owner answer', () {
      final m = owner();
      expect(m.live, isTrue);
      expect(m.available.first, 'bio');
      expect(m.fields['growth'], isFalse);
      expect(m.profile!.isTeacher, isTrue);
      final s = owner(student: true);
      expect(s.blocked, 'username_unconfirmed');
      expect(s.isPublic, isFalse);
    });

    test('reply time in words', () {
      AppConfig.lang = 'en';
      expect(profileReplyTime(0.4), '< 1 hour');
      expect(profileReplyTime(2.4), '2 hours');
      expect(profileReplyTime(50), '2 days');
    });
  });

  Future<void> pump(WidgetTester tester, PublicProfileResult r, {Widget? owner, Widget? join}) => expectNoLayoutErrors(
        tester,
        () => PublicProfileView(
          result: r,
          onOpenCourse: (_) {},
          onOpenCourseId: (_) {},
          ownerPanel: owner,
          joinCard: join,
        ),
      );

  testWidgets('teacher with every figure, growth and most joined', (tester) async {
    await pump(tester, found(richTeacher()));
  });

  testWidgets('young teacher: New, no zeros', (tester) async {
    await pump(tester, found(teacherJson()..['stats'] = statsJson(young: true)..['courses'] = []..['courses_count'] = 0));
  });

  testWidgets('student with the learning summary and finished courses', (tester) async {
    await pump(tester, found(studentJson()));
  });

  testWidgets('owner panel: teacher live', (tester) async {
    final m = owner();
    await pump(tester, found(richTeacher()),
        owner: ProfileOwnerPanel(
            mine: m, onPublic: (_) {}, onField: (_, _) {}, onEdit: () {}, onShare: () {}, onAccount: () {}, onDocuments: () {}));
  });

  testWidgets('owner panel: student blocked, guest join card', (tester) async {
    final m = owner(student: true);
    await pump(tester, found(studentJson()),
        owner: ProfileOwnerPanel(mine: m, onPublic: (_) {}, onField: (_, _) {}, onEdit: () {}, onAccount: () {}),
        join: ProfileJoinCard(name: longName, teacher: false, onJoin: () {}, onSignIn: () {}));
  });

  testWidgets('content (en): figures, "New", the join card', (tester) async {
    final prev = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prev);
    AppConfig.lang = 'en';
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var joined = false;
    await tester.pumpWidget(layoutHost(
      PublicProfileView(
        result: found(richTeacher()),
        onOpenCourse: (_) {},
        joinCard: ProfileJoinCard(name: 'Ahmed', teacher: true, onJoin: () => joined = true, onSignIn: () {}),
      ),
      scale: 1,
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('In numbers'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('Most joined'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('2 hours'), findsOneWidget);
    expect(find.text('Learn with Ahmed on NextBrain'), findsOneWidget);
    await tester.tap(find.text('Create a free account'));
    expect(joined, isTrue);

    await tester.pumpWidget(layoutHost(
      PublicProfileView(result: found(teacherJson()..['stats'] = statsJson(young: true)), onOpenCourse: (_) {}),
      scale: 1,
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('New'), findsOneWidget);
    expect(find.text('New on NextBrain — be one of the first students.'), findsOneWidget);
    expect(find.text('Growth'), findsNothing);
  });
}
