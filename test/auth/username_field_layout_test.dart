// The @username field (D-071): the status line + suggestion chips in every status, and the whole field, at 320 / 1400
// wide, ar + en, textScaler 1.3 (layout harness, real translations); then the field's behaviour — debounce, stale
// answers dropped, nothing sent for an empty value or the account's own name, a submit error shown on the field.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_education_app/features/auth/username_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _long = 'a_very_long_username_of_thirty';

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});

  group('UsernameStatusView layout', () {
    for (final status in UsernameStatus.values) {
      testWidgets('status ${status.name}', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => Padding(
            padding: const EdgeInsets.all(16),
            child: UsernameStatusView(
              status: status,
              username: _long,
              problem: status == UsernameStatus.invalid ? UsernameProblem.domainSuffix : null,
              suggestions: const ['${_long}1', 'a_very_long_username_of_thir.2', 'ahmed_23'],
              onSuggestion: (_) {},
            ),
          ),
        );
      });
    }

    testWidgets('invalid with only the server message', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => const UsernameStatusView(
          status: UsernameStatus.invalid,
          username: 'abc',
          serverMessage: 'اسم المستخدم لا يجب أن يشبه رقم هاتف أو بريداً إلكترونياً — اختر اسماً آخر من فضلك',
        ),
      );
    });

    testWidgets('every rule sentence', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            for (final p in UsernameProblem.values)
              UsernameStatusView(status: UsernameStatus.invalid, username: 'x', problem: p),
          ]),
        ),
      );
    });
  });

  testWidgets('UsernameField layout (taken, with suggestions)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Padding(
        padding: const EdgeInsets.all(16),
        child: UsernameField(
          controller: TextEditingController(text: _long),
          checker: (n) async => UsernameCheck(
            username: n,
            available: false,
            code: 'USERNAME_TAKEN',
            suggestions: const ['${_long}1', 'ahmed.2'],
          ),
          debounce: const Duration(milliseconds: 10),
        ),
      ),
    );
  });

  group('UsernameField behaviour', () {
    setUp(() => AppConfig.lang = 'en');

    Future<void> pump(WidgetTester tester, Widget field) async {
      await tester.pumpWidget(layoutHost(Padding(padding: const EdgeInsets.all(16), child: field), scale: 1));
    }

    testWidgets('debounced: only the last value is checked', (tester) async {
      final asked = <String>[];
      final statuses = <UsernameStatus>[];
      final ctrl = TextEditingController();
      await pump(
        tester,
        UsernameField(
          controller: ctrl,
          checker: (n) async {
            asked.add(n);
            return UsernameCheck(username: n, available: true);
          },
          onStatusChanged: statuses.add,
        ),
      );
      await tester.enterText(find.byType(TextField), 'ahm');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'ahmed');
      await tester.pump(const Duration(milliseconds: 200));
      expect(asked, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(asked, ['ahmed']);
      expect(statuses.last, UsernameStatus.available);
      expect(find.textContaining('@ahmed'), findsOneWidget);
    });

    testWidgets('a stale answer is dropped', (tester) async {
      final pending = <String, Completer<UsernameCheck>>{};
      final ctrl = TextEditingController();
      UsernameStatus? last;
      await pump(
        tester,
        UsernameField(
          controller: ctrl,
          checker: (n) => (pending[n] = Completer<UsernameCheck>()).future,
          onStatusChanged: (s) => last = s,
        ),
      );
      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump(const Duration(milliseconds: 500));
      expect(pending.keys, ['first', 'second']);
      pending['second']!.complete(const UsernameCheck(username: 'second', available: true));
      await tester.pump();
      pending['first']!.complete(
          const UsernameCheck(username: 'first', available: false, code: 'USERNAME_TAKEN'));
      await tester.pump();
      expect(last, UsernameStatus.available);
    });

    testWidgets('empty, invalid and the own name never reach the server', (tester) async {
      final asked = <String>[];
      final ctrl = TextEditingController(text: 'mine');
      UsernameStatus? last;
      await pump(
        tester,
        UsernameField(
          controller: ctrl,
          currentUsername: 'mine',
          checker: (n) async {
            asked.add(n);
            return UsernameCheck(username: n, available: true);
          },
          onStatusChanged: (s) => last = s,
        ),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(seconds: 1));
      expect(last, UsernameStatus.cleared);
      await tester.enterText(find.byType(TextField), 'ahmed.com');
      await tester.pump(const Duration(seconds: 1));
      expect(last, UsernameStatus.invalid);
      expect(last!.blocksSubmit, isTrue);
      await tester.enterText(find.byType(TextField), 'Mine');
      await tester.pump(const Duration(seconds: 1));
      expect(ctrl.text, 'mine'); // the formatter lowercased it
      expect(last, UsernameStatus.current);
      expect(asked, isEmpty);
    });

    testWidgets('an older server (can\'t check) does not block', (tester) async {
      UsernameStatus? last;
      await pump(
        tester,
        UsernameField(
          controller: TextEditingController(),
          checker: (n) async => UsernameCheck.unchecked(n),
          onStatusChanged: (s) => last = s,
        ),
      );
      await tester.enterText(find.byType(TextField), 'ahmed');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(last, UsernameStatus.unchecked);
      expect(last!.blocksSubmit, isFalse);
    });

    testWidgets('a submit error shows on the field with tappable suggestions', (tester) async {
      final ctrl = TextEditingController(text: 'ahmed');
      const err = UsernameError(username: 'ahmed', code: 'USERNAME_TAKEN', suggestions: ['ahmed.7', 'ahmed_8']);
      await pump(
        tester,
        UsernameField(
          controller: ctrl,
          error: err,
          checker: (n) async => UsernameCheck(username: n, available: true),
        ),
      );
      await tester.pump();
      expect(find.text('@ahmed.7'), findsOneWidget);
      await tester.tap(find.text('@ahmed_8'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(ctrl.text, 'ahmed_8');
      expect(find.text('@ahmed.7'), findsNothing); // a new name: the error is gone, the check said available
    });
  });
}
