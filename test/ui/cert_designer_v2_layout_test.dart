// The certificate designer's presentational parts at 320 × 640 and 1400 × 900, Arabic and English, text × 1.3:
// the properties panel for text / logo / signature with captions / QR / line / photo, the language switcher with
// inherited English settings, the languages control, page image rows, the tools, the layers and the toolbar row,
// and the canvas elements themselves.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/cert_canvas_item.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/cert_designer_panels.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/cert_studio_adapter.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _text = CertField(
  id: 't',
  text: 'Certificate of completion for {student_name} — {grade}',
  textAr: 'شهادة إتمام {student_name}',
  w: 600,
  size: 36,
  font: 'amiri_bold',
);
const _logo = CertField(id: 'l', kind: CertFieldKind.logo, w: 90, h: 90, src: 'https://example.invalid/logo.png');
const _sig = CertField(
  id: 's',
  kind: CertFieldKind.signature,
  w: 220,
  h: 80,
  size: 22,
  sigName: 'Dr. Sara Mahmoud Abdel-Rahman',
  sigTitle: 'Dean of the Faculty of Engineering and Technology',
);
const _qr = CertField(id: 'q', kind: CertFieldKind.qr, w: 110, color: '#1E3A8A');
const _line = CertField(id: 'n', kind: CertFieldKind.line, w: 300, h: 2);
const _photo = CertField(id: 'p', kind: CertFieldKind.photo, w: 130, h: 130, shape: 'rounded');

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

Widget _props(CertField f, {Widget? tuner, String? defaultUrl}) => _scroll(CertFieldProps(
      field: f,
      arabic: AppConfig.lang == 'ar',
      themeHex: '#C49A47',
      defaultImageUrl: defaultUrl,
      customKeys: const ['grade', 'final_rank_in_the_department'],
      onAskCustomField: () async => null,
      onEdit: (change, {label = 'edit', coalesce = true}) {},
      onText: (_) {},
      onReplaceImage: () {},
      onUseDefaultImage: () {},
      signatureTuner: tuner,
      onDuplicate: () {},
      onForward: () {},
      onBackward: () {},
      onDelete: () {},
    ));

StudioController<CertField> _controller() {
  var slice = const CertLangSlice(fields: [_text, _logo, _sig, _qr], orientation: 'landscape');
  final c = StudioController<CertField>(
    adapter: CertStudioAdapter(lang: 'ar', read: () => slice, write: (s) => slice = s),
    page: const StudioPage(1000, 707),
  );
  c.select('l');
  return c;
}

void main() {
  setUp(() => AppConfig.disableList = []);

  group('properties panel', () {
    testWidgets('text', (t) => expectNoLayoutErrors(t, () => _props(_text)));
    testWidgets('logo with its own image', (t) => expectNoLayoutErrors(t, () => _props(_logo, defaultUrl: 'https://example.invalid/d.png')));
    testWidgets('signature with captions and the tuner', (t) => expectNoLayoutErrors(
          t,
          () => _props(
            _sig,
            tuner: CertSignatureTuner(ink: '#1E3A8A', strength: .6, onInk: (_) {}, onStrength: (_) {}),
          ),
        ));
    testWidgets('qr', (t) => expectNoLayoutErrors(t, () => _props(_qr)));
    testWidgets('qr with custom text', (t) => expectNoLayoutErrors(t, () => _props(_qr.copyWith(text: '{serial}'))));
    testWidgets('line and photo', (t) async {
      await expectNoLayoutErrors(t, () => _props(_line));
      await expectNoLayoutErrors(t, () => _props(_photo));
    });
    testWidgets('read-only', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(CertFieldProps(
            field: _text,
            arabic: true,
            enabled: false,
            onEdit: (change, {label = 'edit', coalesce = true}) {},
            onText: (_) {},
          )),
        ));
  });

  group('languages', () {
    testWidgets('switcher on English with inherited settings', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(CertLangSwitcher(
            langs: const ['ar', 'en'],
            active: 'en',
            inheritedEn: const ['Background', 'Theme colours', 'Default logo', 'Default signature'],
            onChanged: (_) {},
            onManage: () {},
          )),
        ));
    testWidgets('switcher with one language', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(CertLangSwitcher(langs: const ['ar'], active: 'ar', onChanged: (_) {}, onManage: () {})),
        ));
    testWidgets('languages control', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(CertLangsControl(langs: const ['ar', 'en'], onChanged: (_) {})),
        ));
    testWidgets('page image rows: Arabic, English same / own / none', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(Column(children: [
            CertAssetRow(title: 'Background', url: 'https://example.invalid/bg.png', onUpload: () {}, onRemove: () {}),
            CertAssetRow(
              title: 'Default logo',
              url: 'https://example.invalid/l.png',
              english: true,
              state: CertInherit.same,
              onCustomize: () {},
              more: [TextButton(onPressed: () {}, child: const Text('No background in English'))],
            ),
            CertAssetRow(
              title: 'Default signature',
              url: 'https://example.invalid/s.png',
              english: true,
              hint: 'Upload a photo of the signature on white paper: the background is removed automatically.',
              onUpload: () {},
              onRemove: () {},
              onReset: () {},
            ),
            CertAssetRow(title: 'Background', url: null, english: true, state: CertInherit.none, onUpload: () {}, onReset: () {}),
          ])),
        ));
  });

  group('tools, layers, toolbar', () {
    testWidgets('tools list and grid', (t) => expectNoLayoutErrors(
          t,
          () => _scroll(Column(children: [
            CertToolsPanel(onAdd: (_) {}),
            const SizedBox(height: 16),
            CertToolsPanel(onAdd: (_) {}, grid: true),
          ])),
        ));
    testWidgets('layers', (t) => expectNoLayoutErrors(
          t,
          () => SizedBox(
            height: 400,
            child: CertLayersList(
              fields: const [_text, _logo, _sig, _qr, _line, _photo],
              arabic: AppConfig.lang == 'ar',
              selectedId: 's',
              onSelect: (_) {},
              onToggleVisible: (_) {},
              onReorder: (_, _) {},
              onDelete: (_) {},
            ),
          ),
        ));
    testWidgets('toolbar row with a selection', (t) {
      final c = _controller();
      addTearDown(c.dispose);
      return expectNoLayoutErrors(
        t,
        () => Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.topCenter,
            child: CertToolbarRow(
              controller: c,
              leading: [StudioToolButton(icon: Icons.add_box_outlined, label: 'Add', showLabel: true, onPressed: () {})],
            ),
          ),
        ),
      );
    });
  });

  group('canvas', () {
    testWidgets('elements on the studio canvas', (t) {
      final c = _controller();
      addTearDown(c.dispose);
      return expectNoLayoutErrors(
        t,
        () => StudioCanvas<CertField>(
          controller: c,
          itemBuilder: (context, item, selected) => CertFieldView(
            field: item.payload,
            size: item.rect.size,
            scale: StudioCanvas.scaleOf(context),
            arabic: AppConfig.lang == 'ar',
            imageUrl: item.payload.src,
            samples: const {'grade': 'A+'},
          ),
        ),
      );
    });
    testWidgets('every kind at a small scale', (t) => expectNoLayoutErrors(
          t,
          () => Wrap(children: [
            for (final f in const [_text, _logo, _sig, _qr, _line, _photo])
              SizedBox(
                width: f.w * .4,
                height: certFieldRect(f, arabic: true).height * .4,
                child: CertFieldView(field: f, size: certFieldRect(f, arabic: true).size, scale: .4, arabic: true),
              ),
          ]),
        ));
  });
}
