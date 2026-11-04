// No overflow on any screen size (320x640 and 1400x900, ar + en, text x1.3) for the Configuration hub pages, each driven
// through a FakeApi with realistic payloads: Platform settings (+ fee receipts), Features, Data lab, Student review &
// read flags, Recommendations, Update prompt, Terms (About & terms), Theme, Exam feedback, Live performance; and the
// "needs a server update" state of a page whose route the server does not have.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_education_app/features/admin/admin_content_page.dart';
import 'package:flutter_education_app/features/admin/admin_data_lab_page.dart';
import 'package:flutter_education_app/features/admin/admin_features_page.dart';
import 'package:flutter_education_app/features/admin/admin_feedback_settings.dart';
import 'package:flutter_education_app/features/admin/admin_flags_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_platform_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_recs_page.dart';
import 'package:flutter_education_app/features/admin/admin_theme_page.dart';
import 'package:flutter_education_app/features/admin/admin_versions_page.dart';
import 'package:flutter_education_app/features/admin/live_settings/live_settings_page.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'cfg_support.dart';

void main() {
  Future<void> check(WidgetTester tester, Widget page, {Map<String, FakeHandler>? routes}) async {
    final api = FakeApi(routes ?? cfgRoutes(), latency: const Duration(milliseconds: 20));
    final auth = await cfgSetUp(api);
    await expectNoLayoutErrors(tester, () => cfgProviders(auth, page), scaffold: false, frames: 14);
  }

  testWidgets('Platform settings', (tester) => check(tester, const AdminPlatformSettingsPage()));
  testWidgets('Organization fee receipts', (tester) => check(tester, const AdminOrgFeePaymentsPage()));
  testWidgets('Features', (tester) => check(tester, const AdminFeaturesPage()));
  testWidgets('Data lab', (tester) => check(tester, const AdminDataLabPage()));
  testWidgets('Student review & read flags', (tester) => check(tester, const AdminFlagsSettingsPage()));
  testWidgets('Recommendations', (tester) => check(tester, const AdminRecommendationsPage()));
  testWidgets('Update prompt', (tester) => check(tester, const AdminVersionsPage()));
  testWidgets('About & terms', (tester) => check(tester, const AdminContentPage()));
  testWidgets('Theme', (tester) => check(tester, const AdminThemePage()));
  testWidgets('Exam feedback', (tester) => check(tester, const AdminFeedbackSettingsPage()));
  testWidgets('Live performance', (tester) => check(tester, const LiveSettingsPage()));

  testWidgets('a route the server lacks reads "needs a server update" on every page', (tester) async {
    for (final page in <Widget>[
      const AdminPlatformSettingsPage(),
      const AdminFeaturesPage(),
      const AdminRecommendationsPage(),
      const LiveSettingsPage(),
      const AdminFeedbackSettingsPage(),
    ]) {
      await check(tester, page, routes: cfgRoutes(missing: true));
    }
  });
}
