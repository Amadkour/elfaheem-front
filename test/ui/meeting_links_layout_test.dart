// D-307: the meeting links page parts, the share sheet body and the share-link preview at 320 / 1400 px, ar / en,
// text × 1.3 (test/ui/layout_harness.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart';
import 'package:flutter_education_app/features/shared/live/meeting_links.dart';
import 'package:flutter_education_app/features/shared/live/meeting_links_parts.dart';
import 'package:flutter_education_app/features/shared/share/share_link_page.dart' show ShareLinkPreviewView;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _now = DateTime.utc(2026, 11, 8, 9, 30);

MeetingLinkItem _item(MeetingLinkStatus status, {bool host = true, bool guest = true, bool expired = false}) => MeetingLinkItem(
      kind: host ? 'meeting' : 'session',
      refId: 7,
      title: 'Weekly planning meeting of the mathematics department with a very long title that wraps',
      subtitle: 'Advanced algebra and number theory for the second year',
      orgName: 'Cairo University · Faculty of Engineering',
      status: status,
      appLink: 'https://nextbrain.site/s/meeting/7',
      startsAt: _now.add(const Duration(minutes: 40)),
      endsAt: _now.add(const Duration(minutes: 100)),
      isHost: host,
      recurring: !host,
      myStatus: host ? 'owner' : 'pending',
      guest: guest
          ? MeetingGuestLink(url: 'https://nextbrain.site/live/abcdefghijklmnopqrstuvwxyz012345', hasPin: true, direct: true, guestsJoined: 12, active: !expired)
          : null,
    );

void main() {
  testWidgets('meeting link cards, summary and filters lay out everywhere', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            MeetingLinksSummary(live: 3, upcoming: 128, guestLinks: 12, onFilter: (_) {}),
            const SizedBox(height: 12),
            MeetingLinksFilterBar(value: MeetingLinksFilter.live, counts: const {MeetingLinksFilter.live: 3, MeetingLinksFilter.past: 40}, onChanged: (_) {}),
            for (final it in [
              _item(MeetingLinkStatus.live),
              _item(MeetingLinkStatus.scheduled, host: false, guest: false),
              _item(MeetingLinkStatus.ended, expired: true),
            ])
              MeetingLinkCard(item: it, now: _now, showDay: true, onOpen: () {}, onCopy: () {}, onShare: () {}, onJoin: () {},
                  onCopyGuest: () {}, onShareGuest: () {}),
          ]),
        ));
  });

  testWidgets('the share sheet body (with the QR code) lays out everywhere', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AppShareSheetBody(
            url: 'https://nextbrain.site/s/meeting/123456?some=very-long-parameter-value',
            title: 'Weekly planning meeting of the mathematics department with a very long title',
            subtitle: 'Tomorrow · 10:00 – 11:00',
            kind: 'Meeting',
            icon: Icons.groups_rounded,
            hint: 'Invitees open it after signing in.',
            showQr: true,
            copied: true,
            onCopy: () {},
            onShare: () {},
            onToggleQr: () {},
          ),
        ));
  });

  testWidgets('the share-link preview lays out (public, private, error, loading)', (tester) async {
    for (final v in [
      const ShareLinkPreviewView(kind: 'Course', icon: Icons.school_rounded, isPublic: true, title: 'Advanced algebra and number theory',
          subtitle: 'Ahmed Teacher', description: 'A long description of the course that goes on for a few lines to check wrapping.'),
      const ShareLinkPreviewView(kind: 'Meeting', icon: Icons.groups_rounded, note: 'Have a guest link? Open it to join without an account.'),
      const ShareLinkPreviewView(kind: 'Lesson', icon: Icons.play_lesson_rounded, error: 'This link is not available'),
      const ShareLinkPreviewView(kind: 'Lesson', icon: Icons.play_lesson_rounded, loading: true),
    ]) {
      await expectNoLayoutErrors(tester, () => ShareLinkPreviewView(
            kind: v.kind,
            icon: v.icon,
            isPublic: v.isPublic,
            title: v.title,
            subtitle: v.subtitle,
            description: v.description,
            note: v.note,
            error: v.error,
            loading: v.loading,
            onSignIn: () {},
            onRegister: () {},
            onRetry: () {},
          ));
    }
  });
}
