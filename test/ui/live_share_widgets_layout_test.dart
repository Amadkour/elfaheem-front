// One share at a time + the room's attention cues (lib/features/shared/live/live_share_widgets.dart, the Share
// button modes of controls.dart, the "More" badge of live_control_bar.dart, the minimized box's badge): no overflow
// at 320×640 and 1400×900, ar / en, text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/live_mini_box.dart';
import 'package:flutter_education_app/features/shared/live/live_share_arbiter.dart';
import 'package:flutter_education_app/features/shared/live/live_share_widgets.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/controls.dart' show ControlsWidgetState;
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _dark(Widget child) => ColoredBox(color: LivePalette.bg, child: Center(child: child));

const _long = 'Abdulrahman Mohammed Al-Qahtani the Third';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('request card', () {
    testWidgets('every note, busy, others waiting, a long name', (tester) async {
      for (final note in LiveShareAcceptNote.values) {
        await expectNoLayoutErrors(
            tester,
            () => _dark(Padding(
                  padding: const EdgeInsets.all(16),
                  child: LiveShareRequestCard(
                    name: _long,
                    note: note,
                    presenterName: 'Omar Khaled Abdelrahman',
                    othersWaiting: 2,
                    remaining: const Duration(seconds: 4),
                    onAccept: () {},
                    onReject: () {},
                  ),
                )));
      }
      await expectNoLayoutErrors(
          tester,
          () => _dark(LiveShareRequestCard(name: 'Sara', busy: true, onAccept: () {}, onReject: () {})));
    });

    testWidgets('accept / decline call back; busy disables them', (tester) async {
      var accepted = 0, rejected = 0;
      await tester.pumpWidget(layoutHost(_dark(LiveShareRequestCard(name: 'Sara', onAccept: () => accepted++, onReject: () => rejected++))));
      await tester.tap(find.byKey(const ValueKey('live_share.accept')));
      await tester.tap(find.byKey(const ValueKey('live_share.reject')));
      expect((accepted, rejected), (1, 1));
      await tester.pumpWidget(layoutHost(_dark(LiveShareRequestCard(name: 'Sara', busy: true, onAccept: () => accepted++, onReject: () => rejected++))));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('live_share.accept')), warnIfMissed: false);
      expect(accepted, 1);
    });

    testWidgets('the dialog follows the arbiter and closes itself when the request is gone', (tester) async {
      final a = LiveShareArbiter(localIdentity: () => 'teacher_1', isHost: () => true, send: (_) async {}, autoTick: false);
      addTearDown(a.dispose);
      a.receive(const LiveSharePacket(signal: LiveShareSignal.request, id: 'r1').encode(),
          sender: 'student_7', senderIsHost: false, senderName: 'Sara');
      await tester.pumpWidget(layoutHost(Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showLiveShareRequestDialog(context,
                arbiter: a, onAnswer: (_, _) {}, note: () => (LiveShareAcceptNote.yours, '')),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('live_share.request_card')), findsOneWidget);
      // another host answered: the request goes, the dialog closes
      a.receive(const LiveSharePacket(signal: LiveShareSignal.accept, id: 'r1', to: 'student_7', name: 'Co').encode(),
          sender: 'meet_2', senderIsHost: true);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('live_share.request_card')), findsNothing);
    });
  });

  testWidgets('stop chip and attention badge', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _dark(Wrap(spacing: 8, children: [
              LiveStopShareChip(onTap: () {}),
              LiveStopShareChip(onTap: () {}, busy: true),
              const LiveAttentionBadge(count: 3),
              const LiveAttentionBadge(count: 120),
              const LiveAttentionBadge(count: 0),
            ])));
  });

  testWidgets('chat toast: long message, more unread, slot in and out', (tester) async {
    const data = LiveChatToastData(
      id: 'm1',
      name: _long,
      text: 'Could you please go back to the previous slide? I missed the formula for the second derivative and the example.',
      more: 4,
    );
    await expectNoLayoutErrors(
        tester,
        () => _dark(Padding(
              padding: const EdgeInsets.all(12),
              child: LiveChatToast(data: data, onOpen: () {}, onDismiss: () {}),
            )));
    await expectNoLayoutErrors(tester, () => _dark(LiveChatToastSlot(data: data, onOpen: () {}, onDismiss: () {})));
    await expectNoLayoutErrors(tester, () => _dark(LiveChatToastSlot(data: null, onOpen: () {}, onDismiss: () {})));
  });

  group('the Share button modes', () {
    test('hidden → null; the others carry their keys', () {
      expect(ControlsWidgetState.shareAction(LiveShareButton.hidden), isNull);
      expect(ControlsWidgetState.shareAction(LiveShareButton.request, onTap: () {})!.key, const ValueKey('live_room.share_request'));
      expect(ControlsWidgetState.shareAction(LiveShareButton.requested, onTap: () {})!.active, isTrue);
      expect(ControlsWidgetState.shareAction(LiveShareButton.stop, onTap: () {})!.active, isTrue);
    });

    testWidgets('a full student bar in every mode, chat pinned, More with a badge: no overflow', (tester) async {
      for (final mode in [LiveShareButton.share, LiveShareButton.request, LiveShareButton.requested, LiveShareButton.stop]) {
        final share = ControlsWidgetState.shareAction(mode, onTap: () {})!;
        LiveControlBar bar() => LiveControlBar(
              primary: [
                LiveControlAction(key: const ValueKey('live_room.mic'), icon: Icons.mic_rounded, label: 'Mute', active: true, onTap: () {}),
                LiveControlAction(key: const ValueKey('live_room.camera'), icon: Icons.videocam_rounded, label: 'Camera', onTap: () {}),
                share,
                LiveControlAction(key: const ValueKey('live_room.reactions'), icon: Icons.add_reaction_outlined, label: 'React', onTap: () {}),
                LiveControlAction(key: const ValueKey('live_room.hand'), icon: Icons.back_hand_outlined, label: 'Raise hand', onTap: () {}),
                LiveControlAction(
                    key: const ValueKey('live_room.chat'), icon: Icons.chat_bubble_outline_rounded, label: 'Chat', badge: 7, pinned: true, onTap: () {}),
              ],
              secondary: [
                LiveControlAction(key: const ValueKey('live_room.speaker'), icon: Icons.speaker_phone_rounded, label: 'Speaker', onTap: () {}),
              ],
              end: LiveControlAction(key: const ValueKey('live_room.end'), icon: Icons.call_end_rounded, label: 'End', onTap: () {}),
            );
        await expectNoLayoutErrors(tester, () => Align(alignment: Alignment.bottomCenter, child: bar()), act: (t) async {
          if (t.view.physicalSize.width < kLiveControlsMobileBreakpoint) {
            expect(find.byKey(const ValueKey('live_room.chat')), findsOneWidget, reason: 'chat is pinned in the pill');
          }
        });
      }
    });

    testWidgets("a host's phone pill: hands + lobby inside More add to its badge", (tester) async {
      LiveControlBar bar() => LiveControlBar(
            primary: [
              LiveControlAction(key: const ValueKey('live_room.mic'), icon: Icons.mic_rounded, label: 'Mute', active: true, onTap: () {}),
              LiveControlAction(key: const ValueKey('live_room.camera'), icon: Icons.videocam_rounded, label: 'Camera', onTap: () {}),
              ControlsWidgetState.shareAction(LiveShareButton.share, onTap: () {})!,
              LiveControlAction(key: const ValueKey('live_room.reactions'), icon: Icons.add_reaction_outlined, label: 'React', onTap: () {}),
              LiveControlAction(
                  key: const ValueKey('live_room.hands'), icon: Icons.back_hand_rounded, label: 'Hands', badge: 4, attention: 2, onTap: () {}),
              LiveControlAction(key: const ValueKey('live_room.chat'), icon: Icons.chat_bubble_outline_rounded, label: 'Chat', pinned: true, onTap: () {}),
            ],
            secondary: [
              LiveControlAction(key: const ValueKey('live_room.speaker'), icon: Icons.speaker_phone_rounded, label: 'Speaker', onTap: () {}),
            ],
            end: LiveControlAction(key: const ValueKey('live_room.end'), icon: Icons.call_end_rounded, label: 'End', onTap: () {}),
            onLobby: () {},
            waitingCount: 3,
            lobbyAttention: 1,
          );
      await expectNoLayoutErrors(tester, () => Align(alignment: Alignment.bottomCenter, child: bar()), act: (t) async {
        if (t.view.physicalSize.width < kLiveControlsMobileBreakpoint) {
          final more = find.byKey(const ValueKey('live_room.more'));
          expect(more, findsOneWidget);
          // At 320 the lobby sits in the pill (its own badge); at 390 too. Inside More: the 2 new hands.
          expect(find.descendant(of: more, matching: find.text('2')), findsOneWidget, reason: 'the 2 new hands, not all 4');
        }
      });
    });
  });

  testWidgets('minimized box with an attention badge', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => Center(
              child: SizedBox(
                width: 150, // the smallest box (liveMiniSize)
                height: 94,
                child: LiveMiniBoxLayout(name: _long, onExpand: () {}, onToggleMic: () {}, onLeave: () {}, attention: 105),
              ),
            ));
  });
}
