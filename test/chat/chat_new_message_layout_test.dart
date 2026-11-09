// New message sheet (D-371): no overflow at 320 px or on a desktop, Arabic and English, large text; the states read
// right for "direct" vs "request" and the reason is drawn for an unavailable person.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/chat/chat_models.dart';
import 'package:flutter_education_app/features/shared/chat/chat_new_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const longName = 'Abdelrahman Mohamed Ibrahim Abdelaziz El Sayed عبد الرحمن محمد إبراهيم عبد العزيز السيد';

ChatPersonRow row(String state, {String relation = 'none', String role = 'teacher', String reason = '', String reasonEn = ''}) => ChatPersonRow(
      user: ChatPerson(id: state.hashCode, name: longName, role: role, username: 'long_username_here'),
      course: state == 'direct' ? const ChatCourse(id: 3, name: 'أساسيات الرياضيات المتقدمة للمرحلة الثانوية', nameEn: 'Advanced Mathematics Foundations for Secondary') : null,
      relation: relation,
      reach: ChatReach(state: state, reason: reason, reasonEn: reasonEn),
    );

final people = ChatPeople(
  recent: [row('thread'), row('request_sent'), row('direct')],
  suggested: [row('direct', relation: 'teacher'), row('thread', relation: 'student')],
  results: [
    row('direct', relation: 'teacher'),
    row('request'),
    row('unavailable', reason: 'وصلت إلى الحد اليومي لطلبات المحادثة', reasonEn: 'You have reached today\'s limit of new message requests; try again tomorrow'),
    row('request_received', role: 'parent'),
  ],
  requestsLeft: 3,
  requestsPerDay: 10,
);

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('the people list: empty search, suggestions and results', (tester) async {
    await expectNoLayoutErrors(tester, () => ChatPeopleView(people: people, query: '', onPick: (_) {}));
    await expectNoLayoutErrors(tester, () => ChatPeopleView(people: people, query: 'ab', onPick: (_) {}));
    await expectNoLayoutErrors(tester, () => ChatPeopleView(people: const ChatPeople(), query: 'ab', onPick: (_) {}));
    await expectNoLayoutErrors(tester, () => ChatPeopleView(people: const ChatPeople(), query: '', onPick: (_) {}));
  });

  test('one client id per composed text', () {
    final c = ChatComposedId();
    final a = c.idFor(7, 'hello');
    expect(c.idFor(7, 'hello'), a);
    expect(c.idFor(7, 'hello there'), isNot(a));
    final b = c.idFor(8, 'hello there');
    expect(b, isNot(a));
    expect(c.idFor(8, 'hello there'), b);
  });

  testWidgets('a short screen with the keyboard up: the sheet shrinks instead of overflowing', (tester) async {
    for (final h in const [150.0, 240.0]) {
      await expectNoLayoutErrors(tester, () => Align(alignment: Alignment.topCenter, child: SizedBox(height: h, child: const ChatNewMessageSheet())));
    }
  });

  testWidgets('the request composer', (tester) async {
    final controller = TextEditingController(text: 'Hello');
    await expectNoLayoutErrors(tester, () => ChatRequestComposer(person: row('request'), controller: controller, busy: false, error: 'Something failed', onSend: () {}, onBack: () {}));
  });

  testWidgets('direct and request read differently, an unavailable row shows its reason and takes no tap', (tester) async {
    int taps = 0;
    await tester.pumpWidget(layoutHost(Column(children: [
      ChatPersonTile(row: row('direct', relation: 'teacher'), onTap: () => taps++),
      ChatPersonTile(row: row('request'), onTap: () => taps++),
      ChatPersonTile(row: row('unavailable', reason: 'ع', reasonEn: 'Limit reached today'), onTap: () => taps++),
    ]), scale: 1));
    expect(find.text('chat_nm_reach_direct'), findsOneWidget);
    expect(find.text('chat_nm_reach_request'), findsOneWidget);
    expect(find.text('Limit reached today'), findsOneWidget);
    await tester.tap(find.text('Limit reached today'));
    expect(taps, 0);
  });

  test('the JSON the server sends parses, a stranger needs a request', () {
    final r = ChatPersonRow.fromJson({
      'user': {'id': 7, 'name': 'Sara', 'image_url': null, 'role': 'teacher', 'username': 'sara_t'},
      'course': null,
      'child': null,
      'org': null,
      'relation': 'none',
      'reach': {'state': 'request', 'conversation_id': null, 'reason': '', 'reason_en': ''},
    });
    expect(r.user.username, 'sara_t');
    expect(r.reach.needsRequest, isTrue);
    expect(r.toContact().conversationId, isNull);
    expect(chatComposerState('request_sent'), ChatComposerState.requestSent);
    final conv = ChatConversation.fromJson({
      'id': 3, 'kind': 'direct', 'last_message_at': '2026-11-09T10:00:00', 'request': {'state': 'pending', 'mine': true},
      'composer': {'state': 'request_sent', 'can_send': false, 'reason': 'بانتظار', 'reason_en': 'Waiting'},
    });
    expect(conv.request?.pending, isTrue);
    expect(conv.composerReasonEn, 'Waiting');
  });
}
