// Shared set-up of the master-detail tests (D-290): a FakeApi route for every `/api/v1/entities/...` call, answered
// from the REAL server responses (test/fixtures/payloads/entity_*.json) with realistic Arabic / English names, varied
// enrollment states and dates relative to now, so layouts and renders see what the app will see.
import 'package:dio/dio.dart';

import '../../support/fake_api.dart';
import '../admin_ds/people_support.dart' show peopleUser;

const mdCourses = <(String, String)>[
  ('أساسيات البرمجة بلغة بايثون', 'Python Programming Basics'),
  ('الرياضيات للمرحلة الثانوية', 'High-School Mathematics'),
  ('مقدمة في الفيزياء الحديثة', 'Introduction to Modern Physics'),
  ('تصميم واجهات المستخدم', 'UI Design Fundamentals'),
  ('المحادثة باللغة الإنجليزية', 'Conversational English'),
  ('الكيمياء العضوية', 'Organic Chemistry'),
];

const mdTeachers = ['د. خالد منصور', 'Nadia Farouk', 'أ. هبة السيد'];
const mdStudents = ['سارة أحمد', 'Omar Khaled', 'ليلى محمود', 'Youssef Ali', 'منى إبراهيم', 'Karim Nabil', 'هدى سمير'];

String _iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');
String _ago(Duration d) => _iso(DateTime.now().toUtc().subtract(d));

Map<String, dynamic> _p(String name) => Map<String, dynamic>.from(payload('$name.json') as Map);

Map<String, dynamic> mdCategoryRef(int id) =>
    {'id': id, 'name_ar': id == 3 ? 'العلوم' : 'علوم الحاسب', 'name_en': id == 3 ? 'Science' : 'Computer Science'};

Map<String, dynamic> mdTeacherRef(int i) =>
    {'id': 20 + i, 'name': mdTeachers[i % mdTeachers.length], 'username': 'teacher${i + 1}', 'image_url': null};

Map<String, dynamic> mdCourseRef(int i) => {
      'id': 40 + i,
      'name_ar': mdCourses[i % mdCourses.length].$1,
      'name_en': mdCourses[i % mdCourses.length].$2,
      'image_url': null,
      'category': mdCategoryRef(i.isEven ? 5 : 3),
      'teacher': mdTeacherRef(i),
    };

Map<String, dynamic> mdStudentRef(int i) =>
    {'id': 100 + i, 'name': mdStudents[i % mdStudents.length], 'username': 'student${i + 1}', 'image_url': null};

Map<String, dynamic> _page(List<Map<String, dynamic>> items, RequestOptions o) {
  final size = int.tryParse(o.uri.queryParameters['size'] ?? '') ?? 20;
  final page = int.tryParse(o.uri.queryParameters['page'] ?? '') ?? 1;
  final from = (page - 1) * size;
  final shown = from >= items.length ? <Map<String, dynamic>>[] : items.skip(from).take(size).toList();
  return {'items': shown, 'total': items.length, 'page': page, 'size': size, 'pages': (items.length / size).ceil().clamp(1, 999)};
}

/// The enrollment block of a row in each state.
Map<String, dynamic> _enrollment(int i, Map<String, dynamic> base) {
  final e = Map<String, dynamic>.from(base)..remove('course')..remove('student');
  final states = ['in_progress', 'completed', 'withdrawn', 'expired', 'in_progress', 'pending'];
  final state = states[i % states.length];
  e
    ..['enrollment_id'] = 500 + i
    ..['state'] = state
    ..['enrolled_at'] = _ago(Duration(days: 40 + i * 9))
    ..['progress'] = switch (state) { 'completed' => 100.0, 'withdrawn' => 18.0, 'expired' => 35.0, 'pending' => 0.0, _ => i == 0 ? 64.0 : 12.0 }
    ..['first_activity_at'] = state == 'pending' ? null : _ago(Duration(days: 38 + i * 9))
    ..['last_activity_at'] = switch (state) { 'pending' => null, 'in_progress' => _ago(Duration(days: i == 0 ? 2 : 16, hours: 3)), _ => _ago(Duration(days: 12 + i)) }
    ..['completed_at'] = state == 'completed' ? _ago(const Duration(days: 6)) : null
    ..['withdrawn_at'] = state == 'withdrawn' ? _ago(const Duration(days: 9)) : null
    ..['withdrawal_reason_code'] = state == 'withdrawn' ? 'price' : null
    ..['withdrawal_reason'] = state == 'withdrawn' ? 'The monthly fee went up after the first term.' : null
    ..['expected_end_at'] = state == 'expired' ? _ago(const Duration(days: 3)) : _iso(DateTime.now().toUtc().add(Duration(days: 60 + i)));
  return e;
}

Map<String, dynamic> studentSummary(int id) {
  final j = _p('entity_student');
  final user = peopleUser((id - 100).clamp(0, 999), 'student');
  j['id'] = id;
  (j['header'] as Map)
    ..['id'] = id
    ..['name'] = user['name']
    ..['username'] = user['username'] ?? 'student${id - 99}'
    ..['email'] = user['gmail']
    ..['phone'] = user['phone']
    ..['country'] = 'EG'
    ..['created_at'] = _ago(const Duration(days: 220))
    ..['last_login'] = _ago(const Duration(days: 2, hours: 5));
  (j['stats'] as Map)
    ..['enrolled'] = 6
    ..['in_progress'] = 2
    ..['completed'] = 1
    ..['withdrawn'] = 1
    ..['expired'] = 1
    ..['pending'] = 1
    ..['avg_progress'] = 46.0
    ..['last_activity_at'] = _ago(const Duration(days: 2, hours: 3));
  j['badges'] = [
    {'code': 'at_risk', 'level': 'bad', 'value': 1},
  ];
  return j;
}

List<Map<String, dynamic>> studentCourses() {
  final base = (_p('entity_student_courses')['items'] as List).cast<Map>();
  return [
    for (var i = 0; i < 6; i++) {'course': mdCourseRef(i), ..._enrollment(i, Map<String, dynamic>.from(base[i % base.length]))},
  ];
}

Map<String, dynamic> courseSummary(int id, {bool learner = false}) {
  final j = _p(learner ? 'entity_course_learner' : 'entity_course');
  final i = (id - 40).clamp(0, 99);
  final ref = mdCourseRef(i);
  j['id'] = id;
  (j['header'] as Map)
    ..['id'] = id
    ..['name_ar'] = ref['name_ar']
    ..['name_en'] = ref['name_en']
    ..['category'] = ref['category']
    ..['teacher'] = ref['teacher'];
  final stats = j['stats'] as Map;
  if (!learner) {
    stats
      ..['enrolled'] = 148
      ..['in_progress'] = 96
      ..['completed'] = 31
      ..['withdrawn'] = 14
      ..['expired'] = 7
      ..['completion_rate'] = 22.6
      ..['avg_progress'] = 47.0
      ..['rating_avg'] = 4.6
      ..['rating_count'] = 52
      ..['favorites'] = 63
      ..['sessions'] = 24
      ..['materials'] = 87
      ..['withdrawal_reasons'] = [
        {'code': 'time', 'count': 6},
        {'code': 'price', 'count': 4},
        {'code': 'content_mismatch', 'count': 3},
        {'code': 'unknown', 'count': 1},
      ]
      ..['revenue'] = {'amount': 41250.0, 'currency': 'EGP'};
    final trend = (stats['trend'] as List).cast<Map>();
    const counts = [3, 5, 4, 8, 6, 9, 12, 10, 14, 11, 16, 13];
    for (var k = 0; k < trend.length; k++) {
      trend[k]['count'] = counts[k % counts.length];
    }
    j['badges'] = [
      {'code': 'trending', 'level': 'good', 'value': null},
    ];
  }
  return j;
}

List<Map<String, dynamic>> courseStudents() {
  final base = (_p('entity_course_students')['items'] as List).cast<Map>();
  return [
    for (var i = 0; i < 7; i++) {'student': mdStudentRef(i), ..._enrollment(i, Map<String, dynamic>.from(base[i % base.length]))},
  ];
}

Map<String, dynamic> teacherSummary(int id) {
  final j = _p('entity_teacher');
  final ref = mdTeacherRef((id - 20).clamp(0, 99));
  j['id'] = id;
  (j['header'] as Map)
    ..['id'] = id
    ..['name'] = ref['name']
    ..['username'] = ref['username']
    ..['bio'] = 'مدرس برمجة وعلوم حاسب منذ عشر سنوات، يحب المشاريع العملية.'
    ..['specialization'] = mdCategoryRef(5);
  return j;
}

List<Map<String, dynamic>> courseRows() {
  final base = (_p('entity_teacher_courses')['items'] as List).cast<Map>();
  return [
    for (var i = 0; i < 4; i++)
      {...Map<String, dynamic>.from(base[i % base.length]), 'course': mdCourseRef(i), 'students': 148 - i * 31, 'completion_rate': 22.6 + i * 5},
  ];
}

List<Map<String, dynamic>> personRows(String kind) {
  final base = (_p(kind == 'teacher' ? 'entity_category_teachers' : 'entity_teacher_students')['items'] as List).cast<Map>();
  return [
    for (var i = 0; i < 5; i++)
      {
        ...Map<String, dynamic>.from(base[i % base.length]),
        kind: kind == 'teacher' ? mdTeacherRef(i) : mdStudentRef(i),
        if (kind != 'teacher') 'last_activity_at': i == 3 ? null : _ago(Duration(days: i * 3, hours: 2)),
        if (kind != 'teacher') 'avg_progress': 72.0 - i * 11,
      },
  ];
}

Map<String, dynamic> categorySummary(int id) {
  final j = _p('entity_category');
  j['id'] = id;
  (j['header'] as Map)
    ..['id'] = id
    ..['name_ar'] = mdCategoryRef(id)['name_ar']
    ..['name_en'] = mdCategoryRef(id)['name_en']
    ..['description'] = 'Programming, data and the craft of software.';
  j['stats'] = {
    ...(j['stats'] as Map),
    'top_courses': [
      for (var i = 0; i < 3; i++) {'course': mdCourseRef(i), 'students': 148 - i * 40},
    ],
  };
  return j;
}

List<Map<String, dynamic>> timeline() {
  final base = (_p('entity_timeline')['items'] as List).cast<Map>();
  final titles = ['المحاضرة 7: الدوال', 'Lists and loops', 'المحاضرة 5: الشروط'];
  var t = 0;
  return [
    for (var i = 0; i < 9; i++)
      () {
        final e = Map<String, dynamic>.from(base[i % base.length]);
        final d = Map<String, dynamic>.from(e['data'] as Map);
        if (d.containsKey('title')) d['title'] = e['type'] == 'exam_submitted' ? 'Quiz 2: Functions' : titles[t++ % titles.length];
        return {...e, 'at': _ago(Duration(days: i * 4, hours: 3)), 'data': d};
      }(),
  ];
}

/// Answers every `/api/v1/entities/...` request.
Object? entitiesHandler(RequestOptions o) {
  final segs = o.uri.pathSegments;
  final at = segs.lastIndexOf('entities');
  final rest = segs.sublist(at + 1);
  final kind = rest[0];
  final id = int.parse(rest[1]);
  if (rest.length == 2) {
    return switch (kind) {
      'students' => studentSummary(id),
      'courses' => courseSummary(id),
      'teachers' => teacherSummary(id),
      _ => categorySummary(id),
    };
  }
  final section = rest[2];
  final List<Map<String, dynamic>> items = switch ((kind, section)) {
    ('students', 'courses') when rest.length > 3 => timeline(),
    ('students', 'courses') => studentCourses(),
    ('students', 'payments') => [
        for (final (k, p) in (_p('entity_student_payments')['items'] as List).cast<Map>().take(4).indexed)
          {...Map<String, dynamic>.from(p), 'course': mdCourseRef(k), 'amount': 450.0 + k * 150, 'paid_at': _ago(Duration(days: 30 * k + 4))},
      ],
    ('students', 'subscriptions') => [
        for (final (k, s) in (_p('entity_student_subscriptions')['items'] as List).cast<Map>().take(4).indexed)
          {...Map<String, dynamic>.from(s), 'course': mdCourseRef(k), 'occurred_at': _ago(Duration(days: 30 * k + 4))},
      ],
    ('courses', 'students') => courseStudents(),
    ('teachers', 'courses') || ('categories', 'courses') => courseRows(),
    ('categories', 'teachers') => personRows('teacher'),
    _ => personRows('student'),
  };
  final search = (o.uri.queryParameters['search'] ?? '').toLowerCase();
  final state = o.uri.queryParameters['state'];
  final filtered = items.where((j) {
    if (state != null && j['state'] != state) return false;
    if (search.isEmpty) return true;
    final named = (j['course'] ?? j['student'] ?? j['teacher']) as Map?;
    final text = '${named?['name'] ?? ''} ${named?['name_ar'] ?? ''} ${named?['name_en'] ?? ''}'.toLowerCase();
    return text.contains(search);
  }).toList();
  return _page(filtered, o);
}

Map<String, FakeHandler> entityRoutes() => {'GET /api/v1/entities/*': entitiesHandler};
