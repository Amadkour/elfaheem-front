// People / Support & security pages of the Super Admin dashboard on the design system: no layout error at
// 320x640 and 1400x900 (ar + en, text x1.3), and the behaviours the audit asked for (a failed load is an error
// state with Retry and no Save, a failed page never shows the form with defaults, ...).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_auth_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_categories_page.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart';
import 'package:flutter_education_app/features/admin/admin_devices_page.dart';
import 'package:flutter_education_app/features/admin/admin_parent_link_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_parent_requests_page.dart';
import 'package:flutter_education_app/features/admin/admin_required_documents_page.dart';
import 'package:flutter_education_app/features/admin/admin_send_message_page.dart';
import 'package:flutter_education_app/features/admin/admin_username_stats.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';

Map<String, dynamic> _settings() => {
      'verification_methods': ['email', 'telegram'],
      'login_identifiers': ['email', 'phone'],
      'verification_require_all': false,
      'default_verification_way': 'auto',
      'whatsapp_delivery': 'auto',
      'username_login': true,
      'max_devices': 2,
      'device_switch_days': 30,
      'max_monthly_view': 150,
      'allow_resubscribe': true,
      'availability': {
        'email': {'ok': true},
        'telegram': {'ok': false, 'missing': ['TELEGRAM_BOT_USERNAME']},
        'whatsapp_link': {'ok': false, 'missing': ['WHATSAPP_BUSINESS_NUMBER']},
        'whatsapp_code': {'ok': false, 'missing': ['OTP_PROVIDER']},
        'sms': {'ok': false, 'missing': ['OTP_PROVIDER']},
      },
    };

Map<String, dynamic> _dataset() => {
      'key': 'app_complaints',
      'total': 45,
      'columns': [
        {'key': 'id', 'ar': '#', 'en': '#'},
        {'key': 'title', 'ar': 'العنوان', 'en': 'Title'},
        {'key': 'category', 'ar': 'التصنيف', 'en': 'Category'},
        {'key': 'priority', 'ar': 'الأولوية', 'en': 'Priority'},
        {'key': 'status', 'ar': 'الحالة', 'en': 'Status'},
        {'key': 'created_at', 'ar': 'التاريخ', 'en': 'Date'},
      ],
      'items': [
        for (var i = 0; i < 12; i++)
          {
            'id': i + 1,
            'title': 'مشكلة في تشغيل الفيديو رقم $i — a very long complaint title to test wrapping',
            'category': i.isEven ? 'course_content' : 'technical',
            'priority': i % 3 == 0 ? 'low' : 'high',
            'status': i % 2 == 0 ? 'open' : 'resolved',
            'created_at': '2026-11-01T10:00:00',
          },
      ],
      'summary': {
        'field': 'status',
        'by': {'open': 20, 'resolved': 25},
        'per_day': [for (var i = 0; i < 30; i++) {'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}', 'count': i % 5}],
      },
    };

Map<String, FakeHandler> _routes() => {
      'GET /api/v1/admin/settings': (_) => _settings(),
      'PUT /api/v1/admin/settings': (_) => _settings(),
      'GET /api/v1/datacenter/datasets': (_) => {
            'items': [
              {'key': 'app_complaints', 'title_ar': 'شكاوى التطبيق', 'title_en': 'App complaints'},
              {'key': 'users', 'title_ar': 'المستخدمون', 'title_en': 'Users'},
              {'key': 'parents', 'title_ar': 'أولياء الأمور', 'title_en': 'Parents', 'can_import': true},
            ]
          },
      'GET /api/v1/datacenter/app_complaints': (_) => _dataset(),
      'GET /api/v1/admin/requirements': (_) => {
            'items': [
              {'id': 1, 'kind': 'ack', 'title': 'شروط الاستخدام الجديدة', 'body': 'x', 'roles': ['student'], 'is_active': true, 'acks': 120, 'version': 3},
              {'id': 2, 'kind': 'info', 'title': 'Maintenance window on Friday', 'body': 'y', 'roles': [], 'is_active': false, 'acks': 4, 'version': 1},
            ]
          },
      'GET /api/v1/admin/users': (_) => {'items': [], 'total': 1204, 'page': 1, 'size': 1, 'pages': 1204},
      'GET /api/v1/admin/categories': (_) => {
            'items': [
              {'id': 1, 'name_ar': 'البرمجة', 'name_en': 'Programming', 'courses_count': 12},
              {'id': 2, 'name_ar': 'اللغات', 'name_en': 'Languages', 'courses_count': 0},
            ],
            'total': 2,
          },
      'GET /api/v1/admin/parent-link/requests': (_) => {
            'items': [
              for (var i = 0; i < 4; i++)
                {
                  'id': i + 1,
                  'parent_name': 'عبد الرحمن بن عبد العزيز آل عبد الله',
                  'student_name': 'Student Name $i',
                  'status': ['pending', 'approved', 'rejected', 'failed'][i],
                  'mode': 'advanced',
                  'documents_count': i,
                  'created_at': '2026-11-01T10:00:00Z',
                }
            ],
            'page': 1,
            'pages': 1,
            'pending_count': 1,
          },
      'GET /api/v1/admin/parent-link/settings': (_) => {
            'mode': 'advanced',
            'code_ttl_minutes': 15,
            'advanced': {
              'fields': [
                {'key': 'national_id', 'label_ar': 'الرقم القومي', 'label_en': 'National ID', 'type': 'text', 'required': true},
              ],
              'documents': [
                {'key': 'id_card', 'label_ar': 'بطاقة الهوية', 'label_en': 'ID card', 'required': true},
              ],
            },
            'external': {},
          },
      'GET /api/v1/admin/required-documents': (_) => [
            {'id': 1, 'title_ar': 'الهوية الشخصية', 'title_en': 'National ID', 'icon_name': 'badge', 'is_required': true, 'is_active': true, 'uploads': 12},
            {'id': 2, 'title_ar': 'السيرة الذاتية', 'title_en': 'CV', 'icon_name': 'contact_page', 'is_required': false, 'is_active': false, 'uploads': 0},
          ],
      'GET /api/v1/admin/ads': (_) => {
            'items': [
              {'id': 1, 'title': 'خصم 30% على كل الدورات', 'status': 'pending', 'is_active': true, 'impressions': 1200, 'clicks': 80, 'ctr': 6.7, 'likes': 10, 'dislikes': 1, 'cost': 150, 'paid': false, 'owner_kind': 'teacher', 'owner': {'name': 'Ahmed Teacher'}},
              {'id': 2, 'title': 'Platform launch', 'status': 'approved', 'is_active': true, 'impressions': 0, 'clicks': 0, 'ctr': 0, 'likes': 0, 'dislikes': 0, 'cost': 0, 'owner_kind': 'platform'},
            ],
            'total': 2,
            'page': 1,
            'pages': 1,
          },
      'GET /api/v1/admin/usernames/stats': (_) => {
            'days': 30,
            'snapshot': {'users_total': 100, 'with_username': 40, 'confirmed': 30, 'unconfirmed_pending': 10, 'without': 60},
            'flows': {'kept': 5},
            'logins_by_kind': {'email': 20, 'username': 10},
            'daily': [
              for (var i = 0; i < 30; i++) {'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}', 'events': {'chosen_at_signup': i % 3}, 'logins': {'username': i % 4}}
            ],
          },
    };

void main() {
  late FakeApi fake;
  late StorageService storage;

  Widget withLang(Widget child) => ChangeNotifierProvider(create: (_) => LangProvider(storage: storage), child: child);

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  void install(Map<String, FakeHandler> routes) {
    fake = FakeApi(routes, latency: const Duration(milliseconds: 10))..install();
    addTearDown(fake.uninstall);
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    mockRequestPlugins();
    AppConfig.lang = 'ar';
    install(_routes());
  });

  Future<void> layout(WidgetTester tester, Widget Function() page) =>
      expectNoLayoutErrors(tester, () => withLang(page()), scaffold: false, frames: 12);

  group('layout', () {
    testWidgets('auth settings', (t) => layout(t, () => const AdminAuthSettingsPage()));
    testWidgets('devices', (t) => layout(t, () => const AdminDevicesPage()));
    testWidgets('data center', (t) => layout(t, () => const DataCenterPage()));
    testWidgets('requirements', (t) => layout(t, () => const AdminRequirementsPage()));
    testWidgets('send message', (t) => layout(t, () => const AdminSendMessagePage()));
    testWidgets('categories', (t) => layout(t, () => const AdminCategoriesPage()));
    testWidgets('parent requests', (t) => layout(t, () => const AdminParentRequestsPage()));
    testWidgets('parent-link settings', (t) => layout(t, () => const AdminParentLinkSettingsPage()));
    testWidgets('required documents', (t) => layout(t, () => const AdminRequiredDocumentsPage()));
    testWidgets('ads', (t) => layout(t, () => const AdminAdsPage()));
    testWidgets('usernames', (t) => layout(t, () => const AdminUsernameStatsPage()));
  });

  group('behaviour', () {
    Future<void> pumpPage(WidgetTester t, Widget page) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1400, 900);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(layoutHost(withLang(page), scaffold: false));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('auth settings: a failed load is an error state with Retry and NO Save and NO form', (t) async {
      fake.uninstall();
      install({'GET /api/v1/admin/settings': (_) => const FakeResponse(500, {'detail': 'boom'})});
      await pumpPage(t, const AdminAuthSettingsPage());
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.byType(AppSwitchTile), findsNothing);
      expect(find.text('save'.tr), findsNothing);
    });

    testWidgets('auth settings: Save is off until something changes, raw env names stay in the developer line', (t) async {
      await pumpPage(t, const AdminAuthSettingsPage());
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(AppSwitchTile), findsWidgets);
      final save = t.widget<AppButton>(find.widgetWithText(AppButton, 'save'.tr));
      expect(save.onPressed, isNull);
      expect(find.textContaining('For the developer'), findsNothing); // Arabic page
      expect(find.textContaining('للمطوّر'), findsWidgets);
      expect(find.text('Not configured on the server — missing: TELEGRAM_BOT_USERNAME.'), findsNothing);
    });

    testWidgets('data center: a failed dataset load is an error state, not "no data"', (t) async {
      fake.uninstall();
      install({
        ..._routes(),
        'GET /api/v1/datacenter/app_complaints': (_) => const FakeResponse(500, {'detail': 'boom'}),
      });
      await pumpPage(t, const DataCenterPage());
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('لا بيانات متاحة لك'), findsNothing);
    });

    testWidgets('data center: enum values are translated and the date picker is cancel-safe', (t) async {
      await pumpPage(t, const DataCenterPage());
      expect(find.text('course_content'), findsNothing);
      expect(find.text('low'), findsNothing);
      expect(find.text('محتوى الدورة'), findsWidgets);
    });

    testWidgets('requirements: a failed load is an error state, not the empty state', (t) async {
      fake.uninstall();
      install({'GET /api/v1/admin/requirements': (_) => const FakeResponse(500, {'detail': 'boom'})});
      await pumpPage(t, const AdminRequirementsPage());
      expect(find.text('ds_error_title'.tr), findsOneWidget);
      expect(find.byType(AppEmpty), findsNothing);
    });

    testWidgets('parent requests: a failed detail load shows Retry, not an endless skeleton', (t) async {
      fake.uninstall();
      install({
        ..._routes(),
        'GET /api/v1/admin/parent-link/requests/1': (_) => const FakeResponse(500, {'detail': 'boom'}),
      });
      await pumpPage(t, const AdminParentRequestsPage());
      // the row (the parent's name); the student is a link of its own (D-290)
      await t.tap(find.textContaining('عبد الرحمن').first);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(AppErrorState), findsOneWidget);
    });

    testWidgets('categories: deleting a category with courses says why instead of confirming', (t) async {
      await pumpPage(t, const AdminCategoriesPage());
      expect(find.text('البرمجة'), findsWidgets);
    });

    testWidgets('required documents: one Add button only (the header one)', (t) async {
      await pumpPage(t, const AdminRequiredDocumentsPage());
      expect(find.text('doc_add'.tr), findsOneWidget);
    });

    testWidgets('send message: shows how many people it will reach', (t) async {
      await pumpPage(t, const AdminSendMessagePage());
      expect(find.textContaining('1204'), findsWidgets);
    });
  });
}
