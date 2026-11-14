// Phase 7 of the master-detail redesign: the FakeApi routes of the role lists and a learner's course, answered from
// the REAL server responses (test/fixtures/payloads/entity_*.json, dumped from tests/org_v2/e2e_entities_roles.py) with
// the same realistic names the admin tests use.
import 'package:dio/dio.dart';

import '../../support/fake_api.dart';
import 'md_support.dart';

Map<String, dynamic> _p(String name) => Map<String, dynamic>.from(payload('$name.json') as Map);

List<Map<String, dynamic>> _items(String name) =>
    [for (final i in _p(name)['items'] as List) Map<String, dynamic>.from(i as Map)];

String _iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');
String _ago(int days) => _iso(DateTime.now().toUtc().subtract(Duration(days: days)));
String _in(int days) => _iso(DateTime.now().toUtc().add(Duration(days: days)));

Map<String, dynamic> pageOf(List<Map<String, dynamic>> items, RequestOptions o) {
  final size = int.tryParse(o.uri.queryParameters['size'] ?? '') ?? 20;
  final page = int.tryParse(o.uri.queryParameters['page'] ?? '') ?? 1;
  final from = (page - 1) * size;
  final shown = from >= items.length ? <Map<String, dynamic>>[] : items.skip(from).take(size).toList();
  return {'items': shown, 'total': items.length, 'page': page, 'size': size, 'pages': (items.length / size).ceil().clamp(1, 999)};
}

/// The teacher's students: some need attention.
List<Map<String, dynamic>> teacherStudents({int n = 7}) {
  final base = _items('entity_teacher_students_attention');
  return [
    for (var i = 0; i < n; i++)
      {
        ...base[i % base.length],
        'student': mdStudentRef(i),
        'courses': 1 + i % 3,
        'avg_progress': 88.0 - i * 13,
        'last_activity_at': _ago(i * 6 + 1),
        'attention': i >= 3,
      },
  ];
}

List<Map<String, dynamic>> gradeRows({int n = 6}) {
  final base = _items('entity_grades');
  const titles = ['اختبار الوحدة الأولى', 'Midterm', 'Quiz 3', 'واجب التصميم', 'Final project', 'اختبار قصير'];
  return [
    for (var i = 0; i < n; i++)
      {
        ...base[i % base.length],
        'id': 700 + i,
        'title': titles[i % titles.length],
        'source': i == 3 ? 'assignment' : (i.isEven ? 'exam' : 'engine'),
        'course': mdCourseRef(i % 3),
        'student': mdStudentRef(i),
        'at': _ago(i * 4 + 1),
        'percentage': i == 2 ? null : 92.0 - i * 11,
        'score': i == 2 ? null : 18.0 - i,
        'max_score': i == 2 ? null : 20.0,
        'passed': i == 2 ? null : i < 4,
        'held': i == 2,
        'needs_review': false,
      },
  ];
}

List<Map<String, dynamic>> reviewRows({int n = 5}) {
  final base = _items('entity_reviews');
  const texts = ['شرح واضح جداً ومنظم', 'Great pace, loved the examples.', null, 'The second unit moved too fast for me.', 'ممتاز'];
  return [
    for (var i = 0; i < n; i++)
      {...base[i % base.length], 'id': 800 + i, 'value': 5 - i % 4, 'review': texts[i % texts.length], 'at': _ago(i * 3 + 1),
        'course': mdCourseRef(i % 3), 'student': mdStudentRef(i)},
  ];
}

List<Map<String, dynamic>> lessonRows() {
  final base = _items('entity_lessons');
  const names = ['المحاضرة الأولى: مقدمة', 'Lecture 2: Variables', 'Lecture 3: Control flow', 'المحاضرة الرابعة: الدوال', 'Lecture 5: Modules'];
  const states = ['done', 'done', 'in_progress', 'upcoming', 'open'];
  return [
    for (var i = 0; i < names.length; i++)
      {...base[i % base.length], 'id': 900 + i, 'name': names[i], 'state': states[i], 'materials': i == 3 ? 0 : 4,
        'completed': switch (states[i]) { 'done' => 4, 'in_progress' => 2, _ => 0 }, 'attended': i < 2,
        'scheduled_at': i == 3 ? _in(2) : null},
  ];
}

List<Map<String, dynamic>> deadlineRows() {
  final base = _items('entity_deadlines');
  Map<String, dynamic> row(String type, String title, int days) =>
      {...base.first, 'type': type, 'id': days, 'title': title, 'at': _in(days), 'opens_at': null};
  return [row('session', 'Lecture 4: Functions', 1), row('exam', 'اختبار منتصف الفصل', 5), row('assignment', 'Project draft', 9), row('access_end', '', 60)];
}

/// A learner's own course: [withdrawn] draws the left enrollment with its date and reason.
Map<String, dynamic> learnerCourse(int id, {bool withdrawn = false, double progress = 64}) {
  final j = courseSummary(id, learner: true);
  final stats = j['stats'] as Map;
  final mine = Map<String, dynamic>.from(stats['mine'] as Map);
  mine
    ..['state'] = withdrawn ? 'withdrawn' : 'in_progress'
    ..['progress'] = withdrawn ? 18.0 : progress
    ..['enrolled_at'] = _ago(60)
    ..['last_activity_at'] = _ago(2)
    ..['expected_end_at'] = withdrawn ? null : _in(60)
    ..['withdrawn_at'] = withdrawn ? _ago(9) : null
    ..['withdrawal_reason_code'] = withdrawn ? 'time' : null
    ..['withdrawal_reason'] = null;
  stats
    ..['mine'] = mine
    ..['student_id'] = 77;
  j['sections'] = const ['deadlines', 'lessons', 'grades', 'timeline'];
  return j;
}

/// The routes of the role lists, on top of the admin's [entitiesHandler].
Map<String, FakeHandler> roleRoutes({bool withdrawn = false, int teacherId = 21, int studentId = 77}) => {
      'GET /api/v1/entities/*': (o) {
        final path = o.uri.path;
        if (path.endsWith('/students') && path.contains('/teachers/')) return pageOf(teacherStudents(), o);
        if (path.endsWith('/submissions') || path.endsWith('/grades')) return pageOf(gradeRows(), o);
        if (path.endsWith('/reviews')) return pageOf(reviewRows(), o);
        if (path.endsWith('/lessons')) return pageOf(lessonRows(), o);
        if (path.endsWith('/deadlines')) return pageOf(withdrawn ? [] : deadlineRows(), o);
        return entitiesHandler(o);
      },
    };
