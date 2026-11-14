// The student's browsing and checkout pages in the editorial theme at 320x640 and 1400x900, Arabic + English,
// textScaler 1.3: the categories page (nothing chosen and a chosen category's block), the checkout (three plans,
// every way to pay, the fee breakdown) and the three payment results — over a fake server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_widgets.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show CourseModel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction to AI';

CourseModel get _course => CourseModel(
      id: '42',
      imageUrl: '',
      price: 1234567,
      finalPrice: 987654.5,
      discountActive: true,
      discountPercentage: 20,
      type: 'live',
      isEnrolled: false,
      isPublished: true,
      expectedHours: 40,
      titleAr: _long,
      titleEn: _long,
    );

void main() {
  late FakeApi fake;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final categories = jsonDecode(File('test/fixtures/real/categories.json').readAsStringSync()) as List<dynamic>;
    fake = FakeApi({
      'GET /api/v1/categories': (_) => [
            ...categories,
            {'id': 99, 'name_ar': _long, 'name_en': _long, 'description': '$_long $_long', 'image_url': null},
          ],
      'GET /api/v1/courses': (_) => {
            'items': [
              for (var i = 0; i < 3; i++)
                {'id': i, 'name': _long, 'category_id': 99, 'image_url': '', 'fees': 999999, 'final_price': 999999},
            ],
            'total': 3,
          },
      'GET /api/v1/payments/transfer-status*': (_) => <String, dynamic>{},
      'GET /api/v1/config*': (_) => {
            'provider': 'paymob',
            'currency': 'EGP',
            'payment_methods': [
              {'type': 'card', 'label': _long, 'enabled': true},
              {'type': 'bank_transfer', 'label': _long, 'enabled': true},
              {'type': 'instapay', 'label': _long, 'enabled': true},
            ],
            'wallet_methods': [],
          },
      'GET /api/v1/payment-methods': (_) => <dynamic>[],
      'GET /api/v1/payments/price-options*': (_) => {
            'default_plan': 'yearly',
            'options': [
              {'plan': 'monthly', 'duration_days': 30, 'price': 123456, 'final_price': 123456},
              {'plan': 'six_months', 'duration_days': 180, 'price': 740736, 'final_price': 600000},
              {'plan': 'yearly', 'duration_days': 365, 'price': 1481472, 'final_price': 987654.5, 'discount_active': true},
            ],
          },
      'GET /api/v1/payments/fees/preview*': (_) => {
            'course_price': 987654.5, 'platform_fee': 49382.7, 'vat_on_platform': 7407.4, 'gateway_fee': 27161.5,
            'total': 1071606.1, 'gateway_label': _long, 'amount_minor': 107160610, 'plan': 'yearly',
          },
    }, latency: Duration.zero);
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('categories: nothing chosen', (t) async {
    await expectNoLayoutErrors(
      t,
      () => ChangeNotifierProvider(create: (_) => CategoriesProvider(), child: const CategoriesScreen()),
      scaffold: false,
      frames: 6,
    );
  });

  testWidgets('categories: a chosen category with a long name and description', (t) async {
    await expectNoLayoutErrors(
      t,
      () => ChangeNotifierProvider(create: (_) => CategoriesProvider(), child: const CategoriesScreen(selectedId: '99')),
      scaffold: false,
      frames: 6,
    );
  });

  testWidgets('checkout: plans, methods, fee breakdown', (t) async {
    await expectNoLayoutErrors(t, () => EnrollmentScreen(course: _course), scaffold: false, frames: 8);
  });

  testWidgets('payment results: success, pending, failed', (t) async {
    for (final kind in ResultKind.values) {
      await expectNoLayoutErrors(
        t,
        () => PaymentResultView(
          kind: kind,
          title: _long,
          message: '$_long $_long',
          primaryLabel: _long,
          onPrimary: () {},
          secondaryLabel: _long,
          onSecondary: () {},
        ),
        frames: 6,
      );
    }
  });

  test('a category keeps its glyph: subjects by name, the rest by id', () {
    CategoryModel cat(String id, String en, String ar) =>
        CategoryModel(id: id, nameEn: en, nameAr: ar, imageUrl: null, description: '');
    expect(categoryIconFor(cat('1', 'Mathematics', 'الرياضيات')), Icons.calculate_rounded);
    expect(categoryIconFor(cat('5', 'Computer Science', 'الحاسب الآلي')), Icons.computer_rounded);
    expect(categoryIconFor(cat('2', 'Science', 'العلوم')), Icons.science_rounded);
    expect(categoryIconFor(cat('3', 'Arabic Language', 'اللغة العربية')), Icons.translate_rounded);
    expect(categoryIconFor(cat('7', 'Sports', 'الرياضة')), Icons.sports_soccer_rounded);
    expect(categoryIconFor(cat('8', 'Misc', 'متنوع')), categoryIconFor(cat('8', 'Misc', 'متنوع')));
    AppConfig.lang = 'en';
  });
}
