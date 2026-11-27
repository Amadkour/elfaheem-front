// Redesign group T1, section Home (Tea1Home: the home, to-dos, inbox, transfers, meeting links): demo data from
// docs/redesign/CAST.md (أ. ماجد الشهري, maths class 7:30 – 8:20 pm, a boys' group) on top of FakeApi, for the layout
// tests and the review renders. Pattern of t2_fakes.dart.
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeLiveRoom;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/home/teacher/home_screen.dart';
import 'package:flutter_education_app/features/home/teacher/go_live_sheet.dart' show GoLiveButton;
import 'package:flutter_education_app/features/home/teacher/teacher_home_extra.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';
import 'package:flutter_education_app/features/live/meeting_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_api.dart';
import '../../ui/inbox_page_samples.dart' show inboxRoutes;

/// 09:00 Cairo today (07:00 UTC): the day the renders are taken on.
DateTime t1HomeNow() => DateTime.now().toUtc().copyWith(hour: 7, minute: 0, second: 0, millisecond: 0, microsecond: 0);

ScheduleSession t1Session(int id, String ar, String en, String start, String end, {bool ongoing = false, int inDays = 0, bool ar_ = true}) => ScheduleSession(
      scheduleId: id,
      courseId: id,
      courseName: ar_ ? ar : en,
      day: 'wednesday',
      dayLabel: 'wednesday',
      startTime: start,
      endTime: end,
      durationMinutes: 50,
      isToday: inDays == 0,
      isOngoing: ongoing,
      scheduledDate: t1HomeNow().add(Duration(days: inDays)),
      minutesUntilStart: ongoing ? null : 120,
      minutesUntilEnd: ongoing ? 25 : null,
      maxStudents: 18,
      dayLabelStr: 'wednesday',
    );

/// A day with the physics class running and two more after it (CAST: maths 7:30 – 8:20 pm).
List<ScheduleSession> t1BusyDay(bool ar) => [
      t1Session(2, 'الفيزياء ٢ ثانوي', 'Physics 2 S', '13:00', '13:50', ongoing: true, ar_: ar),
      t1Session(1, 'الرياضيات ٣ ثانوي، مجموعة أ', 'Maths 3 S, group A', '16:30', '17:20', ar_: ar),
      t1Session(3, 'قدرات كمي', 'Qudurat quantitative', '18:00', '18:50', ar_: ar),
    ];

/// Nothing today; the next session is in three days.
List<ScheduleSession> t1CalmDay(bool ar) => [t1Session(1, 'الرياضيات ٣ ثانوي، مجموعة أ', 'Maths 3 S, group A', '13:00', '13:50', inDays: 3, ar_: ar)];

TeacherCourse t1Course(int id, String ar, String en, int students, {bool published = true}) => TeacherCourse(
      id: id,
      imageUrl: '',
      totalHours: 0,
      type: 'live',
      progress: 0,
      expectedHours: 0,
      isPublished: published,
      studentsCount: students,
      sessionsCount: 24,
      titleAr: ar,
      titleEn: en,
    );

List<TeacherCourse> t1Courses() => [
      t1Course(1, 'الرياضيات ٣ ثانوي، مجموعة أ', 'Maths 3 S, group A', 18),
      t1Course(2, 'الفيزياء ٢ ثانوي', 'Physics 2 S', 9),
      t1Course(3, 'قدرات كمي', 'Qudurat quantitative', 10),
      t1Course(4, 'تحصيلي رياضيات', 'Tahsili maths', 12),
    ];

TodoItem t1Todo(String key, String kind, String priority, String titleAr, String titleEn, String whyAr, String whyEn,
        {String? course = 'الرياضيات ٣ ثانوي، مجموعة أ', int days = 3, bool? returned}) =>
    TodoItem(
      key: key,
      kind: kind,
      priority: priority,
      score: 70,
      titleAr: titleAr,
      titleEn: titleEn,
      whyAr: whyAr,
      whyEn: whyEn,
      courseId: 1,
      courseName: course,
      at: DateTime.now().toUtc().subtract(Duration(days: days)),
      action: const {'type': 'course', 'course_id': 1},
    );

TodoList t1TodoList() => TodoList(
      total: 9,
      high: 2,
      items: [
        t1Todo('grading:1', 'grading', 'high', 'صحّح ٦ تسليمات لواجب الدوال الأسية', 'Grade 6 submissions of the exponential functions homework',
            'أقدم تسليم صار له ٣ أيام، و٦ من ٨ طلاب سلّموا.', 'The oldest was handed in 3 days ago, and 6 of 8 students submitted.'),
        t1Todo('attendance:1', 'attendance_missing', 'high', 'سجّل حضور حصة أمس', "Log yesterday's attendance",
            'حصة «المتتابعات الحسابية» خلصت بدون حضور. تقدر تسجّله يدويًا الحين.', 'The "Arithmetic sequences" class ended with no attendance. You can log it by hand now.',
            days: 1),
        t1Todo('requests:1', 'enrollment_requests', 'medium', 'ردّ على ٣ طلبات التحاق', 'Answer 3 join requests', 'أقدمها من اليوم.', 'The oldest is from today.', days: 0),
      ],
    );

TeacherHomeExtra t1HomeExtra({TodoList? todo, bool payout = true}) => TeacherHomeExtra.fromJson({
      'pending': {'attendance_missing': 1, 'grading': 6, 'materials_missing': 0, 'enrollment_requests': 3},
      'teaching_courses': 4,
      'earnings': {'month': 12450.0, if (payout) 'pending_payout': 3200},
      'inbox_preview': [
        {'key': 'f1', 'kind': 'form', 'segment': 'todo', 'title': 'استمارة اعتماد الدرجات', 'subtitle': 'قسم الرياضيات', 'urgency': 'due_soon'},
      ],
      'notifications_unread': 5,
    });

List<MeLiveRoom> t1LiveRooms() => [
      MeLiveRoom(
        kind: 'meeting',
        id: 9,
        title: 'تنسيق اختبارات منتصف الفصل لقسم الرياضيات',
        meetingId: 9,
        hostName: 'أ. نواف القحطاني',
        startedAt: t1HomeNow().subtract(const Duration(minutes: 4)),
      ),
    ];

/// The state of the home the golden / layout tests draw.
enum T1HomeState { busy, calm, first }

/// TeacherHomeBody over the CAST day, with the real hero head (TeacherGreeting).
Widget t1HomeBody(T1HomeState state, {bool ar = true, bool loading = false, String? error}) {
  final first = state == T1HomeState.first;
  final calm = state == T1HomeState.calm;
  final courses = first ? <TeacherCourse>[] : t1Courses();
  final schedule = first ? <ScheduleSession>[] : (calm ? t1CalmDay(ar) : t1BusyDay(ar));
  final todo = state == T1HomeState.busy ? t1TodoList() : const TodoList(items: [], total: 0, high: 0);
  final pending = state == T1HomeState.busy ? const {'attendance_missing': 1, 'grading': 6, 'enrollment_requests': 3} : const <String, int>{};
  final line = teacherHeroLine(
    name: 'ماجد الشهري',
    schedule: schedule,
    courses: courses,
    pending: pending,
    todoCount: todo.totalCount,
    payoutWaiting: !first,
  );
  return TeacherHomeBody(
    loading: loading,
    error: error,
    now: t1HomeNow(),
    liveNow: state == T1HomeState.busy ? t1LiveRooms() : const [],
    stats: first ? const TeacherStats() : const TeacherStats(totalStudents: 74, totalCourses: 4, overallRating: 4.8),
    schedule: schedule,
    pending: pending,
    courses: courses,
    extra: first ? null : t1HomeExtra(),
    todo: first ? null : todo,
    onTab: (_) {},
    onOpenCourse: (_) {},
    onOpenCourseId: (_) {},
    onNewCourse: () {},
    onOpenEarnings: () {},
    onOpenInbox: () {},
    onOpenTransfers: () {},
    onOpenMeetings: () {},
    onSetupProfile: () {},
    showFeeds: false,
    greeting: TeacherGreeting(
      name: 'ماجد الشهري',
      title: line.title,
      subtitle: line.subtitle,
      goLive: GoLiveButton(live: line.live, block: true, onTap: () {}),
      helpPageId: null,
    ),
  );
}

/// A to-do list for the full page: two urgent, three soon, one for when there is time.
TodoList t1TodoPage() => TodoList(
      items: [
        ...t1TodoList().items,
        t1Todo('students:1', 'at_risk', 'medium', 'تابع طلاب معرّضين للتعثر', 'Check on students at risk', 'غابوا عن أغلب الدروس.', 'They missed most lessons.', days: 2),
        t1Todo('content:1', 'materials_missing', 'low', 'أضف ملف حصة الأسبوع', "Add the week's lesson file", 'ما فيه مواد للحصة القادمة.', 'No materials for the next class.', days: 1),
      ],
    );

/// The meeting links of the demo day: one live, two coming, one ended.
MeetingLinksData t1Links() {
  final now = DateTime.now().toUtc();
  MeetingLinkItem item(MeetingLinkStatus s, int id, String title, {bool host = true, Duration at = Duration.zero, bool guest = true, bool session = false}) => MeetingLinkItem(
        kind: session ? 'session' : 'meeting',
        refId: id,
        title: title,
        status: s,
        appLink: 'https://nextbrain.site/s/meeting/$id',
        startsAt: now.add(at),
        endsAt: now.add(at + const Duration(minutes: 50)),
        isHost: host,
        myStatus: host ? 'owner' : 'accepted',
        guest: guest ? MeetingGuestLink(url: 'https://nextbrain.site/live/abcdefghijklmnop', hasPin: id.isEven, direct: !id.isEven, guestsJoined: 0, active: true) : null,
      );
  return MeetingLinksData([
    item(MeetingLinkStatus.live, 1, 'الفيزياء ٢ ثانوي: مراجعة الفصل الثالث', session: true),
    item(MeetingLinkStatus.scheduled, 2, 'الرياضيات ٣ ثانوي: حل أسئلة الاختبار', at: const Duration(hours: 9)),
    item(MeetingLinkStatus.scheduled, 3, 'تنسيق اختبارات منتصف الفصل', host: false, at: const Duration(days: 1), guest: false),
    item(MeetingLinkStatus.ended, 4, 'اجتماع أولياء الأمور', at: const Duration(days: -2)),
  ]);
}

class T1FakeLinksApi extends MeetingLinksApi {
  const T1FakeLinksApi();
  @override
  Future<MeetingLinksData> load() async => t1Links();
}

/// Pending bank transfers of the demo day (the page's own endpoint).
Map<String, dynamic> t1Transfers() => {
      'total': 3,
      'items': [
        for (final (i, s) in const [('راكان الحربي', 440.7), ('فيصل العنزي', 390.0), ('ليث الدوسري', 150.0)].indexed)
          {
            'payment_id': 500 + i,
            'course_id': 41,
            'student_id': 101 + i,
            'course_name': 'الفيزياء ٢ ثانوي',
            'student_name': s.$1,
            'method': 'bank_transfer',
            'amount': s.$2,
            'currency': 'SAR',
            'sender_name': 'خالد الحربي',
            'sender_phone': '+966552314487',
            'transfer_reference': 'FT2611240037$i',
            'proof_image_url': '',
            'submitted_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
            'status': 'pending',
            'plan': 'yearly',
            'course_price': s.$2 - 50.7,
          },
      ],
    };

Map<String, FakeHandler> t1HomeRoutes() => {
      ...inboxRoutes(),
      'GET /api/v1/payments/transfers/pending': (_) => t1Transfers(),
    };

Future<MyAuthProvider> t1HomeSetUp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'ماجد الشهري', 'gmail': 'teacher@example.test', 'role': 'teacher'});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

FakeApi t1HomeApi({Map<String, FakeHandler>? extra}) => FakeApi({...t1HomeRoutes(), ...?extra}, latency: Duration.zero);
