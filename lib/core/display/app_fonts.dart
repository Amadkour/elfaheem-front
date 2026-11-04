// lib/core/display/app_fonts.dart
//
// The app's text fonts: a catalog of premium (OFL) families, one choice per language, loaded on demand.
//
//   AppFonts.family     the family of the CURRENT language's choice — what every TextStyle in the app uses
//                       (`fontFamily: AppFonts.family`, `appText(...)`, the theme). Never the 'tajawal' literal.
//   AppFonts.display    the same font, bold at every weight (what the old 'bahji' headings looked like)
//   AppFonts.fallback   the other language's choice: Arabic names inside English UI (and the reverse) use it;
//                       the theme carries it, so Text widgets get it through DefaultTextStyle
//   AppFonts.select(arabic:, latin:)   loads the files, switches, rebuilds every mounted widget
//
// The two defaults (IBM Plex Sans Arabic · Inter) are declared in pubspec `fonts:`, so they draw from the first
// frame (boot splash). On the web build the post-build prune step keeps Inter out of FontManifest.json (the Arabic
// UI is the default and draws Latin with Plex): `start` / `ensureLanguage` load the family of the open language
// through LazyFonts before it is needed. Every other family is a plain asset folder (assets/fonts/ui/<id>/) registered through
// FontLoader the first time it is chosen or previewed: nothing is downloaded for fonts nobody picked (web).
// The Latin-only families were subset to Latin + punctuation (pyftsubset) to keep the bundle small.
//
// Not for documents: PDF / Word / certificate writers keep their own embedded fonts (PaperPlex, Cert*, the
// export designer's 'tajawal' / 'bahji' choices) so a preview matches the file.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import 'lazy_fonts.dart';

/// One choosable family. [arabic] = it draws Arabic (every Arabic option also draws Latin).
@immutable
class AppFontOption {
  const AppFontOption({
    required this.id,
    required this.family,
    required this.nameAr,
    required this.nameEn,
    required this.noteAr,
    required this.noteEn,
    required this.arabic,
    required this.weights,
    this.bundled = false,
  });

  final String id;

  /// The engine family name (`TextStyle.fontFamily`). Engine names are case-insensitive: keep them distinct.
  final String family;
  final String nameAr, nameEn, noteAr, noteEn;
  final bool arabic;

  /// weight → asset path (static instances; a missing weight resolves to the nearest one).
  final Map<int, String> weights;

  /// Declared in pubspec `fonts:` (available from the first frame, no FontLoader).
  final bool bundled;

  String get displayFamily => '${family}Display';
  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
  String note(String lang) => lang == 'ar' ? noteAr : noteEn;
}

Map<int, String> _w(String id, String stem, List<int> weights) =>
    {for (final w in weights) w: 'assets/fonts/ui/$id/$stem-$w.ttf'};

abstract final class AppFonts {
  static const arabicDefault = 'plex_arabic';
  static const latinDefault = 'inter';

  static final List<AppFontOption> catalog = [
    // ── Arabic (each also draws Latin) ──
    AppFontOption(
      id: 'plex_arabic', family: 'uiPlexArabic', arabic: true, bundled: true,
      nameAr: 'آي بي إم بلكس عربي', nameEn: 'IBM Plex Sans Arabic',
      noteAr: 'واضح واحترافي — الافتراضي', noteEn: 'Crisp and professional — the default',
      weights: _w('plex_arabic', 'IBMPlexSansArabic', [400, 500, 600, 700]),
    ),
    AppFontOption(
      id: 'readex', family: 'uiReadex', arabic: true,
      nameAr: 'ريدكس برو', nameEn: 'Readex Pro',
      noteAr: 'مصمم لسهولة القراءة', noteEn: 'Designed for easy reading',
      weights: _w('readex', 'ReadexPro', [400, 500, 600, 700]),
    ),
    AppFontOption(
      id: 'noto_kufi', family: 'uiNotoKufi', arabic: true,
      nameAr: 'نوتو كوفي', nameEn: 'Noto Kufi Arabic',
      noteAr: 'كوفي حديث وأنيق', noteEn: 'Modern, elegant Kufi',
      weights: _w('noto_kufi', 'NotoKufiArabic', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'almarai', family: 'uiAlmarai', arabic: true,
      nameAr: 'المراعي', nameEn: 'Almarai',
      noteAr: 'ودود ومريح — مناسب للصغار', noteEn: 'Friendly and soft — good for young learners',
      weights: _w('almarai', 'Almarai', [400, 700, 800]),
    ),
    AppFontOption(
      id: 'baloo', family: 'uiBaloo', arabic: true,
      nameAr: 'بالو بهيجان', nameEn: 'Baloo Bhaijaan 2',
      noteAr: 'حروف مستديرة مرحة — للأطفال', noteEn: 'Round, playful letters — for children',
      weights: _w('baloo', 'BalooBhaijaan2', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'cairo', family: 'uiCairo', arabic: true,
      nameAr: 'القاهرة', nameEn: 'Cairo',
      noteAr: 'عصري ومضغوط', noteEn: 'Contemporary and compact',
      weights: _w('cairo', 'Cairo', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'tajawal', family: 'tajawal', arabic: true, bundled: true,
      nameAr: 'تجوّل (الكلاسيكي)', nameEn: 'Tajawal (classic)',
      noteAr: 'خط التطبيق السابق', noteEn: "The app's previous font",
      weights: {
        400: 'assets/fonts/Tajawal-Regular.ttf',
        500: 'assets/fonts/tajawal/Tajawal-Medium.ttf',
        700: 'assets/fonts/tajawal/Tajawal-Bold.ttf',
        800: 'assets/fonts/tajawal/Tajawal-ExtraBold.ttf',
      },
    ),
    // ── Latin ──
    AppFontOption(
      id: 'inter', family: 'uiInter', arabic: false, bundled: true,
      nameAr: 'إنتر', nameEn: 'Inter',
      noteAr: 'خط الواجهات الأشهر — الافتراضي', noteEn: 'The classic UI typeface — the default',
      weights: _w('inter', 'Inter', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'jakarta', family: 'uiJakarta', arabic: false,
      nameAr: 'بلس جاكرتا', nameEn: 'Plus Jakarta Sans',
      noteAr: 'هندسي وفاخر', noteEn: 'Geometric and premium',
      weights: _w('jakarta', 'PlusJakartaSans', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'lexend', family: 'uiLexend', arabic: false,
      nameAr: 'ليكسند', nameEn: 'Lexend',
      noteAr: 'يقلل إجهاد القراءة — للمتعلمين الصغار', noteEn: 'Reduces reading strain — for young readers',
      weights: _w('lexend', 'Lexend', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'atkinson', family: 'uiAtkinson', arabic: false,
      nameAr: 'أتكنسون (وضوح عالٍ)', nameEn: 'Atkinson Hyperlegible',
      noteAr: 'لضعاف البصر: حروف لا تتشابه', noteEn: 'For low vision: letters that never look alike',
      weights: _w('atkinson', 'AtkinsonHyperlegibleNext', [400, 500, 600, 700, 800]),
    ),
    AppFontOption(
      id: 'nunito', family: 'uiNunito', arabic: false,
      nameAr: 'نونيتو', nameEn: 'Nunito',
      noteAr: 'دائري ولطيف', noteEn: 'Rounded and friendly',
      weights: _w('nunito', 'Nunito', [400, 500, 600, 700, 800]),
    ),
  ];

  /// Options for one language: Arabic UI → Arabic fonts; English UI → Latin fonts + the Arabic ones (they draw
  /// Latin too).
  static List<AppFontOption> optionsFor(String lang) =>
      lang == 'ar' ? catalog.where((f) => f.arabic).toList() : [...catalog.where((f) => !f.arabic), ...catalog.where((f) => f.arabic)];

  static AppFontOption byId(String? id, {required bool arabic}) =>
      catalog.where((f) => f.id == id && (!arabic || f.arabic)).firstOrNull ?? byIdOrDefault(arabic ? arabicDefault : latinDefault);

  static AppFontOption byIdOrDefault(String id) => catalog.firstWhere((f) => f.id == id);

  static AppFontOption _ar = byIdOrDefault(arabicDefault);
  static AppFontOption _en = byIdOrDefault(latinDefault);

  /// Bumps after every switch (painters that cache text layouts can listen).
  static final ValueNotifier<int> version = ValueNotifier(0);

  static AppFontOption get arabicChoice => _ar;
  static AppFontOption get latinChoice => _en;
  static AppFontOption get current => AppConfig.lang == 'ar' ? _ar : _en;
  static AppFontOption get other => AppConfig.lang == 'ar' ? _en : _ar;

  static String get family => current.family;
  static String get display => _displayReady.contains(current.id) ? current.displayFamily : current.family;
  static List<String> get fallback => [current.family, other.family];

  // the ids whose files are registered; a bundled family joins after LazyFonts.ensure (instant when not lazy)
  static final Set<String> _loaded = {};
  static final Set<String> _displayReady = {};
  static final Map<String, Future<void>> _pending = {};

  static bool isLoaded(String id) => _loaded.contains(id);

  /// Registers [option]'s files (and its bold display alias) once per run. Safe to call repeatedly.
  static Future<void> ensureLoaded(AppFontOption option) =>
      _pending[option.id] ??= _load(option).catchError((Object e) {
        _pending.remove(option.id);
        debugPrint('[AppFonts] ${option.id} failed to load: $e');
      });

  static Future<void> _load(AppFontOption f) async {
    if (!_loaded.contains(f.id) && f.bundled) {
      await LazyFonts.ensure(f.family); // a pubspec family: only a pruned web build has anything to fetch
      _loaded.add(f.id);
    }
    if (!_loaded.contains(f.id)) {
      final loader = FontLoader(f.family);
      for (final path in f.weights.values) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
      _loaded.add(f.id);
    }
    // the display alias: only the boldest ≤ 800 file, so every weight asked of it draws bold
    final bold = f.weights.keys.where((w) => w >= 700).fold<int?>(null, (a, w) => a == null || w < a ? w : a) ??
        f.weights.keys.reduce((a, b) => a > b ? a : b);
    final alias = FontLoader(f.displayFamily)..addFont(rootBundle.load(f.weights[bold]!));
    await alias.load();
    _displayReady.add(f.id);
  }

  /// Sets the choices without loading or rebuilding (start-up, before the first frame; tests).
  static void setChoices({String? arabic, String? latin}) {
    if (arabic != null) _ar = byId(arabic, arabic: true);
    if (latin != null) _en = byId(latin, arabic: false);
  }

  /// Start-up: loads the choice of [lang] (the open language) and returns; the other language's choice loads in the
  /// background, so the first frame never waits for a family it does not draw with.
  static Future<void> start(String lang) async {
    final first = lang == 'ar' ? _ar : _en;
    final second = lang == 'ar' ? _en : _ar;
    await ensureLoaded(first);
    unawaited(ensureLoaded(second));
    version.value++;
  }

  /// Before the app switches to [lang]: its font choice must be registered first (no fallback-font flash).
  static Future<void> ensureLanguage(String lang) => ensureLoaded(lang == 'ar' ? _ar : _en);

  /// Loads the chosen families, then switches. A family that fails to load keeps the previous choice.
  static Future<void> select({String? arabic, String? latin}) async {
    final ar = arabic == null ? _ar : byId(arabic, arabic: true);
    final en = latin == null ? _en : byId(latin, arabic: false);
    await Future.wait([ensureLoaded(ar), ensureLoaded(en)]);
    if (_loaded.contains(ar.id)) _ar = ar;
    if (_loaded.contains(en.id)) _en = en;
    version.value++;
  }
}
