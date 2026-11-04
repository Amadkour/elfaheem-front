// lib/design/export/export_fonts.dart
//
// THE font catalog of the exports (PDF · Word · Excel, the Export Studio and the export designers). It is the
// certificate studio's catalog — `kCertFonts`, whose keys are the server renderer's `FONT_KEYS` — plus the two
// families older export designs already name ('bahij', 'plex'). There is no second list of fonts: an id here is a
// certificate font key, its label is the certificate font's label, its file is the file the server renders with.
//
//   ExportFonts.catalog          every selectable font (ExportFont: id, label, regular / bold files, Office name)
//   ExportFonts.byId(id)         the font of an id ('' / unknown → Tajawal)
//   ExportFonts.bytes(asset)     the file's bytes, loaded on first use and cached (web: one request per file)
//   ExportFonts.pdf(ids)         the PDF font set: Arabic presentation forms completed (ttf_tools.ttfForPdf) and the
//                                Arabic stand-in of a font that cannot join Arabic in a PDF
//   ExportFonts.ensurePreview    registers a font for the live previews (FontLoader, family 'xf_<id>'): only the
//                                fonts somebody shows are loaded; nothing at start-up
//   ExportFonts.ensureCertFamilies  registers the certificate studio's own families ('CertCinzel', …) — those files
//                                are plain assets now, not pubspec `fonts:` (7.1: the web build no longer downloads
//                                6 MB of certificate fonts at start-up); the studio engine calls it when it opens
//
// Excel cannot embed a font: the sheet names it ([ExportFont.officeName]) and the reader's Excel draws it when the
// font is installed, else a similar one (the flow says so in a hint). Word embeds the files (docx_fonts.dart).
library;


import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart' show AppConfig, translate;
import '../../features/teacher/certificates/designer/certificate_design_models.dart' show CertFont, kCertFonts;
import '../../core/display/lazy_fonts.dart';
import 'ttf_tools.dart';

/// The file of each certificate font key — the server renderer's FONT_CATALOG (`../back/services/
/// certificate_design_renderer.py`), checked against it by test/export/export_fonts_test.dart.
const certFontFiles = <String, String>{
  'cinzel': 'Cinzel-SemiBold.ttf',
  'great_vibes': 'GreatVibes-Regular.ttf',
  'cormorant_italic': 'CormorantGaramond-MediumItalic.ttf',
  'cormorant': 'CormorantGaramond-SemiBold.ttf',
  'playfair': 'PlayfairDisplay-Regular.ttf',
  'playfair_bold': 'PlayfairDisplay-Bold.ttf',
  'playfair_italic': 'PlayfairDisplay-Italic.ttf',
  'eb_garamond': 'EBGaramond-Regular.ttf',
  'pinyon_script': 'PinyonScript-Regular.ttf',
  'baskerville': 'LibreBaskerville-Regular.ttf',
  'baskerville_bold': 'LibreBaskerville-Bold.ttf',
  'tajawal': 'Tajawal-Regular.ttf',
  'tajawal_medium': 'Tajawal-Medium.ttf',
  'tajawal_bold': 'Tajawal-Bold.ttf',
  'amiri': 'Amiri-Regular.ttf',
  'amiri_bold': 'Amiri-Bold.ttf',
  'aref_ruqaa': 'ArefRuqaa-Regular.ttf',
  'aref_ruqaa_bold': 'ArefRuqaa-Bold.ttf',
  'scheherazade': 'ScheherazadeNew-Regular.ttf',
  'scheherazade_bold': 'ScheherazadeNew-Bold.ttf',
  'reem_kufi': 'ReemKufi-Medium.ttf',
  'reem_kufi_bold': 'ReemKufi-Bold.ttf',
  'el_messiri': 'ElMessiri-Medium.ttf',
  'el_messiri_bold': 'ElMessiri-Bold.ttf',
  'cairo': 'Cairo-Medium.ttf',
  'cairo_bold': 'Cairo-ExtraBold.ttf',
  'markazi': 'MarkaziText-Medium.ttf',
  'markazi_bold': 'MarkaziText-Bold.ttf',
};

/// The asset of a certificate font key. Tajawal Regular is the app's own file (assets/fonts/), the rest are in
/// assets/fonts/cert/ (the same files as `services/certificate_fonts` on the server).
String certFontAsset(String key) {
  final file = certFontFiles[key] ?? certFontFiles['tajawal']!;
  return key == 'tajawal' ? 'assets/fonts/$file' : 'assets/fonts/cert/$file';
}

/// The family Excel / Word name a font by when the reader has it installed (the typographic family, as Google
/// Fonts installs it), per certificate key family (the key without _bold / _medium / _italic).
const _officeNames = <String, String>{
  'cinzel': 'Cinzel',
  'great_vibes': 'Great Vibes',
  'cormorant': 'Cormorant Garamond',
  'playfair': 'Playfair Display',
  'eb_garamond': 'EB Garamond',
  'pinyon_script': 'Pinyon Script',
  'baskerville': 'Libre Baskerville',
  'tajawal': 'Tajawal',
  'amiri': 'Amiri',
  'aref_ruqaa': 'Aref Ruqaa',
  'scheherazade': 'Scheherazade New',
  'reem_kufi': 'Reem Kufi',
  'el_messiri': 'El Messiri',
  'cairo': 'Cairo',
  'markazi': 'Markazi Text',
  'bahij': 'Bahij TheSansArabic',
  'plex': 'IBM Plex Sans Arabic',
};

/// In a PDF, the Arabic of a font that cannot join Arabic there (ttf_tools.ttfForPdf) is drawn with this font —
/// the closest complete one. Latin-only fonts use the certificate's own fallback (Amiri / Amiri Bold, like the
/// server renderer).
const _pdfArabicStandIn = <String, String>{
  'reem_kufi': 'cairo',
  'reem_kufi_bold': 'cairo_bold',
  'aref_ruqaa': 'amiri',
  'aref_ruqaa_bold': 'amiri_bold',
};

String _baseKey(String id) => id.replaceAll(RegExp(r'_(bold|medium|italic)$'), '');

/// One selectable export font.
@immutable
class ExportFont {
  const ExportFont({
    required this.id,
    required this.regularAsset,
    required this.boldAsset,
    required this.labelKey,
    required this.labelEn,
    required this.labelAr,
    required this.arabic,
    this.arabicFallbackId,
  });

  /// The certificate font key ('bahij' / 'plex': the two export-only families).
  final String id;
  final String regularAsset, boldAsset;

  /// The certificate studio's label key (`cert_font_*`), with the texts used when the key is missing.
  final String labelKey, labelEn, labelAr;

  /// Draws Arabic with its own letters (else Arabic text uses [arabicFallbackId]).
  final bool arabic;

  /// The font that draws Arabic text set in this (Latin-only) font: the certificate's fallback.
  final String? arabicFallbackId;

  String get label {
    final v = translate(labelKey);
    return v == labelKey ? (AppConfig.lang == 'ar' ? labelAr : labelEn) : v;
  }

  /// Bold text has its own file (else the regular file prints bold text too, never a synthesized bold).
  bool get hasBold => boldAsset != regularAsset;

  /// The family name Excel (and Word, for a font it does not embed) asks for.
  String get officeName => _officeNames[_baseKey(id)] ?? _officeNames['tajawal']!;

  bool get officeBold => id.endsWith('_bold');
  bool get officeItalic => id.endsWith('_italic');

  /// The preview family (FontLoader) — see [ExportFonts.ensurePreview].
  String get previewFamily => 'xf_$id';

  /// The font that draws this font's Arabic in a PDF (a Latin-only font's fallback, or the stand-in of a font whose
  /// Arabic cannot be joined in a PDF — the same answer as [ExportFonts.pdfArabicStandIn], known without loading).
  String? get pdfArabicStandInId => arabicFallbackId ?? _pdfArabicStandIn[id];

  /// The preview fallback chain: the Arabic stand-in, then IBM Plex Sans Arabic.
  List<String> get previewFallback => [
        if (arabicFallbackId != null) 'xf_$arabicFallbackId',
        if (_pdfArabicStandIn[id] != null) 'xf_${_pdfArabicStandIn[id]}',
        'PaperPlex',
      ];
}

ExportFont _fromCert(CertFont c) {
  String? bold;
  if (c.key.endsWith('_bold')) {
    bold = c.key;
  } else {
    final sibling = '${c.key.replaceAll(RegExp(r'_medium$'), '')}_bold';
    if (certFontFiles.containsKey(sibling) && !c.key.endsWith('_italic')) bold = sibling;
  }
  final fallback = c.arabicFallback == null ? null : (c.arabicFallback!.endsWith('Bold') ? 'amiri_bold' : 'amiri');
  return ExportFont(
    id: c.key,
    regularAsset: certFontAsset(c.key),
    boldAsset: certFontAsset(bold ?? c.key),
    labelKey: c.labelKey,
    labelEn: c.key,
    labelAr: c.key,
    arabic: c.arabic,
    arabicFallbackId: fallback,
  );
}

/// The catalog, its loader and the caches. Static: one per app run (the bytes of a file are loaded once).
abstract final class ExportFonts {
  static const defaultId = 'tajawal';

  /// Every selectable font: the certificate studio's list in its order, then the two export-only families.
  static final List<ExportFont> catalog = [
    for (final c in kCertFonts) _fromCert(c),
    const ExportFont(
      id: 'bahij',
      regularAsset: 'assets/fonts/Bahij_TheSansArabic-Bold.ttf',
      boldAsset: 'assets/fonts/Bahij_TheSansArabic-Bold.ttf',
      labelKey: 'export_font_bahij',
      labelEn: 'Bahij',
      labelAr: 'بهيج',
      arabic: true,
    ),
    const ExportFont(
      id: 'plex',
      regularAsset: 'assets/fonts/plex/IBMPlexSansArabic-Regular.ttf',
      boldAsset: 'assets/fonts/plex/IBMPlexSansArabic-Bold.ttf',
      labelKey: 'export_font_plex',
      labelEn: 'IBM Plex Sans Arabic',
      labelAr: 'IBM Plex عربي',
      arabic: true,
    ),
  ];

  static final Map<String, ExportFont> _byId = {for (final f in catalog) f.id: f};

  static List<String> get ids => [for (final f in catalog) f.id];

  static bool has(String? id) => id != null && _byId.containsKey(id);

  static ExportFont byId(String? id) => _byId[id] ?? _byId[defaultId]!;

  /// The catalog with the Arabic-capable fonts first (what an Arabic file offers first).
  static List<ExportFont> sortedFor(String lang) =>
      lang == 'ar' ? [...catalog.where((f) => f.arabic), ...catalog.where((f) => !f.arabic)] : catalog;

  // ── bytes ──────────────────────────────────────────────────────────────────

  /// Reads one asset (tests swap it for a file read).
  static Future<ByteData> Function(String asset) loader = rootBundle.load;

  static final Map<String, Future<Uint8List>> _bytes = {};

  /// [asset]'s bytes, loaded once.
  static Future<Uint8List> bytes(String asset) => _bytes[asset] ??= loader(asset).then((b) => Uint8List.sublistView(b)).catchError((Object e) {
        _bytes.remove(asset);
        throw e;
      });

  /// How many font files have been loaded so far (tests: nothing at start-up, one file per font used).
  @visibleForTesting
  static int get loadedFiles => _bytes.length;

  @visibleForTesting
  static void resetCaches() {
    _bytes.clear();
    _pdf.clear();
    _preview.clear();
    _cert = null;
  }

  // ── PDF ────────────────────────────────────────────────────────────────────

  static final Map<String, Future<(Uint8List, bool)>> _pdf = {};

  /// [asset] as package:pdf gets it (ttf_tools.ttfForPdf) and whether it draws its own Arabic.
  static Future<(Uint8List, bool)> pdfFile(String asset) => _pdf[asset] ??= bytes(asset).then(ttfForPdf);

  /// The font that draws [f]'s Arabic in a PDF, or null when [f] draws it itself.
  static Future<String?> pdfArabicStandIn(ExportFont f) async {
    if (f.arabicFallbackId != null) return f.arabicFallbackId;
    final (_, ok) = await pdfFile(f.regularAsset);
    return ok ? null : (_pdfArabicStandIn[f.id] ?? 'amiri');
  }

  // ── previews ───────────────────────────────────────────────────────────────

  static final Map<String, Future<void>> _preview = {};

  /// Bumps when a preview font has been registered (painters that cache text can listen).
  static final ValueNotifier<int> version = ValueNotifier(0);

  /// Registers [id]'s files as the family `xf_<id>` (and its Arabic stand-in) for the previews: a font whose Arabic
  /// a PDF cannot join shows the stand-in in the preview too, so the preview is the file. Safe to call repeatedly;
  /// failures leave the fallback font.
  static Future<void> ensurePreview(String id) {
    final f = byId(id);
    return _preview[f.id] ??= () async {
      // Flutter shapes Arabic itself (the presentation forms a PDF needs change nothing on screen): the raw file,
      // except for a font whose Arabic a PDF hands to a stand-in — its PDF copy, without Arabic, so the preview
      // shows the stand-in too
      Future<ByteData> file(String asset) => _pdfArabicStandIn.containsKey(f.id)
          ? pdfFile(asset).then((x) => ByteData.sublistView(x.$1))
          : bytes(asset).then((b) => ByteData.sublistView(b));
      await LazyFonts.ensure('PaperPlex'); // the preview's last fallback (see previewFallback)
      final loader = FontLoader(f.previewFamily);
      loader.addFont(file(f.regularAsset));
      if (f.hasBold) loader.addFont(file(f.boldAsset));
      await loader.load();
      final standIn = f.arabicFallbackId ?? await pdfArabicStandIn(f);
      if (standIn != null && standIn != f.id) await ensurePreview(standIn);
      version.value++;
    }()
        .catchError((Object e) {
      _preview.remove(f.id);
      debugPrint('[ExportFonts] $id preview failed: $e');
    });
  }

  /// [ensurePreview] for every font (the font pickers draw each option in its own font).
  static Future<void> ensureAllPreviews() => Future.wait([for (final f in catalog) ensurePreview(f.id)]);

  static Future<void>? _cert;

  /// Registers the certificate studio's families (`CertCinzel`, `CertAmiriBold`, …) from their asset files, once.
  /// The app's own 'tajawal' family stays a pubspec font.
  static Future<void> ensureCertFamilies() => _cert ??= () async {
        await Future.wait([
          LazyFonts.ensure('tajawal'), // the certificate studio draws the app's own 'tajawal' family
          for (final c in kCertFonts)
            if (c.family != 'tajawal')
              (FontLoader(c.family)..addFont(bytes(certFontAsset(c.key)).then((b) => ByteData.sublistView(b)))).load().catchError((Object e) {
                debugPrint('[ExportFonts] ${c.family} failed: $e');
              }),
        ]);
        version.value++;
      }();
}
