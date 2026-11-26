// Redesign A1 (admin): the new and rebuilt admin pages at 320x640 and 1400x900, ar / en, text x1.3 (no layout
// error), over the CAST demo data (test/support/redesign/a1_fakes.dart), plus the inbox's behaviour.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/admin/admin_analytics_page.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/admin/approvals/admin_approvals_inbox.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_api.dart';
import '../../support/redesign/a1_fakes.dart';
import '../layout_harness.dart';

void main() {
  late StorageService storage;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() async {
    storage = await a1SignIn();
    mockRequestPlugins();
    AppConfig.lang = 'ar';
    final fake = FakeApi(a1Routes(), latency: const Duration(milliseconds: 10))..install();
    addTearDown(fake.uninstall);
  });

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
          ChangeNotifierProvider(create: (_) => TeacherDeviceRequestsProvider()),
        ],
        child: child,
      );

  Future<void> layout(WidgetTester tester, Widget Function() page) =>
      expectNoLayoutErrors(tester, () => host(page()), scaffold: false, frames: 12);

  testWidgets('analytics', (t) => layout(t, () => AdminAnalyticsPage(data: AdminHomeData.fromOverview(a1Overview()))));
  testWidgets('analytics, an older server (no series)',
      (t) => layout(t, () => AdminAnalyticsPage(data: AdminHomeData.fromOverview({'students': 3}))));
  testWidgets('requests inbox', (t) => layout(t, () => const AdminApprovalsInboxPage()));

  testWidgets('the inbox gathers every queue, oldest first, and filters by kind', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(layoutHost(const AdminApprovalsInboxPage(), scale: 1)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 2 accounts + 1 transfer + 1 device + 1 certificate + 1 parent link
    expect(find.text('6 requests wait for your decision'), findsOneWidget);
    final titles = [for (final w in tester.widgetList<Text>(find.byType(Text))) w.data ?? ''];
    // the parent link (20 Nov) is older than the teacher account (21 Nov)
    expect(titles.indexWhere((s) => s.contains('أحمد سعد العنزي ←')), lessThan(titles.indexOf('أ. ريم السبيعي')));
    await tester.tap(find.text('Device change').first);
    await tester.pump();
    expect(find.text('أ. ريم السبيعي'), findsNothing);
    expect(find.text('فيصل العنزي'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  test('ages read as days or hours', () {
    AppConfig.lang = 'en';
    final now = DateTime.utc(2026, 11, 27, 12);
    expect(admAgeText(DateTime.utc(2026, 11, 25, 12), now), '2 days ago');
    expect(admAgeText(DateTime.utc(2026, 11, 27, 9), now), '3 hours ago');
    expect(const AdmRequest(kind: AdmRequestKind.account, title: 'x').isOld(now), isFalse);
    expect(AdmRequest(kind: AdmRequestKind.account, title: 'x', at: DateTime.utc(2026, 11, 23)).isOld(now), isTrue);
  });
}
