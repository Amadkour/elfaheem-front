// Games v4 T66: the review queue and the import wizard on a phone and a wide window, ar / en, text 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/v4/import_wizard.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_review_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/review_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'سؤال طويل جدًا عن ترتيب كلمات الآية الكريمة يمتد على عدة أسطر ليختبر أن لا شيء يفيض على الشاشة الضيقة';
final _items = [
  for (var i = 1; i <= 3; i++)
    ReviewItem(
        id: i,
        type: 'sequence',
        topic: 'juz_30/112',
        promptAr: _long,
        promptEn: 'A very long question about putting the words of the ayah in order that wraps over several lines',
        subject: 'quran',
        sourceRef: '112:$i',
        preview: '@quran:112:$i · very long token list that should be trimmed to a few lines at most when shown'),
];
final _subjects = <GameSubjectRow>[
  (id: 1, key: 'quran', nameAr: 'القرآن الكريم', nameEn: 'Quran', requiresReview: true),
  (id: 2, key: 'math', nameAr: 'الرياضيات', nameEn: 'Math', requiresReview: false),
];
final _report = ImportReport.fromJson({
  'rows': 60,
  'ok': 40,
  'pending': 40,
  'created': 0,
  'errors': [
    for (var i = 2; i < 22; i++) {'row': i, 'field': 'body.options[2].text', 'why': 'duplicate'},
  ],
});

void main() {
  testWidgets('review queue + reviewers', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(children: [
              ReviewQueueBody(items: _items, total: 3, onApprove: (_) {}, onReject: (_) {}),
              ReviewersCard(
                  reviewers: const [(id: 1, name: 'محمد عبد الرحمن الطويل الاسم جدًا جدًا', username: 'a_very_long_username_here')],
                  onAdd: () {},
                  onRemove: (_) {}),
            ]));
  });

  testWidgets('review empty / loading / error', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(children: [
              ReviewQueueBody(items: const [], total: 0, onApprove: (_) {}, onReject: (_) {}),
              ReviewQueueBody(items: null, total: 0, onApprove: (_) {}, onReject: (_) {}),
              ReviewQueueBody(items: null, total: 0, error: 'x', onApprove: (_) {}, onReject: (_) {}),
            ]));
  });

  testWidgets('import wizard: result with errors, and done', (tester) async {
    Widget wiz({ImportReport? done}) => ImportWizardBody(
          subjects: _subjects,
          subjectId: 1,
          type: 'mcq',
          format: 'xlsx',
          fileName: 'a-very-long-file-name-for-the-questions-import-2026.xlsx',
          report: _report,
          done: done,
          onSubject: (_) {},
          onType: (_) {},
          onFormat: (_) {},
          onDownload: () {},
          onPick: () {},
          onCommit: () {},
          onAgain: () {},
        );
    await expectNoLayoutErrors(tester, () => ListView(children: [wiz()]));
    await expectNoLayoutErrors(tester, () => ListView(children: [wiz(done: ImportReport.fromJson({'created': 40, 'pending': 40}))]));
  });
}
