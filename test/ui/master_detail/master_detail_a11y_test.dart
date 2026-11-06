// D-290: Flutter's accessibility guidelines (tap targets 48 / 44, labelled tap targets, WCAG text contrast) over the
// detail panel and the admin Students page with a panel open — the same harness as test/ui/a11y_guidelines_test.dart
// (phone + wide, ar / en, light / dark), over the FakeApi entity payloads.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../a11y_guidelines_test.dart' show expectA11y;
import '../admin_ds/people_support.dart';
import 'master_detail_layout_test.dart' show scaffoldWith;
import 'md_support.dart';

void main() {
  late FakeApi api;

  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    EntitiesApi.instance.invalidate();
    api = FakeApi({...entityRoutes(), ...peopleRoutes()}, latency: const Duration(milliseconds: 10))..install();
  });

  tearDown(() => api.uninstall());

  testWidgets('the detail panel (a student, then a course drilled from it)', (tester) async {
    await expectA11y(tester, 'md panel', () => scaffoldWith(const EntityRef(EntityKind.student, 100)));
    await expectA11y(tester, 'md panel course',
        () => scaffoldWith(const EntityRef(EntityKind.student, 100), push: const [EntityRef(EntityKind.course, 40)]));
  });

  testWidgets('the admin Students page with a student panel open', (tester) async {
    final auth = await peopleSetUp(api);
    await expectA11y(tester, 'md admin students', () {
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=student:100');
      return const AdminUsersPage(role: 'student', embedded: true);
    }, wrap: (app) => peopleProviders(auth, app));
  });
}
