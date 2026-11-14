// Hand-raise queue (LiveHandsPanel) and in-room chat (LiveChatPanel) at 320x640 and 1400x900, ar + en,
// textScaler 1.3, inside the 320 px side column and as a full-width sheet body; plus the pure controller logic
// (ordering, dedupe, disconnect drop, own-toggle reset, rate limit, cap, unread).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_chat.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_hands.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _arLong = 'سؤال طويل جدًا عن الدرس الأخير حول البرمجة الديناميكية على الأشجار وكيفية حساب التعقيد الزمني لكل حالة؟';
const _enLong =
    'A very long English question about the last lecture on dynamic programming over trees and how to compute the time complexity of every state, please?';

LiveHandsController _sixHands() {
  final c = LiveHandsController(localIdentity: () => 'me');
  final base = DateTime.now().millisecondsSinceEpoch - 10 * 60 * 1000;
  c.add(LiveHand(identity: '42', name: 'Sara Ahmed', ts: base + 3000));
  c.add(LiveHand(identity: 'guest:abc123', name: 'Visitor with a rather long display name', ts: base + 1000));
  c.add(LiveHand(identity: '7', name: 'أحمد حمدي مدكور الطالب ذو الاسم الطويل جدًا', ts: base + 2000));
  c.add(LiveHand(identity: 'guest:zz9', name: '', ts: base + 4000));
  c.add(LiveHand(identity: '99', name: 'Omar', ts: base + 5000));
  c.add(LiveHand(identity: 'guest:q', name: 'ضيف', ts: DateTime.now().millisecondsSinceEpoch));
  return c;
}

LiveChatController _thirtyMessages() {
  var n = 0;
  final c = LiveChatController(
    localIdentity: () => 'me',
    minInterval: Duration.zero,
    newId: () => 'id${n++}',
  );
  final base = DateTime.now().millisecondsSinceEpoch - 30 * 60 * 1000;
  for (var i = 0; i < 30; i++) {
    final mine = i % 4 == 0;
    final guest = i % 5 == 0;
    c.add(LiveChatMessage(
      id: 'm$i',
      identity: mine ? 'me' : (guest ? 'guest:g$i' : '${i % 3}'),
      name: mine ? 'Me' : (guest ? 'Guest $i' : ['Sara', 'أحمد حمدي', 'Omar Khaled Mohamed'][i % 3]),
      text: i % 3 == 0 ? _arLong : (i % 3 == 1 ? _enLong : 'ok 👍 $i'),
      ts: base + i * 60 * 1000,
      mine: mine,
    ));
  }
  return c;
}

/// A 320 px side column (what RoomPage shows on wide screens) and a full-width sheet body.
Widget _column(Widget child, {bool side = true}) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: side ? SizedBox(width: 320, child: child) : child,
    );

void main() {
  group('LiveHandsPanel layout', () {
    testWidgets('teacher: 6 hands incl. guests, side column and full width', (tester) async {
      final c = _sixHands();
      addTearDown(c.dispose);
      await expectNoLayoutErrors(
        tester,
        () => _column(LiveHandsPanel(
            controller: c, isTeacher: true, onLower: (_) {}, onAllowSpeak: (_) {}, onClose: () {}, busyIdentity: '99')),
        act: (t) async {
          expect(find.byKey(const ValueKey('live_hands.header')), findsOneWidget);
          expect(find.byKey(const ValueKey('live_hands.allow.guest:abc123')), findsOneWidget);
          expect(find.byKey(const ValueKey('live_hands.allow.42')), findsNothing); // students: no allow-speak
          expect(find.byKey(const ValueKey('live_hands.lower.42')), findsOneWidget);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => _column(LiveHandsPanel(controller: c, isTeacher: true, onLower: (_) {}, onAllowSpeak: (_) {}), side: false),
      );
    });

    testWidgets('student view (read-only) and empty queue', (tester) async {
      final c = _sixHands();
      addTearDown(c.dispose);
      await expectNoLayoutErrors(tester, () => _column(LiveHandsPanel(controller: c, isTeacher: false, onClose: () {})),
          act: (t) async => expect(find.byKey(const ValueKey('live_hands.lower.42')), findsNothing));
      final empty = LiveHandsController(localIdentity: () => 'me');
      addTearDown(empty.dispose);
      await expectNoLayoutErrors(tester, () => _column(LiveHandsPanel(controller: empty, isTeacher: true, onClose: () {})),
          act: (t) async => expect(find.byKey(const ValueKey('live_hands.empty')), findsOneWidget));
    });

    testWidgets('hand badge fits a tiny tile', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => const Center(
          child: SizedBox(
            width: 120,
            height: 90,
            child: Stack(children: [
              Positioned(top: 4, left: 4, child: LiveHandBadge(compact: true)),
              Positioned(bottom: 4, left: 4, child: LiveHandBadge()),
            ]),
          ),
        ),
      );
    });
  });

  group('LiveChatPanel layout', () {
    testWidgets('30 messages with long Arabic + English text, input row, teacher clear', (tester) async {
      LiveChatController? c;
      await expectNoLayoutErrors(
        tester,
        () {
          c?.dispose();
          c = _thirtyMessages();
          return _column(LiveChatPanel(controller: c!, senderName: 'Me', canClear: true, onClose: () {}));
        },
        act: (t) async {
          expect(find.byKey(const ValueKey('live_chat.input_row')), findsOneWidget);
          expect(find.byKey(const ValueKey('live_chat.clear')), findsOneWidget);
          await t.enterText(find.byKey(const ValueKey('live_chat.input')), 'مرحبا hello');
          await t.tap(find.byKey(const ValueKey('live_chat.send')));
          await t.pump();
          expect(c!.messages.last.text, 'مرحبا hello');
          expect(c!.messages.last.mine, isTrue);
        },
      );
      c?.dispose();
    });

    testWidgets('full width (sheet body) and empty chat for a guest', (tester) async {
      LiveChatController? c;
      await expectNoLayoutErrors(tester, () {
        c?.dispose();
        c = _thirtyMessages();
        return _column(LiveChatPanel(controller: c!, senderName: 'Guest'), side: false);
      });
      c?.dispose();
      final empty = LiveChatController(localIdentity: () => 'guest:x');
      await expectNoLayoutErrors(tester, () => _column(LiveChatPanel(controller: empty, senderName: 'Guest', onClose: () {})),
          act: (t) async {
        expect(find.byKey(const ValueKey('live_chat.empty')), findsOneWidget);
        expect(find.byKey(const ValueKey('live_chat.clear')), findsNothing);
      });
      empty.dispose();
    });

    testWidgets('panel open/close drives the unread count', (tester) async {
      final c = LiveChatController(localIdentity: () => 'me');
      addTearDown(c.dispose);
      c.add(const LiveChatMessage(id: 'a', identity: '1', name: 'A', text: 'hi', ts: 0));
      expect(c.unread, 1);
      await tester.pumpWidget(layoutHost(LiveChatPanel(controller: c, senderName: 'Me')));
      await tester.pump();
      expect(c.isOpen, isTrue);
      expect(c.unread, 0);
      c.add(const LiveChatMessage(id: 'b', identity: '1', name: 'A', text: 'again', ts: 1));
      expect(c.unread, 0); // open → read immediately
      await tester.pumpWidget(const SizedBox());
      expect(c.isOpen, isFalse);
      c.add(const LiveChatMessage(id: 'c', identity: '1', name: 'A', text: 'later', ts: 2));
      expect(c.unread, 1);
    });
  });

  group('bar badges and prejoin mic meter', () {
    testWidgets('hand / hands / chat buttons with count badges never overflow (phone + wide)', (tester) async {
      LiveControlAction a(String k, IconData i, String l, {int badge = 0, bool active = false}) =>
          LiveControlAction(key: ValueKey('live_room.$k'), icon: i, label: l, badge: badge, active: active, onTap: () {});
      final primary = [
        a('mic', Icons.mic_rounded, 'Mute', active: true),
        a('camera', Icons.videocam_rounded, 'الكاميرا', active: true),
        a('reactions', Icons.add_reaction_outlined, 'React'),
        a('hand', Icons.back_hand_rounded, 'إنزال اليد', active: true),
        a('hands', Icons.back_hand_rounded, 'Hands', badge: 12, active: true),
        a('chat', Icons.chat_bubble_outline_rounded, 'Chat', badge: 120),
      ];
      await expectNoLayoutErrors(
        tester,
        () => Align(
          alignment: Alignment.bottomCenter,
          child: LiveControlBar(
            primary: primary,
            groups: [primary.take(2).toList(), primary.skip(2).toList()],
            end: a('end', Icons.call_end_rounded, 'End'),
          ),
        ),
        act: (t) async {
          final more = find.byKey(const ValueKey('live_room.more'));
          if (more.evaluate().isNotEmpty) {
            await t.tap(more); // phone: badges also render in the More sheet rows
            await t.pump(const Duration(milliseconds: 300));
            expect(find.byKey(const ValueKey('live_room.chat.sheet')), findsOneWidget);
          } else {
            expect(find.byKey(const ValueKey('live_room.chat')), findsOneWidget);
          }
        },
      );
    });

    testWidgets('PreJoinLayout with a live mic level draws the 8-segment meter under the mic pill', (tester) async {
      for (final level in [0.0, 0.37, 1.0]) {
        await expectNoLayoutErrors(
          tester,
          () => PreJoinLayout(
            title: 'Live session',
            isTeacher: false,
            userName: 'أحمد حمدي',
            preview: null,
            micOn: true,
            camOn: false,
            onToggleMic: () {},
            onToggleCam: () {},
            mics: const [('m1', 'Microphone')],
            cams: const [('c1', 'Camera')],
            selectedMic: 'm1',
            selectedCam: 'c1',
            onMicChanged: (_) {},
            onCamChanged: (_) {},
            busy: false,
            onJoin: () {},
            onBack: () {},
            micLevel: level,
          ),
          act: (t) async => expect(find.byKey(const ValueKey('prejoin.mic.meter')), findsOneWidget),
        );
      }
      // Mic off (or no level on mobile) → no meter.
      await expectNoLayoutErrors(
        tester,
        () => PreJoinLayout(
          title: 'Live session',
          isTeacher: true,
          userName: 'A',
          preview: null,
          micOn: false,
          camOn: false,
          onToggleMic: () {},
          onToggleCam: () {},
          mics: const [],
          cams: const [],
          selectedMic: null,
          selectedCam: null,
          onMicChanged: (_) {},
          onCamChanged: (_) {},
          busy: false,
          onJoin: () {},
          onBack: () {},
          micLevel: 0.5,
        ),
        act: (t) async => expect(find.byKey(const ValueKey('prejoin.mic.meter')), findsNothing),
      );
    });
  });

  group('LiveHandsController', () {
    test('orders by ts, dedupes by identity, drops on disconnect', () {
      final sent = <Map>[];
      final c = LiveHandsController(
          localIdentity: () => 'me', onSend: (b) async => sent.add(jsonDecode(utf8.decode(b)) as Map));
      c.add(const LiveHand(identity: 'b', name: 'B', ts: 200));
      c.add(const LiveHand(identity: 'a', name: 'A', ts: 100));
      c.add(const LiveHand(identity: 'c', name: 'C', ts: 300));
      expect(c.hands.map((h) => h.identity), ['a', 'b', 'c']);
      expect(c.add(const LiveHand(identity: 'b', name: 'B again', ts: 50)), isFalse); // duplicate keeps its place
      expect(c.hands.map((h) => h.identity), ['a', 'b', 'c']);
      expect(c.count, 3);
      c.drop('b');
      expect(c.hands.map((h) => h.identity), ['a', 'c']);
      expect(c.isUp('b'), isFalse);
      expect(sent, isEmpty); // add/drop are local
      c.dispose();
    });

    test('local raise/lower sends packets; a received lower for me resets my toggle', () {
      final sent = <Map>[];
      final c = LiveHandsController(
          localIdentity: () => 'me', onSend: (b) async => sent.add(jsonDecode(utf8.decode(b)) as Map));
      c.toggleLocal(name: 'Me');
      expect(c.localUp, isTrue);
      expect(sent.single['up'], isTrue);
      expect(sent.single['identity'], 'me');
      expect(sent.single['name'], 'Me');
      expect(sent.single['ts'], isA<int>());
      c.toggleLocal(name: 'Me'); // raise again → no-op packet? no: it is a lower
      expect(c.localUp, isFalse);
      expect(sent.last['up'], isFalse);
      // Teacher lowers my hand from their side.
      c.setLocal(true, name: 'Me');
      expect(c.receive(LiveHandsController.encode(up: false, identity: 'me')), isTrue);
      expect(c.localUp, isFalse);
      c.dispose();
    });

    test('receive: raise packets, name fallback, unknown payloads', () {
      final c = LiveHandsController(localIdentity: () => 'me');
      expect(c.receive(LiveHandsController.encode(up: true, identity: 'guest:1', name: '', ts: 5), fallbackName: 'Visitor'), isTrue);
      expect(c.hands.single.name, 'Visitor');
      expect(c.hands.single.isGuest, isTrue);
      expect(c.receive(LiveHandsController.encode(up: true, identity: 'guest:1', name: 'Dup', ts: 1)), isTrue);
      expect(c.count, 1);
      expect(c.receive(utf8.encode('{"type":"chat","text":"x"}')), isFalse);
      expect(c.receive('garbage'.codeUnits), isFalse);
      // Teacher lowers a guest and tells the room.
      final sent = <Map>[];
      c.onSend = (b) async => sent.add(jsonDecode(utf8.decode(b)) as Map);
      c.lower('guest:1');
      expect(c.count, 0);
      expect(sent.single, {'type': 'hand', 'up': false, 'identity': 'guest:1'});
      c.lower('guest:1'); // nothing to lower → no packet
      expect(sent.length, 1);
      c.dispose();
    });
  });

  group('LiveChatController', () {
    test('send: trims, caps at 500 chars, rate-limits to one per interval', () {
      var t = DateTime(2026, 1, 1, 12);
      final sent = <Map>[];
      var n = 0;
      final c = LiveChatController(
        localIdentity: () => 'me',
        onSend: (b) async => sent.add(jsonDecode(utf8.decode(b)) as Map),
        newId: () => 'id${n++}',
        now: () => t,
      );
      expect(c.send('   ', name: 'Me'), isFalse);
      expect(c.send('  hello  ', name: 'Me'), isTrue);
      expect(sent.single['text'], 'hello');
      expect(sent.single['id'], 'id0');
      expect(sent.single['identity'], 'me');
      expect(c.send('too fast', name: 'Me'), isFalse); // within 500 ms
      t = t.add(const Duration(milliseconds: 499));
      expect(c.send('still too fast', name: 'Me'), isFalse);
      t = t.add(const Duration(milliseconds: 1));
      expect(c.send('x' * 600, name: 'Me'), isTrue);
      expect(c.messages.last.text.length, kLiveChatMaxChars);
      expect(c.messages.length, 2);
      expect(c.unread, 0); // own messages are never unread
      c.dispose();
    });

    test('receive: dedupe by id, own identity → mine, unread while closed, cap at maxMessages', () {
      final c = LiveChatController(localIdentity: () => 'me', maxMessages: 5);
      final pkt = LiveChatController.encode(
          const LiveChatMessage(id: 'k1', identity: '7', name: 'Sara', text: 'hi', ts: 10));
      expect(c.receive(pkt), isTrue);
      expect(c.receive(pkt), isTrue); // same id → swallowed
      expect(c.messages.length, 1);
      expect(c.unread, 1);
      expect(c.receive(LiveChatController.encode(const LiveChatMessage(id: 'k2', identity: 'me', name: 'Me', text: 'echo', ts: 11))),
          isTrue);
      expect(c.messages.last.mine, isTrue);
      expect(c.unread, 1);
      expect(c.receive(utf8.encode('{"type":"chat","id":"k3","text":"   "}')), isTrue); // empty → ignored
      expect(c.messages.length, 2);
      expect(c.receive(utf8.encode('{"type":"hand","up":true}')), isFalse);
      expect(c.receive('nope'.codeUnits), isFalse);
      for (var i = 0; i < 10; i++) {
        c.add(LiveChatMessage(id: 'f$i', identity: '1', name: 'A', text: '$i', ts: 100 + i));
      }
      expect(c.messages.length, 5);
      expect(c.messages.first.id, 'f5');
      expect(c.messages.last.id, 'f9');
      expect(c.add(const LiveChatMessage(id: 'k1', identity: '7', name: 'Sara', text: 'hi', ts: 10)), isTrue); // evicted id can return
      c.setOpen(true);
      expect(c.unread, 0);
      c.clear();
      expect(c.messages, isEmpty);
      c.dispose();
    });
  });
}
