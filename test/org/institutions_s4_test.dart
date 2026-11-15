// Institutions S4 (messaging, D-975 – D-978): the payloads of docs/institutions/CONTRACT_S4.md, the composer's draft
// and its POST body, the error texts in both languages, the kill switches, the must-acknowledge host (shown after
// sign-in, never inside a live exam, the queue after an acknowledge) and the layout of the composer, the card, the
// sent card and the names sheet through the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live_focus.dart';
import 'package:flutter_education_app/features/org/org_messages.dart';
import 'package:flutter_education_app/features/org/org_messages_models.dart';
import 'package:flutter_education_app/features/org/org_must_ack.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show OrgCall;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> memberMsg({int id = 12, String delivery = 'must_ack', bool acked = false, Map<String, dynamic>? reply}) => {
      'id': id,
      'org_id': 1,
      'delivery': delivery,
      'title': 'تنبيه هام بخصوص موعد امتحانات منتصف الفصل — a long title that has to wrap on a phone',
      'body': 'نرجو من جميع الطلاب الالتزام بالمواعيد الجديدة.\n' * 6,
      'reason': delivery == 'must_ack' ? 'Rules changed: every student must confirm the new exam dates' : null,
      'sender': {'id': 4, 'name': 'أ.د. عميد الكلية — Dean with a long name', 'avatar': null},
      'dept': {'id': 3, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs'},
      'complaint_id': null,
      'work_item_id': null,
      'expires_at': '2026-11-20T10:00:00',
      'expired': false,
      'created_at': '2026-11-15T08:30:00',
      'org': {'id': 1, 'name_ar': 'كلية الهندسة', 'name_en': 'Faculty of Engineering', 'logo_url': null},
      'read_at': null,
      'acked_at': acked ? '2026-11-15T09:00:00' : null,
      'needs_ack': delivery == 'must_ack',
      'reply': reply ?? {'kind': 'chat', 'peer_id': 4, 'org_id': 1},
    };

Map<String, dynamic> staffMsg({String delivery = 'must_ack'}) => {
      ...memberMsg(delivery: delivery)..removeWhere((k, _) => const {'org', 'read_at', 'acked_at', 'needs_ack', 'reply'}.contains(k)),
      'audience': {'user_ids': [1, 2]},
      'stats': {'recipients': 1250, 'read': 900, 'acknowledged': 812, 'pending': 438},
      'recipients': {
        'total': 1250,
        'items': [
          {'user': {'id': 1, 'name': 'سارة محمود عبد الرحمن — a very long student name for the sheet', 'avatar': null}, 'read_at': '2026-11-15T08:40:00', 'acked_at': '2026-11-15T08:41:00'},
          {'user': {'id': 2, 'name': 'Omar', 'avatar': null}, 'read_at': '2026-11-15T08:50:00', 'acked_at': null},
          {'user': {'id': null, 'name': null, 'anonymous': true}, 'read_at': null, 'acked_at': null},
        ],
      },
    };

class _FakeSource implements MustAckSource {
  _FakeSource(this.queue);
  final List<Map<String, dynamic>> queue;
  int fetches = 0, acks = 0;

  MustAckState get _now => queue.isEmpty ? MustAckState.none : MustAckState.fromJson({'item': queue.first, 'queued': queue.length - 1});

  @override
  Future<MustAckState> fetch() async {
    fetches++;
    return _now;
  }

  @override
  Future<OrgCall> acknowledge(int id) async {
    acks++;
    queue.removeWhere((m) => m['id'] == id);
    return OrgCall({'id': id, 'acked_at': '2026-11-15T09:00:00', 'next': {'item': queue.isEmpty ? null : queue.first, 'queued': queue.isEmpty ? 0 : queue.length - 1}});
  }
}

ApiException _err(String code, [Map<String, dynamic> extra = const {}]) =>
    ApiException(message: 'server', statusCode: 429, code: code, body: {'detail': {'code': code, 'message': 'x', ...extra}});

void main() {
  setUp(() {
    AppConfig.lang = 'ar';
    AppConfig.disableList = [];
    AppConfig.orgsEnabled = true;
    LiveFocus.debugReset();
  });

  group('payloads', () {
    test('options: must-acknowledge permission, scope, today\'s count', () {
      final o = MsgOptions.fromJson({
        'can_send': true, 'can_must_ack': true, 'must_ack_scope': 'departments', 'head_dept_ids': [3], 'my_dept_ids': [3, 5],
        'ack_limit': 3, 'ack_used_today': 1, 'ack_max_days': 7, 'max_recipients': 5000,
      });
      expect(o.showMustAck, isTrue);
      expect(o.headOnly, isTrue);
      expect(o.headDeptIds, {3});
      expect(o.ackLeft, 2);
      expect(MsgOptions.fromJson({'can_must_ack': false}).showMustAck, isFalse);
    });

    test('member message: org, reply to the chat, needs_ack', () {
      final m = OrgMessage.fromJson(memberMsg());
      expect(m.mustAck, isTrue);
      expect(m.needsAck, isTrue);
      expect(m.orgName, 'كلية الهندسة');
      expect(m.deptName, 'شؤون الطلاب');
      expect(m.reply!.isChat, isTrue);
      expect(m.reply!.peerId, 4);
      expect(m.expiresAt!.toUtc(), DateTime.utc(2026, 11, 20, 10));
      final item = OrgMessage.fromJson(memberMsg(delivery: 'push', reply: {'kind': 'item', 'complaint_id': 4, 'work_item_id': null}));
      expect(item.reply!.isItem, isTrue);
      expect(item.reply!.complaintId, 4);
      expect(OrgMessage.fromJson(memberMsg(reply: {'kind': 'x'})).reply, isNull);
    });

    test('staff detail: stats and recipients, anonymous submitter', () {
      final d = MsgDetail.fromJson(staffMsg());
      expect(d.total, 1250);
      expect(d.message.stats!.acknowledged, 812);
      expect(d.recipients.length, 3);
      expect(d.recipients.first.ackedAt, isNotNull);
      expect(d.recipients.last.user.anonymous, isTrue);
      expect(d.recipients.last.user.shown, 'مقدّم مجهول');
    });

    test('must-ack state: item + queued, null item', () {
      final s = MustAckState.fromJson({'item': memberMsg(), 'queued': 2});
      expect(s.item!.id, 12);
      expect(s.queued, 2);
      expect(MustAckState.fromJson({'item': null, 'queued': 0}).item, isNull);
    });
  });

  group('draft', () {
    const ackOptions = MsgOptions(canMustAck: true, ackLimit: 3, ackUsedToday: 0);

    test('a normal message to students, a department and a course (union)', () {
      final d = MsgDraft()
        ..title = ' Hello '
        ..body = 'Text'
        ..students.addAll(const [MsgPick(1, 'A'), MsgPick(2, 'B')])
        ..dept = const MsgPick(3, 'Dept')
        ..course = const MsgPick(9, 'Course');
      expect(d.problem(), isNull);
      final b = d.toBody();
      expect(b['delivery'], 'normal');
      expect(b['title'], 'Hello');
      expect(b.containsKey('reason'), isFalse);
      expect(b.containsKey('expires_at'), isFalse);
      final to = b['to'] as Map;
      expect(to['user_ids'], [1, 2]);
      expect(to['dept_id'], 3);
      expect(to['course_id'], 9);
      expect(b['dry_run'], isFalse);
    });

    test('a linked message stands alone (the submitter only)', () {
      final d = MsgDraft(workItemId: 7)..body = 'About your request';
      expect(d.hasAudience, isTrue);
      expect(d.toBody()['to'], {'work_item_id': 7});
      expect(d.toBody()['title'], 'About your request');
      expect(MsgDraft(complaintId: 4).to, {'complaint_id': 4});
    });

    test('local checks use the server codes', () {
      expect(MsgDraft().problem(), 'no_recipients');
      final d = MsgDraft()..students.add(const MsgPick(1, 'A'));
      expect(d.problem(), 'message_empty');
      d
        ..title = 'T'
        ..delivery = MsgDelivery.mustAck;
      expect(d.problem(), 'ack_not_allowed');
      expect(d.problem(ackOptions), 'ack_reason_required');
      d.reason = 'ok!';
      expect(d.problem(ackOptions), isNull);
      expect(d.problem(const MsgOptions(canMustAck: true, ackUsedToday: 3)), 'ack_rate_limit');
      d.expiryDays = 8;
      expect(d.problem(ackOptions), 'ack_expiry_too_far');
    });

    test('must acknowledge: reason and a UTC expiry 3 days out by default', () {
      final now = DateTime.utc(2026, 11, 15, 10);
      final d = MsgDraft()
        ..students.add(const MsgPick(1, 'A'))
        ..title = 'T'
        ..delivery = MsgDelivery.mustAck
        ..reason = ' Exam dates ';
      final b = d.toBody(now: now);
      expect(b['delivery'], 'must_ack');
      expect(b['reason'], 'Exam dates');
      expect(DateTime.parse(b['expires_at'] as String), DateTime.utc(2026, 11, 18, 10));
      expect((b['expires_at'] as String).endsWith('Z'), isTrue);
      expect(d.dryRunBody()['dry_run'], isTrue);
      expect(d.dryRunBody()['delivery'], 'normal');            // the count line never touches the daily limit
    });
  });

  group('texts and switches', () {
    test('ack_rate_limit names the wait in both languages', () {
      final e = _err('ack_rate_limit', {'limit': 3, 'retry_after': 7200});
      expect(msgErrorText(e), contains('2 ساعة'));
      AppConfig.lang = 'en';
      expect(msgErrorText(e), contains('try again in 2 h'));
      expect(msgErrorText(_err('ack_out_of_audience')), contains('departments\' students'));
      expect(msgErrorText(_err('too_many_recipients', {'max': 5000})), contains('max 5000'));
      expect(msgErrorText(_err('bad_audience')), contains('submitter alone'));   // not the S1 audience editor's text
    });

    test('every code has Arabic and English', () {
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final e in msgCodeTexts().entries) {
          expect(e.value, isNot(e.key), reason: e.key);
          expect(e.value.trim(), isNotEmpty);
        }
      }
    });

    test('counts use the plural forms', () {
      expect(msgRecipientsText(1), 'طالب واحد');
      expect(msgRecipientsText(2), 'طالبان');
      expect(msgRecipientsText(5), '5 طلاب');
      expect(mustAckQueuedText(2), 'رسالتان أخريان تنتظران');
      AppConfig.lang = 'en';
      expect(msgRecipientsText(1), '1 student');
      expect(msgRecipientsText(12), '12 students');
      expect(mustAckQueuedText(3), '3 more messages are waiting');
    });

    test('kill switches hide the entries and the card', () {
      expect(orgMessagesEnabled(), isTrue);
      AppConfig.disableList = [orgMustAckFeatureKey];
      expect(orgMessagesEnabled(), isTrue);
      expect(orgMustAckEnabled(), isFalse);
      expect(const MsgOptions(canMustAck: true).showMustAck, isFalse);
      AppConfig.disableList = [orgMessagesFeatureKey];
      expect(orgMessagesEnabled(), isFalse);
      expect(orgMustAckEnabled(), isFalse);
    });

    test('never inside a live exam or a live room; only when signed in', () {
      expect(mustAckMayShow(examOpen: false, roomOpen: false), isTrue);
      expect(mustAckMayShow(examOpen: true, roomOpen: false), isFalse);
      expect(mustAckMayShow(examOpen: false, roomOpen: true), isFalse);
      expect(mustAckShouldAsk(signedIn: false, viewAs: false, enabled: true), isFalse);
      expect(mustAckShouldAsk(signedIn: true, viewAs: true, enabled: true), isFalse);
      expect(mustAckShouldAsk(signedIn: true, viewAs: false, enabled: false), isFalse);
      expect(mustAckShouldAsk(signedIn: true, viewAs: false, enabled: true), isTrue);
      expect(LiveEvents.serverTypes, containsAll([LiveEvents.orgMessage, LiveEvents.orgMustAck, LiveEvents.orgMessageAck]));
    });

    test('LiveFocus counts owners, not calls', () {
      final a = Object(), b = Object();
      LiveFocus.enterExam(a);
      LiveFocus.enterExam(b);
      LiveFocus.leaveExam(a);
      expect(LiveFocus.isExamOpen, isTrue);
      LiveFocus.leaveExam(a);
      expect(LiveFocus.examOpen.value, isTrue);
      LiveFocus.leaveExam(b);
      expect(LiveFocus.isExamOpen, isFalse);
    });
  });

  group('host', () {
    Widget host(_FakeSource src) => layoutHost(OrgMustAckHost(source: src, signedIn: () => true, child: const Scaffold(body: Text('home'))), scaffold: false);

    testWidgets('shows after sign-in, acknowledges into the next one, then gets out of the way', (tester) async {
      final src = _FakeSource([memberMsg(id: 1), memberMsg(id: 2, delivery: 'must_ack')]);
      await tester.pumpWidget(host(src));
      await tester.pump();
      await tester.pump();
      expect(src.fetches, 1);
      expect(find.byType(MustAckCardView), findsOneWidget);
      expect(find.text('رسالة أخرى تنتظر بعد هذه'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('must_ack.ok')));
      await tester.tap(find.byKey(const ValueKey('must_ack.ok')));
      await tester.pump();
      await tester.pump();
      expect(src.acks, 1);
      expect(find.byKey(const ValueKey('must_ack.2')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('must_ack.ok')));
      await tester.tap(find.byKey(const ValueKey('must_ack.ok')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(MustAckCardView), findsNothing);
      expect(find.text('home'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('a live exam asks nothing; leaving it reads /me/must-ack again', (tester) async {
      final owner = Object();
      LiveFocus.enterExam(owner);
      final src = _FakeSource([memberMsg(id: 1)]);
      await tester.pumpWidget(host(src));
      await tester.pump();
      await tester.pump();
      expect(src.fetches, 0);
      expect(find.byType(MustAckCardView), findsNothing);
      LiveEvents.instance.emit(LiveEvents.orgMustAck, {'org_id': 1, 'message_id': 1});
      await tester.pump();
      expect(src.fetches, 0);
      LiveFocus.leaveExam(owner);
      await tester.pump();
      await tester.pump();
      expect(src.fetches, 1);
      expect(find.byType(MustAckCardView), findsOneWidget);
      // an exam opening over a waiting card hides it at once
      LiveFocus.enterExam(owner);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MustAckCardView), findsNothing);
      LiveFocus.leaveExam(owner);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('layout', () {
    MsgDraft draft({bool ack = false, bool linked = false}) {
      final d = linked ? MsgDraft(complaintId: 4) : MsgDraft();
      if (!linked) {
        d.students.addAll(const [MsgPick(1, 'سارة محمود عبد الرحمن — a long student name'), MsgPick(2, 'Omar')]);
        d.dept = const MsgPick(3, 'إدارة شؤون الطلاب والخريجين — a long department');
      }
      if (ack) d.delivery = MsgDelivery.mustAck;
      return d;
    }

    Widget composer(MsgDraft d, {MsgOptions options = const MsgOptions(canMustAck: true, ackUsedToday: 1, mustAckScope: 'departments'), String? error}) =>
        SingleChildScrollView(
          child: MessageComposerView(
            draft: d,
            options: options,
            title: TextEditingController(text: 'Title'),
            body: TextEditingController(text: 'Body'),
            reason: TextEditingController(),
            count: 1250,
            queued: 12,
            error: error,
            onDelivery: (_) {},
            onExpiry: (_) {},
            onSend: () {},
            onAddStudents: () {},
            onPickDept: () {},
            onPickCourse: () {},
          ),
        );

    testWidgets('composer: normal, must acknowledge, linked, without the ack card', (tester) async {
      await expectNoLayoutErrors(tester, () => composer(draft()));
      await expectNoLayoutErrors(tester, () => composer(draft(ack: true), error: 'أرسلت الحد الأقصى من رسائل الإقرار (3 في 24 ساعة)'));
      await expectNoLayoutErrors(tester, () => composer(draft(linked: true), options: const MsgOptions()));
    });

    testWidgets('composer: Must acknowledge is drawn only when the server allows it', (tester) async {
      await tester.pumpWidget(layoutHost(composer(draft(), options: const MsgOptions())));
      expect(find.byKey(const ValueKey('msg.delivery.must_ack')), findsNothing);
      expect(find.byKey(const ValueKey('msg.delivery.push')), findsOneWidget);
      await tester.pumpWidget(layoutHost(composer(draft())));
      expect(find.byKey(const ValueKey('msg.delivery.must_ack')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the must-acknowledge card', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => MustAckCardView(
              message: OrgMessage.fromJson(memberMsg()), queued: 2, error: 'تعذّر الحفظ — حاول مرة أخرى', onAcknowledge: () {}),
          scaffold: false);
    });

    testWidgets('sent card and names sheet', (tester) async {
      final m = OrgMessage.fromJson(staffMsg());
      final d = MsgDetail.fromJson(staffMsg());
      await expectNoLayoutErrors(tester, () => ListView(children: [SentMessageCard(message: m, onTap: () {}), SentMessageCard(message: OrgMessage.fromJson(staffMsg(delivery: 'push')), onTap: () {})]));
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: SentNamesView(message: d.message, recipients: d.recipients, total: d.total, filter: MsgRecipientFilter.pending, onFilter: (_) {})));
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: SentNamesView(message: OrgMessage.fromJson(staffMsg(delivery: 'normal')), recipients: const [], total: 0, filter: MsgRecipientFilter.all, onFilter: (_) {})));
    });

    testWidgets('member card and open message', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(children: [
            MemberMessageCard(message: OrgMessage.fromJson(memberMsg()), onTap: () {}),
            MemberMessageCard(message: OrgMessage.fromJson(memberMsg(acked: true)), onTap: () {}),
          ]));
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: MemberMessageView(
                  message: OrgMessage.fromJson(memberMsg(delivery: 'push', reply: {'kind': 'item', 'complaint_id': 4})), onAcknowledge: () {}, onReplyChat: () {})));
    });
  });
}
