// Records guests by e-mail and the Studio on session materials (D-315): parsing the server's answers, the e-mail list
// rules, the guest token, the publish words.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/features/shared/records/material_studio_api.dart';
import 'package:flutter_education_app/features/shared/records/records_api.dart';
import 'package:flutter_education_app/features/shared/records/records_guests_api.dart';
import 'package:flutter_education_app/features/shared/records/records_share_api.dart';
import 'package:flutter_education_app/features/shared/records/records_studio_parts.dart' show StudioTool;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('guests', () {
    test('the typed addresses: split, lower-cased, once each, the bad ones named', () {
      final p = parseGuestEmails('Mona@Example.com, omar@example.org;\nmona@example.com  nope ، sara@site.co');
      expect(p.valid, ['mona@example.com', 'omar@example.org', 'sara@site.co']);
      expect(p.invalid, ['nope']);
      expect(guestEmailsProblem('a@b.co nope'), 'Not an e-mail address: nope');
      expect(guestEmailsProblem('  '), 'Type at least one e-mail address');
      expect(guestEmailsProblem(List.generate(21, (i) => 'u$i@x.io').join(',')), 'Up to 20 addresses at a time');
      expect(guestEmailsProblem('a@b.co'), isNull);
    });

    test('a share with guests: rows, status lines, the summary counts them', () {
      final r = GuestInviteResult.fromJson({
        'record_id': 4,
        'mode': 'people',
        'token': 'shareToken123',
        'link': 'https://nextbrain.site/s/record/shareToken123',
        'people': [],
        'views': 5,
        'guests': [
          {'id': 1, 'email': 'a@example.com', 'token': 'g_abcdefghijklmnop', 'link': 'https://nextbrain.site/s/record/g_abcdefghijklmnop',
           'expires_at': '2026-11-15T09:00:00', 'expired': false, 'opened_at': '2026-11-08T10:00:00', 'views': 2, 'email_status': 'sent'},
          {'id': 2, 'email': 'b@example.com', 'token': 'g_qrstuvwxyz012345', 'expires_at': null, 'views': 0, 'email_status': 'unavailable'},
          {'id': 3, 'email': 'c@example.com', 'token': 'g_zzzzzzzzzzzzzzzz', 'expired': true, 'email_status': 'failed'},
          {'id': 0, 'email': 'broken'},
        ],
        'mail': {'status': 'unavailable', 'code': 'email_unavailable', 'sent': 0, 'failed': 0},
      }, recordId: 4);
      expect(r.guests.map((g) => g.id), [1, 2, 3]);
      expect(r.share.guests.length, 3);
      expect(r.share.summary(), 'With 3 people · 5 views');
      expect(r.guests[0].status(), 'Opened · 2 views');
      expect(r.guests[1].status(), 'Not opened yet · Copy the link and send it');
      expect(r.guests[2].status(), 'The link expired');
      expect(r.mail.unavailable, isTrue);
      expect(r.mail.notice(), contains("can't send e-mail"));
      expect(GuestMailResult.fromJson({'status': 'partial', 'sent': 2, 'failed': 1}).notice(), contains('Sent 2, 1 failed'));
      expect(GuestMailResult.fromJson({'status': 'sent', 'sent': 3}).notice(), '3 invitations sent');
    });

    test('a guest token opens the guest page; a share token does not', () {
      expect(isGuestRecordToken('g_abcdefghijklmnop'), isTrue);
      expect(isGuestRecordToken('abcDEF123_-xyz'), isFalse);
      expect(isGuestRecordToken('g_'), isFalse);
      final link = AppLink.parse('/s/record/g_abcdefghijklmnopqrstuvwxyz012345');
      expect(link?.kind, AppLinkKind.record);
      expect(isGuestRecordToken(link?.token), isTrue);
    });

    test('the guest card', () {
      final c = GuestRecordCard.fromJson({
        'title': 'Weekly sync',
        'owner': {'name': 'Ahmed', 'image_url': null},
        'duration_seconds': 125.5,
        'media': 'audio',
        'message': 'Watch this',
        'expires_at': '2026-12-01T00:00:00',
      });
      expect(c.title, 'Weekly sync');
      expect(c.ownerName, 'Ahmed');
      expect(c.audio, isTrue);
      expect(c.durationSeconds, 125.5);
      expect(c.expiresAt, isNotNull);
      expect(GuestRecordCard.fromJson(const {}).title, 'Recording');
    });

    test('expiry choices', () {
      expect(recordGuestExpiries, [7, 30, null]);
      expect(recordGuestExpiryLabel(null), 'Never');
      expect(recordGuestExpiryLabel(7), '7 days');
    });
  });

  group('material studio', () {
    test('open: the material as a source, merge candidates, drafts', () {
      final o = MaterialStudioOpen.fromJson({
        'source': {'id': 11, 'kind': 'material', 'title': 'Lecture 1', 'status': 'done', 'media': 'video', 'quality': '720p',
          'duration_seconds': 3600, 'size': 1000, 'can_edit': true, 'can_play': true, 'session_id': 3},
        'others': [
          {'id': 12, 'kind': 'material', 'title': 'Lecture 2', 'status': 'done', 'quality': '720p', 'duration_seconds': 600, 'can_edit': true},
        ],
        'drafts': [
          {'id': 5, 'kind': 'material_draft', 'title': 'Lecture 1 · Trimmed', 'status': 'assembling', 'stage': 'processing', 'progress': 40,
            'operation': 'trim', 'source_ids': [11], 'state': 'draft', 'session_id': 3, 'source_material_id': 11},
        ],
      })!;
      expect(o.source.id, 11);
      expect(o.source.durationSeconds, 3600);
      expect(o.source.canEdit, isTrue);
      expect(o.others.single.mergeable, isTrue);
      final d = o.drafts.single;
      expect(d.item.inProgress, isTrue);
      expect(d.item.operation, RecordOp.trim);
      expect(d.status(), contains('40%'));
      expect(MaterialStudioOpen.fromJson(const {}), isNull);
    });

    test('a draft through its publish life', () {
      MaterialDraft d(Map<String, dynamic> extra) => MaterialDraft.fromJson({
            'id': 7, 'kind': 'material_draft', 'title': 'T', 'status': 'done', 'session_id': 3, 'source_material_id': 11, ...extra})!;
      final ready = d({'state': 'draft', 'can_publish': true, 'can_play': true});
      expect(ready.isDraft && ready.canPublish && ready.item.canPlay, isTrue);
      expect(ready.status(), "Draft — students don't see it until you publish it");
      final rep = d({'state': 'published', 'publish_mode': 'replace', 'published_material_id': 11, 'can_restore': true});
      expect(rep.pendingReplace, isTrue);
      expect(rep.publishedMaterialId, 11);
      expect(rep.status(), contains('old file is kept'));
      final failed = d({'status': 'failed', 'error': 'boom', 'retry_mode': 'manual'});
      expect(failed.item.isFailed, isTrue);
      expect(failed.status(), 'boom');
      expect(MaterialPublishMode.fromWire('new'), MaterialPublishMode.asNew);
      expect(MaterialPublishMode.replace.hint, contains('progress'));
    });

    test('the material source: no Cover, drafts, its own event kinds', () {
      final s = MaterialStudioSource(sessionId: 3, materialId: 11);
      expect(s.tools.contains(StudioTool.cover), isFalse);
      expect(s.tools.first, StudioTool.trim);
      expect(s.drafts, isTrue);
      expect(s.jobEventKind, 'material_edit');
      expect(s.framesEventKind, 'material_frames');
    });

    test('a frames answer keeps its absolute url', () {
      final f = RecordFrames.fromJson({'status': 'ready', 'url': '/api/v1/studio/frames/tok', 'count': 24}, base: 'https://nextbrain.site/api');
      expect(f.url, 'https://nextbrain.site/api/api/v1/studio/frames/tok');
    });
  });
}
