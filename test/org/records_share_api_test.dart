// Records sharing + the Studio filmstrip (D-312): parsing the server's answers, the `/s/record/<token>` link.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/features/records/records_share_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('a share: mode, link, people (opened or not), views; off drops the token', () {
    final s = RecordShare.fromJson({
      'record_id': 12,
      'mode': 'people',
      'token': 'abcDEF123_-xyz',
      'link': 'https://nextbrain.site/s/record/abcDEF123_-xyz',
      'people': [
        {'id': 5, 'name': 'Mona', 'username': 'mona', 'added_at': '2026-11-08T09:00:00', 'opened_at': '2026-11-08T10:00:00'},
        {'id': 6, 'name': 'Omar', 'added_at': '2026-11-08T09:00:00', 'opened_at': null},
        {'id': 0, 'name': 'broken'},
      ],
      'views': 3,
    });
    expect(s.recordId, 12);
    expect(s.mode, RecordShareMode.people);
    expect(s.active, isTrue);
    expect(s.link, endsWith('/s/record/abcDEF123_-xyz'));
    expect(s.people.map((p) => p.id), [5, 6]);
    expect(s.people.first.openedAt, isNotNull);
    expect(s.people.last.openedAt, isNull);
    expect(s.summary(), 'With 2 people · 3 views');

    final off = RecordShare.fromJson({'record_id': 12, 'mode': 'off', 'token': 'stale', 'link': 'x', 'people': []});
    expect(off.active, isFalse);
    expect(off.token, isNull);
    expect(off.link, isNull);
    expect(RecordShare.fromJson({'mode': 'weird'}, recordId: 4).mode, RecordShareMode.off);
    expect(RecordShare.fromJson({'mode': 'link'}, recordId: 4).summary(), 'Anyone with the link');
  });

  test('shared with me: newest first, owner, media', () {
    final items = sharedRecordsFrom({
      'items': [
        {'token': 'old-token-1', 'record_id': 1, 'title': 'Old', 'shared_at': '2026-11-01T09:00:00', 'owner': {'id': 2, 'name': 'Ali'}},
        {'token': 'new-token-2', 'record_id': 2, 'title': 'New', 'media': 'audio', 'quality': 'audio', 'duration_seconds': 61.5,
         'shared_at': '2026-11-08T09:00:00', 'mode': 'link', 'is_owner': false, 'owner': {'id': 3, 'name': 'Sara', 'username': 'sara'}},
        {'record_id': 3, 'title': 'no token'},
      ]
    });
    expect(items.map((r) => r.token), ['new-token-2', 'old-token-1']);
    final n = items.first;
    expect(n.audio, isTrue);
    expect(n.durationSeconds, 61.5);
    expect(n.mode, RecordShareMode.link);
    expect(n.ownerName, 'Sara');
    expect(n.ownerUsername, 'sara');
  });

  test('people search results', () {
    final p = sharePeopleFrom({
      'items': [
        {'id': 9, 'name': 'Hala', 'image_url': 'https://cdn.test/h.png', 'username': 'hala'},
        {'id': 'x'},
      ]
    });
    expect(p.map((x) => x.id), [9]);
    expect(p.single.imageUrl, 'https://cdn.test/h.png');
  });

  test('frames: ready with an absolute url, pending, unavailable', () {
    final r = RecordFrames.fromJson(
        {'status': 'ready', 'url': '/api/v1/me/records/stream/frames/tok', 'count': 24, 'tile_w': 160, 'tile_h': 90},
        base: 'https://nextbrain.site/api/');
    expect(r.ready, isTrue);
    expect(r.url, 'https://nextbrain.site/api/api/v1/me/records/stream/frames/tok');
    expect(r.count, 24);
    expect(RecordFrames.fromJson({'status': 'pending', 'count': 24}, base: '').pending, isTrue);
    expect(RecordFrames.fromJson({'status': 'ready', 'count': 0}, base: '').ready, isFalse);
    expect(RecordFrames.fromJson({'status': '???'}, base: '').status, 'unavailable');
  });

  test('the record link is by token: build, parse (also under /app/), refuse junk', () {
    const l = AppLink.record('abcDEF123_-xyz');
    expect(l.route, '/s/record/abcDEF123_-xyz');
    expect(l.url(), 'https://nextbrain.site/s/record/abcDEF123_-xyz');
    expect(AppLink.parse('https://nextbrain.site/s/record/abcDEF123_-xyz'), l);
    expect(AppLink.parse('/app/s/record/abcDEF123_-xyz')?.token, 'abcDEF123_-xyz');
    expect(AppLink.parse('/s/record/short'), isNull);
    expect(AppLink.parse('/s/record/has.dots.in.it'), isNull);
    expect(AppLink.parse('/s/meeting/12')?.id, 12);              // the id kinds are unchanged
  });
}
