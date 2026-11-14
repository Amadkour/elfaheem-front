// Guest share links (D-840 – D-844): the plain-values widgets on every screen size and language (320×640 and
// 1400×900, ar / en, text scale 1.3) — the soft sign-up card, a course video's guest page with it, the staff's
// "Share with guests" sheet body, a record's open guest link in the share sheet — plus what they do.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/guest/guest_link_cta.dart';
import 'package:flutter_education_app/features/records/records_guests_api.dart';
import 'package:flutter_education_app/features/records/records_guests_parts.dart';
import 'package:flutter_education_app/features/sessions/material/material_guest_links_api.dart';
import 'package:flutter_education_app/features/sessions/material/material_guest_links_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

MaterialGuestLink _link(int id, {String? expires = '2026-12-01T00:00:00', bool opened = false}) => MaterialGuestLink.fromJson({
      'id': id,
      'token': 'v_abcdefghijklmnopqrstuvwxyz012345$id',
      'link': 'https://nextbrain.site/s/video/v_abcdefghijklmnopqrstuvwxyz012345$id',
      'expires_at': expires,
      'views': opened ? 12 : 0,
      'opened_at': opened ? '2026-11-10T10:00:00' : null,
    })!;

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('the soft sign-up card, after a video and after a meeting', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GuestLinkCta(onRegister: () {}, onSignIn: () {})));
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GuestLinkCta(afterMeeting: true, onRegister: () {}, onSignIn: () {})));
  });

  testWidgets("a course video's guest page: the lesson, its course, the teacher, view only, the card under it", (t) async {
    final card = GuestRecordCard.fromJson({
      'title': 'Lecture 7 — Newton’s laws of motion and the long worked examples of the second unit',
      'subtitle': 'Physics for the third secondary year — the complete course with every revision session',
      'owner': {'name': 'Dr. Ahmed Hamdy Madkour'},
      'duration_seconds': 3600,
      'expires_at': '2026-12-01T00:00:00',
      'personal': false,
      'kind': 'video',
    });
    expect(card.video, isTrue);
    expect(card.personal, isFalse);
    await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: GuestRecordView(card: card, onPlay: () {}, showImage: false, footer: GuestLinkCta(onRegister: () {}, onSignIn: () {})),
            ));
    await t.pumpWidget(layoutHost(SingleChildScrollView(child: GuestRecordView(card: card, showImage: false)), scale: 1));
    expect(find.textContaining('View only'), findsOneWidget);
    expect(find.textContaining('personal'), findsNothing);
    expect(find.textContaining('Teacher: Dr. Ahmed'), findsOneWidget);
  });

  testWidgets("the staff's Share with guests body: empty, links, busy, an error", (t) async {
    for (final w in [
      MaterialGuestLinksBody(onExpiry: (_) {}, onCreate: () {}),
      MaterialGuestLinksBody(
        links: [_link(1, opened: true), _link(2, expires: null), _link(3)],
        onCreate: () {},
        onCopy: (_) {},
        onShare: (_) {},
        onRevoke: (_) {},
      ),
      MaterialGuestLinksBody(links: [_link(4)], busy: true, expiresDays: null),
      const MaterialGuestLinksBody(error: 'Sharing videos with guests is switched off right now'),
    ]) {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: w));
    }
  });

  testWidgets('Create link and each row action call back with that link; an expired link is not listed', (t) async {
    var created = 0;
    MaterialGuestLink? copied, revoked;
    final expired = MaterialGuestLink.fromJson({'id': 9, 'token': 'v_expiredexpired', 'link': 'https://x/s/video/v_expiredexpired', 'expired': true})!;
    await t.pumpWidget(layoutHost(
        SingleChildScrollView(
          child: MaterialGuestLinksBody(
            links: [_link(1), expired],
            onCreate: () => created++,
            onCopy: (l) => copied = l,
            onRevoke: (l) => revoked = l,
          ),
        ),
        scale: 1));
    await t.tap(find.byKey(const ValueKey('material_guest.create')));
    await t.tap(find.byKey(const ValueKey('material_guest.copy.1')));
    await t.tap(find.byKey(const ValueKey('material_guest.revoke.1')));
    expect((created, copied?.id, revoked?.id), (1, 1, 1));
    expect(find.byKey(const ValueKey('material_guest.link.9')), findsNothing);
  });

  testWidgets("a record's open guest link: its row and the button in the invite form", (t) async {
    final open = RecordGuest.fromJson({
      'id': 7,
      'kind': 'link',
      'email': null,
      'token': 'g_openlinkopenlink',
      'link': 'https://nextbrain.site/s/record/g_openlinkopenlink',
      'email_status': 'link',
      'expires_at': null,
    })!;
    expect(open.openLink, isTrue);
    await expectNoLayoutErrors(t, () => RecordGuestRow(guest: open, onCopy: () {}, onRevoke: () {}));
    var made = 0;
    await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: RecordGuestsInvite(emails: const TextField(), message: const TextField(), hasOpenLink: true, onOpenLink: () => made++),
            ));
    await t.pumpWidget(layoutHost(RecordGuestRow(guest: open, onCopy: () {}, onRevoke: () {}), scale: 1));
    expect(find.text('Anyone with this link'), findsOneWidget);
    await t.pumpWidget(layoutHost(
        SingleChildScrollView(child: RecordGuestsInvite(emails: const TextField(), message: const TextField(), onOpenLink: () => made++)),
        scale: 1));
    await t.ensureVisible(find.byKey(const ValueKey('records.share.guests.open_link')));
    await t.tap(find.byKey(const ValueKey('records.share.guests.open_link')));
    expect(made, 1);
  });
}
