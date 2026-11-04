// scripts/web/prune_font_manifest.dart
//
// Post-build step of the web build (web start-up, D-171): takes the fonts the first frame does not need out of
// `assets/FontManifest.json`, so Flutter web does not download them before it paints (about 3 MB less).
//
//   flutter build web --release …
//   dart run scripts/web/prune_font_manifest.dart build/web
//
// The font files stay in the build as assets; the removed manifest entries are written to
// `assets/LazyFontManifest.json` (same entry format), which `LazyFonts` (lib/core/display/lazy_fonts.dart) reads to
// load them on demand with FontLoader. Idempotent: a second run changes nothing and keeps the earlier entries.
//
// [lazyFamilies] is the ONE list. A family on it must be awaited with `LazyFonts.ensure` (or drawn under a
// `LazyFontGate`) before any screen that draws with it is shown; uiInter is loaded by AppFonts.start /
// ensureLanguage. NOT on it, because the first frame draws with them: MaterialIcons, CupertinoIcons, the Arabic UI
// font (uiPlexArabic, which also draws the Latin of the Arabic UI) and NotoSansSC (a tiny file whose NAME keeps the
// engine from fetching Noto Sans SC from Google for CJK glyphs).
import 'dart:convert';
import 'dart:io';

/// The families kept out of the start-up manifest.
const lazyFamilies = <String>{
  'PaperPlex',
  'bahji',
  'tajawal',
  'uiInter',
  'packages/moyasar/ReadexPro',
};

/// Splits [manifest] (FontManifest.json entries) into the entries to keep and the lazy ones removed.
/// Pure: no file access.
({List<Map<String, dynamic>> kept, List<Map<String, dynamic>> removed}) pruneFontManifest(
  List<dynamic> manifest, {
  Set<String> lazy = lazyFamilies,
}) {
  final kept = <Map<String, dynamic>>[];
  final removed = <Map<String, dynamic>>[];
  for (final e in manifest) {
    final entry = Map<String, dynamic>.from(e as Map);
    (lazy.contains(entry['family']) ? removed : kept).add(entry);
  }
  return (kept: kept, removed: removed);
}

/// [removed] plus the entries of an earlier run [previous] that this run did not see again (idempotency), in
/// first-seen order, one entry per family.
List<Map<String, dynamic>> mergeLazyEntries(List<dynamic> previous, List<Map<String, dynamic>> removed) {
  final byFamily = <String, Map<String, dynamic>>{
    for (final e in previous) (e as Map)['family'] as String: Map<String, dynamic>.from(e),
  };
  for (final e in removed) {
    byFamily[e['family'] as String] = e;
  }
  return byFamily.values.toList();
}

void main(List<String> args) {
  final dir = args.isEmpty ? 'build/web' : args.first;
  final manifestFile = File('$dir/assets/FontManifest.json');
  if (!manifestFile.existsSync()) {
    stderr.writeln('prune_font_manifest: $dir/assets/FontManifest.json not found (run flutter build web first)');
    exit(1);
  }
  final lazyFile = File('$dir/assets/LazyFontManifest.json');
  final before = manifestFile.readAsStringSync();
  final (:kept, :removed) = pruneFontManifest(jsonDecode(before) as List<dynamic>);
  final previous = lazyFile.existsSync() ? jsonDecode(lazyFile.readAsStringSync()) as List<dynamic> : const [];
  final lazy = mergeLazyEntries(previous, removed);
  if (lazy.isEmpty) {
    stderr.writeln('prune_font_manifest: no lazy family found in the manifest, nothing to do');
    exit(1);
  }
  manifestFile.writeAsStringSync(jsonEncode(kept));
  lazyFile.writeAsStringSync(jsonEncode(lazy));
  int bytes(List<Map<String, dynamic>> es) => [
        for (final e in es)
          for (final f in (e['fonts'] as List))
            if (File('$dir/assets/${(f as Map)['asset']}').existsSync()) File('$dir/assets/${f['asset']}').lengthSync(),
      ].fold(0, (a, b) => a + b);
  stdout.writeln('prune_font_manifest: ${removed.length} families removed (${lazy.length} lazy in all), '
      'start-up fonts ${(bytes(kept) / 1024).round()} KB (lazy: ${(bytes(lazy) / 1024).round()} KB)');
}
