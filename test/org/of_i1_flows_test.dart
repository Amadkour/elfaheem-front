// Org flow overhaul, integration agent i1: the printed join code rotates through its own row (legacy_code_id), the
// remaining server error codes have texts, the report share sheet has no free e-mail, and a phone-invitation
// notification opens My organizations.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/org/org_member_pages.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_reports/report_model.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

ApiException _err(String code) => ApiException(statusCode: 422, message: 'srv', code: code, body: {'detail': {'code': code, 'message': 'srv'}});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
  });

  group('regenerate the printed join code', () {
    test('pure helpers', () {
      expect(legacyCodeIdOf({'legacy_code_id': 9}), 9);
      expect(legacyCodeIdOf({'legacy_code_id': null}), isNull);
      expect(legacyCodeIdOf({'legacy_code': 'ABC'}), isNull);
      expect(legacyCodeIdOf(null), isNull);
      expect(regeneratedCodeOf({'code': 'NEW1', 'id': 3}), 'NEW1');
      expect(regeneratedCodeOf({'join_code': 'OLD2'}), 'OLD2');
    });

    Future<(OrgSession, FakeApi, List<String>)> setup(Map<String, dynamic> settings) async {
      final paths = <String>[];
      final fake = FakeApi({
        'GET /api/v1/org/orgs/mine': (_) => {'items': [{'id': 4, 'name_en': 'Org', 'name_ar': 'م', 'status': 'approved', 'access': 'staff', 'depth': 0}]},
        'GET /api/v1/org/orgs/4/join/settings': (_) => settings,
        'POST /api/v1/org/orgs/4/join/codes/9/regenerate': (o) {
          paths.add(o.path);
          return {'id': 10, 'code': 'NEWCODE123', 'replaces': 9};
        },
        'POST /api/v1/org/orgs/4/join-code/regenerate': (o) {
          paths.add(o.path);
          return {'join_code': 'LEGACY9999'};
        },
      }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      mockRequestPlugins();
      fake.install();
      addTearDown(fake.uninstall);
      final s = OrgSession();
      await s.load();
      s.select(4);
      return (s, fake, paths);
    }

    test('with legacy_code_id: the multi-code route; the new plain code is returned', () async {
      final (s, _, paths) = await setup({'legacy_code': 'OLD', 'legacy_code_id': 9});
      expect(await s.regenerateCode(), 'NEWCODE123');
      expect(paths, ['/api/v1/org/orgs/4/join/codes/9/regenerate']);
    });

    test('older server (no id): the legacy route keeps working', () async {
      final (s, _, paths) = await setup({'legacy_code': 'OLD'});
      expect(await s.regenerateCode(), 'LEGACY9999');
      expect(paths, ['/api/v1/org/orgs/4/join-code/regenerate']);
    });
  });

  group('error texts', () {
    test('every code of the follow-up list reads in both languages', () {
      const codes = [
        'file_url_not_allowed', 'share_rate_limited', 'head_user_not_found', 'bad_filter', 'links_unavailable', 'not_reachable',
        'code_revoked', 'request_not_found', 'account_disabled', 'org_not_approved', 'share_target_not_allowed', 'link_expired',
      ];
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final c in codes) {
          final txt = orgErrorText(_err(c));
          expect(txt, isNot('srv'), reason: '$c ($lang)');
          expect(txt, isNot(c), reason: c);
        }
      }
      AppConfig.lang = 'en';
      expect(orgCodeText('org_not_approved'), contains('deleted'));
    });
  });

  group('report sharing', () {
    test('the share meta has no free e-mail key', () {
      final m = reportShareMeta(title: 'T', channel: 'both', userIds: {3, 4}, orgIds: {8});
      expect(m.containsKey('emails'), isFalse);
      expect(m['user_ids'], [3, 4]);
      expect(m['org_ids'], [8]);
    });

    test('the sheet source offers no e-mail field', () {
      final src = File('lib/features/org/org_reports/report_page.dart').readAsStringSync();
      expect(src.contains('_emails'), isFalse);
      expect(src.contains("'emails'"), isFalse);
      expect(src.contains('Extra e-mail addresses'), isFalse);
    });
  });

  group('notification routing', () {
    testWidgets('org_invitations opens My organizations (no org_id needed)', (tester) async {
      final opened = <String?>[];
      mockRequestPlugins();
      final storage = await StorageService.getInstance();
      await storage.saveUser({'id': 7, 'name': 'Sara', 'gmail': 's@example.test', 'role': 'student'});
      final auth = MyAuthProvider(storage: storage)..loadCachedUser();
      final fake = FakeApi({
        'GET /api/v1/org/orgs/mine': (_) => {'items': []},
      }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{'items': []});
      fake.install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(ChangeNotifierProvider<MyAuthProvider>.value(
        value: auth,
        child: ThemeConfigScope(
          provider: ThemeConfigProvider(api: ApiClient()),
          // the app opens it by its registry URL (D-170); main.dart's router builds the page, here a stand-in router
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('home')),
            onGenerateRoute: (s) {
              opened.add(s.name);
              return s.name == '/my-organizations' ? MaterialPageRoute(settings: s, builder: (_) => const OrgMembershipScreen()) : null;
            },
          ),
        ),
      ));
      await tester.runAsync(() async { AppNavigator.openFromPush({'type': 'org_invitation', 'id': '4', 'module': 'org_invitations'}); await Future<void>.delayed(const Duration(milliseconds: 1500)); });
      for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 200)); }
      expect(opened, contains('/my-organizations'));
      expect(find.byType(OrgMembershipScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
