// Redesign group T1 (teacher: the course page): demo data from docs/redesign/CAST.md (أ. ماجد الشهري, the course
// "الرياضيات ٣ ث، أ") on top of FakeApi, for the layout tests and the review renders.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';

import '../fake_api.dart';
import 't2_fakes.dart';

/// GET /courses/41: a published live course (CAST).
Map<String, dynamic> t1CourseJson({bool draft = false}) => {
      'id': 41,
      'name_ar': draft ? 'كيمياء ١ ثانوي' : 'الرياضيات ٣ ثانوي، مجموعة أ',
      'name_en': draft ? 'Chemistry 1 secondary' : 'Maths 3 secondary, group A',
      'description_ar': 'الحد العام ومجموع متتابعة هندسية منتهية، مع تطبيقات من أسئلة التحصيلي.',
      'description_en': 'The general term and the sum of a finite geometric sequence.',
      'students_count': draft ? 0 : 8,
      'sessions_count': draft ? 0 : 24,
      'type': 'live',
      'is_private': !draft,
      'is_published': !draft,
      'currency': 'SAR',
      'price': draft ? 350 : 8200,
      'final_price': draft ? 350 : 8200,
      'total_hours': 20,
      'expected_hours': 30,
      'category': {'id': 1, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
    };

/// The course page payload (GET /course-profile/41) from a real server payload, retargeted at the demo course.
Map<String, dynamic> t1ProfileJson({bool draft = false}) {
  final raw = jsonDecode(File('test/fixtures/payloads/course_page_staff.json').readAsStringSync()) as Map<String, dynamic>;
  final p = Map<String, dynamic>.from(raw['payload'] as Map);
  final course = Map<String, dynamic>.from(p['course'] as Map)
    ..['id'] = 41
    ..['name_ar'] = t1CourseJson(draft: draft)['name_ar']
    ..['name_en'] = t1CourseJson(draft: draft)['name_en'];
  final page = Map<String, dynamic>.from(p['page'] as Map);
  final counts = Map<String, dynamic>.from(page['counts'] as Map)
    ..['students'] = draft ? 0 : 8
    ..['sessions_total'] = draft ? 0 : 24
    ..['sessions_done'] = draft ? 0 : 18;
  page['counts'] = counts;
  if (draft) {
    page['setup'] = {
      'steps': [
        {'key': 'cover', 'done': true},
        {'key': 'description', 'done': true},
        {'key': 'schedule', 'done': false},
        {'key': 'rules', 'done': false},
        {'key': 'first_exam', 'done': false},
      ],
      'done': 2,
      'total': 5,
    };
  } else {
    page['setup'] = null;
  }
  return {...p, 'course': course, 'page': page};
}

String _iso(DateTime d) => d.toIso8601String();

/// The course's sessions (GET /courses/41/sessions): done ones, one on air, one next.
List<Map<String, dynamic>> t1SessionsJson() {
  final base = DateTime.utc(2026, 11, 15, 16, 30);
  const names = [
    ('الدوال الأسية', 'lecture', 4),
    ('اللوغاريتمات وخصائصها', 'lecture', 3),
    ('المتتابعات الحسابية', 'lecture', 5),
    ('سكشن حل المتتابعات', 'section', 2),
    ('المتتابعات الهندسية', 'lecture', 3),
  ];
  return [
    for (final (i, n) in names.indexed)
      {
        'id': 100 + i,
        'course_id': 41,
        'name': n.$1,
        'description': 'شرح وتطبيقات',
        'type': 'live',
        'track': n.$2,
        'scheduled_at': _iso(base.add(Duration(days: i * 2))),
        'created_at': _iso(base),
        'duration_minutes': 50,
        'order': i,
        'is_live_active': false,
        'total_materials': n.$3,
        'complete_materials': n.$3,
      },
  ];
}

Map<String, FakeHandler> t1CourseRoutes({bool draft = false}) => {
      'GET /api/v1/courses/41': (_) => t1CourseJson(draft: draft),
      'GET /api/v1/courses/41/sessions': (_) => {'items': draft ? <dynamic>[] : t1SessionsJson(), 'total': draft ? 0 : 5},
      'GET /api/v1/course-profile/41': (_) => t1ProfileJson(draft: draft),
      'GET /api/v1/data-lab/config': (_) => {'enabled': false},
    };

TeacherCourse t1Course({bool draft = false}) => TeacherCourse.fromJson(t1CourseJson(draft: draft));

/// The T2 routes plus this group's.
FakeApi t1Api({bool draft = false, Map<String, FakeHandler>? extra}) =>
    t2Api(extra: {...t1CourseRoutes(draft: draft), ...?extra});
