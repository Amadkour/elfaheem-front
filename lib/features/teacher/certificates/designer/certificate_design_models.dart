// features/teacher/certificates/designer/certificate_design_models.dart
//
// Models shared by the certificate designer. They mirror the backend's
// CertificateDesign / CertificateFieldIn schemas (see services/certificate_design_service.py, data/schemas.py).
//
// Coordinates are LOGICAL units: the page is 1000 x 707 (landscape) or 707 x 1000 (portrait);
// (x, y) is the top-left of a field's box. The editor and the server renderer use the same
// units, so what you position is what gets printed.
//
// v2 (FLUTTER_API_CHANGES "Export Studio + certificate studio v2"): one design row holds TWO designs.
//   Arabic  = the base columns + `fields`.
//   English = `fields_en` + each `_en` column: null = the Arabic value, "" on an image = no image in English.
//   `langs` = the languages certificates are issued in. Fields gain `src` (a logo / signature box's own image),
//   `sig_name` / `sig_title` (captions under a signature) and the `qr` kind. Unknown keys are kept as they are.

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

/// The server's limit for one text box (`CertificateFieldIn.text` / `text_ar`, max_length).
const int kCertTextMax = 1000;

/// The server's limit for a signature caption line (`sig_name` / `sig_title`).
const int kCertCaptionMax = 120;

/// The server's limit of elements per layout (MAX_FIELDS).
const int kCertMaxFields = 60;

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

/// Placeholders the server fills by itself but that are not offered as text chips (the QR's link).
const Set<String> kCertHiddenPlaceholders = {'verify_url', 'student_image_url'};

/// What a QR element encodes when its text is empty (the renderer's QR_DEFAULT_TEXT).
const String kCertQrDefaultText = '{verify_url}';

final RegExp _placeholderRe = RegExp(r'\{([a-zA-Z0-9_]+)\}');

/// A custom placeholder key: lowercase letters, digits and "_", 1 – 40 characters.
final RegExp kCertPlaceholderKey = RegExp(r'^[a-z0-9_]{1,40}$');

/// Why [key] cannot be a custom placeholder: 'empty' | 'invalid', or null when it is fine. Surrounding braces and
/// spaces are ignored ("{grade}" is "grade").
String? certPlaceholderKeyError(String key) {
  final k = normalizePlaceholderKey(key);
  if (k.isEmpty) return 'empty';
  if (!kCertPlaceholderKey.hasMatch(k)) return 'invalid';
  return null;
}

String normalizePlaceholderKey(String key) => key.trim().replaceAll('{', '').replaceAll('}', '').trim();

bool isKnownPlaceholder(String key) =>
    kCertHiddenPlaceholders.contains(key) || kCertPlaceholders.any((p) => p.key == key);

/// Every {key} in [text], in order of first use.
List<String> placeholdersIn(String? text) {
  final out = <String>[];
  for (final m in _placeholderRe.allMatches(text ?? '')) {
    final k = m.group(1)!;
    if (!out.contains(k)) out.add(k);
  }
  return out;
}

/// The custom (not built-in) placeholders a layout uses, in order of first use.
List<String> customPlaceholdersOf(Iterable<CertField> fields) {
  final out = <String>[];
  for (final f in fields) {
    for (final t in [f.text, f.textAr, f.sigName, f.sigTitle]) {
      for (final k in placeholdersIn(t)) {
        if (!isKnownPlaceholder(k) && !out.contains(k)) out.add(k);
      }
    }
  }
  return out;
}

/// Replaces {placeholders} with sample values (for the on-screen canvas). A custom key without a sample stays
/// "{key}", like the server preview draws it.
String resolveSample(String template, {required bool arabic, Map<String, String> custom = const {}}) {
  var out = template;
  for (final p in kCertPlaceholders) {
    out = out.replaceAll('{${p.key}}', arabic ? p.sampleAr : p.sampleEn);
  }
  custom.forEach((k, v) {
    if (v.trim().isNotEmpty) out = out.replaceAll('{$k}', v);
  });
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

enum CertFieldKind { text, signature, logo, line, photo, qr }

CertFieldKind _kindOf(String? s) => CertFieldKind.values.firstWhere(
      (k) => k.name == s,
      orElse: () => CertFieldKind.text,
    );

double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

String? _str(Object? v) => v is String ? v : null;

class CertField {
  static const _known = {
    'id', 'kind', 'text', 'text_ar', 'x', 'y', 'w', 'h', 'align', 'font', 'size', 'color', 'letter_spacing',
    'opacity', 'max_lines', 'shrink', 'visible', 'shape', 'src', 'sig_name', 'sig_title',
  };

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

  /// v2: a logo / signature box's own image (null → the design's default logo / signature of that language).
  final String? src;

  /// v2: the two caption lines drawn under a signature (signer's name, signer's title).
  final String? sigName;
  final String? sigTitle;

  /// Keys this app does not know (a newer server): sent back unchanged.
  final Map<String, dynamic> extra;

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
    this.src,
    this.sigName,
    this.sigTitle,
    this.extra = const {},
  });

  bool get isText => kind == CertFieldKind.text;
  bool get isImage => kind == CertFieldKind.signature || kind == CertFieldKind.logo;

  /// Photo and QR are squares of side [w].
  bool get isSquare => kind == CertFieldKind.photo || kind == CertFieldKind.qr;

  factory CertField.fromJson(Map<String, dynamic> j) => CertField(
        id: '${j['id'] ?? ''}',
        kind: _kindOf(_str(j['kind'])),
        text: _str(j['text']),
        textAr: _str(j['text_ar']),
        x: _num(j['x']) ?? 0,
        y: _num(j['y']) ?? 0,
        w: _num(j['w']) ?? 200,
        h: _num(j['h']) ?? 0,
        align: _str(j['align']) ?? 'center',
        font: _str(j['font']) ?? 'tajawal',
        size: _num(j['size']) ?? 24,
        color: _str(j['color']) ?? '#1C1C24',
        letterSpacing: _num(j['letter_spacing']) ?? 0,
        opacity: _num(j['opacity']) ?? 1,
        maxLines: _num(j['max_lines'])?.toInt() ?? 3,
        shrink: (j['shrink'] as bool?) ?? true,
        visible: (j['visible'] as bool?) ?? true,
        shape: _str(j['shape']) ?? 'circle',
        src: (_str(j['src']) ?? '').isEmpty ? null : _str(j['src']),
        sigName: _str(j['sig_name']),
        sigTitle: _str(j['sig_title']),
        extra: {
          for (final e in j.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      );

  Map<String, dynamic> toJson() => {
        ...extra,
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
        if (isImage && src != null) 'src': src,
        if (kind == CertFieldKind.signature && (sigName ?? '').isNotEmpty) 'sig_name': sigName,
        if (kind == CertFieldKind.signature && (sigTitle ?? '').isNotEmpty) 'sig_title': sigTitle,
      };

  CertField copyWith({
    String? id,
    String? text,
    bool clearText = false,
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
    String? src,
    bool clearSrc = false,
    String? sigName,
    String? sigTitle,
  }) =>
      CertField(
        id: id ?? this.id,
        kind: kind,
        text: clearText ? null : (text ?? this.text),
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
        src: clearSrc ? null : (src ?? this.src),
        sigName: sigName ?? this.sigName,
        sigTitle: sigTitle ?? this.sigTitle,
        extra: extra,
      );

  /// A full copy under another id (duplicate, a language's own copy).
  CertField copyWithNewId(String newId) => copyWith(id: newId);
}

/// The id of the invisible element saved into an EMPTY English layout: the server reads `fields_en: []` as "same
/// as the Arabic layout", so an English design whose elements were all deleted would print the Arabic layout.
/// The designer strips it again when it loads the design.
const String kCertBlankFieldId = '__blank__';

const CertField kCertBlankField =
    CertField(id: kCertBlankFieldId, kind: CertFieldKind.line, w: 4, h: 0, opacity: 0, visible: false, shrink: false);

/// How the English design gets one of its settings: from the Arabic design, its own value, or explicitly none.
enum CertInherit { same, own, none }

/// The state of an English image setting [en] next to the Arabic [ar]: null = same (follows the Arabic design),
/// "" = none, else its own (even when it happens to be the same image).
CertInherit certImageInherit(String? en, String? ar) {
  if (en == null) return CertInherit.same;
  if (en.isEmpty) return CertInherit.none;
  return CertInherit.own;
}

/// The theme of the English design: inherited only when unset.
CertInherit certThemeInherit(Map<String, dynamic>? en, Map<String, dynamic> ar) =>
    en == null ? CertInherit.same : CertInherit.own;

/// One language's design as the renderer draws it (the server's `design_spec`), every value resolved.
class CertLangView {
  final String lang;
  final String orientation;
  final String? backgroundUrl;
  final String backgroundKind;
  final String? signatureUrl;
  final String? logoUrl;
  final Map<String, dynamic> theme;
  final List<CertField> fields;

  const CertLangView({
    required this.lang,
    required this.orientation,
    this.backgroundUrl,
    this.backgroundKind = 'none',
    this.signatureUrl,
    this.logoUrl,
    this.theme = const {},
    this.fields = const [],
  });

  bool get landscape => orientation != 'portrait';
  double get logicalW => landscape ? kLogicalLong : kLogicalShort;
  double get logicalH => landscape ? kLogicalShort : kLogicalLong;
  bool get dark => theme['dark'] == true;
}

/// One language's STORED settings (English: raw `_en` values, null = inherit) — what one language's undo history
/// snapshots, so undo in one language never touches the other.
class CertLangSlice {
  final List<CertField> fields;
  final String? orientation;
  final String? backgroundUrl;
  final String? backgroundKind;
  final Map<String, dynamic>? theme;
  final String? signatureUrl;
  final String? logoUrl;

  const CertLangSlice({
    required this.fields,
    this.orientation,
    this.backgroundUrl,
    this.backgroundKind,
    this.theme,
    this.signatureUrl,
    this.logoUrl,
  });

  CertLangSlice withFields(List<CertField> f) => copyWith(fields: f);

  /// Every parameter but [fields] takes [_keep] to stay as it is (null is a value: "same as Arabic").
  CertLangSlice copyWith({
    List<CertField>? fields,
    Object? orientation = _keep,
    Object? backgroundUrl = _keep,
    Object? backgroundKind = _keep,
    Object? theme = _keep,
    Object? signatureUrl = _keep,
    Object? logoUrl = _keep,
  }) =>
      CertLangSlice(
        fields: fields ?? this.fields,
        orientation: identical(orientation, _keep) ? this.orientation : orientation as String?,
        backgroundUrl: identical(backgroundUrl, _keep) ? this.backgroundUrl : backgroundUrl as String?,
        backgroundKind: identical(backgroundKind, _keep) ? this.backgroundKind : backgroundKind as String?,
        theme: identical(theme, _keep) ? this.theme : theme as Map<String, dynamic>?,
        signatureUrl: identical(signatureUrl, _keep) ? this.signatureUrl : signatureUrl as String?,
        logoUrl: identical(logoUrl, _keep) ? this.logoUrl : logoUrl as String?,
      );
}

const Object _keep = Object();

class CertDesign {
  static const allLangs = ['ar', 'en'];

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
  final List<CertField> fields;     // Arabic layout
  final List<CertField> fieldsEn;   // English layout as stored ([] = same as Arabic)
  final bool canEdit;

  // v2
  final List<String> langs;
  final String? orientationEn;          // null = the Arabic orientation
  final String? backgroundUrlEn;        // null = the Arabic background, "" = none in English
  final String? backgroundKindEn;
  final Map<String, dynamic>? themeEn;  // null = the Arabic theme
  final String? signatureUrlEn;         // null = the Arabic default signature, "" = none
  final String? logoUrlEn;              // null = the Arabic default logo, "" = none

  /// Server keys this app does not model (apply_all, course_ids, updated_at, …): kept for [toJson].
  final Map<String, dynamic> extra;

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
    this.fieldsEn = const [],
    this.canEdit = true,
    this.langs = allLangs,
    this.orientationEn,
    this.backgroundUrlEn,
    this.backgroundKindEn,
    this.themeEn,
    this.signatureUrlEn,
    this.logoUrlEn,
    this.extra = const {},
  });

  bool get landscape => orientation != 'portrait';
  double get logicalW => landscape ? kLogicalLong : kLogicalShort;
  double get logicalH => landscape ? kLogicalShort : kLogicalLong;

  bool hasLang(String lang) => langs.contains(lang);

  /// The renderer's view of [lang] (the server's `design_spec`): English takes each `_en` value when set and its
  /// own layout when it has one.
  CertLangView view(String lang) {
    if (lang == 'ar') {
      return CertLangView(
        lang: 'ar',
        orientation: orientation,
        backgroundUrl: backgroundUrl,
        backgroundKind: backgroundKind,
        signatureUrl: signatureUrl,
        logoUrl: logoUrl,
        theme: theme,
        fields: fields,
      );
    }
    String? img(String? en, String? ar) => en == null ? ar : (en.isEmpty ? null : en);
    return CertLangView(
      lang: 'en',
      orientation: (orientationEn ?? '').isNotEmpty ? orientationEn! : orientation,
      backgroundUrl: img(backgroundUrlEn, backgroundUrl),
      backgroundKind: backgroundUrlEn == null
          ? backgroundKind
          : (backgroundKindEn ?? (backgroundUrlEn!.isEmpty ? 'none' : 'upload')),
      signatureUrl: img(signatureUrlEn, signatureUrl),
      logoUrl: img(logoUrlEn, logoUrl),
      theme: themeEn ?? theme,
      fields: fieldsEn.isNotEmpty ? fieldsEn : fields,
    );
  }

  static List<String> _langsOf(Object? raw) {
    final list = raw is List ? raw.map((e) => '$e').toList() : const <String>[];
    final out = [for (final l in allLangs) if (list.contains(l)) l];
    return out.isEmpty ? allLangs : out;
  }

  static const _known = {
    'id', 'name', 'owner_id', 'org_id', 'orientation', 'background_url', 'background_kind', 'signature_url',
    'logo_url', 'theme', 'fields', 'fields_en', 'can_edit', 'langs', 'orientation_en', 'background_url_en',
    'background_kind_en', 'theme_en', 'signature_url_en', 'logo_url_en',
  };

  static List<CertField> _fieldsOf(Object? raw) => ((raw as List?) ?? const [])
      .whereType<Map>()
      .map((e) => CertField.fromJson(Map<String, dynamic>.from(e)))
      .toList();

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
        fields: _fieldsOf(j['fields']),
        fieldsEn: _fieldsOf(j['fields_en']),
        canEdit: (j['can_edit'] as bool?) ?? false,
        langs: _langsOf(j['langs']),
        orientationEn: _str(j['orientation_en']),
        backgroundUrlEn: _str(j['background_url_en']),
        backgroundKindEn: _str(j['background_kind_en']),
        themeEn: j['theme_en'] is Map ? Map<String, dynamic>.from(j['theme_en'] as Map) : null,
        signatureUrlEn: _str(j['signature_url_en']),
        logoUrlEn: _str(j['logo_url_en']),
        extra: {
          for (final e in j.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      );

  /// The design in the server's answer shape (round-trips [CertDesign.fromJson]).
  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'name': name,
        'owner_id': ownerId,
        'org_id': orgId,
        'orientation': orientation,
        'background_url': backgroundUrl,
        'background_kind': backgroundKind,
        'signature_url': signatureUrl,
        'logo_url': logoUrl,
        'theme': theme,
        'fields': [for (final f in fields) f.toJson()],
        'fields_en': [for (final f in fieldsEn) f.toJson()],
        'can_edit': canEdit,
        'langs': langs,
        'orientation_en': orientationEn,
        'background_url_en': backgroundUrlEn,
        'background_kind_en': backgroundKindEn,
        'theme_en': themeEn,
        'signature_url_en': signatureUrlEn,
        'logo_url_en': logoUrlEn,
      };

  /// The stored settings of one language ([CertLangSlice]).
  CertLangSlice slice(String lang) => lang == 'ar'
      ? CertLangSlice(
          fields: fields,
          orientation: orientation,
          backgroundUrl: backgroundUrl,
          backgroundKind: backgroundKind,
          theme: theme,
          signatureUrl: signatureUrl,
          logoUrl: logoUrl,
        )
      : CertLangSlice(
          fields: fieldsEn,
          orientation: orientationEn,
          backgroundUrl: backgroundUrlEn,
          backgroundKind: backgroundKindEn,
          theme: themeEn,
          signatureUrl: signatureUrlEn,
          logoUrl: logoUrlEn,
        );

  /// Puts one language's stored settings back; the other language is left exactly as it is.
  CertDesign withSlice(String lang, CertLangSlice s) => lang == 'ar'
      ? copyWith(
          fields: s.fields,
          orientation: s.orientation ?? orientation,
          backgroundUrl: s.backgroundUrl,
          clearBackground: s.backgroundUrl == null,
          backgroundKind: s.backgroundUrl == null ? 'none' : (s.backgroundKind ?? 'upload'),
          theme: s.theme ?? const {},
          signatureUrl: s.signatureUrl,
          clearSignature: s.signatureUrl == null,
          logoUrl: s.logoUrl,
          clearLogo: s.logoUrl == null,
        )
      : copyWith(
          fieldsEn: s.fields,
          orientationEn: s.orientation,
          backgroundUrlEn: s.backgroundUrl,
          backgroundKindEn: s.backgroundKind,
          themeEn: s.theme,
          signatureUrlEn: s.signatureUrl,
          logoUrlEn: s.logoUrl,
        );

  /// The `_en` parameters take [_keep] to stay as they are; null is a value there ("same as Arabic").
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
    List<CertField>? fieldsEn,
    bool? canEdit,
    List<String>? langs,
    Object? orientationEn = _keep,
    Object? backgroundUrlEn = _keep,
    Object? backgroundKindEn = _keep,
    Object? themeEn = _keep,
    Object? signatureUrlEn = _keep,
    Object? logoUrlEn = _keep,
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
        fieldsEn: fieldsEn ?? this.fieldsEn,
        canEdit: canEdit ?? this.canEdit,
        langs: langs ?? this.langs,
        orientationEn: identical(orientationEn, _keep) ? this.orientationEn : orientationEn as String?,
        backgroundUrlEn: identical(backgroundUrlEn, _keep) ? this.backgroundUrlEn : backgroundUrlEn as String?,
        backgroundKindEn: identical(backgroundKindEn, _keep) ? this.backgroundKindEn : backgroundKindEn as String?,
        themeEn: identical(themeEn, _keep) ? this.themeEn : themeEn as Map<String, dynamic>?,
        signatureUrlEn: identical(signatureUrlEn, _keep) ? this.signatureUrlEn : signatureUrlEn as String?,
        logoUrlEn: identical(logoUrlEn, _keep) ? this.logoUrlEn : logoUrlEn as String?,
        extra: extra,
      );
}
