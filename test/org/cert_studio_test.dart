// Certificate studio (agent A, docs/studio_requests/progress_A.md): the new field / page keys round trip, the
// 2.1.1 regression (edit the Arabic AND the English design, save each, reload: every format value unchanged), three
// signatures keep three images, the autosaved local draft, paper sizes, layers (lock, name, aspect lock, rotation)
// on the studio engine. The provider talks to an in-memory server that stores what it is sent, like the real one
// (tests/org_v2/cert_studio.py checks the real server side of the same contract).
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/cert_studio_adapter.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The certificate-design routes the designer uses, over one stored design (a JSON map like the server's answer).
class _CertServer implements ApiClient {
  _CertServer(this.design);

  Map<String, dynamic> design;
  final saves = <Map<String, dynamic>>[];
  int _uploads = 0;
  int _version = 0;

  Map<String, dynamic> _answer() => jsonDecode(jsonEncode(design)) as Map<String, dynamic>;

  @override
  dynamic noSuchMethod(Invocation i) {
    final path = '${i.positionalArguments.first}';
    final body = i.namedArguments[#body];
    if (i.memberName == #get && path == '/api/v1/certificate-designs/${design['id']}') {
      return Future<dynamic>.value(_answer());
    }
    if (i.memberName == #post && path.endsWith('/save')) {
      final b = Map<String, dynamic>.from(body as Map);
      saves.add(jsonDecode(jsonEncode(b)) as Map<String, dynamic>);
      // what the server stores: the sent layouts and settings (English "inherit" → null, clear flags → none)
      for (final k in ['name', 'orientation', 'theme', 'langs', 'fields', 'orientation_en', 'theme_en']) {
        if (b.containsKey(k)) design[k] = b[k];
      }
      design['fields_en'] = b['fields_en'];
      for (final k in ['background_url', 'signature_url', 'logo_url']) {
        if (b['clear_${k.replaceAll('_url', '')}'] == true) design[k] = null;
        if (b.containsKey(k)) design[k] = b[k];
      }
      for (final n in (b['inherit_en'] as List?) ?? const []) {
        design[n == 'theme' ? 'theme_en' : '${n}_url_en'] = null;
      }
      design['updated_at'] = '2026-11-01T10:00:0${++_version}';
      return Future<dynamic>.value(_answer());
    }
    if (i.memberName == #post && (path.endsWith('/signature') || path.endsWith('/logo'))) {
      return Future<dynamic>.value({'url': 'https://cdn.test/img-${++_uploads}.png', 'width': 400, 'height': 160});
    }
    return Future<dynamic>.error(StateError('unexpected ${i.memberName} $path'));
  }
}

Map<String, dynamic> _design() => {
      'id': 42,
      'name': 'Studio',
      'owner_id': 3,
      'org_id': null,
      'orientation': 'landscape',
      'background_url': null,
      'background_kind': 'none',
      'signature_url': 'https://cdn.test/default-sig.png',
      'logo_url': null,
      'theme': {'color': '#C49A47', 'dark': false, 'style': 'classic'},
      'fields': [
        {'id': 'title', 'kind': 'text', 'text': 'Certificate', 'text_ar': 'شهادة', 'x': 100, 'y': 80, 'w': 800, 'size': 40, 'font': 'amiri_bold', 'max_lines': 1},
        {'id': 'logo', 'kind': 'logo', 'x': 460, 'y': 20, 'w': 80, 'h': 80, 'src': 'https://cdn.test/l1.png'},
      ],
      'fields_en': [],
      'can_edit': true,
      'langs': ['ar', 'en'],
      'updated_at': '2026-11-01T09:00:00',
    };

/// Every format value a text can carry, non-default.
CertField _styled(CertField f, {required bool arabic}) => f.copyWith(
      font: arabic ? 'cairo' : 'playfair',
      size: arabic ? 31 : 29.5,
      color: arabic ? '#123456' : '#654321',
      letterSpacing: arabic ? 0 : 2.5,
      opacity: .85,
      align: arabic ? 'right' : 'left',
      maxLines: 2,
      shrink: false,
      weight: 'bold',
      italic: true,
      underline: true,
      lineHeight: arabic ? 1.6 : 1.3,
      direction: arabic ? 'rtl' : 'ltr',
      bgColor: '#F4EBD0',
      bgOpacity: .7,
      borderColor: '#C49A47',
      borderWidth: 2.5,
      radius: 8,
      padding: 12,
      shadowColor: '#000000',
      shadowBlur: 9,
      shadowDx: 2,
      shadowDy: 4,
      shadowOpacity: .5,
      rotation: arabic ? -8 : 12,
      name: arabic ? 'العنوان' : 'Title',
      locked: true,
    );

Map<String, dynamic> _formats(CertField f) => Map.of(f.toJson())..removeWhere((k, _) => k == 'text' || k == 'text_ar');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model', () {
    test('every studio key round trips; defaults are left out', () {
      final f = _styled(const CertField(id: 't', text: 'x'), arabic: false);
      final j = f.toJson();
      for (final k in ['weight', 'italic', 'underline', 'line_height', 'direction', 'bg_color', 'bg_opacity',
        'border_color', 'border_width', 'radius', 'padding', 'shadow_color', 'shadow_blur', 'shadow_dx', 'shadow_dy',
        'shadow_opacity', 'rotation', 'name', 'locked']) {
        expect(j.containsKey(k), isTrue, reason: k);
      }
      expect(jsonEncode(CertField.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>).toJson()), jsonEncode(j));
      final plain = const CertField(id: 'p', text: 'x').toJson();
      for (final k in ['weight', 'italic', 'rotation', 'locked', 'fit', 'padding', 'shadow_color', 'line_height']) {
        expect(plain.containsKey(k), isFalse, reason: k);
      }
      // keys of another kind are not sent (the server drops them too)
      final logo = const CertField(id: 'l', kind: CertFieldKind.logo, fit: 'cover', padding: 9).toJson();
      expect(logo['fit'], 'cover');
      expect(logo.containsKey('padding'), isFalse);
      // nullable keys clear
      expect(f.copyWith(bgColor: null, lineHeight: null, name: null).toJson().keys,
          isNot(containsAll(['bg_color', 'line_height', 'name'])));
    });

    test('paper sizes: A4 707, Letter 773, custom from mm; portrait swaps', () {
      expect(certPageLogical('landscape', null), const Size(1000, 707));
      expect(certPageLogical('landscape', {'page': {'size': 'letter'}}), const Size(1000, 773));
      expect(certPageLogical('portrait', {'page': {'size': 'letter'}}), const Size(773, 1000));
      expect(certPageLogical('landscape', {'page': {'size': 'custom', 'w_mm': 200, 'h_mm': 400}}), const Size(1000, 500));
      expect(certPageLogical('landscape', {'page': {'size': 'custom', 'w_mm': 1000, 'h_mm': 50}}).height, 300);
      expect(CertPage.of({'page': {'size': 'letter'}}).toJson(), {'size': 'letter'});
      expect(CertPage.a4.toJson(), isNull);
      final d = CertDesign.fromJson({..._design(), 'theme': {'page': {'size': 'letter'}}});
      expect(d.view('ar').logicalH, 773);
    });

    test('watermark JSON', () {
      final w = CertWatermark.of({
        'watermark': {'kind': 'text', 'text': 'أصلية', 'opacity': .2, 'rotation': -45, 'size': 80, 'position': 'tile'},
      })!;
      expect([w.kind, w.text, w.opacity, w.rotation, w.size, w.position], ['text', 'أصلية', .2, -45, 80, 'tile']);
      expect(CertWatermark.of({'watermark': w.toJson()})!.toJson(), w.toJson());
      expect(const CertWatermark(kind: 'image').size, .5);
      expect(CertWatermark.of(const {}), isNull);
    });
  });

  group('2.1.1 the Arabic AND the English design survive save + reload', () {
    test('every format value, both languages, saved one after the other', () async {
      final server = _CertServer(_design());
      final p = CertificateDesignerProvider(api: server, drafts: CertMemoryDraftStore());
      expect(await p.loadDesign(42), isTrue);

      // Arabic: every format value on the title, the paper and a watermark
      p.updateField('title', (f) => _styled(f, arabic: true));
      p.setPage('ar', const CertPage(size: 'letter'));
      p.setWatermark('ar', const CertWatermark(text: 'أصلية', opacity: .2, rotation: -30, position: 'center'));
      p.updateField('logo', (f) => f.copyWith(fit: 'cover', aspectLock: false, rotation: 5));
      expect(await p.save(), isTrue);
      final arSaved = {for (final f in p.fieldsOf('ar')) f.id: _formats(f)};
      final arTheme = Map.of(p.design!.theme);

      // English: its own formats, its own theme (custom paper + image watermark)
      p.setLang('en');
      p.updateField('title', (f) => _styled(f, arabic: false));
      p.setTheme('en', {...p.design!.theme, 'page': {'size': 'custom', 'w_mm': 250, 'h_mm': 180}});
      p.setWatermark('en', const CertWatermark(kind: 'image', src: 'https://cdn.test/wm.png', opacity: .1, size: .4));
      expect(await p.save(), isTrue);
      final enSaved = {for (final f in p.fieldsOf('en')) f.id: _formats(f)};
      final enTheme = Map.of(p.design!.themeEn!);

      // the English save did not touch the Arabic design
      expect({for (final f in p.fieldsOf('ar')) f.id: _formats(f)}, arSaved);
      expect(p.design!.theme, arTheme);

      // reload in a fresh designer: every value is what was saved
      final again = CertificateDesignerProvider(api: server, drafts: CertMemoryDraftStore());
      expect(await again.loadDesign(42), isTrue);
      expect({for (final f in again.fieldsOf('ar')) f.id: _formats(f)}, arSaved);
      expect({for (final f in again.fieldsOf('en')) f.id: _formats(f)}, enSaved);
      expect(again.design!.theme, arTheme);
      expect(again.design!.themeEn, enTheme);
      expect(again.design!.view('ar').logicalH, 773);
      expect(again.design!.view('en').logicalH, 720);
      expect(CertWatermark.of(again.design!.themeEn)!.src, 'https://cdn.test/wm.png');
      final t = again.fieldsOf('ar').firstWhere((f) => f.id == 'title');
      expect([t.font, t.size, t.color, t.weight, t.italic, t.underline, t.lineHeight, t.direction, t.bgColor,
        t.padding, t.shadowColor, t.rotation, t.name, t.locked], ['cairo', 31, '#123456', 'bold', true, true, 1.6, 'rtl',
        '#F4EBD0', 12, '#000000', -8, 'العنوان', true]);
      // and a second save of the reloaded design sends exactly the same layouts
      again.rename('Studio');
      expect(await again.save(), isTrue);
      expect(server.saves.last['fields'], server.saves[1]['fields']);
      expect(server.saves.last['fields_en'], server.saves[1]['fields_en']);
    });
  });

  group('2.1.6 each signature keeps its own image', () {
    test('three uploads into three signature boxes, saved and reloaded', () async {
      final server = _CertServer(_design());
      final p = CertificateDesignerProvider(api: server, drafts: CertMemoryDraftStore());
      await p.loadDesign(42);
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final f = await p.addSignatureImage(Uint8List.fromList([i, i, i]));
        expect(f, isNotNull);
        ids.add(f!.id);
      }
      expect(await p.save(), isTrue);
      final sent = [
        for (final f in (server.saves.last['fields'] as List).cast<Map>())
          if (f['kind'] == 'signature') f['src'],
      ];
      expect(sent.toSet().length, 3, reason: 'three different images: $sent');
      expect(sent, isNot(contains('https://cdn.test/default-sig.png')));
      // replacing one changes only that one
      await p.replaceFieldImage(ids[1], Uint8List.fromList([9]));
      final srcs = {for (final f in p.fieldsOf('ar')) if (f.kind == CertFieldKind.signature) f.id: f.src};
      expect(srcs[ids[0]], sent[0]);
      expect(srcs[ids[2]], sent[2]);
      expect(srcs[ids[1]], isNot(sent[1]));
      await p.save();
      final again = CertificateDesignerProvider(api: server, drafts: CertMemoryDraftStore());
      await again.loadDesign(42);
      expect({for (final f in again.fieldsOf('ar')) if (f.kind == CertFieldKind.signature) f.id: f.src}, srcs);
    });
  });

  group('autosave draft', () {
    test('an edit is kept on the device and offered back; saving drops it; an outdated draft is dropped', () async {
      final store = CertMemoryDraftStore();
      final server = _CertServer(_design());
      final p = CertificateDesignerProvider(api: server, drafts: store, autosaveDelay: Duration.zero);
      await p.loadDesign(42);
      p.updateField('title', (f) => f.copyWith(size: 55));
      await p.writeDraftNow();
      expect(store.data.containsKey(42), isTrue);

      final reopened = CertificateDesignerProvider(api: server, drafts: store);
      await reopened.loadDesign(42);
      expect(await reopened.restoreDraftIfAny(), isTrue);
      expect(reopened.restoredDraft, isTrue);
      expect(reopened.dirty, isTrue);
      expect(reopened.fieldsOf('ar').first.size, 55);
      await reopened.discardDraft();
      expect(reopened.fieldsOf('ar').first.size, 40);
      expect(store.data.containsKey(42), isFalse);

      p.updateField('title', (f) => f.copyWith(size: 60));
      await p.writeDraftNow();
      expect(await p.save(), isTrue);
      expect(store.data.containsKey(42), isFalse, reason: 'a save removes the draft');

      // a draft made on an older version of the design is not restored
      store.data[42] = jsonEncode({'base': '2020-01-01T00:00:00', 'lang': 'ar', 'design': _design()});
      final third = CertificateDesignerProvider(api: server, drafts: store);
      await third.loadDesign(42);
      expect(await third.restoreDraftIfAny(), isFalse);
      expect(store.data.containsKey(42), isFalse);
    });
  });

  group('studio engine', () {
    test('lock, aspect lock and rotation reach the canvas items', () {
      var slice = const CertLangSlice(fields: [
        CertField(id: 'a', kind: CertFieldKind.logo, x: 10, y: 10, w: 100, h: 50, locked: true),
        CertField(id: 'b', kind: CertFieldKind.signature, x: 300, y: 10, w: 100, h: 50, aspectLock: false),
        CertField(id: 'c', kind: CertFieldKind.text, text: 'Hi', x: 100, y: 300, w: 200, rotation: 30),
      ], orientation: 'landscape');
      final c = StudioController<CertField>(
        adapter: CertStudioAdapter(lang: 'ar', read: () => slice, write: (s) => slice = s),
        page: const StudioPage(1000, 707),
      );
      final items = {for (final i in c.items) i.id: i};
      expect(items['a']!.locked, isTrue);
      expect(items['a']!.resize, StudioResize.aspect);
      expect(items['b']!.resize, StudioResize.free);
      expect(items['c']!.rotation, 30);
      // a locked element neither moves nor deletes
      c.select('a');
      expect(c.beginMove(), isFalse);
      c.deleteSelection();
      expect(slice.fields.length, 3);
      // the free signature resizes on one axis
      c.select('b');
      expect(c.beginResize(StudioHandle.right), isTrue);
      c.updateResize(const Offset(50, 0));
      c.endGesture();
      final b = slice.fields.firstWhere((f) => f.id == 'b');
      expect([b.w, b.h], [150, 50]);
      // a turned element shows no handles but still moves
      c.select('c');
      expect(c.resizable, isNull);
      expect(c.beginMove(), isTrue);
      c.cancelGesture();
      // hit-testing a turned box: a point on its turned corner is inside, the unturned corner is not
      final r = c.itemById('c')!.rect;
      expect(r.contains(studioUnrotate(r.topLeft + const Offset(4, 4), r.center, 30)), isFalse);
    });

    test('a duplicate of a locked element is unlocked', () {
      var slice = const CertLangSlice(
          fields: [CertField(id: 'a', kind: CertFieldKind.logo, w: 100, h: 50, locked: true)], orientation: 'landscape');
      final c = StudioController<CertField>(
        adapter: CertStudioAdapter(lang: 'ar', read: () => slice, write: (s) => slice = s),
        page: const StudioPage(1000, 707),
      );
      c.select('a');
      c.duplicate();
      expect(slice.fields.length, 2);
      expect(slice.fields.last.locked, isFalse);
    });

    test('resize on a phone: touch handles, the minimum size, the aspect lock', () {
      var slice = const CertLangSlice(fields: [
        CertField(id: 's', kind: CertFieldKind.signature, x: 100, y: 100, w: 220, h: 80),
        CertField(id: 'f', kind: CertFieldKind.signature, x: 500, y: 100, w: 220, h: 80, aspectLock: false),
      ], orientation: 'landscape');
      final c = StudioController<CertField>(
        adapter: CertStudioAdapter(lang: 'ar', read: () => slice, write: (s) => slice = s),
        page: const StudioPage(1000, 707),
      );
      // a 390 px phone fits the page at ~0.34: a 220-unit box is ~75 px wide on screen
      const phone = .34;
      final locked = studioVisibleHandles(StudioResize.aspect, const Size(220 * phone, 80 * phone), touch: true);
      expect(locked.length, 4, reason: 'corners only while the ratio is kept');
      final free = studioVisibleHandles(StudioResize.free, const Size(220 * phone, 80 * phone), touch: true);
      expect(free, containsAll([StudioHandle.topLeft, StudioHandle.bottomRight, StudioHandle.top, StudioHandle.bottom]));
      expect(studioVisibleHandles(StudioResize.free, const Size(300, 200), touch: true).length, 8);
      // the kept ratio: a corner drag scales both sides
      c.select('s');
      expect(c.beginResize(StudioHandle.bottomRight), isTrue);
      c.updateResize(const Offset(110, 0));
      c.endGesture();
      final s = slice.fields.first;
      expect(s.w / s.h, closeTo(220 / 80, .01));
      // the minimum size (16 × 16 for an image) holds however far the handle goes
      c.select('f');
      expect(c.beginResize(StudioHandle.bottomRight), isTrue);
      c.updateResize(const Offset(-400, -400));
      c.endGesture();
      final f = slice.fields.last;
      expect([f.w, f.h], [16, 16]);
    });

    test('grid: snapping to it and showing it', () {
      final c = StudioController<int>(
        adapter: StudioMemoryAdapter([const StudioItem(id: 'x', rect: Rect.fromLTWH(13, 13, 40, 40), payload: 0)]),
        page: const StudioPage(1000, 707),
      );
      expect(c.showGrid, isFalse);
      c.setGrid(const Size(25, 25));
      expect(c.showGrid, isTrue);
      c.select('x');
      c.beginMove();
      c.updateMove(const Offset(100, 0));
      c.endGesture();
      expect(c.itemById('x')!.rect.left % 25, 0);
      c.showRulers = true;
      expect(c.showRulers, isTrue);
    });
  });

  group('paper size', () {
    test('Letter rescales the elements; an English design that follows the Arabic theme follows too', () async {
      final server = _CertServer(_design());
      final p = CertificateDesignerProvider(api: server, drafts: CertMemoryDraftStore());
      await p.loadDesign(42);
      final y0 = p.fieldsOf('ar').first.y;
      p.setPage('ar', const CertPage(size: 'letter'));
      expect(p.studio.page.height, 773);
      expect(p.fieldsOf('ar').first.y, closeTo(y0 * 773 / 707, .1));
      expect(p.fieldsOf('en').first.y, closeTo(y0 * 773 / 707, .1));
      expect(p.design!.view('en').logicalH, 773);
      // undo puts the A4 page back
      p.studio.undo();
      expect(p.design!.view('ar').logicalH, 707);
    });
  });
}
