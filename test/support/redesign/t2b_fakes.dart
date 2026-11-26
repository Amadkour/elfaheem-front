// Redesign group T2b (teacher: schedule, account, complaints, messages): demo data from docs/redesign/CAST.md
// (أ. ماجد الشهري's week: his maths group B live on Tuesday 24 Nov 2026 at 7:30 pm, a class-plan meeting at 9 pm,
// the functions quiz closing at 10:15 pm, Qudurat on Sunday and Wednesday at 4 pm) for the layout tests and renders.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/calendar/calendar_api.dart';

import '../fake_api.dart';
import 't2_fakes.dart';

/// The teacher signed in over FakeApi: T2's routes, [extra] on top, an empty answer for anything else.
Future<void> t2bSetUp({Map<String, FakeHandler>? extra}) async {
  await t2SetUp(FakeApi({...t2Routes(), 'GET /api/v1/live/meeting/*': (_) => <dynamic>[], 'POST /api/v1/auth/teacher-documents/overview': (_) => t2bDocs(), 'GET /api/v1/me/public-profile': (_) => t2bPublic(), 'GET /api/v1/complaints': (_) => t2bComplaints(), ...?extra},
      latency: Duration.zero, fallback: (_) => <String, dynamic>{}));
}

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Tuesday 24 Nov 2026, [h]:[m] on the platform's wall clock, [day] days later.
DateTime t2bWall(int day, int h, [int m = 0]) => DateTime(2026, 11, 24 + day, h, m);

/// "Now": 7:40 pm on Tuesday, ten minutes into the live maths class.
DateTime get t2bNow => AppTime.fromZone(t2bWall(0, 19, 40)).toUtc();

String _iso(DateTime wall) => AppTime.fromZone(wall).toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> _ev(String id, String source, DateTime s, DateTime e, String title,
        {String? sub, int? course, String? mode, int? meeting, String? status, bool owner = false}) =>
    {
      'id': id,
      'source': source,
      'title': title,
      'subtitle': sub,
      'starts_at': _iso(s),
      'ends_at': _iso(e),
      'course_id': course,
      'mode': mode,
      'meeting_id': meeting,
      'my_status': status,
      'is_owner': owner,
      'editable': owner,
    };

/// The teacher's week, as GET /me/calendar answers it.
List<Map<String, dynamic>> t2bWeek() => [
      _ev('session:1', 'course_session', t2bWall(-2, 16), t2bWall(-2, 16, 50), _t('قدرات كمي', 'Qudurat quantitative'), course: 44, mode: 'online'),
      _ev('session:2', 'course_session', t2bWall(0, 19, 30), t2bWall(0, 20, 20), _t('الرياضيات ٣ ث، مجموعة ب', 'Maths 3 S, group B'),
          sub: _t('٧ من ٨ طلاب داخلين', '7 of 8 students in'), course: 42, mode: 'online'),
      _ev('meeting:5', 'meeting', t2bWall(0, 21), t2bWall(0, 22), _t('مراجعة خطة الفصل', 'Class plan review'),
          mode: 'online', meeting: 5, status: 'accepted', owner: true),
      _ev('exam:3', 'exam', t2bWall(0, 22, 15), t2bWall(0, 23), _t('اختبار الدوال يقفل', 'Functions quiz closes'),
          sub: _t('١٤ من ١٦ سلّموا', '14 of 16 handed in'), course: 41),
      _ev('session:4', 'course_session', t2bWall(1, 16), t2bWall(1, 16, 50), _t('قدرات كمي', 'Qudurat quantitative'), course: 44, mode: 'online'),
      _ev('exam:6', 'exam', t2bWall(2, 15, 30), t2bWall(2, 17), _t('تحصيلي تجريبي', 'Tahsili mock'), sub: _t('٩ طلاب', '9 students'), course: 43),
      _ev('meeting:7', 'meeting', t2bWall(2, 20), t2bWall(2, 20, 45), _t('اجتماع قسم الرياضيات', 'Maths department meeting'),
          sub: _t('من أ. خالد العتيبي', 'From Mr Khaled Alotaibi'), mode: 'online', meeting: 7, status: 'pending'),
      _ev('meeting:8', 'meeting', t2bWall(4, 16), t2bWall(4, 16, 30), _t('استشارة', 'Consultation'), mode: 'online', meeting: 8, status: 'accepted', owner: true),
    ];

class T2bCalApi extends RemoteCalendarApi {
  const T2bCalApi({this.empty = false});

  final bool empty;

  @override
  Future<dynamic> feed(String start, String end, {int? orgId, int? deptId, bool detail = false}) async =>
      {'items': empty ? const [] : t2bWeek(), 'pending_invites': empty ? 0 : 1};

  @override
  Future<dynamic> meeting(int id) async => t2bMeeting();

  @override
  Future<dynamic> people({int? orgId, String? q}) async => {'users': const [], 'courses': const []};

  @override
  Future<dynamic> busy(Map<String, dynamic> body) async => {'busy': const []};
}

/// The class-plan meeting (Tea2Schedule meet): the teacher organizes it, four colleagues invited, one proposes Wednesday.
Map<String, dynamic> t2bMeeting() {
  Map<String, dynamic> who(int id, String ar, String en, String status, {bool propose = false}) => {
        'id': id,
        'status': status,
        'user': {'id': 20 + id, 'name': _t(ar, en)},
        if (propose) 'proposed_start': _iso(t2bWall(1, 21)),
        if (propose) 'proposed_end': _iso(t2bWall(1, 22)),
      };
  return {
    'id': 5,
    'title': _t('مراجعة خطة الفصل', 'Class plan review'),
    'starts_at': _iso(t2bWall(0, 21)),
    'ends_at': _iso(t2bWall(0, 22)),
    'mode': 'online',
    'status': 'scheduled',
    'is_owner': true,
    'my_status': 'accepted',
    'can_join': true,
    'owner': {'id': 7, 'name': _t('أنت', 'You')},
    'counts': {'accepted': 1, 'proposed': 1, 'pending': 1, 'declined': 1},
    'attendees': [
      who(1, 'أ. خالد العتيبي', 'Mr Khaled Alotaibi', 'accepted'),
      who(2, 'أ. فهد الدوسري', 'Mr Fahad Aldosari', 'proposed', propose: true),
      who(3, 'أ. سلمان المطيري', 'Mr Salman Almutairi', 'pending'),
      who(4, 'أ. عبدالله الزهراني', 'Mr Abdullah Alzahrani', 'declined'),
    ],
  };
}

Future<dynamic> t2bWeekly(String path) async => {'all_courses': const []};

/// The teacher's verification documents (Tea2Account docs): two approved, one in review, one returned.
Map<String, dynamic> t2bDocs() {
  Map<String, dynamic> req(int id, String ar, String en, String icon, String? status, {String? file, String? reason}) => {
        'type_id': id,
        'title': _t(ar, en),
        'icon_name': icon,
        'is_required': true,
        if (status != null)
          'document': {
            'id': id,
            'required_document_type_id': id,
            'title': _t(ar, en),
            'file_url': 'https://example.test/$id.pdf',
            'file_name': file,
            'file_type': 'pdf',
            'status': status,
            'rejection_reason': reason,
            'uploaded_at': '2026-09-02T09:00:00',
          },
      };
  return {
    'requirements': [
      req(1, 'الهوية الوطنية', 'National ID', 'badge', 'approved', file: 'national_id.pdf'),
      req(2, 'شهادة البكالوريوس', "Bachelor's degree", 'school', 'approved', file: 'bachelor_maths.pdf'),
      req(3, 'الرخصة المهنية للمعلمين', "Teacher's licence", 'workspace_premium', 'pending', file: 'licence.jpg'),
      req(4, 'شهادة الخبرة', 'Experience letter', 'description', 'rejected',
          file: 'experience.pdf', reason: _t('الختم غير واضح، ارفع نسخة أوضح.', 'The stamp is not clear; upload a clearer copy.')),
    ],
    'custom_documents': const [],
  };
}

/// The owner's view of the public page (GET /me/public-profile).
Map<String, dynamic> t2bPublic() => {
      'settings': {
        'is_public': true,
        'fields': {'bio': true, 'stats': true, 'courses': true, 'growth': true, 'reviews': true},
      },
      'available': ['bio', 'stats', 'courses', 'growth', 'reviews'],
      'username': 'majed.math',
      'username_confirmed': true,
      'live': true,
      'link': 'https://nextbrain.site/@majed.math',
      'profile': {
        'id': 7,
        'kind': 'teacher',
        'name': _t('أ. ماجد الشهري', 'Mr Majed Alshehri'),
        'username': 'majed.math',
        'headline': _t('معلم رياضيات، ثانوي وقدرات وتحصيلي', 'Maths teacher: secondary, Qudurat and Tahsili'),
        'bio': _t('معلم رياضيات من ١٢ سنة، أدرّس الثانوي والقدرات والتحصيلي.', 'A maths teacher for 12 years: secondary, Qudurat and Tahsili.'),
        'experience_years': 12,
        'courses_count': 4,
        'sections': ['bio', 'stats', 'courses'],
        'stats': {'students': 640, 'live_sessions': 312, 'hours': 180, 'certificates': 215, 'rating': 4.8, 'reviews': 212},
        'courses': const [],
      },
    };

/// The teacher's complaints (Tea2Account complaints): one waiting for him, one open, two closed.
Map<String, dynamic> t2bComplaints() {
  Map<String, dynamic> c(int id, String ar, String en, String cat, String status, String at, {bool unread = false}) => {
        'id': id,
        'user_id': 7,
        'user_name': 'ماجد الشهري',
        'title': _t(ar, en),
        'description': _t(ar, en),
        'category': cat,
        'status': status,
        'priority': 'medium',
        'created_at': at,
        'updated_at': at,
        'is_read_by_user': !unread,
        'replies_count': unread ? 1 : 0,
      };
  return {
    'items': [
      c(4821, 'مبلغ اشتراك طالب ما انضاف لأرباحي', "A student's fee is missing from my earnings", 'payment', 'in_progress', '2026-11-23T10:00:00', unread: true),
      c(4790, 'الصوت يقطع في القاعة على الآيباد', 'Sound drops in the room on iPad', 'technical', 'open', '2026-11-21T10:00:00'),
      c(4652, 'طلب تعديل اسم دورة منشورة', 'Rename a published course', 'course_content', 'closed', '2026-11-12T10:00:00'),
      c(4510, 'طالب ينشر محتوى الدورة', 'A student is sharing the course content', 'student', 'closed', '2026-11-02T10:00:00'),
    ],
  };
}
