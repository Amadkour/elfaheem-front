// Certificates as Word (2.1.6): every element where the renderer puts it, every logo / signature field with its OWN
// picture, {placeholders} filled, Arabic right to left, fonts embedded.
//
// EXPORT_SAMPLES=<dir> flutter test test/export/cert_docx_test.dart writes certificate_ar.docx / certificate_en.docx.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/cert_docx.dart';
import 'package:flutter_education_app/design/export/docx_fonts.dart';
import 'package:flutter_education_app/design/export/export_fonts.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_word.dart' show certIssuedVariables;
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/disk_fonts.dart';

Uint8List png(int w, int h, int r, int g, int b, {String? label}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  if (label != null) img.drawString(im, label, font: img.arial24, x: 4, y: 4, color: img.ColorRgb8(255, 255, 255));
  return img.encodePng(im);
}

CertLangView view(String lang) {
  final ar = lang == 'ar';
  return CertLangView(
    lang: lang,
    orientation: 'landscape',
    backgroundUrl: 'https://x/bg.png',
    signatureUrl: 'https://x/default-sig.png',
    logoUrl: 'https://x/default-logo.png',
    fields: [
      CertField(id: 'title', text: 'Certificate of {certificate_title}', textAr: 'شهادة {certificate_title}', x: 100, y: 90, w: 800, h: 60, size: 44, font: ar ? 'amiri_bold' : 'cinzel', color: '#7A5A10'),
      CertField(id: 'name', text: '{student_name}', x: 150, y: 220, w: 700, h: 70, size: 54, font: ar ? 'aref_ruqaa' : 'great_vibes', maxLines: 1),
      CertField(id: 'body', text: 'for completing {course_name} on {date}', textAr: 'لإتمامه {course_name} بتاريخ {date} بتقدير {grade}', x: 150, y: 310, w: 700, h: 60, size: 22, font: ar ? 'cairo' : 'playfair'),
      const CertField(id: 'line', kind: CertFieldKind.line, x: 300, y: 395, w: 400, h: 2, color: '#C49A47'),
      // two signatures, each its own picture; one logo with its own picture, one on the design's default
      CertField(id: 'sig1', kind: CertFieldKind.signature, src: 'https://x/sig-dean.png', x: 90, y: 470, w: 220, h: 80, sigName: ar ? 'د. سارة محمود' : 'Dr. Sara Mahmoud', sigTitle: ar ? 'العميد' : 'Dean', size: 22),
      CertField(id: 'sig2', kind: CertFieldKind.signature, src: 'https://x/sig-chair.png', x: 690, y: 470, w: 220, h: 80, sigName: '{teacher_name}', sigTitle: ar ? 'رئيس القسم' : 'Head of department', size: 22),
      const CertField(id: 'sig3', kind: CertFieldKind.signature, x: 390, y: 520, w: 220, h: 70, size: 20),
      const CertField(id: 'logo1', kind: CertFieldKind.logo, src: 'https://x/logo-org.png', x: 40, y: 30, w: 120, h: 60),
      const CertField(id: 'logo2', kind: CertFieldKind.logo, x: 840, y: 30, w: 120, h: 60),
      const CertField(id: 'qr', kind: CertFieldKind.qr, x: 880, y: 590, w: 90),
      const CertField(id: 'serial', text: '{serial}', x: 40, y: 660, w: 300, h: 24, size: 14, align: 'left', font: 'tajawal'),
    ],
  );
}

final images = {
  'https://x/bg.png': png(400, 283, 250, 246, 236),
  'https://x/default-sig.png': png(200, 70, 30, 30, 120, label: 'DEFAULT'),
  'https://x/default-logo.png': png(120, 60, 120, 30, 30, label: 'DLOGO'),
  'https://x/sig-dean.png': png(200, 80, 20, 90, 40, label: 'DEAN'),
  'https://x/sig-chair.png': png(200, 80, 90, 20, 90, label: 'CHAIR'),
  'https://x/logo-org.png': png(120, 60, 15, 118, 110, label: 'ORG'),
};

Map<String, List<int>> unzip(Uint8List b) => {for (final f in ZipDecoder().decodeBytes(b)) if (f.isFile) f.name: f.content};

void main() {
  useDiskFonts();

  for (final lang in ['ar', 'en']) {
    test('Word certificate ($lang): own pictures, filled text, page, fonts', () async {
      AppConfig.lang = lang;
      final v = view(lang);
      final cert = IssuedCert(
        id: 1,
        serial: 'NB-2026-0042',
        recipientName: lang == 'ar' ? 'محمد أحمد علي' : 'Mohamed Ahmed Ali',
        verifyUrl: 'https://nextbrain.site/verify/abc',
        createdAt: DateTime.utc(2026, 11, 1, 9),
        values: const {'grade': 'ممتاز', 'course_name': 'Data Science', 'email': 'x@y.z'},
      );
      final vars = certIssuedVariables(cert, null, lang);
      expect(vars['date'], lang == 'ar' ? '1 نوفمبر 2026' : '01 November 2026');
      expect(vars.containsKey('email'), isFalse);
      final ids = {for (final f in v.fields) f.font};
      final fonts = DocxFonts.build(await loadDocxFontFiles(ids));
      final files = {for (final id in ids) id: await ExportFonts.bytes(ExportFonts.byId(id).regularAsset)};
      expect(certImageUrls(v, vars), images.keys.toSet());
      final bytes = certificateDocx(v, variables: vars, images: images, qr: {'qr': png(64, 64, 0, 0, 0)}, fonts: fonts, fontFiles: files);
      final z = unzip(bytes);
      final doc = utf8.decode(z['word/document.xml']!);
      final rels = utf8.decode(z['word/_rels/document.xml.rels']!);

      // A4 landscape, no margins
      expect(doc, contains('<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'));
      expect(doc, contains('w:left="0"'));
      // the background behind the text
      expect(doc, contains('behindDoc="1"'));

      // one image part per distinct picture: background, 3 signature pictures, 2 logos, QR
      final media = z.keys.where((k) => k.startsWith('word/media/')).toList();
      expect(media, hasLength(7));
      // each picture field references its OWN relationship, and that relationship its own bytes
      String bytesOf(String rid) {
        final target = RegExp('Id="$rid"[^>]*Target="([^"]+)"').firstMatch(rels)!.group(1)!;
        return base64.encode(z['word/$target']!);
      }

      final used = [for (final m in RegExp(r'<a:blip r:embed="(rImg\d+)"').allMatches(doc)) m.group(1)!];
      expect(used.length, 7); // background + 3 signatures + 2 logos + QR
      for (final (url, name) in [
        ('https://x/sig-dean.png', 'dean'),
        ('https://x/sig-chair.png', 'chair'),
        ('https://x/default-sig.png', 'default signature'),
        ('https://x/logo-org.png', 'own logo'),
        ('https://x/default-logo.png', 'default logo'),
      ]) {
        expect(used.where((rid) => bytesOf(rid) == base64.encode(images[url]!)), hasLength(1), reason: name);
      }

      // placeholders filled, unknown ones print nothing, Arabic right to left
      expect(doc, contains(lang == 'ar' ? 'محمد أحمد علي' : 'Mohamed Ahmed Ali'));
      expect(doc, contains('NB-2026-0042'));
      expect(doc, isNot(contains('{')));
      if (lang == 'ar') {
        expect(doc, contains('بتقدير ممتاز'));
        expect(doc, contains('<w:bidi/>'));
        expect(doc, contains('<w:rtl/>'));
      }
      // signature captions under their pictures
      expect(doc, contains(lang == 'ar' ? 'العميد' : 'Dean'));
      // fonts embedded and named
      final ft = utf8.decode(z['word/fontTable.xml']!);
      expect(ft, contains(lang == 'ar' ? 'w:name="Aref Ruqaa"' : 'w:name="Great Vibes"'));
      expect(z.keys.where((k) => k.endsWith('.odttf')), isNotEmpty);
      // text boxes are Word 2010 shapes
      expect(doc, contains('wps:txbx'));
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out != null) File('$out/certificate_$lang.docx').writeAsBytesSync(bytes);
    });
  }

  test('the renderer\'s helpers: {date}, default title, unknown placeholders', () {
    expect(certFill('{a} {b}', {'a': 'x'}), 'x ');
    expect(certTitle('course completion', 'ar'), 'إتمام الدورة');
    expect(certTitle('Data Lab award', 'ar'), 'Data Lab award');
    expect(certDate(DateTime(2026, 3, 5), 'en'), '05 March 2026');
  });
}
