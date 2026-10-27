// AdminHomeData (the super admin's home model over GET /admin/overview): series parsing, deltas, organizations by
// type, alerts, and what an older server (no D-062 blocks) or an empty payload gives.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> series30({int signups = 1, int enrollments = 2, double egp = 10, double sar = 0}) => [
      for (var i = 0; i < 30; i++)
        {
          'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}',
          // the second half is busier than the first
          'signups': i < 15 ? signups : signups * 3,
          'enrollments': i < 15 ? enrollments : enrollments * 2,
          'revenue': {'EGP': i < 15 ? egp : egp * 2, if (sar > 0) 'SAR': sar},
          'live_sessions': 1,
          'complaints': i % 10 == 0 ? 1 : 0,
        },
    ];

Map<String, dynamic> fullPayload() => {
      'students': 1200,
      'teachers': 84,
      'courses': 310,
      'published_courses': 250,
      'active_enrollments': 4000,
      'pending_transfers': 3,
      'pending_subscriptions': 2,
      'active_subscriptions': 150,
      'subscription_required': true,
      'income_by_currency': {'EGP': 50000.0, 'SAR': 1200.0},
      'collected_by_currency': {'EGP': 60000.0, 'SAR': 1500.0},
      'organizations': {
        'total': 12,
        'active': 10,
        'pending_approval': 2,
        'by_type': {'faculty': 7, 'university': 3, 'school': 2, 'center': 0},
      },
      'series': series30(sar: 5),
      'alerts': [
        {'key': 'jobs_failed_24h', 'severity': 'danger', 'count': 4, 'deep_link': '/admin/ops/jobs', 'by_kind': {'schedule_run': 3, 'outbox': 1}},
        {'key': 'payouts_overdue', 'severity': 'warning', 'count': 5, 'deep_link': '/admin/withdrawals?status=pending', 'days': 7},
        {'key': 'transfers_pending', 'severity': 'warning', 'count': 3, 'deep_link': '/admin/transfers'},
        {'key': 'orgs_pending_approval', 'severity': 'warning', 'count': 2, 'deep_link': '/admin/orgs?status=pending'},
        {'key': 'teacher_documents_pending', 'severity': 'info', 'count': 6, 'deep_link': '/admin/teachers/documents?status=pending'},
        {'key': 'otp_provider_unconfigured', 'severity': 'danger', 'count': 1, 'deep_link': '/admin/settings/otp'},
      ],
      'realtime': {'events_24h': 913},
    };

/// What the server sent before D-062: the legacy numbers only.
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
  setUp(() => AppConfig.lang = 'en');

  group('halfDelta', () {
    test('second half vs first half, in percent', () {
      expect(halfDelta([1, 1, 2, 2]), 100);
      expect(halfDelta([4, 4, 2, 2]), -50);
      expect(halfDelta([2, 2, 2, 2]), 0);
    });
    test('null without a base', () {
      expect(halfDelta([]), isNull);
      expect(halfDelta([5]), isNull);
      expect(halfDelta([0, 0, 3, 3]), isNull);
    });
  });

  group('AdminHomeData.fromOverview', () {
    test('full payload: numbers, series, deltas, organizations, alerts, realtime', () {
      final d = AdminHomeData.fromOverview(fullPayload());
      expect(d.users, 1284);
      expect(d.courses, 310);
      expect(d.hasSeries, isTrue);
      expect(d.series.length, 30);
      expect(d.series.first.date, '2026-10-01');
      expect(d.series.first.dayLabel, '1');
      expect(d.series.last.dayLabel, '30');
      expect(d.signups30, 15 * 1 + 15 * 3);
      expect(d.enrollments30, 15 * 2 + 15 * 4);
      expect(d.liveSessions30, 30);
      expect(d.complaints30, 3);
      expect(d.signupsDelta, 200);
      expect(d.enrollmentsDelta, 100);
      expect(d.signupsSpark.length, 30);
      expect(d.revenueSpark.first, 15); // 10 EGP + 5 SAR summed as the day's gross
      expect(d.revenue30ByCurrency, {'EGP': 450.0, 'SAR': 150.0});
      expect(d.mainCurrency, 'EGP');
      expect(d.revenueDelta, closeTo((15 * 25 - 15 * 15) / (15 * 15) * 100, 0.001));
      expect(d.recent(14).length, 14);
      expect(d.recent(14).first.date, '2026-10-17');
      expect(d.hasActivity, isTrue);

      expect(d.hasOrganizations, isTrue);
      expect(d.orgTotal, 12);
      expect(d.orgPendingApproval, 2);
      expect(d.orgByType, {'faculty': 7, 'university': 3, 'school': 2, 'center': 0});

      expect(d.hasAlerts, isTrue);
      expect(d.alerts.map((a) => a.key).toList(), [
        'jobs_failed_24h',
        'payouts_overdue',
        'transfers_pending',
        'orgs_pending_approval',
        'teacher_documents_pending',
        'otp_provider_unconfigured',
      ]);
      expect(d.alerts.first.isDanger, isTrue);
      expect(d.alert('payouts_overdue')!.days, 7);
      expect(d.jobsFailed24h, 4);
      expect(d.jobsFailedByKind, {'schedule_run': 3, 'outbox': 1});
      expect(d.transfersInAlerts, isTrue);
      expect(d.orgApprovalsInAlerts, isTrue);
      // alerts (minus the OTP flag) + payouts + subscriptions; transfers and org approvals are NOT added twice
      expect(d.queueTotal(9), 4 + 5 + 3 + 2 + 6 + 9 + 2);

      expect(d.hasRealtime, isTrue);
      expect(d.eventsLast24h, 913);
      expect(d.isEmpty, isFalse);
    });

    test('older server: no organizations / series / alerts / realtime → those blocks hide, legacy numbers stay', () {
      final d = AdminHomeData.fromOverview(legacyPayload());
      expect(d.users, 12);
      expect(d.hasSeries, isFalse);
      expect(d.signupsSpark, isEmpty);
      expect(d.signupsDelta, isNull);
      expect(d.revenueDelta, isNull);
      expect(d.mainCurrency, isNull);
      expect(d.revenue30ByCurrency, isEmpty);
      expect(d.recent(14), isEmpty);
      expect(d.hasActivity, isFalse);
      expect(d.hasOrganizations, isFalse);
      expect(d.orgTotal, isNull);
      expect(d.orgByType, isEmpty);
      expect(d.hasAlerts, isFalse);
      expect(d.alerts, isEmpty);
      expect(d.jobsFailed24h, 0);
      expect(d.hasRealtime, isFalse);
      expect(d.eventsLast24h, isNull);
      expect(d.incomeByCurrency, {'EGP': 100.0});
      // the legacy pending counts are the queue
      expect(d.transfersInAlerts, isFalse);
      expect(d.queueTotal(2), 1 + 0 + 2);
    });

    test('empty payload and wrong shapes never throw', () {
      final d = AdminHomeData.fromOverview(const {});
      expect(d.isEmpty, isTrue);
      expect(d.users, 0);
      expect(d.queueTotal(0), 0);
      final odd = AdminHomeData.fromOverview({
        'students': 'x',
        'organizations': 'nope',
        'series': 'nope',
        'alerts': {'key': 'not a list'},
        'realtime': {'events_24h': null},
      });
      expect(odd.hasOrganizations, isFalse);
      expect(odd.hasSeries, isFalse);
      expect(odd.hasAlerts, isFalse);
      expect(odd.hasRealtime, isTrue);
      expect(odd.eventsLast24h, isNull);
      final partial = AdminHomeData.fromOverview({
        'series': [
          {'date': '2026-10-01'},
          {'date': 'bad', 'signups': '3', 'revenue': {'EGP': 'x'}},
        ],
      });
      expect(partial.series.length, 2);
      expect(partial.series[1].dayLabel, 'bad');
      expect(partial.series[1].signups, 3); // asInt parses numeric strings
      expect(partial.hasActivity, isTrue); // 3 signups on the second day
      expect(partial.signupsDelta, isNull);
    });

    test('a series with no sale leaves the revenue donut and tile out', () {
      final d = AdminHomeData.fromOverview({'series': series30(egp: 0)});
      expect(d.hasSeries, isTrue);
      expect(d.revenue30ByCurrency, isEmpty);
      expect(d.mainCurrency, isNull);
      expect(d.hasActivity, isTrue);
    });
  });

  group('translations', () {
    test('every key the home uses exists in both languages', () {
      const keys = [
        'admin_home_users', 'admin_home_organizations', 'admin_home_revenue_30d', 'admin_home_vs_prev_half',
        'admin_home_signups_hint', 'admin_home_enrollments_hint', 'admin_home_org_approvals', 'admin_home_all_clear',
        'admin_home_signups', 'admin_home_enrollments', 'admin_home_activity_title', 'admin_home_orgs_by_type',
        'admin_home_revenue_by_currency', 'admin_home_no_activity', 'admin_home_no_activity_hint', 'admin_home_no_orgs',
        'admin_home_no_revenue', 'admin_home_health', 'admin_home_events_24h', 'admin_home_jobs_failed',
        'admin_home_live_sessions_30d', 'admin_home_complaints_30d', 'admin_home_hubs', 'admin_home_assistant',
        'admin_home_income', 'admin_home_stale', 'admin_alert_jobs_failed_24h', 'admin_alert_payouts_overdue',
        'admin_alert_teacher_documents_pending', 'admin_alert_otp_provider_unconfigured', 'admin_alert_otp_hint',
        'admin_alert_older_than_days', 'admin_alert_jobs_hint', 'admin_job_schedule_run', 'admin_job_registration',
        'admin_job_recording', 'admin_job_outbox',
        // reused
        'home_admin_sub', 'home_needs_you', 'admin_pending_transfers', 'admin_pending_payouts', 'admin_pending_subscriptions',
        'admin_active_subscribers', 'admin_course_income_after_discounts', 'courses', 'dl_admin_title', 'svc_organizations',
        'features', 'admin_teachers',
      ];
      for (final k in keys) {
        final v = translation[k];
        expect(v, isA<Map>(), reason: k);
        expect((v as Map)['en'], isNotEmpty, reason: '$k.en');
        expect(v['ar'], isNotEmpty, reason: '$k.ar');
      }
    });
  });

  group('alert labels', () {
    test('every server key has a title key, an icon and a hint where the server adds one', () {
      for (final k in ['jobs_failed_24h', 'payouts_overdue', 'teacher_documents_pending', 'transfers_pending', 'orgs_pending_approval', 'otp_provider_unconfigured']) {
        expect(adminAlertTitleKey(k), isNot(k), reason: k);
      }
      expect(adminAlertTitleKey('something_new'), 'something_new');
      expect(adminJobKindKey('schedule_run'), 'admin_job_schedule_run');
      expect(adminJobKindKey('weird'), 'weird');
      expect(adminAlertHint(const AdminAlert(key: 'payouts_overdue', severity: 'warning', count: 2, days: 7)), contains('7'));
      expect(adminAlertHint(const AdminAlert(key: 'jobs_failed_24h', severity: 'danger', count: 3, byKind: {'outbox': 3, 'recording': 0})), contains('3'));
      expect(adminAlertHint(const AdminAlert(key: 'jobs_failed_24h', severity: 'danger', count: 3, byKind: {'outbox': 3, 'recording': 0})), isNot(contains('recording')));
      expect(adminAlertHint(const AdminAlert(key: 'transfers_pending', severity: 'warning', count: 3)), isNull);
      expect(adminAlertHint(const AdminAlert(key: 'otp_provider_unconfigured', severity: 'danger', count: 1)), isNotNull);
    });
  });
}
