// LiveKit data packets in the room: which topic goes where (widgets/live_data_route.dart) and whose hand a
// hand packet may raise / lower (handPacketTarget in widgets/live_hands.dart). Any participant can publish
// data, so an unknown topic is dropped and a hand packet's payload identity is not trusted.
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_data_route.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_hands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveDataRoute', () {
    test('known topics', () {
      expect(liveDataRoute('reaction'), LiveDataRoute.reaction);
      expect(liveDataRoute('quiz'), LiveDataRoute.quiz);
      expect(liveDataRoute('hand'), LiveDataRoute.handOrChat);
      expect(liveDataRoute('chat'), LiveDataRoute.handOrChat);
      expect(liveDataRoute('annot'), LiveDataRoute.annotation);
      expect(liveDataRoute('annot.laser'), LiveDataRoute.annotation);
    });

    test('no topic is matched by payload (older senders)', () {
      expect(liveDataRoute(null), LiveDataRoute.handOrChat);
      expect(liveDataRoute(''), LiveDataRoute.handOrChat);
    });

    test('an unknown topic is ignored', () {
      expect(liveDataRoute('spam'), LiveDataRoute.ignore);
      expect(liveDataRoute('Hand'), LiveDataRoute.ignore);
      expect(liveDataRoute('lk-chat-topic'), LiveDataRoute.ignore);
    });
  });

  group('handPacketTarget', () {
    test('a raise is always the sender\'s own hand', () {
      expect(handPacketTarget(up: true, payloadIdentity: 'student_1', senderIdentity: 'student_1'), 'student_1');
      expect(handPacketTarget(up: true, payloadIdentity: 'student_2', senderIdentity: 'student_1'), 'student_1');
      expect(handPacketTarget(up: true, payloadIdentity: '', senderIdentity: 'guest:x'), 'guest:x');
    });

    test('lowering your own hand', () {
      expect(handPacketTarget(up: false, payloadIdentity: 'student_1', senderIdentity: 'student_1'), 'student_1');
      expect(handPacketTarget(up: false, payloadIdentity: '', senderIdentity: 'student_1'), 'student_1');
    });

    test('lowering someone else\'s hand only from a host', () {
      expect(handPacketTarget(up: false, payloadIdentity: 'student_2', senderIdentity: 'student_1'), isNull);
      expect(handPacketTarget(up: false, payloadIdentity: 'student_2', senderIdentity: 'guest:x'), isNull);
      expect(handPacketTarget(up: false, payloadIdentity: 'student_2', senderIdentity: 'teacher_9'), 'student_2');
      expect(handPacketTarget(up: false, payloadIdentity: 'guest:x', senderIdentity: 'teacher_9'), 'guest:x');
    });

    test('a packet without a sender (the server) is taken as written', () {
      expect(handPacketTarget(up: true, payloadIdentity: 'student_2'), 'student_2');
      expect(handPacketTarget(up: false, payloadIdentity: 'student_2', senderIdentity: ''), 'student_2');
      expect(handPacketTarget(up: false, payloadIdentity: ''), isNull);
    });
  });

  group('LiveHandsController.receive uses the sender', () {
    test('a forged raise lands on the sender, a forged lower is dropped', () {
      final c = LiveHandsController(localIdentity: () => 'teacher_9');
      final forgedRaise = LiveHandsController.encode(up: true, identity: 'student_2', name: 'Two', ts: 1);
      expect(c.receive(forgedRaise, senderIdentity: 'student_1', fallbackName: 'One'), isTrue);
      expect(c.hands.single.identity, 'student_1');
      expect(c.isUp('student_2'), isFalse);

      c.add(const LiveHand(identity: 'student_2', name: 'Two', ts: 2));
      final forgedLower = LiveHandsController.encode(up: false, identity: 'student_2');
      expect(c.receive(forgedLower, senderIdentity: 'student_1'), isTrue, reason: 'still a hand packet');
      expect(c.isUp('student_2'), isTrue);

      expect(c.receive(forgedLower, senderIdentity: 'teacher_9'), isTrue);
      expect(c.isUp('student_2'), isFalse);
      c.dispose();
    });

    test('the host lowering my hand resets my toggle', () {
      final c = LiveHandsController(localIdentity: () => 'student_1');
      c.setLocal(true, name: 'Me');
      expect(c.localUp, isTrue);
      c.receive(LiveHandsController.encode(up: false, identity: 'student_1'), senderIdentity: 'teacher_9');
      expect(c.localUp, isFalse);
      c.dispose();
    });
  });
}
