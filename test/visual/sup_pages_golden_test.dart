// VISUAL review renders of the People / Support & security pages on the design system (Auth settings, Devices,
// Data center) at 390x844 and 1440x900 in Arabic, with real fonts, the production theme and realistic payloads,
// into test/visual/goldens/sup_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/sup_pages_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_auth_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart';
import 'package:flutter_education_app/features/admin/admin_devices_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, StorageService storage) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: ChangeNotifierProvider(create: (_) => LangProvider(storage: storage), child: child)),
    ),
  );
}

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
        for (var i = 0; i < 8; i++)
          {
            'id': i + 1,
            'title': ['مشكلة في تشغيل الفيديو', 'لا يصلني رمز التفعيل', 'طلب استرداد المبلغ', 'خطأ في الدفع'][i % 4],
            'category': ['course_content', 'technical', 'payment', 'general'][i % 4],
            'priority': ['low', 'medium', 'high', 'urgent'][i % 4],
            'status': i % 2 == 0 ? 'open' : 'resolved',
            'created_at': '2026-11-01T10:00:00',
          },
      ],
      'summary': {
        'field': 'status',
        'by': {'open': 20, 'resolved': 25},
        'per_day': [for (var i = 0; i < 30; i++) {'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}', 'count': (i * 7) % 9}],
      },
    };

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('support pages', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final storage = await StorageService.getInstance();
    final fake = FakeApi({
      'GET /api/v1/admin/settings': (_) => _settings(),
      'GET /api/v1/datacenter/datasets': (_) => {
            'items': [
              {'key': 'app_complaints', 'title_ar': 'شكاوى التطبيق', 'title_en': 'App complaints'},
              {'key': 'users', 'title_ar': 'المستخدمون', 'title_en': 'Users'},
              {'key': 'ads', 'title_ar': 'الإعلانات', 'title_en': 'Ads'},
            ]
          },
      'GET /api/v1/datacenter/app_complaints': (_) => _dataset(),
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final (name, page) in <(String, Widget)>[
        ('auth', const AdminAuthSettingsPage()),
        ('devices', const AdminDevicesPage()),
        ('datacenter', const DataCenterPage()),
      ]) {
        for (final size in const [Size(390, 844), Size(1440, 900)]) {
          AppConfig.lang = 'ar';
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(page, storage));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull, reason: '$name ${size.width}');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/sup_${name}_${size.width.toInt()}_ar.png'));
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
