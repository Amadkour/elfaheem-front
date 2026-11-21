// lib/features/nahw/nahw_api.dart — the Arabic grammar (nahw) calls (Learning Hub Phase 6, D-1349; server D-1343).
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET  /api/v1/nahw/levels?stage_id&grade_id        levels with their lessons and my progress (signed in)
//   GET  /api/v1/nahw/lessons/{id}                    the lesson, its exercises WITH the answers, my progress
//   POST /api/v1/nahw/lessons/{id}/attempts           {client_id, score, max_score, answers} → {progress, duplicate}
//   GET  /api/v1/parent/children/{id}/nahw            the levels shape for a linked child (404 LINK_NOT_FOUND)
//
// Kill switch: `student_tab_nahw` (the tab and the student routes; the server answers 403 feature_disabled too).
// A finished round keeps its `client_id` until the server answers, so a retry after a timeout is the SAME attempt
// and never counts twice.
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:uuid/uuid.dart';

import 'nahw_models.dart';

const String kNahwTabKey = 'student_tab_nahw';

bool nahwOff() => AppConfig.disableList.contains(kNahwTabKey);

String nahwLabel() => t('النحو', 'Grammar');

/// A nahw code's bilingual text (null = not a nahw code).
String? nahwCodeText(String? code) => switch (code) {
      'nahw_lesson_not_found' => t('هذا الدرس غير متاح', 'This lesson is not available'),
      'nahw_bad_score' => t('تعذّر حفظ هذه النتيجة. أعد حل التمارين.', 'This result could not be saved. Do the exercises again.'),
      'LINK_NOT_FOUND' => t('هذا الطالب غير مرتبط بحسابك', 'This student is not linked to your account'),
      _ => null,
    };

String nahwErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final x = ApiException.from(e);
  return nahwCodeText(x.code) ?? apiErrorText(x);
}

/// The server answered (a status): only then is a round's `client_id` dropped.
bool nahwDefiniteAnswer(Object e) => e is ApiException && e.statusCode > 0;

String nahwClientId() => const Uuid().v4();

class NahwAttemptResult {
  const NahwAttemptResult({this.progress, this.duplicate = false});
  final NahwProgress? progress;
  final bool duplicate;
}

class NahwApi {
  NahwApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<NahwLevel>> levels({int? stageId, int? gradeId}) async => NahwLevel.listFrom(
      await _api.get('/api/v1/nahw/levels', queryParams: {'stage_id': ?stageId, 'grade_id': ?gradeId}));

  Future<NahwLesson> lesson(int id) async => NahwLesson.from(await _api.get('/api/v1/nahw/lessons/$id'));

  Future<NahwAttemptResult> attempt(int lessonId,
      {required String clientId, required int score, required int maxScore, List<Object?> answers = const []}) async {
    final r = await _api.post('/api/v1/nahw/lessons/$lessonId/attempts', body: {
      'client_id': clientId,
      'score': score,
      'max_score': maxScore,
      'answers': answers,
    });
    final m = r is Map ? r : const {};
    return NahwAttemptResult(progress: NahwProgress.from(m['progress']), duplicate: m['duplicate'] == true);
  }

  Future<List<NahwLevel>> child(int studentId) async =>
      NahwLevel.listFrom(await _api.get('/api/v1/parent/children/$studentId/nahw'));
}
