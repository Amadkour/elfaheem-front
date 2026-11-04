import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_media.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_taking.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

final _id = '${'ab' * 32}.png';
// a 1x1 transparent PNG
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, dynamic> _placed(int pid, int qid, {Map<String, dynamic>? media}) => {
      'id': qid, 'type': 'mcq_single', 'tags': <String>[], 'difficulty': 4, 'status': 'active', 'current_version': 1, 'version': 1,
      'body': {'prompt': 'Question $qid', 'options': [{'id': 'a', 'text': 'A'}, {'id': 'b', 'text': 'B'}], if (media != null) 'media': [media]},
      'answer': {'correct': 'a'}, 'points': 2, 'placement_id': pid, 'position': pid, 'required': false, 'pinned_version': 1, 'outdated': false,
    };

ExamView _view() => ExamView.fromJson({
      'id': 5, 'title': 'E', 'status': 'draft', 'version': 1, 'max_score': 6,
      'sections': [
        for (final sid in [1, 2])
          {'id': sid, 'position': sid - 1, 'title': 'Sec $sid', 'mode': 'online', 'weight': 1, 'navigation': 'free', 'pool_tags': [],
            'questions': sid == 1 ? [_placed(1, 11), _placed(2, 12), _placed(3, 13)] : []},
      ],
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('pure', () {
    test('media file validation', () {
      expect(validateMediaFile('a.png', 100), isNull);
      expect(validateMediaFile('A.JPG', 100), isNull);
      expect(validateMediaFile('a.gif', 100), 'question_media_type');
      expect(validateMediaFile('a', 100), 'question_media_type');
      expect(validateMediaFile('a.png', 0), 'question_media_empty');
      expect(validateMediaFile('a.png', questionMediaMaxBytes + 1), 'question_media_too_big');
    });

    test('media list validation and body round trip', () {
      expect(validateMediaList(null), isEmpty);
      expect(validateMediaList([{'id': _id, 'alt': 'x'}]), isEmpty);
      expect(validateMediaList([{'id': 'bad'}]), ['question_media_invalid']);
      expect(validateMediaList([{'id': _id}, {'id': _id}]), ['question_media_too_many']);
      expect(validateMediaList([{'id': _id, 'alt': 'x' * 201}]), ['question_media_alt_long']);
      final d = QuestionDraft.fromJson(_placed(1, 11, media: {'id': _id, 'alt': 'a cell'}));
      expect(d.media, QuestionMedia(_id, 'a cell'));
      expect(d.body()['media'], [{'id': _id, 'alt': 'a cell'}]);
      d.media = null;
      expect(d.body().containsKey('media'), isFalse);
      d.media = QuestionMedia(_id);
      expect(d.body()['media'], [{'id': _id}]);
      expect(BankQuestion.fromJson(_placed(1, 11, media: {'id': _id})).media?.id, _id);
    });

    test('reorder ids follow ReorderableListView semantics', () {
      expect(reorderIds([1, 2, 3], 0, 3), [2, 3, 1]);
      expect(reorderIds([1, 2, 3], 2, 0), [3, 1, 2]);
      expect(reorderIds([1, 2, 3], 0, 1), [1, 2, 3]);
      expect(reorderIds([1, 2, 3], 1, 3), [1, 3, 2]);        // "down" = index + 2
      expect(reorderIds([1, 2, 3], 9, 0), [1, 2, 3]);
    });

    test('bank paging: old and new shapes, no duplicates', () {
      final paging = BankPaging();
      paging.add(BankPage.fromResult({'items': [_placed(1, 3), _placed(2, 2)], 'next_before': 2, 'scan_capped': false}));
      expect(paging.hasMore, isTrue);
      paging.add(BankPage.fromResult({'items': [_placed(2, 2), _placed(3, 1)], 'next_before': null}));
      expect([for (final q in paging.items) q.id], [3, 2, 1]);
      expect(paging.hasMore, isFalse);
      final old = BankPage.fromResult({'items': [_placed(1, 3)]});
      expect(old.nextBefore, isNull);
      expect(BankPage.fromResult({'value': [_placed(1, 3)]}).items.length, 1);       // a bare list
      paging.reset();
      expect(paging.items, isEmpty);
    });

    test('bytes cache is an LRU and shares loads', () async {
      final cache = MediaBytesCache(maxEntries: 2);
      var loads = 0;
      Future<Uint8List> fetch() async {
        loads++;
        return _png;
      }
      await Future.wait([cache.load('a', fetch), cache.load('a', fetch)]);
      expect(loads, 1);
      await cache.load('b', fetch);
      await cache.load('a', fetch);          // touch a
      await cache.load('c', fetch);          // evicts b
      expect(cache.peek('b'), isNull);
      expect(cache.peek('a'), isNotNull);
      expect(loads, 3);
    });

    test('paper question exposes its image', () {
      final q = PaperQuestion(questionId: 1, type: 'mcq_single', points: 1, sectionIndex: 0, index: 0,
          body: {'prompt': 'p', 'media': [{'id': _id, 'alt': 'alt'}]});
      expect(q.image, (id: _id, alt: 'alt'));
    });
  });

  group('api', () {
    test('upload goes to /questions/media with the org, reorder and move send their bodies', () async {
      final seen = <String>[];
      Object? orderBody;
      final fake = FakeApi({
        'POST /api/v1/exam/questions/media': (o) {
          seen.add('${o.method} ${o.uri.path}?${o.uri.query}');
          return FakeResponse(201, {'id': _id, 'name': 'a.png', 'content_type': 'image/png', 'size': 10, 'sha256': 'ab' * 32});
        },
        'PUT /api/v1/exam/exams/5/sections/1/questions/order': (o) {
          orderBody = o.data;
          return FakeResponse(422, {'detail': {'code': 'order_mismatch', 'message_en': 'x'}});
        },
        'PUT /api/v1/exam/exams/5/placements/2': (o) => FakeResponse(200, {'id': 5, 'sections': []}),
      }, latency: const Duration(milliseconds: 5))
        ..install();
      addTearDown(fake.uninstall);
      final up = await QuestionMediaApi().upload(bytes: _png, fileName: 'a.png', orgId: 3, courseId: 9);
      expect(up.ok, isTrue);
      expect(up.map['id'], _id);
      expect(seen.single, contains('org_id=3&course_id=9'));
      final r = await ExamAuthoringApi().reorderQuestions(5, 1, [3, 1, 2]);
      expect(r.ok, isFalse);
      expect(authoringError(r), isNot('order_mismatch'));
      expect(orderBody, {'placement_ids': [3, 1, 2]});
      final m = await ExamAuthoringApi().movePlacement(5, 2, sectionId: 2, position: 0);
      expect(m.ok, isTrue);
    });
  });

  group('layout', () {
    testWidgets('sections panel with drag handles and image rows', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(children: [
            ExamSectionsPanel(
              view: _view(),
              onAddSection: () {},
              onEditSection: (_) {},
              onDeleteSection: (_) {},
              onMoveSection: (_, _) {},
              onAddQuestions: (_) {},
              onRemoveQuestion: (_) {},
              onEditQuestion: (_, _) {},
              onReorderQuestions: (_, _, _) {},
              onMoveQuestionToSection: (_, _) {},
            ),
          ]));
    });

    testWidgets('image field: empty, with image, with error', (tester) async {
      Widget field(QuestionMedia? m) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: QuestionImageField(
              media: m,
              onChanged: (_) {},
              preview: (m) => QuestionImage(cacheKey: 'x/${m.id}', load: () async => _png, cache: MediaBytesCache()),
              upload: (b, n) async => (null, 'boom'),
              pick: (_) async => (bytes: _png, name: 'a.png'),
            ),
          );
      await expectNoLayoutErrors(tester, () => field(null));
      await expectNoLayoutErrors(tester, () => field(QuestionMedia(_id, 'A long description of the picture ' * 4)));
    });

    testWidgets('image field uploads the picked file and reports the media', (tester) async {
      QuestionMedia? got;
      await tester.pumpWidget(layoutHost(
          QuestionImageField(
            media: null,
            onChanged: (m) => got = m,
            preview: (_) => const SizedBox(),
            upload: (b, n) async => (QuestionMedia(_id), null),
            pick: (_) async => (bytes: _png, name: 'a.png'),
          ),
      ));
      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      expect(got?.id, _id);
    });

    testWidgets('image viewer: loaded, failed, compact', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(children: [
            QuestionImage(cacheKey: 'l/1', load: () async => _png, cache: MediaBytesCache()),
            QuestionImage(cacheKey: 'l/2', load: () async => throw Exception('x'), cache: MediaBytesCache()),
            QuestionImage(cacheKey: 'l/3', load: () async => _png, compact: true, cache: MediaBytesCache()),
          ]));
    });

    testWidgets('question editor with an image and the difficulty line', (tester) async {
      final d = QuestionDraft.fromJson(_placed(1, 11, media: {'id': _id, 'alt': 'cell'}));
      await expectNoLayoutErrors(tester, () => QuestionEditorForm(draft: d, onSave: (_) async => null));
    });
  });
}
