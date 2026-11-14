// Live rooms — share links + admission lobby: every presentational widget of
// lib/features/live/live_lobby_sheets.dart (and the control bar's lobby button, the guest page's meeting
// card) at phone and web sizes, in Arabic and English, text scale 1.3 — no overflow, no layout exception.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_page.dart';
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _waiting = <LobbyRequest>[
  LobbyRequest(id: 'r1', name: 'Mohamed Abdelrahman Elsayed Ibrahim', requestedAt: DateTime.utc(2026, 10, 27, 10, 3)),
  const LobbyRequest(id: 'r2', name: 'زائر من رابط المشاركة الطويل جداً', isGuest: true, imageUrl: 'https://x/a.png'),
  const LobbyRequest(id: 'r3', name: '', isGuest: true),
];

Widget _lobby({bool loading = false, String? error, List<LobbyRequest> waiting = const [], Set<String> busy = const {}}) => LobbyBody(
      loading: loading,
      error: error,
      waiting: waiting,
      busyIds: busy,
      everyoneNeedsApproval: true,
      guestsJoinAutomatically: false,
      onAdmit: (_) {},
      onReject: (_) {},
      onAdmitAll: () {},
      onRefresh: () {},
      onEveryoneNeedsApproval: (_) {},
      onGuestsJoinAutomatically: (_) {},
    );

Widget _share({bool loading = false, String? error, LiveLink? link, bool editing = false, bool showQr = false, bool busy = false}) => ShareLinkBody(
      loading: loading,
      busy: busy,
      error: error,
      link: link,
      canPublish: true,
      maxGuestsController: TextEditingController(text: '25'),
      pinController: TextEditingController(),
      editing: editing,
      showQr: showQr,
      onRetry: () {},
      onCanPublishChanged: (_) {},
      onCreate: () {},
      onCopy: () {},
      onShare: () {},
      onToggleQr: () {},
      onToggleSettings: () {},
      onSaveSettings: () {},
      onRevoke: () {},
    );

const _link = LiveLink(
  url: 'https://nextbrain.site/live/4f3b1c9e8d7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c',
  token: '4f3b1c9e',
  canPublish: false,
  maxGuests: 10,
  hasPin: true,
);

void main() {
  group('LobbyBody', () {
    testWidgets('loading · empty · error · list (busy rows) never overflow', (tester) async {
      await expectNoLayoutErrors(tester, () => _lobby(loading: true));
      await expectNoLayoutErrors(tester, () => _lobby(), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.empty')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.admit_all')), findsNothing);
      });
      await expectNoLayoutErrors(tester, () => _lobby(error: 'Network is down for a long while, really long'));
      await expectNoLayoutErrors(tester, () => _lobby(waiting: _waiting, busy: const {'r2'}, error: 'stale'), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.admit_all')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.admit.r1')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.reject.r1')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.admit.r2')), findsNothing); // busy → spinner
        expect(find.byKey(const ValueKey('lobby.everyone_approval')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.guests_auto')), findsOneWidget);
      });
    });
  });

  group('QuickGuestLinkCard (lobby top card, spec §10)', () {
    Widget card({bool loading = false, String? error, LiveLink? link, bool showQr = false, bool busy = false}) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: QuickGuestLinkCard(
            loading: loading,
            busy: busy,
            error: error,
            link: link,
            showQr: showQr,
            onRetry: () {},
            onMakeDirect: () {},
            onDirectChanged: (_) {},
            onCopy: () {},
            onShare: () {},
            onToggleQr: () {},
          ),
        );
    const direct = LiveLink(url: 'https://nextbrain.site/live/4f3b1c9e8d7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c', token: '4f3b', canPublish: true, direct: true);

    testWidgets('loading · error · no link · not direct · direct with QR', (tester) async {
      await expectNoLayoutErrors(tester, () => card(loading: true));
      await expectNoLayoutErrors(tester, () => card(error: 'Only the room host can do this.'),
          act: (t) async => expect(find.byKey(const ValueKey('lobby.quick_link.error')), findsOneWidget));
      await expectNoLayoutErrors(tester, () => card(), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.quick_link.create')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.quick_link.copy')), findsNothing);
        expect(find.byKey(const ValueKey('lobby.quick_link.direct')), findsNothing);
      });
      await expectNoLayoutErrors(tester, () => card(link: _link, busy: true), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.quick_link.create')), findsOneWidget, reason: 'one tap turns it direct');
        expect(find.byKey(const ValueKey('lobby.quick_link.copy')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.quick_link.direct')), findsNothing);
      });
      await expectNoLayoutErrors(tester, () => card(link: direct, showQr: true), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.quick_link.create')), findsNothing);
        expect(find.byKey(const ValueKey('lobby.quick_link.url')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.quick_link.share')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.quick_link.qr_image')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.quick_link.direct')), findsOneWidget);
      });
    });

    testWidgets('the lobby shows the card on top', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => LobbyBody(
          loading: false,
          error: null,
          waiting: _waiting,
          everyoneNeedsApproval: false,
          guestsJoinAutomatically: false,
          onAdmit: (_) {},
          onReject: (_) {},
          onAdmitAll: () {},
          onRefresh: () {},
          onEveryoneNeedsApproval: (_) {},
          onGuestsJoinAutomatically: (_) {},
          quickLink: QuickGuestLinkCard(
            loading: false,
            busy: false,
            error: null,
            link: direct,
            onRetry: () {},
            onMakeDirect: () {},
            onDirectChanged: (_) {},
            onCopy: () {},
            onShare: () {},
            onToggleQr: () {},
          ),
        ),
        act: (t) async {
          expect(find.byKey(const ValueKey('lobby.quick_link')), findsOneWidget);
          expect(find.byKey(const ValueKey('lobby.everyone_approval')), findsOneWidget);
        },
      );
    });
  });

  group('ShareLinkBody', () {
    testWidgets('loading · error · create form · link with QR and settings', (tester) async {
      await expectNoLayoutErrors(tester, () => _share(loading: true));
      await expectNoLayoutErrors(tester, () => _share(error: 'Only the room host can do this.'));
      await expectNoLayoutErrors(tester, () => _share(), act: (t) async {
        expect(find.byKey(const ValueKey('share_link.create')), findsOneWidget);
      });
      await expectNoLayoutErrors(tester, () => _share(link: _link, showQr: true, editing: true, busy: true), act: (t) async {
        expect(find.byKey(const ValueKey('share_link.present')), findsOneWidget);
        expect(find.byKey(const ValueKey('share_link.qr_image')), findsOneWidget);
        expect(find.byKey(const ValueKey('share_link.settings_panel')), findsOneWidget);
        expect(find.byKey(const ValueKey('share_link.url')), findsOneWidget);
      });
    });
  });

  group('WaitingForHostScreen', () {
    testWidgets('waiting · rejected · expired', (tester) async {
      for (final s in WaitingState.values) {
        await expectNoLayoutErrors(
          tester,
          () => WaitingForHostScreen(
            state: s,
            title: 'Project check-in with the whole department and the dean',
            hostName: 'Dr. Mona Abdelaziz',
            onCancel: () {},
          ),
          act: (t) async {
            expect(find.byKey(ValueKey('waiting_host.${s.name}')), findsOneWidget);
            expect(find.byKey(const ValueKey('waiting_host.leave')), findsOneWidget);
          },
        );
      }
      await expectNoLayoutErrors(tester, () => WaitingForHostScreen(state: WaitingState.waiting, onCancel: () {}));
    });
  });

  group('LobbyBanner', () {
    testWidgets('member · guest with others waiting · busy · no dismiss', (tester) async {
      Widget host(Widget b) => Container(
            color: const Color(0xFF0B1020),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.all(12),
            child: b,
          );
      await expectNoLayoutErrors(tester, () => host(LobbyBanner(request: _waiting[0], onAdmit: () {}, onReject: () {}, onOpen: () {}, onDismiss: () {})), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.banner.admit')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.banner.reject')), findsOneWidget);
        expect(find.byKey(const ValueKey('lobby.banner.dismiss')), findsOneWidget);
      });
      await expectNoLayoutErrors(tester, () => host(LobbyBanner(request: _waiting[1], othersWaiting: 12, onAdmit: () {}, onReject: () {})));
      await expectNoLayoutErrors(tester, () => host(LobbyBanner(request: _waiting[2], busy: true, onAdmit: () {}, onReject: () {}, onDismiss: () {})), act: (t) async {
        expect(find.byKey(const ValueKey('lobby.banner.admit')), findsNothing);
      });
    });
  });

  group('control bar lobby button', () {
    testWidgets('shows with the waiting count, in the pill and on the wide bar', (tester) async {
      List<LiveControlAction> actions() => [
            LiveControlAction(key: const ValueKey('live_room.mic'), icon: Icons.mic_rounded, label: 'Mute', active: true, onTap: () {}),
            LiveControlAction(key: const ValueKey('live_room.camera'), icon: Icons.videocam_rounded, label: 'Camera', active: true, onTap: () {}),
            LiveControlAction(key: const ValueKey('live_room.share'), icon: Icons.screen_share_rounded, label: 'Share', onTap: () {}),
            LiveControlAction(key: const ValueKey('live_room.reactions'), icon: Icons.add_reaction_outlined, label: 'React', onTap: () {}),
            LiveControlAction(key: const ValueKey('live_room.chat'), icon: Icons.chat_bubble_outline_rounded, label: 'Chat', badge: 3, onTap: () {}),
          ];
      Widget bar(int waiting) => Align(
            alignment: Alignment.bottomCenter,
            child: LiveControlBar(
              primary: actions(),
              secondary: [LiveControlAction(key: const ValueKey('live_room.speaker'), icon: Icons.speaker_phone_rounded, label: 'Speaker', onTap: () {})],
              groups: [actions().take(2).toList(), [actions()[2]], actions().skip(3).toList()],
              end: LiveControlAction(key: const ValueKey('live_room.end'), icon: Icons.call_end_rounded, label: 'End', onTap: () {}),
              waitingCount: waiting,
              onLobby: () {},
            ),
          );
      await expectNoLayoutErrors(tester, () => bar(0), act: (t) async {
        expect(find.byKey(const ValueKey('live_room.lobby')), findsOneWidget);
      });
      await expectNoLayoutErrors(tester, () => bar(120), act: (t) async {
        expect(find.byKey(const ValueKey('live_room.lobby')), findsOneWidget);
        final endX = t.getCenter(find.byKey(const ValueKey('live_room.end'))).dx;
        final lobbyX = t.getCenter(find.byKey(const ValueKey('live_room.lobby'))).dx;
        expect(endX, greaterThan(lobbyX));
      });
      // Without onLobby nothing changes.
      await expectNoLayoutErrors(
        tester,
        () => Align(alignment: Alignment.bottomCenter, child: LiveControlBar(primary: actions(), end: LiveControlAction(icon: Icons.call_end_rounded, label: 'End', onTap: () {}))),
        act: (t) async => expect(find.byKey(const ValueKey('live_room.lobby')), findsNothing),
      );
    });
  });

  group('guest page: meeting link', () {
    testWidgets('meeting card with host, time, admission note and "Join with my account"', (tester) async {
      final info = GuestLiveInfo.fromJson({
        'kind': 'meeting',
        'id': 44,
        'title': 'Project check-in with the whole department',
        'host_name': 'Dr. Mona Abdelaziz Mahmoud',
        'starts_at': '2026-10-27T10:00:00Z',
        'is_live': true,
        'can_publish': true,
        'recording_enabled': true,
        'guest_admission': 'approve',
        'signed_in_join': true,
      });
      await expectNoLayoutErrors(
        tester,
        () => GuestLiveContent(
          loading: false,
          info: info,
          error: null,
          joining: false,
          nameController: TextEditingController(text: 'Visitor'),
          consent: true,
          signedIn: true,
          accountName: 'Ahmed Hamdy',
          onJoinWithAccount: () {},
          onJoin: () {},
          onRetry: () {},
        ),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.meeting')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.join_account')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.join')), findsOneWidget);
        },
      );
      // A direct link (auto_join): the short card — host, "straight in", the name field, Join.
      final quick = GuestLiveInfo.fromJson({
        'kind': 'meeting',
        'id': 45,
        'title': 'Quick meeting · Ahmed Hamdy Madkour and the study group of section B',
        'host_name': 'Ahmed Hamdy',
        'is_live': true,
        'can_publish': true,
        'auto_join': true,
        'course_name': 'Physics',
        'max_guests': 20,
      });
      await expectNoLayoutErrors(
        tester,
        () => GuestLiveContent(loading: false, info: quick, error: null, joining: false, nameController: TextEditingController(), onJoin: () {}, onRetry: () {}),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.name')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.join')), findsOneWidget);
          expect(find.text('Physics'), findsNothing);
        },
      );
      // Not signed in → no account button.
      await expectNoLayoutErrors(
        tester,
        () => GuestLiveContent(loading: false, info: info, error: null, joining: false, nameController: TextEditingController(), onJoin: () {}, onRetry: () {}),
        act: (t) async => expect(find.byKey(const ValueKey('guest_live.join_account')), findsNothing),
      );
    });
  });
}
