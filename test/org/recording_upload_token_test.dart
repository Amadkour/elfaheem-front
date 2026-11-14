// The device recording's upload token (A7 / I10) and chunk answers (R1 / R4): which route issues it, the fallback
// to the access token, the per-start epoch and what an uploader does with each answer.
import 'package:dio/dio.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/live/room/widgets/record/recording_upload_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('token route', () {
    test('course session, meeting recording, unknown routes', () {
      expect(recordingUploadTokenPath(sessionId: 12), '/api/v1/live-sessions/12/recording-upload-token');
      expect(recordingUploadTokenPath(sessionId: 12, chunkPath: '/api/v1/live-sessions/12/recording-chunk'),
          '/api/v1/live-sessions/12/recording-upload-token');
      expect(recordingUploadTokenPath(sessionId: -7, chunkPath: '/api/v1/live/recordings/55/chunk'),
          '/api/v1/live/recordings/55/upload-token');
      expect(recordingUploadTokenPath(sessionId: -7), isNull, reason: 'a meeting without a recording route');
      expect(recordingUploadTokenPath(sessionId: 12, chunkPath: '/api/v1/other/chunk'), isNull);
    });

    test('the token in the answer', () {
      expect(recordingUploadTokenFrom({'upload_token': ' abc ', 'header': 'X-Upload-Token'}), 'abc');
      expect(recordingUploadTokenFrom({'upload_token': ''}), isNull);
      expect(recordingUploadTokenFrom({'token': 'abc'}), isNull);
      expect(recordingUploadTokenFrom(null), isNull);
      expect(recordingUploadTokenFrom('abc'), isNull);
    });
  });

  group('resolve', () {
    Future<String?> access() async => 'ACCESS';

    test('the upload token when the server issues one', () async {
      final asked = <String>[];
      final a = await resolveRecordingUploadAuth(
        tokenPath: '/api/v1/live-sessions/12/recording-upload-token',
        post: (p) async {
          asked.add(p);
          return {'upload_token': 'UP', 'header': 'X-Upload-Token'};
        },
        accessToken: access,
      );
      expect(asked, ['/api/v1/live-sessions/12/recording-upload-token']);
      expect(a.authorization, 'Bearer UP');
      expect(a.source, RecordingAuthSource.uploadToken);
      expect(a.fallback, isNull);
    });

    test('an older server (bare 404 / 405) falls back to the access token', () async {
      for (final status in [404, 405]) {
        final a = await resolveRecordingUploadAuth(
          tokenPath: '/x',
          post: (_) async => throw ApiException(statusCode: status, message: 'Not Found'),
          accessToken: access,
        );
        expect(a.authorization, 'Bearer ACCESS');
        expect(a.source, RecordingAuthSource.accessToken);
        expect(a.fallback, RecordingAuthFallback.olderServer);
      }
    });

    test('any other failure, an empty answer or no route fall back too (never throws)', () async {
      final coded = await resolveRecordingUploadAuth(
        tokenPath: '/x',
        post: (_) async => throw const ApiException(statusCode: 409, message: 'x', code: 'live_not_started'),
        accessToken: access,
      );
      expect(coded.fallback, RecordingAuthFallback.failed);
      expect(coded.authorization, 'Bearer ACCESS');

      final coded404 = await resolveRecordingUploadAuth(
        tokenPath: '/x',
        post: (_) async => throw const ApiException(statusCode: 404, message: 'x', code: 'recording_not_found'),
        accessToken: access,
      );
      expect(coded404.fallback, RecordingAuthFallback.failed, reason: 'a coded 404 is the route answering');

      final network = await resolveRecordingUploadAuth(
        tokenPath: '/x',
        post: (_) async => throw DioException(requestOptions: RequestOptions(path: '/x')),
        accessToken: access,
      );
      expect(network.fallback, RecordingAuthFallback.failed);

      final empty = await resolveRecordingUploadAuth(tokenPath: '/x', post: (_) async => {}, accessToken: access);
      expect(empty.fallback, RecordingAuthFallback.failed);

      var posted = false;
      final none = await resolveRecordingUploadAuth(
        tokenPath: null,
        post: (_) async => posted = true,
        accessToken: () async => null,
      );
      expect(posted, isFalse);
      expect(none.fallback, RecordingAuthFallback.noRoute);
      expect(none.authorization, 'Bearer ');

      final brokenStore = await resolveRecordingUploadAuth(
        tokenPath: null,
        post: (_) async => null,
        accessToken: () async => throw StateError('storage'),
      );
      expect(brokenStore.authorization, 'Bearer ');
    });
  });

  test('epoch: one id per start, at most 64 characters', () {
    final a = newRecordingEpoch(DateTime.utc(2026, 10, 29, 10));
    final b = newRecordingEpoch(DateTime.utc(2026, 10, 29, 10, 0, 1));
    expect(a, isNot(b));
    expect(a.length, lessThanOrEqualTo(64));
    expect(int.tryParse(a), isNotNull);
  });

  test('chunk answers', () {
    expect(recordingChunkVerdict(200, null), RecordingChunkVerdict.uploaded);
    expect(recordingChunkVerdict(409, 'recording_assembled'), RecordingChunkVerdict.assembled);
    expect(recordingChunkVerdict(409, 'recording_assembling'), RecordingChunkVerdict.keep);
    expect(recordingChunkVerdict(401, 'upload_token_revoked'), RecordingChunkVerdict.drop);
    expect(recordingChunkVerdict(403, 'upload_token_scope'), RecordingChunkVerdict.drop);
    expect(recordingChunkVerdict(409, null), RecordingChunkVerdict.drop);
    expect(recordingChunkVerdict(0, null), RecordingChunkVerdict.retry);
    expect(recordingChunkVerdict(429, 'too_many_requests'), RecordingChunkVerdict.retry);
    expect(recordingChunkVerdict(503, null), RecordingChunkVerdict.retry);
  });
}
