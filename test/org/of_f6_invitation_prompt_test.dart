// Org flow overhaul, agent f6: consent for existing accounts (C7) - the invitation dialog.
//   • pure: the gate, which invitation is shown, the "Later" memory, the 202 answer of the add-member form, texts
//   • over the fake backend: no request while the attention count is 0; a count above 0 reads the list once and shows
//     the newest; Accept / Reject (confirm first) / Later (snoozed, not shown again); several in sequence; a push tap
//     shows a snoozed one; signed out never fetches
//   • layout: the dialog content at 320x640 and 1400x900, ar / en, textScaler 1.3
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_invitation_prompt.dart';
import 'package:flutter_education_app/features/org/org_invitations.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_education_app/features/org/org_member_form.dart' show invitedNoticeText, isInvitedAnswer;
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _mine = '/api/v1/org/public/me/invitations';

Map<String, dynamic> _row(int id, String org, {String created = '2026-11-01T10:00:00', String? expires, String memberRole = 'student', String message = '', String by = 'Dr Admin'}) => {
      'id': id,
      'org': {'id': 40 + id, 'name_ar': 'مؤسسة $org', 'name_en': org, 'logo_url': null},
      'role': 'student',
      'member_role': memberRole,
      'source': 'manual',
      'message': message,
      'created_at': created,
      'expires_at': expires ?? '2099-01-01T10:00:00',
      'invited_by_name': by,
      'status': 'pending',
    };

MyInvitation _inv(int id, {DateTime? created, DateTime? expires}) => MyInvitation(
      id: id,
      orgId: 40 + id,
      orgName: 'Org $id',
      role: 'student',
      createdAt: created ?? DateTime.utc(2026, 11, 1, 10),
      expiresAt: expires ?? DateTime.utc(2099),
    );

class _MemStore implements InviteSnoozeStore {
  final data = <String, List<String>>{};
  @override
  Future<List<String>?> read(String key) async => data[key];
  @override
  Future<void> write(String key, List<String> value) async => data[key] = value;
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await _frames(tester, 2);
  await tester.tap(f);
  await _frames(tester);
}

/// A navigator the prompt can show its dialog over.
Future<GlobalKey<NavigatorState>> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ThemeConfigScope(
    provider: ThemeConfigProvider(api: ApiClient()),
    child: MaterialApp(navigatorKey: key, home: const Scaffold(body: Text('home'))),
  ));
  await _frames(tester, 2);
  return key;
}

OrgInvitationPrompt _prompt(GlobalKey<NavigatorState> key, _MemStore store, int Function() count, {bool allowed = true}) {
  final p = OrgInvitationPrompt.test(
    countProbe: count,
    gate: () => allowed,
    store: store,
    dialog: (ctx, i) => showOrgInvitationDialog(ctx, i, afterAccepted: (_) async {}, confirmReject: (_) async => true, openOrg: (_, _) async {}),
  )..attach(key, null);
  return p;
}

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

  group('pure rules', () {
    bool due({bool signedIn = true, String? role = 'student', bool orgs = true, bool off = false, bool live = false, bool viewAs = false, bool online = true, String? route = '/dashboard'}) =>
        invitationPromptDue(signedIn: signedIn, role: role, orgsEnabled: orgs, featureOff: off, liveRoomOpen: live, viewAs: viewAs, online: online, routeName: route);

    test('the gate: signed out, parent, orgs off, kill switch, live room, view-as, offline, auth routes, link pages', () {
      expect(due(), isTrue);
      expect(due(role: 'teacher'), isTrue);
      expect(due(signedIn: false), isFalse);
      expect(due(role: 'parent'), isFalse);
      expect(due(orgs: false), isFalse);
      expect(due(off: true), isFalse);
      expect(due(live: true), isFalse);
      expect(due(viewAs: true), isFalse);
      expect(due(online: false), isFalse);
      for (final r in ['/login', '/register', '/onboarding', '/otp', '/forgot-password', '/', '/i/TOKEN', '/live/abc']) {
        expect(due(route: r), isFalse, reason: r);
      }
      expect(due(route: null), isTrue);
      expect(due(route: '/org_dashboard'), isTrue);
    });

    test('the newest pending invitation that is not snoozed, expired or handled', () {
      final now = DateTime.utc(2026, 11, 5, 12);
      final a = _inv(1, created: DateTime.utc(2026, 11, 1)), b = _inv(2, created: DateTime.utc(2026, 11, 3)), c = _inv(3, created: DateTime.utc(2026, 11, 2));
      expect(pickInvitationToShow([a, b, c], InviteSnoozes(), now)?.id, 2);
      final sn = InviteSnoozes()..snooze(2, now.subtract(const Duration(hours: 3)));
      expect(pickInvitationToShow([a, b, c], sn, now)?.id, 3);
      expect(pickInvitationToShow([a, b, c], sn, now, skip: {3})?.id, 1);
      expect(pickInvitationToShow([a, b, c], sn, now, skip: {3, 1}), isNull);
      // the snooze ends after 24 hours
      expect(pickInvitationToShow([a, b, c], sn, now.add(const Duration(hours: 20)))?.id, 3);
      expect(pickInvitationToShow([a, b, c], sn, now.add(const Duration(hours: 22)))?.id, 2);
      // a push tap names one: shown even when snoozed; an unknown id shows nothing
      expect(pickInvitationToShow([a, b, c], sn, now, onlyId: 2)?.id, 2);
      expect(pickInvitationToShow([a, b, c], sn, now, onlyId: 99), isNull);
      // expired is never offered
      expect(pickInvitationToShow([_inv(5, expires: DateTime.utc(2026, 11, 4))], InviteSnoozes(), now), isNull);
    });

    test('the Later memory survives encoding and forgets old entries', () {
      final now = DateTime.utc(2026, 11, 5, 12);
      final s = InviteSnoozes()
        ..snooze(1, now.subtract(const Duration(hours: 2)))
        ..snooze(2, now.subtract(const Duration(hours: 30)));
      final back = InviteSnoozes.decode(s.encode())..prune(now);
      expect(back.isSnoozed(1, now), isTrue);
      expect(back.isSnoozed(2, now), isFalse);
      expect(back.encode().length, 1);
      expect(InviteSnoozes.decode(['junk', '3:x', '4:5']).encode(), ['4:5']);
      expect(InviteSnoozes.decode(null).encode(), isEmpty);
    });

    test('the invitation row reads the new keys; an older server answers without them', () {
      final full = MyInvitation.fromJson(_row(1, 'Nile', memberRole: 'teacher_assistant', message: ' Welcome ', by: ' Dr Admin '));
      expect(full.memberRole, 'teacher_assistant');
      expect(full.roleLabel, 'Teaching assistant');
      expect(full.message, 'Welcome');
      expect(full.invitedByName, 'Dr Admin');
      expect(full.source, 'manual');
      expect(full.createdAt, isNotNull);
      final old = MyInvitation.fromJson({'id': 2, 'org': {'id': 3, 'name_en': 'X'}, 'role': 'teacher'});
      expect(old.memberRole, '');
      expect(old.roleLabel, 'Teacher');
      expect(old.source, 'invite');
      expect(OrgInvitation.fromJson({'id': 1, 'source': 'excel', 'member_role': 'student'}).source, 'excel');
      expect(inviteSourceLabel('excel'), contains('Excel'));
      expect(inviteSourceLabel('manual'), 'Added by an admin');
    });

    test('add member: the 202 invited answer is told apart and has its notice; the new codes read in both languages', () {
      expect(isInvitedAnswer({'status': 'invited', 'invitation': {'id': 1}}), isTrue);
      expect(isInvitedAnswer({'id': 5, 'user': {}, 'generated_password': 'x'}), isFalse);
      expect(invitedNoticeText(), 'Invitation sent — they join once they accept');
      for (final code in ['already_invited', 'invite_declined_recently', 'existing_account_invite_first', 'already_member_other_role', 'role_mismatch', 'membership_ended', 'invite_not_pending', 'org_unavailable']) {
        AppConfig.lang = 'en';
        final en = orgCodeText(code);
        AppConfig.lang = 'ar';
        final ar = orgCodeText(code);
        expect(en, isNot(code), reason: code);
        expect(ar, isNot(code), reason: code);
        expect(ar, isNot(en), reason: code);
      }
      expect(invitedNoticeText(), contains('دعوة'));
    });
  });

  group('the prompt over the fake backend', () {
    testWidgets('a count of 0 costs no request, even when asked many times', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(1, 'Nile')]}}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final p = _prompt(key, _MemStore(), () => 0);
      for (var i = 0; i < 5; i++) {
        await p.onAttention();
      }
      expect(fake.calls, isEmpty);
      expect(p.fetchCount, 0);
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
    });

    testWidgets('signed out (the real gate, no auth attached) never reads the list', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(1, 'Nile')]}}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final p = OrgInvitationPrompt.test(countProbe: () => 1, store: _MemStore())..attach(key, null);
      await p.onAttention();
      expect(fake.calls, isEmpty);
      // the gate says no (parent / orgs off ...): same
      final blocked = _prompt(key, _MemStore(), () => 1, allowed: false);
      await blocked.onAttention();
      await blocked.showFor(1);
      expect(fake.calls, isEmpty);
    });

    testWidgets('a count of 1 reads the list ONCE and shows the dialog; Accept answers and offers to open', (tester) async {
      var accepted = 0;
      final fake = FakeApi({
        'GET $_mine': (_) => {'items': [_row(7, 'Nile', message: 'Welcome aboard', memberRole: 'teacher')]},
        'POST $_mine/7/accept': (_) {
          accepted++;
          return {'status': 'accepted'};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final p = _prompt(key, _MemStore(), () => 1);
      final run = p.onAttention();
      await _frames(tester);
      expect(fake.calls.where((c) => c.method == 'GET').length, 1);
      expect(find.text('Nile'), findsOneWidget);
      expect(find.textContaining('as Teacher'), findsOneWidget);
      expect(find.text('Welcome aboard'), findsOneWidget);
      expect(find.textContaining('Dr Admin'), findsOneWidget);
      expect(find.byKey(const ValueKey('org.invite_prompt.accept')), findsOneWidget);

      await _tapKey(tester, 'org.invite_prompt.accept');
      expect(accepted, 1);
      expect(find.byKey(const ValueKey('org.invite_prompt.open')), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.done');
      await run;
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
      // a second nudge with the same count right after: no second read
      await p.onAttention();
      expect(fake.calls.where((c) => c.method == 'GET').length, 1);
    });

    testWidgets('Reject asks first, then declines and closes', (tester) async {
      var declined = 0;
      final fake = FakeApi({
        'GET $_mine': (_) => {'items': [_row(7, 'Nile')]},
        'POST $_mine/7/decline': (_) {
          declined++;
          return {'status': 'declined'};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      var asked = 0;
      final p = OrgInvitationPrompt.test(
        countProbe: () => 1,
        gate: () => true,
        store: _MemStore(),
        dialog: (ctx, i) => showOrgInvitationDialog(ctx, i, confirmReject: (_) async {
          asked++;
          return asked > 1; // the first time the person says "no"
        }),
      )..attach(key, null);
      final run = p.onAttention();
      await _frames(tester);
      await _tapKey(tester, 'org.invite_prompt.reject');
      expect(asked, 1);
      expect(declined, 0, reason: 'a "no" at the confirm sends nothing');
      expect(find.byType(OrgInvitationPromptBody), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.reject');
      expect(declined, 1);
      await run;
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
    });

    testWidgets('Later snoozes that invitation: not shown again this session, nor after a restart for 24 h', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(7, 'Nile')]}}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final store = _MemStore();
      final p = _prompt(key, store, () => 1);
      final run = p.onAttention();
      await _frames(tester);
      await _tapKey(tester, 'org.invite_prompt.later');
      await run;
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
      expect(store.data.values.single.single, startsWith('7:'));

      final reads = fake.calls.length;
      await p.onAttention();
      await _frames(tester, 3);
      expect(fake.calls.length, reads, reason: 'Later stops the prompt for this session');
      expect(find.byType(OrgInvitationPromptBody), findsNothing);

      // an app restart (a new prompt, same device storage): it reads the list but the snoozed one stays quiet
      final again = _prompt(key, store, () => 1);
      final read = again.onAttention(); // the fake backend answers on the test clock: pump while it runs
      await _frames(tester, 5);
      await read;
      expect(again.fetchCount, 1);
      expect(find.byType(OrgInvitationPromptBody), findsNothing);

      // ... unless a push names it
      final run2 = again.showFor(7);
      await _frames(tester);
      expect(find.text('Nile'), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.later');
      await run2;
    });

    testWidgets('several pending: after one is handled the next one shows; Later on the second ends the line', (tester) async {
      final fake = FakeApi({
        'GET $_mine': (_) => {
              'items': [
                _row(1, 'Alpha', created: '2026-11-01T10:00:00'),
                _row(2, 'Beta', created: '2026-11-03T10:00:00'),
                _row(3, 'Gamma', created: '2026-11-02T10:00:00'),
              ]
            },
        'POST $_mine/2/decline': (_) => {'status': 'declined'},
        'POST $_mine/3/accept': (_) => {'status': 'accepted'},
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final store = _MemStore();
      final p = _prompt(key, store, () => 3);
      final run = p.onAttention();
      await _frames(tester);
      expect(find.text('Beta'), findsOneWidget, reason: 'the newest first');
      await _tapKey(tester, 'org.invite_prompt.reject');
      expect(find.text('Gamma'), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.accept');
      await _tapKey(tester, 'org.invite_prompt.done');
      expect(find.text('Alpha'), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.later');
      await run;
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
      expect(fake.calls.where((c) => c.method == 'GET').length, 1, reason: 'one list read for the whole line');
    });

    testWidgets('an answer that fails shows the server text; an expired invitation can only be closed', (tester) async {
      final fake = FakeApi({
        'GET $_mine': (_) => {'items': [_row(7, 'Nile')]},
        'POST $_mine/7/accept': (_) => const FakeResponse(409, {'detail': {'code': 'invite_expired', 'message': 'x'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final p = _prompt(key, _MemStore(), () => 1);
      final run = p.onAttention();
      await _frames(tester);
      await _tapKey(tester, 'org.invite_prompt.accept');
      expect(find.textContaining('has expired'), findsOneWidget);
      expect(find.byKey(const ValueKey('org.invite_prompt.accept')), findsNothing);
      await _tapKey(tester, 'org.invite_prompt.close');
      await run;
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
    });
  });

  group('layout', () {
    Widget view({String message = '', bool accepted = false, bool gone = false, String? error, String? busy, String name = 'Nile University of Science and Technology for Advanced Studies'}) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: OrgInvitationPromptView(
            invitation: MyInvitation(
              id: 1,
              orgId: 2,
              orgName: name,
              role: 'student',
              memberRole: 'teacher_assistant',
              message: message,
              invitedByName: 'Dr Mohamed Abdelrahman El-Sayed',
              expiresAt: DateTime.utc(2099),
            ),
            accepted: accepted,
            gone: gone,
            error: error,
            busy: busy,
            onAccept: () {},
            onReject: () {},
            onLater: () {},
            onOpen: () {},
            onClose: () {},
          ),
        );

    testWidgets('the question, with a long message', (tester) async {
      await expectNoLayoutErrors(tester, () => view(message: List.filled(12, 'Please join our organization so we can start the term together.').join(' ')));
    });
    testWidgets('busy, with an error', (tester) async {
      await expectNoLayoutErrors(tester, () => view(busy: 'accept', error: 'This organization is not available right now'));
    });
    testWidgets('accepted and gone', (tester) async {
      await expectNoLayoutErrors(tester, () => view(accepted: true));
      await expectNoLayoutErrors(tester, () => view(gone: true, error: 'This invitation has expired — ask the organization for a new one'));
    });
    testWidgets('the real dialog around it', (tester) async {
      final fake = FakeApi({}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      await expectNoLayoutErrors(tester, () => Builder(builder: (c) => TextButton(onPressed: () => showOrgInvitationDialog(c, _inv(1)), child: const Text('go'))),
          act: (t) async {
        await t.tap(find.text('go'));
      });
    });
    testWidgets('the admin list row shows where an invitation came from', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => OrgInvitationCard(
              invitation: OrgInvitation.fromJson({
                'id': 1, 'channel': 'email', 'contact': 'a.very.long.address@some-long-domain-name.example.org', 'role': 'student', 'status': 'pending',
                'source': 'excel', 'member_role': 'teacher_assistant', 'expires_at': '2099-01-01T10:00:00',
              })));
    });
  });
}
