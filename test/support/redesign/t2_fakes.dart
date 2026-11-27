// Redesign group T2 (teacher: analysis, money, certificates, exams, teaching): demo data from docs/redesign/CAST.md
// (أ. ماجد الشهري, his maths and physics groups) on top of FakeApi, for the layout tests and the review renders.
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_api.dart';

/// The teacher's four classes (CAST: maths and qudurat, boys' groups).
List<Map<String, dynamic>> t2CourseJson() => [
      {'id': 41, 'name_ar': 'الرياضيات ٣ ث، أ', 'name_en': 'Maths 3 S, A', 'students_count': 18, 'sessions_count': 24},
      {'id': 42, 'name_ar': 'الرياضيات ٣ ث، ب', 'name_en': 'Maths 3 S, B', 'students_count': 16, 'sessions_count': 24},
      {'id': 43, 'name_ar': 'تحصيلي رياضيات', 'name_en': 'Tahsili maths', 'students_count': 12, 'sessions_count': 16},
      {'id': 44, 'name_ar': 'قدرات كمي', 'name_en': 'Qudurat quantitative', 'students_count': 10, 'sessions_count': 12},
    ];

/// The class snapshots of GET /api/v1/data-lab/overview.
Map<String, dynamic> t2Overview() => {
      'items': [
        {
          'course_id': 41,
          'enabled': true,
          'progress': 71,
          'attendance': 88,
          'exam_avg': 74,
          'exam_pass_rate': 82,
          'at_risk': 3,
          'published_columns': 2,
          'at_risk_preview': [
            {'student_id': 101, 'name': 'تركي السبيعي', 'attendance': 44, 'exam_avg': 35},
            {'student_id': 102, 'name': 'عبدالله الدوسري', 'attendance': 72, 'exam_avg': 41},
          ],
        },
        {
          'course_id': 42,
          'enabled': true,
          'progress': 64,
          'attendance': 69,
          'exam_avg': 58,
          'exam_pass_rate': 54,
          'at_risk': 2,
          'published_columns': 1,
          'at_risk_preview': [
            {'student_id': 103, 'name': 'سلطان العمري', 'attendance': 52, 'exam_avg': 61},
          ],
        },
        {
          'course_id': 43,
          'enabled': true,
          'progress': 58,
          'attendance': 81,
          'exam_avg': 66,
          'exam_pass_rate': 70,
          'at_risk': 1,
          'published_columns': 0,
          'at_risk_preview': [],
        },
        {
          'course_id': 44,
          'enabled': true,
          'progress': 79,
          'attendance': 90,
          'exam_avg': 84,
          'exam_pass_rate': 91,
          'at_risk': 0,
          'published_columns': 3,
          'at_risk_preview': [],
        },
      ],
    };

/// Payouts: what can be withdrawn, two accounts, one request in progress.
Map<String, dynamic> t2PayoutStatus() => {
      'allowed': true,
      'min_amount': 200,
      'methods': [
        {'id': 'bank_account', 'label_ar': 'حساب بنكي', 'label_en': 'Bank account', 'automatic': false},
      ],
      'accounts': [
        {
          'id': 1,
          'method': 'bank_account',
          'label': 'مصرف الراجحي',
          'is_default': true,
          'details': {'bank_name': 'مصرف الراجحي', 'account_name': 'ماجد الشهري', 'iban': 'SA4480000000000000002207'},
        },
        {
          'id': 2,
          'method': 'bank_account',
          'label': 'البنك الأهلي',
          'details': {'bank_name': 'البنك الأهلي', 'account_name': 'ماجد الشهري', 'iban': 'SA0310000000608010167519'},
        },
      ],
      'summary': {'pending_balance': 8420.5, 'withdrawn_total': 36200, 'pending_withdrawal': 2360, 'total_net': 46980},
    };

Map<String, dynamic> t2Withdrawals() => {
      'items': [
        {
          'id': 9,
          'amount': 2360,
          'status': 'pending',
          'requested_at': '2026-11-22T09:00:00',
          'payout_method': 'bank_account',
          'bank_snapshot': {'method': 'bank_account', 'iban': 'SA4480000000000000002207'},
        },
        {
          'id': 8,
          'amount': 5000,
          'status': 'paid',
          'requested_at': '2026-10-28T09:00:00',
          'payout_method': 'bank_account',
          'bank_reference': 'TRX-55120',
          'bank_snapshot': {'method': 'bank_account', 'iban': 'SA4480000000000000002207'},
        },
      ],
    };

/// Certificate requests (three students finished the course).
List<Map<String, dynamic>> t2CertRequests() => [
      for (final (i, name, p) in [(1, 'راكان الحربي', 100), (2, 'جواد الغامدي', 100), (3, 'تركي السبيعي', 86)])
        {
          'request_id': i,
          'certificate_id': 5,
          'certificate_title': 'شهادة إتمام',
          'course_id': 41,
          'course_name_ar': 'الرياضيات ٣ ث، أ',
          'course_name_en': 'Maths 3 S, A',
          'student_id': 100 + i,
          'student_name': name,
          'progress': p,
          'status': 'pending',
          'created_at': '2026-11-24T08:00:00Z',
        },
    ];

List<Map<String, dynamic>> t2CertDesigns() => [
      {'id': 1, 'name': 'الكلاسيكي الذهبي', 'orientation': 'landscape', 'can_edit': true, 'langs': ['ar', 'en'], 'apply_all': true},
      {'id': 2, 'name': 'الليلي', 'orientation': 'landscape', 'can_edit': true, 'langs': ['ar']},
    ];

Map<String, dynamic> t2DeviceRequests() => {
      'items': [
        {
          'id': 1,
          'student_id': 101,
          'student_name': 'راكان الحربي',
          'course_id': 41,
          'course_name': 'الرياضيات ٣ ث',
          'new_device_name': 'iPhone 15',
          'created_at': '2026-11-25T09:00:00Z',
        },
        {
          'id': 2,
          'student_id': 102,
          'student_name': 'نواف القحطاني',
          'course_id': 43,
          'course_name': 'تحصيلي رياضيات',
          'new_device_name': 'Galaxy S24',
          'created_at': '2026-11-24T09:00:00Z',
        },
      ],
    };

Map<String, dynamic> t2Ads() => {
      'settings': {'price_per_day': 20, 'requires_approval': true},
      'items': [
        {
          'id': 1,
          'title': 'جهّز للتحصيلي مع أ. ماجد',
          'body': 'يفتح دورة تحصيلي رياضيات',
          'media_type': 'image',
          'status': 'approved',
          'is_active': true,
          'impressions': 8200,
          'clicks': 612,
          'ctr': 7.5,
        },
        {
          'id': 2,
          'title': 'القدرات الكمي في ٤ أسابيع',
          'body': 'يفتح دورة قدرات كمي',
          'media_type': 'video',
          'status': 'approved',
          'is_active': true,
          'impressions': 4200,
          'clicks': 248,
          'ctr': 5.9,
        },
      ],
    };

Map<String, dynamic> t2Flags() => {
      'thresholds': {'min_students': 3, 'min_wrong_tries': 2},
      'items': [
        {
          'question_id': 1,
          'exam_id': 7,
          'exam_name': 'اختبار الدوال الأسية',
          'title': 'وش حل المعادلة 2^(x+1) = 32 ؟',
          'correct_answer': 'x = 4',
          'students_failed': 12,
          'max_wrong_tries': 4,
          'avg_wrong_tries': 2.4,
          'total_wrong': 29,
          'score': 72,
          'students': [
            {'student_id': 101, 'name': 'فيصل العنزي', 'wrong_count': 3},
            {'student_id': 102, 'name': 'راكان الحربي', 'wrong_count': 2},
          ],
        },
      ],
    };

Map<String, dynamic> t2StoreItems() => {
      'total': 3,
      'items': [
        {
          'id': 1,
          'kind': 'summary',
          'title_ar': 'ملخص الدوال الأسية',
          'title_en': 'Exponential functions summary',
          'status': 'published',
          'base_price': 25,
          'currency': 'SAR',
          'has_file': true,
          'sales_count': 84,
        },
        {
          'id': 2,
          'kind': 'ebook',
          'title_ar': 'بنك أسئلة القدرات الكمي',
          'title_en': 'Qudurat question bank',
          'status': 'published',
          'base_price': 45,
          'currency': 'SAR',
          'has_file': true,
          'sales_count': 102,
        },
        {
          'id': 3,
          'kind': 'notes',
          'title_ar': 'ملخص التحصيلي الشامل',
          'title_en': 'Tahsili summary',
          'status': 'draft',
          'base_price': 30,
          'currency': 'SAR',
        },
      ],
    };

/// Every route the T2 screens call, answered with the demo data.
Map<String, FakeHandler> t2Routes() => {
      'GET /api/v1/data-lab/overview': (_) => t2Overview(),
      'GET /api/v1/teacher/payout/status': (_) => t2PayoutStatus(),
      'GET /api/v1/teacher/withdrawals': (_) => t2Withdrawals(),
      'GET /api/v1/teacher/payout/methods': (_) => {
            'country': 'SA',
            'methods': [
              {
                'id': 'bank_account',
                'fields': [
                  {'key': 'account_name', 'required': true},
                  {'key': 'bank_name', 'required': true},
                  {'key': 'iban', 'required': true},
                  {'key': 'swift_code', 'required': false},
                ],
              },
            ],
          },
      'GET /api/v1/teacher/certificate-requests': (_) => t2CertRequests(),
      'GET /api/v1/certificate-designs': (_) => t2CertDesigns(),
      'GET /api/v1/devices/teacher/switch-requests': (_) => t2DeviceRequests(),
      'GET /api/v1/teacher/ads': (_) => t2Ads(),
      'GET /api/v1/teacher/courses/41/read-flags': (_) => t2Flags(),
      'GET /api/v1/store/manage/items': (_) => t2StoreItems(),
      'GET /api/v1/categories': (_) => <dynamic>[],
    };

/// A course list that is already loaded (no request).
class T2CoursesProvider extends TeacherCoursesProvider {
  T2CoursesProvider({List<TeacherCourse>? courses})
      : _courses = courses ?? [for (final j in t2CourseJson()) TeacherCourse.fromJson(j)],
        super(followMode: false);

  final List<TeacherCourse> _courses;

  @override
  List<TeacherCourse> get allCourses => List.unmodifiable(_courses);

  @override
  bool get loadedOnce => true;

  @override
  Future<void> ensureLoaded() async {}
}

/// Installs [api] (the T2 routes plus [extra]) for the current test and signs the demo teacher in.
Future<MyAuthProvider> t2SetUp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'ماجد الشهري', 'gmail': 'teacher@example.test', 'role': 'teacher'});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

FakeApi t2Api({Map<String, FakeHandler>? extra}) =>
    FakeApi({...t2Routes(), ...?extra}, latency: kDebugMode ? const Duration(milliseconds: 10) : Duration.zero);
