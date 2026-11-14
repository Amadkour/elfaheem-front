// Certificate designer v2 (pure parts + the provider without the network): the model's JSON round trip with the
// per-language `_en` semantics (null = same as Arabic, "" = none) and all 28 fonts, the save body never touching
// the language that was not edited, the studio adapter mapping (text h = 0 with an estimated height, aspect for
// images), several logos / signatures, the languages switch, custom placeholders.
import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_studio_adapter.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_designer_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _serverDesign({
  List<Map<String, dynamic>>? fieldsEn,
  String? backgroundUrlEn,
  String? logoUrlEn,
  String? signatureUrlEn,
  Map<String, dynamic>? themeEn,
  String? orientationEn,
  List<String> langs = const ['ar', 'en'],
}) =>
    {
      'id': 7,
      'name': 'Design',
      'owner_id': 3,
      'org_id': null,
      'orientation': 'landscape',
      'background_url': 'https://cdn/bg-ar.png',
      'background_kind': 'draft',
      'signature_url': 'https://cdn/sig-ar.png',
      'logo_url': 'https://cdn/logo-ar.png',
      'theme': {'color': '#C49A47', 'dark': false, 'style': 'classic'},
      'fields': [
        {'id': 'title', 'kind': 'text', 'text': 'Certificate', 'text_ar': 'شهادة', 'x': 100, 'y': 80, 'w': 800, 'h': 0, 'size': 40, 'font': 'amiri_bold', 'max_lines': 1},
        {'id': 'logo1', 'kind': 'logo', 'x': 460, 'y': 20, 'w': 80, 'h': 80, 'src': 'https://cdn/l1.png'},
        {'id': 'sig1', 'kind': 'signature', 'x': 600, 'y': 520, 'w': 220, 'h': 80, 'size': 20, 'sig_name': 'د. سارة', 'sig_title': 'العميدة'},
        {'id': 'qr', 'kind': 'qr', 'x': 40, 'y': 560, 'w': 110, 'h': 0, 'color': '#000000'},
        {'id': 'photo', 'kind': 'photo', 'x': 60, 'y': 280, 'w': 130, 'h': 130, 'shape': 'rounded'},
      ],
      'fields_en': fieldsEn ?? [],
      'can_edit': true,
      'langs': langs,
      'orientation_en': orientationEn,
      'background_url_en': backgroundUrlEn,
      'background_kind_en': backgroundUrlEn == null ? null : (backgroundUrlEn.isEmpty ? 'none' : 'upload'),
      'theme_en': themeEn,
      'signature_url_en': signatureUrlEn,
      'logo_url_en': logoUrlEn,
      'apply_all': false,
      'course_ids': [1, 2],
      'updated_at': '2026-10-31T10:00:00',
    };

CertificateDesignerProvider _provider(CertDesign d, {String lang = 'ar'}) =>
    CertificateDesignerProvider(initialLang: lang)..adopt(d);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // the provider autosaves its draft on a short timer; on a loaded machine a test outlives it, and an unmocked
  // SharedPreferences then failed the test with MissingPluginException
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    test('JSON round trip keeps every v2 key and unknown keys', () {
      final raw = _serverDesign(
        fieldsEn: [
          {'id': 't', 'kind': 'text', 'text': 'Hello {grade}', 'future_key': 42},
        ],
        backgroundUrlEn: '',
        logoUrlEn: 'https://cdn/logo-en.png',
        themeEn: {'color': '#1E3A8A', 'dark': true},
        orientationEn: 'portrait',
        langs: ['en', 'ar'],
      );
      final d = CertDesign.fromJson(raw);
      final again = CertDesign.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.toJson()), jsonEncode(d.toJson()));
      expect(d.langs, ['ar', 'en']); // canonical order
      expect(d.extra['course_ids'], [1, 2]);
      expect(d.fieldsEn.single.extra['future_key'], 42);
      expect(d.fieldsEn.single.toJson()['future_key'], 42);
      final sig = d.fields.firstWhere((f) => f.kind == CertFieldKind.signature);
      expect(sig.sigName, 'د. سارة');
      expect(sig.toJson()['sig_title'], 'العميدة');
      expect(d.fields.firstWhere((f) => f.id == 'logo1').toJson()['src'], 'https://cdn/l1.png');
      expect(d.fields.firstWhere((f) => f.id == 'qr').kind, CertFieldKind.qr);
      expect(d.fields.firstWhere((f) => f.id == 'photo').toJson()['shape'], 'rounded');
      // src / captions only travel on the kinds that own them
      expect(d.fields.first.toJson().containsKey('src'), isFalse);
    });

    test('_en null = same as Arabic, "" = none in English, a value = its own', () {
      final d = CertDesign.fromJson(_serverDesign(backgroundUrlEn: '', logoUrlEn: 'https://cdn/logo-en.png'));
      final en = d.view('en');
      expect(en.backgroundUrl, isNull); // "" → no background in English
      expect(en.backgroundKind, 'none');
      expect(en.logoUrl, 'https://cdn/logo-en.png');
      expect(en.signatureUrl, 'https://cdn/sig-ar.png'); // null → the Arabic one
      expect(en.orientation, 'landscape');
      expect(en.theme['color'], '#C49A47');
      expect(en.fields.length, d.fields.length); // fields_en [] → the Arabic layout (server semantics)
      expect(certImageInherit(d.backgroundUrlEn, d.backgroundUrl), CertInherit.none);
      expect(certImageInherit(d.logoUrlEn, d.logoUrl), CertInherit.own);
      expect(certImageInherit(d.signatureUrlEn, d.signatureUrl), CertInherit.same);
      // "Same as Arabic" only when really null: an own copy of the same image / theme is the teacher's own
      expect(certImageInherit(d.signatureUrl, d.signatureUrl), CertInherit.own);
      expect(certThemeInherit(null, d.theme), CertInherit.same);
      expect(certThemeInherit(Map.of(d.theme), d.theme), CertInherit.own);
      // the tri-state copyWith: _keep leaves it, null clears it
      expect(d.copyWith(name: 'x').logoUrlEn, 'https://cdn/logo-en.png');
      expect(d.copyWith(logoUrlEn: null).logoUrlEn, isNull);
    });

    test('all 28 cert fonts survive a round trip', () {
      expect(kCertFonts.length, 28);
      expect(kCertFonts.map((f) => f.key).toSet().length, 28);
      for (final font in kCertFonts) {
        final f = CertField.fromJson(CertField(id: 'a', font: font.key).toJson());
        expect(f.font, font.key);
        expect(certFont(font.key).key, font.key);
      }
      expect(certFont('unknown').key, 'tajawal');
    });
  });

  group('save body', () {
    test('editing Arabic never changes the English design', () {
      final loaded = CertDesign.fromJson(_serverDesign(
        fieldsEn: [
          {'id': 'en1', 'kind': 'text', 'text': 'Certificate of completion', 'x': 50, 'y': 60, 'w': 600, 'size': 30},
        ],
        logoUrlEn: 'https://cdn/logo-en.png',
        orientationEn: 'portrait',
      ));
      final p = _provider(loaded);
      final before = p.savePayload!;
      final enJson = jsonEncode(before['fields_en']);

      // Arabic edits: move by the studio, change a property, the background, the orientation, add elements
      final st = p.studioFor('ar');
      st.select('title');
      st.beginMove();
      st.updateMove(const Offset(40, 30));
      st.endGesture();
      p.updateField('title', (f) => f.copyWith(size: 50));
      p.setBackground('ar', 'https://cdn/new-bg.png');
      p.setDefaultLogo('ar', 'https://cdn/logo-ar-2.png');
      p.addQr();
      p.setOrientation('ar', 'portrait');

      final after = p.savePayload!;
      expect(jsonEncode(after['fields_en']), enJson);
      expect(after['orientation_en'], 'portrait');
      expect(after['logo_url_en'], 'https://cdn/logo-en.png');
      expect(after.containsKey('background_url_en'), isFalse); // still follows Arabic: stays NULL on the server
      expect(after.containsKey('theme_en'), isFalse);
      expect(after['inherit_en'], ['background', 'signature', 'theme']);
      expect(after['background_url'], 'https://cdn/new-bg.png');
      expect(after['orientation'], 'portrait');
      expect((after['fields'] as List).length, loaded.fields.length + 1);
    });

    test('editing English never changes the Arabic design', () {
      final loaded = CertDesign.fromJson(_serverDesign());
      final p = _provider(loaded, lang: 'en');
      final arJson = jsonEncode(p.savePayload!['fields']);
      // fields_en was [] on the server: the English layout starts as a copy and is its own from now on
      expect((p.savePayload!['fields_en'] as List).length, loaded.fields.length);
      p.setText('title', 'Certificate of Excellence');
      p.setOrientation('en', 'portrait');
      p.setBackground('en', 'https://cdn/bg-en.png');
      p.setTheme('en', {'color': '#1E3A8A', 'dark': true});
      final after = p.savePayload!;
      expect(jsonEncode(after['fields']), arJson);
      expect(after['orientation'], 'landscape');
      expect(after['background_url'], 'https://cdn/bg-ar.png');
      expect(after['theme'], loaded.theme);
      expect(after['orientation_en'], 'portrait');
      expect(after['background_url_en'], 'https://cdn/bg-en.png');
      expect(after['theme_en'], {'color': '#1E3A8A', 'dark': true});
      final enTitle = (after['fields_en'] as List).cast<Map>().firstWhere((f) => f['id'] == 'title');
      expect(enTitle['text'], 'Certificate of Excellence');
      expect(enTitle['text_ar'], 'شهادة'); // the Arabic wording of the ENGLISH layout is not touched
    });

    test('undo in one language never touches the other', () {
      final p = _provider(CertDesign.fromJson(_serverDesign()));
      p.setLang('en');
      p.setText('title', 'Diploma');
      p.setLang('ar');
      p.setText('title', 'دبلوم');
      p.studioFor('ar').undo();
      expect(p.fieldsOf('ar').first.textAr, 'شهادة');
      expect(p.fieldsOf('en').first.text, 'Diploma');
    });

    test('Arabic text edits write text_ar; an empty box clears both', () {
      final p = _provider(CertDesign.fromJson(_serverDesign()));
      p.setText('title', 'شهادة تقدير');
      expect(p.fieldsOf('ar').first.textAr, 'شهادة تقدير');
      expect(p.fieldsOf('ar').first.text, 'Certificate');
      p.setText('title', '  ');
      expect(p.fieldsOf('ar').first.textAr, isNull);
      expect(p.fieldsOf('ar').first.text, isNull);
    });

    test('Reset to Arabic is saved as inherit_en; an empty English layout keeps a marker', () {
      final loaded = CertDesign.fromJson(_serverDesign(
        fieldsEn: [
          {'id': 'en1', 'kind': 'text', 'text': 'Hi'},
        ],
        backgroundUrlEn: 'https://cdn/bg-en.png',
        signatureUrlEn: '',
        themeEn: {'color': '#000000'},
      ));
      final p = _provider(loaded, lang: 'en');
      p.setBackground('en', null, inherit: true);
      p.setDefaultSignature('en', null, inherit: true);
      p.setTheme('en', null);
      p.removeField('en1');
      final body = p.savePayload!;
      expect(body['inherit_en'], ['background', 'logo', 'signature', 'theme']);
      for (final k in ['background_url_en', 'background_kind_en', 'signature_url_en', 'theme_en', 'clear_signature_en']) {
        expect(body.containsKey(k), isFalse, reason: k);
      }
      expect(p.themeInheritEn, CertInherit.same);
      expect(body['fields_en'], [kCertBlankField.toJson()]);
      // the marker is removed again when the design comes back
      final back = normalizeCertDesign(loaded.copyWith(fieldsEn: [kCertBlankField]));
      expect(back.fieldsEn, isEmpty);
    });

    test('None in English uses the clear flags', () {
      final p = _provider(CertDesign.fromJson(_serverDesign()), lang: 'en');
      p.setBackground('en', null);
      p.setDefaultLogo('en', null);
      final body = p.savePayload!;
      expect(body['clear_background_en'], isTrue);
      expect(body['clear_logo_en'], isTrue);
      expect(body.containsKey('background_url_en'), isFalse);
      expect(body['inherit_en'], ['signature', 'theme']);
      p.setTheme('en', Map.of(p.design!.theme)); // "Customize for English" copies the Arabic theme: now its own
      expect(p.themeInheritEn, CertInherit.own);
      expect(p.savePayload!['inherit_en'], ['signature']);
      expect(p.view.backgroundUrl, isNull);
      expect(p.view.logoUrl, isNull);
    });
  });

  group('studio adapter', () {
    CertStudioAdapter adapter(List<CertField> fields, {bool readOnly = false}) {
      var slice = CertLangSlice(fields: fields, orientation: 'landscape');
      return CertStudioAdapter(lang: 'en', read: () => slice, write: (s) => slice = s, readOnly: readOnly);
    }

    test('text keeps h = 0 and reports the renderer box height; images keep their aspect', () {
      const text = CertField(id: 't', text: 'Hello', x: 10, y: 20, w: 300, size: 30, maxLines: 1);
      const multi = CertField(id: 'm', text: 'one\ntwo', x: 10, y: 120, w: 300, size: 20, maxLines: 3);
      const line = CertField(id: 'l', kind: CertFieldKind.line, x: 0, y: 300, w: 200, h: 3);
      const logo = CertField(id: 'g', kind: CertFieldKind.logo, x: 400, y: 10, w: 80, h: 60);
      const qr = CertField(id: 'q', kind: CertFieldKind.qr, x: 40, y: 500, w: 110);
      const photo = CertField(id: 'p', kind: CertFieldKind.photo, x: 40, y: 200, w: 120, h: 120);
      final a = adapter([text, multi, line, logo, qr, photo]);
      final items = {for (final i in a.readItems()) i.id: i};
      // the renderer's rule: Tajawal's ascent + descent (1.0 × the font px) × 1.12 per line, px = size × 1.6
      expect(items['t']!.rect.height, closeTo(48 * 1.12 / 1.6, .01));
      expect(items['m']!.rect.height, closeTo(2 * 32 * 1.12 / 1.6, .01));
      expect(items['t']!.resize, StudioResize.horizontal);
      expect(items['l']!.resize, StudioResize.horizontal);
      expect(items['l']!.rect.height, 3);
      expect(items['g']!.resize, StudioResize.aspect);
      expect(items['q']!.resize, StudioResize.aspect);
      expect(items['p']!.resize, StudioResize.aspect);
      expect(items['q']!.rect, const Rect.fromLTWH(40, 500, 110, 110));

      a.writeRects({
        't': const Rect.fromLTWH(15, 25, 320, 99),
        'l': const Rect.fromLTWH(5, 310, 250, 8),
        'g': const Rect.fromLTWH(390, 5, 120, 90),
        'q': const Rect.fromLTWH(30, 480, 140, 140),
      });
      final out = {for (final f in a.read().fields) f.id: f};
      expect(out['t']!.h, 0);
      expect((out['t']!.x, out['t']!.y, out['t']!.w), (15.0, 25.0, 320.0));
      expect(out['l']!.h, 3); // the thickness stays
      expect(out['l']!.w, 250);
      expect((out['g']!.w, out['g']!.h), (120.0, 90.0));
      expect(out['q']!.w, 140);
    });

    test('a controller over the adapter resizes text horizontally only and undoes', () {
      final a = adapter([const CertField(id: 't', text: 'Hello', x: 100, y: 100, w: 300, size: 30, maxLines: 1)]);
      final c = StudioController<CertField>(adapter: a, page: const StudioPage(1000, 707));
      c.select('t');
      expect(c.beginResize(StudioHandle.right), isTrue);
      c.updateResize(const Offset(50, 80));
      c.endGesture();
      final f = a.read().fields.single;
      expect(f.w, closeTo(350, .5));
      expect(f.h, 0);
      c.undo();
      expect(a.read().fields.single.w, 300);
      c.dispose();
    });

    test('a read-only design locks items and ignores writes', () {
      final a = adapter([const CertField(id: 't', text: 'x')], readOnly: true);
      expect(a.readItems().single.locked, isTrue);
      a.removeItems({'t'});
      expect(a.read().fields, hasLength(1));
    });

    test('clone gives a new id and keeps every property', () {
      final a = adapter([const CertField(id: 's', kind: CertFieldKind.signature, src: 'u', sigName: 'A', sigTitle: 'B', w: 200, h: 80)]);
      final item = a.readItems().single;
      final copy = a.cloneItem(item);
      expect(copy.id, isNot('s'));
      expect(copy.payload.id, copy.id);
      expect((copy.payload.src, copy.payload.sigName, copy.payload.sigTitle), ('u', 'A', 'B'));
    });
  });

  group('elements', () {
    test('several logos and signatures: add, order, remove', () {
      final p = _provider(CertDesign.fromJson({..._serverDesign(), 'fields': <dynamic>[]}));
      final l1 = p.addLogo(src: 'https://cdn/a.png')!;
      final l2 = p.addLogo(src: 'https://cdn/b.png')!;
      final s1 = p.addSignature(src: 'https://cdn/s1.png', name: 'Dr. A', title: 'Dean')!;
      final s2 = p.addSignature(src: 'https://cdn/s2.png', name: 'Dr. B', title: 'Head')!;
      final ids = p.fieldsOf('ar').map((f) => f.id).toList();
      expect(ids, [l1.id, l2.id, s1.id, s2.id]);
      expect(ids.toSet().length, 4);
      final json = (p.savePayload!['fields'] as List).cast<Map>();
      expect(json.map((f) => f['src']), ['https://cdn/a.png', 'https://cdn/b.png', 'https://cdn/s1.png', 'https://cdn/s2.png']);
      expect(json[2]['sig_name'], 'Dr. A');
      expect(json[3]['sig_title'], 'Head');

      final st = p.studio;
      st.select(l1.id);
      st.bringToFront();
      expect(p.fieldsOf('ar').last.id, l1.id);
      st.select(s2.id);
      st.sendToBack();
      expect(p.fieldsOf('ar').first.id, s2.id);
      p.reorderLayer(0, 3);
      expect(p.fieldsOf('ar')[3].id, s2.id);

      p.removeField(l2.id);
      st.select(s1.id);
      st.deleteSelection();
      expect(p.fieldsOf('ar').map((f) => f.id), unorderedEquals([l1.id, s2.id]));
      // the English layout is untouched by all of it
      expect(p.fieldsOf('en'), isEmpty);
    });

    test('a logo box can go back to the default logo', () {
      final p = _provider(CertDesign.fromJson(_serverDesign()));
      p.useDefaultImage('logo1');
      expect(p.fieldsOf('ar').firstWhere((f) => f.id == 'logo1').src, isNull);
      expect((p.savePayload!['fields'] as List).cast<Map>().firstWhere((f) => f['id'] == 'logo1').containsKey('src'),
          isFalse);
    });

    test('rescale keeps relative places and a QR square', () {
      final out = rescaleCertFields([
        const CertField(id: 'q', kind: CertFieldKind.qr, x: 100, y: 707, w: 100),
        const CertField(id: 'g', kind: CertFieldKind.logo, x: 500, y: 0, w: 100, h: 50),
      ], 'landscape', 'portrait');
      expect(out[0].x, closeTo(70.7, .05));
      expect(out[0].y, closeTo(1000, .05));
      expect(out[0].w, closeTo(70.7, .05));
      expect(out[1].h, closeTo(35.4, .05));
    });
  });

  group('languages', () {
    test('turning a language off switches away from it and is saved', () {
      final p = _provider(CertDesign.fromJson(_serverDesign()), lang: 'en');
      expect(p.langHasContent('en'), isTrue); // its own layout copy
      p.setLangs(['ar']);
      expect(p.lang, 'ar');
      expect(p.savePayload!['langs'], ['ar']);
      p.setLang('en'); // not enabled → ignored
      expect(p.lang, 'ar');
      p.setLangs([]); // never empty
      expect(p.design!.langs, ['ar']);
      p.setLangs(['en', 'ar']);
      expect(p.design!.langs, ['ar', 'en']);
    });

    test('a design that issues English only opens on English', () {
      final p = _provider(CertDesign.fromJson(_serverDesign(langs: ['en'])));
      expect(p.lang, 'en');
    });
  });

  group('custom placeholders', () {
    test('key validation', () {
      expect(certPlaceholderKeyError('grade'), isNull);
      expect(certPlaceholderKeyError(' {grade_2} '), isNull);
      expect(certPlaceholderKeyError(''), 'empty');
      expect(certPlaceholderKeyError('{}'), 'empty');
      expect(certPlaceholderKeyError('Grade'), 'invalid');
      expect(certPlaceholderKeyError('final-grade'), 'invalid');
      expect(certPlaceholderKeyError('درجة'), 'invalid');
      expect(certPlaceholderKeyError('a' * 41), 'invalid');
      expect(certPlaceholderKeyError('a' * 40), isNull);
      expect(normalizePlaceholderKey('{grade}'), 'grade');
    });

    test('custom keys in a layout, preview variables, canvas samples', () {
      const fields = [
        CertField(id: 'a', text: '{student_name} — {grade}', textAr: '{grade} / {rank}'),
        CertField(id: 's', kind: CertFieldKind.signature, sigName: '{dean}'),
        CertField(id: 'q', kind: CertFieldKind.qr),
      ];
      expect(customPlaceholdersOf(fields), ['grade', 'rank', 'dean']);
      expect(certPreviewVariables(fields, {'grade': 'A+', 'rank': ' ', 'other': 'x'}), {'grade': 'A+'});
      expect(resolveSample('{student_name}: {grade} {rank}', arabic: false, custom: {'grade': 'A+'}),
          'Mohamed Ahmed Ali: A+ {rank}');
      final p = _provider(CertDesign.fromJson(_serverDesign()));
      final f = p.addPlaceholder('{grade}')!;
      expect(f.text, '{grade}');
      expect(f.textAr, '{grade}');
      p.setCustomSample('grade', 'Excellent');
      expect(p.customSamples['grade'], 'Excellent');
      p.setCustomSample('grade', '');
      expect(p.customSamples.containsKey('grade'), isFalse);
    });
  });
}
