// lib/features/self_learning/sl_api.dart — the self-learning calls (Learning Hub v2 CONTRACT §5, D-1600). Every path
// is a literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET    /api/v1/me/self-learning                       my state: on / off, subjects, today's items, progress
//   PUT    /api/v1/me/self-learning                       {enabled, subjects}; 403 toggle_locked when not allowed
//   POST   /api/v1/me/self-learning/lessons/{id}/seen     "Got it" (idempotent)
//   POST   /api/v1/me/self-learning/reviews/{id}          {choice, client_id} → {right, explanation, card}
//   GET    /api/v1/admin/self-learning/items?subject&kind&page&size   {items, total, page}
//   POST   /api/v1/admin/self-learning/items              an SlItem body
//   PUT    /api/v1/admin/self-learning/items/{id}         the whole SlItem body
//   DELETE /api/v1/admin/self-learning/items/{id}
//   POST   /api/v1/admin/self-learning/items/reorder      {ids}
//
// Kill switches: `student_tab_self_learning` (the student side), `admin.self_learning` (the content page).
// A review answer is graded on the device first (the item carries the answer), so the feedback is instant. Then it
// is posted with a `client_id`; when the post gets no answer at all (offline, a timeout) it goes to the device's
// outbox as an `sl_review` op under the SAME id, so the server counts it once (D-1606).
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:uuid/uuid.dart';

import 'sl_models.dart';

const String kSlStudentFeatureKey = 'student_tab_self_learning';
const String kSlAdminFeatureKey = 'admin.self_learning';

bool slOff() => AppConfig.disableList.contains(kSlStudentFeatureKey);
bool slAdminOff() => AppConfig.disableList.contains(kSlAdminFeatureKey);

String slClientId() => const Uuid().v4();

/// A self-learning code's bilingual text (null = not one of ours).
String? slCodeText(String? code) => switch (code) {
      'toggle_locked' => t('لا يمكنك تغيير هذا الإعداد. تديره إدارة المنصة.', 'You cannot change this setting. The platform manages it.'),
      'feature_disabled' => t('الدروس اليومية متوقفة حالياً', 'Daily lessons are switched off'),
      'sl_item_not_found' || 'item_not_found' => t('هذا العنصر غير متاح', 'This item is not available'),
      'bad_question' || 'sl_bad_question' =>
        t('السؤال يحتاج خيارين على الأقل وإجابة صحيحة', 'A question needs at least two options and a right answer'),
      _ => null,
    };

String slErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final x = ApiException.from(e);
  return slCodeText(x.code) ?? apiErrorText(x);
}

/// No answer from the server at all (offline, timeout, transport): the review answer is kept on the device.
bool slNoAnswer(Object e) => e is TimeoutException || (e is ApiException && e.statusCode <= 0);

/// The admin switched self-learning off: the server's 403 `feature_disabled`.
bool slSwitchedOff(Object e) => e is ApiException && e.statusCode == 403 && e.code == 'feature_disabled';

/// Posts the answer, or keeps it in the outbox. Separate so a test can fake it.
typedef SlEnqueue = Future<EnqueueResult> Function(String id, Map<String, dynamic> payload);

Future<EnqueueResult> _outboxEnqueue(String id, Map<String, dynamic> payload) =>
    Outbox.instance.enqueue(id: id, kind: SyncKinds.slReview, payload: payload);

class SlApi {
  SlApi({ApiClient? api, SlEnqueue? enqueue})
      : _api = api ?? ApiClient(),
        _enqueue = enqueue ?? _outboxEnqueue;

  final ApiClient _api;
  final SlEnqueue _enqueue;

  // ── student ────────────────────────────────────────────────────────────────

  /// My state; the admin's switch off (403 feature_disabled) reads as [SlState.off].
  Future<SlState> me() async {
    try {
      return SlState.from(await _api.get('/api/v1/me/self-learning'));
    } catch (e) {
      if (slSwitchedOff(e)) return SlState.off;
      rethrow;
    }
  }

  Future<SlState> update({required bool enabled, required List<String> subjects}) async =>
      SlState.from(await _api.put('/api/v1/me/self-learning', body: {'enabled': enabled, 'subjects': subjects}));

  Future<void> seen(int itemId) async {
    await _api.post('/api/v1/me/self-learning/lessons/$itemId/seen');
  }

  /// Sends one review answer. No answer at all → kept in the outbox under [clientId] ([SlReviewResult.queued]);
  /// a server refusal is thrown.
  Future<SlReviewResult> review(int itemId, {required int choice, required String clientId}) async {
    try {
      final r = await _api.post('/api/v1/me/self-learning/reviews/$itemId', body: {'choice': choice, 'client_id': clientId});
      return SlReviewResult.from(r);
    } catch (e) {
      if (!slNoAnswer(e)) rethrow;
      final q = await _enqueue(clientId, {'item_id': itemId, 'choice': choice});
      if (q == EnqueueResult.postDirectly) rethrow;
      return const SlReviewResult(right: false, queued: true);
    }
  }

  // ── admin ──────────────────────────────────────────────────────────────────

  Future<SlItemPage> items({String? subject, String? kind, int page = 1, int size = 20}) async => SlItemPage.from(
      await _api.get('/api/v1/admin/self-learning/items',
          queryParams: {'subject': ?subject, 'kind': ?kind, 'page': page, 'size': size}),
      size: size);

  Future<SlItem> create(Map<String, dynamic> body) async {
    final r = await _api.post('/api/v1/admin/self-learning/items', body: body);
    return SlItem.from(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<SlItem> save(int id, Map<String, dynamic> body) async {
    final r = await _api.put('/api/v1/admin/self-learning/items/$id', body: body);
    return SlItem.from(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<void> delete(int id) async {
    await _api.delete('/api/v1/admin/self-learning/items/$id');
  }

  Future<void> reorder(List<int> ids) async {
    await _api.post('/api/v1/admin/self-learning/items/reorder', body: {'ids': ids});
  }
}
