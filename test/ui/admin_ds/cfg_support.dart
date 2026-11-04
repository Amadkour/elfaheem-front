// Shared set-up of the cfg_* tests (the Configuration hub: Platform settings, Features, Data lab, Flags, Recommendations,
// Update prompt, Terms, Theme, Exam feedback, Live): a FakeApi that answers the routes with realistic payloads and
// records the bodies the pages PUT / PATCH.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';

/// The bodies sent by PUT / PATCH / POST, in order: `'PUT /path'` → body.
late StorageService cfgStorage;

final cfgSent = <String, List<Object?>>{};

Object? _rec(RequestOptions o, Object? answer) {
  final path = o.uri.path.startsWith('/api/api/') ? o.uri.path.substring(4) : o.uri.path;
  (cfgSent['${o.method.toUpperCase()} $path'] ??= []).add(o.data);
  return answer;
}

Map<String, dynamic> cfgPlatformSettings({bool canEdit = true, num fee = 500}) => {
      'can_edit': canEdit,
      'orgs_enabled': true,
      'sharing_enabled': true,
      'org_creation_fee': {
        'amount': fee,
        'currency': 'EGP',
        'methods': ['paymob_card', 'bank_transfer'],
      },
      'timezone': 'Africa/Cairo',
      'time_format': '12h',
      'currencies': ['EGP', 'SAR', 'USD'],
      'awaiting_fee_review': 2,
      'available_methods': [
        {'id': 'paymob_card', 'label_ar': 'بطاقة بنكية', 'label_en': 'Bank card', 'kind': 'card', 'ready': true, 'currency': null},
        {'id': 'bank_transfer', 'label_ar': 'تحويل بنكي', 'label_en': 'Bank transfer', 'kind': 'transfer', 'ready': true, 'currency': null},
        {'id': 'wallet', 'label_ar': 'محفظة إلكترونية', 'label_en': 'Mobile wallet', 'kind': 'transfer', 'ready': false, 'reason': 'disabled'},
      ],
    };

List<Map<String, dynamic>> cfgFeatureItems() => [
      for (var i = 0; i < 12; i++)
        {
          'key': 'feature.k$i',
          'title_ar': 'ميزة رقم ${i + 1}',
          'title_en': 'Feature number ${i + 1}',
          'description_ar': i.isEven ? 'وصف قصير للميزة رقم ${i + 1}' : '',
          'description_en': i.isEven ? 'A short description of feature ${i + 1}' : '',
          'tab': i < 6 ? 'student' : 'teacher',
          'hidden': i == 3,
          'platforms': i == 3 ? ['android', 'ios', 'web'] : (i == 5 ? ['ios'] : []),
          'hidden_everywhere': i == 3,
          'org_manageable': i % 3 == 0,
          'allow_to_admin': i % 2 == 0,
          'is_custom': i == 11,
          'deletable': i == 11,
        },
    ];

Map<String, dynamic> cfgFeatureCatalog() => {
      'is_super_admin': true,
      'platforms': ['android', 'ios', 'web'],
      'tabs': [
        {'id': 'student', 'title_ar': 'الطالب', 'title_en': 'Student', 'count': 6},
        {'id': 'teacher', 'title_ar': 'المعلم', 'title_en': 'Teacher', 'count': 6},
      ],
      'items': cfgFeatureItems(),
      'counts': {'total': 12, 'hidden': 2, 'org_manageable': 4},
    };

Map<String, dynamic> cfgRecStats(int days) => {
      'days': days,
      'students': 812,
      'total': {'shown': 5400, 'opened': 1320, 'dismissed': 210, 'enrolled': 96},
      'by_reason': [
        {'reason': 'because_completed', 'shown': 1800, 'opened': 520, 'dismissed': 40, 'enrolled': 41},
        {'reason': 'similar_students', 'shown': 2100, 'opened': 480, 'dismissed': 90, 'enrolled': 33},
        {'reason': 'matches_interest', 'shown': 1500, 'opened': 320, 'dismissed': 80, 'enrolled': 22},
      ],
      'weights': {'similar_students': 0.35, 'content': 0.35, 'same_teacher': 0.1, 'popularity': 0.2},
      'defaults': {'similar_students': 0.35, 'content': 0.35, 'same_teacher': 0.1, 'popularity': 0.2},
    };

Map<String, dynamic> cfgDataLabSettings() => {
      'enabled': true,
      'allow_import': true,
      'allow_create_accounts': false,
      'allow_export': true,
      'allow_email_export': true,
      'allow_certificates': true,
      'allow_student_requests': true,
      'student_view': true,
      'max_import_rows': 2000,
      'max_custom_columns': 30,
      'export_formats': ['xlsx', 'csv'],
      'stats': {'courses_with_data': 14, 'custom_columns': 52, 'open_requests': 3},
    };

Map<String, dynamic> cfgDataLabCourses(RequestOptions o) {
  final q = (o.uri.queryParameters['search'] ?? '').toLowerCase();
  final skip = int.tryParse(o.uri.queryParameters['skip'] ?? '') ?? 0;
  var all = [
    for (var i = 0; i < 30; i++) {'id': i + 1, 'title': i.isEven ? 'الفيزياء ${i + 1}' : 'Calculus ${i + 1}', 'columns': i % 5, 'enabled': i % 7 != 3}
  ];
  if (q.isNotEmpty) all = all.where((c) => '${c['title']}'.toLowerCase().contains(q)).toList();
  return {'items': all.skip(skip).take(20).toList(), 'total': all.length};
}

Map<String, dynamic> cfgAdminSettings() => {
      'max_devices': 2,
      'allow_review_flags': true,
      'allow_read_flags': true,
      'review_limit_per_exam': 5,
      'review_limit_per_course': 0,
      'read_flag_teacher_min_students': 3,
      'read_flag_teacher_min_wrong_tries': 2,
    };

List<Map<String, dynamic>> cfgVersions() => [
      {'id': 1, 'version': '1.4.1', 'platform': 'android', 'is_active': true, 'force_update': false, 'recommend_update': true, 'min_supported': '1.3.0', 'release_notes_ar': 'تحسينات في البث المباشر', 'release_notes_en': 'Live class improvements'},
      {'id': 2, 'version': '1.4.0', 'platform': 'ios', 'is_active': false, 'force_update': true, 'recommend_update': false},
      {'id': 3, 'version': '1.4.1', 'platform': 'web', 'is_active': true, 'force_update': false, 'recommend_update': false},
    ];

Map<String, dynamic> cfgThemes() => {
      'active_preset': 'teal',
      'items': [
        {
          'id': 1,
          'key': 'teal',
          'name_ar': 'تيل',
          'name_en': 'Teal',
          'is_builtin': true,
          'colors': {
            'primary_hex': '#24B1B1',
            'primary_dark_hex': '#0E7C86',
            'primary_light_hex': '#D4FEFD',
            'accent1_hex': '#F4C542',
            'accent2_hex': '#8B6FFF',
            'background_hex': '#F8F4EF',
            'text_dark': '#1A1A1A',
            'text_action': '#FFFFFF',
            'dark_background': '#0F1224',
            'dark_card': '#1A1F3A',
            'surface_card': '#FFFFFF',
          },
        },
        {
          'id': 9,
          'key': 'custom_9',
          'name_ar': 'ثيم الجامعة',
          'name_en': 'University theme',
          'is_builtin': false,
          'colors': {
            'primary_hex': '#2F3E9E',
            'primary_dark_hex': '#22306B',
            'primary_light_hex': '#F2F4FF',
            'accent1_hex': '#F4C542',
            'accent2_hex': '#FF6F61',
            'background_hex': '#FAF4EE',
            'text_dark': '#1A1A1A',
            'text_action': '#FFFFFF',
            'dark_background': '#0F1224',
            'dark_card': '#1A1F3A',
          },
        },
      ],
    };

Map<String, FakeHandler> cfgRoutes({bool missing = false}) {
  if (missing) return {}; // every route answers FastAPI's bare 404
  return {
    'GET /api/v1/admin/platform-settings': (_) => cfgPlatformSettings(),
    'PUT /api/v1/admin/platform-settings': (o) => _rec(o, {...cfgPlatformSettings(), ...(o.data as Map).cast<String, dynamic>()}),
    'GET /api/v1/admin/platform-settings/org-fee/payments': (_) => {
          'items': [
            {'id': 1, 'status': 'review', 'sender_name': 'منى إبراهيم', 'email': 'mona@example.test', 'amount': 500, 'currency': 'EGP', 'method': 'bank_transfer', 'transfer_reference': 'TR-88231', 'created_at': '2026-11-02T10:00:00Z'},
            {'id': 2, 'status': 'paid', 'sender_name': 'Omar Khaled', 'email': 'omar@example.test', 'amount': 500, 'currency': 'EGP', 'method': 'paymob_card', 'created_at': '2026-11-01T09:00:00Z', 'org_id': 12},
          ]
        },
    'POST /api/v1/admin/platform-settings/org-fee/payments/*': (o) => _rec(o, {'ok': true}),
    'GET /api/v1/admin/features/catalog': (_) => cfgFeatureCatalog(),
    'PUT /api/v1/admin/features/*': (o) => _rec(o, {'ok': true}),
    'GET /api/v1/admin/settings': (_) => cfgAdminSettings(),
    'PUT /api/v1/admin/settings': (o) => _rec(o, {...cfgAdminSettings(), ...(o.data as Map).cast<String, dynamic>()}),
    'GET /api/v1/admin/data-lab/settings': (_) => cfgDataLabSettings(),
    'PUT /api/v1/admin/data-lab/settings': (o) => _rec(o, {...cfgDataLabSettings(), ...(o.data as Map).cast<String, dynamic>()}),
    'GET /api/v1/admin/data-lab/courses': cfgDataLabCourses,
    'PUT /api/v1/admin/data-lab/courses/*': (o) => _rec(o, {'ok': true}),
    'GET /api/v1/admin/recommendations/stats': (o) => cfgRecStats(int.tryParse(o.uri.queryParameters['days'] ?? '') ?? 30),
    'PUT /api/v1/admin/recommendations/settings': (o) => _rec(o, {'weights': (o.data as Map)['weights']}),
    'GET /app/': (_) => cfgVersions(),
    'GET /api/app/': (_) => cfgVersions(),
    'PATCH /app/*': (o) => _rec(o, {'ok': true}),
    'PATCH /api/app/*': (o) => _rec(o, {'ok': true}),
    'GET /api/v1/admin/themes': (_) => cfgThemes(),
    'GET /api/v1/exam/admin/feedback/settings': (_) => {'enabled': true, 'org_default': false, 'retention_days': 365, 'records': 1840},
    'PUT /api/v1/exam/admin/feedback/settings': (o) => _rec(o, {...(o.data as Map).cast<String, dynamic>(), 'records': 1840}),
    'GET /api/v1/admin/live-settings': (_) => <String, dynamic>{},
    'GET /api/v1/admin/content/about': (_) => {
          'info': {'name_ar': 'نكست برين', 'name_en': 'NextBrain', 'mission_ar': 'تعليم أفضل للجميع', 'mission_en': 'Better learning for all'},
          'stats': [
            {'id': 1, 'value': '12K', 'label_ar': 'طالب مسجّل', 'label_en': 'Registered students', 'icon': 'groups', 'is_active': true},
          ],
          'team': [
            {'id': 1, 'name_ar': 'سارة أحمد', 'name_en': 'Sara Ahmed', 'role_ar': 'مؤسسة', 'role_en': 'Founder', 'is_active': true},
          ],
          'contacts': [
            {'id': 1, 'type': 'email', 'value': 'hello@example.test', 'label_ar': 'البريد', 'label_en': 'Email', 'is_active': true},
          ],
        },
    'GET /api/v1/admin/content/terms': (_) => {
          'meta': {'version': '2.1', 'last_updated': '2026-10-01'},
          'sections': [
            {'id': 1, 'title_ar': 'قبول الشروط', 'title_en': 'Acceptance of terms', 'body_ar': 'نص', 'body_en': 'Text', 'icon': 'gavel', 'is_active': true},
          ],
        },
  };
}

/// Signs a super-admin in and plugs [api] into the app's Dio.
Future<MyAuthProvider> cfgSetUp(FakeApi api, {String role = 'super-admin'}) async {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  cfgSent.clear();
  final storage = cfgStorage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': role});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

Widget cfgProviders(MyAuthProvider auth, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<MyAuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => LangProvider(storage: cfgStorage)),
        ChangeNotifierProvider(create: (_) => ThemeConfigProvider(api: ApiClient())),
      ],
      child: child,
    );

Future<void> cfgPump(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
