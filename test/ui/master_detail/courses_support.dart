// Shared set-up of the courses tests and renders (D-290 phase 5): GET /api/v1/admin/courses answered like the real route
// (search, publishing, sort, numbered pages) from the REAL row (test/fixtures/payloads/admin_courses.json) with
// realistic names, every status, covers absent, and the course's detail over md_support.dart.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../support/fake_api.dart';
import 'md_support.dart';

/// The `md_p5_*` strings live beside the code until the merge: tests read them from there.
void loadP5Keys() {
  final keys = jsonDecode(File('docs/master_detail/keys_p5.json').readAsStringSync()) as Map<String, dynamic>;
  translation = {...translation, ...keys};
}

Map<String, dynamic> _base() =>
    Map<String, dynamic>.from(((payload('admin_courses.json') as Map)['items'] as List).first as Map);

/// One row as the server sends it in `items`. Course 40 + i, so its detail is md_support's course i.
Map<String, dynamic> courseRow(int i) {
  final ref = mdCourseRef(i);
  final students = i == 4 ? 0 : 148 - (i % 11) * 13;
  return {
    ..._base(),
    'id': ref['id'],
    'name': ref['name_en'],
    'name_ar': ref['name_ar'],
    'name_en': ref['name_en'],
    'teacher_id': (ref['teacher'] as Map)['id'],
    'teacher_name': (ref['teacher'] as Map)['name'],
    'teacher': ref['teacher'],
    'category': i == 5 ? null : ref['category'],
    'category_id': i == 5 ? null : (ref['category'] as Map)['id'],
    'type': const ['recorded', 'live', 'both'][i % 3],
    'status': i % 7 == 3 ? 'completed' : 'in_progress',
    'is_published': i % 6 != 2,
    'archived': i == 7,
    'is_private': i % 5 == 1,
    'discount_active': i % 4 == 1,
    'discount_percentage': i % 4 == 1 ? 20.0 : 0.0,
    'pending_payments': i == 0 ? 3 : 0,
    'students_count': students,
    'paid_count': students ~/ 2,
    'income': 41250.0 - i * 1500,
    'collected': 44000.0 - i * 1500,
    'fees': 900.0,
    'list_price': i == 6 ? 0.0 : 900.0 + i * 50,
    'final_price': i == 6 ? 0.0 : (i % 4 == 1 ? 720.0 : 900.0 + i * 50),
    'currency': i % 5 == 2 ? 'SAR' : 'EGP',
    'completion_rate': students == 0 ? 0.0 : 22.6 + i * 6,
    'avg_progress': 47.0 - i,
    'withdrawn_count': 14 - i,
    'rating_avg': i == 3 ? null : 4.6 - i * 0.1,
    'rating_count': i == 3 ? 0 : 52 - i,
    'created_at': DateTime.utc(2026, 10 - (i % 9), 20 - i).toIso8601String().replaceAll('Z', ''),
    'recent_payments': [
      {'id': 900 + i, 'student_id': 100, 'amount': 450.0, 'price_paid': 450.0, 'status': 'completed', 'method': 'card', 'created_at': '2026-10-20T10:00:00'},
    ],
    'access_code': i % 5 == 1 ? '123456' : null,
  };
}

/// The paged list route: search by name, publishing, sort, pages of `size`.
Object? coursesList(RequestOptions o, {int total = 45}) {
  final q = o.uri.queryParameters;
  final size = int.tryParse(q['size'] ?? '') ?? 20;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  var all = [for (var i = 0; i < total; i++) courseRow(i)];
  final s = (q['search'] ?? '').toLowerCase();
  if (s.isNotEmpty) {
    all = all.where((c) => '${c['name_en']} ${c['name_ar']}'.toLowerCase().contains(s)).toList();
  }
  if (q['published'] != null) all = all.where((c) => '${c['is_published']}' == q['published']).toList();
  switch (q['sort']) {
    case 'students_desc':
      all.sort((a, b) => (b['students_count'] as int).compareTo(a['students_count'] as int));
    case 'students_asc':
      all.sort((a, b) => (a['students_count'] as int).compareTo(b['students_count'] as int));
  }
  final pages = (all.length / size).ceil().clamp(1, 999);
  final from = (page - 1) * size;
  return {
    'items': from >= all.length ? <Map<String, dynamic>>[] : all.skip(from).take(size).toList(),
    'total': all.length,
    'page': page,
    'size': size,
    'pages': pages,
    'totals': {
      'income': 145000.5,
      'income_by_currency': {'EGP': 120000.5, 'SAR': 25000},
    },
  };
}

Map<String, FakeHandler> courseRoutes({int total = 45}) => {
      'GET /api/v1/admin/courses': (o) => coursesList(o, total: total),
      'GET /api/v1/admin/courses/*': (o) {
        final id = int.parse(o.uri.pathSegments.last);
        return courseRow((id - 40).clamp(0, 999));
      },
      'PUT /api/v1/admin/courses/*': (_) => {'ok': true},
      'DELETE /api/v1/admin/courses/*': (_) => {'ok': true},
      'GET /api/v1/admin/categories': (_) => {'items': []},
      'GET /api/v1/admin/lookup/*': (_) => {'items': []},
    };
