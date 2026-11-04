// Org flow overhaul, agent f2: invitations (C1), join links, joining lifecycle, effective permissions.
//   • pure: contact parsing / validation, status labels, request bodies, join / invitation link parsing,
//     effective-permission rows, every new error code has bilingual text
//   • over the fake backend: invite -> list -> cancel, /i/<token> signed out -> sign in -> accept (and the contact
//     mismatch), my invitations, /j/<CODE> signed out and in, withdraw / request again, parents, leave
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_access_joining.dart';
import 'package:flutter_education_app/features/org/org_effective_access.dart';
import 'package:flutter_education_app/features/org/org_invitations.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_education_app/features/org/org_join_scan.dart';
import 'package:flutter_education_app/features/org/org_member_pages.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

const _org = '/api/v1/org/orgs/4';
const _pub = '/api/v1/org/public';

Map<String, dynamic> _body(dynamic data) => Map<String, dynamic>.from(data is String ? jsonDecode(data) as Map : data as Map);

Map<String, dynamic> _inv(int id, String contact, {String status = 'pending', String? link, String role = 'student', String? expires}) => {
      'id': id,
      'channel': 'email',
      'contact': contact,
      'role': role,
      'dept_id': null,
      'program_id': null,
      'status': status,
      'created_at': '2026-11-01T10:00:00',
      'expires_at': expires ?? '2099-01-01T10:00:00',
      'accepted_at': null,
      'invited_by': {'id': 1, 'name': 'Dr Admin'},
      'sent_count': 1,
      'last_sent_at': '2026-11-01T10:00:00',
      'link': ?link,
    };

Map<String, dynamic> _lookup({String status = 'pending'}) => {
      'org': {'id': 4, 'name_ar': 'جامعة النيل', 'name_en': 'Nile University', 'logo_url': null},
      'role': 'teacher',
      'status': status,
      'expires_at': '2099-01-01T10:00:00',
      'contact_masked': 'a***@mail.com',
    };

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _frames(tester, 2);
  await tester.tap(f);
  await _frames(tester);
}

/// A host whose navigator records the named routes it is asked for.
Future<List<String>> _pump(WidgetTester tester, Widget page, {Size size = const Size(1000, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final pushed = <String>[];
  await tester.pumpWidget(ThemeConfigScope(
    provider: ThemeConfigProvider(api: ApiClient()),
    child: MaterialApp(
      home: page,
      onGenerateRoute: (s) {
        pushed.add(s.name ?? '');
        return MaterialPageRoute(settings: s, builder: (_) => Scaffold(body: Text('route ${s.name}')));
      },
    ),
  ));
  await _frames(tester);
  return pushed;
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
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
    SignInReturn.pending = null;
  });

  group('contacts', () {
    test('e-mails: any separator, brackets, case, repeats, junk, limit', () {
      final p = parseContacts('Ahmed <A@Mail.com>, b@x.org;\nb@x.org  not-an-email c@@d.com\t"d@e.io"', 'email');
      expect(p.valid, ['a@mail.com', 'b@x.org', 'd@e.io']);
      expect(p.invalid, ['not-an-email', 'c@@d.com']);
      expect(p.duplicates, 1);
      expect(p.overLimit, 0);

      final many = parseContacts(List.generate(maxInviteContacts + 5, (i) => 'u$i@x.org').join('\n'), 'email');
      expect(many.valid.length, maxInviteContacts);
      expect(many.overLimit, 5);
      expect(parseContacts('  \n ', 'email').isEmpty, isTrue);
    });

    test('phones: spaces, dashes, 00 prefix, Arabic digits, too short / long', () {
      expect(normalizePhone('+20 100-123 4567'), '+201001234567');
      expect(normalizePhone('00201001234567'), '+201001234567');
      expect(normalizePhone('٠١٠٠١٢٣٤٥٦٧'), '01001234567');
      expect(normalizePhone('(010) 0123 4567'), '01001234567');
      expect(normalizePhone('12345'), isNull);
      expect(normalizePhone('+1234567890123456'), isNull);
      expect(normalizePhone('abc'), isNull);
      final p = parseContacts('0100 123 4567\n+20 111 222 3333, 12\n0100 123 4567', 'phone');
      expect(p.valid, ['01001234567', '+201112223333']);
      expect(p.invalid, ['12']);
      expect(p.duplicates, 1);
    });

    test('e-mail validation', () {
      expect(normalizeEmail(' Sara@Uni.EDU.eg '), 'sara@uni.edu.eg');
      expect(normalizeEmail('sara@uni'), isNull);
      expect(normalizeEmail('@uni.com'), isNull);
    });
  });

  group('labels, models, bodies', () {
    test('status labels in both languages and the expired-by-date rule', () {
      AppConfig.lang = 'en';
      expect(inviteStatusLabel('pending'), 'Pending');
      expect(inviteStatusLabel('cancelled'), 'Cancelled');
      AppConfig.lang = 'ar';
      expect(inviteStatusLabel('accepted'), 'قُبلت');
      AppConfig.lang = 'en';
      final past = OrgInvitation.fromJson(_inv(1, 'a@x.org', expires: '2020-01-01T00:00:00'));
      expect(past.status, 'pending');
      expect(past.effectiveStatus(), 'expired');
      expect(past.canAct(), isFalse);
      expect(OrgInvitation.fromJson(_inv(2, 'a@x.org')).canAct(), isTrue);
      expect(OrgInvitation.fromJson(_inv(3, 'a@x.org', status: 'accepted')).canAct(), isFalse);
      expect(inviteSkipText('already_member'), contains('member'));
      expect(inviteSkipText('already_invited'), contains('pending'));
      expect(inviteSkipText('weird'), 'weird');
    });

    test('the request body follows the contract', () {
      final b = inviteBody(channel: 'email', contacts: ['a@x.org'], role: 'teacher', programId: 7, message: '  hi ', expiresDays: 30);
      expect(b, {'channel': 'email', 'contacts': ['a@x.org'], 'role': 'teacher', 'program_id': 7, 'message': 'hi', 'expires_days': 30});
      expect(inviteBody(channel: 'phone', contacts: ['1'], role: 'student', message: ' ').containsKey('message'), isFalse);
    });

    test('create result and the lookup parse', () {
      final r = InviteResult.fromJson({
        'created': [_inv(1, 'a@x.org', link: 'https://nextbrain.site/i/T1'), _inv(2, 'b@x.org', link: 'https://nextbrain.site/i/T2')],
        'skipped': [{'contact': 'c@x.org', 'code': 'already_member'}],
      });
      expect(r.created.length, 2);
      expect(r.skipped.single.code, 'already_member');
      expect(r.allLinks, 'a@x.org: https://nextbrain.site/i/T1\nb@x.org: https://nextbrain.site/i/T2');
      final l = InviteLookup.fromJson(_lookup());
      expect(l.orgId, 4);
      expect(l.pending, isTrue);
      expect(l.orgName, 'Nile University');
      expect(l.contactMasked, 'a***@mail.com');
    });
  });

  group('links', () {
    test('join links: parseJoinQr reads /j/<CODE>, joinLinkFor writes it, DeepLinkService is not needed for the parse', () {
      expect(parseJoinQr('https://nextbrain.site/j/abcd2345xy'), 'ABCD2345XY');
      expect(parseJoinQr('https://nextbrain.site/j/ABCD-2345-XY'), 'ABCD2345XY');
      expect(parseJoinQr('https://nextbrain.site/j/AB'), isNull);
      expect(parseJoinQr(joinLinkFor('abcd2345xy')), 'ABCD2345XY');
      expect(joinLinkFor('abcd-2345'), 'https://nextbrain.site/j/ABCD2345');
    });
  });

  group('effective permissions', () {
    final catalog = {
      'actions': [
        {'key': 'view', 'label_ar': 'عرض', 'label_en': 'View'},
        {'key': 'insert', 'label_ar': 'إضافة', 'label_en': 'Add'},
        {'key': 'delete', 'label_ar': 'حذف', 'label_en': 'Delete'},
      ],
      'groups': [
        {'key': 'people', 'label_ar': 'الأشخاص', 'label_en': 'People'},
        {'key': 'academics', 'label_ar': 'الأكاديمي', 'label_en': 'Academics'},
      ],
      'modules': [
        {'key': 'courses', 'group': 'academics', 'scope': 'dept', 'label_ar': 'الكورسات', 'label_en': 'Courses', 'actions': ['view', 'insert', 'delete']},
        {'key': 'students', 'group': 'people', 'scope': 'org', 'label_ar': 'الطلاب', 'label_en': 'Students', 'actions': ['view', 'insert']},
      ],
    };

    test('rows follow the catalog (groups, then modules) and mark full / none', () {
      final rows = effectiveAccessRows(catalog, {
        'students': {'view', 'insert'},
        'courses': {'view'},
        'ghost': {'view'}, // not in the catalog: ignored
      });
      expect(rows.map((r) => r.module), ['students', 'courses']);
      expect(rows[0].full, isTrue);
      expect(rows[0].allowed, ['View', 'Add']);
      expect(rows[1].full, isFalse);
      expect(rows[1].allowed, ['View']);
      expect(effectiveAccessRows(catalog, const {}).every((r) => r.none), isTrue);
      expect(effectiveAccessRows(catalog, {'courses': {'view'}}, deptOnly: true).map((r) => r.module), ['courses']);
    });
  });

  group('error texts', () {
    test('every code of the contract has Arabic and English text', () {
      const codes = [
        'invite_resend_too_soon', 'invite_not_found', 'invite_contact_mismatch', 'invite_not_pending', 'invite_expired',
        'already_member', 'already_invited', 'invalid_contact', 'role_cannot_join', 'child_not_found', 'org_not_found',
        'link_expired', 'confirm_name_mismatch', 'not_a_member', 'not_org_admin', 'share_target_not_allowed',
        'members_only', 'request_not_found',
      ];
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final c in codes) {
          final txt = orgCodeText(c);
          expect(txt, isNot(c), reason: '$c has no $lang text');
          expect(txt.length, greaterThan(8));
        }
      }
      AppConfig.lang = 'en';
    });
  });

  group('staff: invite, list, cancel', () {
    testWidgets('the sheet sends the parsed contacts and shows created links and skipped reasons', (tester) async {
      Map<String, dynamic>? sent;
      final fake = FakeApi({
        'GET $_org/departments': (_) => {'items': [{'id': 11, 'name_ar': 'علوم', 'name_en': 'Science'}]},
        'GET $_org/academic/programs': (_) => {'items': <dynamic>[]},
        'POST $_org/invitations': (o) {
          sent = _body(o.data);
          return FakeResponse(201, {
            'created': [_inv(1, 'a@x.org', link: 'https://nextbrain.site/i/TOKEN1')],
            'skipped': [{'contact': 'b@x.org', 'code': 'already_member'}],
          });
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const Scaffold(body: OrgInviteSheet(orgId: 4, orgName: 'Nile University')));

      // nothing typed: the send button explains instead of calling
      await _tap(tester, find.byKey(const ValueKey('org.invite.send')));
      expect(find.textContaining('Add at least one'), findsOneWidget);
      expect(fake.calls.where((c) => c.method == 'POST'), isEmpty);

      await tester.enterText(find.byType(TextField).first, 'A@x.org, b@x.org bad');
      await _frames(tester, 3);
      expect(find.text('2 valid contacts'), findsOneWidget);
      expect(find.text('1 invalid'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('org.invite.send')));

      expect(sent, {'channel': 'email', 'contacts': ['a@x.org', 'b@x.org'], 'role': 'student', 'expires_days': 14});
      expect(find.text('1 created'), findsOneWidget);
      expect(find.text('1 skipped'), findsOneWidget);
      expect(find.textContaining('Already a member'), findsOneWidget);
      expect(find.byKey(const ValueKey('org.invite.copy_all')), findsOneWidget);
      await _end(tester);
    });

    testWidgets('the list loads pending, filters by search, and cancels after a confirm', (tester) async {
      final rows = [_inv(1, 'a@x.org'), _inv(2, 'b@x.org', role: 'teacher')];
      final queries = <Map<String, dynamic>>[];
      var cancelled = 0;
      final fake = FakeApi({
        'GET $_org/invitations': (o) {
          queries.add(Map.of(o.uri.queryParameters));
          return {'items': rows, 'total': rows.length, 'page': 1, 'page_size': 20};
        },
        'POST $_org/invitations/1/cancel': (_) {
          cancelled++;
          rows.removeAt(0);
          return _inv(1, 'a@x.org', status: 'cancelled');
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgInvitationsPage(orgId: 4, orgName: 'Nile University'));

      expect(queries.first['status'], 'pending');
      expect(find.text('a@x.org'), findsOneWidget);
      expect(find.text('b@x.org'), findsOneWidget);
      expect(find.text('Teacher'), findsWidgets);

      await _tap(tester, find.byKey(const ValueKey('org.invite.cancel.1')));
      expect(find.byType(AlertDialog), findsWidgets);
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)).first);
      expect(cancelled, 1);
      expect(find.text('a@x.org'), findsNothing);
      expect(find.text('b@x.org'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('resend shows the server\'s too-soon refusal', (tester) async {
      final fake = FakeApi({
        'GET $_org/invitations': (_) => {'items': [_inv(1, 'a@x.org')], 'total': 1, 'page': 1, 'page_size': 20},
        'POST $_org/invitations/1/resend': (_) => const FakeResponse(429, {
              'detail': {'code': 'invite_resend_too_soon', 'message': 'ar', 'message_en': 'wait'}
            }),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgInvitationsPage(orgId: 4));
      await _tap(tester, find.byKey(const ValueKey('org.invite.resend.1')));
      expect(fake.calls.where((c) => c.key == 'POST $_org/invitations/1/resend'), hasLength(1));
      expect(find.text('a@x.org'), findsOneWidget, reason: 'the row stays');
      await _end(tester);
    });

    testWidgets('the whole feature hides under its kill switch', (tester) async {
      AppConfig.disableList = [invitationsFeatureKey];
      final fake = FakeApi({}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const Scaffold(body: OrgMyInvitationsCard()));
      expect(find.byKey(const ValueKey('org.my_invitations')), findsNothing);
      await _end(tester);
    });
  });

  group('invitee: /i/<token>', () {
    testWidgets('signed out: sign in remembers the page, then signed in accepts', (tester) async {
      final fake = FakeApi({
        'GET $_pub/invitations/TOK12345': (_) => _lookup(),
        'POST $_pub/invitations/TOK12345/accept': (_) => {'org_id': 4, 'member_id': 9, 'status': 'active'},
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final pushed = await _pump(tester, const OrgInviteePage(token: 'TOK12345', signedIn: false));
      expect(find.text('Nile University'), findsOneWidget);
      expect(find.textContaining('invited to join as Teacher'), findsOneWidget);
      expect(find.text('a***@mail.com'), findsNothing); // inside "Sent to …"
      expect(find.textContaining('a***@mail.com'), findsOneWidget);
      expect(find.byKey(const ValueKey('org.invitee.accept')), findsNothing);

      await _tap(tester, find.byKey(const ValueKey('org.invitee.sign_in')));
      expect(SignInReturn.pending, '/i/TOK12345');
      expect(pushed, contains('/login'));

      await _end(tester);
      // the first signed-in page opens it again (D-170): same token, now signed in
      var joined = 0;
      await _pump(tester, OrgInviteePage(token: 'TOK12345', signedIn: true, onAccepted: (id) => joined = id));
      await _tap(tester, find.byKey(const ValueKey('org.invitee.accept')));
      expect(fake.calls.where((c) => c.key == 'POST $_pub/invitations/TOK12345/accept'), hasLength(1));
      expect(joined, 4);
      expect(find.textContaining('now a member of "Nile University"'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('a contact mismatch is explained, nothing is joined', (tester) async {
      final fake = FakeApi({
        'GET $_pub/invitations/TOK12345': (_) => _lookup(),
        'POST $_pub/invitations/TOK12345/accept': (_) => const FakeResponse(403, {
              'detail': {'code': 'invite_contact_mismatch', 'message': 'ar', 'message_en': 'no'}
            }),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgInviteePage(token: 'TOK12345', signedIn: true, myContact: 'me@other.org'));
      await _tap(tester, find.byKey(const ValueKey('org.invitee.accept')));
      expect(find.textContaining('sent to a***@mail.com'), findsOneWidget);
      expect(find.textContaining('signed in as me@other.org'), findsOneWidget);
      expect(find.byKey(const ValueKey('org.invitee.accept')), findsOneWidget, reason: 'can still switch account and retry');
      await _end(tester);
    });

    testWidgets('an unknown or expired link says so and offers a retry', (tester) async {
      final fake = FakeApi({
        'GET $_pub/invitations/NOPE': (_) => const FakeResponse(404, {
              'detail': {'code': 'invite_not_found', 'message': 'ar', 'message_en': 'x'}
            }),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgInviteePage(token: 'NOPE', signedIn: true));
      expect(find.textContaining('does not exist'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('my invitations: accept removes the card and reports it', (tester) async {
      var accepted = 0;
      final fake = FakeApi({
        'GET $_pub/me/invitations': (_) => {
              'items': [
                {'id': 5, 'token_hint': 'ab12', 'role': 'student', 'expires_at': '2099-01-01T00:00:00', 'org': {'id': 4, 'name_ar': 'جامعة النيل', 'name_en': 'Nile University'}}
              ]
            },
        'POST $_pub/me/invitations/5/accept': (_) => {'org_id': 4, 'member_id': 1, 'status': 'active'},
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, Scaffold(body: OrgMyInvitationsCard(onChanged: (i) => accepted = i.orgId)));
      expect(find.text('Nile University'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('org.my_invitation.accept.5')));
      expect(accepted, 4);
      expect(find.byKey(const ValueKey('org.my_invitations')), findsNothing);
      await _end(tester);
    });
  });

  group('join link and joining lifecycle', () {
    Map<String, FakeHandler> joinRoutes({List<Map<String, dynamic>> orgs = const []}) => {
          'GET $_pub/search': (_) => {'items': <dynamic>[]},
          'GET $_pub/me/join-status': (_) => {'organizations': orgs, 'units': <dynamic>[]},
        };

    testWidgets('/j/<CODE> signed out keeps the code through the sign-in', (tester) async {
      final fake = FakeApi(joinRoutes(), latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      final pushed = await _pump(tester, const OrgJoinLinkPage(code: 'abcd-2345xy', signedIn: false));
      expect(find.text('ABCD2345XY'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('org.join_link.register')));
      expect(SignInReturn.pending, '/j/ABCD2345XY');
      expect(pushed, contains('/register'));
      await _end(tester);
    });

    testWidgets('/j/<CODE> signed in opens the join page with the code filled, not sent', (tester) async {
      final fake = FakeApi(joinRoutes(), latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgJoinLinkPage(code: 'abcd2345xy', signedIn: true));
      expect(find.byWidgetPredicate((w) => w is TextField && w.controller?.text == 'ABCD2345XY'), findsOneWidget);
      expect(fake.calls.where((c) => c.method == 'POST'), isEmpty);
      await _end(tester);
    });

    testWidgets('a pending organization request can be withdrawn; a rejected one asked again', (tester) async {
      final posted = <String>[];
      var asked = <String, dynamic>{};
      final fake = FakeApi({
        ...joinRoutes(orgs: [
          {'id': 1, 'status': 'pending', 'role': 'student', 'created_at': '2026-11-01T10:00:00', 'organization': {'id': 9, 'name_ar': 'أ', 'name_en': 'Pending Uni'}},
          {'id': 2, 'status': 'rejected', 'role': 'student', 'created_at': '2026-11-01T10:00:00', 'organization': {'id': 8, 'name_ar': 'ب', 'name_en': 'Rejected Uni'}},
        ]),
        'POST $_pub/9/join-request/cancel': (_) {
          posted.add('cancel9');
          return {'cancelled': true};
        },
        'POST $_pub/join': (o) {
          asked = _body(o.data);
          posted.add('join');
          return {'status': 'pending', 'organization': {'id': 8, 'name_en': 'Rejected Uni'}};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgJoinPage(isParent: false, scannerAvailable: true));
      expect(find.text('Pending Uni'), findsOneWidget);

      await _tap(tester, find.byTooltip('Cancel request'));
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)).first);
      expect(posted, ['cancel9']);

      await _tap(tester, find.text('Request again'));
      expect(posted, ['cancel9', 'join']);
      expect(asked, {'org_id': 8});
      await _end(tester);
    });

    testWidgets('a parent is told why and how, before typing a code', (tester) async {
      final fake = FakeApi(joinRoutes(), latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgJoinPage(isParent: true));
      expect(find.textContaining('follow your child'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await _end(tester);
    });

    testWidgets('without a camera scanner (web) the page explains and keeps the manual field', (tester) async {
      final fake = FakeApi(joinRoutes(), latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgJoinPage(isParent: false, scannerAvailable: false));
      expect(find.byKey(const ValueKey('org.join.no_scan')), findsOneWidget);
      expect(find.textContaining('Scanning a QR code works in the phone app'), findsOneWidget);
      expect(find.text('Scan QR'), findsNothing);
      await _end(tester);
      await _pump(tester, const OrgJoinPage(isParent: false, scannerAvailable: true));
      expect(find.byKey(const ValueKey('org.join.no_scan')), findsNothing);
      expect(find.text('Scan QR'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('leaving is a labelled action with a consequences text', (tester) async {
      var left = 0;
      final fake = FakeApi({
        'GET $_pub/mine': (_) => {
              'items': [
                {'membership_id': 3, 'role': 'student', 'status': 'active', 'organization': {'id': 4, 'name_ar': 'جامعة', 'name_en': 'Nile University', 'type': 'university'}}
              ]
            },
        'GET $_pub/me/invitations': (_) => {'items': <dynamic>[]},
        'DELETE $_pub/4/leave': (_) {
          left++;
          return {'left': true};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const OrgMembershipScreen());
      expect(find.text('Leave organization'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('org.leave.4')));
      expect(find.textContaining('lose access'), findsOneWidget);
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)).first);
      expect(left, 1);
      await _end(tester);
    });
  });
}
