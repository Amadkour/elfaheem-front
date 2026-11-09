// NextBrain Messages (D-330): no overflow from 320 px to desktop, Arabic and English, large text.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/chat/chat_api.dart';
import 'package:flutter_education_app/features/shared/chat/chat_models.dart';
import 'package:flutter_education_app/features/shared/chat/chat_sheets.dart';
import 'package:flutter_education_app/features/shared/chat/chat_store.dart';
import 'package:flutter_education_app/features/shared/chat/chat_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const longName = 'Abdelrahman Mohamed Ibrahim Abdelaziz El Sayed عبد الرحمن محمد إبراهيم عبد العزيز السيد';
final now = DateTime.utc(2026, 11, 8, 10);

ChatConversation conv({bool group = false, int unread = 3, bool muted = true}) => ChatConversation(
      id: 1,
      kind: group ? 'course_group' : 'direct',
      peer: group ? null : const ChatPerson(id: 2, name: longName, role: 'teacher'),
      online: !group,
      course: const ChatCourse(id: 3, name: 'أساسيات الرياضيات المتقدمة للمرحلة الثانوية', nameEn: 'Advanced Mathematics Foundations for Secondary'),
      child: const ChatPerson(id: 4, name: 'Omar Hassan', role: 'student'),
      last: ChatLastMessage(id: 9, kind: 'text', body: 'The homework is due tomorrow, please check the attached sheet carefully before you start.', senderId: 2, senderName: longName, createdAt: now),
      lastAt: now,
      unread: unread,
      muted: muted,
      pinned: true,
    );

ChatMessage m(int id, String body, {bool att = false}) => ChatMessage(
      id: id,
      clientId: 'c$id',
      conversationId: 1,
      body: body,
      senderId: 2,
      senderName: longName,
      senderIsTeacher: true,
      createdAt: now,
      attachments: att ? const [ChatAttachment(id: 1, name: 'a very long lecture notes file name for the midterm.pdf', mime: 'application/pdf', ext: 'pdf', size: 123456)] : const [],
    );

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('conversation tiles', (t) async {
    await expectNoLayoutErrors(t, () => Column(children: [
          ChatConversationTile(conversation: conv(), myId: 1, now: now),
          ChatConversationTile(conversation: conv(group: true, unread: 120, muted: false), myId: 1, now: now),
          ChatConversationTile(conversation: conv(unread: 0), myId: 2, draft: 'a long draft that the person has not sent yet', now: now),
          ChatConversationTile(conversation: conv(), myId: 1, typingName: longName, now: now),
        ]));
  });

  testWidgets('bubbles', (t) async {
    await expectNoLayoutErrors(t, () => ListView(padding: const EdgeInsets.all(8), children: [
          ChatBubble(message: m(1, 'short'), mine: false, showSender: true),
          ChatBubble(message: m(2, 'A much longer message that has to wrap over several lines in a phone width without any overflow at all. ' * 3), mine: true, tick: ChatTick.read),
          ChatBubble(message: m(3, '', att: true), mine: false),
          ChatBubble(message: m(4, 'with file', att: true), mine: true, tick: ChatTick.sending),
          ChatBubble(message: m(5, 'failed')..sendState = ChatSendState.failed, mine: true, tick: ChatTick.failed, onRetry: () {}),
          const ChatTypingBubble(name: longName),
          const ChatDateChip(label: 'Yesterday'),
        ]));
  });

  testWidgets('composer notices and chips', (t) async {
    await expectNoLayoutErrors(t, () => ListView(children: [
          for (final s in ChatComposerState.values) ChatComposerNotice(state: s, onUnblock: () {}),
        ]));
  });

  testWidgets('chips', (t) async {
    await expectNoLayoutErrors(t, () => ListView(children: [
          Wrap(children: [ChatPendingFileChip(name: 'a very very long file name that should be cut.png', onRemove: () {})]),
          Wrap(children: [ChatFilterChip(label: longName, selected: true, onTap: () {})]),
        ]));
  });

  testWidgets('composer with files, request bars, jump button, offline strip and dividers', (t) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    await expectNoLayoutErrors(t, () => ListView(children: [
          ChatComposerBar(
            controller: TextEditingController(text: 'a very long line of text in the composer ' * 12),
            focusNode: FocusNode(),
            onSend: () {},
            onChanged: (_) {},
            onAttach: () {},
            enterSends: true,
            files: [ChatLocalFile(name: 'a very very long photo name for the lecture.png', bytes: png), ChatLocalFile(name: 'report.pdf')],
            onRemoveFile: (_) {},
          ),
          ChatRequestCard(conversation: conv(), onAccept: () {}, onDecline: () {}, onBlock: () {}, now: now),
          ChatRequestDecisionBar(onAccept: () {}, onDecline: () {}, onBlock: () {}, reason: longName),
          ChatRequestsRow(count: 120, onTap: () {}),
          const ChatOfflineStrip(),
          const ChatUnreadDivider(),
          Align(alignment: AlignmentDirectional.centerEnd, child: ChatJumpToLatest(count: 120, onTap: () {})),
          ChatComposerNotice(state: ChatComposerState.requestSent, reason: longName),
        ]));
  });

  testWidgets('bubbles: local files, queued, failed with an actions row', (t) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    await expectNoLayoutErrors(t, () => ListView(children: [
          ChatBubble(message: ChatMessage(clientId: 'a', conversationId: 1, createdAt: now, senderId: 1, body: 'caption', local: [ChatLocalFile(name: 'p.png', bytes: png)], sendState: ChatSendState.sending), mine: true, tick: ChatTick.sending),
          ChatBubble(message: ChatMessage(clientId: 'b', conversationId: 1, createdAt: now, senderId: 1, body: 'waiting for the network', sendState: ChatSendState.queued), mine: true, tick: ChatTick.queued),
          ChatBubble(message: ChatMessage(clientId: 'c', conversationId: 1, createdAt: now, senderId: 1, body: 'refused', error: 'The server refused this message for a long reason that wraps', sendState: ChatSendState.failed), mine: true, tick: ChatTick.failed, onRetry: () {}, onDiscard: () {}),
          ChatBubble(message: ChatMessage(clientId: 'd', conversationId: 1, createdAt: now, senderId: 1, body: 'lost file', error: ChatMessage.lostFileError, sendState: ChatSendState.failed), mine: true, tick: ChatTick.failed, onRetry: () {}, onDiscard: () {}),
          ChatBubble(message: m(6, 'second of a run'), mine: false, runStart: false, runEnd: false),
        ]));
  });

  testWidgets('replies, deleted messages, links and long words at every width', (t) async {
    const quote = ChatReplyRef(id: 9, body: 'The question was about the second exercise in the chapter on vectors, and I still do not get it', senderId: 2, senderName: longName);
    await expectNoLayoutErrors(t, () => ListView(children: [
          ChatBubble(message: m(7, 'Yes, see https://example.com/a/very/long/path/that/goes/on/and/on/and/on?with=params&more=params')..replyTo = quote, mine: true, tick: ChatTick.read, myId: 2),
          ChatBubble(message: m(8, 'x' * 300), mine: false, myId: 1, pointerFirst: true, onReply: () {}, onActions: (_) {}),
          ChatBubble(message: ChatMessage(id: 10, clientId: 'd1', conversationId: 1, createdAt: now, senderId: 2, deleted: true), mine: false),
          ChatBubble(message: m(11, 'مرحبا hello 2026 مزيج')..replyTo = quote, mine: false, showSender: true, myId: 1, onQuoteTap: () {}),
          ChatComposerBar(controller: TextEditingController(), focusNode: FocusNode(), onSend: () {}, onChanged: (_) {}, replyTo: quote, replyIsMine: false, onCancelReply: () {}),
          const SizedBox(height: 320, child: ChatThreadSkeleton()),
        ]));
  });

  test('links: found with their punctuation left out, Arabic around them is kept', () {
    final parts = chatLinkify('شوف https://a.com/x، و www.b.org.');
    expect(parts.where((p) => p.url != null).map((p) => p.url), ['https://a.com/x', 'https://www.b.org']);
    expect(parts.map((p) => p.text).join(), 'شوف https://a.com/x، و www.b.org.');
    expect(chatLinkify('no links here').single.url, isNull);
  });

  test('the bubble inks stay readable on any brand colour', () {
    for (final bg in const [Color(0xFFF5C644), Color(0xFF123B8A), Colors.white, Color(0xFF16181D)]) {
      expect(chatContrast(chatReadableOn(bg, const Color(0xFFF5C644)), bg), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('block sheet at every level', (t) async {
    const person = ChatPerson(id: 2, name: longName);
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(
          child: ChatBlockSheet(user: person, preloaded: ChatBlockOptions(['person', 'course', 'all_courses'], [ChatCourse(id: 1, name: 'math', nameEn: 'Maths')], [])),
        ));
  });

  testWidgets('report sheet', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: ChatReportSheet(conversation: conv())));
  });
}
