// lib/design/export/docx_fonts.dart
//
// Font embedding for the Word writers (ECMA-376 Part 1 §17.8.1 "Font Embedding"): every catalog font a document
// uses travels inside the .docx, so it prints the same on a computer that does not have it.
//
//   word/fonts/fontN.odttf          the TTF, its first 32 bytes XOR the entry's font key (docxObfuscateFont)
//   word/fontTable.xml              <w:font w:name="…"> with <w:embedRegular> / <w:embedBold r:id w:fontKey>
//   word/_rels/fontTable.xml.rels   the font parts
//   word/settings.xml               <w:embedTrueTypeFonts/>
//
// Word finds an embedded font by the name inside the file (name ID 1), so a run names exactly that ([DocxFonts.rPr]):
//   * the bold file is the same family with a Bold style (Amiri, Scheherazade New, IBM Plex Sans Arabic):
//     one entry, embedRegular + embedBold, bold runs say <w:b/>;
//   * the bold file has its own family name (Tajawal Medium → Tajawal Bold): two entries, bold runs name the
//     bold file (with <w:b/> only when that file IS the bold style);
//   * both files claim the same family AND style (static instances named "Cairo / Regular" at weights 500 and 800:
//     Cairo, El Messiri, Reem Kufi, Markazi Text, Playfair Display, Libre Baskerville): one entry, embedRegular +
//     embedBold — Word picks the bold slot for <w:b/> runs by the files' weight class;
//   * an italic file (Cormorant Italic, Playfair Italic) goes in the family's embedItalic slot, its runs say <w:i/>;
//   * one file only (Cinzel, Great Vibes, …): bold runs print the same file without <w:b/>, like the PDF (the
//     catalog never synthesizes a bold);
//   * a Latin-only font sets Arabic (w:cs) in its Arabic fallback (Amiri / Amiri Bold, the certificate's rule),
//     which is embedded too.
// A font whose OS/2 fsType forbids embedding (restricted / bitmap only) is named, not embedded (none in the
// catalog today: Bahij allows editable embedding, the rest are OFL).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../export/table_export_model.dart' show xmlEsc;
import 'export_fonts.dart';
import 'ttf_tools.dart';

/// The files of one catalog font as the Word writer gets them (pure data: may cross an isolate).
class DocxFontFiles {
  const DocxFontFiles({required this.id, required this.regularKey, required this.regular, this.boldKey, this.bold, this.officeName = '', this.csId});
  final String id;

  /// A stable key per file (the asset path): a file used by two fonts is embedded once.
  final String regularKey;
  final Uint8List regular;
  final String? boldKey;
  final Uint8List? bold;

  /// The name used when the font cannot be embedded.
  final String officeName;

  /// The font that sets this font's Arabic (a Latin-only font), or null.
  final String? csId;
}

class _Entry {
  _Entry(this.name);
  final String name;
  String? regularKey, boldKey, italicKey;
}

/// How runs name one catalog font: (name, bold flag) for regular and bold text.
class _Face {
  const _Face(this.name, this.boldName, this.boldFlag, {this.italic = false});
  final String name, boldName;
  final bool boldFlag;

  /// The file is an italic style (Cormorant Italic, Playfair Italic): embedded in the italic slot, runs say `<w:i/>`.
  final bool italic;
}

/// The embedded fonts of one Word document.
class DocxFonts {
  DocxFonts._(this._faces, this._entries, this._files, this._cs);

  /// Nothing embedded: runs keep the writer's own default (Arial).
  static final empty = DocxFonts._(const {}, const [], const {}, const {});

  final Map<String, _Face> _faces;
  final List<_Entry> _entries;
  final Map<String, Uint8List> _files;
  final Map<String, String> _cs;

  bool get isEmpty => _faces.isEmpty;

  bool has(String id) => _faces.containsKey(id);

  /// Builds the entries of [fonts] (pure).
  factory DocxFonts.build(Iterable<DocxFontFiles> fonts) {
    final faces = <String, _Face>{};
    final entries = <String, _Entry>{};
    final files = <String, Uint8List>{};
    final cs = <String, String>{};
    _Entry entry(String name) => entries.putIfAbsent(name, () => _Entry(name));
    for (final f in fonts) {
      final r = ttfInfo(f.regular);
      if (r == null || !r.embeddable || r.family.isEmpty) {
        final n = f.officeName.isEmpty ? (r?.cleanFamily ?? 'Arial') : f.officeName;
        faces[f.id] = _Face(n, n, true);
        continue;
      }
      files[f.regularKey] = f.regular;
      final b = f.bold == null || f.boldKey == null || f.boldKey == f.regularKey ? null : ttfInfo(f.bold!);
      final er = entry(r.family);
      final italic = r.isItalic && !r.isBold;
      if (italic) {
        er.italicKey ??= f.regularKey;
      } else {
        er.regularKey ??= f.regularKey;
      }
      if (b == null || !b.embeddable) {
        faces[f.id] = _Face(r.family, r.family, false, italic: italic);
      } else {
        files[f.boldKey!] = f.bold!;
        if (b.family == r.family) {
          er.boldKey ??= f.boldKey;
          faces[f.id] = _Face(r.family, r.family, true, italic: italic);
        } else {
          final eb = entry(b.family);
          if (b.isBold) {
            eb.boldKey ??= f.boldKey;
          } else {
            eb.regularKey ??= f.boldKey;
          }
          faces[f.id] = _Face(r.family, b.family, b.isBold, italic: italic);
        }
      }
      if (f.csId != null) cs[f.id] = f.csId!;
    }
    return DocxFonts._(faces, entries.values.toList(), files, cs);
  }

  /// `<w:rFonts …/>` plus the bold elements of a run set in [id] (null = not embedded: [fallbackName]).
  /// [bold] = the run is bold text.
  String rPr(String? id, {bool bold = false, String fallbackName = 'Arial'}) {
    final face = id == null ? null : _faces[id];
    if (face == null) {
      return '<w:rFonts w:ascii="${xmlEsc(fallbackName)}" w:hAnsi="${xmlEsc(fallbackName)}" w:cs="${xmlEsc(fallbackName)}"/>${bold ? '<w:b/><w:bCs/>' : ''}';
    }
    final name = bold ? face.boldName : face.name;
    final csFace = _cs[id] == null ? null : _faces[_cs[id]];
    final csName = csFace == null ? name : (bold ? csFace.boldName : csFace.name);
    final flag = bold && face.boldFlag;
    final csFlag = bold && (csFace?.boldFlag ?? face.boldFlag);
    return '<w:rFonts w:ascii="${xmlEsc(name)}" w:hAnsi="${xmlEsc(name)}" w:eastAsia="${xmlEsc(name)}" w:cs="${xmlEsc(csName)}"/>'
        '${flag ? '<w:b/>' : ''}${csFlag ? '<w:bCs/>' : ''}${face.italic ? '<w:i/>' : ''}';
  }

  /// The parts to add to the package (path → bytes), plus the font table, its relationships and the settings.
  Map<String, List<int>> parts() {
    if (_entries.isEmpty) return {};
    final out = <String, List<int>>{};
    final rels = <String>[];
    final fontXml = StringBuffer();
    final partOf = <String, (String, String)>{};
    (String, String) part(String key) => partOf.putIfAbsent(key, () {
          final n = partOf.length + 1;
          final guid = docxFontKey(key);
          out['word/fonts/font$n.odttf'] = docxObfuscateFont(_files[key]!, guid);
          rels.add('<Relationship Id="rFont$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/font" Target="fonts/font$n.odttf"/>');
          return ('rFont$n', guid);
        });
    for (final e in _entries) {
      fontXml.write('<w:font w:name="${xmlEsc(e.name)}"><w:charset w:val="00"/><w:family w:val="auto"/><w:pitch w:val="variable"/>');
      if (e.regularKey != null) {
        final (rid, key) = part(e.regularKey!);
        fontXml.write('<w:embedRegular r:id="$rid" w:fontKey="$key"/>');
      }
      if (e.boldKey != null) {
        final (rid, key) = part(e.boldKey!);
        fontXml.write('<w:embedBold r:id="$rid" w:fontKey="$key"/>');
      }
      if (e.italicKey != null) {
        final (rid, key) = part(e.italicKey!);
        fontXml.write('<w:embedItalic r:id="$rid" w:fontKey="$key"/>');
      }
      fontXml.write('</w:font>');
    }
    out['word/fontTable.xml'] = utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '$fontXml</w:fonts>');
    out['word/_rels/fontTable.xml.rels'] = utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${rels.join()}</Relationships>');
    out['word/settings.xml'] = utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:embedTrueTypeFonts/></w:settings>');
    return out;
  }

  /// The content-type entries the parts need.
  String get contentTypes => _entries.isEmpty
      ? ''
      : '<Default Extension="odttf" ContentType="application/vnd.openxmlformats-officedocument.obfuscatedFont"/>'
          '<Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>'
          '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>';

  /// The document relationships the parts need.
  String get documentRels => _entries.isEmpty
      ? ''
      : '<Relationship Id="rFontTable" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/>'
          '<Relationship Id="rSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>';
}

/// Loads the files of [ids] (and the Arabic fallback of each Latin-only one) for [DocxFonts.build].
Future<List<DocxFontFiles>> loadDocxFontFiles(Iterable<String> ids) async {
  final out = <String, DocxFontFiles>{};
  Future<void> add(String id) async {
    final f = ExportFonts.byId(id);
    if (out.containsKey(f.id)) return;
    final r = await ExportFonts.bytes(f.regularAsset);
    final b = f.hasBold ? await ExportFonts.bytes(f.boldAsset) : null;
    out[f.id] = DocxFontFiles(id: f.id, regularKey: f.regularAsset, regular: r, boldKey: f.hasBold ? f.boldAsset : null, bold: b, officeName: f.officeName, csId: f.arabicFallbackId);
    if (f.arabicFallbackId != null) await add(f.arabicFallbackId!);
  }

  for (final id in ids) {
    if (id.isNotEmpty) await add(id);
  }
  return out.values.toList();
}
