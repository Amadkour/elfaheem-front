// Layout of the username v2 pieces and the restyled phone field (layout harness: 320×640 and 1400×900, ar + en,
// textScaler 1.3, real translations): the keep / change / remove sheet content (choose, busy, error, change step),
// the profile's username field during the change cooldown (kept and cleared), and PhoneInputField.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_education_app/features/auth/username_confirm.dart';
import 'package:flutter_education_app/features/auth/username_field.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _long = 'a_very_long_username_of_thirty';

Future<UsernameCheck> _taken(String n) async => UsernameCheck(
      username: n,
      available: false,
      code: 'USERNAME_TAKEN',
      suggestions: const ['${_long}1', 'ahmed.2'],
    );

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});

  group('UsernameConfirmContent', () {
    testWidgets('choose', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => UsernameConfirmContent(username: _long, onKeep: () {}, onChange: () {}, onRemove: () {}, onLater: () {}),
      );
    });

    testWidgets('choose · busy keep · error', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => const UsernameConfirmContent(
          username: _long,
          busy: UsernameConfirmAction.keep,
          error: 'تعذّر الاتصال بالخادم — تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى من فضلك',
        ),
      );
    });

    testWidgets('choose · busy remove', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => const UsernameConfirmContent(username: 'ahmed', busy: UsernameConfirmAction.remove),
      );
    });

    testWidgets('change step with a taken name and suggestions', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => UsernameConfirmContent(
          username: 'ahmed',
          step: UsernameConfirmStep.change,
          canSave: true,
          onBack: () {},
          onSave: () {},
          error: 'Something went wrong',
          changeField: UsernameField(
            controller: TextEditingController(text: _long),
            currentUsername: 'ahmed',
            checker: _taken,
            debounce: const Duration(milliseconds: 10),
          ),
        ),
      );
    });

    testWidgets('the buttons call back', (tester) async {
      final hits = <String>[];
      await tester.pumpWidget(layoutHost(UsernameConfirmContent(
        username: 'ahmed',
        onKeep: () => hits.add('keep'),
        onChange: () => hits.add('change'),
        onRemove: () => hits.add('remove'),
        onLater: () => hits.add('later'),
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('@ahmed'), findsOneWidget);
      await tester.tap(find.text('username_confirm_keep'.tr));
      await tester.tap(find.text('username_confirm_change'.tr));
      await tester.tap(find.text('username_confirm_remove'.tr));
      await tester.tap(find.text('username_confirm_later'.tr));
      expect(hits, ['keep', 'change', 'remove', 'later']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('profile cooldown', () {
    final until = DateTime.utc(2026, 11, 11, 8, 30);

    testWidgets('locked: read-only, says when, offers removal', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: UsernameField(
            controller: TextEditingController(text: _long),
            currentUsername: _long,
            lockedUntil: until,
            label: 'username_label'.tr,
          ),
        ),
      );
    });

    testWidgets('locked and cleared: "will be removed" + undo', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: UsernameField(
            controller: TextEditingController(),
            currentUsername: _long,
            lockedUntil: until,
          ),
        ),
      );
    });

    testWidgets('status line with and without the date', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Column(children: [
          UsernameStatusView(status: UsernameStatus.locked, username: _long, lockedUntil: until),
          const UsernameStatusView(status: UsernameStatus.locked, username: _long),
        ]),
      );
    });

    testWidgets('locked: typing is refused, Remove empties the field, Keep puts the name back', (tester) async {
      final ctrl = TextEditingController(text: 'ahmed');
      final statuses = <UsernameStatus>[];
      await tester.pumpWidget(layoutHost(Padding(
        padding: const EdgeInsets.all(16),
        child: UsernameField(
          controller: ctrl,
          currentUsername: 'ahmed',
          lockedUntil: until,
          onStatusChanged: statuses.add,
        ),
      )));
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isTrue);
      await tester.tap(find.text('username_remove'.tr));
      await tester.pump();
      expect(ctrl.text, '');
      expect(statuses.last, UsernameStatus.cleared);
      await tester.tap(find.text('username_keep_current'.tr));
      await tester.pump();
      expect(ctrl.text, 'ahmed');
      expect(statuses.last, UsernameStatus.locked);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('PhoneInputField (auth field look)', () {
    testWidgets('empty and filled', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            child: Column(children: [
              PhoneInputField(controller: TextEditingController(), label: 'phone'.tr, required: true),
              const SizedBox(height: 16),
              PhoneInputField(controller: TextEditingController(text: '+966512345678'), label: 'phone'.tr),
            ]),
          ),
        ),
      );
    });

    testWidgets('error state after validation', (tester) async {
      final key = GlobalKey<FormState>();
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: key,
            child: PhoneInputField(controller: TextEditingController(text: '+2012'), label: 'phone'.tr, required: true),
          ),
        ),
        act: (t) async => key.currentState?.validate(),
      );
    });

    testWidgets('keeps the full international number in the controller', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(layoutHost(PhoneInputField(controller: ctrl, label: 'Phone')));
      await tester.enterText(find.byType(TextFormField), '01012345678');
      expect(ctrl.text, '+201012345678');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
