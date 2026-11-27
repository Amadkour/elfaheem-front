// F1 + S4: every role lands on its own home (MyAuthProvider.homeRoute), and a signed-in user who opens another
// role's home by URL (a student on /app/admin_dashboard, a teacher on /parent_dashboard) is sent back to their own
// home by main.dart's `_Guard` (routeRoleRedirect) instead of getting that shell with failing requests.
// A super admin in "view as" keeps the viewed user's shell (startViewAs opens /teacher_dashboard for a teacher).
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/routing/route_roles.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Future<MyAuthProvider> _signedInAs(String? role) async {
  final storage = await StorageService.getInstance();
  await storage.clearUser();
  await storage.saveUser({'id': 7, 'name': 'Test', 'gmail': 'u@example.com', 'role': ?role});
  return MyAuthProvider(storage: storage);
}

const _homes = {
  'student': '/dashboard',
  'teacher': '/teacher_dashboard',
  'parent': '/parent_dashboard',
  'admin': '/admin_dashboard',
  'super-admin': '/admin_dashboard',
  'developer': '/admin_dashboard',
  'org-admin': '/org_dashboard',
  'org-staff': '/org_dashboard',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  setUp(mockRequestPlugins);

  group('homeRoute per role (F1)', () {
    for (final e in _homes.entries) {
      test('${e.key} → ${e.value}', () async {
        final auth = await _signedInAs(e.key);
        expect(auth.currentUser?.role, e.key);
        expect(auth.homeRoute, e.value);
      });
    }

    test('an unknown role gets the student home; an unreadable cached user is signed out, not a crash', () async {
      expect((await _signedInAs('mystery')).homeRoute, '/dashboard');
      final broken = await _signedInAs(null); // no role: UserModel.fromJson throws
      expect(broken.currentUser, isNull);
      expect(broken.isAuthenticated, isFalse);
      expect(broken.homeRoute, '/dashboard');
    });

    test('an org admin who last left for the personal account starts on /dashboard', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppModeController.personalHomeKey(7), true);
      addTearDown(() => prefs.remove(AppModeController.personalHomeKey(7)));
      final auth = await _signedInAs('org-admin');
      expect(auth.homeRoute, '/dashboard');
    });
  });

  group('_Guard role check (S4)', () {
    test('every role-only home names its roles', () {
      expect(roleOnlyRoutes.keys, containsAll(['/admin_dashboard', '/teacher_dashboard', '/parent_dashboard']));
    });

    for (final e in _homes.entries) {
      final role = e.key;
      test('$role: other roles\' homes send it to ${e.value}, its own home opens', () async {
        // the release behaviour: a debug build opens the developer tools (/kit_gallery) to every role on purpose
        debugOpenRoutesEnabled = false;
        addTearDown(() => debugOpenRoutesEnabled = true);
        final auth = await _signedInAs(role);
        for (final route in roleOnlyRoutes.keys) {
          final allowed = roleOnlyRoutes[route]!.contains(role);
          expect(
            routeRoleRedirect(route, role: auth.currentUser?.role, homeRoute: auth.homeRoute),
            allowed ? isNull : e.value,
            reason: '$role on $route',
          );
        }
        // the own home is never redirected (no loop)
        expect(routeRoleRedirect(auth.homeRoute, role: role, homeRoute: auth.homeRoute), isNull);
      });
    }

    test('a student on the admin, teacher and parent homes', () async {
      final auth = await _signedInAs('student');
      for (final r in ['/admin_dashboard', '/teacher_dashboard', '/parent_dashboard']) {
        expect(routeRoleRedirect(r, role: 'student', homeRoute: auth.homeRoute), '/dashboard', reason: r);
      }
      expect(routeRoleRedirect('/admin_dashboard?tab=users', role: 'student', homeRoute: auth.homeRoute), '/dashboard');
    });

    test('a debug build opens the developer tools to every role', () {
      expect(debugOpenRoutesEnabled, isTrue);
      expect(routeRoleRedirect('/kit_gallery', role: 'student', homeRoute: '/dashboard'), isNull);
    });

    test('routes open to every signed-in role are never redirected', () {
      for (final r in ['/dashboard', '/home', '/org_dashboard', '/subscription', '/calendar', null]) {
        expect(routeRoleRedirect(r, role: 'student', homeRoute: '/dashboard'), isNull, reason: r);
      }
    });

    test('view as: the admin keeps the viewed user\'s shell', () {
      expect(routeRoleRedirect('/teacher_dashboard', role: 'super-admin', homeRoute: '/admin_dashboard', viewAs: true), isNull);
      expect(routeRoleRedirect('/teacher_dashboard', role: 'super-admin', homeRoute: '/admin_dashboard'), '/admin_dashboard');
    });
  });
}
