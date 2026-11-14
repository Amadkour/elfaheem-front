// NextBrain Messages (D-330): the pure message merging, tick and parsing rules.
import 'package:flutter_education_app/features/messaging/chat/chat_models.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage msg(int? id, String client, {ChatSendState s = ChatSendState.sent, int sec = 0}) =>
    ChatMessage(id: id, clientId: client, conversationId: 1, createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)), sendState: s, body: 'b$client');

void main() {
  test('a pending message is replaced by its stored self, no duplicates, newest first', () {
    final pending = msg(null, 'c1', s: ChatSendState.sending, sec: 5);
    final merged = chatMergeMessages([msg(1, 'a', sec: 1), pending], [msg(9, 'c1', sec: 5), msg(1, 'a', sec: 1)]);
    expect(merged.map((m) => m.id), [9, 1]);
    expect(merged.first.sendState, ChatSendState.sent);
    expect(identical(merged.first, pending), isTrue);
  });

  test('messages still going out stay above the stored ones', () {
    final merged = chatMergeMessages([msg(3, 'x', sec: 1), msg(null, 'p', s: ChatSendState.sending, sec: 9)], const []);
    expect(merged.first.clientId, 'p');
  });

  test('the same client id never adds a second row', () {
    final merged = chatMergeMessages([msg(4, 'dup')], [msg(4, 'dup')]);
    expect(merged.length, 1);
  });

  test('ticks: sending, failed, sent, delivered, read', () {
    expect(chatTickFor(msg(null, 'a', s: ChatSendState.sending)), ChatTick.sending);
    expect(chatTickFor(msg(null, 'a', s: ChatSendState.failed)), ChatTick.failed);
    expect(chatTickFor(msg(5, 'a')), ChatTick.sent);
    expect(chatTickFor(msg(5, 'a'), peerDeliveredId: 5), ChatTick.delivered);
    expect(chatTickFor(msg(5, 'a'), peerDeliveredId: 9, peerReadId: 6), ChatTick.read);
    expect(chatTickFor(msg(7, 'a'), peerReadId: 6, peerDeliveredId: 6), ChatTick.sent);
  });

  test('composer states and a server conversation row', () {
    expect(chatComposerState('you_blocked'), ChatComposerState.youBlocked);
    expect(chatComposerState('whatever'), ChatComposerState.ended);
    final c = ChatConversation.fromJson({
      'id': 3,
      'kind': 'direct',
      'peer': {'id': 2, 'name': 'Sara', 'image_url': '', 'role': 'teacher'},
      'online': true,
      'course': {'id': 8, 'name': 'رياضيات', 'name_en': 'Maths'},
      'child': {'id': 9, 'name': 'Ali', 'role': 'student'},
      'last_message': {'id': 11, 'kind': 'text', 'body': 'hi', 'sender_id': 2, 'created_at': '2026-01-01T10:00:00'},
      'last_message_at': '2026-01-01T10:00:00',
      'unread': 2,
      'composer': {'state': 'blocked', 'can_send': false},
    });
    expect(c.title, 'Sara');
    expect(c.peer!.imageUrl, isNull);
    expect(c.composer, ChatComposerState.blocked);
    expect(c.child!.name, 'Ali');
    expect(c.last!.createdAt.isUtc, isTrue);
  });
}
