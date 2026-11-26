// VISUAL review renders of the S-C schedule, analysis and messages screens (redesign Stu2Schedule, Stu2Analysis,
// Stu1Comm) with the CAST.md demo data, at 390x844 and 1360x900, Arabic and English, light. Compared by eye with
// D:/platform/redesign-ref/ref/student/056_* … 067_*, 155_* … 167_*. Not a CI suite.
//
//   flutter test test/visual/redesign/sc --update-goldens [--plain-name schedule]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_api.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_provider.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_screen.dart';
import 'package:flutter_education_app/features/attendance/analysis/student/student_attendance_model.dart';
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalView;
import 'package:flutter_education_app/features/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/calendar/schedule_store.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_page.dart' show ScAnnouncementsBanner, ScPrivateReplyNote;
import 'package:flutter_education_app/features/messaging/inbox/inbox_page.dart' show ScInboxHero;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// Wednesday 25 Nov 2026 (a school day): the maths class is on now, 7:30 to 8:20 pm
DateTime _wall(int day, int h, [int m = 0]) => DateTime(2026, 11, 25 + day, h, m);
DateTime get _now => AppTime.fromZone(_wall(0, 19, 40)).toUtc();
String _iso(DateTime wall) => AppTime.fromZone(wall).toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> _ev(String id, String source, DateTime s, DateTime e, String title, {String? sub, int? course, String? mode}) =>
    {'id': id, 'source': source, 'title': title, 'subtitle': sub, 'starts_at': _iso(s), 'ends_at': _iso(e), 'course_id': course, 'mode': mode};

class _CalApi extends RemoteCalendarApi {
  const _CalApi({this.empty = false});
  final bool empty;

  @override
  Future<dynamic> feed(String start, String end, {int? orgId, int? deptId, bool detail = false}) async => {
        'items': empty
            ? const []
            : [
                _ev('session:1', 'course_session', _wall(0, 16), _wall(0, 16, 50), _t('الفيزياء: مراجعة الفصل', 'Physics: chapter review'),
                    sub: _t('أ. فهد المطيري', 'Mr Fahad Almutairi'), course: 11, mode: 'online'),
                _ev('session:2', 'course_session', _wall(0, 19, 30), _wall(0, 20, 20), _t('الرياضيات: الدوال الأسية', 'Maths: exponential functions'),
                    sub: _t('أ. ماجد الشهري', 'Mr Majed Alshehri'), course: 12, mode: 'online'),
                _ev('exam:3', 'exam', _wall(0, 21), _wall(0, 22), _t('اختبار الدوال', 'Functions quiz'), course: 12),
                _ev('session:4', 'course_session', _wall(1, 16), _wall(1, 16, 50), _t('الإنجليزي: Unit 5', 'English: Unit 5'),
                    sub: _t('أ. خالد العتيبي', 'Mr Khaled Alotaibi'), course: 13, mode: 'online'),
              ],
        'pending_invites': 0,
      };
}

Future<dynamic> _weekly(String path) async => {'all_courses': const []};

class _AnApi extends StudentAnalyticsApi {
  @override
  Future<List<EnrolledCourse>> fetchMyEnrollments() async => [
        EnrolledCourse(id: 12, title: _t('الرياضيات', 'Maths'), teacherName: _t('أ. ماجد الشهري', 'Mr Majed Alshehri'), progress: 64, sessionsCount: 18),
        EnrolledCourse(id: 11, title: _t('الفيزياء', 'Physics'), teacherName: _t('أ. فهد المطيري', 'Mr Fahad Almutairi'), progress: 71, sessionsCount: 14),
        EnrolledCourse(id: 13, title: _t('الإنجليزي', 'English'), progress: 81, sessionsCount: 12),
        EnrolledCourse(id: 14, title: _t('الكيمياء', 'Chemistry'), progress: 32, sessionsCount: 10),
      ];

  @override
  Future<DlProfile?> fetchMyProfile({int? courseId}) async => null;
}

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('schedule', (tester) async {
    for (final empty in [false, true]) {
      await kitRender(
        tester,
        empty ? 'sc_schedule_empty' : 'sc_schedule_list',
        () => SchedulePage(
          key: UniqueKey(),
          api: _CalApi(empty: empty),
          store: CalendarStore(),
          now: _now,
          liveKeys: const {'session:2'},
          weeklyGet: _weekly,
          role: 'student',
          initialView: CalView.agenda,
          asTab: true,
        ),
        storage: storage,
        modes: const [false],
        langs: empty ? const ['ar'] : const ['ar', 'en'],
        grow: false,
      );
    }
  });

  testWidgets('analysis', (tester) async {
    await kitRender(
      tester,
      'sc_analysis_overview',
      () => ChangeNotifierProvider(create: (_) => StudentAnalyticsProvider(api: _AnApi()), child: const StudentAnalyticsScreen()),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('messages pieces', (tester) async {
    await kitRender(
      tester,
      'sc_messages_pieces',
      () => const AppAreaScope(
        area: AppArea.chat,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ScInboxHero(waiting: 4, late: 1),
          ScAnnouncementsBanner(),
          Padding(padding: EdgeInsets.symmetric(horizontal: AppSpace.md), child: ScPrivateReplyNote()),
        ]),
      ),
      storage: storage,
      modes: const [false],
      grow: false,
    );
  });
}
