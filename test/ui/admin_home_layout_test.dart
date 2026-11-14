// The super admin's home body (AdminHomeBody) at 320x640 and 1400x900, Arabic + English, textScaler 1.3: full
// D-062 payload, an older server's payload (legacy keys only) and an empty platform.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longName = 'عبد الرحمن محمد عبد العزيز الشريف Abdulrahman Mohammed Abdulaziz Alsharif';

Map<String, dynamic> fullPayload() => {
      'students': 128400,
      'teachers': 8400,
      'courses': 3100,
      'published_courses': 2500,
      'active_enrollments': 400000,
      'pending_transfers': 3,
      'pending_subscriptions': 12,
      'active_subscriptions': 1500,
      'subscription_required': true,
      'income_by_currency': {'EGP': 5000000.0, 'SAR': 120000.0},
      'collected_by_currency': {'EGP': 6000000.0, 'SAR': 150000.0},
      'organizations': {
        'total': 42,
        'active': 40,
        'pending_approval': 2,
        'by_type': {'faculty': 20, 'university': 7, 'school': 9, 'center': 4, 'institute': 2, 'other': 0},
      },
      'series': [
        for (var i = 0; i < 30; i++)
          {
            'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}',
            'signups': 40 + (i * 37) % 90,
            'enrollments': 120 + (i * 53) % 400,
            'revenue': {'EGP': 12500.0 + (i * 911) % 30000, 'SAR': 300.0 + (i * 17) % 900, 'USD': 25.0},
            'live_sessions': 5 + i % 7,
            'complaints': i % 4,
          },
      ],
      'alerts': [
        {'key': 'jobs_failed_24h', 'severity': 'danger', 'count': 14, 'deep_link': '/admin/ops/jobs', 'by_kind': {'schedule_run': 9, 'registration': 2, 'recording': 2, 'outbox': 1}},
        {'key': 'otp_provider_unconfigured', 'severity': 'danger', 'count': 1, 'deep_link': '/admin/settings/otp'},
        {'key': 'payouts_overdue', 'severity': 'warning', 'count': 5, 'deep_link': '/admin/withdrawals?status=pending', 'days': 7},
        {'key': 'transfers_pending', 'severity': 'warning', 'count': 3, 'deep_link': '/admin/transfers'},
        {'key': 'orgs_pending_approval', 'severity': 'warning', 'count': 2, 'deep_link': '/admin/orgs?status=pending'},
        {'key': 'teacher_documents_pending', 'severity': 'info', 'count': 126, 'deep_link': '/admin/teachers/documents?status=pending'},
        {'key': 'brand_new_alert_kind', 'severity': 'info', 'count': 7, 'deep_link': '/admin/new'},
      ],
      'realtime': {'events_24h': 91300},
    };

Map<String, dynamic> legacyPayload() => {
      'students': 10,
      'teachers': 2,
      'courses': 5,
      'pending_transfers': 1,
      'pending_subscriptions': 0,
      'active_subscriptions': 4,
      'income_by_currency': {'EGP': 100.0},
    };

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    homeAttentionBadge = (_, child) => child;
  });

  testWidgets('full payload: pulse, needs you, charts, health, hubs', (tester) async {
    final data = AdminHomeData.fromOverview(fullPayload());
    await expectNoLayoutErrors(
      tester,
      () => AdminHomeBody(data: data, name: longName, pendingPayouts: 240, actions: AdminHomeActions(openAlert: (_) {}, openStudents: () {})),
    );
  });

  testWidgets('older server: legacy keys only (no organizations / series / alerts / realtime)', (tester) async {
    final data = AdminHomeData.fromOverview(legacyPayload());
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: data, name: 'A', pendingPayouts: 2));
  });

  testWidgets('empty platform: zeros, all clear, empty charts', (tester) async {
    final data = AdminHomeData.fromOverview({
      'organizations': {'total': 0, 'active': 0, 'pending_approval': 0, 'by_type': {}},
      'series': [
        for (var i = 0; i < 30; i++) {'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}', 'signups': 0, 'enrollments': 0, 'revenue': {}},
      ],
      'alerts': [],
      'realtime': {'events_24h': null},
    });
    expect(data.hasActivity, isFalse);
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: data, name: '', notice: 'x' * 120));
  });

  testWidgets('worst case: huge figures, long alert texts, many currencies (premium layout)', (tester) async {
    final p = fullPayload();
    p['students'] = 2147483647;
    p['teachers'] = 999999999;
    p['courses'] = 88888888;
    p['published_courses'] = 77777777;
    p['active_subscriptions'] = 123456789;
    p['organizations'] = {'total': 999999, 'active': 999998, 'pending_approval': 99999, 'by_type': {'faculty': 999999}};
    p['series'] = [
      for (var i = 0; i < 30; i++)
        {
          'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}',
          'signups': 9999999,
          'enrollments': 99999999,
          'revenue': {'EGP': 987654321987.55, 'SAR': 1.0, 'USD': 2.0, 'EUR': 3.0, 'KWD': 4.0},
          'live_sessions': 99999,
          'complaints': 99999,
        },
    ];
    p['alerts'] = [
      for (var i = 0; i < 12; i++)
        {'key': 'k$i', 'severity': i.isEven ? 'danger' : 'warning', 'count': 99999 * (i + 1), 'title': longName * 2, 'hint': longName * 3},
    ];
    p['realtime'] = {'events_24h': 9999999999};
    final data = AdminHomeData.fromOverview(p);
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: data, name: longName * 3, pendingPayouts: 999999, notice: 'x ' * 200));
  });

  testWidgets('a count the alerts already carry is drawn once', (tester) async {
    AppConfig.lang = 'en';
    final data = AdminHomeData.fromOverview(fullPayload());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(AdminHomeBody(data: data, name: 'A', pendingPayouts: 240), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('admin_pending_transfers'.tr), findsOneWidget);
    expect(find.text('admin_home_org_approvals'.tr), findsOneWidget);
    expect(find.text('admin_pending_payouts'.tr), findsOneWidget);
    expect(find.text('admin_home_all_clear'.tr), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
