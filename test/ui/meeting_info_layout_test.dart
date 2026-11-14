// The room's (i) sheet (lib/features/live/meeting_info_sheet.dart, live-rooms-spec §11) at phone and web
// sizes, Arabic and English, text scale 1.3: a guest, a member and the host with the link and the rules.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/meeting_info_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('guest / member: no host section; free time and recording shown', (tester) async {
    for (final role in [LiveRoomRole.guest, LiveRoomRole.member]) {
      await expectNoLayoutErrors(
        tester,
        () => MeetingInfoSheet(
          info: MeetingInfo(
            title: 'Study group — chapter 4 review with everyone from section B before the midterm',
            isMeeting: true,
            role: role,
            hostName: 'Mohamed Abdelrahman Elsayed Ibrahim',
            startsAt: DateTime.utc(2026, 10, 28, 10),
            elapsed: const Duration(minutes: 7, seconds: 31),
            participants: 12,
            recording: LiveInfoRecording.recording,
            freeLeft: const Duration(minutes: 2, seconds: 10),
          ),
        ),
        act: (t) async {
          expect(find.byKey(const ValueKey('meeting_info')), findsOneWidget);
          expect(find.byKey(const ValueKey('meeting_info.free_left')), findsOneWidget);
          expect(find.byKey(const ValueKey('meeting_info.copy_link')), findsNothing);
          expect(find.byKey(const ValueKey('meeting_info.admission')), findsNothing);
        },
      );
    }
  });

  testWidgets('Part 3 §16: "Live for" from the room start, your own time beside it; fallback without it', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const MeetingInfoSheet(
        info: MeetingInfo(
          title: 'Weekly sync',
          isMeeting: true,
          role: LiveRoomRole.member,
          elapsed: Duration(minutes: 4, seconds: 2),
          liveFor: Duration(hours: 12, minutes: 34, seconds: 56),
          participants: 2,
        ),
      ),
      act: (t) async {
        expect(find.byKey(const ValueKey('meeting_info.live_for')), findsOneWidget);
        expect(find.byKey(const ValueKey('meeting_info.elapsed')), findsOneWidget);
        expect(find.text('12:34:56'), findsOneWidget);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => const MeetingInfoSheet(
        info: MeetingInfo(title: 'Weekly sync', isMeeting: true, role: LiveRoomRole.guest, elapsed: Duration(minutes: 4, seconds: 2)),
      ),
      act: (t) async {
        expect(find.byKey(const ValueKey('meeting_info.live_for')), findsOneWidget);
        expect(find.byKey(const ValueKey('meeting_info.elapsed')), findsNothing);
        expect(find.text('04:02'), findsOneWidget);
      },
    );
  });

  testWidgets('host: share link with Copy and the admission rules; loading; no link', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => MeetingInfoSheet(
        info: const MeetingInfo(
          title: 'Quick meeting · Ahmed',
          isMeeting: true,
          role: LiveRoomRole.host,
          elapsed: Duration(hours: 1, minutes: 2, seconds: 3),
          participants: 3,
          linkUrl: 'https://alfheemacademy.com/live/4f3b1c9e8d7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c',
          linkDirect: true,
          admission: LiveAdmission.approve,
          guestAdmission: LiveGuestAdmission.approve,
          freeLeft: Duration.zero,
        ),
        onCopyLink: () {},
      ),
      act: (t) async {
        expect(find.byKey(const ValueKey('meeting_info.link')), findsOneWidget);
        expect(find.byKey(const ValueKey('meeting_info.copy_link')), findsOneWidget);
        expect(find.byKey(const ValueKey('meeting_info.admission')), findsOneWidget);
        expect(find.byKey(const ValueKey('meeting_info.guest_admission')), findsOneWidget);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => const MeetingInfoSheet(
        info: MeetingInfo(title: '', isMeeting: false, role: LiveRoomRole.host, linkLoading: true, recording: LiveInfoRecording.server),
      ),
    );
    await expectNoLayoutErrors(
      tester,
      () => const MeetingInfoSheet(info: MeetingInfo(title: 'Lecture 3', isMeeting: false, role: LiveRoomRole.host)),
      act: (t) async => expect(find.byKey(const ValueKey('meeting_info.copy_link')), findsNothing),
    );
  });
}
