// Redesign group A1 (admin): demo data from docs/redesign/CAST.md on top of FakeApi, for the layout tests and the
// review renders. The admin is سلمان الدوسري; the people are the cast (فيصل العنزي and his family, أ. ماجد الشهري).
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_api.dart';

/// GET /api/v1/admin/overview: the platform of the reference's admin home.
Map<String, dynamic> a1Overview() => {
      'students': 24810,
      'teachers': 318,
      'courses': 1240,
      'published_courses': 980,
      'active_enrollments': 31200,
      'pending_transfers': 5,
      'pending_subscriptions': 0,
      'active_subscriptions': 8430,
      'subscription_required': true,
      'income_by_currency': {'SAR': 486200.0},
      'collected_by_currency': {'SAR': 486200.0},
      'series': [
        for (var i = 0; i < 30; i++)
          {
            'date': '2026-10-${(i + 27) % 31 + 1 < 10 ? '0' : ''}${(i + 27) % 31 + 1}',
            'signups': 14 + (i * 7) % 19,
            'enrollments': 40 + (i * 11) % 37,
            'revenue': {'SAR': 12000.0 + (i * 913) % 9000},
            'live_sessions': 18 + i % 6,
            'complaints': i % 3 == 0 ? 2 : 1,
          },
      ],
      'alerts': [
        {'key': 'teacher_documents_pending', 'severity': 'warning', 'count': 7, 'deep_link': '/admin/teachers/documents'},
        {'key': 'transfers_pending', 'severity': 'info', 'count': 5, 'deep_link': '/admin/transfers'},
        {'key': 'jobs_failed_24h', 'severity': 'danger', 'count': 0, 'deep_link': '/admin/ops/jobs', 'by_kind': {}},
        {'key': 'otp_provider_unconfigured', 'severity': 'warning', 'count': 1, 'deep_link': '/admin/settings/otp'},
      ],
      'realtime': {'events_24h': 184},
    };

const _students = ['فيصل العنزي', 'ريم الحربي', 'عبدالرحمن الشمري', 'لمى القحطاني', 'سعود المطيري', 'ريم العنزي'];
const _teachers = ['أ. ماجد الشهري', 'أ. فهد المطيري', 'أ. خالد العتيبي', 'أ. ماهر السبيعي', 'أ. نورة القحطاني'];

/// One row of GET /api/v1/admin/users (the fields the server's _user_row sends).
Map<String, dynamic> a1User(int i, String role) {
  final names = role == 'teacher' ? _teachers : _students;
  return {
    'id': 100 + i,
    'name': names[i % names.length],
    'gmail': 'user$i@nextbrain.site',
    'phone': '+9665041${1000 + i}',
    'role': role,
    'country': 'SA',
    'is_active': i % 4 != 3,
    'is_verified': true,
    'pending_deletion': false,
    'created_at': '2026-0${1 + i % 9}-1${i % 9}T10:00:00Z',
    'last_login': '2026-11-2${i % 7}T08:30:00Z',
    'login_times': 3 + i,
    'courses_count': role == 'teacher' ? 2 + i % 4 : 0,
    'enrolled_courses': role == 'student'
        ? [for (var k = 0; k < 1 + i % 4; k++) {'id': 41 + k, 'name': 'الرياضيات ٣ ث', 'status': 'active'}]
        : [],
    'subscription': role == 'student' && i.isEven ? {'status': 'active', 'plan_code': 'monthly', 'amount': 450, 'currency': 'SAR'} : null,
    'image_url': null,
  };
}

/// Pending accounts, transfers, device and certificate requests, parent links: the inbox's queues.
Map<String, FakeHandler> a1Routes() => {
      'GET /api/v1/admin/overview': (_) => a1Overview(),
      'GET /api/v1/admin/users': (o) {
        final role = o.uri.queryParameters['role'] ?? 'student';
        final n = role == 'teacher' ? 5 : 6;
        return {
          'items': [for (var i = 0; i < n; i++) a1User(i, role)],
          'total': role == 'teacher' ? 318 : 24810,
          'page': 1,
          'size': 20,
          'pages': 1,
        };
      },
      'GET /api/v1/admin/settings': (_) => {
            'max_devices': 2,
            'device_switch_days': 30,
            'max_monthly_view': 150,
            'allow_resubscribe': true,
          },
      'GET /api/v1/admin/categories': (_) => {
            'items': [
              {'id': 1, 'name_ar': 'الرياضيات', 'name_en': 'Maths', 'courses_count': 214},
              {'id': 2, 'name_ar': 'الفيزياء', 'name_en': 'Physics', 'courses_count': 96},
              {'id': 3, 'name_ar': 'القدرات والتحصيلي', 'name_en': 'Qudurat and Tahsili', 'courses_count': 140},
            ],
            'total': 3,
          },
      'GET /api/v1/datacenter/datasets': (_) => {
            'items': [
              {'key': 'users', 'title_ar': 'المستخدمون', 'title_en': 'Users'},
              {'key': 'parents', 'title_ar': 'أولياء الأمور', 'title_en': 'Parents', 'can_import': true},
            ]
          },
      'GET /api/v1/datacenter/users': (_) => {
            'key': 'users',
            'total': 2,
            'columns': [
              {'key': 'id', 'ar': '#', 'en': '#'},
              {'key': 'name', 'ar': 'الاسم', 'en': 'Name'},
              {'key': 'role', 'ar': 'الدور', 'en': 'Role'},
            ],
            'items': [
              {'id': 101, 'name': 'فيصل العنزي', 'role': 'student'},
              {'id': 7, 'name': 'أ. ماجد الشهري', 'role': 'teacher'},
            ],
          },
      'GET /api/v1/admin/accounts/pending': (_) => {
            'items': [
              {'id': 31, 'name': 'أ. ريم السبيعي', 'role': 'teacher', 'gmail': 'reem.s@mail.sa', 'created_at': '2026-11-21T09:00:00Z'},
              {'id': 32, 'name': 'أحمد سعد العنزي', 'role': 'parent', 'phone': '+966504412237', 'created_at': '2026-11-25T18:20:00Z'},
            ],
            'total': 2,
            'ready': true,
          },
      'GET /api/v1/payments/transfers/pending': (_) => {
            'items': [
              {
                'payment_id': 48213,
                'course_id': 41,
                'student_id': 101,
                'course_name': 'الرياضيات ٣ ث، أ',
                'student_name': 'فيصل العنزي',
                'method': 'bank_transfer',
                'amount': 450,
                'currency': 'SAR',
                'sender_name': 'أحمد سعد العنزي',
                'transfer_reference': 'FT2611847',
                'proof_image_url': '',
                'submitted_at': '2026-11-26T19:40:00Z',
                'status': 'pending',
              },
            ],
          },
      'GET /api/v1/devices/teacher/switch-requests': (_) => {
            'items': [
              {'id': 7, 'student_id': 101, 'student_name': 'فيصل العنزي', 'course_name': 'الرياضيات ٣ ث، أ', 'new_device_name': 'iPhone 15', 'created_at': '2026-11-26T08:00:00Z'},
            ],
          },
      'GET /api/v1/teacher/certificate-requests': (_) => [
            {
              'request_id': 3,
              'certificate_id': 9,
              'certificate_title': 'شهادة إتمام الرياضيات ٣ ث',
              'course_id': 41,
              'student_id': 102,
              'student_name': 'ريم العنزي',
              'progress': 100,
              'status': 'pending',
              'created_at': '2026-11-24T10:00:00Z',
            },
          ],
      'GET /api/v1/admin/parent-link/requests': (_) => {
            'items': [
              {
                'id': 5,
                'parent_name': 'أحمد سعد العنزي',
                'student_name': 'فيصل العنزي',
                'status': 'pending',
                'mode': 'advanced',
                'documents_count': 2,
                'created_at': '2026-11-20T10:00:00Z',
              },
            ],
            'page': 1,
            'pages': 1,
            'pending_count': 1,
          },
    };

/// Signs the admin in (role [role]) so `admRole` and the super-admin checks see them.
Future<StorageService> a1SignIn({String role = 'admin'}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 1, 'name': 'سلمان الدوسري', 'role': role, 'gmail': 'salman@nextbrain.site'});
  return storage;
}

/// The auth provider of the signed-in admin.
MyAuthProvider a1Auth(StorageService storage) => MyAuthProvider(storage: storage);
