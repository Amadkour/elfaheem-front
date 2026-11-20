// The digital store's screens (D-1333) on a phone and a wide window, ar / en, text 1.3: browse, item page,
// checkout sheet, My Library (files + purchases).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/store/store_checkout.dart';
import 'package:flutter_education_app/features/store/store_item_page.dart';
import 'package:flutter_education_app/features/store/store_library.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/store/store_tab.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

StoreItem _item(int id, {bool owned = false, String title = 'ملخص الفيزياء الشامل للصف الثالث الثانوي مع حلول'}) => StoreItem.fromJson({
      'id': id,
      'kind': id.isEven ? 'ebook' : 'summary',
      'title_ar': title,
      'title_en': 'The complete physics summary for the third secondary grade, with worked answers',
      'price': {'net': 1234.57, 'vat': 185.19, 'gross': 1419.76, 'currency': 'SAR', 'vat_percent': 15.0, 'includes_vat': false},
      'points_price': 3000,
      'pages': 240,
      'owned': owned,
      'description_ar': 'وصف طويل ' * 30,
      'description_en': 'A long description ' * 30,
      'file_name': 'physics.pdf',
      'file_size': 12400000,
      'preview_url': 'https://cdn.example/p.pdf',
    });

final _quote = StoreQuote.fromJson({
  'lines': [
    {'item_id': 1, 'title': 'The complete physics summary for the third secondary grade', 'vat_exempt': false, 'net': 1234.57, 'vat': 185.19, 'gross': 1419.76},
    {'item_id': 2, 'title': 'Book', 'vat_exempt': true, 'net': 50.0, 'vat': 0.0, 'gross': 50.0},
  ],
  'subtotal': 1284.57,
  'vat_amount': 185.19,
  'total': 1469.76,
  'currency': 'SAR',
  'vat_percent': 15.0,
  'points_total': 3500,
});

void main() {
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);
  final edu = CourseFilterEdu(catalog: cat, loadAreas: (_) async => const []);
  final items = [for (var i = 1; i <= 6; i++) _item(i, owned: i == 2)];

  testWidgets('browse', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => StoreBrowseView(
        filters: CourseFilters(country: 'EG', stageId: cat.stages.first.id, subjectId: 1),
        edu: edu,
        onFilters: (_) {},
        categories: const [(id: 1, name: 'العلوم والرياضيات المتقدمة'), (id: 2, name: 'Languages')],
        categoryId: 1,
        items: items,
        total: 31,
        hasMore: true,
        cartIds: const {3},
      ),
    );
  });

  testWidgets('browse: empty, loading, error', (tester) async {
    for (final v in [
      StoreBrowseView(filters: CourseFilters(stageId: cat.stages.first.id), onFilters: (_) {}, items: const [], total: 0),
      StoreBrowseView(filters: CourseFilters.empty, onFilters: (_) {}, items: const [], loading: true),
      StoreBrowseView(filters: CourseFilters.empty, onFilters: (_) {}, items: const [], error: 'No connection'),
    ]) {
      await expectNoLayoutErrors(tester, () => v);
    }
  });

  testWidgets('item page', (tester) async {
    for (final v in [
      StoreItemView(item: _item(1), inCart: true),
      StoreItemView(item: _item(2, owned: true)),
      StoreItemView(item: _item(3), buyOff: true),
    ]) {
      await expectNoLayoutErrors(tester, () => v);
    }
  });

  testWidgets('checkout sheet', (tester) async {
    for (final p in StoreCheckoutPhase.values) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: StoreCheckoutView(
            phase: p,
            quote: _quote,
            method: 'points',
            pointsAllowed: true,
            error: p == StoreCheckoutPhase.ready ? 'The payment provider could not start the payment.' : null,
            onPay: () {},
          ),
        ),
      );
    }
  });

  testWidgets('My Library: files and purchases', (tester) async {
    final lib = [
      for (var i = 1; i <= 3; i++)
        StoreLibraryItem.fromJson({
          'item_id': i,
          'kind': 'ebook',
          'title_ar': 'ملخص الفيزياء الشامل للصف الثالث الثانوي مع حلول',
          'title_en': 'The complete physics summary for the third secondary grade',
          'pages': 240,
          'file_name': i == 3 ? 'book.epub' : 'physics.pdf',
          'file_size': 12400000,
          'granted_at': '2026-11-20T10:00:00',
          'last_download_at': i == 1 ? '2026-11-20T11:00:00' : null,
        }),
    ];
    final orders = [
      StoreOrder.fromJson({
        'id': 12,
        'status': 'paid',
        'method': 'card',
        'currency': 'SAR',
        'subtotal': 1234.57,
        'vat_amount': 185.19,
        'total': 1419.76,
        'created_at': '2026-11-20T10:00:00',
        'items': [
          {'item_id': 1, 'title': 'The complete physics summary for the third secondary grade', 'unit_gross': 1419.76},
        ],
      }),
      StoreOrder.fromJson({'id': 13, 'status': 'failed', 'method': 'points', 'points_spent': 300, 'failure_code': 'declined'}),
    ];
    for (final tab in [0, 1]) {
      await expectNoLayoutErrors(
        tester,
        () => StoreLibraryView(tab: tab, items: lib, orders: orders, kept: const {1}, progress: const {2: 0.4}),
      );
    }
    await expectNoLayoutErrors(tester, () => const StoreLibraryView(tab: 0, items: [], orders: [], keepsFiles: false));
  });
}
