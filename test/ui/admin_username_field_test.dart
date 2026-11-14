// The admin's username field (D-071, admin edit — round 3): the body builder (unchanged → key absent, cleared → null,
// set → normalized, kill switch → nothing), the save hold, the field at 320 / 1400 wide, ar + en, textScaler 1.3
// (layout harness, real translations), its Remove / Keep action, a submit error on the field, and the kill switch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_username_field.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_education_app/features/auth/username_field.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'a_very_long_username_of_thirty';

Future<UsernameCheck> _free(String n) async => UsernameCheck(username: n, available: true);

void main() {
  final killSwitches = AppConfig.disableList;
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});

  group('adminUsernameBody', () {
    test('unchanged → the key is absent', () {
      expect(adminUsernameBody(current: 'ahmed', text: 'ahmed'), isEmpty);
      expect(adminUsernameBody(current: 'ahmed', text: '@Ahmed '), isEmpty);
      expect(adminUsernameBody(current: null, text: ''), isEmpty);
      expect(adminUsernameBody(current: '', text: '  '), isEmpty);
    });

    test('cleared → null', () {
      final b = adminUsernameBody(current: 'ahmed', text: '');
      expect(b.containsKey('username'), isTrue);
      expect(b['username'], isNull);
      expect(adminUsernameBody(current: 'ahmed', text: '@')['username'], isNull);
    });

    test('set or changed → the normalized name', () {
      expect(adminUsernameBody(current: 'ahmed', text: '@New.Name'), {'username': 'new.name'});
      expect(adminUsernameBody(current: null, text: 'first_one'), {'username': 'first_one'});
    });

    test('the kill switch sends nothing', () {
      expect(adminUsernameBody(current: 'ahmed', text: '', enabled: false), isEmpty);
      expect(adminUsernameBody(current: 'ahmed', text: 'other', enabled: false), isEmpty);
    });

    test('the save waits for a changed name the field still checks or refuses', () {
      AppConfig.lang = 'en';
      final set = adminUsernameBody(current: 'ahmed', text: 'other');
      expect(adminUsernameHold(set, UsernameStatus.available), isNull);
      expect(adminUsernameHold(set, UsernameStatus.unchecked), isNull);
      expect(adminUsernameHold(set, UsernameStatus.checking), 'username_wait_check'.tr);
      expect(adminUsernameHold(set, UsernameStatus.taken), 'username_fix_first'.tr);
      expect(adminUsernameHold(const {}, UsernameStatus.taken), isNull, reason: 'nothing sent: nothing to wait for');
      expect(adminUsernameHold(const {'username': null}, UsernameStatus.cleared), isNull);
    });
  });

  group('AdminUsernameField layout', () {
    tearDown(() => AppConfig.disableList = killSwitches);

    testWidgets('the current name, with Remove', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: AdminUsernameField(
            controller: TextEditingController(text: _long),
            currentUsername: _long,
            checker: _free,
          ),
        ),
      );
    });

    testWidgets('a taken name with suggestions', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: AdminUsernameField(
            controller: TextEditingController(text: 'holder'),
            currentUsername: _long,
            error: const UsernameError(
              username: 'holder',
              code: 'USERNAME_TAKEN',
              suggestions: ['${_long}1', 'holder.2', 'holder_37'],
            ),
            checker: _free,
          ),
        ),
      );
    });

    testWidgets('no name yet', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: AdminUsernameField(controller: TextEditingController(), checker: _free),
        ),
      );
    });
  });

  group('AdminUsernameField behaviour', () {
    setUp(() => AppConfig.lang = 'en');
    tearDown(() => AppConfig.disableList = killSwitches);

    Future<void> pump(WidgetTester tester, Widget field) =>
        tester.pumpWidget(layoutHost(Padding(padding: const EdgeInsets.all(16), child: field), scale: 1));

    testWidgets('Remove empties the field, Keep puts the name back', (tester) async {
      final ctrl = TextEditingController(text: 'ahmed');
      final statuses = <UsernameStatus>[];
      await pump(
        tester,
        AdminUsernameField(controller: ctrl, currentUsername: 'ahmed', checker: _free, onStatusChanged: statuses.add),
      );
      expect(find.text('username_current'.tr), findsOneWidget);
      expect(find.text('username_remove'.tr), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin.username.remove')));
      await tester.pump();
      expect(ctrl.text, '');
      expect(statuses.last, UsernameStatus.cleared);
      expect(adminUsernameBody(current: 'ahmed', text: ctrl.text), {'username': null});
      expect(find.text('admin_username_keep'.tr), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin.username.remove')));
      await tester.pump();
      expect(ctrl.text, 'ahmed');
      expect(statuses.last, UsernameStatus.current);
      expect(adminUsernameBody(current: 'ahmed', text: ctrl.text), isEmpty);
    });

    testWidgets('no Remove action without a current name', (tester) async {
      await pump(tester, AdminUsernameField(controller: TextEditingController(), checker: _free));
      expect(find.byKey(const ValueKey('admin.username.remove')), findsNothing);
      expect(find.byType(UsernameField), findsOneWidget);
    });

    testWidgets('a submit error shows on the field with its suggestions', (tester) async {
      await pump(
        tester,
        AdminUsernameField(
          controller: TextEditingController(text: 'holder'),
          currentUsername: 'ahmed',
          error: const UsernameError(username: 'holder', code: 'USERNAME_TAKEN', suggestions: ['holder.7']),
          checker: _free,
        ),
      );
      await tester.pump();
      expect(find.textContaining('username_taken'.tr, findRichText: true), findsOneWidget);
      expect(find.text('@holder.7'), findsOneWidget);
    });

    testWidgets('hidden by the kill switch auth.username', (tester) async {
      AppConfig.disableList = [kUsernameFeatureKey];
      expect(adminUsernameOn, isFalse);
      await pump(tester, AdminUsernameField(controller: TextEditingController(text: 'a'), checker: _free));
      expect(find.byType(UsernameField), findsNothing);
      AppConfig.disableList = const [];
      expect(adminUsernameOn, isTrue);
    });
  });
}
