// The organization's detail / editor screens on the dashboard's pushed-page header (OrgPushedPage, D-103): roles,
// a person's access, a form's editor and its answers, a complaint thread (composer at the bottom), the complaints
// report wizard (Back / Next bar at the bottom), an announcement's insights, the news feed, a unit's joining hub and
// the exam risk / feedback routes — each under Back · a long Arabic title · its context line · More · Refresh ·
// switcher, at 320x640 and 1400x900, Arabic and English, text x1.3: never an overflow, the Back button and the
// switcher there. Screens a member may open too (complaint thread, news feed) keep their own app bar when I do not
// work in that organization.
//
// The screens are pumped whole over FakeApi (fixture payloads; anything else is FastAPI's bare 404, which the
// screens show as their own error / empty state).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_access_page.dart';
import 'package:flutter_education_app/features/org/org_announcements.dart';
import 'package:flutter_education_app/features/org/org_feedback_risk.dart';
import 'package:flutter_education_app/features/org/org_join_pages.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_reports/report_page.dart';
import 'package:flutter_education_app/features/org/org_services_pages.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _longAr = 'مسؤول القبول والتسجيل وشؤون الطلاب والخريجين والدراسات العليا بكلية الهندسة والتكنولوجيا';
const _o = '/api/v1/org/orgs/4';

OrgSession _session({bool withOrg = true}) => OrgSession()
  ..loaded = true
  ..items = [
    if (withOrg)
      {
        'id': 4,
        'name_ar': 'كلية الهندسة والتكنولوجيا وعلوم الحاسب بجامعة النيل الأهلية',
        'name_en': 'Faculty of Engineering, Technology and Computer Science — Nile National University',
        'type': 'faculty',
        'status': 'approved',
        'my_role': 'org_admin',
        'access': 'admin',
        'depth': 0,
      },
  ]
  ..currentId = withOrg ? 4 : null;

Map<String, dynamic> _complaint() => {
      'id': 5,
      'ref': 'CMP-2026-000123',
      'subject': 'تأخر رصد درجات أعمال السنة لمقرر هندسة البرمجيات المتقدمة في الفصل الدراسي الأول',
      'body': 'لم تظهر درجات أعمال السنة حتى الآن رغم انتهاء موعد الرصد المعلن في التقويم الأكاديمي للكلية.',
      'status': 'in_progress',
      'priority': 'high',
      'dept_id': 2,
      'overdue': true,
      'user': {'id': 11, 'name': 'عبد الرحمن محمد عبد العزيز الشناوي'},
      'assigned_to': {'id': 12, 'name': 'Dr. Hala Mostafa'},
      'assignable': [
        {'id': 12, 'name': 'Dr. Hala Mostafa'},
        {'id': 13, 'name': 'أ. محمود السيد عبد الفتاح'},
      ],
      'attachments': const [],
      'messages': [
        {'id': 1, 'body': 'تم استلام الشكوى وجارٍ التواصل مع أستاذ المقرر.', 'from_staff': true, 'created_at': '2026-10-30T09:00:00'},
        {'id': 2, 'body': 'شكراً، في انتظار الرد.', 'from_staff': false, 'created_at': '2026-10-30T10:00:00'},
      ],
    };

final _routes = <String, FakeHandler>{
  'GET $_o/complaints/5': (_) => _complaint(),
  'GET $_o/access/users/7': (_) => {
        'user': {'id': 7, 'name': 'د. عبد الرحمن محمد عبد العزيز الشناوي — أستاذ مساعد بقسم علوم الحاسب'},
        'assignments': [
          {'id': 1, 'role_name_ar': _longAr, 'role_name_en': 'Admission officer', 'color': '#2563EB', 'dept_id': null},
        ],
        'grants': const [],
        'effective': const {'permissions': {}, 'dept_permissions': {}},
      },
  'GET $_o/access/roles': (_) => {'items': const []},
  'GET $_o/departments': (_) => {'items': const []},
  'GET $_o/forms/3/responses': (_) => {'items': const [], 'total': 0},
};

late FakeApi _api;

Widget _host(Widget child, OrgSession s) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider<OrgSession>.value(value: s),
      ],
      child: child,
    );

/// The dashboard's header is drawn (Back + the organization switcher).
Future<void> _expectHeader(WidgetTester tester) async {
  expect(find.byKey(const ValueKey('org.header.back')), findsOneWidget);
  expect(find.byKey(const ValueKey('org.header.switcher')), findsOneWidget);
}

/// Pumps [build] through the layout harness, letting the fake backend answer first.
Future<void> _check(WidgetTester tester, Widget Function() build, {Future<void> Function(WidgetTester)? act}) =>
    expectNoLayoutErrors(tester, build, frames: 6, act: (tester) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      if (act != null) await act(tester);
    });

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    _api = FakeApi(_routes, latency: const Duration(milliseconds: 10))..install();
  });
  tearDown(() => _api.uninstall());

  testWidgets('role editor: long name, Delete in More, the form keeps its input on Refresh', (tester) async {
    final s = _session();
    await _check(
      tester,
      () => _host(
        const OrgRoleEditor(role: {
          'id': 3,
          'name_ar': _longAr,
          'name_en': 'Admission, registration, student affairs and graduate studies officer',
          'description': 'Handles every admission file of the faculty',
          'color': '#2563EB',
          'editable': true,
          'is_system': false,
          'permissions': {},
        }),
        s,
      ),
      act: (tester) async {
        await _expectHeader(tester);
        expect(find.byKey(const ValueKey('org.page.more')), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'تم التعديل');
        await tester.tap(find.byKey(const ValueKey('org.header.refresh')).first);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('تم التعديل'), findsOneWidget);
      },
    );
  });

  testWidgets("a person's access: the name as the title, the roles below", (tester) async {
    final s = _session();
    await _check(tester, () => _host(const OrgPersonAccess(userId: 7), s), act: _expectHeader);
  });

  testWidgets('form editor and its answers (export / assignments in More)', (tester) async {
    final s = _session();
    await _check(
      tester,
      () => _host(
        const OrgFormBuilderScreen(edit: {
          'id': 3,
          'title': 'طلب إفادة قيد للطلاب المقيدين بمرحلة البكالوريوس والدراسات العليا',
          'kind': 'request',
          'fields': [
            {'type': 'text', 'label': 'الرقم القومي', 'required': true},
          ],
        }),
        s,
      ),
      act: _expectHeader,
    );
    await _check(
      tester,
      () => _host(
        const OrgFormResponsesScreen(form: {'id': 3, 'title': 'طلب إفادة قيد للطلاب المقيدين بمرحلة البكالوريوس والدراسات العليا'}),
        s,
      ),
      act: (tester) async {
        await _expectHeader(tester);
        expect(find.byKey(const ValueKey('org.page.more')), findsOneWidget);
      },
    );
  });

  testWidgets('complaint thread: ref + subject, actions in More, the composer at the bottom', (tester) async {
    final s = _session();
    await _check(
      tester,
      () => _host(const OrgComplaintThreadScreen(id: 5), s),
      act: (tester) async {
        await _expectHeader(tester);
        expect(find.text('CMP-2026-000123'), findsOneWidget);
        expect(find.byKey(const ValueKey('org.page.more')), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      },
    );
  });

  testWidgets('complaint thread opened for another organization keeps its own app bar', (tester) async {
    final s = _session(withOrg: false);
    await _check(
      tester,
      () => _host(const OrgComplaintThreadScreen(id: 5, orgId: 4, canAct: true), s),
      act: (tester) async {
        expect(find.byKey(const ValueKey('org.header.back')), findsNothing);
        expect(find.text('CMP-2026-000123'), findsOneWidget);
      },
    );
  });

  testWidgets('complaints report wizard: steps on top, Back / Next at the bottom', (tester) async {
    final s = _session();
    await _check(tester, () => _host(const OrgComplaintReportPage(deptId: 2), s), act: _expectHeader);
  });

  testWidgets('announcement insights and the news feed', (tester) async {
    final s = _session();
    await _check(
      tester,
      () => _host(
        const OrgAnnouncementAnalyticsScreen(
            orgId: 4, announcementId: 2, initial: {'title': 'مواعيد امتحانات منتصف الفصل الدراسي الأول لجميع الفرق والبرامج الدراسية'}),
        s,
      ),
      act: _expectHeader,
    );
    await _check(tester, () => _host(const OrgAnnouncementsFeedScreen(orgId: 4), s), act: _expectHeader);
    // a member of another organization: the feed keeps its app bar
    await _check(tester, () => _host(const OrgAnnouncementsFeedScreen(orgId: 77), s), act: (tester) async {
      expect(find.byKey(const ValueKey('org.header.back')), findsNothing);
    });
  });

  testWidgets("a program's joining hub: the tabs head the body", (tester) async {
    final s = _session();
    await _check(
      tester,
      () => _host(const OrgUnitJoinHub(unitType: 'program', unitId: 1, title: 'CSAI · $_longAr'), s),
      act: _expectHeader,
    );
  });

  testWidgets('exam risk / feedback routes wear the header; the sub-pages draw none of their own', (tester) async {
    final s = _session();
    for (final route in <Route<void> Function()>[() => orgExamRiskRoute(4), () => orgFeedbackSettingsRoute(4)]) {
      await _check(
        tester,
        () => _host(Navigator(onGenerateRoute: (_) => route()), s),
        act: _expectHeader,
      );
    }
    await _check(tester, () => _host(const OrgExamRiskPage(orgId: 4), s), act: (tester) async {
      expect(find.byKey(const ValueKey('org.header.back')), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    });
  });
}
