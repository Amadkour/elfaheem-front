import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/rag/library/rag_doc_status.dart';
import 'package:flutter_education_app/features/rag/library/rag_upload_scope.dart';
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base(int id, Map<String, dynamic> more) => {'id': id, 'filename': 'a.pdf', 'status': 'processing', ...more};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('document fields', () {
    test('progress, warnings, skipped pages and excluded parts', () {
      final d = RagDocument.fromJson(_base(1, {
        'progress_done': 12,
        'progress_total': 80,
        'warnings': [
          {'code': 'partially_scanned', 'pages': [3, 7], 'ar': 'تم تخطي صفحات ممسوحة', 'en': 'Some pages were skipped (scanned)'}
        ],
        'skipped_pages': [3, 7],
        'excluded': [
          {'kind': 'toc', 'pages': [2]},
          {'kind': 'references', 'pages': [79, 80]},
          {'kind': 'index', 'pages': []},
        ],
      }));
      expect(d.showProgress, isTrue);
      expect(ragProgressText(d.progressDone, d.progressTotal), '12 / 80 pages');
      expect(ragProgressValue(12, 80), closeTo(0.15, 1e-9));
      expect(d.warnings.single.line, 'Some pages were skipped (scanned): 3, 7');
      AppConfig.lang = 'ar';
      expect(d.warnings.single.line, 'تم تخطي صفحات ممسوحة: 3, 7');
      AppConfig.lang = 'en';
      expect(d.skippedPages, [3, 7]);
      expect(ragExcludedLine(d.excluded), 'Skipped: table of contents, references, index');
    });

    test('an older server without the new fields', () {
      final d = RagDocument.fromJson({'id': 2, 'filename': 'a.pdf', 'status': 'processing'});
      expect(d.progressTotal, 0);
      expect(d.showProgress, isFalse);
      expect(d.warnings, isEmpty);
      expect(d.excluded, isEmpty);
      expect(ragExcludedLine(d.excluded), '');
      expect(ragProgressText(0, 0), '');
      expect(ragProgressValue(0, 0), isNull);
    });

    test('progress shows only while processing', () {
      expect(RagDocument.fromJson(_base(3, {'status': 'ready', 'progress_total': 80, 'progress_done': 80})).showProgress, isFalse);
    });

    test('an unknown warning code falls back to its own text, a missing language to ours', () {
      final w = RagWarning.fromJson({'code': 'partially_scanned', 'pages': [1]});
      expect(w.line, 'Some pages were skipped (scanned): 1');
    });

    test('failed no_readable_text reads as a clear sentence', () {
      expect(ragDocErrorText('no_readable_text: nothing to read'), 'This file has no readable text');
      expect(ragDocErrorText('no_text: x'), 'This file has no readable text');
      expect(ragDocErrorText('bad_pdf'), 'bad_pdf');
      AppConfig.lang = 'ar';
      expect(ragDocErrorText('no_readable_text:'), 'هذا الملف لا يحتوي على نص مقروء');
    });
  });

  group('scope options per role', () {
    test('super admin: app and global', () {
      final r = ragUploaderRole(manager: true, app: true);
      expect(ragScopeOptions(r), ['app', 'global']);
    });
    test('org admin: org, staff, course; never app / global', () {
      final o = ragScopeOptions(ragUploaderRole(manager: true, orgId: 4));
      expect(o, ['org', 'staff', 'course']);
      expect(o, isNot(contains('app')));
      expect(o, isNot(contains('global')));
    });
    test('teacher in a course: that course only', () {
      expect(ragScopeOptions(ragUploaderRole(manager: true, orgId: 4, courseId: 9)), ['course']);
      expect(ragScopeOptions(ragUploaderRole(manager: true, courseId: 9)), ['course']);
    });
    test('a student or any non-manager gets nothing, even in the app library', () {
      expect(ragScopeOptions(ragUploaderRole(manager: false, orgId: 4)), isEmpty);
      expect(ragScopeOptions(ragUploaderRole(manager: false, app: true)), isEmpty);
      expect(ragScopeOptions(ragUploaderRole(manager: false, courseId: 9)), isEmpty);
    });
    test('the roles field: org scope only, known roles in order', () {
      expect(ragRolesField('org', {'teacher', 'student'}), 'student,teacher');
      expect(ragRolesField('org', {}), isNull);
      expect(ragRolesField('staff', {'teacher'}), isNull);
    });
  });

  group('draft fields', () {
    final bytes = Uint8List(10);
    test('global and app send no org; org sends roles', () {
      final g = RagUploadDraft(scope: 'global', fileName: 'a.pdf', fileBytes: bytes);
      expect(g.validate(), isNull);
      expect(g.fields(orgId: 4).containsKey('org_id'), isFalse);
      final a = RagUploadDraft(scope: 'app', fileName: 'a.pdf', fileBytes: bytes);
      expect(a.fields(orgId: 4)['scope'], 'app');
      final o = RagUploadDraft(scope: 'org', roles: {'teacher', 'staff'}, fileName: 'a.pdf', fileBytes: bytes);
      expect(o.validate(orgId: 4), isNull);
      final f = o.fields(orgId: 4);
      expect(f['org_id'], 4);
      expect(f['roles'], 'teacher,staff');
      expect(RagUploadDraft(scope: 'org', fileName: 'a.pdf', fileBytes: bytes).fields(orgId: 4).containsKey('roles'), isFalse);
    });
    test('roles on another scope are refused before the request', () {
      expect(RagUploadDraft(scope: 'staff', roles: {'teacher'}, fileName: 'a.pdf', fileBytes: bytes).validate(orgId: 4), 'roles_only_org');
    });
    test('a course scope needs a course', () {
      expect(RagUploadDraft(scope: 'course', fileName: 'a.pdf', fileBytes: bytes).validate(orgId: 4), 'course_required');
      expect(RagUploadDraft(scope: 'course', courseId: '9', fileName: 'a.pdf', fileBytes: bytes).validate(orgId: 4), isNull);
    });
  });

  group('upload errors', () {
    test('too_large carries the limit', () {
      final r = EngineResult.fail(413, 'too_large', 'x', {'limit_mb': 50});
      expect(ragResultText(r), 'The file is larger than the allowed 50 MB');
      AppConfig.lang = 'ar';
      expect(ragResultText(r), contains('50'));
    });
    test('too_large without a limit, and the other codes', () {
      expect(ragResultText(EngineResult.fail(413, 'too_large', 'x')), 'The file is larger than the allowed size');
      expect(ragLibraryCodeText('images_not_accepted', ''), contains('Photos are not accepted'));
      expect(ragLibraryCodeText('bad_roles', ''), 'The roles list is not valid');
      expect(ragLibraryCodeText('roles_only_org', ''), contains('whole-organization'));
      expect(ragLibraryCodeText('bad_scope', ''), 'Invalid scope');
      expect(ragLibraryCodeText('no_readable_text', ''), 'This file has no readable text');
      expect(ragLibraryCodeText('file_too_large', ''), isNotEmpty);
    });
  });

  group('upload hint', () {
    test('scanned reading off: a fully scanned PDF is refused', () {
      final h = ragUploadHint(ocrScanned: false, maxMb: 30);
      expect(h, contains('Images inside files are ignored'));
      expect(h, contains('fully scanned PDF is refused'));
      expect(h, contains('30 MB'));
    });
    test('scanned reading on: read automatically', () {
      expect(ragUploadHint(ocrScanned: true), contains('read automatically and may lose words'));
      expect(ragUploadHint(ocrScanned: true), isNot(contains('Maximum')));
    });
  });
}
