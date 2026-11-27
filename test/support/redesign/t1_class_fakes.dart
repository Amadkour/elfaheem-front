// Redesign group T1, section Class (attendance, announcements, rules, team, archive, path, students, nudge): demo
// data from docs/redesign/CAST.md (أ. ماجد الشهري, the course "الرياضيات ٣ ث، أ", a boys' group) on top of FakeApi, for
// the layout tests and the review renders.
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_api.dart';

const t1CourseId = 41;
const t1CourseAr = 'الرياضيات ٣ ث، أ';
const t1CourseEn = 'Maths 3 S, A';

/// The eight boys of the group: id, Arabic name.
const t1Boys = <(int, String)>[
  (101, 'راكان الحربي'),
  (102, 'فيصل العنزي'),
  (103, 'ليث الدوسري'),
  (104, 'سلمان القرني'),
  (105, 'نايف الشمري'),
  (106, 'عبدالله الغامدي'),
  (107, 'تركي السبيعي'),
  (108, 'ماجد العتيبي'),
];

String t1Iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String().replaceAll('Z', '');

/// One row of GET /api/v1/courses/{id}/students.
Map<String, dynamic> t1StudentRow(int i) {
  const progress = [92.0, 21.0, 74.0, 38.0, 100.0, 66.0, 18.0, 81.0];
  const lessons = [20, 5, 16, 9, 24, 15, 4, 19];
  final low = progress[i] < 40;
  return {
    'id': t1Boys[i].$1,
    'name': t1Boys[i].$2,
    'gmail': 'student${t1Boys[i].$1}@example.test',
    'enrolled_at': t1Iso(Duration(days: 60 + i)),
    'status': 'active',
    'progress_percentage': progress[i],
    'lessons_done': lessons[i],
    'lessons_total': 24,
    'last_active_at': t1Iso(Duration(days: low ? 14 : 0, hours: 1 + i)),
    'exam_avg': [94.0, 58.0, 80.0, null, 90.0, 72.0, 40.0, 85.0][i],
    'state': progress[i] >= 100 ? 'completed' : (low ? 'low' : 'active'),
    'at_risk': low,
    'risk': low ? {'code': 'no_activity', 'days': 14} : null,
    'parent_count': i.isEven ? 1 : 0,
    'last_nudged_at': i == 3 ? t1Iso(const Duration(hours: 3)) : null,
    'can_nudge': i != 3,
  };
}

Map<String, dynamic> t1StudentsPage() => {
      'items': [for (var i = 0; i < t1Boys.length; i++) t1StudentRow(i)],
      'total': 8,
      'avg_progress': 68.0,
      'completed_count': 1,
      'counts': {'all': 8, 'active': 6, 'low': 2, 'inactive': 0, 'completed': 1},
      'summary': {'enrolled': 8, 'active_week': 6, 'avg_progress': 68.0, 'at_risk': 3, 'completed': 1, 'low_nudgeable': 3, 'low_with_parent': 2},
      'filter': 'all',
      'sort': 'name',
      'rule': {'nudge_cooldown_hours': 24},
      'nudge_enabled': true,
    };

/// GET /api/v1/sessions/{courseId}/course_attendance: two lessons, the first one the day before.
List<Map<String, dynamic>> t1CourseAttendance() => [
      for (final (i, name) in ['المتتابعات الحسابية', 'المتتابعات الهندسية'].indexed)
        {
          'session': {
            'id': 301 + i,
            'name': name,
            'scheduled_at': DateTime.now().toUtc().subtract(Duration(days: 1 - i)).toIso8601String().replaceAll('Z', ''),
            'type': 'live',
          },
          'students': [
            for (var k = 0; k < t1Boys.length; k++)
              {
                'student_id': t1Boys[k].$1,
                'student_name': t1Boys[k].$2,
                'student_image': null,
                'is_attended': i == 0 ? ![1, 3, 6].contains(k) : k < 6,
                'join_date': t1Iso(const Duration(minutes: 100)),
                'leave_date': t1Iso(const Duration(minutes: 50)),
              },
          ],
        },
    ];

Map<String, dynamic> t1Person(int id, String name) => {'id': id, 'name': name};

/// The course-profile payload of the teacher (instructor view), enough for the Team, Archive and Announcements tabs.
Map<String, dynamic> t1ProfilePayload() => {
      'course': {'id': t1CourseId, 'name_ar': t1CourseAr, 'name_en': t1CourseEn, 'kind': 'personal', 'teacher': t1Person(7, 'أ. ماجد الشهري')},
      'role': 'instructor',
      'caps': {
        'view_material': true,
        'manage_lecture': true,
        'manage_section': true,
        'attend_lecture': true,
        'attend_section': true,
        'view_attendance': true,
        'view_all_attendance': true,
        'manage_staff': true,
        'manage_certificates': true,
        'manage_archive': true,
        'approve_archive': true,
        'live': true,
        'announce': true,
        'view_versions': true,
        'archive_course': false,
        'course_settings': true,
      },
      'version': {'run_id': 2, 'past': false},
      'versions': [
        {'id': 2, 'status': 'open', 'current': true, 'students': 8, 'passed': 0, 'term': {'id': 2, 'year_label': '١٤٤٧', 'kind': 'term1'}},
        {'id': 1, 'status': 'archived', 'current': false, 'students': 9, 'passed': 8, 'term': {'id': 1, 'year_label': '١٤٤٦', 'kind': 'term2'}},
      ],
      'announcements': [
        {
          'id': 1,
          'track': 'all',
          'title': 'اختبار الوحدة الثالثة الثلاثاء الجاي',
          'body': 'الاختبار إلكتروني ومدته ٤٠ دقيقة ويشمل الدوال الأسية واللوغاريتمات والمتتابعات. راجعوا ملخص الوحدة في الحصة ٢.',
          'pinned': true,
          'created_at': t1Iso(const Duration(days: 2)),
          'author': t1Person(7, 'أ. ماجد الشهري'),
          'can_delete': true,
        },
        {
          'id': 2,
          'track': 'section',
          'title': 'تمارين إضافية قبل السكشن',
          'body': 'حليت لكم ١٠ تمارين على المتتابعات ورفعتها في مواد الحصة ٥، حلوها قبل الخميس.',
          'pinned': false,
          'created_at': t1Iso(const Duration(days: 4)),
          'author': t1Person(7, 'أ. ماجد الشهري'),
          'can_delete': true,
        },
        {
          'id': 3,
          'track': 'all',
          'title': 'تسجيلات الحصص صارت مع ترجمة نصية',
          'body': 'تقدرون تقرؤون الشرح مع الفيديو من أي حصة مسجلة.',
          'pinned': false,
          'created_at': t1Iso(const Duration(days: 7)),
          'author': t1Person(7, 'أ. ماجد الشهري'),
          'can_delete': true,
        },
      ],
      'closed': false,
      'read_only': false,
      'archive': null,
      'archive_policy': {'mode': 'request', 'days': 180, 'code': 'AB12CD', 'open_access': true},
      'tracks': {'lecture': [], 'section': []},
      'staff': {
        'instructor': t1Person(7, 'أ. ماجد الشهري'),
        'assistants': [
          {'user': t1Person(12, 'أ. سعود العتيبي'), 'lecture_edit': true, 'lecture_attendance': false},
          {'user': t1Person(13, 'أ. فهد القحطاني'), 'lecture_edit': false, 'lecture_attendance': true},
        ],
      },
      'certificates': [],
      'analytics': {'lectures': 24, 'sections': 0, 'students': 8, 'avg_progress': 68.0, 'completed': 1, 'attendance_rate': 87.0, 'at_risk': 3},
    };

/// GET …/rules.
Map<String, dynamic> t1Rules() => {
      'absence_limit': 4,
      'grade_breakdown': [
        {'label': 'الاختبار النهائي', 'weight': 40},
        {'label': 'الاختبارات القصيرة', 'weight': 30},
        {'label': 'الواجبات', 'weight': 20},
        {'label': 'الحضور', 'weight': 10},
      ],
      'late_policy': 'خصم ١٠٪ لكل يوم',
      'items': [
        {'id': 1, 'text': 'الأسئلة تُرسل في المحادثة الخاصة مع المعلم', 'order': 0},
        {'id': 2, 'text': 'تسليم الواجب قبل الحصة التالية', 'order': 1},
      ],
      'can_edit': true,
    };

/// GET …/sections.
Map<String, dynamic> t1Sections() => {
      'mode': 'teacher_assigns',
      'mode_source': 'course',
      'source': 'course',
      'can_pick': false,
      'can_edit': true,
      'unassigned': 2,
      'groups': [
        {'group_no': 1, 'label': 'السكشن أ', 'ta': t1Person(12, 'أ. سعود العتيبي'), 'students': 3},
        {'group_no': 2, 'label': 'السكشن ب', 'ta': t1Person(13, 'أ. فهد القحطاني'), 'students': 3},
        {'group_no': 3, 'label': 'المعمل', 'ta': null, 'students': 0},
      ],
      'students': [
        for (final (i, (id, name)) in t1Boys.indexed) {'user': t1Person(id, name), 'group_no': i < 3 ? 1 : (i < 6 ? 2 : null), 'set_by': 'teacher'},
      ],
    };

Map<String, dynamic> _rm(int id, String ar, String en, {String? state, int students = 0}) => {
      'id': id,
      'name_ar': ar,
      'name_en': en,
      'is_published': true,
      'state': state,
      'level': 'intermediate',
      'tags': ['math'],
      'students_count': students,
    };

/// GET /api/v1/roadmap/courses/41: what comes before and after.
Map<String, dynamic> t1Roadmap() => {
      'course': _rm(t1CourseId, t1CourseAr, t1CourseEn, students: 8),
      'previous': [_rm(31, 'الرياضيات ٢ ثانوي', 'Maths 2', students: 9), _rm(32, 'أساسيات الدوال', 'Function basics', students: 12)],
      'next': [_rm(51, 'تحصيلي رياضيات: مراجعة نهائية', 'Tahsili maths: final review', students: 47), _rm(52, 'القدرات: الكمي المكثف', 'Qudurat: intensive quantitative', students: 10)],
      'prerequisites': [
        {'id': 31, 'name_ar': 'الرياضيات ٢ ثانوي', 'name_en': 'Maths 2'},
        {'id': 32, 'name_ar': 'أساسيات الدوال', 'name_en': 'Function basics'},
      ],
      'can_edit': true,
    };

Map<String, FakeHandler> t1Routes() => {
      'GET /api/v1/courses/$t1CourseId/students': (_) => t1StudentsPage(),
      'POST /api/v1/courses/$t1CourseId/students/nudge': (_) => {'sent': 3, 'skipped': 0},
      'GET /api/v1/sessions/$t1CourseId/course_attendance': (_) => t1CourseAttendance(),
      'GET /api/v1/course-profile/$t1CourseId/announcements': (_) => {'items': t1ProfilePayload()['announcements']},
      'GET /api/v1/course-profile/$t1CourseId/archive/requests': (_) => {
            'items': [
              {'id': 1, 'student': t1Person(105, 'نايف الشمري'), 'reason': 'يبي يراجع الوحدة الأولى قبل التحصيلي'},
              {'id': 2, 'student': t1Person(106, 'عبدالله الغامدي'), 'reason': 'غاب عن الحصة ١٢'},
            ]
          },
      'GET /api/v1/course-profile/$t1CourseId/rules': (_) => t1Rules(),
      'GET /api/v1/course-profile/$t1CourseId/sections': (_) => t1Sections(),
      'GET /api/v1/roadmap/courses/$t1CourseId': (_) => t1Roadmap(),
      'GET /api/v1/roadmap/courses/$t1CourseId/candidates': (_) => [
            _rm(61, 'فيزياء ٣ ثانوي', 'Physics 3'),
            _rm(62, 'كيمياء ٣ ثانوي', 'Chemistry 3'),
          ],
    };

/// Installs [api] (the T1 routes plus [extra]) for the current test and signs the demo teacher in.
Future<MyAuthProvider> t1SetUp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'ماجد الشهري', 'gmail': 'teacher@example.test', 'role': 'teacher'});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

FakeApi t1Api({Map<String, FakeHandler>? extra}) =>
    FakeApi({...t1Routes(), ...?extra}, latency: kDebugMode ? const Duration(milliseconds: 10) : Duration.zero);
