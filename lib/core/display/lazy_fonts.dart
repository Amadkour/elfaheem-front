// lib/core/display/lazy_fonts.dart
//
// Fonts the web build does NOT download at start-up (web start-up, D-150).
//
// Flutter web fetches every family of assets/FontManifest.json before its first frame (about 3.5 MB here). The
// post-build step `scripts/web/prune_font_manifest.dart` takes the families the first frame does not need out of
// that manifest and writes them to assets/LazyFontManifest.json (same entry format; the files stay in the build).
// This file loads them on demand with FontLoader:
//
//   await LazyFonts.ensure('tajawal');            // before a screen that draws with it is shown
//   await LazyFonts.ensureAll(const ['PaperPlex', 'bahji']);
//   LazyFontGate(families: const ['tajawal'], child: …)   // a widget that draws with them, hidden until loaded
//
// A no-op everywhere but the web, and wherever the manifest was not pruned (`flutter run`, tests): there is no
// LazyFontManifest.json, so every family is still a normal pubspec font. Concurrent calls share one future; a
// failure is logged and leaves the fallback font (the next call tries again).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Registers one family from the asset keys [assets] (the production implementation uses FontLoader).
typedef LazyFontRegister = Future<void> Function(String family, List<String> assets);

abstract final class LazyFonts {
  /// The asset key of the pruned entries.
  static const manifestAsset = 'LazyFontManifest.json';

  /// How long after start-up the remaining lazy families are fetched in the background ([prefetchLater]).
  static const prefetchDelay = Duration(seconds: 10);

  // test seams
  static bool enabled = kIsWeb;
  static Future<String?> Function() readManifest = _readManifest;
  static LazyFontRegister register = _register;

  static Map<String, List<String>>? _entries; // family → asset keys, null = not read yet
  static Future<Map<String, List<String>>>? _reading;
  static final Map<String, Future<void>> _pending = {};
  static final Set<String> _done = {};
  static Timer? _prefetch;

  /// Forgets everything (tests).
  @visibleForTesting
  static void reset() {
    _entries = null;
    _reading = null;
    _pending.clear();
    _done.clear();
    _prefetch?.cancel();
    _prefetch = null;
    enabled = kIsWeb;
    readManifest = _readManifest;
    register = _register;
  }

  /// The families a pruned build keeps out of FontManifest.json, parsed from [json] (a list of FontManifest entries).
  static Map<String, List<String>> parse(String? json) {
    final out = <String, List<String>>{};
    if (json == null || json.trim().isEmpty) return out;
    final list = jsonDecode(json);
    if (list is! List) return out;
    for (final e in list) {
      if (e is! Map) continue;
      final family = e['family'];
      final fonts = e['fonts'];
      if (family is! String || fonts is! List) continue;
      out[family] = [
        for (final f in fonts)
          if (f is Map && f['asset'] is String) f['asset'] as String,
      ];
    }
    return out;
  }

  static Future<String?> _readManifest() async {
    try {
      return await rootBundle.loadString(manifestAsset);
    } catch (_) {
      return null; // not a pruned build
    }
  }

  static Future<void> _register(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  static Future<Map<String, List<String>>> _manifest() => _reading ??= readManifest().then((s) {
        try {
          return _entries = parse(s);
        } catch (e) {
          debugPrint('[LazyFonts] manifest unreadable: $e');
          return _entries = const {};
        }
      });

  /// True when [family] is usable now (loaded, or not a lazy family of this build). Only exact after the first
  /// [ensure] or [prefetchLater] has read the manifest; before that it answers true off the web only.
  static bool isReady(String family) {
    if (!enabled) return true;
    final e = _entries;
    if (e == null) return false;
    return !e.containsKey(family) || _done.contains(family);
  }

  /// Loads [family] once. Resolves immediately when it is not lazy in this build.
  static Future<void> ensure(String family) {
    if (!enabled) return SynchronousFuture<void>(null);
    return _pending[family] ??= _ensure(family);
  }

  static Future<void> ensureAll(Iterable<String> families) => Future.wait([for (final f in families) ensure(f)]);

  static Future<void> _ensure(String family) async {
    try {
      final assets = (await _manifest())[family];
      if (assets == null || assets.isEmpty) return;
      await register(family, assets);
      _done.add(family);
    } catch (e) {
      _pending.remove(family);
      debugPrint('[LazyFonts] $family failed to load: $e');
    }
  }

  /// Fetches every lazy family once, [prefetchDelay] from now (a no-op off the web / on an unpruned build): a
  /// screen that draws with one of them and forgot to [ensure] it still finds it loaded.
  static void prefetchLater({Duration? after}) {
    if (!enabled || _prefetch != null) return;
    _prefetch = Timer(after ?? prefetchDelay, () async {
      final all = (await _manifest()).keys.toList();
      for (final f in all) {
        await ensure(f); // one at a time: it is background work
      }
    });
  }
}

/// Draws [child] at once, but invisible until [families] are loaded, so no screen flashes in a fallback font.
/// Instant (a plain pass-through) when they are already loaded or not lazy.
class LazyFontGate extends StatefulWidget {
  const LazyFontGate({super.key, required this.families, required this.child});

  final List<String> families;
  final Widget child;

  @override
  State<LazyFontGate> createState() => _LazyFontGateState();
}

class _LazyFontGateState extends State<LazyFontGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ready = !LazyFonts.enabled || widget.families.every(LazyFonts.isReady);
    if (!_ready) {
      LazyFonts.ensureAll(widget.families).whenComplete(() {
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  // Opacity 1 paints the child as is and keeps the tree the same shape, so nothing under it is rebuilt from scratch
  Widget build(BuildContext context) => Opacity(opacity: _ready ? 1 : 0, child: widget.child);
}
