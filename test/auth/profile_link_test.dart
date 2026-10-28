// Profile links by username (D-074): the link parser (`/@ahmed`, `@Ahmed`, full URLs, junk), the share URL, and the
// defensive reader of GET /api/v1/public/u/{username}.
import 'package:flutter_education_app/features/shared/public_profile/public_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// One course card as the server sends it (CourseResponse without `teacher`).
Map<String, dynamic> courseJson(int id, {String name = 'Python from zero', int students = 120}) => {
      'id': id,
      'is_private': false,
      'allow_resubscribe': true,
      'name_ar': 'بايثون من الصفر',
      'name_en': name,
      'description_ar': 'وصف',
      'description_en': 'A description',
      'fees': 300.0,
      'type': 'recorded',
      'category': {'id': 3, 'name_ar': 'برمجة', 'name_en': 'Programming', 'description': null, 'parent_id': null,
        'image_url': null},
      'image_url': null,
      'is_published': true,
      'max_students': null,
      'start_date': null,
      'end_date': null,
      'created_at': '2026-10-01T10:00:00',
      'students_count': students,
      'sessions_count': 12,
      'enrollments_count': students,
      'average_rating': 4.5,
      'total_hours': 18.0,
      'is_favorite': false,
      'is_enrolled': false,
      'progress': 0.0,
      'materials_total': 0,
      'materials_completed': 0,
      'schedules': [],
      'certificates': [],
      'tools': [],
      'prerequisites': [],
      'currency': 'EGP',
      'status': 'in_progress',
      'next_course_ids': [],
      'recommended_course_ids': [],
      'price': 300.0,
      'final_price': 300.0,
      'price_yearly': 300.0,
      'price_monthly': null,
      'price_six_months': null,
      'price_options': [],
      'default_price_plan_index': 0,
      'default_plan': 'yearly',
      'discount_active': false,
      'discount_ends_at': null,
      'discount_percentage': null,
      'discount_days': null,
    };

Map<String, dynamic> teacherJson() => {
      'kind': 'teacher',
      'id': 7,
      'name': 'Ahmed Teacher',
      'username': 'ahmed',
      'image_url': 'https://img.test/a.png',
      'bio': 'I teach Python.',
      'headline': 'Programming',
      'specialization': {'id': 3, 'name_ar': 'برمجة', 'name_en': 'Programming'},
      'experience_years': 7,
      'courses_count': 2,
      'courses': <Object?>[courseJson(1), courseJson(2, name: 'Data science')],
    };

void main() {
  group('profileLinkFrom', () {
    test('route names and bare handles', () {
      expect(profileLinkFrom('/@ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('/@Ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('@Ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('/@ahmed/'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('/@ahmed?utm=wa'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('/%40ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('/@ahmed.ali_1'), const ProfileLink('ahmed.ali_1'));
    });

    test('full URLs on the site only', () {
      expect(profileLinkFrom('https://nextbrain.site/@ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('https://www.nextbrain.site/@Ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('http://nextbrain.site/@ahmed'), const ProfileLink('ahmed'));
      expect(profileLinkFrom('https://evil.example/@ahmed'), isNull);
      expect(profileLinkFrom('ftp://nextbrain.site/@ahmed'), isNull);
    });

    test('junk and other links are not profile links', () {
      for (final s in <String?>[
        null, '', '   ', '/', '/ahmed', 'ahmed', '/c/12?ref=5', '/live/abc', '/@', '/@@ahmed', '/@ab', '/@admin',
        '/@a..b', '/@ahmed/courses', '/u/@ahmed', '/@ahmed.com', '/@123', '/@${'a' * 31}', '/@%E0%A4%A', '/login',
        'mailto:ahmed@nextbrain.site', 'https://nextbrain.site/', 'https://nextbrain.site/c/3',
      ]) {
        expect(profileLinkFrom(s), isNull, reason: '$s');
      }
    });
  });

  test('profileUrl', () {
    expect(profileUrl('ahmed'), 'https://nextbrain.site/@ahmed');
    expect(profileUrl('@Ahmed'), 'https://nextbrain.site/@ahmed');
    expect(profileLinkFrom(profileUrl('@Ahmed.Ali')), const ProfileLink('ahmed.ali'));
  });

  group('PublicProfile.fromJson', () {
    test('a teacher with courses', () {
      final p = PublicProfile.fromJson(teacherJson())!;
      expect(p.isTeacher, isTrue);
      expect(p.id, 7);
      expect(p.username, 'ahmed');
      expect(p.bio, 'I teach Python.');
      expect(p.specialization('ar'), 'برمجة');
      expect(p.specialization('en'), 'Programming');
      expect(p.experienceYears, 7);
      expect(p.coursesCount, 2);
      expect(p.courses.map((c) => c.id).toList(), ['1', '2']);
      expect(p.courses.first.teacher, isNull);
      expect(p.courses.first.studentsCount, 120);
    });

    test('a teacher block on a course is dropped; a broken card is skipped', () {
      final j = teacherJson();
      (j['courses'] as List).add({...courseJson(3), 'teacher': {'id': 7}}); // the catalogue's strict teacher parser
      (j['courses'] as List).add({...courseJson(4), 'sessions_count': 'many'}); // a type CourseModel cannot read
      (j['courses'] as List).add('junk');
      final p = PublicProfile.fromJson(j)!;
      expect(p.courses.map((c) => c.id).toList(), ['1', '2', '3']);
    });

    test('missing keys never throw; another kind is a minimal card', () {
      final p = PublicProfile.fromJson({'id': 9, 'username': '@Sara', 'kind': 'student'})!;
      expect(p.isTeacher, isFalse);
      expect(p.username, 'sara');
      expect(p.name, '@sara');
      expect(p.courses, isEmpty);
      expect(p.coursesCount, 0);
      expect(p.specialization('en'), isNull);
      final q = PublicProfile.fromJson({'id': 9, 'username': 'sara', 'headline': 'Maths', 'specialization': 'x'})!;
      expect(q.kind, 'person');
      expect(q.specialization('ar'), 'Maths');
    });

    test('no id or username → null', () {
      expect(PublicProfile.fromJson(null), isNull);
      expect(PublicProfile.fromJson('x'), isNull);
      expect(PublicProfile.fromJson({'id': 1}), isNull);
      expect(PublicProfile.fromJson({'username': 'ahmed'}), isNull);
      expect(PublicProfile.fromJson({'id': 1, 'username': '  '}), isNull);
    });
  });
}
