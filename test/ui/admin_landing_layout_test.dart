import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/landing/landing_admin_api.dart';
import 'package:flutter_education_app/features/admin/landing/landing_admin_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _ar = 'دورة رائعة جداً وشرح مبسط وواضح، استفدت منها كثيراً في الامتحان النهائي وأنصح بها كل زميل يريد أن يفهم المادة من الصفر دون تعقيد ولا حفظ أعمى.';
const _en = 'An outstanding course with a very clear explanation; it helped me a great deal in the final exam and I recommend it to anyone who wants to understand the subject from scratch.';

List<LandingReview> _reviews(int n) => [
      for (var i = 0; i < n; i++)
        LandingReview(
          id: i + 1,
          studentName: 'Abdelrahman Mohammed Al-Sayed Ibrahim $i',
          displayName: i.isEven ? 'عبدالرحمن م.' : 'Ahmed M.',
          stars: 3 + i % 3,
          text: i.isEven ? _ar : _en,
          kind: i % 3 == 0 ? 'teacher' : 'course',
          course: 'الفيزياء — الصف الثالث الثانوي مع شرح موسع للمنهج كاملاً $i',
          teacher: 'Mr. Karim Abdel-Fattah El-Sherbiny',
          createdAt: DateTime.utc(2026, 10, 1 + i),
        ),
    ];

Widget _body(List<LandingReview> reviews) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LandingAdminBody(
        rate: const LandingRateLimit(enabled: true, perMinute: 60),
        minPerMinute: 10,
        maxPerMinute: 600,
        rateDirty: true,
        savingRate: false,
        onRate: (_) {},
        onSaveRate: () {},
        reviews: reviews,
        listDirty: true,
        savingList: false,
        onReorder: (_, _) {},
        onRemove: (_) {},
        onAdd: () {},
        onSaveList: () {},
      ),
    );

void main() {
  for (final n in [0, 1, 12]) {
    testWidgets('landing page body with $n featured reviews has no layout errors', (tester) async {
      await expectNoLayoutErrors(tester, () => _body(_reviews(n)));
    });
  }

  testWidgets('rate limit card (on and off)', (tester) async {
    for (final on in [true, false]) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LandingRateLimitCard(
            value: LandingRateLimit(enabled: on, perMinute: 600),
            min: 10,
            max: 600,
            dirty: on,
            saving: !on,
            onChanged: (_) {},
            onSave: () {},
          ),
        ),
      );
    }
  });

  testWidgets('candidates sheet body (loaded, loading, error, empty)', (tester) async {
    final items = _reviews(12);
    for (final mode in ['loaded', 'loading', 'error', 'empty']) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LandingCandidatesBody(
            items: mode == 'loaded' ? items : const [],
            selectedIds: {1, 2, 3},
            total: 40,
            loading: mode == 'loading',
            loadingMore: false,
            hasMore: mode == 'loaded',
            error: mode == 'error' ? 'Could not load the reviews, please check your connection and try again.' : null,
            minStars: 4,
            kind: 'course',
            onQuery: (_) {},
            onMinStars: (_) {},
            onKind: (_) {},
            onToggle: (_) {},
            onMore: () {},
            onRetry: () {},
            onDone: () {},
          ),
        ),
      );
    }
  });

  group('models', () {
    test('LandingRateLimit tolerates missing keys and nulls', () {
      expect(LandingRateLimit.fromJson(null), const LandingRateLimit(enabled: true, perMinute: 60));
      expect(LandingRateLimit.fromJson({'enabled': false, 'per_minute': null}), const LandingRateLimit(enabled: false, perMinute: 60));
      expect(LandingRateLimit.fromJson({'enabled': true, 'per_minute': 120}).toJson(), {'enabled': true, 'per_minute': 120});
    });

    test('LandingReview reads the contract keys', () {
      final r = LandingReview.fromJson({
        'id': 7,
        'student_name': 'Ahmed Mohamed',
        'display_name': 'Ahmed M.',
        'stars': 5,
        'text': 'Great',
        'kind': 'teacher',
        'course': null,
        'teacher': 'Mr. Karim',
        'created_at': '2026-10-05T10:00:00',
        'featured': true,
      });
      expect(r.id, 7);
      expect(r.displayName, 'Ahmed M.');
      expect(r.kind, 'teacher');
      expect(r.course, isNull);
      expect(r.subject, 'Mr. Karim');
      expect(r.featured, isTrue);
      expect(r.createdAt, isNotNull);
    });

    test('LandingReview from an empty map', () {
      final r = LandingReview.fromJson(<String, dynamic>{});
      expect((r.id, r.stars, r.text, r.kind, r.featured), (0, 0, '', 'course', false));
      expect(r.createdAt, isNull);
      expect(r.subject, isNull);
      expect(LandingReview.fromJson(null).id, 0);
    });

    test('LandingOverview and candidates page with missing keys', () {
      final o = LandingOverview.fromJson({});
      expect(o.minPerMinute, 10);
      expect(o.maxPerMinute, 600);
      expect(o.testimonials, isEmpty);
      final o2 = LandingOverview.fromJson({
        'rate_limit': {'enabled': false, 'per_minute': 30},
        'limits': {'min': 20, 'max': 300},
        'testimonials': [
          {'id': 1, 'text': 'x'},
          null,
        ],
      });
      expect(o2.rateLimit.enabled, isFalse);
      expect(o2.maxPerMinute, 300);
      expect(o2.testimonials.length, 2);
      final p = LandingCandidatesPage.fromJson({'items': [{'id': 1}], 'total': 45, 'page': 1, 'page_size': 20});
      expect(p.hasMore, isTrue);
      expect(LandingCandidatesPage.fromJson(null).items, isEmpty);
    });
  });
}
