// The certificate studio on the design engine at 320 x 640 and 1400 x 900, Arabic and English, text x 1.3
// (layout_harness): the studio with one language and with both, and the dialogs and sheets it opens.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_studio.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_panels.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_api.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Map<String, dynamic> _design(bool rtl) => {
      'mode': 'page',
      'page': {'size': 'A4', 'orientation': 'landscape', 'margins': {'top': 0, 'right': 0, 'bottom': 0, 'left': 0}, 'rtl': rtl, 'font': 'tajawal', 'font_size': 14},
      'row': {
        'height': 210,
        'elements': [
          {'id': 'a', 'kind': 'field', 'x': 40, 'y': 60, 'w': 200, 'h': 20, 'bind': {'field': 'student_name'}, 'style': {'size': 30, 'align': 'center'}},
          {'id': 'b', 'kind': 'text', 'x': 40, 'y': 20, 'w': 200, 'h': 14, 'value': rtl ? 'شهادة تقدير' : 'Certificate of Achievement', 'style': {'size': 24, 'align': 'center'}},
          {'id': 'c', 'kind': 'qr', 'x': 250, 'y': 170, 'w': 26, 'h': 26, 'value': '{{verify_url}}'},
        ],
      },
    };

void main() {
  late FakeApi fake;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    fake = FakeApi({
      'GET /api/v1/certificate-designs/7/document': (_) => {
            'document': {
              'schema_version': 4,
              'format': 'pdf',
              'purpose': 'certificate',
              'languages': ['ar', 'en'],
              'designs': {'ar': _design(true), 'en': _design(false)},
            },
            'version': 3,
            'converted': true,
          },
      'GET /api/v1/exports/layout/fonts': (_) => <Object>[],
    }, latency: Duration.zero);
    fake.install();
  });
  tearDown(() => fake.uninstall());

  Widget studio() => CertEngineStudio(designId: 7, drafts: CertEngineMemoryDrafts(), userId: 'u1', imageLoader: (_) async => null);

  testWidgets('the studio, both languages, converted banner', (tester) async {
    await expectNoLayoutErrors(tester, studio, scaffold: false, frames: 12);
  });

  testWidgets('the menu, the page sheet and the languages sheet', (tester) async {
    await expectNoLayoutErrors(tester, studio, scaffold: false, frames: 12, act: (t) async {
      await t.tap(find.byKey(const ValueKey('cert-menu')));
      await t.pump(const Duration(milliseconds: 400));
    });
  });

  testWidgets('the sheets and dialogs', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton(onPressed: () => showCertPageSheet(context, design: LayoutDocument.fromJson({'designs': {'ar': _design(true)}}).designs['ar']!, onChanged: () {}, pickBackground: () async => null), child: const Text('page')),
            ElevatedButton(onPressed: () => showCertPageSheet(context, design: LayoutDocument.fromJson({'designs': {'ar': _design(true)}}).designs['ar']!, onChanged: () {}, pickBackground: () async => null, generateBackground: (_, _, _) async => null), child: const Text('generate')),
            ElevatedButton(onPressed: () => showCertGallery(context, starters: const [], templates: [for (var i = 0; i < 3; i++) CertServerTemplate(key: 'k$i', nameAr: 'تصميم ذهبي طويل الاسم جدًا $i', nameEn: 'A very long ready-made design name $i', orientation: i == 1 ? 'portrait' : 'landscape')], lang: 'en'), child: const Text('gallery')),
            ElevatedButton(onPressed: () => showCertSignatureClean(context, fromSaved: true), child: const Text('sig')),
            ElevatedButton(onPressed: () => showCertStartChoice(context, lang: 'en', canMirror: true), child: const Text('start')),
            ElevatedButton(onPressed: () => showCertConflictDialog(context), child: const Text('conflict')),
          ]),
        ),
      ),
      act: (t) async {
        for (final k in ['page', 'generate', 'gallery', 'sig', 'start', 'conflict']) {
          await t.tap(find.text(k));
          await t.pump(const Duration(milliseconds: 500));
          await t.tapAt(const Offset(2, 2));
          await t.pump(const Duration(milliseconds: 500));
        }
      },
    );
  });
}
