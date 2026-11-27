// Redesign group P (parent): the CAST family (docs/redesign/CAST.md) on top of FakeApi, for the layout tests and the
// review renders — أحمد سعد العنزي and his children ريم (الثاني المتوسط, on track), فيصل (الثاني الثانوي, watch)
// and سارة (الرابع الابتدائي, waiting for the parent's consent). Times are relative to now, so "today" and "live"
// hold whenever the renders run.
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_api.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

DateTime get _now => DateTime.now().toUtc();

const paReem = 4, paFaisal = 5, paSara = 6;

Map<String, dynamic> paChildRow(int id) => switch (id) {
      paReem => {
          'id': paReem, 'name': 'ريم العنزي', 'image_url': null, 'is_active': true, 'linked_at': '2026-09-12T09:00:00Z',
          'grade_name': 'الصف الثاني المتوسط', 'created_by_me': false, 'claimed': true, 'needs_consent': false,
        },
      paFaisal => {
          'id': paFaisal, 'name': 'فيصل العنزي', 'image_url': null, 'is_active': true, 'linked_at': '2026-09-12T09:00:00Z',
          'grade_name': 'الصف الثاني الثانوي', 'created_by_me': true, 'claimed': true, 'needs_consent': false,
        },
      _ => {
          'id': paSara, 'name': 'سارة العنزي', 'image_url': null, 'is_active': true, 'linked_at': '2026-11-20T09:00:00Z',
          'grade_name': 'الصف الرابع الابتدائي', 'created_by_me': true, 'claimed': false, 'needs_consent': true,
        },
    };

Map<String, dynamic> _event(String id, String title, String sub, DateTime start, {String mode = 'online', String source = 'course_session'}) => {
      'id': id,
      'source': source,
      'title': title,
      'subtitle': sub,
      'starts_at': _iso(start),
      'ends_at': _iso(start.add(const Duration(minutes: 50))),
      'mode': mode,
      'course_id': 1,
    };

Map<String, dynamic> _pulse(String status, {required int rate, required double avg, int missingHw = 0, List<Map<String, dynamic>> insights = const []}) => {
      'status': status,
      'week': {
        'scheduled': 6, 'attended': (6 * rate / 100).round(), 'missed': rate >= 100 ? 0 : 1, 'rate': rate,
        'homework_due': 8, 'homework_missing': missingHw, 'homework_due_soon': 1, 'active_days': 5,
      },
      'attendance_trend': [for (final r in [88, 92, 100, 84, 96, rate]) {'rate': r}],
      'grades': {
        'avg': avg, 'prev_avg': avg - 4, 'class_avg': 74.0, 'mine_vs_class': avg, 'count': 6, 'failed': 0,
        'trend': [for (final r in [78, 82, 80, 84, 85, avg]) {'avg': r}],
      },
      'subjects': [
        {'course_id': 1, 'name_ar': 'الرياضيات، مجموعة أ', 'name_en': 'Maths, group A', 'progress': 84.0, 'avg': 92.0, 'class_avg': 78.0, 'missed': 0, 'tone': 'strength', 'teacher': {'id': 31, 'name': 'أ. ماجد الشهري'}},
        {'course_id': 2, 'name_ar': 'العلوم', 'name_en': 'Science', 'progress': 61.0, 'avg': 71.0, 'class_avg': 75.0, 'missed': 1, 'tone': 'focus', 'teacher': {'id': 32, 'name': 'أ. فهد المطيري'}},
        {'course_id': 3, 'name_ar': 'الإنجليزي', 'name_en': 'English', 'progress': 77.0, 'avg': 90.0, 'class_avg': 78.0, 'missed': 0, 'tone': 'steady', 'teacher': {'id': 33, 'name': 'أ. خالد العتيبي'}},
      ],
      'upcoming': [
        _event('u1', 'الرياضيات، مجموعة أ', 'أ. ماجد الشهري', _now.add(const Duration(hours: 2))),
        _event('u2', 'الإنجليزي', 'أ. خالد العتيبي', _now.add(const Duration(days: 1))),
        _event('u3', 'اختبار الرياضيات «المعادلات»', '', _now.add(const Duration(days: 4)), source: 'exam'),
        _event('u4', 'العلوم', 'أ. فهد المطيري', _now.add(const Duration(days: 5))),
      ],
      'roadmap': {'field': {'name_ar': 'العلوم', 'name_en': 'Science'}, 'done': 2, 'total': 5, 'next': {'name_ar': 'العلوم المتقدمة', 'name_en': 'Advanced science', 'progress': 0}},
      'insights': insights,
      'teachers': [
        {'id': 31, 'name': 'أ. ماجد الشهري', 'course_id': 1, 'course_ar': 'الرياضيات، مجموعة أ', 'course_en': 'Maths, group A'},
        {'id': 32, 'name': 'أ. فهد المطيري', 'course_id': 2, 'course_ar': 'العلوم', 'course_en': 'Science'},
        {'id': 33, 'name': 'أ. خالد العتيبي', 'course_id': 3, 'course_ar': 'الإنجليزي', 'course_en': 'English'},
      ],
    };

/// GET /api/v1/parent/overview: three children ([kids] = how many of them).
Map<String, dynamic> paOverview({int kids = 3, bool pulse = true}) {
  final today = _now;
  final reem = {
    'child': paChildRow(paReem),
    'today_sessions': [
      _event('s1', 'الرياضيات، مجموعة أ', 'أ. ماجد الشهري', today.subtract(const Duration(minutes: 10))),
      _event('s2', 'الإنجليزي', 'أ. خالد العتيبي', today.add(const Duration(hours: 3))),
    ],
    'attendance_pct_30d': 92,
    'latest_marks': [
      {'exam_id': 11, 'exam': 'اختبار الكسور', 'course_ar': 'الرياضيات', 'course_en': 'Maths', 'percentage': 92.0, 'passed': true},
      {'exam_id': 12, 'exam': 'الوحدة ٣', 'course_ar': 'الإنجليزي', 'course_en': 'English', 'percentage': 88.0, 'passed': true},
    ],
    'open_alerts': 2,
    'next_exam': {'id': 2, 'name': 'اختبار الرياضيات «المعادلات»', 'starts_at': _iso(today.add(const Duration(days: 4))), 'source': 'course'},
    'courses': 4,
    if (pulse)
      'pulse': _pulse('on_track', rate: 92, avg: 86, missingHw: 1, insights: [
        {'code': 'homework_missing', 'level': 'warn', 'params': {'count': 1}, 'action': {'kind': 'message_teacher', 'course_id': 2}},
        {'code': 'exam_soon', 'level': 'info', 'params': {'title': 'اختبار الرياضيات «المعادلات»', 'at': _iso(today.add(const Duration(days: 4)))}, 'action': {'kind': 'open_report'}},
        {'code': 'above_class', 'level': 'good', 'params': {'delta': 12}, 'action': null},
        {'code': 'open_alerts', 'level': 'info', 'params': {'count': 2}, 'action': {'kind': 'open_alerts'}},
      ]),
  };
  final faisal = {
    'child': paChildRow(paFaisal),
    'today_sessions': [
      _event('s3', 'الفيزياء ١، فردي', 'أ. فهد المطيري', today.add(const Duration(hours: 4))),
    ],
    'attendance_pct_30d': 81,
    'latest_marks': [
      {'exam_id': 21, 'exam': 'اختبار الوحدة ٢', 'course_ar': 'الفيزياء', 'course_en': 'Physics', 'percentage': 48.0, 'passed': false},
    ],
    'open_alerts': 3,
    'next_exam': null,
    'courses': 3,
    if (pulse)
      'pulse': _pulse('watch', rate: 81, avg: 61, missingHw: 2, insights: [
        {'code': 'failed_exams', 'level': 'warn', 'params': {'count': 1}, 'action': {'kind': 'message_teacher', 'course_id': 2}},
      ]),
  };
  final sara = {
    'child': paChildRow(paSara),
    'today_sessions': [],
    'attendance_pct_30d': null,
    'latest_marks': [],
    'open_alerts': 0,
    'next_exam': null,
    'courses': 2,
    if (pulse) 'pulse': {'status': 'quiet'},
  };
  return {
    'now': _iso(today),
    'timezone': 'Asia/Riyadh',
    'children': [reem, faisal, sara].take(kids).toList(),
    'alerts_total': kids == 0 ? 0 : 4,
    'requests': [if (kids == 0) {'id': 1, 'status': 'pending'}],
    'link_config': {'mode': 'easy'},
  };
}

Map<String, dynamic> paProfile(int id) => {
      'student': {'id': id, 'name': paChildRow(id)['name']},
      'overall': {'progress': 72, 'attendance': 92, 'exam_avg': 86},
      'courses': [
        {
          'course': {'id': 1, 'title': 'الرياضيات، مجموعة أ'},
          'progress': 84, 'attendance': {'rate': 88, 'attended': 22, 'held': 25},
          'exams': {'avg': 92, 'items': [{'name': 'اختبار الكسور', 'best_percentage': 92, 'attempts': 1, 'passed': true}]},
          'columns': [],
        },
        {
          'course': {'id': 2, 'title': 'العلوم'},
          'progress': 61, 'attendance': {'rate': 90, 'attended': 18, 'held': 20},
          'exams': {'avg': 71, 'items': []},
          'columns': [],
        },
        {
          'course': {'id': 3, 'title': 'الإنجليزي'},
          'progress': 77, 'attendance': {'rate': 100, 'attended': 12, 'held': 12},
          'exams': {'avg': 90, 'items': []},
          'columns': [],
        },
      ],
    };

Map<String, dynamic> _alert(String key, String prio, int child, String type, Duration ago, {bool unread = true}) => {
      'key': key,
      'type': type,
      'priority': prio,
      'unread': unread,
      'status': unread ? 'unread' : 'read',
      'at': _iso(_now.subtract(ago)),
      'child': {'id': child, 'name': paChildRow(child)['name']},
      'params': {'pct': 48, 'exam': 'اختبار الوحدة ٢', 'course_ar': 'الفيزياء', 'course_en': 'Physics', 'title': 'الروابط', 'days': 3, 'pass': 50},
    };

Map<String, dynamic> paAlerts() => {
      'items': [
        _alert('a1', 'high', paFaisal, 'failed_exam', const Duration(hours: 2)),
        _alert('a2', 'high', paFaisal, 'missed_session', const Duration(hours: 3)),
        _alert('a3', 'medium', paReem, 'missing_homework', const Duration(days: 1)),
        _alert('a4', 'medium', paReem, 'score_drop', const Duration(days: 2), unread: false),
        _alert('a5', 'medium', paFaisal, 'missing_homework', const Duration(days: 3), unread: false),
        _alert('a6', 'low', paReem, 'inactive', const Duration(days: 4), unread: false),
        _alert('a7', 'low', paFaisal, 'inactive', const Duration(days: 6)),
      ],
    };

/// One period of GET /api/v1/parent/reports for a child.
Map<String, dynamic> paReport({int score = 86, String tier = 'excellent'}) => {
      'start': '2026-11-22',
      'end': '2026-11-28',
      'days': List.generate(7, (i) => '2026-11-${22 + i}'),
      'summary': {
        'study_minutes': 400, 'active_days': 5, 'exams_avg_percentage': 86, 'exams_taken': 3, 'exams_passed': 3,
        'assignments_submitted': 7, 'materials_completed': 6, 'videos_completed': 4, 'weak_questions_open': 2,
        'certificates_earned': 1, 'sessions_attended': 6,
      },
      'previous_summary': {
        'study_minutes': 360, 'active_days': 4, 'exams_avg_percentage': 82, 'materials_completed': 4, 'videos_completed': 3,
      },
      'score': {
        'value': score,
        'tier': tier,
        'components': [
          {'key': 'attendance', 'value': 92, 'weight': 35},
          {'key': 'consistency', 'value': 88, 'weight': 20},
          {'key': 'performance', 'value': 86, 'weight': 30},
          {'key': 'homework', 'value': 75, 'weight': 15},
        ],
      },
      'attendance': {
        'rate': 92, 'scheduled': 6, 'attended': 6, 'late_count': 0, 'avg_late_minutes': 0, 'short_stays': 0,
        'avg_presence_percentage': 96, 'missed': [],
      },
      'homework': {'due': 8, 'on_time': 7, 'late': 0, 'missing': 1},
      'behavior': {
        'time_of_day': {'morning': 1, 'afternoon': 4, 'evening': 6, 'night': 1},
        'peak_slot': 'evening', 'days_since_last_activity': 0, 'weekday': [2, 3, 1, 2, 0, 1, 3], 'week_start': 6,
        'streak': 5, 'longest_streak': 9,
      },
      'trend': {
        'unit': 'day',
        'points': [for (var i = 0; i < 7; i++) {'label': '2026-11-${22 + i}', 'minutes': 40 + i * 8, 'activities': 2 + i % 3, 'exam_avg': 80 + i}],
      },
      'insights': [
        {'code': 'streak', 'level': 'good', 'params': {'days': 5}},
        {'code': 'stays_full', 'level': 'good', 'params': {'pct': 96}},
        {'code': 'exam_up', 'level': 'good', 'params': {'delta': 4, 'avg': 86}},
      ],
      'courses': [
        {'course_id': 1, 'name_ar': 'الرياضيات، مجموعة أ', 'name_en': 'Maths, group A', 'progress': 84, 'sessions': 2, 'minutes': 100, 'exam_avg': 92, 'missed': 0},
        {'course_id': 2, 'name_ar': 'العلوم', 'name_en': 'Science', 'progress': 61, 'sessions': 2, 'minutes': 100, 'exam_avg': 71, 'missed': 0},
      ],
      'exams': [
        {'exam': 'اختبار الكسور', 'course_ar': 'الرياضيات', 'course_en': 'Maths', 'course_id': 1, 'percentage': 92, 'passed': true, 'at': _iso(_now.subtract(const Duration(days: 2)))},
      ],
      'attendance_log': [
        {'session': 'المعادلات الخطية', 'course_ar': 'الرياضيات', 'course_en': 'Maths', 'course_id': 1, 'minutes': 45, 'at': _iso(_now.subtract(const Duration(days: 3)))},
      ],
      'assignments': [
        {'title': 'واجب الخلية ووظائفها', 'at': _iso(_now.subtract(const Duration(days: 2))), 'marks': null, 'total': 10},
      ],
    };

Map<String, dynamic> _reportChild(int id, int score, String tier) => {
      'student': {'id': id, 'name': paChildRow(id)['name']},
      'daily': paReport(score: score, tier: tier),
      'weekly': paReport(score: score, tier: tier),
      'monthly': paReport(score: score, tier: tier),
    };

Map<String, dynamic> paReports() => {
      'children': [_reportChild(paReem, 86, 'excellent'), _reportChild(paFaisal, 61, 'fair'), _reportChild(paSara, 40, 'attention')],
    };

/// GET /api/v1/edu/catalog?country=SA: two stages of the Saudi curriculum, enough for the child form.
Map<String, dynamic> paCatalog() => {
      'country': 'SA',
      'stages': [
        {'id': 1, 'key': 'primary', 'name_ar': 'ابتدائي', 'name_en': 'Primary', 'grades': [
          for (final (i, n) in ['الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس'].indexed)
            {'id': 10 + i, 'name_ar': 'الصف $n الابتدائي', 'name_en': 'Grade ${i + 1}', 'order': i},
        ]},
        {'id': 2, 'key': 'intermediate', 'name_ar': 'متوسط', 'name_en': 'Intermediate', 'grades': [
          for (final (i, n) in ['الأول', 'الثاني', 'الثالث'].indexed)
            {'id': 20 + i, 'name_ar': 'الصف $n المتوسط', 'name_en': 'Grade ${i + 7}', 'order': i},
        ]},
        {'id': 3, 'key': 'secondary', 'name_ar': 'ثانوي', 'name_en': 'Secondary', 'grades': [
          for (final (i, n) in ['الأول', 'الثاني', 'الثالث'].indexed)
            {'id': 30 + i, 'name_ar': 'الصف $n الثانوي', 'name_en': 'Grade ${i + 10}', 'order': i},
        ]},
      ],
      'subjects': [
        for (final (i, s) in [('math', 'الرياضيات', 'Maths'), ('science', 'العلوم', 'Science'), ('english', 'الإنجليزي', 'English'), ('arabic', 'لغتي', 'Arabic'), ('social', 'الدراسات الاجتماعية', 'Social studies'), ('digital', 'المهارات الرقمية', 'Digital skills')].indexed)
          {'id': 100 + i, 'key': s.$1, 'name_ar': s.$2, 'name_en': s.$3, 'grade_ids': [10, 11, 12, 13, 14, 15, 20, 21, 22, 30, 31, 32]},
      ],
    };

/// The parent's routes.
Map<String, FakeHandler> paRoutes({int kids = 3, bool pulse = true}) => {
      'GET /api/v1/parent/overview': (_) => paOverview(kids: kids, pulse: pulse),
      'GET /api/v1/parent/children': (_) => [for (final id in [paReem, paFaisal, paSara].take(kids)) paChildRow(id)],
      for (final id in [paReem, paFaisal, paSara]) 'GET /api/v1/parent/children/$id/profile': (_) => paProfile(id),
      for (final id in [paReem, paFaisal, paSara]) 'GET /api/v1/parent/children/$id/report': (_) => _reportChild(id, 86, 'excellent'),
      for (final id in [paReem, paFaisal, paSara])
        'GET /api/v1/parent/children/$id/login-code': (_) => id == paSara ? {'active': true, 'expires_at': _iso(_now.add(const Duration(hours: 40))), 'seconds_left': 144000} : {'active': false},
      'POST /api/v1/parent/children': (_) => {
            'child': {'id': 9, 'name': 'فيصل العنزي', 'first_name': 'فيصل', 'last_name': 'العنزي', 'username': 'faisal.alanazi', 'grade_name_ar': 'الصف الثاني الثانوي', 'grade_name_en': 'Grade 11', 'created_by_me': true, 'claimed': false},
            'login_code': {'code': '482917', 'code_display': '482 917', 'expires_at': _iso(_now.add(const Duration(hours: 48))), 'ttl_seconds': 172800, 'share_text_ar': 'كود دخول فيصل: 482 917', 'share_text_en': "Faisal's sign-in code: 482 917"},
          },
      'GET /api/v1/parent/link/config': (_) => {'mode': 'easy', 'fields': [], 'documents': []},
      'GET /api/v1/parent/link/requests': (_) => [if (kids == 0) {'id': 1, 'status': 'pending', 'student_name': 'نوف العنزي', 'created_at': _iso(_now.subtract(const Duration(days: 1)))}],
      'GET /api/v1/parent/alerts': (_) => paAlerts(),
      'GET /api/v1/parent/reports': (_) => paReports(),
      'GET /api/v1/org/parent/children': (_) => {'children': []},
      'GET /api/v1/my-payments': (_) => {
            'items': [
              {'id': 1191, 'student_id': 3, 'course_id': 1, 'amount': 449, 'status': 'completed', 'payment_method': 'mada', 'transaction_id': 'TX-88213', 'meta_data': {'currency': 'SAR'}, 'paid_at': _iso(_now.subtract(const Duration(days: 6))), 'created_at': _iso(_now.subtract(const Duration(days: 6)))},
              {'id': 1184, 'student_id': 3, 'course_id': 3, 'amount': 199, 'status': 'completed', 'payment_method': 'card', 'meta_data': {'currency': 'SAR'}, 'paid_at': _iso(_now.subtract(const Duration(days: 11))), 'created_at': _iso(_now.subtract(const Duration(days: 11)))},
              {'id': 1172, 'student_id': 3, 'course_id': 2, 'amount': 199, 'status': 'pending', 'payment_method': 'bank_transfer', 'meta_data': {'currency': 'SAR'}, 'created_at': _iso(_now.subtract(const Duration(days: 2)))},
            ],
            'total': 3,
          },
      'GET /api/v1/edu/countries': (_) => [
            {'code': 'SA', 'name_ar': 'السعودية', 'name_en': 'Saudi Arabia', 'default': true},
            {'code': 'KW', 'name_ar': 'الكويت', 'name_en': 'Kuwait'},
            {'code': 'AE', 'name_ar': 'الإمارات', 'name_en': 'UAE'},
          ],
      'GET /api/v1/booking/options': (_) => {
            'subject': {'id': 104, 'name_ar': 'الدراسات الاجتماعية', 'name_en': 'Social studies'},
            'class_minutes': 50, 'group_size': {'min': 5, 'max': 10}, 'currency': 'SAR', 'price_period': 'month',
            'modes': [{'key': 'remote', 'available': true}, {'key': 'in_person', 'available': false, 'reason': 'no_centre_here'}],
            'kinds': [{'key': 'group', 'available': true, 'prices': {'remote': 199}}, {'key': 'individual', 'available': true, 'prices': {'remote': 449}}],
          },
      'GET /api/v1/edu/catalog': (_) => paCatalog(),
      'GET /api/v1/notifications': (_) => {'items': [], 'unread': 5},
    };

Future<MyAuthProvider> paSetUp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 3, 'name': 'أحمد سعد العنزي', 'gmail': 'ahmed.alenezi@example.test', 'phone': '+966554127781', 'role': 'parent'});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

FakeApi paApi({int kids = 3, bool pulse = true, Map<String, FakeHandler>? extra}) => FakeApi(
      {...paRoutes(kids: kids, pulse: pulse), ...?extra},
      latency: kDebugMode ? const Duration(milliseconds: 10) : Duration.zero,
      fallback: (_) => const <String, dynamic>{},
    );
