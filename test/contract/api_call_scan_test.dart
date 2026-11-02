// The path scanner behind api_paths_test.dart, on small hand-written sources: what a call's first argument must turn
// into, and how a template is matched against a server route.
import 'package:flutter_test/flutter_test.dart';

import 'api_call_scan.dart';

List<String> _scan(String src, {Map<String, String> more = const {}}) =>
    ApiCallScan({'lib/a.dart': src, ...more}).calls().map((c) => '${c.method} ${c.resolved ? c.templates.join(' | ') : '?'}').toList();

void main() {
  group('scan', () {
    test('literal paths, every ApiClient method, query dropped', () {
      expect(_scan(r'''
f(ApiClient _api) {
  _api.get('/api/v1/courses?page=1');
  _api.post("/api/v1/auth/login", body: {});
  _api.put('/api/v1/x');
  _api.patch('/api/v1/x');
  _api.delete('/api/v1/x');
  _api.getBytes('/api/v1/f');
  _api.postForm('/api/v1/up', fields: {});
  _api.postMultipart('/api/v1/up2', fields: {}, fileField: 'f', fileName: 'n');
  _api.postFiles('/api/v1/up3', files: []);
  _api.postForBytes('/api/v1/pdf');
}'''), [
        'GET /api/v1/courses',
        'POST /api/v1/auth/login',
        'PUT /api/v1/x',
        'PATCH /api/v1/x',
        'DELETE /api/v1/x',
        'GET /api/v1/f',
        'POST /api/v1/up',
        'POST /api/v1/up2',
        'POST /api/v1/up3',
        'POST /api/v1/pdf',
      ]);
    });

    test('interpolated values become {} and base constants are inlined', () {
      expect(_scan(r'''
class ExamApi {
  static const base = '/api/v1/exam';
  final ApiClient _api;
  get(int id, Q q) => _api.get('$base/questions/${q.id}/v$id');
}'''), ['GET /api/v1/exam/questions/{}/v{}']);
    });

    test('class-qualified, getters, functions, locals, top-level consts of another file', () {
      expect(
          _scan(r'''
const _b = '/api/v1/me';
String _pub(int org) => '$orgBase/public/$org';
class S {
  static const base = Other.base;
  String get reg => '${session.base}/registrar';
  f(ApiClient api, int o) {
    final url = '$_b/inbox';
    api.get(url);
    api.get('${_pub(o)}/join');
    api.get('$reg/terms');
    api.get('$base/x');
  }
}
class Other { static const base = '/api/v1/other'; }
class Session { String get base => '$orgBase/orgs/$currentId'; }''', more: {'lib/b.dart': "const orgBase = '/api/v1/org';"}),
          [
            'GET /api/v1/me/inbox',
            'GET /api/v1/org/public/{}/join',
            'GET /api/v1/org/orgs/{}/registrar/terms',
            'GET /api/v1/other/x',
          ]);
    });

    test('a local is only seen after its declaration and inside its block', () {
      expect(_scan(r'''
f(ApiClient api) {
  { final p = '/api/v1/inner'; }
  api.get(p);
  final q = '/api/v1/q';
  api.get(q);
}'''), ['GET ?', 'GET /api/v1/q']);
    });

    test('ternary and ?? give one template per branch', () {
      expect(_scan(r'''
f(ApiClient api, bool edit, int id) {
  api.post(edit ? '/api/v1/items/$id' : '/api/v1/items');
}'''), ['POST /api/v1/items | /api/v1/items/{}']);
    });

    test('comments, full URLs and non-API .get calls are ignored; a parameter path is unresolved', () {
      expect(_scan(r'''
// _api.get('/api/v1/commented');
/* _api.get('/api/v1/block'); */
f(ApiClient _api, Map m, String path) {
  _api.get('https://example.com/file.pdf');
  m.get('key');
  prefs.get(key);
  _api.get(path);
}'''), ['GET ?']);
    });

    test('an instance getter is not confused with a static of the same name', () {
      expect(_scan(r'''
class A { static const base = '/api/v1/exam'; }
class OrgSession { String get base => '/api/v1/org/orgs/$id'; }
f(ApiClient api, OrgSession s) => api.get('${s.base}/rooms');'''), ['GET /api/v1/org/orgs/{}/rooms']);
    });
  });

  group('match', () {
    test('holes match parameters and parameters match literals', () {
      expect(templatesMatch('/api/v1/courses/{}', '/api/v1/courses/{course_id}'), isTrue);
      expect(templatesMatch('/api/v1/theme/mobile', '/api/v1/theme/{platform}'), isTrue);
      expect(templatesMatch('/api/v1/payouts/{}', '/api/v1/payouts/bank'), isTrue);
      expect(templatesMatch('/api/v1/courses/{}', '/api/v1/courses/{course_id:int}'), isTrue);
      expect(templatesMatch('/api/v1/courses/12', '/api/v1/courses/{course_id:int}'), isTrue);
    });

    test('a literal never matches an integer parameter', () {
      expect(templatesMatch('/api/v1/payments/transfer-status', '/api/v1/payments/{payment_id:int}'), isFalse);
      expect(templatesMatch('/api/v1/payments/transfer-status', '/api/v1/payments/{ref}'), isTrue);
    });

    test('an enum parameter takes only its words (or a run-time value)', () {
      const r = '/api/v1/ads/{ad_id:int}/{decision:approve|reject}';
      expect(templatesMatch('/api/v1/ads/{}/approve', r), isTrue);
      expect(templatesMatch('/api/v1/ads/{}/{}', r), isTrue);
      expect(templatesMatch('/api/v1/ads/{}/approved', r), isFalse);
    });

    test('different segments, extra or missing segments do not match', () {
      expect(templatesMatch('/api/v1/course/{}', '/api/v1/courses/{id}'), isFalse);
      expect(templatesMatch('/api/v1/courses/{}/x', '/api/v1/courses/{id}'), isFalse);
      expect(templatesMatch('/api/v1/courses', '/api/v1/courses/{id}'), isFalse);
      expect(templatesMatch('/api/v1/courses/', '/api/v1/courses'), isFalse);
    });

    test('a hole glued to a literal keeps only the prefix', () {
      expect(isPrefixOnly('/api/v1/admin{}'), isTrue);
      expect(templatesMatch('/api/v1/admin{}', '/api/v1/admin/users/{id}'), isTrue);
      expect(isPrefixOnly('/api/v1/admin/{}'), isFalse);
    });

    test('paths go to the service nginx sends them to', () {
      expect(serviceOf('/api/v1/exam/questions'), 'exam');
      expect(serviceOf('/api/v1/rag/ask'), 'rag');
      expect(serviceOf('/api/v1/models'), 'models');
      expect(serviceOf('/api/v1/models/12/activate'), 'models');
      expect(serviceOf('/api/v1/models-legacy'), 'core');
      expect(serviceOf('/api/v1/exams/1'), 'core');
      expect(serviceOf('/api/v1/auth/login'), 'core');
    });
  });
}
