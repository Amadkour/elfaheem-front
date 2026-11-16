// UX v3 phase 2: deep-link notifications and badges.
//   • NotifLink parses a notification row, the target answer, a push, an old row and a stale answer
//   • every action has its banner label in Arabic and English
//   • the routing decision for each module (incl. action_inbox) and the attention row's target (one → the item,
//     several → Needs my action)
//   • ActionBanner, StaleLinkView, NeedsMyActionList and NeedsMyActionPage (over FakeApi) on every screen size
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/notif_link.dart';
import 'package:flutter_education_app/design/action_banner.dart';
import 'package:flutter_education_app/design/attention_badge.dart' show attentionTargetLink;
import 'package:flutter_education_app/features/org/needs_my_action_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _row = {
  'id': 'n1',
  'action': 'edit',
  'link': {
    'module': 'org_work',
    'id': 41,
    'org_id': 7,
    'focus': 'decision',
    'reason_ar': 'طلب المراجِع تعديل العنوان',
    'reason_en': 'The reviewer asked you to change the title',
    'note': 'Please name the course',
    'fields': ['title', {'name': 'body', 'label_ar': 'التفاصيل', 'label_en': 'Details'}],
  },
};

Map<String, dynamic> _inboxItem(int i, {int urgency = 1, bool overdue = false}) => {
      'key': 'org_work:$i',
      'kind': 'work_item',
      'action': i.isEven ? 'approve' : 'vote',
      'title': 'A request with a long title that wraps on a small phone number $i',
      'reason_ar': 'بانتظار قرارك منذ يومين',
      'reason_en': 'Waiting for your decision for two days',
      'module': i.isEven ? 'org_work' : 'org_council',
      'id': 100 + i,
      'org_id': 7,
      'org_name': 'Faculty of Engineering and Applied Sciences',
      'due_at': '2026-11-20T10:00:00',
      'overdue': overdue,
      'urgency': urgency,
      'created_at': '2026-11-14T10:00:00',
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('NotifLink parsing', () {
    test('a notification row', () {
      final l = NotifLink.fromRow(_row)!;
      expect(l.action, NotifAction.edit);
      expect(l.module, 'org_work');
      expect(l.id, 41);
      expect(l.orgId, 7);
      expect(l.focus, 'decision');
      expect(l.note, 'Please name the course');
      expect(l.fields.map((f) => f.key).toList(), ['title', 'body']);
      expect(l.fields.map((f) => f.label).toList(), ['title', 'Details']);
      expect(l.reason, 'The reviewer asked you to change the title');
      AppConfig.lang = 'ar';
      expect(l.reason, 'طلب المراجِع تعديل العنوان');
      expect(l.fields[1].label, 'التفاصيل');
      expect(l.stale, isFalse);
    });

    test('an old row has neither key → null (today\'s routing)', () {
      expect(NotifLink.fromRow({'id': 'n2', 'title': 'Hi', 'related_type': 'org_work_item'}), isNull);
      expect(NotifLink.fromTarget({'module': 'org_work', 'target_id': 3, 'org_id': 1}), isNull);
      expect(NotifLink.fromPush({'module': 'org_work', 'id': '3'}), isNull);
    });

    test('the target answer (keys at the top)', () {
      final l = NotifLink.fromTarget({
        'module': 'org_council',
        'target_id': 9,
        'org_id': 2,
        'action': 'vote',
        'reason_ar': 'صوّت',
        'reason_en': 'Vote',
        'note': null,
        'fields': [],
        'focus': 'agenda:5',
      })!;
      expect((l.action, l.module, l.id, l.orgId, l.focus), (NotifAction.vote, 'org_council', 9, 2, 'agenda:5'));
      expect(l.note, isNull);
      expect(l.fields, isEmpty);
      expect(notifLinkDestination(l), NotifDestination.govSession);
    });

    test('a stale target answer', () {
      final l = NotifLink.fromTarget({
        'stale': true,
        'stale_reason_ar': 'اتُّخذ القرار بالفعل',
        'stale_reason_en': 'A decision was already made',
        'fallback': {'module': 'org_assignments'},
      })!;
      expect(l.stale, isTrue);
      expect(l.staleReason, 'A decision was already made');
      expect(l.fallbackModule, 'org_assignments');
      expect(notifLinkDestination(l), NotifDestination.stale);
    });

    test('push data (all strings)', () {
      final l = NotifLink.fromPush({
        'notification_id': 'abc',
        'action': 'fill',
        'module': 'org_form_assignment',
        'id': '12',
        'org_id': '3',
        'reason_ar': 'املأ',
        'reason_en': 'Fill it',
      })!;
      expect((l.notificationId, l.action, l.module, l.id, l.orgId), ('abc', NotifAction.fill, 'org_form_assignment', 12, 3));
      expect(l.reason, 'Fill it');
      expect(notifLinkDestination(l), NotifDestination.govAssignment);
      // a push with only its notification id still routes through the target answer
      expect(NotifLink.fromPush({'notification_id': 'x'})!.notificationId, 'x');
    });

    test('rejected reads "Rejected: see why"', () {
      final l = NotifLink.fromRow({'action': 'edit', 'link': {'module': 'org_work', 'id': 1, 'outcome': 'rejected'}})!;
      expect(l.rejected, isTrue);
      expect(notifActionLabel(l.action, rejected: l.rejected), 'Rejected: see why');
      AppConfig.lang = 'ar';
      expect(notifActionLabel(l.action, rejected: true), 'مرفوض: اطّلع على السبب');
    });
  });

  test('every action has its banner label in both languages', () {
    const en = {
      NotifAction.edit: 'Needs your edit',
      NotifAction.confirm: 'Awaiting your confirmation',
      NotifAction.vote: 'Vote required',
      NotifAction.review: 'New request',
      NotifAction.reply: 'Reply needed',
      NotifAction.fill: 'Fill the form',
      NotifAction.approve: 'Awaiting your approval',
      NotifAction.view: 'For your information',
    };
    for (final e in en.entries) {
      AppConfig.lang = 'en';
      expect(notifActionLabel(e.key), e.value);
      expect(notifActionButton(e.key), isNotEmpty);
      AppConfig.lang = 'ar';
      final ar = notifActionLabel(e.key);
      expect(ar, isNot(e.value));
      expect(RegExp(r'[؀-ۿ]').hasMatch(ar), isTrue, reason: '${e.key} has an Arabic label');
    }
    for (final v in const ['edit', 'confirm', 'vote', 'reply', 'review', 'fill', 'approve', 'view']) {
      expect(notifActionOf(v).name, v);
    }
    expect(notifActionOf('something_new'), NotifAction.none);
  });

  test('the routing decision of each module', () {
    NotifDestination d(String m, [int? id = 1]) => notifLinkDestination(NotifLink(module: m, id: id));
    expect(d('action_inbox', null), NotifDestination.actionInbox);
    expect(d('org_work'), NotifDestination.govItem);
    expect(d('org_council'), NotifDestination.govSession);
    expect(d('org_delegation'), NotifDestination.govDelegation);
    expect(d('org_form_assignment'), NotifDestination.govAssignment);
    expect(d('org_work', null), NotifDestination.module); // no id: the old list routing
    expect(d('course'), NotifDestination.module);
    expect(notifLinkDestination(const NotifLink(module: 'org_work', id: 1, stale: true)), NotifDestination.stale);
  });

  test('an attention row with a target: one → that item, several → Needs my action', () {
    final one = AttentionItem({
      'key': 'gov.work', 'tab': 'org_services', 'org_id': 7, 'count': 1,
      'action': {'type': 'org_tab', 'org_id': 7, 'tab': 'services', 'sub': 'governance'},
      'target': {'module': 'org_work', 'id': 41},
    });
    final l1 = attentionTargetLink(one)!;
    expect((l1.module, l1.id, l1.orgId), ('org_work', 41, 7));
    expect(notifLinkDestination(l1), NotifDestination.govItem);

    final many = AttentionItem({'key': 'gov.votes', 'count': 3, 'action': {'type': 'org_tab', 'target': {'module': 'action_inbox'}}});
    expect(notifLinkDestination(attentionTargetLink(many)!), NotifDestination.actionInbox);

    expect(attentionTargetLink(AttentionItem({'key': 'x', 'action': {'type': 'org_tab'}})), isNull);
  });

  test('action inbox rows parse defensively and filter', () {
    final (items, total) = ActionInboxItem.parse({
      'items': [_inboxItem(1, urgency: 3, overdue: true), _inboxItem(2, urgency: 0), {'title': 'bare'}],
      'total': 7,
    });
    expect(total, 7);
    expect(items.length, 3);
    expect(items.first.link.module, 'org_council');
    expect(items.first.link.action, NotifAction.vote);
    expect(items[2].action, NotifAction.none);
    expect(filterActionInbox(items, ActionInboxFilter.urgent).length, 1);
    expect(filterActionInbox(items, ActionInboxFilter.overdue).length, 1);
    final vote = ActionInboxItem.fromJson({..._inboxItem(1), 'kind': 'vote', 'item_id': 55, 'ref': 'GV-12', 'org_name_en': 'Engineering'});
    expect((vote.link.module, vote.link.id, vote.link.focus), ('org_council', 101, 'agenda:55'));
    expect(vote.title, startsWith('GV-12 · '));
    expect(vote.orgName, 'Engineering');
  });

  group('layout', () {
    testWidgets('ActionBanner (every action, note, fields, button)', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
            child: Column(children: [
              for (final a in NotifAction.values)
                ActionBanner(
                  action: a,
                  reason: 'The reviewer asked you to change the title and the details before it can be approved',
                  note: 'Please write the full name of the course and attach the signed form',
                  fields: const ['Title', 'Details', 'A field with a very long label for small screens'],
                  onAction: () {},
                ),
              const ActionBanner(action: NotifAction.edit, rejected: true),
            ]),
          ));
    });

    testWidgets('StaleLinkView (handled, gone)', (tester) async {
      await expectNoLayoutErrors(tester, () => StaleLinkView(reason: 'A decision was already made by the head of the department', onFallback: () {}));
      await expectNoLayoutErrors(tester, () => const StaleLinkView(gone: true));
    });

    testWidgets('NeedsMyActionList', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
            child: NeedsMyActionList(items: [for (var i = 0; i < 4; i++) ActionInboxItem.fromJson(_inboxItem(i, urgency: i, overdue: i == 3))], onOpen: (_) {}),
          ));
    });

    for (final (name, handler) in <(String, FakeHandler)>[
      ('items', (_) => {'items': [for (var i = 0; i < 5; i++) _inboxItem(i, urgency: i % 4, overdue: i == 1)], 'total': 5}),
      ('empty', (_) => {'items': [], 'total': 0}),
      ('error', (_) => const FakeResponse(500, {'detail': {'code': 'boom', 'message': 'x', 'kind': 'server', 'ref': 'req-1'}})),
    ]) {
      testWidgets('NeedsMyActionPage over FakeApi: $name', (tester) async {
        final api = FakeApi({'GET $kActionInboxPath': handler}, latency: const Duration(milliseconds: 10))..install();
        addTearDown(api.uninstall);
        await expectNoLayoutErrors(tester, () => const NeedsMyActionPage(embedded: true), frames: 6, act: (t) async {
          if (name == 'items') expect(find.byType(NeedsMyActionList), findsOneWidget);
          if (name == 'error') expect(find.byKey(const ValueKey('app_error_box')), findsOneWidget);
          if (name == 'empty') expect(find.text(AppConfig.lang == 'ar' ? 'لا شيء ينتظرك' : 'Nothing is waiting for you'), findsOneWidget);
        });
        expect(api.calls.where((c) => c.path == kActionInboxPath), isNotEmpty);
      });
    }
  });
}
