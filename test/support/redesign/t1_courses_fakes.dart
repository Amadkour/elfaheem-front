// Redesign group T1 (teacher: My courses, My students, Submissions, Reviews): demo data from docs/redesign/CAST.md
// (أ. ماجد الشهري, the course "الرياضيات ٣ ث، أ", the students راكان الحربي, فيصل العنزي, ليث الدوسري) on top of
// FakeApi, for the layout tests and the review renders.
import 'package:dio/dio.dart';

import '../../ui/master_detail/md_roles_support.dart';
import '../fake_api.dart';
import 't2_fakes.dart';

Map<String, dynamic> _course(
  int id,
  String ar,
  String en, {
  required String type,
  required double price,
  required int students,
  required int sessions,
  double? rating,
  bool published = true,
  String? category,
}) =>
    {
      'id': id,
      'name_ar': ar,
      'name_en': en,
      'image_url': '',
      'type': type,
      'is_published': published,
      'org': null,
      'students_count': students,
      'sessions_count': sessions,
      'fees': price,
      'price': price,
      'currency': 'SAR',
      'total_hours': 20,
      'progress': 0,
      'expected_hours': 30,
      if (category != null) 'category': {'id': 1, 'name_ar': category, 'name_en': category == 'رياضيات' ? 'Maths' : 'Physics'},
      if (rating != null) 'rate': {'ratings': <dynamic>[], 'total': 7, 'average': rating},
    };

/// The teacher's five courses (GET /my-courses): four published, one draft.
List<Map<String, dynamic>> t1TeacherCourses() => [
      _course(41, 'الرياضيات ٣ ثانوي، مجموعة أ', 'Maths 3 secondary, group A',
          type: 'live', price: 450, students: 8, sessions: 24, rating: 4.8, category: 'رياضيات'),
      _course(42, 'الفيزياء ٢ ثانوي', 'Physics 2 secondary',
          type: 'live', price: 390, students: 9, sessions: 18, rating: 4.9, category: 'فيزياء'),
      _course(43, 'القدرات: الكمي المكثّف', 'Qudurat: intensive quantitative',
          type: 'recorded', price: 220, students: 10, sessions: 36, rating: 4.7, category: 'رياضيات'),
      _course(44, 'التحصيلي: رياضيات', 'Tahsili: maths',
          type: 'recorded', price: 180, students: 47, sessions: 30, rating: 4.7, category: 'رياضيات'),
      _course(45, 'كيمياء ١ ثانوي', 'Chemistry 1 secondary',
          type: 'live', price: 350, students: 0, sessions: 0, published: false, category: 'فيزياء'),
    ];

const _students = ['راكان الحربي', 'فيصل العنزي', 'ليث الدوسري', 'نواف القحطاني', 'سلمان الغامدي', 'تركي السبيعي'];
const _usernames = ['rakan', 'faisal', 'laith', 'nawaf', 'salman', 'turki'];
const _courseNames = [
  ('الرياضيات ٣ ث', 'Maths 3 S'),
  ('القدرات', 'Qudurat'),
  ('الفيزياء ٢ ث', 'Physics 2 S'),
  ('الرياضيات ٣ ث', 'Maths 3 S'),
];

/// An entities page whose people and courses carry the cast.
Object? _cast(Object? page) {
  if (page is! Map || page['items'] is! List) return page;
  final items = <Map<String, dynamic>>[];
  for (final (i, raw) in (page['items'] as List).indexed) {
    final r = Map<String, dynamic>.from(raw as Map);
    if (r['student'] is Map) {
      r['student'] = {...Map<String, dynamic>.from(r['student'] as Map), 'name': _students[i % _students.length], 'username': _usernames[i % _usernames.length]};
    }
    if (r['course'] is Map) {
      final n = _courseNames[i % _courseNames.length];
      r['course'] = {...Map<String, dynamic>.from(r['course'] as Map), 'name_ar': n.$1, 'name_en': n.$2};
    }
    items.add(r);
  }
  return {...Map<String, dynamic>.from(page), 'items': items};
}

/// The routes of the four teacher spaces and the course panel.
Map<String, FakeHandler> t1CoursesRoutes() {
  final roles = roleRoutes(teacherId: 7);
  return {
    'GET /api/v1/my-courses': (o) => {
          'items': t1TeacherCourses(),
          'total': 5,
          'scope': 'all',
          'scopes': <dynamic>[],
        },
    'GET /api/v1/entities/*': (RequestOptions o) => _cast(roles['GET /api/v1/entities/*']!(o)),
  };
}

FakeApi t1CoursesApi({Map<String, FakeHandler>? extra}) => t2Api(extra: {...t1CoursesRoutes(), ...?extra});
