// The timetable / academics / registrar screens pushed on top of the organization dashboard (D-103): they wear the
// dashboard's own header (OrgPushedPage: Back · title · subtitle · Refresh · calendar · bell · switcher) when I work
// in the organization, and keep their older app bar otherwise (a student, a member page, another organization).
// No overflow at 320x640 and 1400x900, Arabic and English, text x1.3, with long Arabic titles.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_academic_pages.dart' show CourseArchiveScreen;
import 'package:flutter_education_app/features/org/org_availability_pages.dart' show OrgAvailabilityRequestsPage;
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_registrar_member.dart';
import 'package:flutter_education_app/features/org/org_schedule_planning.dart' show orgStudioPage;
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart' show ScreenAppBar;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _longAr = 'جدول الفصل الدراسي الأول لكلية الهندسة والتكنولوجيا وعلوم الحاسب — البرامج الجامعية والدراسات العليا';
const _back = ValueKey('org.header.back');

OrgSession _session({int? current = 4}) => OrgSession()
  ..loaded = true
  ..items = [
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
  ..currentId = current;

Widget _wrap(Widget child, OrgSession session) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider<OrgSession>.value(value: session),
      ],
      child: child,
    );

void main() {
  late FakeApi api;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    await StorageService.getInstance();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  /// [routes] answer every call the screen makes (so the real content is drawn, not an error state), unless
  /// [allowMissing].
  void serve(Map<String, FakeHandler> routes, {bool allowMissing = false}) {
    // the badge counts: AttentionService refreshes on route pushes, throttled by the wall clock, so whether a test
    // reaches it depends on timing; it is always answered (as in org_pages_layout_test)
    api = FakeApi({
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
      ...routes,
    }, latency: const Duration(milliseconds: 10));
    api.install();
    addTearDown(api.uninstall);
    if (!allowMissing) addTearDown(() => expect(api.unmatched, isEmpty, reason: 'unanswered calls'));
  }

  group('studio sub-pages (orgStudioPage)', () {
    testWidgets('dashboard header: long Arabic title + subtitle over a page with its own FAB', (tester) async {
      final session = _session();
      await expectNoLayoutErrors(
        tester,
        () => _wrap(
          Builder(
            builder: (ctx) => orgStudioPage(
              ctx,
              title: _longAr,
              subtitle: 'الجدول الرئيسي · الإصدار 12 · مسودة لم تُنشر بعد وتحتاج مراجعة التعارضات',
              child: Scaffold(
                backgroundColor: Colors.transparent,
                floatingActionButton:
                    FloatingActionButton.extended(heroTag: 't', onPressed: () {}, icon: const Icon(Icons.add_rounded), label: const Text('طلب جديد')),
                body: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
                  for (var i = 0; i < 20; i++) ListTile(title: Text('$_longAr $i')),
                ]),
              ),
            ),
          ),
          session,
        ),
        act: (tester) async {
          expect(find.byKey(_back), findsOneWidget);
          expect(find.byType(ScreenAppBar), findsNothing);
          expect(find.byKey(const ValueKey('org.header.switcher')), findsOneWidget);
        },
      );
    });

    testWidgets('no organization open: the older bar stays', (tester) async {
      final session = _session(current: null);
      await expectNoLayoutErrors(
        tester,
        () => _wrap(
          Builder(builder: (ctx) => orgStudioPage(ctx, title: _longAr, child: const Center(child: Text('body')))),
          session,
        ),
        act: (tester) async {
          expect(find.byKey(_back), findsNothing);
          expect(find.byType(ScreenAppBar), findsOneWidget);
        },
      );
    });

    testWidgets('availability requests list under the header', (tester) async {
      serve({
        'GET /api/v1/org/orgs/4/availability-requests': (_) => {
              'items': [
                {'id': 1, 'title': 'مواعيدك المتاحة للفصل القادم — هيئة التدريس والهيئة المعاونة بجميع الأقسام', 'status': 'open',
                    'submitted': 12, 'targeted': 40, 'deadline': '2026-11-07T21:59:00', 'min_cells': 4, 'max_cells': 12},
              ],
            },
      });
      final session = _session();
      await expectNoLayoutErrors(
        tester,
        () => _wrap(
          Builder(builder: (ctx) => orgStudioPage(ctx, title: 'طلبات المواعيد المتاحة', maxWidth: 900, child: const OrgAvailabilityRequestsPage())),
          session,
        ),
        act: (tester) async => expect(find.byKey(_back), findsOneWidget),
      );
    });
  });

  group('course archive', () {
    final archive = {
      'course': {'code': 'CS401', 'name_ar': 'تصميم وتحليل الخوارزميات المتقدمة وتطبيقاتها في الذكاء الاصطناعي', 'name_en': 'Advanced algorithms'},
      'current': null,
      'years': [
        {
          'year_label': '2025/2026',
          'runs': [
            {'id': 1, 'status': 'archived', 'passed': 40, 'students': 44, 'term': {'kind': 'term1'}},
          ],
        },
      ],
    };

    testWidgets('staff of the organization: dashboard header', (tester) async {
      serve({'GET /api/v1/org/orgs/4/academic/courses/3/archive': (_) => archive});
      final session = _session();
      await expectNoLayoutErrors(
        tester,
        () => _wrap(const CourseArchiveScreen(orgId: 4, courseId: 3, canManage: true), session),
        act: (tester) async {
          expect(find.byKey(_back), findsOneWidget);
          expect(find.byType(ScreenAppBar), findsNothing);
        },
      );
    });

    testWidgets('another organization (a course profile): the older bar', (tester) async {
      serve({'GET /api/v1/org/orgs/5/academic/courses/3/archive': (_) => archive});
      final session = _session();
      await expectNoLayoutErrors(
        tester,
        () => _wrap(const CourseArchiveScreen(orgId: 5, courseId: 3), session),
        act: (tester) async {
          expect(find.byKey(_back), findsNothing);
          expect(find.byType(ScreenAppBar), findsOneWidget);
        },
      );
    });
  });

  group('registrar staff screens', () {
    testWidgets('grade entry (staff approval) with its bottom bar under the dashboard header', (tester) async {
      serve({
        'GET /api/v1/org/orgs/4/registrar/terms/1/grades/2': (_) => {
              'course': {'code': 'CS401', 'name_ar': 'تصميم وتحليل الخوارزميات المتقدمة وتطبيقاتها في الذكاء الاصطناعي'},
              'deny_letter': 'DN',
              'items': [
                for (var i = 0; i < 12; i++)
                  {
                    'student': {'id': 100 + i, 'name': 'عبد الرحمن محمد عبد العزيز الشناوي $i'},
                    'student_code': '2026${1000 + i}',
                    'grade_state': i.isEven ? 'draft' : 'none',
                    'percent': i.isEven ? 75 + i : null,
                    'letter': i.isEven ? 'B+' : null,
                    'absence_pct': 10,
                  },
              ],
            },
      });
      final session = _session();
      await expectNoLayoutErrors(
        tester,
        () => _wrap(staffGradesScreen(4, 1, 2), session),
        act: (tester) async {
          expect(find.byKey(_back), findsOneWidget);
          expect(find.byType(ScreenAppBar), findsNothing);
        },
      );
    });

    testWidgets('timetable consents and teaching list under the dashboard header', (tester) async {
      serve({
        'GET /api/v1/org/public/4/registrar/consents': (_) => {
              'periods': {
                '1': {'start': '08:00', 'end': '09:30'},
              },
              'items': [
                {
                  'id': 1,
                  'title': 'الجدول يضعك في وقت غير متاح لك — هل توافق على هذه المحاضرات؟',
                  'status': 'open',
                  'recommendation': {
                    'params': {
                      'cells': [
                        {'day': 'sunday', 'period_id': 1},
                        {'day': 'tuesday', 'period_id': 1},
                      ],
                    },
                  },
                },
              ],
            },
        'GET /api/v1/org/public/4/registrar/teach': (_) => {
              'items': [
                {
                  'course': {'id': 2, 'code': 'CS401', 'name_ar': 'تصميم وتحليل الخوارزميات المتقدمة وتطبيقاتها في الذكاء الاصطناعي'},
                  'term': {'id': 1, 'name_ar': 'الفصل الدراسي الأول 2026/2027'},
                  'grade_states': {'none': 12, 'draft': 30},
                },
              ],
            },
      });
      final session = _session();
      for (final screen in [const OrgConsentsScreen(orgId: 4), const OrgTeachScreen(orgId: 4)]) {
        await expectNoLayoutErrors(
          tester,
          () => _wrap(screen, session),
          act: (tester) async => expect(find.byKey(_back), findsOneWidget),
        );
      }
    });

    testWidgets("a student's own record keeps its bar; staff viewing a student's record get the header", (tester) async {
      serve({}, allowMissing: true); // every route a bare 404: the screens show their error state
      final session = _session();
      await expectNoLayoutErrors(
        tester,
        () => _wrap(const OrgRecordScreen(orgId: 4), session),
        act: (tester) async {
          expect(find.byKey(_back), findsNothing);
          expect(find.byType(ScreenAppBar), findsOneWidget);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => _wrap(const OrgRecordScreen(orgId: 4, studentId: 7), session),
        act: (tester) async => expect(find.byKey(_back), findsOneWidget),
      );
    });
  });
}
