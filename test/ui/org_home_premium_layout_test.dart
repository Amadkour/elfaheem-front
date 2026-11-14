// The organization home's premium pieces (D-631): the hero, the members card, the stat row and the shortcut tiles
// through expectNoLayoutErrors (320×640 and 1400×900, ar / en, text ×1.3), with the spec's payload, a worst-case one
// (a long organization name, huge counts, a long first name, long shortcut labels) and an empty one.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/home/org_home_premium.dart';
import 'package:flutter_education_app/features/org/org_dashboard_home.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';
import 'org_home_v3_layout_test.dart' show adminPayload, emptyMemberPayload, wrapProviders;

Map<String, dynamic> worstPayload() {
  final m = adminPayload();
  m['organization'] = {
    'id': 4,
    'name_ar': 'الأكاديمية العربية للعلوم والتكنولوجيا والنقل البحري — فرع العلمين الجديدة للدراسات العليا',
    'name_en': 'Arab Academy for Science, Technology and Maritime Transport — New Alamein Postgraduate Branch',
    'type': 'university',
    'status': 'approved',
  };
  m['kpis'] = {'students': 1284000, 'teachers': 99999, 'staff': 18750, 'courses': 123456, 'sub_organizations': 1};
  m['members'] = {'students': 1284000, 'teachers': 99999, 'staff': 18750, 'pending_join': 12345};
  m['pending_total'] = 98765;
  m['tasks_total'] = 98765;
  return m;
}

List<OrgHomeShortcut> shortcuts() => [
      for (final (icon, ar, en) in [
        (Icons.groups_rounded, 'الأعضاء وطلبات الانضمام المعلّقة', 'Members and pending join requests'),
        (Icons.account_tree_rounded, 'الهيكل الأكاديمي', 'Academic structure'),
        (Icons.campaign_rounded, 'الإعلانات', 'Announcements'),
        (Icons.support_agent_rounded, 'الشكاوى والمقترحات الواردة', 'Complaints and suggestions received'),
      ])
        OrgHomeShortcut(icon: icon, label: AppConfig.lang == 'ar' ? ar : en, onTap: () {}),
    ];

Widget body(Map<String, dynamic> payload, {bool admin = true, String name = 'Aleksandra'}) {
  final d = OrgHomeData.fromJson(payload)!;
  return wrapProviders(
      OrgHomeBody(
        data: d,
        alerts: [for (final a in d.alerts) ?OrgAttentionSpec.of(a, () {})],
        onTaskAction: (_, _) {},
        onOpenTask: (_) {},
        onRetryTask: (_) {},
        onSeeAllTasks: () {},
        onOpenUnit: (_) {},
        onSeeAllUnits: admin ? () {} : null,
        greetingName: name,
        shortcuts: shortcuts(),
        onOpenMembers: () {},
      ),
      admin: admin);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  testWidgets('premium org home: the spec payload', (tester) async {
    await expectNoLayoutErrors(tester, () => body(adminPayload()));
  });

  testWidgets('premium org home: worst case (long names, huge counts, long labels)', (tester) async {
    await expectNoLayoutErrors(tester, () => body(worstPayload(), name: 'Bartholomew-Fitzgerald'));
  });

  testWidgets('premium org home: empty member home', (tester) async {
    await expectNoLayoutErrors(tester, () => body(emptyMemberPayload(), admin: false, name: ''));
  });

  testWidgets('the hero offers Review only while something waits', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(body(adminPayload())));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const ValueKey('org.home.hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('org.home.members')), findsOneWidget);
    expect(find.text('Review what needs you'), findsOneWidget);
    await tester.pumpWidget(layoutHost(body(emptyMemberPayload(), admin: false)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Review what needs you'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
