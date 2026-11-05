// Org flow overhaul, agent f7: the C7 review findings on the front.
//   4   a tap naming an invitation that is not pending opens My organizations (never silent)
//   9   the live event rules: only `org_invitation` with an id fetches; an attention change goes through the count
//   10  an answer that arrives after another person signed in is dropped
//   11  a tap while busy / gated is queued once and handled when it opens
//   12  the 202 notice says positions are set after acceptance, only when some were picked
//   13  another account on the invitation link reads "different account"
//   17  OrgMembersProvider.add treats a 202 invited answer as invited
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_invitation_prompt.dart';
import 'package:flutter_education_app/features/org/org_invitations.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_education_app/features/org/org_member_form.dart' show invitedNoticeText;
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _mine = '/api/v1/org/public/me/invitations';

Map<String, dynamic> _row(int id, String org) => {
      'id': id,
      'org': {'id': 40 + id, 'name_ar': 'مؤسسة $org', 'name_en': org, 'logo_url': null},
      'role': 'student',
      'member_role': 'student',
      'source': 'manual',
      'message': '',
      'created_at': '2026-11-01T10:00:00',
      'expires_at': '2099-01-01T10:00:00',
      'invited_by_name': 'Dr Admin',
      'status': 'pending',
    };

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

OrgInvitationPrompt _prompt(GlobalKey<NavigatorState> key, {bool Function()? gate, int? Function()? uid, Future<void> Function()? gone}) =>
    OrgInvitationPrompt.test(
      countProbe: () => 1,
      gate: gate ?? () => true,
      store: _MemStore(),
      userId: uid ?? () => 7,
      onGone: gone ?? () async {},
      dialog: (ctx, i) => showOrgInvitationDialog(ctx, i, afterAccepted: (_) async {}, confirmReject: (_) async => true, openOrg: (_, _) async {}),
    )..attach(key, null);

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
    test('9: only the org_invitation event with an id fetches; attention changes count; others are ignored', () {
      expect(invitationEventAction('org_invitation', null, {'invitation_id': 5}).kind, InviteEventKind.show);
      expect(invitationEventAction('org_invitation', null, {'invitation_id': 5}).id, 5);
      expect(invitationEventAction('org_invitation', null, {}).kind, InviteEventKind.count);
      // the attention change after my own accept / decline carries related_id: never a fetch by id
      expect(invitationEventAction('attention_changed', 'org_invitation', {'related_id': 3}).kind, InviteEventKind.count);
      expect(invitationEventAction('attention_changed', 'complaint', {'related_id': 3}).kind, InviteEventKind.none);
    });

    test('12: the notice mentions positions only when some were picked', () {
      expect(invitedNoticeText(), isNot(contains('head-of-department')));
      expect(invitedNoticeText(positionsPending: true), contains('after they accept'));
      AppConfig.lang = 'ar';
      expect(invitedNoticeText(positionsPending: true), isNot(invitedNoticeText()));
    });

    test('the new error codes read in both languages', () {
      for (final code in ['invite_no_longer_valid', 'invitations_disabled', 'membership_ended', 'invite_not_pending']) {
        AppConfig.lang = 'en';
        final en = orgCodeText(code);
        AppConfig.lang = 'ar';
        final ar = orgCodeText(code);
        expect(en, isNot(code), reason: code);
        expect(ar, isNot(en), reason: code);
      }
      AppConfig.lang = 'en';
      expect(orgCodeText('invite_no_longer_valid'), contains('no longer valid'));
      expect(orgCodeText('invitations_disabled'), contains('join code'));
    });
  });

  group('the prompt', () {
    testWidgets('4: a tap for an id that is not pending says so and goes to My organizations; a pending id shows', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(7, 'Nile')]}}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      var gone = 0;
      final p = _prompt(key, gone: () async => gone++);
      final run = p.showFor(99); // an org id, a deleted invitation ...
      await _frames(tester);
      await run;
      expect(gone, 1);
      expect(find.byType(OrgInvitationPromptBody), findsNothing);

      final run2 = p.showFor(7);
      await _frames(tester);
      expect(find.text('Nile'), findsOneWidget);
      expect(gone, 1);
      await _tapKey(tester, 'org.invite_prompt.later');
      await run2;
    });

    testWidgets('9: a count of 0 right after my own decision costs no request', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(7, 'Nile')]}}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final p = OrgInvitationPrompt.test(countProbe: () => 0, gate: () => true, store: _MemStore(), userId: () => 7, onGone: () async {})..attach(key, null);
      expect(invitationEventAction('attention_changed', 'org_invitation', {}).kind, InviteEventKind.count);
      await p.onAttention();
      expect(fake.calls, isEmpty);
      expect(p.fetchCount, 0);
    });

    testWidgets('10: an answer that arrives after another person signed in is dropped', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(7, 'Nile')]}}, latency: const Duration(milliseconds: 300))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      var uid = 1;
      final p = _prompt(key, uid: () => uid);
      final run = p.showFor(null);
      await tester.pump(const Duration(milliseconds: 50));
      uid = 2; // B signed in while A's request was in flight
      await _frames(tester, 8);
      await run;
      expect(find.byType(OrgInvitationPromptBody), findsNothing);
      expect(find.text('Nile'), findsNothing);
    });

    testWidgets('11: a tap while the gate is shut is queued, then handled when it opens; sign-out drops it', (tester) async {
      final fake = FakeApi({'GET $_mine': (_) => {'items': [_row(7, 'Nile')]}}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      var open = false;
      final p = _prompt(key, gate: () => open);
      await p.showFor(7);
      expect(fake.calls, isEmpty);
      await p.drainQueued();
      expect(fake.calls, isEmpty, reason: 'still gated');
      open = true;
      final run = p.drainQueued();
      await _frames(tester);
      expect(find.text('Nile'), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.later');
      await run;

      // queued, then the person signs out: nothing is handled later
      open = false;
      await p.showFor(7);
      p.clearQueued();
      open = true;
      final before = fake.calls.length;
      await p.drainQueued();
      expect(fake.calls.length, before);
    });

    testWidgets('11: a tap while the dialog is busy is queued and shown after it', (tester) async {
      final fake = FakeApi({
        'GET $_mine': (_) => {'items': [_row(7, 'Nile'), _row(8, 'Delta')]},
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final key = await _pumpApp(tester);
      final p = _prompt(key);
      final first = p.showFor(7);
      await _frames(tester);
      expect(find.text('Nile'), findsOneWidget);
      await p.showFor(8); // busy: queued, no second request
      expect(fake.calls.where((c) => c.method == 'GET').length, 1);
      await _tapKey(tester, 'org.invite_prompt.later');
      await first;
      await _frames(tester);
      expect(find.text('Delta'), findsOneWidget);
      await _tapKey(tester, 'org.invite_prompt.later');
      p.clearQueued();
    });
  });

  group('13: the invitee page', () {
    Widget view({bool other = false}) => InviteeView(
          lookup: InviteLookup(orgId: 1, nameAr: 'م', nameEn: 'Nile', role: 'student', status: 'pending', expiresAt: DateTime.utc(2099)),
          signedIn: true,
          mismatchMasked: '',
          otherAccount: other,
          myContact: 'me@x.io',
        );

    testWidgets('another account reads "different account", not the verified contact text', (tester) async {
      await tester.pumpWidget(ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: MaterialApp(home: Scaffold(body: view(other: true)))));
      await _frames(tester, 2);
      expect(find.textContaining('different account'), findsOneWidget);
      expect(find.textContaining('verified'), findsNothing);
    });

    testWidgets('no overflow', (tester) async {
      await expectNoLayoutErrors(tester, () => view(other: true));
    });
  });

  group('17: OrgMembersProvider.add', () {
    test('a 202 invited answer is "invited": no refresh, answer handed back', () async {
      final fake = FakeApi({
        'POST /api/v1/org/orgs/5/members': (_) => const FakeResponse(202, {'status': 'invited', 'invitation': {'id': 3}}),
        'GET /api/v1/org/orgs/5/members': (_) => {'items': [], 'total': 0},
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      final s = OrgSession()..currentId = 5;
      final prov = OrgMembersProvider(s, 'student');
      final r = await prov.add({'email': 'a@b.c', 'role': 'student'});
      expect(r?['status'], 'invited');
      expect(fake.calls.where((c) => c.method == 'GET'), isEmpty);
    });

    test('a normal add still refreshes the list', () async {
      final fake = FakeApi({
        'POST /api/v1/org/orgs/5/members': (_) => const FakeResponse(201, {'id': 9, 'user': {}}),
        'GET /api/v1/org/orgs/5/members': (_) => {'items': [], 'total': 0},
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      final s = OrgSession()..currentId = 5;
      final prov = OrgMembersProvider(s, 'student');
      final r = await prov.add({'email': 'a@b.c', 'role': 'student'});
      expect(r?['id'], 9);
      expect(fake.calls.where((c) => c.method == 'GET'), isNotEmpty);
    });
  });
}
