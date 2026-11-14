// lib/features/courses/admin/course_trash/trash_api.dart
//
// The calls of the Super Admin's "Deleted courses" console (every route platform SUPER_ADMIN only, D-260).
library;

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/courses/admin/course_trash/trash_models.dart';

const String _base = '/api/v1/admin/course-trash';

class CourseTrashApi {
  CourseTrashApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  Map<String, dynamic> _q(String state, String q, int page, int size) =>
      {'state': state, if (q.trim().isNotEmpty) 'q': q.trim(), 'page': page, 'size': size};

  Future<TrashPage<TrashItem>> trash({String q = '', int page = 1, int size = 20}) async =>
      TrashPage.parse(await _api.get(_base, queryParams: _q('trash', q, page, size)), TrashItem.fromJson);

  Future<TrashPage<PurgedItem>> purged({String q = '', int page = 1, int size = 20}) async =>
      TrashPage.parse(await _api.get(_base, queryParams: _q('purged', q, page, size)), PurgedItem.fromJson);

  Future<TrashDetail> detail(int courseId) async => TrashDetail.fromJson(await _api.get('$_base/$courseId'));

  Future<TrashRestoreResult> restore(int courseId, {String? reason}) async => TrashRestoreResult.fromJson(
      await _api.post('$_base/$courseId/restore', body: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()}));

  Future<TrashPurgeSummary> purge(int courseId, {required String reason, required String confirm}) async =>
      TrashPurgeSummary.fromJson(await _api.post('$_base/$courseId/purge', body: {'reason': reason.trim(), 'confirm': confirm.trim()}));
}
