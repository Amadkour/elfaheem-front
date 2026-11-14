// VISUAL review renders of the student's course browsing pages in the editorial theme: the categories page (the
// real CategoriesProvider over a fake server answering with the real categories payload, nothing chosen and a
// chosen category) and the checkout (EnrollmentScreen over the real EnrollmentProvider: three plans, every way to
// pay, the fee breakdown; the success result) — 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/student_courses_*.png.
// Not a CI suite; compared by eye.
//
//   flutter test test/visual/student_courses_golden_test.dart --update-goldens [--plain-name categories]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_widgets.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show CourseModel;
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

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Map<String, dynamic> _course(int id, String name, {double fees = 0, String teacher = 'Dr. Mona Adel', int cat = 1}) => {
      'id': id, 'name': name, 'category_id': cat, 'image_url': '', 'fees': fees, 'price': fees, 'final_price': fees,
      'rating': 4.6, 'teacher': {'name': teacher}, 'discount_active': false, 'discount_percentage': 0,
    };

final _courses = [
  _course(31, 'الجبر للصف الأول الثانوي', fees: 250),
  _course(32, 'Geometry: angles and triangles', teacher: 'Prof. Hany Saleh'),
  _course(33, 'حساب المثلثات خطوة بخطوة', fees: 180, teacher: 'Dr. Salma Nour'),
  _course(34, 'Calculus essentials', fees: 400),
  _course(35, 'مراجعة نهائية رياضيات', fees: 120),
];

CourseModel get _paidCourse => CourseModel(
      id: '42',
      imageUrl: '',
      price: 1200,
      finalPrice: 900,
      discountActive: true,
      discountPercentage: 25,
      type: 'live',
      isEnrolled: false,
      isPublished: true,
      expectedHours: 40,
      titleAr: 'أساسيات الذكاء الاصطناعي بلغة بايثون',
      titleEn: 'AI foundations with Python',
    );

final _plans = {
  'default_plan': 'yearly',
  'options': [
    {'plan': 'monthly', 'duration_days': 30, 'price': 120, 'final_price': 120},
    {'plan': 'six_months', 'duration_days': 180, 'price': 720, 'final_price': 600},
    {'plan': 'yearly', 'duration_days': 365, 'price': 1440, 'final_price': 900, 'discount_active': true},
  ],
};

final _gateway = {
  'provider': 'paymob',
  'currency': 'EGP',
  'payment_methods': [
    {'type': 'card', 'label': 'Card', 'enabled': true},
    {'type': 'bank_transfer', 'label': 'Bank transfer', 'enabled': true},
    {'type': 'instapay', 'label': 'InstaPay', 'enabled': true},
  ],
  'wallet_methods': [],
};

final _fees = {
  'course_price': 900, 'platform_fee': 45, 'vat_on_platform': 6.3, 'gateway_fee': 27.5, 'total': 978.8,
  'gateway_label': 'Paymob 2.75% + 3 EGP', 'amount_minor': 97880, 'plan': 'yearly',
};

void main() {
  late FakeApi fake;
  late List<dynamic> categories;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    categories = jsonDecode(File('test/fixtures/real/categories.json').readAsStringSync()) as List<dynamic>;
    await _loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    fake = FakeApi({
      'GET /api/v1/categories': (_) => categories,
      'GET /api/v1/courses': (_) => {'items': _courses, 'total': _courses.length},
      'GET /api/v1/payments/transfer-status*': (_) => <String, dynamic>{},
      'GET /api/v1/config*': (_) => _gateway,
      'GET /api/v1/payment-methods': (_) => <dynamic>[],
      'GET /api/v1/payments/price-options*': (_) => _plans,
      'GET /api/v1/payments/fees/preview*': (_) => _fees,
    }, latency: Duration.zero);
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('categories all', (t) => _render(
        t,
        'student_courses_categories_all',
        () => ChangeNotifierProvider(create: (_) => CategoriesProvider(), child: const CategoriesScreen()),
      ));

  testWidgets('enroll method', (t) => _render(t, 'student_courses_enroll', () => EnrollmentScreen(course: _paidCourse)));

  testWidgets('enroll success', (t) => _render(
        t,
        'student_courses_enroll_success',
        () => Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            body: PaymentResultView(
              kind: ResultKind.success,
              title: 'enroll_success_title'.tr,
              message: 'enroll_success_message'.tr,
              primaryLabel: 'start_learning_now'.tr,
              onPrimary: () {},
              secondaryLabel: 'back_to_home'.tr,
              onSecondary: () {},
            ),
          ),
        ),
      ));

  testWidgets('categories chosen', (t) => _render(
        t,
        'student_courses_categories_chosen',
        () => ChangeNotifierProvider(create: (_) => CategoriesProvider(), child: const CategoriesScreen(selectedId: '1')),
      ));
}
