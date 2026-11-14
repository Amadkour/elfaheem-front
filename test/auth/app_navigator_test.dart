// F13: AppNavigator.openModule / openFromPush land each module type on its page, and a link opened while signed out
// (DeepLinkService.setPending / setPendingProfile) opens once after the sign-in (main.dart's `_Guard` calls
// consumePending). The pushes are recorded by a NavigatorObserver and popped again before a frame is drawn, so the
// real pages are never built here: this checks WHERE a tap goes, the pages have their own tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart' show AppReleasesPage, kAppReleasesFeatureKey;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart' show kPointsFeatureKey;
import 'package:flutter_education_app/features/profile/public_profile/public_profile.dart' show ProfileLink;
import 'package:flutter_education_app/features/records/records_api.dart' show kRecordsFeatureKey;
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

class _Pushes extends NavigatorObserver {
  final names = <String>[];
  final args = <Object?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name ?? '<unnamed>');
    args.add(route.settings.arguments);
  }
}

void main() {
  late _Pushes pushes;
  late MyAuthProvider auth;

  Future<void> pumpApp(WidgetTester tester, String role) async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Test', 'gmail': 'u@example.com', 'role': role});
    await ApiClient.instance.saveTokens(access: 'a', refresh: 'r');
    auth = MyAuthProvider(storage: storage);
    pushes = _Pushes();
    await tester.pumpWidget(ChangeNotifierProvider<MyAuthProvider>.value(
      value: auth,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [pushes],
        onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => const SizedBox()),
      ),
    ));
    pushes.names.clear();
    pushes.args.clear();
  }

  /// Runs [open] up to its first push, records where it went, and pops back before any page is built.
  Future<List<String>> landing(WidgetTester tester, FutureOr<void> Function() open) async {
    pushes.names.clear();
    pushes.args.clear();
    unawaited(Future.sync(open));
    for (var i = 0; i < 10; i++) {
      await tester.idle();
    }
    final out = List.of(pushes.names);
    navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await tester.pump();
    return out;
  }

  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    AppNavigator.requestedTab.value = null;
  });

  tearDown(() {
    AppConfig.disableList = [];
    if (ViewAsState.active) ViewAsState.instance.stop();
  });

  group('openModule', () {
    testWidgets('named pages', (tester) async {
      await pumpApp(tester, 'student');
      final cases = <String, String>{
        'notifications': '/notifications',
        'inbox': '/inbox',
        'subscription': '/subscription',
        'calendar': '/calendar',
        'chat': '/chat',
        'chat_reports': '/chat/reports',
        'org_invitations': AppRoutes.location(AppRoutes.orgMemberships.id),
        'brand_new_module': '/brand_new_module', // a module this build does not know: its route, never nothing
      };
      for (final e in cases.entries) {
        expect(await landing(tester, () => AppNavigator.openModule(e.key, targetId: 3)), [e.value], reason: e.key);
      }
    });

    testWidgets('a course: its page by id; without an id, the notifications', (tester) async {
      await pumpApp(tester, 'student');
      expect(await landing(tester, () => AppNavigator.openModule('course', targetId: 12)), ['/course-by-id']);
      expect(await landing(tester, () => AppNavigator.openModule('course')), ['/notifications']);
      expect(await landing(tester, () => AppNavigator.openModule('course_profile', targetId: 12)), ['/course-profile']);
      expect(await landing(tester, () => AppNavigator.openModule('course_profile')), ['/notifications']);
    });

    testWidgets('the inbox opens on the tab the notice names', (tester) async {
      await pumpApp(tester, 'student');
      await landing(tester, () => AppNavigator.openModule('inbox', kind: 'notifications'));
      expect('${pushes.args.single}', 'InboxTab.notifications');
      await landing(tester, () => AppNavigator.openModule('inbox', kind: 'offers')); // offers sit with the announcements
      expect('${pushes.args.single}', 'InboxTab.announcements');
      await landing(tester, () => AppNavigator.openModule('inbox'));
      expect('${pushes.args.single}', 'InboxTab.todo');
    });

    testWidgets('pages behind a kill switch or a role fall back to the notifications', (tester) async {
      await pumpApp(tester, 'student');
      AppConfig.disableList = [kPointsFeatureKey, kRecordsFeatureKey];
      for (final m in ['points', 'live_plan', 'records', 'records_shared']) {
        expect(await landing(tester, () => AppNavigator.openModule(m)), ['/notifications'], reason: m);
      }
      AppConfig.disableList = [];
      // super admins only / parents only
      expect(await landing(tester, () => AppNavigator.openModule('app_releases')), ['/notifications']);
      expect(await landing(tester, () => AppNavigator.openModule('parent_grades')), ['/notifications']);
      // a lobby notice without a room
      expect(await landing(tester, () => AppNavigator.openModule('live_lobby')), ['/notifications']);
    });

    testWidgets('pages with a route of their own', (tester) async {
      await pumpApp(tester, 'student');
      expect(await landing(tester, () => AppNavigator.openModule('points')), ['/points']);
      expect(await landing(tester, () => AppNavigator.openModule('records', targetId: 4)), ['/records']);
      expect(await landing(tester, () => AppNavigator.openModule('records_shared', data: {'token': 'abc'})), ['/records/shared']);
      expect(await landing(tester, () => AppNavigator.openModule('teacher_todo')), ['/teacher-todo']);
    });

    testWidgets('a super admin opens App versions', (tester) async {
      await pumpApp(tester, 'super-admin');
      expect(AppConfig.disableList, isNot(contains(kAppReleasesFeatureKey)));
      expect(await landing(tester, () => AppNavigator.openModule('app_releases')), [AppReleasesPage.routeName]);
      expect(await landing(tester, () => AppNavigator.openModule('app_release', targetId: 9)), ['${AppReleasesPage.routeName}/9']);
    });

    testWidgets('profile / my_courses switch the home tab instead of pushing', (tester) async {
      await pumpApp(tester, 'student');
      for (final m in ['profile', 'my_courses']) {
        expect(await landing(tester, () => AppNavigator.openModule(m)), isEmpty, reason: m);
        expect(AppNavigator.requestedTab.value, m);
      }
    });

    testWidgets('signed out, or an admin in view-as: nothing opens', (tester) async {
      await pumpApp(tester, 'student');
      await ApiClient.instance.clearTokens();
      expect(await landing(tester, () => AppNavigator.openModule('notifications')), isEmpty);
      await ApiClient.instance.saveTokens(access: 'a', refresh: 'r');
      ViewAsState.instance.start(id: 5, name: 'x', role: 'student');
      expect(await landing(tester, () => AppNavigator.openModule('notifications')), isEmpty);
      expect(await landing(tester, () => AppNavigator.openFromPush({'module': 'notifications'})), isEmpty);
    });
  });

  group('openFromPush', () {
    testWidgets('each payload shape', (tester) async {
      await pumpApp(tester, 'student');
      final cases = <Map<String, dynamic>, String>{
        {'module': 'notifications'}: '/notifications',
        {'module': 'calendar', 'target_id': '3'}: '/calendar',
        {'module': 'inbox', 'tab': 'offers'}: '/inbox',
        {'course_id': '12'}: '/course-by-id', // a bare course id → that course
        {'type': 'course_profile', 'id': '12'}: '/course-profile',
        {'type': 'points'}: '/points',
        {'type': 'live_plan_expiring'}: '/points',
        {'type': 'live_lobby'}: '/notifications', // no room id
        <String, dynamic>{}: '/notifications', // nothing to go by → the list
      };
      for (final e in cases.entries) {
        expect(await landing(tester, () => AppNavigator.openFromPush(e.key)), [e.value], reason: '${e.key}');
      }
    });
  });

  group('pending deep link after the sign-in', () {
    testWidgets('a course link opens once', (tester) async {
      await pumpApp(tester, 'student');
      DeepLinkService.instance.setPending(const CourseLink(12, 5));
      expect(await landing(tester, DeepLinkService.instance.consumePending), ['/course-by-id']);
      expect(await landing(tester, DeepLinkService.instance.consumePending), isEmpty); // once only
    });

    testWidgets('a profile link opens once; the last link opened wins', (tester) async {
      await pumpApp(tester, 'student');
      DeepLinkService.instance.setPending(const CourseLink(12, null));
      DeepLinkService.instance.setPendingProfile(const ProfileLink('ahmed'));
      expect(await landing(tester, DeepLinkService.instance.consumePending), ['/@ahmed']);
      expect(await landing(tester, DeepLinkService.instance.consumePending), isEmpty);
    });
  });
}
