import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/rag/library/rag_doc_status.dart';
import 'package:flutter_education_app/features/shared/rag/library/rag_upload_scope.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

RagConflictPlan get _plan => const RagConflictPlan(existing: 0, matching: 0, fresh: 1);

Widget _batch(List<String> options, String scope, {Set<String> roles = const {}, List<RagCourseChoice> courses = const [], bool? ocr}) => SingleChildScrollView(
      child: RagBatchUploadForm(
        files: const [('a-very-long-file-name-for-the-regulation-of-students-affairs.pdf', 2345678)],
        scopes: options,
        scope: scope,
        plan: _plan,
        mode: RagConflictMode.keep,
        onPick: () {},
        onRemove: (_) {},
        onScope: (_) {},
        onMode: (_) {},
        onSubmit: () {},
        roles: roles,
        onRoles: (_) {},
        courses: courses,
        onCourse: (_) {},
        ocrScanned: ocr,
        maxMb: 30,
        error: 'a.pdf: The file is larger than the allowed 30 MB',
      ),
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  final courses = [for (var i = 1; i <= 3; i++) RagCourseChoice(i, 'مقرر تجريبي طويل الاسم جداً رقم $i — Introduction to Distributed Systems')];

  testWidgets('upload sheet: super admin', (t) async {
    await expectNoLayoutErrors(t, () => _batch(const ['app', 'global'], 'app'));
  });
  testWidgets('upload sheet: org admin, org scope with roles', (t) async {
    await expectNoLayoutErrors(t, () => _batch(const ['org', 'staff', 'course'], 'org', roles: {'teacher', 'student'}, ocr: true));
  });
  testWidgets('upload sheet: org admin, course picker', (t) async {
    await expectNoLayoutErrors(t, () => _batch(const ['org', 'staff', 'course'], 'course', courses: courses));
  });
  testWidgets('upload sheet: teacher (one scope, no chips)', (t) async {
    await expectNoLayoutErrors(t, () => _batch(const ['course'], 'course'));
  });
  testWidgets('single upload form with the hint', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagUploadForm(orgId: 1, onSubmit: (_) {}, ocrScanned: false)));
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagUploadForm(courseId: 9, onSubmit: (_) {}, pickFile: () async => ('a.pdf', Uint8List(4)))));
  });
  testWidgets('hint, progress row, warnings chip, excluded line', (t) async {
    final warnings = [
      RagWarning.fromJson({'code': 'partially_scanned', 'pages': List.generate(40, (i) => i + 3), 'ar': 'تم تخطي بعض الصفحات (ممسوحة ضوئياً)', 'en': 'Some pages were skipped (scanned)'})
    ];
    await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const RagUploadHint(ocrScanned: true, maxMb: 30),
              const RagUploadHint(ocrScanned: false),
              const RagProgressRow(done: 12, total: 80),
              const RagProgressRow(done: 0, total: 0),
              RagWarningChips(warnings: warnings),
              RagExcludedText(excluded: const [RagExcluded('cover'), RagExcluded('publisher'), RagExcluded('toc'), RagExcluded('references'), RagExcluded('index')]),
            ])));
  });
  testWidgets('document cards: processing with progress, warnings, failed without text', (t) async {
    final base = {'id': 1, 'title': 'لائحة شؤون الطلاب الطويلة جداً', 'filename': 'a.pdf', 'scope': 'org', 'pages': 80};
    final docs = [
      RagDocument.fromJson({...base, 'status': 'processing', 'progress_done': 12, 'progress_total': 80}),
      RagDocument.fromJson({
        ...base,
        'status': 'ready',
        'warnings': [
          {'code': 'partially_scanned', 'pages': [3, 7], 'ar': 'تم تخطي بعض الصفحات', 'en': 'Some pages were skipped (scanned)'}
        ],
        'excluded': [
          {'kind': 'toc', 'pages': [2]}
        ]
      }),
      RagDocument.fromJson({...base, 'status': 'failed', 'error': 'no_readable_text: nothing'}),
    ];
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [for (final d in docs) RagDocumentCard(doc: d, manager: true, onDownload: () {})])));
  });
}
