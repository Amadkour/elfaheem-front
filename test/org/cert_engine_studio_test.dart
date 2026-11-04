// The certificate studio on the design engine (D-165): load a converted design, edit one language without touching the
// other, the mirrored copy, save with the version, the 409 "saved elsewhere" dialog (keep mine / reload), the local
// draft prompt and the kill switch that opens the legacy designer.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show RequestOptions;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_screen.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_api.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_presets.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_studio.dart';
import 'package:flutter_education_app/design/export_layout/layout_canvas.dart' show LayoutAddOption;
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _el(String id, String text, {double x = 20}) =>
    {'id': id, 'kind': 'text', 'x': x, 'y': 30, 'w': 100, 'h': 12, 'value': text};

Map<String, dynamic> _design(bool rtl, List<Map<String, dynamic>> els) => {
      'mode': 'page',
      'page': {'size': 'A4', 'orientation': 'landscape', 'margins': {'top': 0, 'right': 0, 'bottom': 0, 'left': 0}, 'rtl': rtl, 'font': 'tajawal', 'font_size': 14},
      'row': {'height': 210, 'elements': els},
    };

Map<String, dynamic> _doc({bool both = false, List<Map<String, dynamic>>? ar, List<Map<String, dynamic>>? en}) => {
      'schema_version': 4,
      'format': 'pdf',
      'purpose': 'certificate',
      'languages': both ? ['ar', 'en'] : ['ar'],
      'designs': {
        'ar': _design(true, ar ?? [_el('a1', 'شهادة', x: 150)]),
        if (both) 'en': _design(false, en ?? <Map<String, dynamic>>[]),
      },
    };

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  late FakeApi fake;
  late CertEngineMemoryDrafts drafts;
  final puts = <Map<String, dynamic>>[];
  var putAnswers = <Object>[];
  var loadVersion = 5;
  var converted = false;
  late Map<String, dynamic> served;
  final calls = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic> body(RequestOptions o) => (o.data as Map).cast<String, dynamic>();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    drafts = CertEngineMemoryDrafts();
    puts.clear();
    calls.clear();
    putAnswers = [];
    loadVersion = 5;
    converted = false;
    served = _doc();
    fake = FakeApi({
      'GET /api/v1/certificate-designs/7/document': (_) => {'document': served, 'version': loadVersion, 'converted': converted},
      'PUT /api/v1/certificate-designs/7/document': (o) {
        puts.add((o.data as Map).cast<String, dynamic>());
        if (putAnswers.isNotEmpty) return putAnswers.removeAt(0);
        return {'document': served, 'version': (puts.last['version'] as int) + 1};
      },
      'GET /api/v1/exports/layout/fonts': (_) => <Object>[],
      'PUT /api/v1/certificate-designs/7': (o) {
        (calls['rename'] ??= []).add(body(o));
        return {'id': 7};
      },
      'POST /api/v1/certificate-designs/draft': (o) {
        (calls['draft'] ??= []).add(body(o));
        return {'background_url': 'https://x/ar.png', 'background_url_en': 'https://x/en.png'};
      },
      'POST /api/v1/certificate-designs/signature': (o) {
        (calls['signature'] ??= []).add(body(o));
        return {'url': 'https://x/sig.png', 'width': 1, 'height': 1};
      },
      'POST /api/v1/certificate-designs/preview-document': (o) {
        (calls['preview'] ??= []).add(body(o));
        return {'png_b64': _png};
      },
    }, latency: const Duration(milliseconds: 20));
    fake.install();
  });
  tearDown(() => fake.uninstall());

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(
      CertEngineStudio(designId: 7, drafts: drafts, userId: 'u1', imageLoader: (_) async => null),
      scaffold: false,
      scale: 1,
    ));
    await settle(tester);
  }

  /// Adds a text element through the canvas' "Add" menu.
  Future<void> addText(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add an element'));
    await settle(tester, 300);
    await tester.tap(find.widgetWithText(PopupMenuItem<LayoutAddOption>, 'Text').first);
    await settle(tester, 300);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('cert-save')));
    await settle(tester);
  }

  testWidgets('a converted legacy design opens with the one-line banner and nothing to save', (tester) async {
    converted = true;
    await open(tester);
    expect(find.byKey(const ValueKey('cert-converted-banner')), findsOneWidget);
    expect(find.text('Moved to the new studio — nothing changes until you save.'), findsOneWidget);
    expect(find.text('All changes saved'), findsOneWidget);
    final btn = tester.widget<IconButton>(find.byKey(const ValueKey('cert-save')));
    expect(btn.onPressed, isNull);
    expect(puts, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing English leaves the Arabic design untouched; save sends the version', (tester) async {
    served = _doc(both: true);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-tab-en')));
    await settle(tester, 300);
    await addText(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await save(tester);
    expect(puts, hasLength(1));
    expect(puts.single['version'], 5);
    final designs = (puts.single['document'] as Map)['designs'] as Map;
    expect((((designs['ar'] as Map)['row'] as Map)['elements'] as List), hasLength(1), reason: 'Arabic is as it was');
    expect((((designs['en'] as Map)['row'] as Map)['elements'] as List), hasLength(1), reason: 'English gained the new text');
    expect(((designs['ar'] as Map)['page'] as Map)['rtl'], isTrue);
    expect(((designs['en'] as Map)['page'] as Map)['rtl'], isFalse);
    expect(find.text('All changes saved'), findsOneWidget);

    // the next save builds on the version the server answered
    await addText(tester);
    await save(tester);
    expect(puts.last['version'], 6);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Start English from the Arabic design" copies the Arabic one mirrored, rtl off', (tester) async {
    served = _doc(both: true);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-tab-en')));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('cert-menu')));
    await settle(tester, 300);
    await tester.tap(find.text('Start English from the Arabic design'));
    await settle(tester);
    await save(tester);
    final en = (((puts.single['document'] as Map)['designs'] as Map)['en']) as Map;
    final els = (en['row'] as Map)['elements'] as List;
    expect(els, hasLength(1));
    // A4 landscape is 297 mm wide: x' = 297 − 150 − 100
    expect((els.single as Map)['x'], 47);
    expect((en['page'] as Map)['rtl'], isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('certMirrorDesign: x mirrored on the page width, rtl follows, rotation reversed, source untouched', () {
    final src = LayoutDocument.fromJson(_doc()).designs['ar']!;
    src.row.elements.single.rotation = 10;
    final m = certMirrorDesign(src, toRtl: false);
    expect(m.row.elements.single.x, 47);
    expect(m.row.elements.single.rotation, -10);
    expect(m.page.rtl, isFalse);
    expect(src.row.elements.single.x, 150);
    expect(src.page.rtl, isTrue);
  });

  testWidgets('409 design_conflict: the dialog offers Keep mine, which saves over the newer version', (tester) async {
    await open(tester);
    await addText(tester);
    putAnswers = [const FakeResponse(409, {'detail': {'code': 'design_conflict', 'message': 'saved elsewhere'}})];
    loadVersion = 9; // somebody else saved
    await save(tester);
    expect(find.text('This design was saved elsewhere meanwhile'), findsOneWidget);
    expect(puts, hasLength(1));
    expect(puts.single['version'], 5);

    await tester.tap(find.byKey(const ValueKey('cert-conflict-keep')));
    await settle(tester, 900);
    expect(puts, hasLength(2));
    expect(puts.last['version'], 9, reason: 'kept mine on top of the version the server holds now');
    expect(find.text('All changes saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('409 then Reload discards my edits and takes the saved copy', (tester) async {
    await open(tester);
    await addText(tester);
    putAnswers = [const FakeResponse(409, {'detail': {'code': 'design_conflict'}})];
    loadVersion = 8;
    await save(tester);
    await tester.tap(find.byKey(const ValueKey('cert-conflict-reload')));
    await settle(tester, 900);
    expect(puts, hasLength(1));
    expect(find.text('All changes saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the draft is written 2 s after the last edit and removed by a save', (tester) async {
    await open(tester);
    await addText(tester);
    await settle(tester, 1000);
    expect(drafts.data, isEmpty, reason: 'not before 2 s of quiet');
    await settle(tester, 1500);
    expect(drafts.data.keys, ['cert_engine_draft_u1_7']);
    final saved = jsonDecode(drafts.data.values.single) as Map;
    expect(saved['base_version'], 5);
    await save(tester);
    expect(drafts.data, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stored draft is offered back; Restore keeps it as unsaved edits', (tester) async {
    final edited = _doc(ar: [_el('a1', 'شهادة', x: 150), _el('a2', 'محفوظ محليًا')]);
    drafts.data['cert_engine_draft_u1_7'] = jsonEncode({'base_version': 5, 'document': edited});
    await open(tester);
    expect(find.text('Unsaved edits on this device'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cert-draft-restore')));
    await settle(tester, 300);
    expect(find.text('Unsaved changes'), findsOneWidget);
    await save(tester);
    final els = ((((puts.single['document'] as Map)['designs'] as Map)['ar'] as Map)['row'] as Map)['elements'] as List;
    expect(els, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Discard the draft removes it; Later keeps it', (tester) async {
    drafts.data['cert_engine_draft_u1_7'] = jsonEncode({'base_version': 5, 'document': _doc(ar: [_el('a2', 'x')])});
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-draft-later')));
    await settle(tester, 300);
    expect(drafts.data, isNotEmpty);
    expect(find.text('All changes saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-draft-discard')));
    await settle(tester, 300);
    expect(drafts.data, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renaming sends the name only and keeps the design clean', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-title')));
    await settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('cert-rename-field')), 'Gold diploma');
    await tester.pump(); // enterText does not pump: the Save button enables on the next frame
    await tester.tap(find.byKey(const ValueKey('cert-rename-ok')));
    await settle(tester);
    expect(calls['rename'], [
      {'name': 'Gold diploma'}
    ]);
    expect(find.text('Gold diploma'), findsOneWidget);
    expect(find.text('All changes saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the watermark text is a locked, faint, tilted element at the back of the page', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Add an element'));
    await settle(tester, 300);
    await tester.tap(find.widgetWithText(PopupMenuItem<LayoutAddOption>, 'Watermark text'));
    await settle(tester, 300);
    await save(tester);
    final els = ((((puts.single['document'] as Map)['designs'] as Map)['ar'] as Map)['row'] as Map)['elements'] as List;
    expect(els, hasLength(2));
    final w = els.first as Map;
    expect(w['locked'], isTrue);
    expect(w['opacity'], closeTo(.12, 1e-9));
    expect(w['rotation'], -30);
    expect(w['x'] + w['w'] / 2, closeTo(148.5, 1), reason: 'centred on the landscape A4');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a generated background goes into the current language only', (tester) async {
    served = _doc(both: true);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-tab-en')));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('cert-menu')));
    await settle(tester, 300);
    await tester.tap(find.text('Page and background'));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('cert-gen-modern')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('cert-gen-go')));
    await tester.tap(find.byKey(const ValueKey('cert-gen-go')));
    await settle(tester);
    expect(calls['draft']!.single['lang'], 'en');
    expect(calls['draft']!.single['style'], 'modern');
    expect(calls['draft']!.single['design_id'], 7);
    expect(calls['draft']!.single['reset_fields'], false);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester, 300);
    await save(tester);
    final designs = (puts.single['document'] as Map)['designs'] as Map;
    expect(((designs['en'] as Map)['page'] as Map)['background_image'], 'https://x/en.png');
    expect(((designs['ar'] as Map)['page'] as Map)['background_image'], isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sample values typed in the preview are sent as values', (tester) async {
    served = _doc(ar: [_el('a1', '{{honors_level}}')]);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cert-preview')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cert-sample-values')));
    await settle(tester, 400);
    await tester.enterText(find.byKey(const ValueKey('cert-sample-honors_level')), 'First class');
    await tester.tap(find.byKey(const ValueKey('cert-sample-apply')));
    await settle(tester);
    expect(calls['preview'], hasLength(2));
    expect((calls['preview']!.last['values'] as Map)['honors_level'], 'First class');
    await tester.pumpWidget(const SizedBox());
  });

  test('signature, rename and background calls have the legacy body shapes', () async {
    final api = CertEngineApi();
    expect(await api.uploadSignature(Uint8List.fromList([1, 2]), ink: '#000000', strength: .7), 'https://x/sig.png');
    final b = calls['signature']!.single;
    expect(b['ink_color'], '#000000');
    expect(b['strength'], .7);
    expect(b['image_base64'], base64Encode([1, 2]));
    expect(await api.generateBackground(7, lang: 'ar', landscape: true, style: 'classic'), 'https://x/ar.png');
    expect(calls['draft']!.single['orientation'], 'landscape');
    final wm = certAddOptions('en', const []).firstWhere((o) => o.label == 'Watermark image');
    expect(wm.toBack && wm.centered, isTrue);
  });

  test('the kill switch certificates.engine opens the legacy designer', () {
    AppConfig.disableList = [];
    expect(certificateDesignerPage(designId: 7), isA<CertEngineStudio>());
    AppConfig.disableList = ['certificates.engine'];
    expect(certificateDesignerPage(designId: 7), isA<CertificateDesignerScreen>());
    AppConfig.disableList = [];
  });

  test('the preview decodes the server png and the starters parse', () async {
    final f = FakeApi({
      'POST /api/v1/certificate-designs/preview-document': (_) => {'png_b64': 'data:image/png;base64,${base64Encode([1, 2, 3])}'},
      'GET /api/v1/exports/layout/starters': (_) => [
            {'key': 'classic', 'name_ar': 'كلاسيكي', 'name_en': 'Classic', 'description_ar': '', 'description_en': 'Gold frame', 'mode': 'page', 'document': _doc()},
            {'key': 'bad', 'name_en': 'No document'},
          ],
    }, latency: Duration.zero);
    fake.uninstall();
    f.install();
    addTearDown(f.uninstall);
    final api = CertEngineApi();
    expect((await api.preview(_doc(), 'ar', {})).toList(), [1, 2, 3]);
    final s = await api.starters();
    expect(s.single.key, 'classic');
    expect(s.single.name('en'), 'Classic');
    expect(s.single.document.designs['ar']!.row.elements, hasLength(1));
  });
}
