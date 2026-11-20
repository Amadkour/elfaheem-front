// The digital store's management widgets (learning hub phase 5, D-1336): list, form, review queue, orders, and the
// country VAT card / sheet of the Education-levels page, at 320 and 1400 px in both languages.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/app_data_table.dart' show AppTableState;
import 'package:flutter_education_app/features/admin/edu/edu_admin_api.dart';
import 'package:flutter_education_app/features/admin/edu/edu_levels_page.dart';
import 'package:flutter_education_app/features/store/manage/store_manage_api.dart';
import 'package:flutter_education_app/features/store/manage/store_manage_views.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _NoForm implements StoreFormActions {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

const _long = 'A very long digital store item title that keeps going to test wrapping on the smallest phone screen';

final _items = [
  const StoreManageItem(id: 1, titleAr: 'ملخص الرياضيات للصف الثالث الثانوي - المراجعة النهائية الشاملة', titleEn: _long, status: 'published', basePrice: 120, currency: 'EGP', pointsPrice: 300, hasFile: true, fileName: 'math.pdf', fileSize: 12400000, salesCount: 37),
  const StoreManageItem(id: 2, titleAr: 'مذكرة الفيزياء', titleEn: 'Physics notes', kind: 'notes', status: 'pending', basePrice: 0, hasFile: true, hasPreview: true, descriptionAr: 'وصف طويل للمذكرة يشرح محتواها بالتفصيل لكل الفصول', descriptionEn: 'A long description of the notes that explains every chapter in detail', updatedAt: '2026-11-19T10:00:00Z'),
  const StoreManageItem(id: 3, titleAr: 'كتاب', titleEn: 'Book', status: 'draft', basePrice: 49.5, currency: 'SAR'),
  const StoreManageItem(id: 4, titleAr: 'مخفي', titleEn: 'Hidden', status: 'hidden', basePrice: 10, currency: 'USD', hasFile: true),
];

final _orders = [
  for (var i = 1; i <= 6; i++)
    StoreOrderRow(
      id: 1000 + i,
      status: kStoreOrderStatuses[i % kStoreOrderStatuses.length],
      method: i.isEven ? 'card' : 'points',
      currency: 'EGP',
      subtotal: 100.0 * i,
      vatAmount: 14.0 * i,
      total: 114.0 * i,
      pointsSpent: i.isEven ? null : 250,
      createdAt: '2026-11-1${i}T08:30:00Z',
      userName: 'طالب باسم طويل جداً رقم $i',
      username: 'student_$i',
      items: [_long, 'ملخص الرياضيات'],
      needsRefund: i == 2,
    ),
];

void main() {
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);

  testWidgets('items list: all, filtered, loading, empty', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StoreItemsListBody(items: _items, status: null, selectedId: 1, onStatus: (_) {}, onOpen: (_) {}, onNew: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StoreItemsListBody(items: _items, status: 'pending', onStatus: (_) {}, onOpen: (_) {}, onNew: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StoreItemsListBody(items: const [], status: null, loading: true, onStatus: (_) {}, onOpen: (_) {}, onNew: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StoreItemsListBody(items: const [], status: null, onStatus: (_) {}, onOpen: (_) {}, onNew: () {})));
  });

  testWidgets('item form: new, and an existing item uploading', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StoreItemForm(item: null, actions: _NoForm(), countries: const {'EG': 'مصر', 'SA': 'السعودية'}, country: 'EG', stages: cat.stages, subjects: cat.subjects)));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StoreItemForm(
          item: _items[0],
          actions: _NoForm(),
          countries: const {'EG': 'Egypt'},
          country: 'EG',
          stages: cat.stages,
          subjects: cat.subjects,
          categories: const [StoreChoice(1, 'تصنيف طويل جداً للكتب والملخصات', 'A very long category for books')],
          uploading: const {'file': 0.42},
        )));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StoreItemForm(item: _items[2], actions: _NoForm())));
  });

  testWidgets('review queue and the reject sheet', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StoreReviewQueueBody(items: [_items[1], _items[0]], busyId: 1, onApprove: (_) {}, onReject: (_) {})));
    await expectNoLayoutErrors(tester, () => StoreReviewQueueBody(items: const [], onApprove: (_) {}, onReject: (_) {}));
    await expectNoLayoutErrors(tester, () => const StoreRejectSheet(title: _long));
  });

  testWidgets('orders table / cards, loading and empty', (tester) async {
    await expectNoLayoutErrors(tester, () => StoreOrdersBody(orders: _orders, status: 'paid', hasMore: true, onStatus: (_) {}, onExport: () {}));
    await expectNoLayoutErrors(tester, () => StoreOrdersBody(orders: const [], status: null, state: AppTableState.loading, onStatus: (_) {}, onExport: () {}));
    await expectNoLayoutErrors(tester, () => StoreOrdersBody(orders: const [], status: null, onStatus: (_) {}, onExport: () {}));
  });

  test('orders export rows carry every column', () {
    final e = storeOrdersExport(_orders, status: 'paid');
    expect(e.rows.length, _orders.length);
    expect(e.rows.first.keys.toSet(), {for (final c in e.columns) c.id});
  });

  testWidgets('country VAT card and sheet', (tester) async {
    const eg = EduCountryRow(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt', currency: 'EGP', vatPercent: 14, pricesIncludeVat: true);
    await expectNoLayoutErrors(tester, () => EduTaxCard(country: eg, onEdit: () {}));
    await expectNoLayoutErrors(tester, () => EduTaxCard(country: const EduCountryRow(code: 'XX', nameAr: 'س', nameEn: 'X'), onEdit: () {}));
    await expectNoLayoutErrors(tester, () => const EduTaxSheet(country: eg));
  });
}
