// Meeting recordings → Google Drive / OneDrive (docs/backend/live-rooms-spec.md §5): the pure part —
// GET /me/cloud parsing, the quality → recorder settings, the recording's statuses, the start answer, server
// codes → bilingual text, and the API's paths.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/live/meeting_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('cloud accounts', () {
    test('every provider is listed in a fixed order; a missing one is "not available"', () {
      final list = cloudAccountsFrom({
        'providers': [
          {'provider': 'onedrive', 'available': true, 'connected': true, 'email': 'a@b.c', 'connected_at': '2026-10-27T10:00:00'},
        ],
      });
      expect(list.map((a) => a.provider), [CloudProvider.googleDrive, CloudProvider.onedrive]);
      expect(list[0].available, isFalse);
      expect(list[0].usable, isFalse);
      expect(list[1].usable, isTrue);
      expect(list[1].email, 'a@b.c');
      expect(list[1].connectedAt, DateTime.utc(2026, 10, 27, 10));
    });

    test('available but not connected is not usable; unknown providers are skipped', () {
      final list = cloudAccountsFrom({
        'providers': [
          {'provider': 'google_drive', 'available': true, 'connected': false},
          {'provider': 'dropbox', 'available': true, 'connected': true},
        ],
      });
      expect(list.length, 2);
      expect(list[0].available, isTrue);
      expect(list[0].connected, isFalse);
      expect(list[0].usable, isFalse);
      expect(CloudProvider.fromWire('dropbox'), isNull);
    });

    test('an empty or odd body gives both providers unavailable', () {
      expect(cloudAccountsFrom(null).every((a) => !a.available), isTrue);
      expect(cloudAccountsFrom('x').length, 2);
    });

    test('configured: the new key wins, an older server\'s available is the fallback, neither means configured', () {
      final list = cloudAccountsFrom({
        'providers': [
          {'provider': 'google_drive', 'configured': false, 'available': true, 'connected': true},
          {'provider': 'onedrive', 'available': false},
        ],
      });
      expect(list[0].configured, isFalse);
      expect(list[0].available, isFalse, reason: 'available is the older name of configured');
      expect(list[0].usable, isFalse, reason: 'a connected drive of an unconfigured provider cannot record');
      expect(list[1].configured, isFalse);
      expect(cloudConfiguredFrom({'provider': 'onedrive', 'configured': true, 'available': false}), isTrue);
      expect(cloudConfiguredFrom({'provider': 'onedrive', 'available': true}), isTrue);
      expect(cloudConfiguredFrom({'provider': 'onedrive', 'connected': true}), isTrue);
      expect(cloudConfiguredFrom({'provider': 'onedrive', 'configured': null, 'available': false}), isFalse);
    });

    test('markCloudUnconfigured greys one provider and keeps the rest', () {
      const g = CloudAccount(provider: CloudProvider.googleDrive, configured: true, connected: true, email: 'a@b.c');
      const o = CloudAccount(provider: CloudProvider.onedrive, configured: true);
      final out = markCloudUnconfigured(const [g, o], CloudProvider.googleDrive)!;
      expect(out[0].configured, isFalse);
      expect(out[0].connected, isTrue);
      expect(out[0].email, 'a@b.c');
      expect(out[1].configured, isTrue);
      expect(markCloudUnconfigured(null, CloudProvider.onedrive), isNull);
    });

    test('wire values and labels', () {
      expect(CloudProvider.googleDrive.wire, 'google_drive');
      expect(CloudProvider.onedrive.wire, 'onedrive');
      expect(CloudProvider.fromWire('GOOGLE_DRIVE'), CloudProvider.googleDrive);
      expect(CloudProvider.googleDrive.label, 'Google Drive');
    });
  });

  group('quality', () {
    test('wire values match the spec; an unknown value falls back to 720p', () {
      expect(RecordingQuality.values.map((q) => q.wire), ['1080p', '720p', '480p', 'audio']);
      expect(RecordingQuality.fromWire('480p'), RecordingQuality.p480);
      expect(RecordingQuality.fromWire('8k'), RecordingQuality.p720);
      expect(RecordingQuality.fromWire(null, fallback: RecordingQuality.audio), RecordingQuality.audio);
    });

    test('recorder settings: bitrate and height cap fall with the quality; the video ones are never audio-only', () {
      final s1080 = RecorderSettings.of(RecordingQuality.p1080);
      final s720 = RecorderSettings.of(RecordingQuality.p720);
      final s480 = RecorderSettings.of(RecordingQuality.p480);
      expect(s1080.maxHeight, 1080);
      expect(s720.maxHeight, 720);
      expect(s480.maxHeight, 480);
      expect(s1080.videoBitsPerSecond > s720.videoBitsPerSecond, isTrue);
      expect(s720.videoBitsPerSecond > s480.videoBitsPerSecond, isTrue);
      for (final q in [RecordingQuality.p1080, RecordingQuality.p720, RecordingQuality.p480]) {
        expect(q.audioOnly, isFalse, reason: q.wire);
        expect(RecorderSettings.of(q).audioOnly, isFalse, reason: q.wire);
        expect(RecorderSettings.of(q).toMap()['audioOnly'], isFalse, reason: q.wire);
      }
      expect(s720.toMap(), {'videoBitrate': 3000000, 'maxHeight': 720, 'audioOnly': false});
    });

    test('audio is a real audio-only capture: audioOnly on the wire, no video bitrate or height cap', () {
      final audio = RecorderSettings.of(RecordingQuality.audio);
      expect(RecordingQuality.audio.audioOnly, isTrue);
      expect(audio.audioOnly, isTrue);
      expect(audio.videoBitsPerSecond, 0, reason: 'nothing encodes video');
      expect(audio.maxHeight, 0, reason: 'nothing scales a frame');
      // What ClientRecorder hands the native start call (`...?encoder`) and the web compositor's start meta.
      expect(audio.toMap(), {'videoBitrate': 0, 'maxHeight': 0, 'audioOnly': true});
      expect(audio.toMap()['audioOnly'], isA<bool>());
    });

    test('labels exist in both languages', () {
      for (final q in RecordingQuality.values) {
        AppConfig.lang = 'ar';
        final ar = q.label;
        AppConfig.lang = 'en';
        expect(q.label, isNot(ar), reason: q.wire);
      }
    });
  });

  group('recording start', () {
    test('parses the 201 answer; the stop path matches the chunk path', () {
      final r = RecordingStart.fromJson({'recording_id': 9, 'status': 'recording', 'chunk_path': '/api/v1/live/recordings/9/chunk'});
      expect(r.recordingId, 9);
      expect(r.chunkPath, '/api/v1/live/recordings/9/chunk');
      expect(r.stopPath, '/api/v1/live/recordings/9/stop');
      expect(r.quality, RecordingQuality.p720);
      expect(r.copyWith(quality: RecordingQuality.audio).quality, RecordingQuality.audio);
    });

    test('a missing chunk_path is derived from the id', () {
      expect(RecordingStart.fromJson({'recording_id': 4}).chunkPath, recordingChunkPath(4));
    });
  });

  group('recordings', () {
    final done = {
      'recording_id': 12,
      'kind': 'meeting',
      'id': 7,
      'status': 'done',
      'quality': '720p',
      'destination': 'google_drive',
      'size': 52428800,
      'duration_seconds': 3725,
      'remote_url': 'https://drive.google.com/file/d/x/view',
      'created_at': '2026-10-27T09:00:00',
      'finished_at': '2026-10-27T10:05:00',
    };

    test('parses the GET answer', () {
      final r = MeetingRecording.fromJson(done)!;
      expect(r.id, 12);
      expect(r.refId, 7);
      expect(r.isDone, isTrue);
      expect(r.inProgress, isFalse);
      expect(r.canOpen, isTrue);
      expect(r.destination, CloudProvider.googleDrive);
      expect(r.quality, RecordingQuality.p720);
      expect(r.finishedAt, DateTime.utc(2026, 10, 27, 10, 5));
      expect(recordingSizeLabel(r.size), '50.0 MB');
      expect(recordingDurationLabel(r.durationSeconds), '01:02:05');
    });

    test('statuses: recording / assembling / uploading poll; failed retries; unknown → recording', () {
      for (final s in ['recording', 'assembling', 'uploading']) {
        final r = MeetingRecording.fromJson({...done, 'status': s, 'remote_url': null})!;
        expect(r.inProgress, isTrue, reason: s);
        expect(r.canOpen, isFalse, reason: s);
      }
      final failed = MeetingRecording.fromJson({...done, 'status': 'failed', 'error': 'quota', 'remote_url': null})!;
      expect(failed.isFailed, isTrue);
      expect(failed.error, 'quota');
      expect(MeetingRecording.fromJson({...done, 'status': 'weird'})!.status, 'recording');
      expect(MeetingRecording.fromJson({'status': 'done'}), isNull, reason: 'no id');
    });

    test('a done recording without an https link cannot be opened', () {
      expect(MeetingRecording.fromJson({...done, 'remote_url': 'http://x'})!.canOpen, isFalse);
      expect(MeetingRecording.fromJson({...done, 'remote_url': ''})!.canOpen, isFalse);
    });

    test('the list is newest first, from a bare list or an {items} / {recordings} envelope', () {
      final older = {...done, 'recording_id': 11, 'created_at': '2026-10-26T09:00:00'};
      expect(recordingsFrom([older, done]).map((r) => r.id), [12, 11]);
      expect(recordingsFrom({'items': [older, done]}).map((r) => r.id), [12, 11]);
      expect(recordingsFrom({'recordings': [done]}).length, 1);
      expect(recordingsFrom(null), isEmpty);
    });

    test('the meeting detail carries the latest recording (or none)', () {
      expect(MeetingRecording.latestOf({'id': 7, 'recording': done})?.id, 12);
      expect(MeetingRecording.latestOf({'id': 7, 'recording': null}), isNull);
      expect(MeetingRecording.latestOf({'id': 7}), isNull);
    });

    test('status labels exist in both languages', () {
      for (final s in recordingStatuses) {
        AppConfig.lang = 'ar';
        final ar = recordingStatusLabel(s);
        AppConfig.lang = 'en';
        expect(recordingStatusLabel(s), isNot(ar), reason: s);
      }
      expect(recordingStatusLabel('done'), 'Ready');
    });
  });

  group('errors', () {
    ApiException coded(String code, {int status = 409}) =>
        ApiException(statusCode: status, message: 'raw', type: ApiErrorType.conflict, code: code);

    test('the three 409 codes of the spec and the cloud ones have bilingual text', () {
      for (final code in ['cloud_not_connected', 'course_session_recording', 'recording_active', 'cloud_auth_failed',
        'cloud_provider_unconfigured', 'cloud_provider_unavailable']) {
        AppConfig.lang = 'ar';
        final ar = meetingRecordingErrorText(coded(code));
        AppConfig.lang = 'en';
        final en = meetingRecordingErrorText(coded(code));
        expect(en, isNot('raw'), reason: code);
        expect(ar, isNot(en), reason: code);
      }
      expect(meetingRecordingErrorText(coded('cloud_not_connected')), contains('Connected drives'));
    });

    test('503 cloud_provider_unconfigured (and an older 409 cloud_provider_unavailable) name the provider', () {
      const body = {
        'detail': {'code': 'cloud_provider_unconfigured', 'message': 'raw', 'provider': 'google_drive'},
      };
      const e503 = ApiException(statusCode: 503, message: 'raw', type: ApiErrorType.server, code: 'cloud_provider_unconfigured', body: body);
      expect(isCloudUnconfigured(e503), isTrue);
      expect(cloudProviderOfError(e503), CloudProvider.googleDrive);
      expect(meetingRecordingErrorText(e503), "Google Drive isn't set up on this server yet. Ask the platform admin to set it up.");
      AppConfig.lang = 'ar';
      expect(meetingRecordingErrorText(e503), 'ربط Google Drive غير متاح على هذا الخادم بعد. اطلب من مسؤول المنصة إعداده.');
      AppConfig.lang = 'en';
      final old = coded('cloud_provider_unavailable');
      expect(isCloudUnconfigured(old), isTrue);
      expect(cloudProviderOfError(old), isNull);
      expect(meetingRecordingErrorText(old), contains('Ask the platform admin'));
      expect(cloudUnconfiguredText(CloudProvider.onedrive), startsWith('OneDrive'));
      expect(isCloudUnconfigured(coded('cloud_not_connected')), isFalse);
      expect(isCloudUnconfigured(Exception('x')), isFalse);
    });

    test('a bare 404 / 405 means the server lacks the routes; other errors keep their message', () {
      expect(meetingRecordingErrorText(const ApiException(statusCode: 404, message: 'Not Found')), contains('server update'));
      expect(meetingRecordingErrorText(const ApiException(statusCode: 500, message: 'boom')), 'boom');
      expect(meetingRecordingErrorText(Exception('x')), isNotEmpty);
    });
  });

  group('paths', () {
    test('chunk and stop routes', () {
      expect(recordingChunkPath(3), '/api/v1/live/recordings/3/chunk');
      expect(recordingStopPath(3), '/api/v1/live/recordings/3/stop');
    });

    test('parseRecordingTime treats naive stamps as UTC', () {
      expect(parseRecordingTime('2026-01-02T03:04:05'), DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(parseRecordingTime('2026-01-02T03:04:05+02:00'), DateTime.utc(2026, 1, 2, 1, 4, 5));
      expect(parseRecordingTime(null), isNull);
      expect(parseRecordingTime(''), isNull);
    });
  });
}
