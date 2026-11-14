// QA round 3 bugs that goldens built on hand-made data missed, reproduced from REAL server payloads
// (test/fixtures/real/: the local stack, demo student `market.student`, one course, personal fields cleared):
//   N5  the analytics tab said 89 %, the analytics profile 100 % for the same course: the profile's copy is the
//       stored Enrollment.progress_percentage, which the server refreshes only on a completion
//   N9  material cards and the session row drew "☆☆☆☆☆ 0.0 (0)" from `rate: {total: 0, average: 0.0}`, and the
//       recording names are "<session> — تسجيل الحصة (لقاء n)"
//   L2  "4 من 4 محاضرة" / "حضر 4 من 4 جلسة": counts with the wrong noun form
//   N7  the categories carry no picture (`image_url: null`): one letter, after the article
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_ui.dart' show anFmt, anPct;
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_screen.dart' show CategoryAvatar;
import 'package:flutter_education_app/features/shared/session/material/components/material_title.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_api.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_provider.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_models.dart';
import 'package:flutter_test/flutter_test.dart';

dynamic _real(String name) => jsonDecode(File('test/fixtures/real/$name.json').readAsStringSync());

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});
  setUp(() => AppConfig.lang = 'ar');

  group('N5 one progress figure (real /my-enrolled-courses + /data-lab/me/profile)', () {
    final courses = StudentAnalyticsApi.parseEnrollments(_real('my_enrolled_courses'));
    final profile = DlProfile.fromJson(dlMap(_real('data_lab_me_profile')));
    final block = profile.courses.single;

    test('the server disagrees with itself: the live count is 88.9 %, the profile copy 100 %', () {
      expect(courses.single.id, block.courseId);
      expect(courses.single.progress, 89);
      expect(block.progress, 100); // what the analytics profile drew
    });

    test('the profile shows the enrolment figure the analytics tab shows', () {
      final live = anLiveProgress(courses);
      final hub = StudentAnalyticsProvider();
      expect(anPct(anBlockProgress(block, live)), anPct(hub.progressOf(courses.single)));
      expect(anPct(anBlockProgress(block, live)), '89%');
      expect(anPct(anProfileProgress(profile.courses, live, overall: profile.progress)), '89%');
      // a teacher (no live figures) keeps the profile's own
      expect(anProfileProgress(profile.courses, const {}, overall: profile.progress), 100);
    });

    test('a cohort of one is level with itself on both pages', () {
      final live = anLiveProgress(courses);
      final shown = anBlockProgress(block, live);
      double? cls(String key) => block.columns.firstWhere((c) => c.key == key).classAvg;
      expect(anClassOnScale(shown: shown, mine: block.progress, cls: cls('progress')), shown);
    });
  });

  group('N9 session materials (real /sessions/{id}/materials + /courses/{id}/sessions)', () {
    final materials = [for (final m in _real('session_materials') as List) SessionMaterialModel.fromJson(m as Map<String, dynamic>)];
    final sessions = [
      for (final s in (_real('course_sessions') as Map)['items'] as List) TeacherSessionItem.fromJson(s as Map<String, dynamic>),
    ];

    test('recording titles drop the session name', () {
      final titles = [for (final m in materials) materialTitle(m.name, recorded: m.type == SessionMaterialType.recorded)];
      expect(titles.first, 'تسجيل الحصة');
      expect(titles[1], 'تسجيل الحصة · لقاء 2');
      expect(titles.where((t) => t.contains('—')), isEmpty);
    });

    test('no "0.0 (0)" row: an unrated file invites a student who finished it, else nothing', () {
      for (final m in materials) {
        expect(m.rateSummary!.total, 0);
        expect(ratingShow(total: m.rateSummary!.total, canRate: m.completed), RatingShow.invite);
        expect(ratingShow(total: m.rateSummary!.total, canRate: false), RatingShow.none);
      }
      expect(ratingShow(total: 3, canRate: false), RatingShow.stars);
    });

    test('an unrated session: an invite for the student once held, nothing for the teacher', () {
      final held = sessions.firstWhere((s) => s.name == 'ننن'); // 8 / 8 files done
      expect(held.rateSummary!.total, 0);
      final student = sessionRateable(isTeacher: false, completedFiles: held.completeMaterial, scheduledAt: held.scheduledAt);
      expect(ratingShow(total: held.rateSummary!.total, canRate: student), RatingShow.invite);
      final teacher = sessionRateable(isTeacher: true, completedFiles: held.completeMaterial, scheduledAt: held.scheduledAt);
      expect(ratingShow(total: held.rateSummary!.total, canRate: teacher), RatingShow.none);
      final now = DateTime.utc(2026, 10, 30, 9);
      expect(sessionRateable(isTeacher: false, completedFiles: 0, scheduledAt: now.add(const Duration(days: 2)), now: now), isFalse);
    });
  });

  group('L2 counts read with the right noun form', () {
    test('Arabic', () {
      expect(anFmt('an2_sessions_of', {'a': 4, 'sessions': anSessionsWord(4)}), '4 من 4 جلسات');
      expect(anFmt('an2_you_attended_of', {'a': 4, 'sessions': anSessionsWord(4)}), 'حضرت 4 من 4 جلسات حتى الآن');
      expect(anFmt('sa_ins_att_excellent', {'present': 11, 'sessions': anSessionsWord(11)}), contains('من 11 جلسة'));
      expect(anFmt('sa_ins_att_fair', {'sessions': anSessionsWord(1)}), contains('فاتتك جلسة واحدة'));
      expect(anFmt('sa_ins_exam_some', {'passed': 1, 'exams': anExamsWord(3), 'failed': 2}), 'اجتزت 1 من 3 اختبارات، ولم تجتز 2.');
      expect(anCoursesCount(1), 'مقرر واحد');
      expect(anCoursesCount(4), '4 مقررات');
    });

    test('English', () {
      AppConfig.lang = 'en';
      expect(anFmt('an2_sessions_of', {'a': 4, 'sessions': anSessionsWord(4)}), '4 of 4 sessions');
      expect(anFmt('an2_ins_low_att', {'a': 1, 'sessions': anSessionsWord(1), 'course': 'X'}), startsWith('You attended 1 of 1 session in X.'));
      expect(anCoursesCount(1), '1 course');
    });

    test('every key keeps its placeholders in both languages', () {
      for (final k in ['an2_sessions_of', 'an2_ins_low_att', 'an2_you_attended_of', 'sa_ins_att_excellent', 'sa_ins_att_fair',
        'sa_ins_att_low', 'sa_ins_exam_some', 'session_rate_it']) {
        final e = translation[k] as Map;
        Set<String> ph(String s) => RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();
        expect(ph(e['ar'] as String), ph(e['en'] as String), reason: k);
      }
    });
  });

  test('N7 the real categories (no image_url) each get one letter', () {
    final cats = [for (final c in _real('categories') as List) CategoryModel.fromJson(c as Map<String, dynamic>)];
    expect(cats.every((c) => c.imageUrl == null), isTrue);
    expect([for (final c in cats) CategoryAvatar.initialsOf(c.nameAr)], ['ر', 'ع', 'ل', 'ل', 'ح', 'ت']);
    expect([for (final c in cats) CategoryAvatar.initialsOf(c.nameEn)], ['M', 'S', 'A', 'E', 'C', 'H']);
  });
}
