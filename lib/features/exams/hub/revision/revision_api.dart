// Grade revision: the calls the Exam Hub adds to mark sessions (contract B3), on top of [MarkSessionsApi]. Every call
// answers an [EngineResult] or a plain model.
library;

import 'dart:convert' show jsonEncode;
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_screen.dart' show loadCourseStudents;
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart' show GradeStudent;
import 'package:flutter_education_app/features/exams/hub/revision/revision_models.dart';

enum RevisionDecideKind { ok, valueChanged, alreadyDecided, sessionClosed, error }

class RevisionDecideOutcome {
  const RevisionDecideOutcome(this.kind, {this.row, this.current, this.message = ''});
  final RevisionDecideKind kind;
  final RevisionRow? row;

  /// `value_changed`: what the record holds now.
  final double? current;
  final String message;
}

class RevisionApi {
  RevisionApi([ApiClient? api])
      : _api = api ?? ApiClient(),
        sessions = MarkSessionsApi(api);

  final ApiClient _api;
  final MarkSessionsApi sessions;
  static const _b = '/api/v1/exam/mark-sessions';

  /// An older server has no `/sample`: it answers FastAPI's bare 405 / 404 to the empty request; a new one refuses
  /// the empty request itself (422), or says the feature is off (403). Nothing is read and nothing stored.
  Future<bool> supported() async {
    final r = await engineCall(() => _api.post('$_b/sample', body: const <String, dynamic>{}));
    return !r.unavailable;
  }

  Future<EngineResult> sheetPreview(String name, Uint8List bytes) => engineCall(() => _api.postFiles('$_b/sheet-preview', files: [(name, bytes)], field: 'file'));

  Future<EngineResult> sample(
    (String, Uint8List) image, {
    required int templateId,
    RevisionMatch? match,
    RevisionStyles? styles,
    int? courseId,
    String? sheetKey,
    String? sheetMatchColumn,
  }) =>
      engineCall(() => _api.postFiles('$_b/sample', files: [image], field: 'image', fields: {
            'template_id': templateId,
            'match': match == null ? null : jsonEncode(match.toJson()),
            'styles': styles == null ? null : jsonEncode(styles.toJson()),
            'course_id': courseId,
            'sheet_key': sheetKey,
            'sheet_match_column': sheetMatchColumn,
          }));

  Future<EngineResult> create(Map<String, dynamic> body) => engineCall(() => _api.post(_b, body: body));

  Future<RevisionSession?> session(int sid) async {
    final r = await sessions.get(sid);
    return r.ok ? RevisionSession.fromJson(r.map) : null;
  }

  /// Open sessions to continue: of a course, or (no course) of the organization / the personal space.
  Future<List<RevisionSession>> openSessions({int? courseId, int? orgId}) async {
    final r = await engineCall(() => _api.get(_b, queryParams: {'course_id': ?courseId, if (courseId == null) 'org_id': ?orgId}));
    if (!r.ok) return const [];
    return [for (final m in asMapList(r.map['items'])) RevisionSession.fromJson(m)].where((s) => s.session.open).toList();
  }

  Future<List<RevisionRow>?> papers(int sid) async {
    final r = await sessions.rows(sid, status: 'all');
    if (!r.ok) return null;
    return [for (final m in asMapList(r.map['items'])) RevisionRow.fromJson(m)]..sort((a, b) => a.id.compareTo(b.id));
  }

  Future<RevisionPageRead?> pageRow(int sid, int pageId) async {
    final r = await engineCall(() => _api.get('$_b/$sid/pages/$pageId/row'));
    return r.ok ? RevisionPageRead.fromJson(r.map, lang: AppConfig.lang) : null;
  }

  Future<RevisionHistoryPage?> history(int sid, {int limit = 50, int? before}) async {
    final r = await engineCall(() => _api.get('$_b/$sid/history', queryParams: {'limit': limit, 'before': ?before}));
    return r.ok ? RevisionHistoryPage.fromJson(r.map) : null;
  }

  Future<Uint8List> sheetFile(int sid) => _api.getBytes('$_b/$sid/sheet.xlsx');

  /// Whoever a paper can be assigned to: the rows of the sheet, or the students of the course.
  Future<List<GradeStudent>> students(RevisionSession s) async {
    if (!s.excel) return loadCourseStudents(s.session.courseId);
    final r = await engineCall(() => _api.get('$_b/${s.id}/sheet-rows'));
    if (!r.ok) return const [];
    return [
      for (final m in asMapList(r.map['items'])) GradeStudent(asInt(m['id']), '${m['name'] ?? ''}'),
    ];
  }

  Future<RevisionDecideOutcome> decide(int sid, int rid, String action, {int? studentId, Map<String, double>? marks, double? value, String? reason}) async {
    final r = await sessions.decide(sid, rid, action, studentId: studentId, marks: marks, value: value, reason: reason);
    if (r.ok) return RevisionDecideOutcome(RevisionDecideKind.ok, row: RevisionRow.fromJson(r.map));
    final msg = revisionErrorText(r);
    return switch (r.code) {
      'value_changed' => RevisionDecideOutcome(RevisionDecideKind.valueChanged, current: double.tryParse('${r.detail['current'] ?? ''}'), message: msg),
      'row_decided' => RevisionDecideOutcome(RevisionDecideKind.alreadyDecided, message: msg),
      'session_closed' => RevisionDecideOutcome(RevisionDecideKind.sessionClosed, message: msg),
      _ => RevisionDecideOutcome(RevisionDecideKind.error, message: msg),
    };
  }

  /// The courses the person can review: the ones they teach, then one page of the organization's.
  Future<List<({int id, String name, int? orgId})>> courses({int? orgId}) async {
    final out = <int, ({int id, String name, int? orgId})>{};
    String pick(Map<String, dynamic> m) {
      final ar = '${m['name_ar'] ?? ''}'.trim(), en = '${m['name_en'] ?? ''}'.trim();
      final plain = '${m['title'] ?? m['name'] ?? ''}'.trim();
      final s = AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
      return s.isNotEmpty ? s : plain;
    }

    try {
      final r = asMap(await _api.get('/api/v1/my-courses', queryParams: {'scope': 'all', 'skip': 0, 'limit': 100}));
      for (final c in asMapList(r['items'])) {
        final org = asMap(c['org']);
        final oid = org['id'] == null ? null : asInt(org['id']);
        if (orgId != null && oid != orgId) continue;
        final id = asInt(c['id']), name = pick(c);
        if (id > 0 && name.isNotEmpty) out[id] = (id: id, name: name, orgId: oid);
      }
    } catch (_) {
      // not a teacher (an organization's staff): the organization's list below
    }
    if (orgId != null) {
      try {
        final r = asMap(await _api.get('/api/v1/org/orgs/$orgId/courses', queryParams: {'page': 1, 'size': 100}));
        for (final c in asMapList(r['items'])) {
          final id = asInt(c['id']), name = pick(c);
          if (id > 0 && name.isNotEmpty) out.putIfAbsent(id, () => (id: id, name: name, orgId: orgId));
        }
      } catch (_) {
        // no right to the organization's list
      }
    }
    return out.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
