// Exam Engine client (Phase 5, D-018): the student side of /api/v1/exam/… over the one ApiClient.
//
// Every call returns an [EngineResult]: `ok`, the JSON map, and on failure the ApiException's status / code so
// screens can map codes with `examCodeText`. `unavailable` is true when the engine is not routed yet (a bare 404
// "Not Found" / 405 from the proxy, or no network at all): the legacy exam flow stays in charge then.
import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asMap;

class EngineResult {
  EngineResult.ok(this.map) : ok = true, status = 200, code = null, message = '', detail = const {};
  EngineResult.fail(this.status, this.code, this.message, [this.detail = const {}]) : ok = false, map = const {};
  final bool ok;
  final Map<String, dynamic> map;

  /// The server's `detail` object on failure (`reason`, `question_id`, `allowed`, `starts_at`, …); empty when ok.
  final Map<String, dynamic> detail;
  final int status;
  final String? code;
  final String message;

  /// The engine is not deployed / not routed: FastAPI's bare 404 or a 405 from a stranger server.
  bool get unavailable => !ok && (code == null && (status == 404 || status == 405) && (message == 'Not Found' || message.isEmpty || status == 405));
}

Future<EngineResult> engineCall(Future<dynamic> Function() fn) async {
  try {
    final r = await fn();
    return EngineResult.ok(r is Map ? asMap(r) : {'value': r});
  } on ApiException catch (e) {
    final body = e.body;
    String? code = e.code;
    String msg = e.message;
    Map<String, dynamic> detail = const {};
    if (body is Map && body['detail'] is Map) {
      detail = asMap(body['detail']);
      code = (detail['code'] ?? code)?.toString();
      msg = '${detail['message'] ?? msg}';
    } else if (body is Map && body['detail'] is String) {
      msg = '${body['detail']}';
    }
    return EngineResult.fail(e.statusCode, code, msg, detail);
  } catch (e) {
    return EngineResult.fail(0, null, ApiException.from(e).message);
  }
}

class ExamEngineApi {
  ExamEngineApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/exam';

  Future<EngineResult> studentExams({int? courseId, int? orgId}) => engineCall(() => _api.get('$base/student/exams', queryParams: {
        if (courseId != null) 'course_id': courseId,
        if (orgId != null) 'org_id': orgId,
      }));

  Future<EngineResult> consent(int examId, {required String lang}) => engineCall(() => _api.get('$base/exams/$examId/consent', queryParams: {'lang': lang}));

  Future<EngineResult> acceptConsent(int examId, {required String textHash, required String lang, String? deviceId, required String platform}) =>
      engineCall(() => _api.post('$base/exams/$examId/consent/accept', body: {
            'text_hash': textHash,
            'lang': lang,
            'device_id': deviceId,
            'platform': platform,
          }));

  Future<EngineResult> start(int examId, {required String platform, String? deviceId, String? passcode}) =>
      engineCall(() => _api.post('$base/exams/$examId/attempts', body: {
            'platform': platform,
            'device_id': deviceId,
            if (passcode != null && passcode.isNotEmpty) 'passcode': passcode,
          }));

  Future<EngineResult> attempt(int attemptId) => engineCall(() => _api.get('$base/attempts/$attemptId'));

  Future<EngineResult> refreshSession(int attemptId, {String? deviceId}) =>
      engineCall(() => _api.post('$base/attempts/$attemptId/session', headers: _h(null, deviceId)));

  Future<EngineResult> save(int attemptId, List<Map<String, dynamic>> items, {required String session, String? deviceId}) =>
      engineCall(() => _api.put('$base/attempts/$attemptId/answers', body: {'items': items}, headers: _h(session, deviceId)));

  Future<EngineResult> submit(int attemptId, {required String session, String? deviceId}) =>
      engineCall(() => _api.post('$base/attempts/$attemptId/submit', headers: _h(session, deviceId)));

  Future<EngineResult> events(int attemptId, List<Map<String, dynamic>> events, {required String session, String? deviceId}) =>
      engineCall(() => _api.post('$base/attempts/$attemptId/events', body: {'events': events}, headers: _h(session, deviceId)));

  /// A `file_upload` answer: stored by the server, which saves the answer as {file: {name, content_type, size, sha256}}.
  Future<EngineResult> uploadAnswerFile(int attemptId, int questionId,
          {required String fileName, Uint8List? bytes, String? path, required String session, String? deviceId}) =>
      engineCall(() => _api.postMultipart('$base/attempts/$attemptId/files?question_id=$questionId',
          fields: const {}, fileField: 'file', fileName: fileName, fileBytes: bytes, filePath: path, headers: _h(session, deviceId)));

  /// The exam given as a file (settings.paper_file), while the student may sit it.
  Future<Uint8List> paperFile(int examId) => _api.getBytes('$base/exams/$examId/paper-file');

  Future<EngineResult> result(int attemptId) => engineCall(() => _api.get('$base/attempts/$attemptId/result'));

  static Map<String, String> _h(String? session, String? deviceId) => {
        if (session != null) 'X-Exam-Session': session,
        if (deviceId != null && deviceId.isNotEmpty) 'X-Device-Id': deviceId,
      };
}
