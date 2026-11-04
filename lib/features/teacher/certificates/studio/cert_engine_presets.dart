// features/teacher/certificates/studio/cert_engine_presets.dart
//
// What the certificate studio offers on the design engine (D-165): the placeholder catalog (the row the server fills
// per recipient), sample values for the canvas and the preview, the "Add" menu (ready elements, millimetres on the
// page), the mirrored copy of a design for the other language and the helpers that move a design into another one
// IN PLACE (the canvas controllers hold the element lists, so a list is never replaced).
library;

import 'package:flutter/material.dart';

import '../../../../design/export_layout/layout_canvas.dart' show LayoutAddOption;
import '../../../../design/export_layout/layout_model.dart';
import '../../../../design/export_layout/layout_props.dart' show LayoutFieldOption;
import '../../../admin/admin_common.dart' show t;

/// One recipient value: its key in the row, its names and the sample shown while designing.
class CertPlaceholder {
  const CertPlaceholder(this.key, this.ar, this.en, this.sampleAr, this.sampleEn, {this.type = 'text'});
  final String key, ar, en, sampleAr, sampleEn;
  final String type;

  String label(String lang) => lang == 'ar' ? ar : en;
  String sample(String lang) => lang == 'ar' ? sampleAr : sampleEn;
}

const kCertPlaceholders = <CertPlaceholder>[
  CertPlaceholder('student_name', 'اسم الطالب', 'Student name', 'أحمد محمد علي', 'Ahmed Mohamed Ali'),
  CertPlaceholder('course_name', 'اسم الدورة', 'Course name', 'أساسيات البرمجة', 'Programming Fundamentals'),
  CertPlaceholder('certificate_title', 'عنوان الشهادة', 'Certificate title', 'شهادة إتمام', 'Certificate of Completion'),
  CertPlaceholder('teacher_name', 'اسم المدرّس', 'Teacher name', 'د. سارة حسن', 'Dr. Sara Hassan'),
  CertPlaceholder('date', 'التاريخ', 'Date', '١٥ مارس ٢٠٢٦', '15 March 2026', type: 'date'),
  CertPlaceholder('serial', 'الرقم التسلسلي', 'Serial number', 'NB-2026-000123', 'NB-2026-000123'),
  CertPlaceholder('grade', 'الدرجة', 'Grade', '95%', '95%'),
  CertPlaceholder('org_name', 'اسم المؤسسة', 'Organization name', 'أكاديمية نكست برين', 'NextBrain Academy'),
];

/// Keys the studio knows without a declaration (the row, plus the verify link and the photo).
final Set<String> kCertBuiltInKeys = {for (final p in kCertPlaceholders) p.key, 'verify_url', 'photo'};

final RegExp kCertCustomKey = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// Why [key] cannot be a custom variable (null when fine).
String? certCustomKeyError(String key) {
  if (key.isEmpty) return t('اكتب اسم المتغيّر', 'Enter a variable name');
  if (!kCertCustomKey.hasMatch(key)) return t('أحرف إنجليزية صغيرة وأرقام و _ فقط', 'Lowercase letters, digits and _ only');
  if (kCertBuiltInKeys.contains(key)) return t('هذا الاسم مستخدم', 'This name is already used');
  return null;
}

final RegExp _tokens = RegExp(r'\{\{\s*([A-Za-z0-9_]+)\s*\}\}');

/// The custom variables the document uses (not built in), in order of first use.
List<String> certCustomKeysOf(LayoutDocument doc) {
  final out = <String>[];
  void see(String? k) {
    if (k != null && k.isNotEmpty && !kCertBuiltInKeys.contains(k) && !out.contains(k)) out.add(k);
  }

  for (final d in doc.designs.values) {
    for (final e in d.row.elements) {
      for (final s in [e.value, e.sigName, e.sigTitle]) {
        if (s == null) continue;
        for (final m in _tokens.allMatches(s)) {
          see(m.group(1));
        }
      }
      see(e.bind?.field);
    }
  }
  return out;
}

/// The fields the properties panel offers for a bound element, in [lang].
List<LayoutFieldOption> certFieldOptions(String lang, List<String> custom) => [
      for (final p in kCertPlaceholders) (key: p.key, label: p.label(lang), numeric: false),
      (key: 'verify_url', label: t('رابط التحقق', 'Verify link'), numeric: false),
      (key: 'photo', label: t('الصورة', 'Photo'), numeric: false),
      for (final k in custom) (key: k, label: k, numeric: false),
    ];

/// The field (names) the canvas shows in brackets for a bound element.
LayoutField? certFieldOf(String lang, String key) {
  for (final p in kCertPlaceholders) {
    if (p.key == key) return LayoutField(key: key, labelAr: p.ar, labelEn: p.en);
  }
  return switch (key) {
    'verify_url' => const LayoutField(key: 'verify_url', labelAr: 'رابط التحقق', labelEn: 'Verify link'),
    'photo' => const LayoutField(key: 'photo', labelAr: 'الصورة', labelEn: 'Photo'),
    _ => LayoutField(key: key, labelAr: key, labelEn: key),
  };
}

/// Sample values for the canvas texts and the server preview.
Map<String, String> certSampleValues(String lang, List<String> custom) => {
      for (final p in kCertPlaceholders) p.key: p.sample(lang),
      'verify_url': 'https://nextbrain.site/v/NB-2026-000123',
      for (final k in custom) k: k.replaceAll('_', ' '),
    };

// ── the Add menu ─────────────────────────────────────────────────────────────────────────────────────────────────

LayoutElement _text(String id, {String? value, LayoutBind? bind, String? name, double w = 120, double h = 14, double size = 20, int weight = 400, String align = 'center', String color = '#1A1A1A'}) =>
    LayoutElement(
      id: id,
      kind: bind != null ? 'field' : 'text',
      w: w,
      h: h,
      value: value,
      bind: bind,
      name: name,
      style: LayoutStyle(size: size, weight: weight, align: align, color: color, padding: 0),
    );

/// The ready elements of the "Add" menu; [custom] are the document's own variables.
List<LayoutAddOption> certAddOptions(String lang, List<String> custom) => [
      LayoutAddOption(t('نص', 'Text'), Icons.text_fields_rounded, (id) => _text(id, value: t('نص جديد', 'New text'))),
      for (final p in kCertPlaceholders)
        LayoutAddOption(
          p.label(lang),
          p.type == 'date' ? Icons.event_rounded : Icons.data_object_rounded,
          (id) => _text(id, bind: LayoutBind(field: p.key, format: p.type == 'date' ? 'date' : 'text', empty: ''), name: p.label(lang), size: p.key == 'student_name' ? 30 : 18, weight: p.key == 'student_name' ? 700 : 400),
        ),
      for (final k in custom)
        LayoutAddOption(k, Icons.data_object_rounded, (id) => _text(id, value: '{{$k}}', name: k)),
      LayoutAddOption(t('شعار', 'Logo'), Icons.workspace_premium_outlined, (id) => LayoutElement(id: id, kind: 'image', w: 35, h: 35, fit: 'contain', name: t('شعار', 'Logo'))),
      LayoutAddOption(
        t('توقيع', 'Signature'),
        Icons.draw_rounded,
        (id) => LayoutElement(
          id: id,
          kind: 'signature',
          w: 55,
          h: 30,
          fit: 'contain',
          sigName: '{{teacher_name}}',
          sigTitle: t('المدرّس', 'Instructor'),
          name: t('توقيع', 'Signature'),
          style: LayoutStyle(size: 11, align: 'center'),
        ),
      ),
      LayoutAddOption(t('صورة', 'Image'), Icons.image_outlined, (id) => LayoutElement(id: id, kind: 'image', w: 50, h: 35, fit: 'contain')),
      LayoutAddOption(
        t('صورة الطالب', 'Student photo'),
        Icons.account_circle_outlined,
        (id) => LayoutElement(id: id, kind: 'image', w: 32, h: 32, fit: 'cover', shape: 'circle', bind: LayoutBind(field: 'photo', empty: ''), name: t('صورة الطالب', 'Student photo')),
      ),
      LayoutAddOption(t('رمز QR للتحقق', 'Verify QR code'), Icons.qr_code_2_rounded, (id) => LayoutElement(id: id, kind: 'qr', w: 26, h: 26, value: '{{verify_url}}', name: t('رمز التحقق', 'Verify QR'))),
      LayoutAddOption(t('خط', 'Line'), Icons.horizontal_rule_rounded, (id) => LayoutElement(id: id, kind: 'line', w: 70, h: .8, style: LayoutStyle(color: '#C49A47'))),
      LayoutAddOption(t('مستطيل', 'Rectangle'), Icons.crop_square_rounded, (id) => LayoutElement(id: id, kind: 'rect', w: 60, h: 30, style: LayoutStyle(border: LayoutBorder(width: .6, color: '#C49A47')))),
      LayoutAddOption(t('شكل بيضاوي', 'Ellipse'), Icons.circle_outlined, (id) => LayoutElement(id: id, kind: 'ellipse', w: 40, h: 40, style: LayoutStyle(border: LayoutBorder(width: .6, color: '#C49A47')))),
    ];

// ── designs ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// A blank certificate page: A4 landscape, margins 0 (the canvas is the page).
LayoutDesign certBlankDesign(String lang) => LayoutDesign(
      mode: 'page',
      page: LayoutPage(orientation: 'landscape', margins: LayoutMargins(top: 0, right: 0, bottom: 0, left: 0), rtl: lang == 'ar', fontSize: 14),
    );

/// A new certificate document with the given designs.
LayoutDocument certNewDocument(Map<String, LayoutDesign> designs) => LayoutDocument(
      purpose: 'certificate',
      languages: designs.keys.toList(),
      designs: {...designs},
    );

/// [src] for the other language: every x mirrored (x' = width − x − w), rtl [toRtl], rotations reversed. The texts
/// stay as they are (the person translates them); this is an explicit copy, never a fallback.
LayoutDesign certMirrorDesign(LayoutDesign src, {required bool toRtl}) {
  final copy = src.copy();
  final width = copy.page.contentWidth;
  copy.page.rtl = toRtl;
  for (final e in copy.row.elements) {
    e
      ..x = mm(width - e.x - e.w)
      ..rotation = -e.rotation;
    if (e.style.dir == 'rtl' || e.style.dir == 'ltr') e.style.dir = 'auto';
  }
  return copy;
}

/// Moves [src] into [target] in place (the element list keeps its identity: the canvas controller holds it).
void certAdoptDesign(LayoutDesign target, LayoutDesign src) {
  final from = src.copy();
  target
    ..mode = 'page'
    ..page = from.page;
  target.row
    ..height = from.row.height
    ..background = from.row.background
    ..elements.clear()
    ..elements.addAll(from.row.elements);
  target.watermark = from.watermark;
  target.frame = from.frame;
}

/// The page of [d] changed from [oldW]×[oldH] to its current size: the elements keep their relative places.
void certRescaleElements(LayoutDesign d, double oldW, double oldH) {
  final nw = d.page.contentWidth, nh = d.page.contentHeight;
  if (oldW <= 0 || oldH <= 0 || (nw == oldW && nh == oldH)) return;
  final sx = nw / oldW, sy = nh / oldH;
  for (final e in d.row.elements) {
    e
      ..x = mm(e.x * sx)
      ..y = mm(e.y * sy)
      ..w = mm(e.w * sx)
      ..h = mm(e.h * sy);
  }
}
