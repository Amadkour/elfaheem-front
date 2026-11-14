// The certificate studio's new parts at 320 × 640 and 1400 × 900, Arabic and English, text × 1.3 (layout_harness):
// the properties of a fully styled text (style toggles, line height, direction, box, shadow, rotation, layer) and of
// an image (fit, crop, aspect lock), the paper control, the watermark control, the preview's sample data, a template
// card, the layers list with locks, the canvas text and the watermark — and the whole designer, whose properties are
// docked on the end side (tablet / desktop) or in a non-modal panel under the page (phone).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_canvas_item.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_designer_panels.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_text_layout.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_designer_provider.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_designer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _styled = CertField(
  id: 't',
  text: 'Certificate of excellence for {student_name}',
  textAr: 'شهادة تميز إلى {student_name}',
  w: 520,
  size: 34,
  font: 'cairo',
  maxLines: 2,
  weight: 'bold',
  italic: true,
  underline: true,
  lineHeight: 1.4,
  direction: 'rtl',
  bgColor: '#F4EBD0',
  bgOpacity: .8,
  borderColor: '#C49A47',
  borderWidth: 2,
  radius: 12,
  padding: 14,
  shadowColor: '#000000',
  rotation: -6,
  name: 'Headline of the certificate with a long layer name',
  locked: true,
);
const _logo = CertField(id: 'l', kind: CertFieldKind.logo, w: 120, h: 80, src: 'https://example.invalid/logo.png', fit: 'cover', aspectLock: false);

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

Widget _props(CertField f) => _scroll(CertFieldProps(
      field: f,
      arabic: AppConfig.lang == 'ar',
      themeHex: '#C49A47',
      defaultImageUrl: 'https://example.invalid/d.png',
      onEdit: (change, {label = 'edit', coalesce = true}) {},
      onText: (_) {},
      onReplaceImage: () {},
      onUseDefaultImage: () {},
      onCropImage: () {},
      autoLineHeight: 1.32,
      onDuplicate: () {},
      onForward: () {},
      onBackward: () {},
      onDelete: () {},
    ));

CertDesign _design() => CertDesign.fromJson({
      'id': 9,
      'name': 'Graduation certificate of the Faculty of Engineering',
      'orientation': 'landscape',
      'background_kind': 'none',
      'theme': {
        'color': '#C49A47',
        'page': {'size': 'letter'},
        'watermark': {'kind': 'text', 'text': 'ORIGINAL', 'opacity': .1, 'rotation': -30, 'size': 90, 'position': 'center'},
      },
      'fields': [_styled.toJson(), _logo.copyWith(src: null).toJson(),
        {'id': 'n', 'kind': 'text', 'text': '{student_name}', 'x': 200, 'y': 300, 'w': 600, 'size': 40, 'font': 'amiri_bold', 'max_lines': 1}],
      'fields_en': [],
      'can_edit': true,
      'langs': ['ar', 'en'],
    });

void main() {
  setUp(() => AppConfig.disableList = []);

  group('properties', () {
    testWidgets('a fully styled text', (t) => expectNoLayoutErrors(t, () => _props(_styled)));
    testWidgets('an image: fit, crop, aspect lock, rotation', (t) => expectNoLayoutErrors(t, () => _props(_logo)));
  });

  group('page', () {
    testWidgets('paper: A4, Letter, custom', (t) async {
      for (final p in const [CertPage.a4, CertPage(size: 'letter'), CertPage(size: 'custom', wMm: 250, hMm: 180)]) {
        await expectNoLayoutErrors(t, () => _scroll(CertPaperControl(page: p, onChanged: (_) {})));
      }
    });
    testWidgets('watermark: none, text, image', (t) async {
      for (final w in const [
        null,
        CertWatermark(text: 'نسخة أصلية معتمدة من المؤسسة', position: 'tile'),
        CertWatermark(kind: 'image', src: 'https://example.invalid/wm.png'),
      ]) {
        await expectNoLayoutErrors(
            t, () => _scroll(CertWatermarkControl(watermark: w, onChanged: (_, {coalesce = false}) {}, onUploadImage: () {})));
      }
    });
    testWidgets('preview sample data', (t) => expectNoLayoutErrors(
          t,
          () => CertSampleDataForm(lang: AppConfig.lang, values: const {'student_name': 'Layla'}, onApply: (_) {}),
        ));
    testWidgets('template cards', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(Wrap(spacing: 8, runSpacing: 8, children: [
            CertTemplateCard(name: 'Classic gold with a very long template name', preview: null, portrait: false, onTap: () {}),
            CertTemplateCard(name: 'Academic', preview: null, portrait: true, onTap: () {}, width: 160),
          ])),
        ));
  });

  group('layers and canvas', () {
    testWidgets('layers with a locked, a hidden and a named element', (t) => expectNoLayoutErrors(
          t,
          () => CertLayersList(
            fields: [_styled, _logo.copyWith(visible: false), const CertField(id: 'q', kind: CertFieldKind.qr, w: 100)],
            arabic: AppConfig.lang == 'ar',
            selectedId: 'q',
            onSelect: (_) {},
            onToggleVisible: (_) {},
            onToggleLock: (_) {},
            onReorder: (_, _) {},
            onDelete: (_) {},
          ),
        ));
    testWidgets('the canvas text and a tiled watermark', (t) => expectNoLayoutErrors(
          t,
          () {
            final f = _styled.copyWith(rotation: 0);
            final l = certTextLayout(f, f.textAr!)!;
            return Stack(children: [
              const Positioned.fill(
                child: CertWatermarkView(
                  watermark: CertWatermark(text: 'ORIGINAL', position: 'tile', size: 40),
                  scale: .5,
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                width: l.boxWidth * .5,
                height: l.boxHeight * .5,
                child: CertTextView(field: f, layout: l, scale: .5),
              ),
            ]);
          },
        ));
  });

  group('the designer', () {
    testWidgets('properties docked at every width (page panel)', (t) async {
      await expectNoLayoutErrors(t, () {
        final p = CertificateDesignerProvider(initialLang: AppConfig.lang, drafts: CertMemoryDraftStore())..adopt(_design());
        return CertificateDesignerScreen(provider: p);
      }, frames: 4);
    });
    testWidgets('with a selected element (the phone panel opens)', (t) async {
      await expectNoLayoutErrors(t, () {
        final p = CertificateDesignerProvider(initialLang: AppConfig.lang, drafts: CertMemoryDraftStore())..adopt(_design());
        p.studio.select('n');
        return CertificateDesignerScreen(provider: p);
      }, frames: 6);
    });
  });
}
