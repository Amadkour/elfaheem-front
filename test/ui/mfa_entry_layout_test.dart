// The "Two-step verification" settings entry (review R3 M2) and the super-admin reset (R3 L4). Requirements:
// - the entry is offered to every role the server lets use MFA (status `allowed`), and to an account that already
//   has MFA or must have it; not to anyone else, never to a guest or while viewing as someone else;
// - it says On / Required / Off, opens the MFA page, and the feature key `profile.mfa` hides it;
// - it lays out on every screen size in both languages;
// - the super-admin reset asks first, calls the reset only after a yes, and reports a refusal.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_mfa_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/mfa.dart';
import 'package:flutter_education_app/features/auth/mfa_entry.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

class _Api implements MfaApi {
  _Api(this.current);
  MfaStatus current;
  int statusCalls = 0;

  @override
  Future<MfaStatus> status() async {
    statusCalls++;
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  tearDown(() {
    ViewAsState.instance.stop();
    AppConfig.disableList = [];
  });

  group('which accounts get the entry', () {
    test('allowed, enabled or required → shown; otherwise hidden', () {
      expect(mfaEntryVisible(const MfaStatus(allowed: true)), isTrue);
      expect(mfaEntryVisible(const MfaStatus(enabled: true)), isTrue, reason: 'MFA on: it must stay manageable');
      expect(mfaEntryVisible(const MfaStatus(required: true)), isTrue);
      expect(mfaEntryVisible(const MfaStatus()), isFalse);
      expect(mfaEntryVisible(MfaStatus.empty), isFalse);
    });

    test('the pill says On / Required / Off in both languages', () {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        final on = mfaEntryState(const MfaStatus(enabled: true, allowed: true));
        final req = mfaEntryState(const MfaStatus(required: true, allowed: true));
        final off = mfaEntryState(const MfaStatus(allowed: true));
        expect(on.$2, isTrue);
        expect(req.$2 || off.$2, isFalse);
        expect({on.$1, req.$1, off.$1}.length, 3, reason: lang);
      }
      AppConfig.lang = 'en';
      expect(mfaEntryState(const MfaStatus(enabled: true)).$1, 'On');
      expect(mfaEntryState(const MfaStatus(required: true)).$1, 'Required');
      expect(mfaEntryState(const MfaStatus(allowed: true)).$1, 'Off');
    });
  });

  group('layout', () {
    for (final s in {
      'off': const MfaStatus(allowed: true),
      'required': const MfaStatus(allowed: true, required: true),
      'on': const MfaStatus(allowed: true, enabled: true),
    }.entries) {
      testWidgets('MfaSecurityGroup ${s.key}', (t) async {
        await expectNoLayoutErrors(t, () => SingleChildScrollView(child: MfaSecurityGroup(status: s.value, onTap: () {})));
      });
    }
  });

  group('MfaSettingsEntry', () {
    Widget host(Widget child) => ChangeNotifierProvider(
          create: (_) => MyAuthProvider(storage: storage),
          child: layoutHost(SingleChildScrollView(child: child), scale: 1),
        );

    testWidgets('shown for an allowed role (e.g. org admin), opens the MFA page', (t) async {
      final api = _Api(const MfaStatus(allowed: true));
      await t.pumpWidget(host(MfaSettingsEntry(api: api)));
      await t.pump();
      expect(find.byKey(const ValueKey('mfa.entry')), findsOneWidget);
      expect(find.text('Two-step verification'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mfa.entry')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminMfaPage), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a forced account sees "Required"', (t) async {
      await t.pumpWidget(host(MfaSettingsEntry(api: _Api(const MfaStatus(allowed: true, required: true)))));
      await t.pump();
      expect(find.text('Required'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('hidden when the role may not use MFA', (t) async {
      await t.pumpWidget(host(MfaSettingsEntry(api: _Api(const MfaStatus()))));
      await t.pump();
      expect(find.byKey(const ValueKey('mfa.entry')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('hidden by the profile.mfa kill-switch', (t) async {
      AppConfig.disableList = ['profile.mfa'];
      await t.pumpWidget(host(MfaSettingsEntry(api: _Api(const MfaStatus(allowed: true)))));
      await t.pump();
      expect(find.byKey(const ValueKey('mfa.entry')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('never while viewing as someone else (the status is not even asked)', (t) async {
      ViewAsState.instance.start(id: 9, name: 'x', role: 'admin');
      final api = _Api(const MfaStatus(allowed: true));
      await t.pumpWidget(host(MfaSettingsEntry(api: api)));
      await t.pump();
      expect(find.byKey(const ValueKey('mfa.entry')), findsNothing);
      expect(api.statusCalls, 0);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('super-admin reset', () {
    Future<(bool?, List<int>)> run(WidgetTester t, {required bool yes, Object? error}) async {
      final calls = <int>[];
      bool? result;
      await t.pumpWidget(layoutHost(Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmResetUserMfa(context, userId: 42, name: 'Mona', reset: (id) async {
            calls.add(id);
            if (error != null) throw error;
          }),
          child: const Text('go'),
        ),
      ), scale: 1));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.textContaining('"Mona"'), findsOneWidget, reason: 'the question names the user');
      await t.tap(find.text(yes ? 'Reset' : 'exam_cancel'.tr));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5)); // let any notice timer finish
      return (result, calls);
    }

    testWidgets('asks first; a no changes nothing', (t) async {
      final (r, calls) = await run(t, yes: false);
      expect(r, isFalse);
      expect(calls, isEmpty);
    });

    testWidgets('a yes resets that user', (t) async {
      final (r, calls) = await run(t, yes: true);
      expect(r, isTrue);
      expect(calls, [42]);
    });

    testWidgets('a refusal (no MFA on that account) is reported, not swallowed as success', (t) async {
      final (r, calls) = await run(t,
          yes: true,
          error: const ApiException(statusCode: 409, message: 'x', type: ApiErrorType.conflict, code: 'mfa_not_enabled'));
      expect(r, isFalse);
      expect(calls, [42]);
    });

    test('the reset label exists in both languages', () {
      AppConfig.lang = 'ar';
      final ar = mfaResetLabel();
      AppConfig.lang = 'en';
      expect(mfaResetLabel(), 'Reset two-step verification');
      expect(ar, isNot(mfaResetLabel()));
    });
  });
}
