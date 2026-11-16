// UX v3 phase 3: one account, optional personal profile. The user model reads `personal_enabled` (absent = on),
// the cold-start home and the forced Organization mode follow it, the switcher drops "Personal" when it is off,
// the settings switch lays out, and the shared `enable_personal` fix turns it on and retries.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/personal_access.dart';
import 'package:flutter_education_app/design/app_errors.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/personal_account_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

Widget _themed(Widget app) => ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: app);

Map<String, dynamic> _user({bool? personal, String role = 'org-staff'}) => {
      'id': 7,
      'name': 'Sara',
      'gmail': 'sara@example.com',
      'role': role,
      'last_login': '2026-11-15T08:00:00',
      if (personal != null) 'personal_enabled': personal,
    };

Map<String, dynamic> _overview({bool student = true}) => {
      'items': [
        {
          'organization': {'id': 4, 'status': 'approved', 'name_en': 'Uni'},
          'roles': [student ? 'student' : 'teacher'],
          'manage': null,
        },
      ],
      'default_org_id': 4,
    };

ApiException _personalOff() => ApiException.fromResponse(Response(
      requestOptions: RequestOptions(path: '/api/v1/teacher/courses'),
      statusCode: 403,
      data: {
        'detail': {
          'code': 'personal_off',
          'message': 'الحساب الشخصي مغلق',
          'message_en': 'Your personal account is off',
          'kind': 'permission',
          'fix_action': 'enable_personal',
        }
      },
    ));

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: Center(child: ContextSwitcher())))));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('ctx.pill')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
    AppModeController.applyContext = (_) {};
  });
  tearDown(() {
    PersonalAccess.instance.bind();
    PersonalAccess.send = (on) => ApiClient().put(PersonalAccess.path, body: {'enabled': on});
  });

  group('user model', () {
    test('personal_enabled present, absent (older server = on), cached round trip', () {
      expect(UserModel.fromJson(_user(personal: false)).personalEnabled, isFalse);
      expect(UserModel.fromJson(_user(personal: true)).personalEnabled, isTrue);
      expect(UserModel.fromJson(_user()).personalEnabled, isTrue);
      final off = UserModel.fromJson(_user(personal: false));
      expect(UserModel.fromJson(off.toJson()).personalEnabled, isFalse);
      expect(off.withPersonal(true).personalEnabled, isTrue);
      expect(off.withPersonal(true).id, 7);
    });
  });

  group('landing', () {
    test('decision table', () {
      String home(String role, bool on, [bool? remembered]) =>
          PersonalAccess.homeFor(role, personalEnabled: on, rememberedPersonal: remembered);
      // org roles: on = today (remembered Personal honoured), off = always the organization
      expect(home('org-staff', true), '/org_dashboard');
      expect(home('org-staff', true, true), '/dashboard');
      expect(home('org-admin', false, true), '/org_dashboard');
      expect(home('org-staff', false), '/org_dashboard');
      // a teacher / parent who is staff somewhere with personal off: the organization dashboard
      expect(home('teacher', true), '/teacher_dashboard');
      expect(home('teacher', false), '/org_dashboard');
      expect(home('parent', false), '/org_dashboard');
      // students open /dashboard either way (Organization mode is forced there), admins are untouched
      expect(home('student', false), '/dashboard');
      expect(home('super-admin', false), '/admin_dashboard');
    });

    test('never off without an organization', () {
      expect(PersonalAccess.decide(flag: false, noOrg: true), isTrue);
      expect(PersonalAccess.decide(flag: false, noOrg: false), isFalse);
      expect(PersonalAccess.decide(flag: true, noOrg: false), isTrue);
      PersonalAccess.instance.bind(personalEnabled: false, role: 'student');
      AppModeController.instance.debugSet({'items': []}, mode: AppMode.individual);
      expect(PersonalAccess.enabled, isTrue); // the overview answered: no organization
      AppModeController.instance.debugSet(_overview(), mode: AppMode.individual);
      expect(PersonalAccess.enabled, isFalse);
    });

    test('a student member with personal off is in Organization mode, even with Personal remembered', () {
      AppModeController.instance.debugSet(_overview(), mode: AppMode.individual);
      PersonalAccess.instance.bind(personalEnabled: true, role: 'student');
      expect(AppModeController.instance.isOrg, isFalse);
      PersonalAccess.instance.bind(personalEnabled: false, role: 'student');
      expect(AppModeController.instance.isOrg, isTrue);
      expect(AppModeController.instance.currentOrgId, 4);
      // staff only (no member home): nothing forced, the dashboard is the home
      AppModeController.instance.debugSet(_overview(student: false), mode: AppMode.individual);
      expect(AppModeController.instance.isOrg, isFalse);
    });
  });

  group('switcher', () {
    testWidgets('personal on: Personal offered, no sign-out card', (tester) async {
      AppModeController.instance.debugSet(_overview(), mode: AppMode.organization, orgId: 4);
      await _openSheet(tester);
      expect(find.byKey(const ValueKey('ctx.sheet.personal')), findsOneWidget);
      expect(find.byKey(const ValueKey('ctx.sheet.signout')), findsNothing);
    });

    testWidgets('personal off: no Personal, sign out instead; no exit pill', (tester) async {
      PersonalAccess.instance.bind(personalEnabled: false, role: 'student');
      AppModeController.instance.debugSet(_overview(), mode: AppMode.organization, orgId: 4);
      await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: Center(child: ContextSwitcher())))));
      await tester.pump();
      expect(find.byKey(const ValueKey('ctx.exit')), findsNothing);
      await _openSheet(tester);
      expect(find.byKey(const ValueKey('ctx.sheet.personal')), findsNothing);
      expect(find.byKey(const ValueKey('ctx.sheet.signout')), findsOneWidget);
      expect(find.byKey(const ValueKey('ctx.sheet.org.4')), findsOneWidget);
    });

    testWidgets('ContextExitButton: leave when on, switch when off', (tester) async {
      AppModeController.instance.debugSet(_overview(), mode: AppMode.organization, orgId: 4);
      await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: Center(child: ContextExitButton())))));
      expect(find.byKey(const ValueKey('ctx.leave')), findsOneWidget);
      PersonalAccess.instance.bind(personalEnabled: false, role: 'student');
      await tester.pump();
      expect(find.byKey(const ValueKey('ctx.leave')), findsNothing);
      expect(find.byKey(const ValueKey('ctx.switch')), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the Personal account switch lays out (ar/en, every size)', (tester) async {
      PersonalAccess.instance.bind(personalEnabled: false, role: 'org-staff');
      await expectNoLayoutErrors(tester, () => _themed(const PersonalAccountTile(inOrg: true)), scaffold: true);
    });

    testWidgets('hidden for a person without an organization', (tester) async {
      PersonalAccess.instance.bind(personalEnabled: true, role: 'teacher');
      AppModeController.instance.debugSet({'items': []}, mode: AppMode.individual);
      await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: PersonalAccountTile()))));
      expect(find.byKey(const ValueKey('personal.switch')), findsNothing);
    });
  });

  group('enable_personal fix', () {
    test('the shared fix turns the personal account on, then retries', () async {
      PersonalAccess.instance.bind(personalEnabled: false, role: 'org-staff');
      final sent = <bool>[];
      PersonalAccess.send = (on) async {
        sent.add(on);
        return {'personal_enabled': on};
      };
      final e = _personalOff();
      expect(e.fixAction, PersonalAccess.fixAction);
      var retried = 0;
      final fix = appSharedFix(e, onRetry: () => retried++);
      expect(fix, isNotNull);
      expect(fix!.$2, 'Turn on personal account');
      fix.$1();
      await Future<void>.delayed(Duration.zero);
      expect(sent, [true]);
      expect(PersonalAccess.instance.flag, isTrue);
      expect(retried, 1);
      // any other error: no shared fix
      expect(appSharedFix(ApiException(statusCode: 403, message: 'x')), isNull);
    });

    testWidgets('AppErrorBox shows the fix button for personal_off', (tester) async {
      await tester.pumpWidget(_themed(MaterialApp(home: Scaffold(body: AppErrorBox(error: _personalOff())))));
      expect(find.byKey(const ValueKey('app_error_fix')), findsOneWidget);
      expect(find.text('Turn on personal account'), findsOneWidget);
    });
  });
}
