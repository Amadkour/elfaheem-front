// My certificates (editorial theme): the gold "earned" block and the certificate cards in every state, plus the
// loading, failed and empty pages, at 320x640 and 1400x900, Arabic + English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/certificates/student/my_certificate_model.dart';
import 'package:flutter_education_app/features/certificates/student/my_certificates_provider.dart';
import 'package:flutter_education_app/features/certificates/student/my_certificates_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'layout_harness.dart';

const longAr = 'شهادة إتمام برنامج إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Certificate of completion, Office of Student Affairs, Graduate Studies and Scientific Research';

MyCertificate cert(int id, String state, {double progress = 40, String? reason}) => MyCertificate.fromJson({
      'certificate_id': id,
      'course_id': id,
      'course_name_ar': longAr,
      'course_name_en': longEn,
      'title': '$longAr $longEn',
      'teacher_name': longEn,
      'progress': progress,
      'state': state,
      'can_request': state == 'available',
      'rejection_reason': reason,
    });

Widget view(MyCertificatesProvider p) =>
    ChangeNotifierProvider<MyCertificatesProvider>.value(value: p, child: const MyCertificatesView(embedded: true));

void main() {
  testWidgets('every certificate state on one page', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => view(MyCertificatesProvider()
        ..items = [
          cert(1, 'available', progress: 99.5),
          cert(2, 'pending', progress: 100),
          cert(3, 'ready_soon'),
          cert(4, 'rejected', reason: '$longAr $longEn'),
        ]),
    );
  });

  testWidgets('loading, failed, empty', (tester) async {
    await expectNoLayoutErrors(tester, () => view(MyCertificatesProvider()..loading = true));
    await expectNoLayoutErrors(tester, () => view(MyCertificatesProvider()..loadFailed = true));
    await expectNoLayoutErrors(tester, () => view(MyCertificatesProvider()));
  });
}
