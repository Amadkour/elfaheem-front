// Certificate issuing — no overflow on a phone (320×640) or a wide window (1400×900), Arabic and English, text ×1.3
// (layout_harness.dart), for every step's presentational widget, the history list, a batch, a saved list and the
// public verification page (lib/features/shared/certificates_issue/).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_expiry_card.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_history.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_lists.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_parts.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_verify_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _cols = [
  IssueColumn(key: 'student_name', labelAr: 'اسم الطالب', labelEn: 'Student name'),
  IssueColumn(key: 'course_name', labelAr: 'اسم الدورة', labelEn: 'Course name'),
  IssueColumn(key: 'grade', labelAr: 'التقدير', labelEn: 'Grade'),
  IssueColumn(key: 'hours', labelAr: 'عدد الساعات', labelEn: 'Hours'),
  IssueColumn(key: 'email', labelAr: 'البريد الإلكتروني', labelEn: 'Email', required: false),
];

const _students = [
  StudentBrief(id: 1, name: 'سارة علي محمود عبد الرحمن', username: 'sara.ali.mahmoud', emailHint: 's***@university.example.com'),
  StudentBrief(id: 2, name: 'Omar Hassan Abdelrahman Mostafa', username: 'omar', emailHint: 'o***@mail.com'),
  StudentBrief(id: 3, name: 'Mona Adel'),
];

// A 1×1 transparent PNG.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

RecipientDraft _draft() {
  final d = RecipientDraft(columns: _cols);
  d.addChecked(jsonDecode(File('test/fixtures/cert_issue/check.json').readAsStringSync()) as Map<String, dynamic>);
  d.addStudents([_students[0]]);
  d.addManual({'student_name': 'A very long manual recipient name that keeps going and going', 'grade': 'Excellent with honours'});
  return d;
}

IssueBatch _batch(String status) => IssueBatch.fromJson({
      'id': 7,
      'mode': 'standalone',
      'title': 'شهادات دفعة أكتوبر للبرمجة المتقدمة وتطوير التطبيقات',
      'status': status,
      'total': 1200,
      'done': status == 'done' ? 1180 : 430,
      'failed': 20,
      'emailed': 1100,
      'email_failed': 80,
      'email': true,
      'has_zip': status == 'done',
      'has_pdf': status == 'done',
      'created_by': 5,
      'langs': ['ar', 'en'],
      'created_at': '2026-10-31T09:30:00',
      'error': status == 'failed' ? 'every recipient failed' : null,
    });

final _issued = [
  IssuedCert.fromJson({
    'id': 1, 'serial': 'NB-2026-ABCDEF', 'recipient_name': 'سارة علي محمود عبد الرحمن الطويل جدًا', 'status': 'issued',
    'url_ar': 'https://x/a.png', 'verify_url': 'https://nextbrain.site/verify/abc', 'emailed': true,
    'created_at': '2026-10-31T09:31:00',
  }),
  IssuedCert.fromJson({
    'id': 2, 'serial': 'NB-2026-QWERTY', 'recipient_name': 'Omar Hassan', 'student_id': 4, 'status': 'revoked',
    'revoked_reason': 'Issued by mistake to the wrong person, a second time with a longer reason',
    'url_en': 'https://x/e.png', 'created_at': '2026-10-31T09:32:00',
  }),
];

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  testWidgets('step header and bottom bar', (tester) async {
    await expectNoLayoutErrors(tester, () => Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: IssueStepper(labels: ['ci_step_how'.tr, 'ci_step_who'.tr, 'ci_step_preview'.tr, 'ci_step_issue'.tr], current: 1, onTap: (_) {}),
          ),
          const Spacer(),
          IssueStepBar(onBack: () {}, summary: _draft().summary.label, nextLabel: 'ci_issue_n'.tr.replaceAll('{n}', '1200'), onNext: () {}),
          IssueStepBar(nextLabel: 'ci_next'.tr, onNext: null, busy: true),
        ]));
  });

  testWidgets('step 1: mode, course list and shared values', (tester) async {
    final ctrls = {for (final c in _cols.skip(1)) c.key: TextEditingController(text: c.key == 'hours' ? '30' : '')};
    await expectNoLayoutErrors(tester, () => _scroll(IssueModeStep(
          mode: IssueMode.course,
          onMode: (_) {},
          courseArea: Column(children: [
            IssueCourseList(
              courses: const [
                (id: 1, name: 'أساسيات البرمجة وتطوير التطبيقات للمبتدئين — الفصل الدراسي الأول', students: 1240),
                (id: 2, name: 'Data structures', students: null),
              ],
              selectedId: 1,
              onPick: (_) {},
            ),
            const IssueCourseList(courses: [], selectedId: null, onPick: _noop),
            IssueCourseList(courses: const [], selectedId: null, onPick: _noop, error: 'ci_load_failed'.tr, onRetry: () {}),
            IssueConstantsForm(columns: _cols.skip(1).toList(), controllers: ctrls),
          ]),
        )));
  });

  testWidgets('step 2: paste, upload and search panels', (tester) async {
    final paste = TextEditingController(text: 'سارة علي, ممتاز\nOmar, A');
    final search = TextEditingController(text: 'sa');
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          SizedBox(width: double.infinity, child: IssueRecipientTabs(tab: RecipientTab.paste, onTab: (_) {})),
          const SizedBox(height: 16),
          IssuePastePanel(columns: _cols, controller: paste, onChanged: (_) {}, parsedCount: 2),
          IssuePastePanel(columns: _cols, controller: paste, onChanged: (_) {}, checking: true),
          IssuePastePanel(columns: _cols, controller: paste, onChanged: (_) {}, error: 'ci_file_too_big'.tr),
          IssueUploadPanel(columns: _cols, onPick: () {}, onSample: (_) {}, fileName: 'October batch of the advanced programming course final.xlsx', parsedCount: 1200),
          IssueUploadPanel(columns: _cols, onPick: () {}, onSample: (_) {}, busy: true),
          IssueSearchPanel(
            controller: search,
            onQuery: (_) {},
            results: _students,
            selected: const {1},
            onToggle: (_, _) {},
            onSelectAll: () {},
            total: 240,
            filter: const SizedBox(height: 48),
          ),
          IssueSearchPanel(controller: search, onQuery: (_) {}, results: const [], selected: const {}, onToggle: (_, _) {}, onSelectAll: null, needsFilter: true),
          IssueSearchPanel(controller: search, onQuery: (_) {}, results: const [], selected: const {}, onToggle: (_, _) {}, onSelectAll: null),
          IssueSearchPanel(controller: search, onQuery: (_) {}, results: const [], selected: const {}, onToggle: (_, _) {}, onSelectAll: null, loading: true),
        ])));
  });

  testWidgets('step 2: the review list', (tester) async {
    await expectNoLayoutErrors(tester, () {
      final d = _draft();
      return ListView(padding: const EdgeInsets.all(16), children: [
        IssueReviewHeader(
          summary: d.summary,
          filter: ReviewFilter.all,
          onFilter: (_) {},
          manualDefault: true,
          onManualDefault: (_) {},
          onRemoveDuplicates: () {},
          onClear: () {},
        ),
        const SizedBox(height: 12),
        for (final e in d.review())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IssueReviewRow(
              row: e.row,
              state: e.state,
              issues: e.issues,
              columns: d.columns,
              manual: d.manualOf(e.row),
              onEdit: () {},
              onRemove: () {},
              onPickCandidate: (_) {},
              onManual: (_) {},
            ),
          ),
      ]);
    });
  });

  testWidgets('step 3: languages and preview', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          IssueLangPicker(available: const ['ar', 'en'], selected: const {'ar', 'en'}, onChanged: (_) {}),
          const SizedBox(height: 16),
          IssuePreviewPanel(langs: const ['ar', 'en'], lang: 'ar', onLang: (_) {}, images: {'ar': _png}, recipientName: 'سارة علي محمود عبد الرحمن'),
          IssuePreviewPanel(langs: const ['ar', 'en'], lang: 'en', onLang: (_) {}, images: const {}, loading: true),
          IssuePreviewPanel(langs: const ['ar'], lang: 'ar', onLang: (_) {}, images: const {}, error: 'ci_load_failed'.tr, onRetry: () {}),
        ])));
  });

  testWidgets('step 4: batch progress, running and done', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          IssueBatchProgressCard(batch: _batch('running')),
          const SizedBox(height: 12),
          IssueBatchProgressCard(batch: _batch('done'), onZip: () {}, onPdf: () {}, onViewIssued: () {}, onIssueMore: () {}, downloading: 'zip'),
          const SizedBox(height: 12),
          IssueBatchProgressCard(batch: _batch('failed'), onIssueMore: () {}),
        ])));
  });

  testWidgets('history list and a batch', (tester) async {
    await expectNoLayoutErrors(tester, () => CertBatchList(
          items: [_batch('done'), _batch('running'), _batch('failed')],
          total: 10,
          meId: 5,
          selectedId: 7,
          onOpen: (_) {},
        ));
    await expectNoLayoutErrors(tester, () => const CertBatchList(items: [], onOpen: _noopBatch));
    final q = TextEditingController(text: 'NB-2026');
    await expectNoLayoutErrors(tester, () => CertBatchBody(
          batch: _batch('done'),
          query: q,
          onQuery: (_) {},
          status: 'issued',
          onStatus: (_) {},
          items: _issued,
          total: 40,
          onZip: () {},
          onPdf: () {},
          onView: (_) {},
          onCopyLink: (_) {},
          onRevoke: (_) {},
          onReissue: (_) {},
        ));
  });

  testWidgets('saved lists', (tester) async {
    final list = RecipientListInfo.fromJson({
      'id': 3,
      'name': 'دفعة أكتوبر — طلاب البرمجة المتقدمة وتطوير التطبيقات',
      'count': 2,
      'updated_at': '2026-10-30T12:00:00',
      'columns': [for (final c in _cols) c.toJson()],
      'rows': [
        {'values': {'student_name': 'سارة علي محمود عبد الرحمن', 'grade': 'ممتاز', 'hours': '30'}, 'email': 'sara@example.com', 'student_id': 1},
        {'values': {'student_name': 'Mona Adel'}},
      ],
    });
    await expectNoLayoutErrors(tester, () => Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: IssueSavedListTile(list: list, onTap: () {})),
          Expanded(child: CertListBody(list: list, columns: _cols, onAddPerson: () {}, onIssueAll: () {}, onRemove: (_) {})),
        ]));
    await expectNoLayoutErrors(tester, () => CertListBody(list: list, columns: _cols, canIssue: false, loading: true));
  });

  testWidgets('public verification page', (tester) async {
    final valid = VerifyResult.fromJson({
      'valid': true,
      'status': 'issued',
      'serial': 'NB-2026-ABCDEF',
      'recipient_name': 'سارة علي محمود عبد الرحمن',
      'title': 'شهادة إتمام دورة أساسيات البرمجة وتطوير التطبيقات',
      'issuer': 'جامعة الاختبار — كلية الحاسبات والمعلومات',
      'issued_at': '2026-10-31T09:31:00',
      'langs': ['ar', 'en'],
      'images': {'ar': 'https://x/a.png', 'en': 'https://x/e.png'},
    });
    final revoked = VerifyResult.fromJson({
      'valid': false, 'status': 'revoked', 'serial': 'NB-2026-QWERTY', 'recipient_name': 'Omar Hassan',
      'revoked_at': '2026-10-31T10:00:00', 'langs': ['en'], 'images': {'en': 'https://x/e.png'},
    });
    Widget box(String _) => const AspectRatio(aspectRatio: 1.414, child: ColoredBox(color: Colors.white));
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.found, result: valid, lang: 'ar', onLang: (_) {}, imageBuilder: box));
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.found, result: revoked, imageBuilder: box));
    await expectNoLayoutErrors(tester, () => const CertVerifyView(state: VerifyState.notFound));
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.notFound, queried: 'NB-2026-AAAAAA', onAnother: () {}));
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.foreign, foreignHost: 'a-very-long-subdomain.of-some-untrusted-host.example.com', onAnother: () {}));
    final ctl = TextEditingController();
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.entry, entry: CertVerifyEntry(controller: ctl, onSubmit: () {}, onScan: () {})));
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.entry, entry: CertVerifyEntry(controller: ctl, onSubmit: () {}, fieldError: 'x' * 90)));
    for (final name in const ['real', 'expired', 'no_expiry', 'revoked', 'number', 'number_masked']) {
      final r = VerifyResult.fromJson((jsonDecode(File('test/fixtures/payloads/cert_verify_$name.json').readAsStringSync()) as Map).cast());
      await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.found, result: r, lang: 'ar', onLang: (_) {}, imageBuilder: box, onAnother: () {}));
    }
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CertExpiryCard(value: DateTime(2030, 6, 30), onChanged: (_) {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CertExpiryCard(value: null, onChanged: (_) {})));
    await expectNoLayoutErrors(tester, () => CertVerifyView(state: VerifyState.error, onRetry: () {}));
    await expectNoLayoutErrors(tester, () => const CertVerifyView(state: VerifyState.loading));
  });
}

void _noop(int _) {}
void _noopBatch(IssueBatch _) {}
