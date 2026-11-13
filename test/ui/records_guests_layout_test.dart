// Guests by e-mail and the Studio on session materials (D-315): the plain-values widgets on every screen size and
// language (320×640 and 1400×900, ar / en, text scale 1.3) — the guest rows in the share sheet, the invite form,
// the guest's page in each state, the drafts strip, the publish choice, the Studio in material mode (no Cover,
// Save as draft, the job card's Publish) — plus what they say and do.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/records/material_studio_api.dart';
import 'package:flutter_education_app/features/shared/records/material_studio_parts.dart';
import 'package:flutter_education_app/features/shared/records/records_api.dart';
import 'package:flutter_education_app/features/shared/records/records_guests_api.dart';
import 'package:flutter_education_app/features/shared/records/records_guests_parts.dart';
import 'package:flutter_education_app/features/shared/records/records_share_api.dart';
import 'package:flutter_education_app/features/shared/records/records_share_parts.dart';
import 'package:flutter_education_app/features/shared/records/records_studio_parts.dart';
import 'package:flutter_education_app/features/shared/records/studio_export.dart';
import 'package:flutter_education_app/features/shared/records/studio_project.dart';
import 'package:flutter_education_app/features/shared/records/studio_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

RecordGuest _g(int id, {bool expired = false, String? status = 'sent', bool opened = false}) => RecordGuest.fromJson({
      'id': id,
      'email': 'a.guest.with.a.very.long.address.number.$id@some-university.example.edu',
      'token': 'g_abcdefghijklmnop$id',
      'link': 'https://nextbrain.site/s/record/g_abcdefghijklmnop$id',
      'expires_at': expired ? '2026-11-01T00:00:00' : '2026-12-08T00:00:00',
      'expired': expired,
      'opened_at': opened ? '2026-11-08T10:00:00' : null,
      'views': opened ? 4 : 0,
      'email_status': status,
    })!;

MaterialDraft _d(int id, Map<String, dynamic> extra) => MaterialDraft.fromJson({
      'id': id,
      'kind': 'material_draft',
      'title': 'Lecture 3 — the long title of a trimmed lecture video for the second term $id',
      'status': 'done',
      'operation': 'trim',
      'duration_seconds': 2400.0,
      'session_id': 3,
      'source_material_id': 11,
      'state': 'draft',
      'can_play': true,
      'can_publish': true,
      ...extra,
    })!;

RecordItem _material() => RecordItem.fromJson({
      'id': 11,
      'kind': 'material',
      'title': 'Lecture 3 — introduction to the second unit',
      'status': 'done',
      'quality': '720p',
      'duration_seconds': 3600.0,
      'can_edit': true,
      'can_play': true,
    })!;

Widget _studio(StudioTool tool, {bool job = false}) {
  const tools = [StudioTool.edit, StudioTool.text, StudioTool.image, StudioTool.history, StudioTool.quality, StudioTool.split, StudioTool.merge];
  final item = _material();
  final ready = _d(21, const {});
  if (job) {
    return SingleChildScrollView(
      child: StudioExportJob(
        card: StudioJobCard(
          items: [ready.item, _d(22, {'status': 'assembling', 'progress': 30, 'can_publish': false}).item],
          drafts: true,
          libraryLabel: 'To the session',
          onPlay: (_) {},
          onAgain: () {},
          onLibrary: () {},
          actionsFor: (r) => r.id == 21 ? AppPillLike(onTap: () {}) : null,
        ),
        running: true,
        onKeepEditing: () {},
      ),
    );
  }
  if (tool == StudioTool.quality || tool == StudioTool.split) {
    // a material's Quality and Two files are choices of the Export panel (D-827), where the draft note replaces Keep / Replace
    return SingleChildScrollView(
      child: StudioExportSettings(
        item: item,
        duration: 3590,
        draft: true,
        form: StudioSaveArea(title: const TextField(decoration: InputDecoration(labelText: 'Name of the new video')), draft: true).form,
        onQuality: (_, _) {},
        twoFiles: tool == StudioTool.split,
        halves: (60, 3530),
        onTwoFiles: (_) {},
        result: const [1190],
        onExport: () {},
      ),
    );
  }
  return RecordStudioLayout(
    tools: [for (final x in tools) if (x.inRail) x],
    tool: tool,
    onTool: (_) {},
    preview: const SizedBox.expand(),
    transport: StudioTransport(position: 60, duration: 3600, onPlayPause: () {}, onSkip: (_) {}, onPreviewSpeed: () {}),
    timeline: StudioTimelineView(edit: StudioEdit.original(3600).split(1200), position: 60, sourceDuration: 3600, onScrub: (_) {}),
    panel: StudioToolPanel(tool: tool, item: item, duration: 3600, showImages: false),
  );
}

/// A stand-in for the page's Publish pill (the real one is an AppPill).
class AppPillLike extends StatelessWidget {
  const AppPillLike({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(key: const ValueKey('test.publish'), onPressed: onTap, child: const Text('Publish'));
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('guests layout', () {
    testWidgets('guest rows in the share sheet, each state', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: RecordShareLayout(
                  mode: RecordShareMode.people,
                  people: const [],
                  link: 'https://nextbrain.site/s/record/abcdefghijklmnop',
                  active: true,
                  showImages: false,
                  guestRows: [
                    RecordGuestRow(guest: _g(1, opened: true), onCopy: () {}, onResend: () {}, onRevoke: () {}),
                    RecordGuestRow(guest: _g(2, status: 'unavailable')),
                    RecordGuestRow(guest: _g(3, expired: true, status: 'failed')),
                  ],
                ),
              ));
    });

    testWidgets('the invite form: empty, a problem, busy, the server cannot send e-mail', (t) async {
      for (final w in [
        RecordGuestsInvite(emails: const TextField(), message: const TextField(), onExpiry: (_) {}, onInvite: () {}),
        const RecordGuestsInvite(emails: TextField(), message: TextField(), problem: 'Not an e-mail address: nope', expiresDays: null),
        const RecordGuestsInvite(emails: TextField(), message: TextField(), busy: true, mailUnavailable: true, expiresDays: 7),
      ]) {
        await expectNoLayoutErrors(t, () => SingleChildScrollView(child: w));
      }
    });

    testWidgets("the guest's page: loading, not available, the card, a long message", (t) async {
      final card = GuestRecordCard.fromJson({
        'title': 'Weekly planning sync with the whole department and every guest of the term',
        'owner': {'name': 'Dr. Ahmed Hamdy Madkour'},
        'duration_seconds': 5400.0,
        'message': 'Please watch the part about the exams before Sunday — ' * 6,
        'expires_at': '2026-12-01T00:00:00',
      });
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: GuestRecordView()));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GuestRecordView(error: 'This link is not available', onRetry: () {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GuestRecordView(card: card, onPlay: () {}, showImage: false)));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GuestRecordView(card: card, starting: true, showImage: false)));
    });

    testWidgets('Invite is off while the addresses are wrong; the row copies', (t) async {
      var invites = 0, copies = 0;
      await t.pumpWidget(layoutHost(
          SingleChildScrollView(
            child: RecordGuestsInvite(emails: const TextField(), message: const TextField(), problem: 'bad', onInvite: () => invites++),
          ),
          scale: 1));
      await t.tap(find.byKey(const ValueKey('records.share.guests.invite')), warnIfMissed: false);
      expect(invites, 0);
      await t.pumpWidget(layoutHost(RecordGuestRow(guest: _g(5), onCopy: () => copies++), scale: 1));
      expect(find.text('Guest'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('records.share.guest.copy.5')));
      expect(copies, 1);
    });
  });

  group('material studio layout', () {
    testWidgets('the drafts strip: ready, saving, failed, a replace to confirm', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: MaterialDraftsStrip(drafts: [
                  _d(1, const {}),
                  _d(2, {'status': 'uploading', 'stage': 'uploading', 'progress': 85, 'can_publish': false, 'can_play': false}),
                  _d(3, {'status': 'failed', 'error': 'The edit could not finish', 'can_publish': false, 'can_play': false, 'retry_mode': 'manual'}),
                  _d(4, {'state': 'published', 'publish_mode': 'replace', 'can_restore': true, 'can_publish': false}),
                ], onAction: (_, _) {}),
              ));
      await expectNoLayoutErrors(t, () => const MaterialDraftsStrip(drafts: []));
    });

    testWidgets('the publish choice, with and without the original', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: MaterialPublishChoice(mode: MaterialPublishMode.replace, onMode: (_) {}, onPublish: () {})));
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: MaterialPublishChoice(mode: MaterialPublishMode.asNew, canReplace: false, busy: true)));
    });

    for (final tool in [StudioTool.edit, StudioTool.split, StudioTool.merge]) {
      testWidgets('the Studio on a material: ${tool.name}', (t) async {
        await expectNoLayoutErrors(t, () => _studio(tool));
      });
    }

    testWidgets('the Studio on a material: the job card with Publish', (t) async {
      await expectNoLayoutErrors(t, () => _studio(StudioTool.edit, job: true));
    });

    testWidgets('material mode: no Cover tool, Export as a draft, the draft note, Publish on a ready draft', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(layoutHost(_studio(StudioTool.edit), scale: 1));
      expect(find.byKey(const ValueKey('studio.tool.cover')), findsNothing);
      expect(find.byKey(const ValueKey('studio.tool.merge')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio.tool.quality')), findsNothing, reason: 'Quality is in the Export panel (D-827)');
      await t.pumpWidget(layoutHost(_studio(StudioTool.edit, job: true), scale: 1));
      expect(find.text('The draft is ready — play it, then publish it'), findsNothing); // one item still saving
      expect(find.byKey(const ValueKey('test.publish')), findsOneWidget);
      expect(find.text('To the session'), findsOneWidget);
      await t.pumpWidget(layoutHost(_studio(StudioTool.quality), scale: 1));
      expect(find.text('Export as a draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('studio.draft.note')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio.replace')), findsNothing);
    });

    testWidgets('a draft tile offers what its state allows', (t) async {
      final got = <MaterialDraftAction>[];
      await t.pumpWidget(layoutHost(MaterialDraftTile(draft: _d(9, const {}), onAction: got.add), scale: 1));
      expect(find.byKey(const ValueKey('material.draft.publish.9')), findsOneWidget);
      expect(find.byKey(const ValueKey('material.draft.restore.9')), findsNothing);
      await t.tap(find.byKey(const ValueKey('material.draft.publish.9')));
      expect(got, [MaterialDraftAction.publish]);
      await t.pumpWidget(layoutHost(
          MaterialDraftTile(draft: _d(9, {'state': 'published', 'publish_mode': 'replace', 'can_restore': true, 'can_publish': false})),
          scale: 1));
      expect(find.byKey(const ValueKey('material.draft.publish.9')), findsNothing);
      expect(find.byKey(const ValueKey('material.draft.confirm.9')), findsOneWidget);
      expect(find.byKey(const ValueKey('material.draft.discard.9')), findsNothing);
    });
  });
}
