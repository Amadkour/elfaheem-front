// The certificate photo step (D-386): the wire bits, matching files to people by name / number, the screens.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_api.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_photo_logic.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_photos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _people = [
  IssuePhotoPerson(key: 'r1', name: 'أحمد محمد', identifiers: ['1024']),
  IssuePhotoPerson(key: 'r2', name: 'Sara Ali', identifiers: ['2048', 'sara@x.com']),
  IssuePhotoPerson(key: 'r3', name: 'Omar', identifiers: []),
  IssuePhotoPerson(key: 'r4', name: 'Omar', identifiers: []),
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('files match by identifier, name, or a part of the file name; a shared name never matches', () {
    final m = certMatchPhotoFiles(
      ['1024.jpg', 'Sara_Ali.png', '2048_portrait.jpeg', 'Omar.jpg', 'nobody.png'],
      _people,
    );
    expect(m.byPerson, {'r1': 0, 'r2': 1});
    expect(m.duplicates, ['2048_portrait.jpeg']);
    expect(m.ambiguous, ['Omar.jpg']);
    expect(m.unmatched, ['nobody.png']);
  });

  test('an Arabic file name is compared the way names are', () {
    final m = certMatchPhotoFiles(['أحمد محمّد.jpg'], const [IssuePhotoPerson(key: 'a', name: 'احمد محمد')]);
    expect(m.byPerson, {'a': 0});
  });

  test('the server photo status and bodies', () {
    final st = IssuePhotoStatus.fromJson({
      'photo': 'required',
      'total': 3,
      'complete': false,
      'missing': [
        {'index': 2, 'name': 'X', 'student_id': null},
      ],
    });
    expect(st.photo, 'required');
    expect(st.missing.single.index, 2);
    expect(certPhotoStatusBody(designId: 1, mode: IssueMode.course, courseId: 5, certificateId: 9)['certificate_id'], 9);
    // course rows travel only when a photo was uploaded
    expect(certBatchBody(designId: 1, mode: IssueMode.course, courseId: 5).containsKey('rows'), isFalse);
    expect(certBatchBody(designId: 1, mode: IssueMode.course, courseId: 5, rows: [{'student_id': 4, 'photo_url': 'u'}]).containsKey('rows'), isTrue);
    expect(IssueTemplate.fromJson({'columns': [], 'photo': 'optional'}).photo, 'optional');
    expect(IssueTemplate.fromJson({'columns': []}).photo, 'none');
  });

  test('a draft row carries its photo to the batch and the saved list', () {
    final d = RecipientDraft(columns: const [IssueColumn(key: 'student_name', labelAr: 'x', labelEn: 'x')]);
    final r = d.addManual({'student_name': 'Non User'});
    d.setPhoto(r.uid, 'https://f/p.jpg');
    expect(d.batchRows().single['photo_url'], 'https://f/p.jpg');
    expect(d.batchUids(), [r.uid]);
    expect(d.listRows().single['photo_url'], 'https://f/p.jpg');
    final restored = RecipientDraft(columns: const [IssueColumn(key: 'student_name', labelAr: 'x', labelEn: 'x')])
      ..addListRows([d.listRows().single]);
    expect(restored.rows.single.photoUrl, 'https://f/p.jpg');
  });

  test('photos_required reads the count', () {
    expect(certIssueErrorText(Exception('x')), isA<String>());
  });

  testWidgets('the step has no overflow', (t) async {
    await expectNoLayoutErrors(t, () {
      final photos = CertPhotoCollector(api: CertIssueApi())
        ..setPeople(const [
          IssuePhotoPerson(key: 'a', name: 'اسم طويل جدا للطالب الذي لا يحمل صورة في حسابه', identifiers: ['1024']),
          IssuePhotoPerson(key: 'b', name: 'Sara'),
        ], missing: {'a', 'b'});
      return IssuePhotosBody(photos: photos);
    });
  });
}
