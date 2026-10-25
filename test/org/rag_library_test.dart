import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _doc(int id, {String status = 'ready', String scope = 'org', int? course, String? error, int version = 1}) => {
      'id': id, 'org_id': 1, 'title': 'لائحة شؤون الطلاب والخريجين الطويلة جداً رقم $id', 'filename': 'reg$id.pdf', 'kind': 'pdf', 'scope': scope,
      'course_id': course, 'version': version, 'family_id': id, 'status': status, 'pages': 12, 'chunks': 40, 'size': 2345678,
      'created_at': '2026-03-01T10:00:00Z', 'error': error, 'ocr_pages': 2,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('library parsing', () {
    final lib = RagLibrary.fromJson({
      'manager': true,
      'items': [_doc(1), _doc(2, status: 'queued'), _doc(3, status: 'processing'), _doc(4, status: 'failed', error: 'bad_pdf'), _doc(5, scope: 'course', course: 9), _doc(6, status: 'archived')]
    });
    test('documents, flags and counts', () {
      expect(lib.manager, isTrue);
      expect(lib.items.length, 6);
      expect(lib.hasBusy, isTrue);
      expect(lib.counts()['ready'], 2);
      expect(lib.filtered('failed').single.id, 4);
      expect(lib.filtered('').length, 6);
      expect(lib.items[1].busy, isTrue);
      expect(lib.items[3].canReindex, isTrue);
      expect(lib.items[1].canReindex, isFalse);
      expect(lib.items[5].archived, isTrue);
      expect(RagLibrary.fromJson({}).manager, isFalse);
      expect(RagLibrary.fromJson({'items': [_doc(1)]}).hasBusy, isFalse);
    });
    test('replaceable: same scope, not archived, same course', () {
      expect(lib.replaceable('org').map((d) => d.id), [1, 2, 3, 4]);
      expect(lib.replaceable('course', courseId: 9).map((d) => d.id), [5]);
      expect(lib.replaceable('course', courseId: 10), isEmpty);
    });
    test('a document without a title shows its file name; sizes are readable', () {
      expect(RagDocument.fromJson({'id': 1, 'filename': 'a.pdf'}).displayTitle, 'a.pdf');
      expect(ragSizeText(500), '500 B');
      expect(ragSizeText(2048), '2 KB');
      expect(ragSizeText(3 * 1024 * 1024), '3.0 MB');
    });
  });

  group('upload draft', () {
    Uint8List bytes([int n = 10]) => Uint8List(n);
    test('needs a file, a known type and a context', () {
      expect(RagUploadDraft().validate(orgId: 1), 'file_required');
      expect(RagUploadDraft(fileName: 'a.pdf', fileBytes: bytes(0)).validate(orgId: 1), 'empty_file');
      expect(RagUploadDraft(fileName: 'a.exe', fileBytes: bytes()).validate(orgId: 1), 'unsupported_type');
      expect(RagUploadDraft(fileName: 'a.PDF', fileBytes: bytes()).validate(orgId: 1), isNull);
      expect(RagUploadDraft(fileName: 'notes', fileBytes: bytes()).validate(orgId: 1), isNull);
      expect(RagUploadDraft(fileName: 'a.pdf', fileBytes: bytes()).validate(), 'org_required');
      expect(RagUploadDraft(fileName: 'a.pdf', fileBytes: Uint8List(ragMaxUploadBytes + 1)).validate(orgId: 1), 'file_too_large');
    });
    test('a course document needs a course id (typed or fixed)', () {
      final d = RagUploadDraft(fileName: 'a.docx', fileBytes: bytes(), scope: 'course');
      expect(d.validate(orgId: 1), 'course_required');
      d.courseId = 'x';
      expect(d.validate(orgId: 1), 'course_required');
      d.courseId = '٧';
      expect(d.validate(orgId: 1), isNull);
      expect(d.courseIdValue, 7);
      expect(RagUploadDraft(fileName: 'a.docx', fileBytes: bytes(), scope: 'course').validate(fixedCourseId: 3), isNull);
      expect(RagUploadDraft(fileName: 'a.pdf', fileBytes: bytes(), scope: 'galaxy').validate(orgId: 1), 'bad_scope');
    });
    test('multipart fields', () {
      final d = RagUploadDraft(title: ' Rules ', scope: 'staff', replaces: 5, fileName: 'a.pdf', fileBytes: bytes());
      expect(d.fields(orgId: 2), {'title': 'Rules', 'scope': 'staff', 'org_id': 2, 'replaces': 5});
      final c = RagUploadDraft(scope: 'course', courseId: '9');
      expect(c.fields(orgId: 2, fixedCourseId: null)['course_id'], 9);
      expect(RagUploadDraft().fields().containsKey('replaces'), isFalse);
    });
  });

  group('settings and feedback', () {
    test('settings parse and the body drops the external flag unless llm', () {
      final s = RagOrgSettings.fromJson({'generator': 'llm', 'allow_external_llm': true, 'llm_available': true, 'llm_external': true});
      expect((s.generator, s.allowExternal, s.llmAvailable, s.llmExternal), ('llm', true, true, true));
      expect(RagOrgSettings.fromJson({'generator': 'weird'}).generator, 'extractive');
      expect(RagOrgSettings.body('llm', true), {'generator': 'llm', 'allow_external_llm': true});
      expect(RagOrgSettings.body('extractive', true), {'generator': 'extractive', 'allow_external_llm': false});
    });
    test('answer feedback parse and share', () {
      final f = RagAnswerFeedback.fromJson({
        'answered': 20, 'rated': 8, 'helpful': 6, 'not_found': 3,
        'unhelpful': [
          {'id': 1, 'question': 'متى؟', 'found': false, 'comment': null, 'citations': [{'title': 'Reg', 'section': 'Art 1'}, {'title': 'Fees'}], 'at': '2026-03-01T10:00:00Z'}
        ]
      });
      expect(f.helpfulShare, 0.75);
      expect(f.unhelpful.single.sources, ['Reg › Art 1', 'Fees']);
      expect(f.unhelpful.single.comment, '');
      expect(RagAnswerFeedback.fromJson({}).helpfulShare, isNull);
    });
    test('codes are bilingual; chat codes still resolve', () {
      expect(ragLibraryCodeText('not_library_manager', 'x'), isNot('x'));
      expect(ragLibraryCodeText('document_busy', 'x'), isNot('x'));
      expect(ragLibraryCodeText('too_many_requests', 'x'), isNot('x'));
      expect(ragLibraryCodeText('zzz', 'raw'), 'raw');
      AppConfig.lang = 'ar';
      expect(ragLibraryCodeText('file_too_large', 'x'), contains('30'));
      expect(ragStatusText('ready'), 'جاهز');
    });
  });

  group('layout', () {
    final docs = [
      RagDocument.fromJson(_doc(1)),
      RagDocument.fromJson(_doc(2, status: 'processing')),
      RagDocument.fromJson(_doc(3, status: 'failed', error: 'The PDF is invalid or password-protected, so nothing could be read from it')),
    ];
    testWidgets('document cards', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  for (final d in docs) RagDocumentCard(doc: d, manager: true, onDownload: () {}, onReindex: d.canReindex ? () {} : null, onArchive: () {}, onNewVersion: () {}),
                ]),
              ));
      await expectNoLayoutErrors(t, () => RagDocumentCard(doc: docs.first, onDownload: () {}));
    });
    testWidgets('upload form', (t) async {
      final lib = RagLibrary.fromJson({'items': [_doc(1), _doc(2)], 'manager': true});
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagUploadForm(orgId: 1, library: lib, onSubmit: (_) {}, error: 'The file is larger than 30 MB')));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagUploadForm(courseId: 9, onSubmit: (_) {}, replaces: docs.first)));
    });
    testWidgets('settings form', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagSettingsForm(settings: const RagOrgSettings(generator: 'llm', allowExternal: true, llmAvailable: true, llmExternal: true), onSave: (_, _) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagSettingsForm(settings: const RagOrgSettings(), onSave: (_, _) {})));
    });
    testWidgets('unhelpful answers', (t) async {
      final f = RagAnswerFeedback.fromJson({
        'answered': 200, 'rated': 80, 'helpful': 60, 'not_found': 30,
        'unhelpful': [
          for (var i = 0; i < 3; i++)
            {'id': i, 'question': 'ما هي شروط الحرمان من الامتحان النهائي بسبب الغياب في المقررات العملية؟', 'found': false, 'comment': 'لم أجد الإجابة ' * 6, 'citations': [{'title': 'لائحة شؤون الطلاب ' * 3, 'section': 'المادة 5'}], 'at': '2026-03-01T10:00:00Z'}
        ]
      });
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagFeedbackView(feedback: f)));
      await expectNoLayoutErrors(t, () => RagFeedbackView(feedback: RagAnswerFeedback.fromJson({})));
    });
  });
}
