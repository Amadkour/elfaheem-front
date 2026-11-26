// The notebook's routes (WP10) over FakeApi: an in-memory store with versions, idempotent creates and the 409
// note_stale answer, seeded with the CAST demo pages (Faisal's maths notebook with أ. ماجد الشهري).
import 'dart:convert';

import 'package:dio/dio.dart';

import '../fake_api.dart';

class NotebookFakeStore {
  NotebookFakeStore({bool seeded = true, this.disabled = false}) {
    if (seeded) {
      for (final p in demoNotebookPages()) {
        pages[p['id'] as int] = p;
      }
    }
  }

  final pages = <int, Map<String, dynamic>>{};
  bool disabled;

  /// The next PUT answers 409 once (another device saved first).
  bool staleOnce = false;
  int _next = 100;

  static Map<String, dynamic> _body(RequestOptions o) {
    final d = o.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(d) as Map);
    return {};
  }

  static const _off = FakeResponse(403, {
    'detail': {'code': 'feature_disabled', 'message': 'off'},
  });

  Object? list(RequestOptions o) {
    if (disabled) return _off;
    final course = int.tryParse('${o.queryParameters['course_id'] ?? ''}');
    final items = pages.values.where((p) => course == null || p['course_id'] == course).toList()
      ..sort((a, b) => '${b['updated_at']}'.compareTo('${a['updated_at']}'));
    return {'items': items, 'server_time': '2026-11-25T17:00:00', 'has_more': false};
  }

  Object? create(RequestOptions o) {
    if (disabled) return _off;
    final b = _body(o);
    final existing = pages.values.where((p) => p['client_id'] == b['client_id']);
    if (existing.isNotEmpty) return existing.first;
    final id = _next++;
    final p = {
      ...b,
      'id': id,
      'version': 1,
      'shared': false,
      'deleted': false,
      'created_at': '2026-11-25T17:${id % 60}:00',
      'updated_at': '2026-11-25T17:${id % 60}:00',
    };
    pages[id] = p;
    return FakeResponse(201, p);
  }

  Object? update(RequestOptions o) {
    final id = int.parse(o.path.split('/').last);
    final p = pages[id];
    if (p == null) return const FakeResponse(404, {'detail': {'code': 'note_not_found', 'message': 'x'}});
    final b = _body(o);
    if (staleOnce) {
      staleOnce = false;
      p['version'] = (p['version'] as int) + 1;
    }
    if (b['base_version'] != p['version']) {
      return FakeResponse(409, {
        'detail': {'code': 'note_stale', 'message': 'stale', 'page': p},
      });
    }
    p
      ..addAll(b..remove('base_version'))
      ..['version'] = (p['version'] as int) + 1;
    return p;
  }

  Map<String, FakeHandler> get routes => {
    'GET /api/v1/me/notebook/pages': list,
    'POST /api/v1/me/notebook/pages': create,
    'PUT /api/v1/me/notebook/pages/*': update,
    'DELETE /api/v1/me/notebook/pages/*': (o) {
      pages.remove(int.parse(o.path.split('/').last));
      return {'deleted': true};
    },
    'GET /api/v1/me/notebook/summary': (_) => {
      'items': [
        {'subject_id': 3, 'course_id': 41, 'pages': pages.length, 'updated_at': '2026-11-25T17:00:00'},
      ],
    },
  };
}

/// The reference's notebook (SubjectProfile `pv-nb`), newest first: today's live class, then lesson 1.
List<Map<String, dynamic>> demoNotebookPages() => [
  {
    'id': 2,
    'client_id': 'demo_page_two',
    'subject_id': 3,
    'course_id': 41,
    'lesson_id': 7,
    'title': 'حصة اليوم، مع أ. ماجد',
    'kind': 'typed',
    'blocks': [
      {'t': 'h', 'x': 'الدوال الأسية'},
      {'t': 'p', 'x': 'ص = ٢^س تتضاعف بسرعة. راجع مثال البكتيريا.'},
      {'t': 'sticky', 'x': 'واجب: تمارين صفحة ٢٨ من ١ إلى ٦ قبل الثلاثاء'},
    ],
    'ink': null,
    'shared': false,
    'version': 3,
    'created_at': '2026-11-25T16:40:00',
    'updated_at': '2026-11-25T16:55:00',
    'deleted': false,
  },
  {
    'id': 1,
    'client_id': 'demo_page_one',
    'subject_id': 3,
    'course_id': 41,
    'lesson_id': 6,
    'title': 'الدرس ١، المجال والمدى',
    'kind': 'typed',
    'blocks': [
      {'t': 'h', 'x': 'الدوال'},
      {'t': 'hl', 'x': 'الدالة: كل س لها ص وحدة بس.'},
      {'t': 'p', 'x': 'اختبار الخط الرأسي: إذا قطع الرسم في أكثر من نقطة، ما هي دالة.'},
      {'t': 'eq', 'x': 'د(س) = ٢س + ٣ ← د(٤) = ١١'},
    ],
    'ink': null,
    'shared': false,
    'version': 1,
    'created_at': '2026-11-22T17:00:00',
    'updated_at': '2026-11-22T17:20:00',
    'deleted': false,
  },
];
