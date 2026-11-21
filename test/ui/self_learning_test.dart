// Self-learning (Learning Hub v2 §5, D-1600..D-1611): the contract shapes, the review round (answer → feedback →
// next, offline queued), the API over FakeApi, and the new widgets through the layout harness.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/features/self_learning/admin/sl_admin_page.dart';
import 'package:flutter_education_app/features/self_learning/self_learning_page.dart';
import 'package:flutter_education_app/features/self_learning/sl_api.dart';
import 'package:flutter_education_app/features/self_learning/sl_models.dart';
import 'package:flutter_education_app/features/self_learning/sl_review_session.dart';
import 'package:flutter_education_app/features/self_learning/sl_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

final _meJson = {
  'enabled': true,
  'can_toggle': true,
  'subjects': ['quran', 'nahw'],
  'today': {
    'lessons': [
      {
        'id': 11,
        'subject': 'nahw',
        'kind': 'lesson',
        'category': 'أقسام الكلمة',
        'title': 'الاسم والفعل والحرف',
        'body': 'الكلمة في العربية ثلاثة أقسام: **اسم** وفعل وحرف.\nالاسم يدل على معنى في نفسه غير مقترن بزمن، مثل: كتاب، شجرة، مدينة الإسكندرية.',
        'lesson_id': null,
        'question': null,
        'source': {'type': 'nahw_lesson', 'id': 7},
        'sort': 1,
        'published': true,
      },
    ],
    'reviews': [
      {
        'id': 21,
        'subject': 'quran',
        'kind': 'question',
        'category': '',
        'title': 'مراجعة',
        'body': '',
        'lesson_id': 11,
        'question': {
          'prompt': 'كم عدد آيات سورة الفاتحة؟',
          'options': ['خمس', 'ست', 'سبع', 'ثمان'],
          'answer': 2,
          'explanation': 'سورة الفاتحة سبع آيات.',
        },
        'source': {'type': null},
        'sort': 2,
        'published': true,
      },
      {
        'id': 22,
        'subject': 'nahw',
        'kind': 'question',
        'title': 'مراجعة',
        'question': {'prompt': 'أي الكلمات فعل؟', 'options': ['قلم', 'جلسَ'], 'answer': 1, 'explanation': 'جلسَ فعل ماضٍ.'},
        'published': true,
      },
    ],
  },
  'progress': {
    'learned': 14,
    'due': 3,
    'streak_days': 5,
    'per_subject': {
      'quran': {'learned': 9, 'due': 2, 'total': 40},
      'nahw': {'learned': 5, 'due': 1},
    },
  },
};

SlState get _state => SlState.from(_meJson);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('contract shapes', () {
    test('GET /me/self-learning', () {
      final s = _state;
      expect(s.available, isTrue);
      expect(s.on, isTrue);
      expect(s.subjects, ['quran', 'nahw']);
      expect(s.lessons.single.source.type, 'nahw_lesson');
      expect(s.lessons.single.source.id, 7);
      expect(s.lessons.single.plainBody.contains('**'), isFalse);
      expect(s.reviews.first.question!.answer, 2);
      expect(s.reviews.first.question!.valid, isTrue);
      expect(s.reviews.first.lessonId, 11);
      expect(s.progress.streakDays, 5);
      expect(s.progress.perSubject['quran']!.fraction, closeTo(9 / 40, 1e-9));
      expect(s.progress.perSubject['nahw']!.fraction, closeTo(5 / 6, 1e-9), reason: 'no total: learned / (learned + due)');
      expect(s.forSubjects(kSlQuranSubjects).reviews.map((r) => r.id), [21]);
      expect(s.forSubjects({'nahw'}).lessons.map((r) => r.id), [11]);
    });

    test('tolerant reader and review answer', () {
      final s = SlState.from({'enabled': false});
      expect(s.canToggle, isTrue);
      expect(s.lessons, isEmpty);
      expect(SlState.from({'available': false}).available, isFalse);
      final r = SlReviewResult.from({
        'right': true,
        'explanation': 'x',
        'card': {'item_id': 21, 'box': 3, 'due_at': '2026-11-28T08:00:00', 'last_result': 'right'},
      });
      expect(r.right, isTrue);
      expect(r.card!.box, 3);
      expect(r.card!.dueAt, DateTime.utc(2026, 11, 28, 8));
      final page = SlItemPage.from({'items': _meJson['today'] is Map ? (_meJson['today'] as Map)['reviews'] : [], 'total': 45, 'page': 2});
      expect(page.items.length, 2);
      expect(page.pageCount, 3);
    });

    test('the admin body round-trips and the form rules', () {
      final q = _state.reviews.first;
      final back = SlItem.from(q.toJson()..['id'] = q.id);
      expect(back.question!.options, q.question!.options);
      expect(back.lessonId, 11);
      expect(slItemProblem(q), isNull);
      expect(slItemProblem(const SlItem(id: 0, subject: 'nahw', kind: 'lesson', title: 'x')), isNotNull, reason: 'a lesson needs its text');
      expect(
          slItemProblem(const SlItem(
              id: 0, subject: 'fiqh', kind: 'question', title: 'x', question: SlQuestion(prompt: 'p', options: ['a', ''], answer: 0))),
          isNotNull);
    });
  });

  group('review round', () {
    test('answer → feedback → next → done', () async {
      final sent = <(int, int)>[];
      final s = SlReviewSession(
        items: _state.reviews,
        submit: (id, choice, cid) async {
          sent.add((id, choice));
          return const SlReviewResult(right: true, explanation: 'من الخادم');
        },
        clientId: () => 'client-0001',
      );
      expect(s.phase, SlReviewPhase.answering);
      final f = s.answer(2);
      expect(s.right, isTrue, reason: 'graded on the device at once');
      expect(s.phase, SlReviewPhase.feedback);
      await f;
      expect(s.explanation, 'من الخادم');
      await s.answer(0);
      expect(sent.length, 1, reason: 'one answer per question');
      s.next();
      await s.answer(0);
      expect(s.right, isFalse);
      expect(s.rightCount, 1);
      s.next();
      expect(s.phase, SlReviewPhase.done);
      expect(sent.map((e) => e.$1), [21, 22]);
    });

    test('offline: kept in the outbox under the same client_id', () async {
      final fake = FakeApi({
        'POST /api/v1/me/self-learning/reviews/21': (_) => throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/'), reason: 'offline'),
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      mockRequestPlugins();
      final queued = <String, Map<String, dynamic>>{};
      final api = SlApi(enqueue: (id, p) async {
        queued[id] = p;
        return EnqueueResult.queued;
      });
      final s = SlReviewSession(
          items: [_state.reviews.first],
          submit: (id, c, cid) => api.review(id, choice: c, clientId: cid),
          clientId: () => 'client-offline-1');
      await s.answer(1);
      expect(s.right, isFalse);
      expect(s.queued, isTrue);
      expect(s.error, isNull);
      expect(queued, {
        'client-offline-1': {'item_id': 21, 'choice': 1},
      });
    });

    test('a server refusal keeps the verdict and shows the error', () async {
      final s = SlReviewSession(
          items: [_state.reviews.first],
          submit: (_, _, _) async => throw Exception('x'),
          clientId: () => 'client-0002');
      await s.answer(2);
      expect(s.right, isTrue);
      expect(s.error, isNotNull);
    });
  });

  test('API paths over FakeApi', () async {
    final fake = FakeApi({
      'GET /api/v1/me/self-learning': (_) => _meJson,
      'PUT /api/v1/me/self-learning': (o) => {...o.data as Map, 'can_toggle': true},
      'POST /api/v1/me/self-learning/lessons/11/seen': (_) => {'ok': true},
      'POST /api/v1/me/self-learning/reviews/21': (o) => {'right': (o.data as Map)['choice'] == 2, 'explanation': 'e'},
      'GET /api/v1/admin/self-learning/items': (o) => {'items': (_meJson['today'] as Map)['reviews'], 'total': 2, 'page': 1},
      'POST /api/v1/admin/self-learning/items/reorder': (_) => {'ok': true},
    }, latency: Duration.zero);
    fake.install();
    addTearDown(fake.uninstall);
    mockRequestPlugins();
    final api = SlApi();
    expect((await api.me()).reviews.length, 2);
    expect((await api.update(enabled: false, subjects: ['fiqh'])).subjects, ['fiqh']);
    await api.seen(11);
    expect((await api.review(21, choice: 2, clientId: 'abcdefgh-1')).right, isTrue);
    expect((await api.items(subject: 'quran', kind: 'question')).total, 2);
    await api.reorder([22, 21]);
    final itemsCall = fake.calls.firstWhere((c) => c.path == '/api/v1/admin/self-learning/items');
    expect(itemsCall.query['subject'], 'quran');
    expect(fake.unmatched, isEmpty);
  });

  test('the admin switch off reads as the off state', () async {
    final fake = FakeApi({
      'GET /api/v1/me/self-learning': (_) => const FakeResponse(403, {
            'detail': {'code': 'feature_disabled', 'message': 'off'}
          }),
    }, latency: Duration.zero);
    fake.install();
    addTearDown(fake.uninstall);
    mockRequestPlugins();
    final s = await SlApi().me();
    expect(s.available, isFalse);
  });

  group('layout', () {
    testWidgets('daily view (on, off, paused, loading)', (tester) async {
      for (final st in <SlState?>[_state, SlState.off, SlState.from({'enabled': false, 'can_toggle': false}), null]) {
        await expectNoLayoutErrors(tester, () => SlDailyView(state: st, submit: (_, _, _) async => const SlReviewResult(right: true)));
      }
    });

    testWidgets('review card: answered right (celebration) and wrong, offline note', (tester) async {
      final item = _state.reviews.first;
      await expectNoLayoutErrors(
          tester,
          () => ListView(children: [
                SlReviewCard(item: item, picked: 2, right: true, explanation: 'سورة الفاتحة سبع آيات.', onNext: () {}),
                SlReviewCard(item: item, picked: 0, right: false, explanation: 'x', queued: true, error: 'تعذّر', index: 1, total: 3, onNext: () {}),
              ]));
    });

    testWidgets('tab section and lesson card', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => ListView(children: [
                SlTodaySection(state: _state.forSubjects(kSlQuranSubjects), submit: (_, _, _) async => const SlReviewResult(right: true), onSeeAll: () {}),
                SlTodaySection(state: SlState.from({'enabled': false}), submit: (_, _, _) async => const SlReviewResult(right: true), onSeeAll: () {}),
                SlLessonCard(item: _state.lessons.single, onGotIt: () {}),
                const SlOffState(),
              ]));
    });

    testWidgets('tap an option: instant feedback, then Next', (tester) async {
      await tester.pumpWidget(layoutHost(ListView(children: [
        SlReviewRunner(items: _state.reviews, submit: (_, _, _) async => const SlReviewResult(right: true)),
      ])));
      await tester.tap(find.text('سبع'));
      await tester.pump();
      expect(find.byKey(const ValueKey('learn.feedback.action')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('learn.feedback.action')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('أي الكلمات فعل؟'), findsOneWidget);
    });

    testWidgets('admin list and item form', (tester) async {
      final page = SlItemPage(items: [..._state.lessons, ..._state.reviews], total: 45, page: 1);
      await expectNoLayoutErrors(tester, () => ListView(children: [SlAdminListBody(data: page, subject: 'quran', onReorder: (_, _) {})]));
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: SlItemForm(initial: _state.reviews.first, onSave: (_) async => null)));
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: SlItemForm(kind: 'lesson', subject: 'nahw', onSave: (_) async => null)));
    });
  });

  test('progress ring semantics stay stable', () {
    expect(slDaysText(1), isNotEmpty);
  });
}
