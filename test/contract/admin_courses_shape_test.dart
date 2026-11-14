// GET /api/v1/admin/courses against the REAL answer (test/fixtures/payloads/admin_courses.json, written by
// ../back/tests/contract/dump_payloads.py admin_lists): every key the courses table reads must be in the payload and
// parse to its value; a row from an older server (no D-290 fields) still parses (D-290 phase 5).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/admin/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture() =>
    Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/admin_courses.json').readAsStringSync())['payload'] as Map);

void main() {
  test('the envelope: items, paging, the income totals', () {
    final j = _fixture();
    for (final k in const ['items', 'total', 'page', 'size', 'pages', 'totals']) {
      expect(j.containsKey(k), isTrue, reason: 'the server sends no "$k"');
    }
    expect((j['totals'] as Map).containsKey('income_by_currency'), isTrue);
    final page = PageData(j);
    expect(page.items.length, (j['items'] as List).length);
    expect(page.total, j['total']);
    expect(page.pages, j['pages']);
  });

  test('every key the table reads is in a row and parses to its value', () {
    final rows = (_fixture()['items'] as List).cast<Map<String, dynamic>>();
    for (final j in rows) {
      for (final k in const [
        'id', 'name', 'name_ar', 'name_en', 'type', 'status', 'is_published', 'archived', 'is_private', 'image_url',
        'teacher_id', 'teacher_name', 'teacher', 'category', 'students_count', 'final_price', 'currency', 'income',
        'discount_active', 'discount_percentage', 'pending_payments', 'created_at', 'completion_rate', 'avg_progress',
        'withdrawn_count', 'rating_avg', 'rating_count', 'payment_settings',
      ]) {
        expect(j.containsKey(k), isTrue, reason: 'the row has no "$k": ${j.keys}');
      }
      final c = AdminCourse(j);
      expect(c.id, j['id']);
      expect(c.completionRate, (j['completion_rate'] as num).toDouble());
      expect(c.avgProgress, (j['avg_progress'] as num).toDouble());
      expect(c.withdrawnCount, j['withdrawn_count']);
      expect(c.ratingAvg, (j['rating_avg'] as num?)?.toDouble());
      expect(c.ratingCount, j['rating_count']);
      expect(c.archived, j['archived']);
      expect(c.isPrivate, j['is_private']);
      expect(c.createdAt, j['created_at']);
      final teacher = j['teacher'] as Map?;
      if (teacher != null) expect(teacher.keys, containsAll(const ['id', 'name', 'username', 'image_url']));
      final category = j['category'] as Map?;
      if (category != null) expect(category.keys, containsAll(const ['id', 'name_ar', 'name_en']));
    }
    expect(rows.any((j) => j['rating_avg'] != null), isTrue, reason: 'the capture holds a rated course');
    expect(rows.any((j) => j['category'] != null), isTrue, reason: 'the capture holds a category');
  });

  test('a row from an older server parses with empty figures', () {
    final j = Map<String, dynamic>.from((_fixture()['items'] as List).first as Map)
      ..removeWhere((k, _) => const ['category', 'teacher', 'completion_rate', 'avg_progress', 'withdrawn_count', 'rating_avg',
          'rating_count', 'created_at', 'archived'].contains(k));
    final c = AdminCourse(j);
    expect(c.ratingAvg, isNull);
    expect(c.completionRate, 0);
    expect(c.archived, isFalse);
    expect(c.createdAt, isNull);
  });
}
