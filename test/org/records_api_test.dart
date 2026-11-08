// Records (D-311): the pure part — parsing the library rows the server sends, grouping by meeting, times as mm:ss,
// the edit rules (the server's MIN_PART / speeds), the request bodies and the play URL.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/meeting_recording.dart';
import 'package:flutter_education_app/features/shared/records/records_api.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(int id, {String status = 'done', String kind = 'meeting', int meeting = 7, String created = '2026-11-08T09:00:00',
        String? op, Map<String, dynamic>? params, List<int> sources = const [], String quality = '720p', String? title}) =>
    {
      'recording_id': id,
      'kind': kind,
      'id': meeting,
      'status': status,
      'quality': quality,
      'destination': 'google_drive',
      'file_name': 'Weekly sync – 2026-11-08.mp4',
      'size': 734003200,
      'duration_seconds': 125.6,
      'remote_url': status == 'done' ? 'https://drive.google.com/file/d/x/view' : null,
      'error': status == 'failed' ? 'cloud_unreachable: down' : null,
      'retry_mode': status == 'failed' ? 'manual' : null,
      'created_at': created,
      'finished_at': null,
      'title': title ?? 'Weekly sync',
      'custom_title': title != null,
      'cover_url': null,
      'operation': op,
      'op_params': params,
      'source_ids': sources,
      'stage': status == 'assembling' ? 'processing' : null,
      'progress': status == 'assembling' ? 50 : null,
      'media': quality == 'audio' ? 'audio' : 'video',
      'meeting': {'id': meeting, 'title': 'Weekly sync', 'starts_at': '2026-11-08T08:00:00'},
      'can_edit': status == 'done',
      'can_play': status == 'done',
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('parses a library row (summary + Records fields), naive UTC times', () {
    final r = RecordItem.fromJson(_row(5, op: 'speed', params: {'speed': 1.5}, sources: [2], kind: 'edit', title: 'Fast'))!;
    expect(r.id, 5);
    expect(r.isEdit, isTrue);
    expect(r.title, 'Fast');
    expect(r.customTitle, isTrue);
    expect(r.operation, RecordOp.speed);
    expect(r.opParams['speed'], 1.5);
    expect(r.sourceIds, [2]);
    expect(r.durationSeconds, 125.6);
    expect(r.destination, CloudProvider.googleDrive);
    expect(r.meetingId, 7);
    expect(r.meetingTitle, 'Weekly sync');
    expect(r.meetingAt, DateTime.utc(2026, 11, 8, 8));
    expect(r.createdAt, DateTime.utc(2026, 11, 8, 9));
    expect(r.canEdit && r.mergeable && r.canOpenDrive, isTrue);
    final running = RecordItem.fromJson(_row(6, status: 'assembling'))!;
    expect(running.inProgress, isTrue);
    expect(running.stage, 'processing');
    expect(running.progress, 50);
    expect(running.mergeable, isFalse);
    expect(recordStatusLabel(running), 'Editing');
    expect(RecordItem.fromJson(_row(8, quality: 'audio'))!.isAudio, isTrue);
    expect(RecordItem.fromJson({'recording_id': 0}), isNull);
    // an older answer without the Records fields still parses (title from the meeting / file name)
    final old = RecordItem.fromJson({'recording_id': 3, 'status': 'done', 'id': 9, 'file_name': 'x.mp4'})!;
    expect(old.title, 'x.mp4');
    expect(old.meetingId, 9);
    expect(old.canEdit, isFalse);
  });

  test('newest first, grouped by meeting (the newest group first), edits replace in place', () {
    final items = recordsFrom({
      'items': [
        _row(1, created: '2026-11-01T10:00:00', meeting: 1),
        _row(2, created: '2026-11-03T10:00:00', meeting: 2),
        _row(3, created: '2026-11-04T10:00:00', meeting: 1, kind: 'edit', op: 'trim'),
      ]
    });
    expect([for (final r in items) r.id], [3, 2, 1]);
    final groups = groupRecords(items);
    expect([for (final g in groups) g.meetingId], [1, 2]);
    expect([for (final r in groups.first.items) r.id], [3, 1]);
    final fresh = RecordItem.fromJson(_row(2, status: 'failed', created: '2026-11-03T10:00:00', meeting: 2))!;
    final merged = mergeRecordItems(items, [fresh, RecordItem.fromJson(_row(9, created: '2026-11-08T10:00:00'))!]);
    expect([for (final r in merged) r.id], [9, 3, 2, 1]);
    expect(merged.firstWhere((r) => r.id == 2).isFailed, isTrue);
    expect([for (final r in withoutRecords(merged, {3, 9})) r.id], [2, 1]);
  });

  test('mm:ss and back', () {
    expect(mmss(0), '00:00');
    expect(mmss(59.9), '00:59');
    expect(mmss(125.6), '02:05');
    expect(mmss(3725), '1:02:05');
    expect(mmss(double.nan), '00:00');
    expect(parseMmss('02:05'), 125);
    expect(parseMmss('1:02:05'), 3725);
    expect(parseMmss('90'), 90);
    expect(parseMmss('1:75'), isNull);
    expect(parseMmss('x'), isNull);
    expect(speedLabel(2), '×2');
    expect(speedLabel(0.75), '×0.75');
  });

  test('edit rules follow the server (1 s pieces, never the whole thing, the five speeds)', () {
    expect(editProblem(const RecordEdit(op: RecordOp.trim, start: 10, end: 40), 120), isNull);
    expect(editProblem(const RecordEdit(op: RecordOp.trim, start: 10, end: 10.5), 120), isNotNull);
    expect(editProblem(const RecordEdit(op: RecordOp.trim, start: 130, end: 140), 120), isNotNull);
    expect(editProblem(const RecordEdit(op: RecordOp.cut, start: 0, end: 120), 120), isNotNull);
    expect(editProblem(const RecordEdit(op: RecordOp.cut, start: 0, end: 119), 120), isNull);
    expect(editProblem(const RecordEdit(op: RecordOp.split, at: 0.5), 120), isNotNull);
    expect(editProblem(const RecordEdit(op: RecordOp.split, at: 119.5), 120), isNotNull);
    expect(editProblem(const RecordEdit(op: RecordOp.split, at: 60), 120), isNull);
    expect(editProblem(const RecordEdit(op: RecordOp.speed, speed: 3), 120), isNotNull);
    for (final s in recordSpeeds) {
      expect(editProblem(RecordEdit(op: RecordOp.speed, speed: s), 120), isNull);
    }
    expect(editResultDurations(const RecordEdit(op: RecordOp.trim, start: 10, end: 40), 120), [30]);
    expect(editResultDurations(const RecordEdit(op: RecordOp.cut, start: 10, end: 20), 120), [110]);
    expect(editResultDurations(const RecordEdit(op: RecordOp.split, at: 50), 120), [50, 70]);
    expect(editResultDurations(const RecordEdit(op: RecordOp.speed, speed: 2), 120), [60]);
  });

  test('request bodies carry only what the operation reads', () {
    expect(const RecordEdit(op: RecordOp.trim, start: 1.23456, end: 9, at: 4, speed: 2, title: '  Clip ').toJson(),
        {'op': 'trim', 'start': 1.235, 'end': 9.0, 'title': 'Clip'});
    expect(const RecordEdit(op: RecordOp.split, start: 1, end: 2, at: 30).toJson(), {'op': 'split', 'at': 30.0});
    expect(const RecordEdit(op: RecordOp.speed, speed: 0.5, deleteSource: true).toJson(),
        {'op': 'speed', 'speed': 0.5, 'delete_source': true});
    expect(defaultEditTitle('Sync', RecordOp.speed, speed: 1.5), 'Sync · ×1.5');
    expect(defaultEditTitle('Sync', RecordOp.trim), 'Sync · Trimmed');
  });

  test('the play URL is made absolute on the API base', () {
    final p = RecordPlay.fromJson({'url': '/api/v1/me/records/stream/tok', 'mime': 'audio/mp4', 'expires_in': 7200},
        base: 'https://nextbrain.site/api/');
    expect(p.url, 'https://nextbrain.site/api/api/v1/me/records/stream/tok');
    expect(p.audio, isTrue);
    expect(p.expiresIn, 7200);
    expect(RecordPlay.fromJson({'url': 'https://x.test/s'}, base: 'https://b').url, 'https://x.test/s');
  });

  test('coded refusals have their own words', () {
    expect(recordsCodes.containsKey('records_busy') && recordsCodes.containsKey('cloud_delete_failed'), isTrue);
  });

  group('quality and size (D-318)', () {
    test('the body carries only what was chosen', () {
      expect(const RecordEdit(op: RecordOp.quality, height: 480, level: StudioQualityLevel.small).toJson(),
          {'op': 'quality', 'height': 480, 'level': 'small'});
      expect(const RecordEdit(op: RecordOp.quality, level: StudioQualityLevel.best).toJson(), {'op': 'quality', 'level': 'best'});
      expect(RecordOp.fromWire('quality'), RecordOp.quality);
    });

    test('nothing to refuse; the length stays', () {
      const e = RecordEdit(op: RecordOp.quality, level: StudioQualityLevel.balanced);
      expect(editProblem(e, 100), isNull);
      expect(editResultDurations(e, 100), [100.0]);
    });

    test('the ceiling follows height and level (kbps + 128 of sound), the source height when the size stays', () {
      int at(int? h, StudioQualityLevel l, {int source = 720}) =>
          studioQualityCeilingBytes(100, height: h, level: l, sourceHeight: source);
      expect(at(480, StudioQualityLevel.small), (500 + 128) * 1000 / 8 * 100);
      expect(at(1080, StudioQualityLevel.best), (5500 + 128) * 1000 / 8 * 100);
      expect(at(null, StudioQualityLevel.balanced), at(720, StudioQualityLevel.balanced));
      expect(at(null, StudioQualityLevel.balanced, source: 1080), at(1080, StudioQualityLevel.balanced));
      expect(at(720, StudioQualityLevel.small), lessThan(at(720, StudioQualityLevel.best)));
    });

    test('the default name says the new height', () {
      expect(defaultEditTitle('Math', RecordOp.quality, height: 480), 'Math · 480p');
    });
  });
}
