// Certificate issuing — the pure part (lib/features/shared/certificates_issue/cert_issue_logic.dart): the review
// state over a real-shaped check answer (test/fixtures/cert_issue/check.json, the shape of
// ../back/services/certificate_issue_service.check), row edit / remove, candidate pick, manual recipients,
// duplicates, the summary, and every request body.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _check() =>
    jsonDecode(File('test/fixtures/cert_issue/check.json').readAsStringSync()) as Map<String, dynamic>;

RecipientDraft _draft({bool manual = true}) {
  final d = RecipientDraft(manualDefault: manual);
  d.addChecked(_check());
  return d;
}

RecipientRow _row(RecipientDraft d, int line) => d.rows.firstWhere((r) => r.line == line);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('review state from a check answer', () {
    test('rows, columns, matches and the summary', () {
      final d = _draft();
      expect(d.columns.map((c) => c.key), ['student_name', 'grade', 'email']);
      expect(d.columns.last.required, isFalse);
      expect(d.rows.length, 5);
      expect(_row(d, 1).student?.id, 11);
      expect(_row(d, 2).match, MatchState.ambiguous);
      expect(_row(d, 2).candidates.map((s) => s.id), [21, 22]);
      expect(_row(d, 2).structural.single.code, 'too_few_values');

      final s = d.summary;
      expect(s.total, 5);
      expect(s.ready, 2); // Sara (matched) + Mona (unmatched → manual recipient by default)
      expect(s.attention, 3); // Omar (count + several students), Laila (empty grade, bad e-mail), "mona adel" (dup)
      expect(s.skipped, 0);
      expect(s.matched, 1);
      expect(s.ambiguous, 1);
      expect(s.unmatched, 3);
      expect(s.duplicates, 1);
      expect(s.label, '2 ready · 3 need attention');
    });

    test('problems are recomputed here: empty, bad e-mail, duplicate (normalised name)', () {
      final d = _draft();
      final laila = d.issuesOf(_row(d, 4)).map((i) => i.code).toList();
      expect(laila, ['empty_value', 'bad_email']);
      final dup = d.issuesOf(_row(d, 5)).single;
      expect(dup.code, 'duplicate');
      expect(dup.ofLine, 3);
      expect(dup.text(d.columns), 'Duplicate of line 3');
      expect(d.issuesOf(_row(d, 4)).first.text(d.columns), 'Empty value: Grade');
      // a count problem hides the per-column "empty" noise of the same line
      expect(d.issuesOf(_row(d, 2)).map((i) => i.code), ['too_few_values']);
    });

    test('a re-check of the paste replaces only its own rows', () {
      final d = _draft();
      d.addStudents(const [StudentBrief(id: 99, name: 'Searched One')]);
      expect(d.rows.length, 6);
      d.addChecked({'rows': []}, source: RowSource.paste);
      expect(d.rows.single.student?.id, 99);
    });
  });

  group('editing', () {
    test('editing clears the count problem; picking a candidate makes the row ready', () {
      final d = _draft();
      final omar = _row(d, 2);
      d.pickCandidate(omar.uid, omar.candidates[1]);
      expect(d.stateOf(d.byUid(omar.uid)!), RowState.attention); // still the count problem
      d.edit(omar.uid, 'email', 'omar@b.dev');
      final after = d.byUid(omar.uid)!;
      expect(after.structural, isEmpty);
      expect(after.student?.id, 22);
      expect(d.stateOf(after), RowState.ready);
    });

    test('fixing values makes a row ready; renaming a matched row unlinks the student', () {
      final d = _draft();
      final laila = _row(d, 4);
      d.edit(laila.uid, 'grade', 'Good');
      d.edit(laila.uid, 'email', 'laila@test.dev');
      expect(d.stateOf(d.byUid(laila.uid)!), RowState.ready);

      final sara = _row(d, 1);
      d.edit(sara.uid, 'grade', 'A+'); // other values keep the match
      expect(d.byUid(sara.uid)!.student?.id, 11);
      d.edit(sara.uid, 'student_name', 'Somebody Else');
      expect(d.byUid(sara.uid)!.student, isNull);
      expect(d.byUid(sara.uid)!.match, MatchState.unmatched);
    });

    test('renaming a row with several candidates and none picked drops them (not stuck in "needs attention")', () {
      final d = _draft();
      final omar = _row(d, 2);
      expect(omar.candidates, hasLength(2));
      d.edit(omar.uid, 'grade', 'B'); // another value keeps the candidates
      expect(d.byUid(omar.uid)!.candidates, hasLength(2));
      expect(d.stateOf(d.byUid(omar.uid)!), RowState.attention);
      d.edit(omar.uid, 'student_name', 'Omar Khaled');
      final after = d.byUid(omar.uid)!;
      expect(after.match, MatchState.unmatched);
      expect(after.candidates, isEmpty);
      expect(d.stateOf(after), RowState.ready); // a manual recipient by default
      expect(d.batchRows().any((r) => r['name'] == 'Omar Khaled'), isTrue);
      // looked up again by the new name: one student with that name → matched; a stale answer is ignored
      d.rematch(omar.uid, 'Somebody', const [StudentBrief(id: 5, name: 'Somebody')]);
      expect(d.byUid(omar.uid)!.student, isNull);
      d.rematch(omar.uid, 'Omar Khaled', const [StudentBrief(id: 41, name: 'omar  khaled'), StudentBrief(id: 42, name: 'Omar K')]);
      expect(d.byUid(omar.uid)!.student?.id, 41);
      expect(d.byUid(omar.uid)!.match, MatchState.matched);
      // two of that name → pick one
      final mona = _row(d, 3);
      d.edit(mona.uid, 'student_name', 'Nour');
      d.rematch(mona.uid, 'Nour', const [StudentBrief(id: 51, name: 'Nour'), StudentBrief(id: 52, name: 'nour')]);
      expect(d.byUid(mona.uid)!.match, MatchState.ambiguous);
      expect(d.byUid(mona.uid)!.candidates.map((s) => s.id), [51, 52]);
    });

    test('remove and remove duplicates', () {
      final d = _draft();
      expect(d.removeDuplicates(), 1);
      expect(d.rows.map((r) => r.line), [1, 2, 3, 4]);
      d.remove(_row(d, 4).uid);
      expect(d.summary.total, 3);
      expect(d.summary.duplicates, 0);
      d.clear();
      expect(d.isEmpty, isTrue);
    });
  });

  group('manual recipients', () {
    test('switched off: unmatched names are skipped; one row can still be issued', () {
      final d = _draft(manual: false);
      final mona = _row(d, 3);
      expect(d.stateOf(mona), RowState.skipped);
      expect(d.summary.ready, 1);
      expect(d.summary.skipped, 1);
      d.setManual(mona.uid, true);
      expect(d.stateOf(d.byUid(mona.uid)!), RowState.ready);
      expect(d.summary.ready, 2);
      d.manualDefault = true;
      d.setManual(mona.uid, false);
      expect(d.stateOf(d.byUid(mona.uid)!), RowState.skipped);
    });
  });

  group('searched students', () {
    test('added once, removed by untick, and a repeat of a checked row is a duplicate', () {
      final d = _draft();
      const sara = StudentBrief(id: 11, name: 'سارة علي');
      const ali = StudentBrief(id: 12, name: 'Ali');
      expect(d.addStudents([ali, ali]), 1);
      expect(d.hasStudent(12), isTrue);
      expect(d.addStudents([sara]), 0); // already in the list through the paste
      d.removeStudent(12);
      expect(d.hasStudent(12), isFalse);
      // a student matched from a pasted row shows ticked, and unticking takes that row out
      expect(d.hasStudent(11), isTrue);
      d.removeStudent(11);
      expect(d.hasStudent(11), isFalse);
      expect(d.rows.any((r) => r.line == 1), isFalse);

      final e = RecipientDraft(columns: d.columns)..addStudents([sara]);
      e.addChecked(_check(), replace: false);
      final pasted = e.rows.firstWhere((r) => r.line == 1);
      expect(e.issuesOf(pasted).map((i) => i.code), ['duplicate']);
      // a searched student needs no grade typed by hand to be listed, but the grade column is still required
      final searched = e.rows.first;
      expect(e.issuesOf(searched), isEmpty);
    });
  });

  group('request bodies', () {
    test('batch rows: only ready rows, e-mail in its own field, the student id when matched', () {
      final d = _draft();
      final rows = d.batchRows();
      expect(rows.length, 2);
      expect(rows[0], {
        'values': {'student_name': 'سارة علي', 'grade': 'ممتاز'},
        'name': 'سارة علي',
        'email': 'sara@test.dev',
        'student_id': 11,
      });
      expect(rows[1], {
        'values': {'student_name': 'Mona Adel', 'grade': 'B'},
        'name': 'Mona Adel',
      });
    });

    test('list rows keep everyone with a name, without the batch-only `name`', () {
      final d = _draft();
      final rows = d.listRows();
      expect(rows.length, 5);
      expect(rows.first.containsKey('name'), isFalse);
      expect(rows.first['student_id'], 11);
      final loaded = RecipientDraft(columns: d.columns)..addListRows(rows);
      expect(loaded.rows.first.student?.id, 11);
      expect(loaded.rows.first.email, 'sara@test.dev');
      expect(loaded.rows[2].match, MatchState.unmatched);
    });

    test('standalone and course batch bodies', () {
      final s = certBatchBody(
        designId: 7,
        mode: IssueMode.standalone,
        orgId: 3,
        courseId: 99, // ignored: a standalone batch takes no course
        langs: const ['ar', 'en'],
        email: true,
        constants: const {'hours': ' 30 ', 'grade': '  '},
        title: '  October batch ',
        rows: const [
          {'values': {'student_name': 'A'}, 'name': 'A'},
        ],
      );
      expect(s, {
        'design_id': 7,
        'mode': 'standalone',
        'org_id': 3,
        'langs': ['ar', 'en'],
        'email': true,
        'constants': {'hours': '30'},
        'title': 'October batch',
        'rows': [
          {'values': {'student_name': 'A'}, 'name': 'A'},
        ],
      });
      final c = certBatchBody(designId: 7, mode: IssueMode.course, courseId: 5, constants: const {'grade': ''});
      expect(c, {'design_id': 7, 'mode': 'course', 'course_id': 5, 'replace_existing': false, 'email': false});
    });

    test('course batch: the course certificate and "replace existing" travel (standalone never sends them)', () {
      final c = certBatchBody(designId: 7, mode: IssueMode.course, courseId: 5, certificateId: 31, replaceExisting: true);
      expect(c['certificate_id'], 31);
      expect(c['replace_existing'], isTrue);
      final s = certBatchBody(designId: 7, mode: IssueMode.standalone, certificateId: 31, replaceExisting: true);
      expect(s.containsKey('certificate_id'), isFalse);
      expect(s.containsKey('replace_existing'), isFalse);
      // which certificate: the one using this design, else the course's only one, else none
      final certs = [
        IssueCourseCertificate.fromJson(const {'id': 30, 'title': 'Old', 'design_id': 2}),
        IssueCourseCertificate.fromJson(const {'id': 31, 'title': 'New', 'design_id': 7}),
      ];
      expect(certCourseCertificateFor(certs, 7), 31);
      expect(certCourseCertificateFor(certs, 9), isNull);
      expect(certCourseCertificateFor([certs.first], 9), 30);
      expect(certCourseCertificateFor(const [], 7), isNull);
      // everyone already holds it: the message points at the switch
      const e = ApiException(statusCode: 422, message: 'x', code: 'no_recipients', body: {'detail': {'code': 'no_recipients', 'skipped': 4}});
      expect(certIssueErrorText(e), contains('Replace existing certificates'));
    });

    test('preview, check, list, person and re-issue bodies', () {
      expect(
        certPreviewBody(designId: 1, mode: IssueMode.standalone, values: const {'student_name': 'A', 'email': 'a@b.c', 'grade': ''},
            langs: const ['en']),
        {'design_id': 1, 'mode': 'standalone', 'values': {'student_name': 'A'}, 'langs': ['en']},
      );
      expect(certPreviewBody(designId: 1, mode: IssueMode.course, courseId: 4, constants: const {'hours': '30'}),
          {'design_id': 1, 'mode': 'course', 'course_id': 4, 'constants': {'hours': '30'}});
      expect(certCheckBody(designId: 2, withEmail: true, text: 'x'),
          {'design_id': 2, 'mode': 'standalone', 'with_email': true, 'text': 'x'});
      final list = certListBody(
          name: ' Oct ', designId: 2, columns: const [IssueColumn(key: 'student_name', labelAr: 'الاسم', labelEn: 'Name')], rows: const []);
      expect(list, {
        'name': 'Oct',
        'design_id': 2,
        'columns': [
          {'key': 'student_name', 'label_ar': 'الاسم', 'label_en': 'Name'},
        ],
        'rows': [],
      });
      expect(certPersonBody(values: const {'student_name': 'New One', 'email': 'n@o.dev', 'grade': ''}, issue: true, designId: 2,
          langs: const ['ar'], sendEmail: true), {
        'values': {'student_name': 'New One'},
        'name': 'New One',
        'email': 'n@o.dev',
        'issue': true,
        'design_id': 2,
        'langs': ['ar'],
        'send_email': true,
      });
      expect(certPersonBody(values: const {'student_name': 'X'}), {'values': {'student_name': 'X'}, 'name': 'X', 'issue': false});
      expect(
        certReissueBody(
          before: const {'student_name': 'Sara', 'grade': 'B'},
          after: const {'student_name': 'Sara', 'grade': 'A', 'email': 'x@y.z'},
          email: 'x@y.z',
          emailBefore: 'x@y.z',
          reason: ' typo ',
        ),
        {'values': {'grade': 'A'}, 'send_email': false, 'reason': 'typo'},
      );
    });
  });

  group('wire models and helpers', () {
    test('batch progress and labels', () {
      final b = IssueBatch.fromJson({
        'batch': {'id': 4, 'status': 'running', 'total': 10, 'done': 3, 'failed': 1, 'mode': 'standalone',
            'created_at': '2026-10-31T08:00:00', 'langs': ['ar']},
      });
      expect(b.id, 4);
      expect(b.progress, closeTo(0.4, 1e-9));
      expect(b.finished, isFalse);
      expect(b.createdAt, DateTime.utc(2026, 10, 31, 8));
      expect(certBatchStatusLabel('done'), 'Done');
      expect(IssueBatch.fromJson({'id': 1, 'status': 'done', 'total': 0}).progress, 1);
    });

    test('issued certificate, saved list and verification answer', () {
      final i = IssuedCert.fromJson({'id': 9, 'serial': 'NB-2026-ABCDEF', 'recipient_name': 'Sara', 'status': 'revoked',
          'url_ar': 'https://x/ar.png', 'url_en': null, 'values': {'grade': 'A'}});
      expect(i.revoked, isTrue);
      expect(i.imageUrl, 'https://x/ar.png');
      expect(i.values['grade'], 'A');

      final l = RecipientListInfo.fromJson({'list': {'id': 2, 'name': 'Oct', 'count': 3, 'columns': [], 'rows': []}});
      expect((l.id, l.name, l.count), (2, 'Oct', 3));

      AppConfig.lang = 'ar';
      final v = VerifyResult.fromJson({'valid': true, 'status': 'issued', 'serial': 'S', 'recipient_name': 'R',
          'langs': ['en', 'ar'], 'images': {'ar': 'a.png', 'en': 'e.png'}, 'issued_at': '2026-10-01T10:00:00'});
      expect(v.imageLangs, ['ar', 'en']);
      expect(v.issuedAt, DateTime.utc(2026, 10, 1, 10));
      expect(VerifyResult.fromJson({'valid': false, 'status': 'revoked', 'images': {'ar': null}}).imageLangs, isEmpty);
    });

    test('verify route token', () {
      expect(certVerifyTokenFromRoute('/verify/abc-DEF_123'), 'abc-DEF_123');
      expect(certVerifyTokenFromRoute('/verify/abc?x=1'), 'abc');
      expect(certVerifyTokenFromRoute('/verify'), isNull);
      expect(certVerifyTokenFromRoute('/verify/a/b'), isNull);
      expect(certVerifyTokenFromRoute('/live/abc'), isNull);
      expect(certVerifyTokenFromRoute('/verify/${'x' * 65}'), isNull);
      // the path is decoded once (by Uri): an escaped "%" must not throw
      expect(certVerifyTokenFromRoute('/verify/a%25b'), 'a%b');
      expect(certVerifyTokenFromRoute('/verify/a%2Fb'), 'a/b');
    });

    test('name normalisation matches the server rule', () {
      expect(certNormalizeName('  أحمـــد   علىّ '), certNormalizeName('احمد علي'));
      expect(certNormalizeName('فاطمة'), certNormalizeName('فاطمه'));
      expect(certNormalizeName('Mona  ADEL'), 'mona adel');
      expect(certNormalizeName('٣٠'), '30');
    });

    test('example line follows the columns', () {
      const cols = [
        IssueColumn(key: 'student_name', labelAr: 'الاسم', labelEn: 'Name'),
        IssueColumn(key: 'grade', labelAr: 'التقدير', labelEn: 'Grade'),
        IssueColumn(key: 'custom_x', labelAr: 'س', labelEn: 'Custom x'),
      ];
      expect(certExampleLine(cols), 'Mohamed Ahmed Ali, Excellent, Custom x');
    });

    test('server codes become text in both languages', () {
      const e = ApiException(
        statusCode: 422,
        message: 'الحد الأقصى',
        code: 'too_many_rows',
        body: {
          'detail': {'code': 'too_many_rows', 'message': 'الحد الأقصى', 'message_en': 'At most 5000', 'max_rows': 5000},
        },
      );
      expect(certIssueErrorText(e), 'At most 5000 recipients at a time');
      AppConfig.lang = 'ar';
      expect(certIssueErrorText(e), 'الحد الأقصى 5000 مستلم في المرة الواحدة');
      AppConfig.lang = 'en';
      const unknown = ApiException(
        statusCode: 409,
        message: 'رسالة',
        code: 'something_new',
        body: {
          'detail': {'code': 'something_new', 'message': 'رسالة', 'message_en': 'Server sentence'},
        },
      );
      expect(certIssueErrorText(unknown), 'Server sentence');
    });
  });
}
