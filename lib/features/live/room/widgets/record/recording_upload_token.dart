// recording_upload_token.dart
//
// The device recording's upload token (live hardening A7 / I10, ../back/FLUTTER_API_CHANGES.md "Device recording
// upload token"). A lecture longer than the 60-minute access token used to 401 its chunk uploads; the recorder now
// asks once at start for a token scoped to its own chunk route and run, and every uploader (web compositor,
// Android ScreenCaptureService, iOS AppDelegate) sends it as `Authorization: Bearer <upload token>` — the header
// they already send, so the native side needs no change for the token itself.
//
//   recordingUploadTokenPath   which route issues it: the course session's
//                              `POST /live-sessions/{id}/recording-upload-token`, a meeting recording's
//                              `POST /live/recordings/{rid}/upload-token`; null for any other chunk route.
//   recordingUploadTokenFrom   the token in the answer.
//   resolveRecordingUploadAuth the Authorization value: the upload token, else the access token (an older server
//                              answers the route with a bare 404 / 405; any other failure falls back too — the access
//                              token still works on both chunk routes, it only runs out after an hour).
//   newRecordingEpoch          the per-start id sent as the chunk field `epoch` (a restarted recorder never
//                              overwrites earlier footage; assembly orders by (epoch, index)).
//   recordingChunkVerdict      what an uploader does with a chunk answer: 409 recording_assembled = done, stop
//                              uploading; 409 recording_assembling = keep the chunk; other 4xx = drop; 5xx = retry.
//
// Pure (the HTTP calls are passed in), unit-tested in test/org/recording_upload_token_test.dart.
library;

import 'package:flutter_education_app/core/api_client.dart' show ApiException;

/// The route that issues the upload token for a recorder posting to [chunkPath] (null = the course session's own
/// route for [sessionId]); null when the chunk route is not one the server issues tokens for.
String? recordingUploadTokenPath({required int sessionId, String? chunkPath}) {
  if (chunkPath == null || chunkPath.isEmpty) {
    return sessionId > 0 ? '/api/v1/live-sessions/$sessionId/recording-upload-token' : null;
  }
  final meeting = RegExp(r'^/api/v1/live/recordings/(\d+)/chunk/?$').firstMatch(chunkPath);
  if (meeting != null) return '/api/v1/live/recordings/${meeting.group(1)}/upload-token';
  final session = RegExp(r'^/api/v1/live-sessions/(\d+)/recording-chunk/?$').firstMatch(chunkPath);
  if (session != null) return '/api/v1/live-sessions/${session.group(1)}/recording-upload-token';
  return null;
}

/// `upload_token` of the issue answer; null when it carries none.
String? recordingUploadTokenFrom(dynamic body) {
  if (body is! Map) return null;
  final t = body['upload_token'];
  return t is String && t.trim().isNotEmpty ? t.trim() : null;
}

/// Where the Authorization value came from.
enum RecordingAuthSource { uploadToken, accessToken }

/// Why the access token is used instead.
enum RecordingAuthFallback {
  /// No route to ask (a chunk route without tokens).
  noRoute,

  /// The server has no such route yet (bare 404 / 405).
  olderServer,

  /// The request failed otherwise (no live run, network, …), or answered without a token.
  failed,
}

/// A bare 404 / 405 (no server code): the route does not exist on this server.
bool recordingUploadTokenRouteMissing(Object error) {
  final ex = ApiException.from(error);
  return (ex.statusCode == 404 || ex.statusCode == 405) && (ex.code == null || ex.code!.isEmpty);
}

class RecordingUploadAuth {
  const RecordingUploadAuth(this.authorization, this.source, {this.fallback});

  /// The `Authorization` header value the uploaders send (`Bearer <token>`).
  final String authorization;
  final RecordingAuthSource source;

  /// Set when [source] is the access token.
  final RecordingAuthFallback? fallback;

  @override
  String toString() => 'RecordingUploadAuth(${source.name}${fallback == null ? '' : ', ${fallback!.name}'})';
}

/// Asks [post] for the upload token at [tokenPath]; falls back to [accessToken] when there is no route, the server
/// is older (404 / 405) or the request failed. Never throws.
Future<RecordingUploadAuth> resolveRecordingUploadAuth({
  required String? tokenPath,
  required Future<dynamic> Function(String path) post,
  required Future<String?> Function() accessToken,
}) async {
  Future<RecordingUploadAuth> access(RecordingAuthFallback why) async {
    String token = '';
    try {
      token = (await accessToken()) ?? '';
    } catch (_) {}
    return RecordingUploadAuth('Bearer $token', RecordingAuthSource.accessToken, fallback: why);
  }

  if (tokenPath == null) return access(RecordingAuthFallback.noRoute);
  try {
    final token = recordingUploadTokenFrom(await post(tokenPath));
    if (token == null) return await access(RecordingAuthFallback.failed);
    return RecordingUploadAuth('Bearer $token', RecordingAuthSource.uploadToken);
  } catch (e) {
    return await access(
        recordingUploadTokenRouteMissing(e) ? RecordingAuthFallback.olderServer : RecordingAuthFallback.failed);
  }
}

/// A new id for one recorder start (the chunk field `epoch`, ≤ 64 chars): its start time in milliseconds.
String newRecordingEpoch(DateTime now) => '${now.millisecondsSinceEpoch}';

/// What an uploader does with a chunk's answer.
enum RecordingChunkVerdict {
  uploaded,

  /// 409 recording_assembled: the run's recording is assembled — stop uploading, the recording is done.
  assembled,

  /// 409 recording_assembling: being assembled right now — keep the chunk (an empty ping is still accepted).
  keep,

  /// Another 4xx (no live run, a revoked / expired upload token, another user, too large): retrying cannot help.
  drop,

  /// No answer, 408 / 429 or 5xx: try again later.
  retry,
}

RecordingChunkVerdict recordingChunkVerdict(int status, String? code) {
  if (status >= 200 && status < 300) return RecordingChunkVerdict.uploaded;
  if (status == 409 && code == 'recording_assembled') return RecordingChunkVerdict.assembled;
  if (status == 409 && code == 'recording_assembling') return RecordingChunkVerdict.keep;
  if (status == 0 || status == 408 || status == 429 || status >= 500) return RecordingChunkVerdict.retry;
  return RecordingChunkVerdict.drop;
}
