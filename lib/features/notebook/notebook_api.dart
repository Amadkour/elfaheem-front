// lib/features/notebook/notebook_api.dart
//
// WP10, the student's notebook (docs/redesign/api/notebook.md). Kill switch `course.notebook` (403 feature_disabled).
//
//   GET    /api/v1/me/notebook/summary                 → {items: [{subject_id, course_id, pages, updated_at}]}
//   GET    /api/v1/me/notebook/pages?…&full=&limit=&before=&before_id=   → {items, server_time, has_more}
//   GET    /api/v1/me/notebook/pages/{id}              → page
//   POST   /api/v1/me/notebook/pages                   → 201 page (idempotent on client_id)
//   PUT    /api/v1/me/notebook/pages/{id}              → page (409 note_stale {page})
//   DELETE /api/v1/me/notebook/pages/{id}              → {deleted: true}
//   POST   /api/v1/me/notebook/pages/{id}/share        → page
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/notebook/notebook_models.dart';

/// One page of the list answer.
class NotePageList {
  const NotePageList({required this.items, required this.hasMore, this.serverTime});

  final List<NotePage> items;
  final bool hasMore;
  final DateTime? serverTime;
}

/// One row of the summary: how many pages a subject / course holds.
class NoteSummaryItem {
  const NoteSummaryItem({this.subjectId, this.courseId, required this.pages, this.updatedAt});

  final int? subjectId, courseId;
  final int pages;
  final DateTime? updatedAt;
}

/// True when the error means the super admin switched the notebook off.
bool notebookDisabled(Object e) {
  final x = ApiException.from(e);
  return x.statusCode == 403 && (x.code == 'feature_disabled' || x.code == 'feature_off');
}

class NotebookApi {
  NotebookApi([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  static const _base = '/api/v1/me/notebook';

  static Map<String, dynamic> _map(Object? r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  Future<List<NoteSummaryItem>> summary() async {
    final r = _map(await _api.get('$_base/summary'));
    return [
      for (final i in (r['items'] as List?) ?? const [])
        if (i is Map)
          NoteSummaryItem(
            subjectId: (i['subject_id'] as num?)?.toInt(),
            courseId: (i['course_id'] as num?)?.toInt(),
            pages: (i['pages'] as num?)?.toInt() ?? 0,
            updatedAt: notebookParseUtc(i['updated_at']),
          ),
    ];
  }

  /// Newest first. The next page: pass the last item as [after] (its `updated_at` + id).
  Future<NotePageList> pages({
    int? subjectId,
    int? courseId,
    int? lessonId,
    bool full = true,
    int limit = 50,
    NotePage? after,
    DateTime? since,
  }) async {
    final q = <String, dynamic>{
      'subject_id': ?subjectId,
      'course_id': ?courseId,
      'lesson_id': ?lessonId,
      if (full) 'full': true,
      'limit': limit,
      if (after?.updatedAt != null) 'before': _naive(after!.updatedAt!),
      if (after != null) 'before_id': after.id,
      if (since != null) 'since': _naive(since),
    };
    final r = _map(await _api.get('$_base/pages', queryParams: q));
    return NotePageList(
      items: [
        for (final i in (r['items'] as List?) ?? const [])
          if (i is Map) NotePage.fromJson(Map<String, dynamic>.from(i)),
      ],
      hasMore: r['has_more'] == true,
      serverTime: notebookParseUtc(r['server_time']),
    );
  }

  Future<NotePage> page(int id) async => NotePage.fromJson(_map(await _api.get('$_base/pages/$id')));

  Future<NotePage> create(NotePage draft) async =>
      NotePage.fromJson(_map(await _api.post('$_base/pages', body: draft.toCreateJson())));

  Future<NotePage> update(NotePage draft, {required int baseVersion}) async =>
      NotePage.fromJson(_map(await _api.put('$_base/pages/${draft.id}', body: draft.toUpdateJson(baseVersion))));

  Future<void> delete(int id) async => _api.delete('$_base/pages/$id');

  Future<NotePage> share(int id, {required bool shared}) async =>
      NotePage.fromJson(_map(await _api.post('$_base/pages/$id/share', body: {'shared': shared})));

  /// Saves [draft]: a create when it has no id, else an update on top of its version. On 409 `note_stale` the
  /// server's copy is the base: the device's text and ink (what the student just wrote) are sent again on top of
  /// the stored version, once.
  Future<NotePage> save(NotePage draft) async {
    if (draft.id == 0) return create(draft);
    try {
      return await update(draft, baseVersion: draft.version);
    } catch (e) {
      final stale = staleServerPage(e);
      if (stale == null) rethrow;
      return update(draft, baseVersion: stale.version);
    }
  }

  /// The server's page carried by a 409 `note_stale`, else null.
  static NotePage? staleServerPage(Object e) {
    final x = ApiException.from(e);
    if (x.statusCode != 409 || x.code != 'note_stale') return null;
    final body = x.body;
    Object? page;
    if (body is Map) {
      page = body['page'] ?? (body['detail'] is Map ? (body['detail'] as Map)['page'] : null);
    }
    return page is Map ? NotePage.fromJson(Map<String, dynamic>.from(page)) : null;
  }

  static String _naive(DateTime d) => d.toUtc().toIso8601String().replaceFirst('Z', '');
}
