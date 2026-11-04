// Layout of the people pages (Students, Teachers, Admins, View as, My account): no overflow at 320x640 / 1400x900,
// Arabic + English, text x1.3, over a FakeApi that answers like the real /admin/users routes.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_admins_page.dart';
import 'package:flutter_education_app/features/admin/admin_profile_page.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_education_app/features/admin/admin_view_as_page.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'people_support.dart';

void main() {
  Future<void> layoutOf(WidgetTester tester, Widget Function() page, {Map<String, FakeHandler>? extra}) async {
    final api = FakeApi({...peopleRoutes(), ...?extra}, latency: const Duration(milliseconds: 50));
    final auth = await peopleSetUp(api);
    await expectNoLayoutErrors(tester, () => peopleProviders(auth, page()), frames: 6);
  }

  testWidgets('Students tab (embedded) lays out on a phone and a wide screen', (tester) async {
    await layoutOf(tester, () => const AdminUsersPage(role: 'student', embedded: true));
  });

  testWidgets('Teachers page (pushed) lays out', (tester) async {
    await layoutOf(tester, () => const AdminUsersPage(role: 'teacher'));
  });

  testWidgets('Admins page lays out', (tester) async {
    await layoutOf(tester, () => const AdminAdminsPage());
  });

  testWidgets('View as page lays out', (tester) async {
    await layoutOf(tester, () => const AdminViewAsPage());
  });

  testWidgets('My account lays out', (tester) async {
    await layoutOf(
      tester,
      () => ChangeNotifierProvider(create: (_) => ProfileProvider(storage: peopleStorage), child: const AdminProfilePage()),
      extra: {
        'GET /api/v1/admin/me': (_) => {
              'id': 7,
              'name': 'Boss',
              'gmail': 'boss@example.test',
              'phone': '+201000000000',
              'country': 'EG',
              'dob': '1990-04-02',
              'role': 'super-admin',
            },
      },
    );
  });
}
