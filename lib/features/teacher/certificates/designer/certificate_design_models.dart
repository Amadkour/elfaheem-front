// features/teacher/certificates/designer/certificate_design_models.dart
//
// Models shared by the certificate designer. They mirror the backend's
// CertificateDesign / CertificateFieldIn schemas (see services/certificate_design_service.py).
//
// Coordinates are LOGICAL units: the page is 1000 x 707 (landscape) or 707 x 1000 (portrait);
// (x, y) is the top-left of a field's box. The editor and the server renderer use the same
// units, so what you position is what gets printed.

import 'dart:ui' show Color;

const double kLogicalLong = 1000;
const double kLogicalShort = 707;

/// Fonts the server can draw — the same keys AND the same static files as
/// certificate_design_renderer.FONT_CATALOG, so the on-screen design is exactly what students receive.
class CertFont {
  final String key;
  final String labelKey;
  final String family;          // bundled static font (assets/fonts/cert)
  final String? arabicFallback; // Latin-only fonts draw Arabic with Amiri — like the server
  final bool arabic;            // has its own Arabic glyphs
  // weight / style are baked into each file: never synthesized (that is what made the preview differ)
  bool get italic => false;
  bool get bold => false;

  const CertFont(this.key, this.labelKey, this.family, {this.arabicFallback, this.arabic = false});
}

const List<CertFont> kCertFonts = [
  CertFont('cinzel', 'cert_font_cinzel', 'CertCinzel', arabicFallback: 'CertAmiriBold', arabic: false),
  CertFont('great_vibes', 'cert_font_great_vibes', 'CertGreatVibes', arabicFallback: 'CertAmiriBold', arabic: false),
  CertFont('cormorant_italic', 'cert_font_cormorant_italic', 'CertCormorantItalic', arabicFallback: 'CertAmiri', arabic: false),
  CertFont('cormorant', 'cert_font_cormorant', 'CertCormorant', arabicFallback: 'CertAmiriBold', arabic: false),
  CertFont('playfair', 'cert_font_playfair', 'CertPlayfair', arabicFallback: 'CertAmiri', arabic: false),
  CertFont('playfair_bold', 'cert_font_playfair_bold', 'CertPlayfairBold', arabicFallback: 'CertAmiriBold', arabic: false),
  CertFont('playfair_italic', 'cert_font_playfair_italic', 'CertPlayfairItalic', arabicFallback: 'CertAmiri', arabic: false),
  CertFont('eb_garamond', 'cert_font_eb_garamond', 'CertEBGaramond', arabicFallback: 'CertAmiri', arabic: false),
  CertFont('pinyon_script', 'cert_font_pinyon_script', 'CertPinyon', arabicFallback: 'CertAmiri', arabic: false),
  CertFont('baskerville', 'cert_font_baskerville', 'CertBaskerville', arabicFallback: 'CertAmiri', arabic: false),
  CertFont('baskerville_bold', 'cert_font_baskerville_bold', 'CertBaskervilleBold', arabicFallback: 'CertAmiriBold', arabic: false),
  CertFont('tajawal', 'cert_font_tajawal', 'tajawal', arabic: true),
  CertFont('tajawal_medium', 'cert_font_tajawal_medium', 'CertTajawalMedium', arabic: true),
  CertFont('tajawal_bold', 'cert_font_tajawal_bold', 'CertTajawalBold', arabic: true),
  CertFont('amiri', 'cert_font_amiri', 'CertAmiri', arabic: true),
  CertFont('amiri_bold', 'cert_font_amiri_bold', 'CertAmiriBold', arabic: true),
  CertFont('aref_ruqaa', 'cert_font_aref_ruqaa', 'CertArefRuqaa', arabic: true),
  CertFont('aref_ruqaa_bold', 'cert_font_aref_ruqaa_bold', 'CertArefRuqaaBold', arabic: true),
  CertFont('scheherazade', 'cert_font_scheherazade', 'CertScheherazade', arabic: true),
  CertFont('scheherazade_bold', 'cert_font_scheherazade_bold', 'CertScheherazadeBold', arabic: true),
  CertFont('reem_kufi', 'cert_font_reem_kufi', 'CertReemKufi', arabic: true),
  CertFont('reem_kufi_bold', 'cert_font_reem_kufi_bold', 'CertReemKufiBold', arabic: true),
  CertFont('el_messiri', 'cert_font_el_messiri', 'CertElMessiri', arabic: true),
  CertFont('el_messiri_bold', 'cert_font_el_messiri_bold', 'CertElMessiriBold', arabic: true),
  CertFont('cairo', 'cert_font_cairo', 'CertCairo', arabic: true),
  CertFont('cairo_bold', 'cert_font_cairo_bold', 'CertCairoBold', arabic: true),
  CertFont('markazi', 'cert_font_markazi', 'CertMarkazi', arabic: true),
  CertFont('markazi_bold', 'cert_font_markazi_bold', 'CertMarkaziBold', arabic: true),
];

CertFont certFont(String key) =>
    kCertFonts.firstWhere((f) => f.key == key, orElse: () => kCertFonts.firstWhere((f) => f.key == 'tajawal'));

/// Dynamic values a text field can contain, written as {key}.
class CertPlaceholder {
  final String key;
  final String labelKey;
  final String sampleEn;
  final String sampleAr;

  const CertPlaceholder(this.key, this.labelKey, this.sampleEn, this.sampleAr);
}

const List<CertPlaceholder> kCertPlaceholders = [
  CertPlaceholder('student_name', 'cert_ph_student_name', 'Mohamed Ahmed Ali', 'محمد أحمد علي'),
  CertPlaceholder('course_name', 'cert_ph_course_name', 'Programming Fundamentals', 'أساسيات البرمجة'),
  CertPlaceholder('certificate_title', 'cert_ph_certificate_title', 'Course Completion', 'إتمام الدورة'),
  CertPlaceholder('teacher_name', 'cert_ph_teacher_name', 'Dr. Sara Mahmoud', 'د. سارة محمود'),
  CertPlaceholder('date', 'cert_ph_date', '19 October 2026', '19 أكتوبر 2026'),
  CertPlaceholder('serial', 'cert_ph_serial', 'EF-0001-001-00042', 'EF-0001-001-00042'),
  CertPlaceholder('attendance', 'cert_ph_attendance', '18 / 20', '18 / 20'),
  CertPlaceholder('progress', 'cert_ph_progress', '100%', '100%'),
  CertPlaceholder('org_name', 'cert_ph_org_name', 'Organization name', 'اسم المؤسسة'),
];

/// Replaces {placeholders} with sample values (for the on-screen preview).
String resolveSample(String template, {required bool arabic}) {
  var out = template;
  for (final p in kCertPlaceholders) {
    out = out.replaceAll('{${p.key}}', arabic ? p.sampleAr : p.sampleEn);
  }
  return out;
}

Color hexToColor(String hex, {Color fallback = const Color(0xFF000000)}) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

String colorToHex(Color c) {
  String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

enum CertFieldKind { text, signature, logo, line, photo }

CertFieldKind _kindOf(String? s) => CertFieldKind.values.firstWhere(
      (k) => k.name == s,
      orElse: () => CertFieldKind.text,
    );

class CertField {
  final String id;
  final CertFieldKind kind;
  final String? text;
  final String? textAr;
  final double x;
  final double y;
  final double w;
  final double h;
  final String align; // left | center | right
  final String font;
  final double size;
  final String color; // #RRGGBB
  final double letterSpacing;
  final double opacity;
  final int maxLines;
  final bool shrink;
  final bool visible;
  final String shape; // student photo: circle | rounded

  const CertField({
    required this.id,
    this.kind = CertFieldKind.text,
    this.text,
    this.textAr,
    this.x = 0,
    this.y = 0,
    this.w = 200,
    this.h = 0,
    this.align = 'center',
    this.font = 'tajawal',
    this.size = 24,
    this.color = '#1C1C24',
    this.letterSpacing = 0,
    this.opacity = 1,
    this.maxLines = 3,
    this.shrink = true,
    this.visible = true,
    this.shape = 'circle',
  });

  bool get isText => kind == CertFieldKind.text;
  bool get isImage => kind == CertFieldKind.signature || kind == CertFieldKind.logo;

  factory CertField.fromJson(Map<String, dynamic> j) => CertField(
        id: j['id'] as String,
        kind: _kindOf(j['kind'] as String?),
        text: j['text'] as String?,
        textAr: j['text_ar'] as String?,
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 200,
        h: (j['h'] as num?)?.toDouble() ?? 0,
        align: (j['align'] as String?) ?? 'center',
        font: (j['font'] as String?) ?? 'tajawal',
        size: (j['size'] as num?)?.toDouble() ?? 24,
        color: (j['color'] as String?) ?? '#1C1C24',
        letterSpacing: (j['letter_spacing'] as num?)?.toDouble() ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
        maxLines: (j['max_lines'] as num?)?.toInt() ?? 3,
        shrink: (j['shrink'] as bool?) ?? true,
        visible: (j['visible'] as bool?) ?? true,
        shape: (j['shape'] as String?) ?? 'circle',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'text': text,
        'text_ar': textAr,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'align': align,
        'font': font,
        'size': size,
        'color': color,
        'letter_spacing': letterSpacing,
        'opacity': opacity,
        'max_lines': maxLines,
        'shrink': shrink,
        'visible': visible,
        if (kind == CertFieldKind.photo) 'shape': shape,
      };

  CertField copyWith({
    String? text,
    String? textAr,
    bool clearTextAr = false,
    double? x,
    double? y,
    double? w,
    double? h,
    String? align,
    String? font,
    double? size,
    String? color,
    double? letterSpacing,
    double? opacity,
    int? maxLines,
    bool? shrink,
    bool? visible,
    String? shape,
  }) =>
      CertField(
        id: id,
        kind: kind,
        text: text ?? this.text,
        textAr: clearTextAr ? null : (textAr ?? this.textAr),
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        align: align ?? this.align,
        font: font ?? this.font,
        size: size ?? this.size,
        color: color ?? this.color,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        opacity: opacity ?? this.opacity,
        maxLines: maxLines ?? this.maxLines,
        shrink: shrink ?? this.shrink,
        visible: visible ?? this.visible,
        shape: shape ?? this.shape,
      );

  CertField copyWithNewId(String newId) => CertField(
        id: newId,
        kind: kind,
        text: text,
        textAr: textAr,
        x: x,
        y: y,
        w: w,
        h: h,
        align: align,
        font: font,
        size: size,
        color: color,
        letterSpacing: letterSpacing,
        opacity: opacity,
        maxLines: maxLines,
        shrink: shrink,
        visible: visible,
      );
}

class CertDesign {
  final int id;
  final String name;
  final int? ownerId;
  final int? orgId;
  final String orientation; // landscape | portrait
  final String? backgroundUrl;
  final String backgroundKind; // none | upload | draft
  final String? signatureUrl;
  final String? logoUrl;
  final Map<String, dynamic> theme; // {color, dark, style}
  final List<CertField> fields;
  final bool canEdit;

  const CertDesign({
    required this.id,
    required this.name,
    this.ownerId,
    this.orgId,
    this.orientation = 'landscape',
    this.backgroundUrl,
    this.backgroundKind = 'none',
    this.signatureUrl,
    this.logoUrl,
    this.theme = const {},
    this.fields = const [],
    this.canEdit = true,
  });

  bool get landscape => orientation != 'portrait';
  double get logicalW => landscape ? kLogicalLong : kLogicalShort;
  double get logicalH => landscape ? kLogicalShort : kLogicalLong;

  factory CertDesign.fromJson(Map<String, dynamic> j) => CertDesign(
        id: (j['id'] as num).toInt(),
        name: (j['name'] as String?) ?? '',
        ownerId: (j['owner_id'] as num?)?.toInt(),
        orgId: (j['org_id'] as num?)?.toInt(),
        orientation: (j['orientation'] as String?) ?? 'landscape',
        backgroundUrl: j['background_url'] as String?,
        backgroundKind: (j['background_kind'] as String?) ?? 'none',
        signatureUrl: j['signature_url'] as String?,
        logoUrl: j['logo_url'] as String?,
        theme: Map<String, dynamic>.from((j['theme'] as Map?) ?? const {}),
        fields: ((j['fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CertField.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        canEdit: (j['can_edit'] as bool?) ?? false,
      );

  CertDesign copyWith({
    String? name,
    String? orientation,
    String? backgroundUrl,
    bool clearBackground = false,
    String? backgroundKind,
    String? signatureUrl,
    bool clearSignature = false,
    String? logoUrl,
    bool clearLogo = false,
    Map<String, dynamic>? theme,
    List<CertField>? fields,
  }) =>
      CertDesign(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId,
        orgId: orgId,
        orientation: orientation ?? this.orientation,
        backgroundUrl: clearBackground ? null : (backgroundUrl ?? this.backgroundUrl),
        backgroundKind: clearBackground ? 'none' : (backgroundKind ?? this.backgroundKind),
        signatureUrl: clearSignature ? null : (signatureUrl ?? this.signatureUrl),
        logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
        theme: theme ?? this.theme,
        fields: fields ?? this.fields,
        canEdit: canEdit,
      );
}
