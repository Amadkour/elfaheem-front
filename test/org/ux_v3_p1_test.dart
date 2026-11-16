// UX v3 phase 1: actionable errors. ApiException parses the coded shape and the 422 `error` object (and stays
// tolerant of older servers), FieldErrors maps server fields onto a form, AppErrorBox draws every kind without a
// layout error, the roster's "add as member" fix builds the right body, orgErrorText appends the server's fix.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_errors.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/org_institution_wizard.dart' show headErrorIdsOf;
import 'package:flutter_education_app/features/org/org_v3.dart' show orgErrorText;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

ApiException res(int status, dynamic data, {String? rid}) => ApiException.fromResponse(Response(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: status,
      data: data,
      headers: Headers.fromMap({if (rid != null) 'x-request-id': [rid]}),
    ));

Map<String, dynamic> secretaryNotMember() => {
      'detail': {
        'code': 'secretary_not_member',
        'message': 'الأمين ليس عضواً',
        'message_en': 'The secretary is not a member',
        'kind': 'validation',
        'field': 'secretary_user_id',
        'fix': 'أضفه إلى الأعضاء',
        'fix_en': 'Add them to the members',
        'fix_action': 'add_member',
        'user_id': 42,
      }
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('ApiException', () {
    test('coded detail: kind, field, fix, fix_action, both languages', () {
      final e = res(422, secretaryNotMember());
      expect(e.code, 'secretary_not_member');
      expect(e.kind, ApiErrorKind.validation);
      expect(e.message, 'The secretary is not a member');
      expect(e.field, 'secretary_user_id');
      expect(e.fields, [('secretary_user_id', 'The secretary is not a member')]);
      expect(e.fix, 'Add them to the members');
      expect(e.fixAction, 'add_member');
      expect(e.detail['user_id'], 42);
      AppConfig.lang = 'ar';
      final a = res(422, secretaryNotMember());
      expect(a.message, 'الأمين ليس عضواً');
      expect(a.fix, 'أضفه إلى الأعضاء');
    });

    test('422 with pydantic detail + the top-level error object', () {
      final e = res(422, {
        'detail': [
          {'loc': ['body', 'name_ar'], 'msg': 'field required', 'type': 'missing'}
        ],
        'error': {
          'code': 'validation',
          'kind': 'validation',
          'message': 'بيانات غير صالحة',
          'message_en': 'Some fields are invalid',
          'fields': [
            {'field': 'name_ar', 'message': 'الاسم مطلوب', 'message_en': 'The name is required'},
            {'field': 'head_user_id', 'message': 'رئيس غير صالح', 'message_en': 'Not a valid head'},
          ],
        },
      });
      expect(e.kind, ApiErrorKind.validation);
      expect(e.message, 'Some fields are invalid');
      expect(e.fields.length, 2);
      expect(e.fields.first, ('name_ar', 'The name is required'));
      expect(e.field, 'name_ar');
    });

    test('older server: no kind (derived from the status), pydantic list only', () {
      final e = res(422, {
        'detail': [
          {'loc': ['body', 'email'], 'msg': 'not an email'}
        ]
      });
      expect(e.kind, ApiErrorKind.validation);
      expect(e.fields, [('email', 'not an email')]);
      expect(e.fix, isNull);
      expect(res(403, {'detail': {'code': 'not_staff', 'message': 'x'}}).kind, ApiErrorKind.permission);
      expect(res(409, {'detail': 'busy'}).kind, ApiErrorKind.conflict);
      expect(res(404, {'detail': 'Not Found'}).kind, ApiErrorKind.notFound);
      expect(res(429, null).kind, ApiErrorKind.rateLimit);
      expect(res(418, null).kind, ApiErrorKind.unknown);
    });

    test('network: no response', () {
      final e = ApiException.from(DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError));
      expect(e.kind, ApiErrorKind.network);
      expect(e.ref, isNull);
      expect(ApiException.from(DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.receiveTimeout)).kind,
          ApiErrorKind.network);
    });

    test('500: the body ref, else the X-Request-Id header; the message stays safe', () {
      final a = res(500, {'detail': {'code': 'server_error', 'kind': 'server', 'message': 'خطأ', 'message_en': 'Oops', 'ref': 'R-1'}}, rid: 'H-1');
      expect(a.kind, ApiErrorKind.server);
      expect(a.ref, 'R-1');
      expect(a.message, ApiMessages.server);
      final b = res(502, '<html>bad gateway</html>', rid: 'H-2');
      expect(b.kind, ApiErrorKind.server);
      expect(b.ref, 'H-2');
      expect(res(422, {'detail': 'x'}, rid: 'H-3').ref, isNull);
    });

    test('a hand-built exception keeps working', () {
      const e = ApiException(statusCode: 400, message: 'm', type: ApiErrorType.badRequest, code: 'head_required');
      expect(e.kind, ApiErrorKind.validation);
      expect(e.fields, isEmpty);
      expect(e.detail, isEmpty);
    });
  });

  group('FieldErrors', () {
    test('maps server names through aliases, codes for older servers, summary, clear', () {
      final fe = FieldErrors(aliases: const {'secretary_user_id': 'secretary', 'members': 'members'});
      expect(fe.take(res(422, secretaryNotMember())), isTrue);
      expect(fe.errorFor('secretary'), 'The secretary is not a member');
      expect(fe.summary, isNull);

      final many = res(422, {
        'error': {
          'kind': 'validation',
          'message_en': 'bad',
          'fields': [
            {'field': 'members.2.user_id', 'message_en': 'Unknown member'},
            {'field': 'body.secretary_user_id', 'message_en': 'Not a member'},
          ],
        }
      });
      fe.take(many);
      expect(fe.errorFor('members'), 'Unknown member');
      expect(fe.errorFor('secretary'), 'Not a member');
      expect(fe.summary, contains('2'));
      fe.keyFor('secretary');
      fe.keyFor('members');
      expect(fe.bad, ['secretary', 'members']);     // on-screen (registration) order first
      fe.clear('members');
      expect(fe.has('members'), isFalse);
      fe.clear();
      expect(fe.isEmpty, isTrue);

      final dotted = FieldErrors(aliases: const {'members': 'members', 'chair_user_id': 'chair'});
      expect(dotted.fieldOf('members.0.weight'), 'members');
      expect(dotted.fieldOf('faculty.chair_user_id'), 'chair');
      expect(dotted.fieldOf('body.members'), 'members');
      expect(dotted.fieldOf('query.page'), 'query.page');

      final act = FieldErrors(actions: const {'pick_head': 'head'});
      expect(act.take(res(422, {'detail': {'code': 'whatever', 'message': 'm', 'fix_action': 'pick_head'}})), isTrue);
      expect(act.errorFor('head'), 'm');

      final old = FieldErrors(codes: const {'head_required': 'head'});
      expect(old.take(res(422, {'detail': {'code': 'head_required', 'message': 'r'}}), text: 'Pick a head'), isTrue);
      expect(old.errorFor('head'), 'Pick a head');
    });

    testWidgets('revealFirst scrolls to the first bad field', (tester) async {
      final fe = FieldErrors()..take(res(422, {'detail': {'code': 'x', 'message': 'm', 'field': 'far'}}));
      final ctrl = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(controller: ctrl, cacheExtent: 5000, children: [
            const SizedBox(height: 2000),
            TextField(key: fe.keyFor('far')),
          ]),
        ),
      ));
      expect(ctrl.offset, 0);
      final done = fe.revealFirst();     // the scroll animates: pump it, then the future completes
      await tester.pumpAndSettle();
      await done;
      expect(ctrl.offset, greaterThan(0));
    });
  });

  group('AppErrorBox', () {
    final cases = <ApiException>[
      res(422, secretaryNotMember()),
      res(403, {'detail': {'code': 'not_staff', 'message': 'ليست لك صلاحية', 'message_en': 'You are not staff', 'kind': 'permission'}}),
      res(409, {'detail': {'code': 'busy', 'message': 'م', 'message_en': 'It clashes with a long existing booking in the same room', 'kind': 'conflict'}}),
      res(404, {'detail': {'code': 'gone', 'message': 'م', 'message_en': 'Gone', 'kind': 'not_found'}}),
      ApiException.from(DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError)),
      res(500, {'detail': {'code': 'server_error', 'kind': 'server', 'message': 'خطأ', 'message_en': 'Oops', 'ref': 'req-7f3a9c21d0e64b55a1c2'}}),
    ];
    for (final e in cases) {
      testWidgets('kind ${e.kind.name} lays out everywhere', (tester) async {
        await expectNoLayoutErrors(
            tester,
            () => SingleChildScrollView(
                  child: AppErrorBox(error: e, onRetry: () {}, onFix: e.fixAction == null ? null : () {}, fixLabel: 'Add as member and continue'),
                ));
      });
    }

    testWidgets('the fix and retry buttons and the copyable ref', (tester) async {
      var fixed = 0, retried = 0;
      await tester.pumpWidget(layoutHost(Column(children: [
        AppErrorBox(error: res(422, secretaryNotMember()), onFix: () => fixed++, fixLabel: 'Add as member and continue'),
        AppErrorBox(error: cases.last, onRetry: () => retried++),
      ]), scale: 1));
      expect(find.text('Add them to the members'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app_error_fix')));
      await tester.tap(find.byKey(const ValueKey('app_error_retry')));
      expect((fixed, retried), (1, 1));
      expect(find.text('req-7f3a9c21d0e64b55a1c2'), findsOneWidget);
      expect(find.byKey(const ValueKey('app_error_copy')), findsOneWidget);
    });
  });

  group('roster fix + org texts', () {
    const roster = CouncilRoster(councilId: 3, members: [
      RosterMember(userId: 1, name: 'Chair', weight: 2, isChair: true),
      RosterMember(userId: 2, name: 'B'),
    ]);

    test('add_member adds the secretary at weight 1 and keeps the others', () {
      final body = rosterAddMemberBody(roster, userId: 42, secretaryUserId: 42);
      expect(body['secretary_user_id'], 42);
      expect(body['members'], [
        {'user_id': 1, 'weight': 2},
        {'user_id': 2, 'weight': 1},
        {'user_id': 42, 'weight': 1},
      ]);
      final edited = rosterAddMemberBody(roster, weights: {1: 3, 2: 1}, userId: 42, secretaryUserId: 42);
      expect(edited['members'], [
        {'user_id': 1, 'weight': 3},
        {'user_id': 2, 'weight': 1},
        {'user_id': 42, 'weight': 1},
      ]);
      expect(rosterFixUserId({'user_id': 42}, 7), 42);
      expect(rosterFixUserId({}, 7), 7);
      expect(rosterCanAddMemberFix('secretary_not_member', null), isTrue);
      expect(rosterCanAddMemberFix('weight_cap', 'add_member'), isTrue);
      expect(rosterCanAddMemberFix('weight_cap', null), isFalse);
    });

    test('orgErrorText keeps the mapped text first and appends the fix', () {
      final txt = orgErrorText(res(422, secretaryNotMember()));
      expect(txt, startsWith('The secretary must be a member'));
      expect(txt, endsWith('— Add them to the members'));
      expect(orgErrorText(res(422, {'detail': {'code': 'head_required', 'message': 'x'}})), isNot(contains('—  ')));
      expect(orgErrorText(res(422, {'detail': {'code': 'dept_parent_cycle', 'message': 'x'}})), contains("can't sit under itself"));
    });

    test('heads step: refused ids from dept_ids and heads.<id> fields', () {
      final e = res(422, {
        'detail': {
          'code': 'head_invalid',
          'message': 'x',
          'dept_ids': [5],
          'fields': [
            {'field': 'heads.9', 'message_en': 'Not a member'}
          ],
        }
      });
      expect(headErrorIdsOf(e), {5, 9});
    });
  });
}
