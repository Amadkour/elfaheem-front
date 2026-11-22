// lib/features/nahw/admin/nahw_admin_api.dart — the super admin's nahw content calls (6.R #8, D-1349). Every path is a
// literal `/api/v1/…` (test/contract/ checks each against the server's routes). Kill switch `admin.nahw`.
//
//   GET    /api/v1/admin/nahw/levels                    every level (inactive too) with its lessons
//   POST   /api/v1/admin/nahw/levels                    {key, title_ar, title_en, stage_id?, grade_id?, sort?, active?}
//   PUT    /api/v1/admin/nahw/levels/{id}               the same fields, each optional
//   DELETE /api/v1/admin/nahw/levels/{id}
//   GET    /api/v1/admin/nahw/lessons/{id}              the lesson with body_ar and every exercise (any kind)
//   POST   /api/v1/admin/nahw/lessons                   {level_id, title_ar, title_en, body_ar?, sort?, active?}
//   PUT    /api/v1/admin/nahw/lessons/{id} · DELETE …
//   POST   /api/v1/admin/nahw/lessons/{id}/exercises    {kind, prompt, data, answer, explanation?, sort?}
//   PUT    /api/v1/admin/nahw/exercises/{id} · DELETE …
//
// Server codes: 409 nahw_key_taken · 422 nahw_bad_kind | nahw_bad_exercise · 404 nahw_level_not_found |
// nahw_lesson_not_found | nahw_exercise_not_found · 403 admin_required | feature_disabled.
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import '../nahw_api.dart' show nahwCodeText;

const String kNahwAdminKey = 'admin.nahw';

bool nahwAdminOff() => AppConfig.disableList.contains(kNahwAdminKey);

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? d;

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// A level as the admin edits it (inactive ones too).
class NahwAdminLevel {
  const NahwAdminLevel({
    required this.id,
    required this.key,
    required this.titleAr,
    this.titleEn = '',
    this.stageId,
    this.gradeId,
    this.sort = 0,
    this.active = true,
    this.lessons = const [],
  });

  final int id;
  final String key;
  final String titleAr;
  final String titleEn;
  final int? stageId;
  final int? gradeId;
  final int sort;
  final bool active;
  final List<NahwAdminLessonRef> lessons;

  String get title => t(titleAr, titleEn.isEmpty ? titleAr : titleEn);

  static NahwAdminLevel from(Map<String, dynamic> m) => NahwAdminLevel(
        id: _int(m['id']),
        key: '${m['key'] ?? ''}',
        titleAr: '${m['title_ar'] ?? ''}',
        titleEn: '${m['title_en'] ?? ''}',
        stageId: m['stage_id'] == null ? null : _int(m['stage_id']),
        gradeId: m['grade_id'] == null ? null : _int(m['grade_id']),
        sort: _int(m['sort']),
        active: m['active'] != false,
        lessons: [for (final l in _maps(m['lessons'])) NahwAdminLessonRef.from(l)],
      );

  static List<NahwAdminLevel> listFrom(dynamic v) => [for (final l in _maps(_map(v)['levels'])) NahwAdminLevel.from(l)];
}

class NahwAdminLessonRef {
  const NahwAdminLessonRef({
    required this.id,
    required this.levelId,
    required this.titleAr,
    this.titleEn = '',
    this.sort = 0,
    this.active = true,
    this.exerciseCount = 0,
  });

  final int id;
  final int levelId;
  final String titleAr;
  final String titleEn;
  final int sort;
  final bool active;
  final int exerciseCount;

  String get title => t(titleAr, titleEn.isEmpty ? titleAr : titleEn);

  static NahwAdminLessonRef from(Map<String, dynamic> m) => NahwAdminLessonRef(
        id: _int(m['id']),
        levelId: _int(m['level_id']),
        titleAr: '${m['title_ar'] ?? ''}',
        titleEn: '${m['title_en'] ?? ''}',
        sort: _int(m['sort']),
        active: m['active'] != false,
        exerciseCount: _int(m['exercise_count']),
      );
}

/// A lesson with its reading text and every exercise (the raw maps: the editor keeps unknown data keys).
class NahwAdminLesson {
  const NahwAdminLesson({required this.ref, this.bodyAr = '', this.exercises = const []});

  final NahwAdminLessonRef ref;
  final String bodyAr;
  final List<Map<String, dynamic>> exercises;

  static NahwAdminLesson from(dynamic v) {
    final m = _map(v);
    return NahwAdminLesson(
      ref: NahwAdminLessonRef.from({...m, 'exercise_count': _maps(m['exercises']).length}),
      bodyAr: '${m['body_ar'] ?? ''}',
      exercises: _maps(m['exercises']),
    );
  }
}

/// A nahw admin code's bilingual text (else the shared error texts).
String nahwAdminErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final x = ApiException.from(e);
  final own = switch (x.code) {
    'nahw_key_taken' => t('هذا المفتاح مستخدم لمستوى آخر', 'Another level already uses this key'),
    'nahw_bad_kind' => t('نوع التمرين غير مدعوم', 'This exercise kind is not supported'),
    'nahw_bad_exercise' => t('بيانات التمرين ناقصة أو لا تطابق نوعه', 'The exercise is incomplete or does not fit its kind'),
    'nahw_level_not_found' => t('المستوى غير موجود', 'Level not found'),
    'nahw_exercise_not_found' => t('التمرين غير موجود', 'Exercise not found'),
    'admin_required' => t('للمدير العام فقط', 'Super admin only'),
    _ => null,
  };
  return own ?? nahwCodeText(x.code) ?? apiErrorText(x);
}

class NahwAdminApi {
  NahwAdminApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<NahwAdminLevel>> levels() async => NahwAdminLevel.listFrom(await _api.get('/api/v1/admin/nahw/levels'));

  Future<void> createLevel(Map<String, dynamic> body) => _api.post('/api/v1/admin/nahw/levels', body: body);

  Future<void> updateLevel(int id, Map<String, dynamic> body) => _api.put('/api/v1/admin/nahw/levels/$id', body: body);

  Future<void> deleteLevel(int id) => _api.delete('/api/v1/admin/nahw/levels/$id');

  Future<NahwAdminLesson> lesson(int id) async => NahwAdminLesson.from(await _api.get('/api/v1/admin/nahw/lessons/$id'));

  Future<void> createLesson(Map<String, dynamic> body) => _api.post('/api/v1/admin/nahw/lessons', body: body);

  Future<void> updateLesson(int id, Map<String, dynamic> body) => _api.put('/api/v1/admin/nahw/lessons/$id', body: body);

  Future<void> deleteLesson(int id) => _api.delete('/api/v1/admin/nahw/lessons/$id');

  Future<void> createExercise(int lessonId, Map<String, dynamic> body) =>
      _api.post('/api/v1/admin/nahw/lessons/$lessonId/exercises', body: body);

  Future<void> updateExercise(int id, Map<String, dynamic> body) =>
      _api.put('/api/v1/admin/nahw/exercises/$id', body: body);

  Future<void> deleteExercise(int id) => _api.delete('/api/v1/admin/nahw/exercises/$id');
}
