// lib/core/entities/entities_api.dart — the client of `/api/v1/entities/...` (D-290).
//
//   EntitiesApi.instance.summary(ref)                     the summary (from the cache when fresh: a re-open is instant)
//   EntitiesApi.instance.cached(ref)                      the cached summary or null (drawn at once, then refreshed)
//   EntitiesApi.instance.prefetch(ref)                    warm the cache (a row hovered on the web)
//   EntitiesApi.instance.page(ref, 'courses', query: …)   one page of a sub-list the summary listed
//   EntitiesApi.instance.timeline(studentId, courseId)    one student's history in one course, newest first
//   EntitiesApi.instance.invalidate(ref)                  after a change (the Manage sheet saved)
//   EntitiesApi.instance.allowed(['student:12'])          which refs this viewer may open (a chip is a link only then)
//   EntitiesApi.instance.message(studentId, text)         a staff note to one student (delivered as a notification)
//
// Every call goes through ApiClient (errors are ApiException: 404 `not_found` when the entity is out of the viewer's
// scope, 403 `entity_forbidden` for a role with no entity views). Each path is written out in full so the API
// contract test checks it against the server's routes.
library;

import 'package:flutter_education_app/core/api_client.dart';

import 'entity_models.dart';
import 'entity_ref.dart';

class EntitiesApi {
  EntitiesApi._();
  static final EntitiesApi instance = EntitiesApi._();

  ApiClient get _api => ApiClient.instance;

  /// The summary cache: the 50 most recent, each fresh for 2 minutes.
  static const int cacheSize = 50;
  static const Duration cacheAge = Duration(minutes: 2);

  final _cache = <String, (DateTime, EntitySummary)>{}; // insertion-ordered: the oldest first
  final _inFlight = <String, Future<EntitySummary>>{};

  String _key(EntityRef ref, int? studentId) => studentId == null ? ref.toToken() : '${ref.toToken()}?s=$studentId';

  /// The cached summary while it is fresh (and touched: most recent first), else null.
  EntitySummary? cached(EntityRef ref, {int? studentId}) {
    final k = _key(ref, studentId);
    final hit = _cache.remove(k);
    if (hit == null) return null;
    if (DateTime.now().difference(hit.$1) > cacheAge) return null;
    _cache[k] = hit;
    return hit.$2;
  }

  /// The summary of [ref]: the fresh cached one unless [force], else ONE request however many callers ask at once.
  /// [studentId] picks a parent's child for a course's `mine`.
  Future<EntitySummary> summary(EntityRef ref, {int? studentId, bool force = false}) {
    final k = _key(ref, studentId);
    if (!force) {
      final hit = cached(ref, studentId: studentId);
      if (hit != null) return Future.value(hit);
    }
    final running = _inFlight[k];
    if (running != null) return running;
    final f = _fetchSummary(ref, studentId).then((s) {
      _cache.remove(k);
      _cache[k] = (DateTime.now(), s);
      while (_cache.length > cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      return s;
    }).whenComplete(() {
      _inFlight.remove(k); // a block on purpose: a returned future would be awaited, and this one is f itself
    });
    _inFlight[k] = f;
    return f;
  }

  /// Warms the cache for [ref] (errors are ignored: the panel asks again when it opens).
  void prefetch(EntityRef ref) {
    if (cached(ref) != null || _inFlight.containsKey(_key(ref, null))) return;
    summary(ref).then((_) {}, onError: (Object _) {});
  }

  /// Forgets [ref] (every child variant), or everything without one.
  void invalidate([EntityRef? ref]) {
    if (ref == null) {
      _cache.clear();
      return;
    }
    final t = ref.toToken();
    _cache.removeWhere((k, _) => k == t || k.startsWith('$t?'));
  }

  Future<EntitySummary> _fetchSummary(EntityRef ref, int? studentId) async {
    final q = studentId == null ? null : <String, dynamic>{'student_id': studentId};
    final id = ref.id;
    final dynamic r = switch (ref.kind) {
      EntityKind.student => await _api.get('/api/v1/entities/students/$id'),
      EntityKind.course => await _api.get('/api/v1/entities/courses/$id', queryParams: q),
      EntityKind.teacher => await _api.get('/api/v1/entities/teachers/$id'),
      EntityKind.category => await _api.get('/api/v1/entities/categories/$id'),
    };
    final m = entityMap(r);
    if (m == null) throw const ApiException(statusCode: 0, message: '', type: ApiErrorType.unknown);
    return EntitySummary.fromJson(m, kind: ref.kind, id: ref.id);
  }

  /// One page of [section] of [ref] (a section the summary listed). A section this app does not know answers an
  /// empty page.
  Future<EntityPage<EntityItem>> page(EntityRef ref, String section, {EntityListQuery query = const EntityListQuery()}) async {
    final q = query.toParams();
    final id = ref.id;
    final dynamic r = switch ((ref.kind, section)) {
      (EntityKind.student, 'courses') => await _api.get('/api/v1/entities/students/$id/courses', queryParams: q),
      (EntityKind.student, 'payments') => await _api.get('/api/v1/entities/students/$id/payments', queryParams: q),
      (EntityKind.student, 'subscriptions') =>
        await _api.get('/api/v1/entities/students/$id/subscriptions', queryParams: q),
      (EntityKind.course, 'students') => await _api.get('/api/v1/entities/courses/$id/students', queryParams: q),
      (EntityKind.teacher, 'courses') => await _api.get('/api/v1/entities/teachers/$id/courses', queryParams: q),
      (EntityKind.teacher, 'students') => await _api.get('/api/v1/entities/teachers/$id/students', queryParams: q),
      (EntityKind.category, 'courses') => await _api.get('/api/v1/entities/categories/$id/courses', queryParams: q),
      (EntityKind.category, 'teachers') => await _api.get('/api/v1/entities/categories/$id/teachers', queryParams: q),
      (EntityKind.category, 'students') => await _api.get('/api/v1/entities/categories/$id/students', queryParams: q),
      (EntityKind.student, 'grades') => await _api.get('/api/v1/entities/students/$id/grades', queryParams: q),
      (EntityKind.course, 'grades') => await _api.get('/api/v1/entities/courses/$id/grades', queryParams: q),
      (EntityKind.course, 'lessons') => await _api.get('/api/v1/entities/courses/$id/lessons', queryParams: q),
      (EntityKind.course, 'deadlines') => await _api.get('/api/v1/entities/courses/$id/deadlines', queryParams: q),
      (EntityKind.course, 'reviews') => await _api.get('/api/v1/entities/courses/$id/reviews', queryParams: q),
      (EntityKind.teacher, 'submissions') => await _api.get('/api/v1/entities/teachers/$id/submissions', queryParams: q),
      (EntityKind.teacher, 'reviews') => await _api.get('/api/v1/entities/teachers/$id/reviews', queryParams: q),
      _ => null,
    };
    if (r == null) return const EntityPage();
    return EntityPage.fromJson<EntityItem>(r, (j) => EntityItem.parse(ref.kind, section, j));
  }

  /// Of [tokens] (`student:12`, at most 100), the ones this viewer may open.
  Future<Set<String>> allowed(List<String> tokens) async {
    final r = entityMap(await _api.post('/api/v1/entities/access', body: {'refs': tokens}));
    final list = r?['allowed'];
    return list is List ? {for (final t in list) '$t'} : const {};
  }

  /// A staff note to one student they may see; [courseId] names the course it is about.
  Future<void> message(int studentId, String text, {int? courseId}) =>
      _api.post('/api/v1/entities/students/$studentId/message',
          body: {'text': text, if (courseId != null) 'course_id': courseId});

  /// One student's history in one course, newest first.
  Future<EntityPage<EntityTimelineEvent>> timeline(int studentId, int courseId, {int page = 1, int size = 20}) async {
    final r = await _api.get('/api/v1/entities/students/$studentId/courses/$courseId/timeline',
        queryParams: {'page': page, 'size': size});
    return EntityPage.fromJson<EntityTimelineEvent>(r, EntityTimelineEvent.fromJson);
  }
}
