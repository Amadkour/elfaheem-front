// lib/design/export/ttf_tools.dart
//
// Pure TrueType helpers for the export writers (no Flutter, so they also run in an isolate and in plain tests):
//
//   ttfInfo                    the names Word matches a font by (name IDs 1 / 2 / 16), the embedding permission
//                              (OS/2 fsType) and whether the font draws Arabic
//   ttfForPdf                  a copy of an Arabic font whose cmap ALSO maps the Arabic presentation forms
//                              (U+FB50–FDFF, U+FE70–FEFC) to the font's own contextual glyphs, read from its GSUB
//                              (isol / init / medi / fina single substitutions, the lam-alef ligatures). package:pdf
//                              shapes Arabic by turning letters into presentation forms and draws them through the
//                              cmap: Scheherazade New had 30 of them, Cairo / Tajawal / El Messiri / Markazi miss a few
//                              dozen, so their Arabic printed as boxes. Fonts whose letters cannot be completed this way
//                              (Reem Kufi, Aref Ruqaa: dotless shapes + dots) lose their Arabic mappings instead, so a
//                              fallback font draws all of their Arabic text (see [ttfForPdf]).
//   docxObfuscateFont          the ECMA-376 §17.8.1 obfuscation of an embedded Word font (.odttf)
//
// The presentation forms are found through the bidi package's Unicode decomposition data (FE8D → isolated 0627),
// so there is no hand-written letter table here.
library;

import 'dart:typed_data';

import 'package:bidi/bidi.dart' as bidi;

/// What the export writers need to know about one font file.
class TtfInfo {
  const TtfInfo({required this.family, required this.subfamily, required this.typoFamily, required this.fsType, required this.arabic, required this.presentationForms});

  /// Name ID 1 (the legacy family Word and Excel match by), 2 (Regular / Bold / Italic …), 16 (the typographic
  /// family, without the weight; empty when the font has none).
  final String family, subfamily, typoFamily;

  /// OS/2 fsType: 0 = installable; bit 1 (2) = restricted license (never embed); 4 = preview & print;
  /// 8 = editable; bit 9 (0x200) = no subsetting; bit 8 (0x100) = bitmap embedding only.
  final int fsType;

  /// Draws Arabic letters (U+0628 in the cmap) / how many Arabic presentation forms the cmap maps.
  final bool arabic;
  final int presentationForms;

  /// May be embedded in a document (Word): not restricted, not bitmap-only.
  bool get embeddable => fsType & 0x0002 == 0 && fsType & 0x0100 == 0;

  /// The family without the weight: the typographic family when present, else [family].
  String get cleanFamily => typoFamily.isNotEmpty ? typoFamily : family;

  bool get isBold => subfamily.toLowerCase().contains('bold');
  bool get isItalic => subfamily.toLowerCase().contains('italic');
}

class _Font {
  _Font(this.bytes) : data = ByteData.sublistView(bytes) {
    final n = data.getUint16(4);
    for (var i = 0; i < n; i++) {
      final at = 12 + 16 * i;
      final tag = String.fromCharCodes(bytes.sublist(at, at + 4));
      tables[tag] = (data.getUint32(at + 8), data.getUint32(at + 12));
    }
  }

  final Uint8List bytes;
  final ByteData data;
  final Map<String, (int, int)> tables = {};

  int u16(int at) => data.getUint16(at);
  int i16(int at) => data.getInt16(at);
  int u32(int at) => data.getUint32(at);

  Uint8List table(String tag) {
    final t = tables[tag]!;
    return Uint8List.sublistView(bytes, t.$1, t.$1 + t.$2);
  }

  Map<int, String> names() {
    final t = tables['name'];
    if (t == null) return {};
    final base = t.$1, count = u16(base + 2), strings = base + u16(base + 4);
    final win = <int, String>{}, mac = <int, String>{};
    for (var i = 0; i < count; i++) {
      final r = base + 6 + 12 * i;
      final platform = u16(r), lang = u16(r + 4), id = u16(r + 6), len = u16(r + 8), off = strings + u16(r + 10);
      if (off + len > bytes.length) continue;
      if (platform == 3 && lang == 0x409) {
        final units = [for (var k = 0; k + 1 < len; k += 2) u16(off + k)];
        win[id] = String.fromCharCodes(units);
      } else if (platform == 1 && lang == 0) {
        mac[id] = String.fromCharCodes(bytes.sublist(off, off + len));
      }
    }
    return {...mac, ...win};
  }

  /// code point → glyph, from the Windows Unicode subtables (3,10 format 12 and 3,1 format 4).
  Map<int, int> cmap() {
    final t = tables['cmap'];
    if (t == null) return {};
    final base = t.$1, n = u16(base + 2);
    final out = <int, int>{};
    for (var i = 0; i < n; i++) {
      final platform = u16(base + 4 + 8 * i), enc = u16(base + 6 + 8 * i), at = base + u32(base + 8 + 8 * i);
      final format = u16(at);
      if (platform == 3 && enc == 1 && format == 4) {
        final seg = u16(at + 6) ~/ 2;
        final ends = at + 14, starts = ends + seg * 2 + 2, deltas = starts + seg * 2, ranges = deltas + seg * 2;
        for (var s = 0; s < seg; s++) {
          final end = u16(ends + s * 2), start = u16(starts + s * 2), delta = u16(deltas + s * 2), ro = u16(ranges + s * 2);
          if (start == 0xFFFF) continue;
          for (var c = start; c <= end; c++) {
            int g;
            if (ro == 0) {
              g = (c + delta) & 0xFFFF;
            } else {
              final ga = ranges + s * 2 + ro + (c - start) * 2;
              if (ga + 2 > bytes.length) continue;
              g = u16(ga);
              if (g != 0) g = (g + delta) & 0xFFFF;
            }
            if (g != 0) out.putIfAbsent(c, () => g);
          }
        }
      } else if (platform == 3 && enc == 10 && format == 12) {
        final groups = u32(at + 12);
        for (var k = 0; k < groups; k++) {
          final g = at + 16 + 12 * k;
          final start = u32(g), end = u32(g + 4), gid = u32(g + 8);
          for (var c = start; c <= end; c++) {
            out[c] = gid + c - start;
          }
        }
      }
    }
    return out;
  }
}

const _pfRanges = [(0xFB50, 0xFDFF), (0xFE70, 0xFEFC)];

bool _isPresentationForm(int c) => _pfRanges.any((r) => c >= r.$1 && c <= r.$2);

/// The names, permission and Arabic coverage of [ttf] (null when it is not a TrueType / OpenType file).
TtfInfo? ttfInfo(Uint8List ttf) {
  try {
    final f = _Font(ttf);
    final n = f.names();
    final os2 = f.tables['OS/2'];
    final cmap = f.cmap();
    return TtfInfo(
      family: n[1] ?? '',
      subfamily: n[2] ?? '',
      typoFamily: n[16] ?? '',
      fsType: os2 == null ? 0 : f.u16(os2.$1 + 8),
      arabic: cmap.containsKey(0x0628),
      presentationForms: cmap.keys.where(_isPresentationForm).length,
    );
  } catch (_) {
    return null;
  }
}

/// The font's Unicode cmap (code point → glyph), as package:pdf reads it from a font made by [ttfForPdf].
Map<int, int> ttfCmap(Uint8List ttf) {
  try {
    return _Font(ttf).cmap();
  } catch (_) {
    return const {};
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  GSUB → presentation forms
// ═════════════════════════════════════════════════════════════════════════════

class _Gsub {
  _Gsub(this.f) : base = f.tables['GSUB']?.$1 ?? -1;
  final _Font f;
  final int base;

  /// Feature tag → its lookup indices.
  Map<String, List<int>> features() {
    final out = <String, List<int>>{};
    if (base < 0) return out;
    final list = base + f.u16(base + 6), n = f.u16(list);
    for (var i = 0; i < n; i++) {
      final r = list + 2 + 6 * i;
      final tag = String.fromCharCodes(f.bytes.sublist(r, r + 4));
      final ft = list + f.u16(r + 4);
      final count = f.u16(ft + 2);
      out.putIfAbsent(tag, () => []).addAll([for (var k = 0; k < count; k++) f.u16(ft + 4 + 2 * k)]);
    }
    return out;
  }

  int _lookup(int index) {
    final list = base + f.u16(base + 8);
    return list + f.u16(list + 2 + 2 * index);
  }

  /// The subtables of a lookup as (type, offset), extension subtables (type 7) unwrapped.
  List<(int, int)> subtables(int index) {
    final l = _lookup(index), type = f.u16(l), n = f.u16(l + 4);
    final out = <(int, int)>[];
    for (var i = 0; i < n; i++) {
      final st = l + f.u16(l + 6 + 2 * i);
      if (type == 7) {
        out.add((f.u16(st + 2), st + f.u32(st + 4)));
      } else {
        out.add((type, st));
      }
    }
    return out;
  }

  List<int> coverage(int at) {
    final format = f.u16(at);
    if (format == 1) return [for (var i = 0; i < f.u16(at + 2); i++) f.u16(at + 4 + 2 * i)];
    final out = <int>[];
    for (var i = 0; i < f.u16(at + 2); i++) {
      final r = at + 4 + 6 * i;
      for (var g = f.u16(r); g <= f.u16(r + 2); g++) {
        out.add(g);
      }
    }
    return out;
  }

  /// glyph → glyph of the single substitutions of [lookups] (the first one found wins).
  Map<int, int> singles(Iterable<int> lookups) {
    final out = <int, int>{};
    for (final li in lookups) {
      for (final (type, st) in subtables(li)) {
        if (type != 1) continue;
        final format = f.u16(st), cov = coverage(st + f.u16(st + 2));
        for (var i = 0; i < cov.length; i++) {
          final to = format == 1 ? (cov[i] + f.i16(st + 4)) & 0xFFFF : (i < f.u16(st + 4) ? f.u16(st + 6 + 2 * i) : 0);
          if (to != 0) out.putIfAbsent(cov[i], () => to);
        }
      }
    }
    return out;
  }

  /// (first glyph, rest of the components) → ligature glyph, from the ligature substitutions of [lookups].
  Map<String, int> ligatures(Iterable<int> lookups) {
    final out = <String, int>{};
    for (final li in lookups) {
      for (final (type, st) in subtables(li)) {
        if (type != 4) continue;
        final cov = coverage(st + f.u16(st + 2)), sets = f.u16(st + 4);
        for (var i = 0; i < cov.length && i < sets; i++) {
          final set = st + f.u16(st + 6 + 2 * i);
          for (var k = 0; k < f.u16(set); k++) {
            final lig = set + f.u16(set + 2 + 2 * k);
            final glyph = f.u16(lig), comps = f.u16(lig + 2);
            final key = [cov[i], for (var c = 1; c < comps; c++) f.u16(lig + 4 + 2 * (c - 1))].join(',');
            out.putIfAbsent(key, () => glyph);
          }
        }
      }
    }
    return out;
  }
}

/// The presentation-form code points the font lacks, mapped to its own glyphs: (code point → glyph).
Map<int, int> ttfPresentationFormGlyphs(Uint8List ttf) {
  final f = _Font(ttf);
  final cmap = f.cmap();
  if (!cmap.containsKey(0x0628) || !f.tables.containsKey('GSUB')) return {};
  final g = _Gsub(f);
  final feats = g.features();
  final forms = {
    for (final tag in const ['isol', 'init', 'medi', 'fina']) tag: g.singles(feats[tag] ?? const []),
  };
  final ligs = g.ligatures([...?feats['rlig'], ...?feats['liga'], ...?feats['ccmp']]);
  final out = <int, int>{};
  for (final (lo, hi) in _pfRanges) {
    for (var cp = lo; cp <= hi; cp++) {
      if (cmap.containsKey(cp)) continue;
      final type = bidi.getDecompositionType(cp);
      final parts = bidi.getDecompositionMapping(cp);
      if (type == null || parts == null || parts.isEmpty) continue;
      final tag = switch (type) {
        bidi.DecompositionType.isolated => 'isol',
        bidi.DecompositionType.initial => 'init',
        bidi.DecompositionType.medial => 'medi',
        bidi.DecompositionType.finalForm => 'fina',
        _ => null,
      };
      if (tag == null) continue;
      final glyphs = [for (final p in parts) cmap[p]];
      if (glyphs.contains(null)) continue;
      if (glyphs.length == 1) {
        final base = glyphs.single!;
        final to = forms[tag]![base] ?? (tag == 'isol' ? base : null);
        if (to != null) out[cp] = to;
        continue;
      }
      if (glyphs.length != 2) continue;
      // lam-alef: the ligature is made of the letters' contextual forms (OpenType applies isol / init / medi /
      // fina before rlig), else of the plain letters
      final a = glyphs[0]!, b = glyphs[1]!;
      final first = tag == 'fina' ? [forms['medi']![a], a] : [forms['init']![a], a];
      final second = [forms['fina']![b], b];
      int? hit;
      for (final x in first) {
        for (final y in second) {
          if (x == null || y == null || hit != null) continue;
          hit = ligs['$x,$y'];
        }
      }
      if (hit != null) out[cp] = hit;
    }
  }
  return out;
}

int _checksum(Uint8List b) {
  var sum = 0;
  final d = ByteData.sublistView(b);
  for (var i = 0; i + 3 < b.length; i += 4) {
    sum = (sum + d.getUint32(i)) & 0xFFFFFFFF;
  }
  final rest = b.length % 4;
  if (rest != 0) {
    var last = 0;
    for (var k = 0; k < 4; k++) {
      last = (last << 8) | (k < rest ? b[b.length - rest + k] : 0);
    }
    sum = (sum + last) & 0xFFFFFFFF;
  }
  return sum;
}

/// A cmap table of ONE (3,10) format 12 subtable mapping [all] (the font's own mappings and the added presentation
/// forms). The patched font only ever feeds package:pdf, which merges every subtable it finds (and asserts that two
/// agree): one subtable leaves nothing to disagree with.
Uint8List _cmapOf(Map<int, int> all) {
  // groups of consecutive code points with consecutive glyphs
  final codes = all.keys.toList()..sort();
  final groups = <(int, int, int)>[];
  for (final c in codes) {
    final g = all[c]!;
    if (groups.isNotEmpty && groups.last.$2 == c - 1 && groups.last.$3 + (c - groups.last.$1) == g) {
      groups[groups.length - 1] = (groups.last.$1, c, groups.last.$3);
    } else {
      groups.add((c, c, g));
    }
  }
  final t = ByteData(12 + 16 + 12 * groups.length);
  t.setUint16(0, 0);
  t.setUint16(2, 1);
  t.setUint16(4, 3);
  t.setUint16(6, 10);
  t.setUint32(8, 12);
  t.setUint16(12, 12);
  t.setUint32(16, 16 + 12 * groups.length);
  t.setUint32(24, groups.length);
  for (var i = 0; i < groups.length; i++) {
    t.setUint32(28 + 12 * i, groups[i].$1);
    t.setUint32(32 + 12 * i, groups[i].$2);
    t.setUint32(36 + 12 * i, groups[i].$3);
  }
  return t.buffer.asUint8List();
}

/// [ttf] with [replace]d tables (tag → bytes), checksums and head.checkSumAdjustment recomputed.
Uint8List _rebuild(_Font f, Map<String, Uint8List> replace) {
  final tags = f.tables.keys.toList()..sort();
  final bodies = {for (final t in tags) t: replace[t] ?? Uint8List.fromList(f.table(t))};
  // head.checkSumAdjustment is summed as 0
  final head = bodies['head'];
  if (head != null && head.length >= 12) ByteData.sublistView(head).setUint32(8, 0);
  final n = tags.length;
  var entry = 0;
  while ((1 << (entry + 1)) <= n) {
    entry++;
  }
  final search = (1 << entry) * 16;
  var offset = 12 + 16 * n;
  final dir = ByteData(offset);
  dir.setUint32(0, f.u32(0));
  dir.setUint16(4, n);
  dir.setUint16(6, search);
  dir.setUint16(8, entry);
  dir.setUint16(10, n * 16 - search);
  final out = BytesBuilder(copy: false);
  final placed = <String, int>{};
  for (var i = 0; i < n; i++) {
    final t = tags[i], b = bodies[t]!;
    final r = 12 + 16 * i;
    for (var k = 0; k < 4; k++) {
      dir.setUint8(r + k, t.codeUnitAt(k));
    }
    dir.setUint32(r + 4, _checksum(b));
    dir.setUint32(r + 8, offset);
    dir.setUint32(r + 12, b.length);
    placed[t] = offset;
    offset += (b.length + 3) & ~3;
  }
  out.add(dir.buffer.asUint8List());
  for (final t in tags) {
    final b = bodies[t]!;
    out.add(b);
    final pad = ((b.length + 3) & ~3) - b.length;
    if (pad > 0) out.add(Uint8List(pad));
  }
  final file = out.toBytes();
  final at = placed['head'];
  if (at != null) ByteData.sublistView(file).setUint32(at + 8, (0xB1B0AFBA - _checksum(file)) & 0xFFFFFFFF);
  return file;
}

/// The letters a PDF font must be able to join (initial, medial and final forms) before its own Arabic is used:
/// beh teh hah seen sad ain feh qaf kaf lam meem noon heh yeh.
const _joiningLetters = [0x0628, 0x062A, 0x062D, 0x0633, 0x0635, 0x0639, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x064A];

const _arabicRanges = [(0x0600, 0x06FF), (0x0750, 0x077F), (0x08A0, 0x08FF), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)];

/// Whether [cmap] maps every joining form of [_joiningLetters] and the final alef.
bool _canJoin(Map<int, int> cmap) {
  for (var cp = 0xFE70; cp <= 0xFEFC; cp++) {
    final parts = bidi.getDecompositionMapping(cp);
    final type = bidi.getDecompositionType(cp);
    if (parts == null || parts.length != 1 || type == bidi.DecompositionType.isolated) continue;
    if ((_joiningLetters.contains(parts.single) || parts.single == 0x0627) && !cmap.containsKey(cp)) return false;
  }
  return true;
}

/// A font as package:pdf should get it, and whether it draws its own Arabic:
///   * not Arabic: [ttf] unchanged, false;
///   * Arabic, complete after adding the presentation forms read from its GSUB: the patched font, true;
///   * Arabic but some joining forms still missing — Reem Kufi and Aref Ruqaa build letters from dotless shapes plus
///     dots (a GSUB decomposition placed by GPOS mark anchors), which a cmap cannot express: a copy WITHOUT any
///     Arabic mapping, false, so every Arabic letter is drawn by the caller's fallback font (one consistent font per
///     word instead of letters from two fonts) while Latin text and digits keep this font.
(Uint8List, bool) ttfForPdf(Uint8List ttf) {
  try {
    final f = _Font(ttf);
    final cmap = f.cmap();
    if (!cmap.containsKey(0x0628)) return (ttf, false);
    final added = ttfPresentationFormGlyphs(ttf);
    final all = {...cmap, ...added};
    if (_canJoin(all)) return (added.isEmpty ? ttf : _rebuild(f, {'cmap': _cmapOf(all)}), true);
    all.removeWhere((c, _) => _arabicRanges.any((r) => c >= r.$1 && c <= r.$2));
    return (_rebuild(f, {'cmap': _cmapOf(all)}), false);
  } catch (_) {
    return (ttf, false);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Word font embedding
// ═════════════════════════════════════════════════════════════════════════════

/// The 16 key bytes of a `{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}` font key: the hex pairs read from the END of the
/// string (ECMA-376 Part 1 §17.8.1).
List<int> docxFontKeyBytes(String guid) {
  final hex = guid.replaceAll(RegExp(r'[{}-]'), '');
  return [for (var i = 0; i < 16; i++) int.parse(hex.substring(30 - 2 * i, 32 - 2 * i), radix: 16)];
}

/// [font] obfuscated for `word/fonts/*.odttf`: the first 32 bytes XOR the key (twice over). The same call undoes it.
Uint8List docxObfuscateFont(Uint8List font, String guid) {
  final key = docxFontKeyBytes(guid);
  final out = Uint8List.fromList(font);
  for (var i = 0; i < 32 && i < out.length; i++) {
    out[i] ^= key[i % 16];
  }
  return out;
}

/// A stable font key for [seed] (the same font gets the same key in every file: reproducible output).
String docxFontKey(String seed) {
  // FNV-1a over the seed, stretched to 128 bits
  var h = 0x811C9DC5;
  final parts = <int>[];
  for (var round = 0; round < 4; round++) {
    for (final c in '$round$seed'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    parts.add(h);
  }
  final hex = parts.map((p) => p.toRadixString(16).padLeft(8, '0').toUpperCase()).join();
  return '{${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}}';
}
