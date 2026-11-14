// The certificate font path, app side (D-380..D-382): the fonts picker lists the renderer's catalog; every catalog font
// draws on the canvas from the same file the server renders with; a picked font reaches the document, survives
// JSON (draft / save / reload) and draws on the canvas in that face (bold / italic included). Fails on the original
// bug: the properties panel had no font control at all, so a text element kept the page font.
//
// The catalog fixture comes from ../back/scripts/contract/dump_cert_fonts.py.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/export_fonts.dart';
import 'package:flutter_education_app/design/export_layout/layout_element_view.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/export_layout/layout_props.dart';
import 'package:flutter_education_app/design/export_layout/layout_canvas.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/certificates/studio/cert_engine_api.dart';
import 'package:flutter_education_app/features/certificates/studio/cert_font_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

final _catalog = jsonDecode(File('test/fixtures/cert_fonts/catalog.json').readAsStringSync()) as Map<String, dynamic>;
List<CertFontInfo> get _fonts => [for (final j in _catalog['items'] as List) CertFontInfo.tryParse(j)!];

String _sha(String asset) => sha1.convert(File(asset).readAsBytesSync()).toString();

CertFontInfo _font(String id) => _fonts.firstWhere((f) => f.id == id);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('the catalog on the canvas', () {
    test('every font the app ships draws from the same file as the renderer', () {
      final files = (_catalog['files'] as Map).cast<String, Map>();
      expect(_fonts.where((f) => f.bundled), isNotEmpty);
      for (final f in _fonts.where((f) => f.bundled)) {
        expect(ExportFonts.has(f.id), isTrue, reason: '${f.id} is not an app font: the canvas would draw another face');
        final x = ExportFonts.byId(f.id);
        expect(_sha(x.regularAsset), files[f.id]!['regular'], reason: '${f.id}: canvas and renderer use different files');
        if (files[f.id]!['bold'] != null) expect(_sha(x.boldAsset), files[f.id]!['bold'], reason: '${f.id} bold');
        if (files[f.id]!['italic'] != null) expect(_sha(ExportFonts.byId('${f.id}_italic').regularAsset), files[f.id]!['italic'], reason: '${f.id} italic');
        expect(x.arabic, f.arabic, reason: '${f.id}: the canvas and the renderer disagree about Arabic');
      }
    });

    test('a font this build lacks is announced at once and its file only fetched when drawn', () async {
      expect(ExportFonts.has('xserver_only'), isFalse);
      final asked = <String>[];
      ExportFonts.remoteFetch = (id, variant) async {
        asked.add('$id:$variant');
        return File('assets/fonts/cert/Amiri-Regular.ttf').readAsBytesSync();
      };
      ExportFonts.declareRemote(id: 'xserver_only', family: 'Server Only', arabic: true, bold: true, italic: true);
      expect(asked, isEmpty, reason: 'declaring downloads nothing');
      expect(ExportFonts.has('xserver_only'), isTrue);
      expect(ExportFonts.has('xserver_only_italic'), isTrue);
      expect(ExportFonts.byId('xserver_only').previewFamily, 'xf_xserver_only');
      expect(await ExportFonts.bytes(ExportFonts.byId('xserver_only').regularAsset), isNotEmpty);
      expect(asked, ['xserver_only:regular']);
      ExportFonts.remoteFetch = null;
    });

    test('a font the catalog names but the app does not ship stays a server font, not a Tajawal copy', () {
      for (final f in _fonts.where((f) => !f.bundled)) {
        expect(f.style, isNotEmpty, reason: '${f.id}: the picker groups by style');
        expect(ExportFonts.has(f.id), isFalse, reason: '${f.id} needs no copy in the app build');
      }
      expect(_fonts.where((f) => !f.bundled && f.arabic).length, greaterThanOrEqualTo(12));
      expect(_fonts.where((f) => !f.bundled && !f.arabic).length, greaterThanOrEqualTo(12));
    });
  });

  group('picked font: model, draft, canvas', () {
    LayoutElement el(String font) => LayoutElement(id: 'a', kind: 'text', w: 100, h: 12, value: 'Certificate of Award', style: LayoutStyle(font: font, size: 18, weight: 700, italic: true));

    test('font, bold and italic survive the document JSON (draft, save, reload)', () {
      final e = el('scheherazade');
      final again = LayoutElement.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(again.style.font, 'scheherazade');
      expect(again.style.weight, 700);
      expect(again.style.italic, isTrue);
    });

    test('the canvas uses the chosen family and the italic file the renderer uses', () {
      expect(layoutTextStyle(el('playfair')..style.weight = 400, 'tajawal', 3, const Color(0xFF000000)).fontFamily, 'xf_playfair_italic');
      // bold + italic: the renderer draws the bold file slanted (no bold italic file)
      expect(layoutTextStyle(el('playfair'), 'tajawal', 3, const Color(0xFF000000)).fontFamily, 'xf_playfair');
      expect(layoutTextStyle(el('amiri')..style.font = null, 'cairo', 3, const Color(0xFF000000)).fontFamily, 'xf_cairo');
      expect(layoutTextStyle(el('noto_kufi'), 'tajawal', 3, const Color(0xFF000000)).fontFamily, 'xf_noto_kufi');
    });
  });

  group('the control', () {
    StudioController<LayoutElement> ctlOf(List<LayoutElement> els) => StudioController<LayoutElement>(adapter: LayoutElementsAdapter(els, newId: () => 'x'), page: const StudioPage(200, 100, unitPx: kMmPx));

    Widget control(StudioController<LayoutElement> ctl, List<LayoutElement> targets, {String lang = 'en'}) => CertFontControl(
          ctl: ctl,
          targets: targets,
          sampleOf: (e) => e.value ?? '',
          lang: lang,
          api: CertEngineApi(),
          loader: () async => _fonts,
        );

    LayoutElement text(String id, String value, {String? font}) => LayoutElement(id: id, kind: 'text', w: 100, h: 12, value: value, style: LayoutStyle(font: font, size: 18));

    Future<Finder> row(WidgetTester tester, String id) async {
      final f = find.byKey(ValueKey('cert-font-$id'));
      await tester.scrollUntilVisible(f, 200, scrollable: find.descendant(of: find.byKey(const ValueKey('cert-font-list')), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      return f;
    }

    Future<void> openPicker(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('cert-font-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cert-font-open')));
      await tester.pumpAndSettle();
    }

    testWidgets('the panel offers a font control for a text field, and the pick lands in the document', (tester) async {
      final e = text('a', 'Certificate of Award');
      final ctl = ctlOf([e]);
      await tester.pumpWidget(layoutHost(SizedBox(
        width: 400,
        child: LayoutElementProps(ctl: ctl, element: e, fields: const [], upload: (_, _) async => null, fontControl: (ctx, c, t, s) => control(c, t), sampleOf: (e) => e.value ?? ''),
      ), scale: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cert-font-open')), findsOneWidget, reason: 'the original bug: there was no font control');
      await openPicker(tester);
      await tester.tap(await row(tester, 'eb_garamond'));
      await tester.pumpAndSettle();
      expect(e.style.font, 'eb_garamond');
      expect(e.toJson()['style']['font'], 'eb_garamond');
      ctl.undo();
      expect(ctl.items.single.payload.style.font, isNull, reason: 'one undo step (the elements are restored as copies)');
    });

    testWidgets('italic and bold apply to every selected field', (tester) async {
      final a = text('a', 'One'), b = text('b', 'Two');
      final ctl = ctlOf([a, b]);
      await tester.pumpWidget(layoutHost(SizedBox(width: 400, child: control(ctl, [a, b])), scale: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cert-font-italic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cert-font-bold')));
      await tester.pumpAndSettle();
      expect((a.style.italic, b.style.italic, a.style.weight, b.style.weight), (true, true, 700, 700));
    });

    testWidgets('several selected fields, and apply to all fields', (tester) async {
      final a = text('a', 'One'), b = text('b', 'Two'), z = text('z', 'Three');
      final shape = LayoutElement(id: 'r', kind: 'rect', w: 10, h: 10);
      final ctl = ctlOf([a, b, z, shape]);
      await tester.pumpWidget(layoutHost(SizedBox(width: 400, child: control(ctl, [a, b])), scale: 1));
      await tester.pumpAndSettle();
      await openPicker(tester);
      await tester.tap(await row(tester, 'cinzel'));
      await tester.pumpAndSettle();
      expect((a.style.font, b.style.font, z.style.font), ('cinzel', 'cinzel', null));

      await openPicker(tester);
      await tester.tap(find.text('All fields (3)'));
      await tester.pumpAndSettle();
      await tester.tap(await row(tester, 'baskerville'));
      await tester.pumpAndSettle();
      expect((a.style.font, b.style.font, z.style.font), ('baskerville', 'baskerville', 'baskerville'));
      expect(shape.style.font, isNull, reason: 'a shape has no text');
    });

    testWidgets('groups, search, the field\'s real text, and a Latin font says so on an Arabic field', (tester) async {
      AppConfig.lang = 'ar';
      final e = text('a', 'شهادة تقدير');
      await tester.pumpWidget(layoutHost(SizedBox(width: 400, child: control(ctlOf([e]), [e], lang: 'ar')), scale: 1));
      await tester.pumpAndSettle();
      await openPicker(tester);
      expect(find.text('عربي'), findsOneWidget, reason: 'the Arabic tab opens for an Arabic field');
      expect(find.byKey(const ValueKey('cert-font-style-naskh')), findsOneWidget);
      await row(tester, 'amiri');
      expect(find.byKey(const ValueKey('cert-font-note-amiri')), findsNothing);
      await tester.tap(find.text('إنجليزي'));
      await tester.pumpAndSettle();
      await row(tester, 'cinzel');
      expect(find.byKey(const ValueKey('cert-font-note-cinzel')), findsOneWidget, reason: 'Cinzel has no Arabic letters: said before it is chosen');
      await tester.tap(find.text('عربي'));
      await tester.pumpAndSettle();
      expect(find.text('شهادة تقدير'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('cert-font-search')), 'kufi');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cert-font-noto_kufi')), findsOneWidget);
      expect(find.byKey(const ValueKey('cert-font-amiri')), findsNothing);
    });
  });

  testWidgets('catalog parsing keeps what the server says', (tester) async {
    expect(_font('amiri').arabic, isTrue);
    expect(_font('cinzel').arabic, isFalse);
    expect(_font('cinzel').arabicFallback, 'amiri');
    expect(_font('playfair').italic, isTrue);
  });

  testWidgets('the rows load only the fonts on screen, a few at a time, regular file only', (tester) async {
    final asked = <String>[];
    ExportFonts.remoteFetch = (id, variant) async {
      asked.add('$id:$variant');
      return File('assets/fonts/cert/Amiri-Regular.ttf').readAsBytesSync();
    };
    final many = [for (var i = 0; i < 40; i++) CertFontInfo(id: 'lazyf$i', family: 'Lazy $i', scripts: const ['arabic', 'latin'], bold: true, style: 'sans', bundled: false)];
    for (final f in many) {
      ExportFonts.declareRemote(id: f.id, family: f.family, arabic: true, bold: true);
    }
    await tester.pumpWidget(layoutHost(SizedBox(width: 400, height: 500, child: CertFontPickerBody(fonts: many, value: null, sample: 'شهادة تقدير', lang: 'ar', selected: 1, total: 1, onPick: (_) {})), scale: 1));
    await tester.pump();
    expect(asked.length, lessThanOrEqualTo(3), reason: 'at most three at a time');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(asked.length, lessThan(15), reason: 'rows off the screen stay unloaded, got ${asked.length}');
    expect(asked.every((a) => a.endsWith(':regular')), isTrue, reason: 'a row does not fetch the bold');
    await tester.pumpWidget(const SizedBox());
    ExportFonts.remoteFetch = null;
  });

  testWidgets('the picker lays out on every screen', (tester) async {
    await expectNoLayoutErrors(tester, () => SizedBox(
          height: 600,
          child: CertFontPickerBody(fonts: _fonts, value: 'amiri', sample: 'شهادة تقدير للطالب المتميز', lang: AppConfig.lang, selected: 2, total: 5, onPick: (_) {}),
        ));
  });

  group('the catalog is the only list', () {
    test('the app bundles the catalog and nothing else is offered', () {
      final ids = {for (final f in _fonts) f.id};
      // the legacy per-weight keys and the families the renderer cannot join never appear
      for (final gone in const ['playfair_bold', 'cormorant_italic', 'aref_ruqaa', 'reem_kufi']) {
        expect(ids, isNot(contains(gone)));
      }
      expect(ids.containsAll(const ['scheherazade', 'noto_kufi', 'plex', 'amiri', 'playfair']), isTrue);
    });
  });
}
