// lib/features/admin/course_students/cs_api.dart
//
// The calls of the Super Admin's "Courses & students" console (every route platform SUPER_ADMIN only).
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import 'cs_models.dart';

const String _base = '/api/v1/admin/course-students';

class CsQuery {
  const CsQuery({this.search = '', this.status, this.sort, this.desc = false, this.page = 1, this.extra = const {}});
  final String search;
  final String? status;
  final String? sort;
  final bool desc;
  final int page;
  final Map<String, String?> extra;

  CsQuery copyWith({String? search, Object? status = _keep, Object? sort = _keep, bool? desc, int? page, Map<String, String?>? extra}) => CsQuery(
        search: search ?? this.search,
        status: identical(status, _keep) ? this.status : status as String?,
        sort: identical(sort, _keep) ? this.sort : sort as String?,
        desc: desc ?? this.desc,
        page: page ?? this.page,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toParams({int? pageSize, bool withPage = true}) => {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (status != null) 'status': status,
        if (sort != null) ...{'sort': sort, 'dir': desc ? 'desc' : 'asc'},
        for (final e in extra.entries)
          if (e.value != null) e.key: e.value,
        if (withPage) 'page': page,
        if (withPage && pageSize != null) 'page_size': pageSize,
      };
}

const Object _keep = Object();

class CourseStudentsApi {
  CourseStudentsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<CsCoursesPage> courses(CsQuery q, {int pageSize = 20}) async =>
      CsCoursesPage.fromJson(await _api.get('$_base/courses', queryParams: q.toParams(pageSize: pageSize)));

  Future<CsRoster> roster(int courseId, CsQuery q, {int pageSize = 25}) async =>
      CsRoster.fromJson(await _api.get('$_base/courses/$courseId/students', queryParams: q.toParams(pageSize: pageSize)));

  /// The CSV of every page for the same filters (UTF-8 with BOM, from the server).
  Future<Uint8List> rosterCsv(int courseId, CsQuery q) =>
      _api.getBytes('$_base/courses/$courseId/students.csv', queryParams: q.toParams(withPage: false));

  Future<List<CsStudent>> lookup(String q) async {
    final r = await _api.get('$_base/students/lookup', queryParams: {'q': q.trim()});
    return csList(csMap(r)['items']).map(CsStudent.fromJson).toList();
  }

  Future<CsProfile> profile(int studentId) async => CsProfile.fromJson(await _api.get('$_base/students/$studentId'));

  /// extend | reactivate | grant | cancel; returns the new access.
  Future<CsAccess> act(int studentId, int courseId, {required String action, required String reason, int? days, String? plan}) async {
    final r = await _api.post('$_base/students/$studentId/courses/$courseId/actions', body: {
      'action': action,
      'reason': reason.trim(),
      if (days != null) 'days': days,
      if (plan != null) 'plan': plan,
    });
    return CsAccess.fromJson(csMap(r)['access']);
  }
}
