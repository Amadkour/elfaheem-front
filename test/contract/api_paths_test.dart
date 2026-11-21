// API drift guard (D-026; core API added in Phase 10): every path the app hands to `ApiClient` must exist in the
// backend's route snapshot `test/contract/api_paths.json` (core, Exam Engine, RAG — written by
// ../back/scripts/contract/export_api_paths.py --front, checked against the routers by the backend CI). A renamed or
// removed route fails here, not in production.
//
// The scan (api_call_scan.dart) resolves each call's first argument into a template (`{}` = a run-time value);
// `/api/v1/exam/…` is checked against the engine, `/api/v1/rag/…` against RAG, the rest against the core — the split
// nginx makes. Calls whose path is a parameter (`_api.get(path)` in a helper) cannot be resolved and are only counted.
//
// When a route is added on the server: regenerate the snapshot (`python scripts/contract/export_api_paths.py --front
// ../nextbrain-front` in ../back). When the app calls a route the server does not have yet ON PURPOSE: add it to
// [knownMissing] below with the reason. The test also fails when an entry there is no longer needed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'api_call_scan.dart';

/// `METHOD template` (as the failure message prints it) → why it is allowed to have no server route today.
/// Checked by hand (Phase 10, A05); delete an entry when its call is fixed or removed — the test says when.
const knownMissing = <String, String>{
  // fallback for an older backend: tried only after GET /api/v1/my-enrolled-courses answers 404
  'GET /api/v1/my-enrollments': 'legacy fallback route (student_analytics_api.dart fetchMyEnrollments)',
  // the paper exam flow (D-697 over the back's OFFLINE_FLOW_CONTRACT.md §2 / §3, branch of/b)
  // org_inst_notify.dart: the phone-push setting and "Message this department"
  // repeating meetings (Learning Hub v2 §4 + C5, D-1570), built against the contract before the server
  'DELETE /api/v1/me/calendar/series/{}': 'lands with feature/lh2-cal',
  'DELETE /api/v1/me/calendar/series/{}/occurrences/{}': 'lands with feature/lh2-cal',
  'GET /api/v1/me/calendar/series/{}': 'lands with feature/lh2-cal',
  'PATCH /api/v1/me/calendar/series/{}': 'lands with feature/lh2-cal',
  'PATCH /api/v1/me/calendar/series/{}/occurrences/{}': 'lands with feature/lh2-cal',
  'POST /api/v1/me/calendar/series': 'lands with feature/lh2-cal',
  'POST /api/v1/me/calendar/series/{}/occurrences/{}/open': 'lands with feature/lh2-cal',
  // Learning Hub v2 games (CONTRACT §3 + C9): the server half is built in parallel
  'GET /api/v1/games/{}/leaderboard': 'lands with feature/lh2-learn',
  'PUT /api/v1/me/games/leaderboard': 'lands with feature/lh2-learn',
  'POST /api/v1/admin/games/reorder': 'lands with feature/lh2-learn',
  'GET /api/v1/admin/games/engines': 'lands with feature/lh2-learn',
  'POST /api/v1/admin/games/{}/cover': 'lands with feature/lh2-learn (cover upload, asked under the contract\'s Requests)',

  // self-learning (Learning Hub v2 CONTRACT §5, D-1600): the server routes land with the back's branch
  'DELETE /api/v1/admin/self-learning/items/{}': 'lands with feature/lh2-learn',
  'GET /api/v1/admin/self-learning/items': 'lands with feature/lh2-learn',
  'GET /api/v1/me/self-learning': 'lands with feature/lh2-learn',
  'POST /api/v1/admin/self-learning/items': 'lands with feature/lh2-learn',
  'POST /api/v1/admin/self-learning/items/reorder': 'lands with feature/lh2-learn',
  'POST /api/v1/me/self-learning/lessons/{}/seen': 'lands with feature/lh2-learn',
  'POST /api/v1/me/self-learning/reviews/{}': 'lands with feature/lh2-learn',
  'PUT /api/v1/admin/self-learning/items/{}': 'lands with feature/lh2-learn',
  'PUT /api/v1/me/self-learning': 'lands with feature/lh2-learn',
  // Learning Hub v2 teachers and packages (CONTRACT.md §1 / §2, lib/features/teachers/teachers_api.dart)
  'DELETE /api/v1/me/teacher-profile/documents/{}': 'lands with feature/lh2-core',
  'GET /api/v1/admin/teachers': 'lands with feature/lh2-core',
  'GET /api/v1/admin/teachers/{}/documents/{}/url': 'lands with feature/lh2-core',
  'GET /api/v1/me/packages': 'lands with feature/lh2-core',
  'GET /api/v1/me/teacher-profile': 'lands with feature/lh2-core',
  'GET /api/v1/me/teachers': 'lands with feature/lh2-core',
  'GET /api/v1/packages': 'lands with feature/lh2-core',
  'GET /api/v1/packages/{}': 'lands with feature/lh2-core',
  'GET /api/v1/packages/{}/enrollments': 'lands with feature/lh2-core',
  'GET /api/v1/teachers': 'lands with feature/lh2-core',
  'GET /api/v1/teachers/{}': 'lands with feature/lh2-core',
  'POST /api/v1/admin/teachers/{}/approve': 'lands with feature/lh2-core',
  'POST /api/v1/admin/teachers/{}/reject': 'lands with feature/lh2-core',
  'POST /api/v1/me/teacher-profile/documents': 'lands with feature/lh2-core',
  'POST /api/v1/me/teacher-profile/submit': 'lands with feature/lh2-core',
  'POST /api/v1/packages': 'lands with feature/lh2-core',
  'POST /api/v1/packages/{}/duplicate': 'lands with feature/lh2-core',
  'POST /api/v1/packages/{}/enroll': 'lands with feature/lh2-core',
  'POST /api/v1/packages/{}/leave': 'lands with feature/lh2-core',
  'POST /api/v1/packages/{}/status': 'lands with feature/lh2-core',
  'PUT /api/v1/me/teacher-profile': 'lands with feature/lh2-core',
  'PUT /api/v1/packages/{}': 'lands with feature/lh2-core',
};

void main() {
  test('every ApiClient call in lib/ matches a backend route (method + path)', () {
    final snap = jsonDecode(File('test/contract/api_paths.json').readAsStringSync()) as Map<String, dynamic>;
    final routes = <String, List<(String, String)>>{
      for (final e in snap.entries)
        e.key: [
          for (final r in (e.value as List).cast<String>()) (r.substring(0, r.indexOf(' ')), r.substring(r.indexOf(' ') + 1)),
        ],
    };
    expect(routes.keys, containsAll(['core', 'exam', 'rag']), reason: 'snapshot from the Phase 10 export script');

    final sources = {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
    };
    final calls = ApiCallScan(sources).calls();

    final missing = <String, List<ApiCall>>{};
    final allowedSeen = <String>{};
    var matched = 0, prefixOnly = 0, unresolved = 0, allowed = 0;
    for (final c in calls) {
      if (!c.resolved) {
        unresolved++;
        continue;
      }
      // every branch of a ternary must exist
      var unknown = false, known = false, viaPrefix = false;
      for (final t in c.templates) {
        final svc = routes[serviceOf(t)] ?? const [];
        if (svc.any((r) => r.$1 == c.method && templatesMatch(t, r.$2))) {
          viaPrefix |= isPrefixOnly(t);
          continue;
        }
        final key = '${c.method} $t';
        if (knownMissing.containsKey(key)) {
          allowedSeen.add(key);
          known = true;
        } else {
          missing.putIfAbsent(key, () => []).add(c);
          unknown = true;
        }
      }
      if (!unknown && !known) {
        matched++;
        if (viaPrefix) prefixOnly++;
      } else if (!unknown) {
        allowed++;
      }
    }
    final found = calls.length;
    // ignore: avoid_print — the coverage line is the point of this test's output
    print('api contract: $found calls found · ${found - unresolved} resolved · $matched matched '
        '($prefixOnly by prefix only) · $allowed known-missing · ${missing.length} unknown paths · $unresolved unresolved');

    expect(found, greaterThan(500), reason: 'the scan found the clients');
    expect(unresolved / found, lessThan(0.10), reason: 'the scan resolves almost every path; did a client change shape?');
    expect(missing.keys.toList()..sort(), isEmpty,
        reason: 'calls with no backend route — the API changed, a path is mistyped, or the snapshot is old:\n'
            '${missing.entries.map((e) => '${e.key}   ${e.value.map((c) => '${c.file}:${c.line}').join(', ')}').join('\n')}');
    final stale = knownMissing.keys.where((k) => !allowedSeen.contains(k)).toList();
    expect(stale, isEmpty, reason: 'knownMissing entries that now match a route or are no longer called — delete them');
  });
}
