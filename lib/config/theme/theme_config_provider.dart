// lib/config/theme_config_provider.dart
//
// The single theme access point for the whole app: `context.themeConfig`.
//
// Lifecycle
// ─────────
//   1. load() is called once at app startup (via a regular
//      context.read<ThemeConfigProvider>().load() — not through the
//      context.themeConfig getter below, which is for reading colours/
//      styles during build, not for lifecycle calls).
//   2. The built-in DEFAULT theme is AppTheme (app_theme.dart). On top of it:
//        • the last cached server palette (SharedPreferences) is applied
//          instantly, so the app opens without waiting for the network;
//        • the server palette is then fetched. Success → applied + cached.
//          Failure → [serverUnreachable] becomes true and the app shows a
//          "no internet" banner with a reload button (see main.dart); the
//          cached/default palette keeps working meanwhile.
//   3. Widgets read context.themeConfig.primary, .h2, .cardShadow, etc.
//      Every colour/style/shadow/gradient the app used to get from
//      `context.colors` (ThemeConfigProvider) lives here now — there is no second
//      theme accessor.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/display/display_settings.dart';
import '../../core/app_time.dart';
import '../app_config.dart';
import 'app_theme.dart';
import 'theme_config_model.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_contrast.dart';

// v2: drops palettes cached before the new default theme, so offline users
// get the new default instead of the old cached one.
const _kCacheKey = 'theme_config_v2';
const _kDisableListCacheKey = 'disable_list_v1';
const _kPlatformCacheKey = 'platform_settings_v1';

/// Detects which platform string to send to the API.
String get _currentPlatform {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  return 'android';
}

class ThemeConfigProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ApiClient _api;

  ThemeConfigProvider({required ApiClient api}) : _api = api {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Silent pushes only reach the app while it is in the foreground, so a theme
  // changed while the app was in the background is picked up on resume.
  DateTime? _lastFetchAt;
  bool _silentInFlight = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastFetchAt;
    if (_isLoading || last == null) return;
    if (DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    silentRefresh();
  }

  // ── Loading / model state ─────────────────────────────────────────────────

  ThemeConfigModel? _model;
  ThemeConfigModel? get model => _model;

  /// Tests and visual renders: paint with [colors] (a theme response's `colors` map) instead of the built-in
  /// palette, without a network call.
  @visibleForTesting
  void debugUseColors(Map<String, dynamic> colors) {
    _model = ThemeConfigModel.fromJson(colors);
    _isLoading = false;
    notifyListeners();
  }

  /// True from construction until the first [load] call resolves (either
  /// from the API or, on failure, from the SharedPreferences cache).
  /// The app should show a loading/splash screen while this is true.
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// Kept for backwards compatibility with existing call sites.
  bool get isFetching => _isLoading;

  String? _error;
  String? get error => _error;

  /// True when the last attempt to fetch the theme from the server failed
  /// (offline, timeout, server error). The app then runs on the cached /
  /// default palette and shows a banner with a reload button.
  bool _serverUnreachable = false;
  bool get serverUnreachable => _serverUnreachable;

  /// True while the banner's reload button is fetching.
  bool _isRetrying = false;
  bool get isRetrying => _isRetrying;

  /// Feature kill-switch list for the current platform. Same value as
  /// [AppConfig.disableList] — exposed here too so widgets that already
  /// read context.themeConfig don't need a second lookup.
  List<String> get disableList => AppConfig.disableList;

  /// Set by the `context.themeConfig` getter right before it returns this
  /// instance, from `Theme.of(context).brightness`. Every colour/style
  /// getter below branches on this. The app has one global brightness with
  /// no per-subtree overrides, so a shared mutable flag read synchronously
  /// within the same build is safe and avoids a second wrapper class.
  bool isDark = false;

  // ── Entry point ───────────────────────────────────────────────────────────

  /// Call this once at app startup.
  ///
  /// The cached palette is applied first (instant, works offline). The app
  /// only waits briefly for the server — if it is slow or unreachable the app
  /// opens on the cached / default theme and the fetch finishes in the
  /// background (the banner appears if it fails).
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadFromCache();

      final fetch = _fetchFromServer();
      if (_model == null) {
        // Nothing cached: give the server a short window so the very first
        // frame is usually right, then continue with the default theme.
        await fetch.timeout(const Duration(seconds: 30), onTimeout: () => false);
      }
      _isLoading = false;
      notifyListeners();
      await fetch;
    } catch (e) {
      debugPrint('[ThemeConfigProvider] load error: $e');
    } finally {
      // Always leave the splash, even if everything above failed.
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-fetch from the server WITHOUT going back to the splash screen (the
  /// splash would tear down the Navigator and lose the current screen).
  /// Used by the "no internet" banner's reload button.
  Future<void> reload() async {
    if (_isRetrying) return;
    _isRetrying = true;
    notifyListeners();
    try {
      await _fetchFromServer();
    } finally {
      _isRetrying = false;
      notifyListeners();
    }
  }

  /// Alias for [reload] — call after an admin colour change to force a
  /// fresh fetch.
  Future<void> refresh() => reload();

  /// Re-fetch the theme in the background (admin changed it -> silent FCM push
  /// `theme_updated`, or the app was resumed). No splash, no retry spinner and
  /// no "no internet" banner on failure - the current palette just stays.
  /// Listeners are notified on success, so every `context.colors` consumer
  /// repaints automatically.
  Future<void> silentRefresh() async {
    if (_silentInFlight || _isRetrying) return;
    _silentInFlight = true;
    try {
      await _fetchFromServer(silent: true);
    } finally {
      _silentInFlight = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // SURFACES
  // ══════════════════════════════════════════════════════════════════════

  Color get background => isDark
      ? (_model?.darkCard.withAlpha(230) ?? AppTheme.darkBackground)
      : (_model?.background ?? AppTheme.background);

  /// [background] made opaque, for a pinned header (a tab strip) that content scrolls under: in dark mode
  /// [background] is the card tone at 90 % alpha, so cards and titles showed through the strip. Blended over the
  /// page's base tone it looks the same as the page around it when nothing is under it.
  Color get pinnedBackground => Color.alphaBlend(background, isDark ? cardBg2 : cardBg).withAlpha(255);

  Color get surface => isDark
      ? (_model?.darkSurface ?? AppTheme.darkSurface)
      : (_model?.cardBg ?? AppTheme.cardBg);

  Color get cardBg => isDark
      ? (_model?.darkCard ?? AppTheme.darkCard)
      : (_model?.cardBg ?? AppTheme.cardBg);

  /// Same as [cardBg] in light mode; in dark mode this intentionally
  /// resolves to the darker background tone rather than the card tone —
  /// used for nested surfaces that need to recede rather than pop.
  Color get cardBg2 => isDark
      ? (_model?.darkBackground ?? AppTheme.darkBackground)
      : (_model?.cardBg ?? AppTheme.cardBg);

  Color get inputBg => isDark
      ? (_model?.inputBgDark ?? AppTheme.inputBgDark)
      : (_model?.inputBg ?? AppTheme.inputBg);

  Color get divider => _contrast(
      isDark ? (_model?.darkDivider ?? AppTheme.darkDivider) : (_model?.divider ?? AppTheme.divider), textMedium, 0.35);

  /// "High contrast" (Display & reading settings): muted ink and dividers are pulled toward the main ink.
  Color _contrast(Color c, Color toward, double t) => _hc ? Color.lerp(c, toward, t)! : c;

  bool get _hc => DisplaySettings.instance.prefs.highContrast;

  // ══════════════════════════════════════════════════════════════════════
  // TEXT
  // ══════════════════════════════════════════════════════════════════════

  Color get textDark => isDark
      ? (_model?.darkTextPrimary ?? AppTheme.darkTextPrimary)
      : (_model?.textDark ?? AppTheme.textDark);

  Color get textMedium => _contrast(
      isDark ? (_model?.darkTextMuted ?? AppTheme.darkTextMuted) : (_model?.textMedium ?? AppTheme.textMedium), textDark, 0.5);

  Color get textLight => _contrast(
      isDark ? (_model?.darkTextLight ?? AppTheme.darkTextLight) : (_model?.textLight ?? AppTheme.textLight), textDark, 0.55);

  Color get textAction => _model?.textAction ?? AppTheme.textAction;

  // ══════════════════════════════════════════════════════════════════════
  // BRAND  (same in both modes)
  // ══════════════════════════════════════════════════════════════════════

  Color get primary => _model?.primary ?? AppTheme.primary;

  Color get primaryDark => _model?.primaryDark ?? AppTheme.primaryDark;

  Color get primaryLight => _model?.primaryLight ?? AppTheme.primaryLight;

  Color get lightPrimary => _model?.lightPrimary ?? AppTheme.lightPrimary;

  Color get accent => _model?.accent ?? AppTheme.accent;

  Color get accent2 => _model?.accent2 ?? AppTheme.accent2;

  Color get success => _model?.success ?? AppTheme.success;

  Color get danger => _model?.danger ?? AppTheme.danger;

  Color get warning => _model?.warning ?? AppTheme.warning;

  Color get purple => _model?.purple ?? AppTheme.purple;

  /// Secondary copy (subtitles, hints, unselected labels): WCAG AA on this mode's surfaces.
  Color get secondText => _contrast(
      isDark ? (_model?.darkSecondText ?? AppTheme.darkSecondText) : (_model?.secondText ?? AppTheme.secondText), textDark, 0.5);

  // ══════════════════════════════════════════════════════════════════════
  // CHARCOAL TONES  (same in both modes)
  // ══════════════════════════════════════════════════════════════════════

  Color get charcoal => _model?.charcoal ?? AppTheme.charcoal;

  Color get charcoalLight => _model?.charcoalLight ?? AppTheme.charcoalLight;

  Color get charcoalDark => _model?.charcoalDark ?? AppTheme.charcoalDark;

  // ══════════════════════════════════════════════════════════════════════
  // TINTED ICON BACKGROUNDS
  // ══════════════════════════════════════════════════════════════════════

  /// Server-configured, unlike the other tints below — the admin can set
  /// this to something other than a flat alpha derivative of [primary].
  Color get primaryTint => isDark
      ? (_model?.primaryTintDark ?? AppTheme.primaryTintDark)
      : (_model?.primaryTint ?? AppTheme.primaryTint);

  Color get blueTint => charcoal.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get accentTint => accent.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get successTint => success.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get dangerTint => danger.withValues(alpha: isDark ? 0.14 : 0.06);

  Color get purpleTint => purple.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get tealTint => accent2.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get darkIconBg => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : textDark.withValues(alpha: 0.08);

  // ══════════════════════════════════════════════════════════════════════
  // ON-HERO ROLES — ink and glass over a gradient hero, the sidebar and the
  // primary top bar. The same in both modes (a hero keeps its brand gradient
  // in dark mode). Derived from the server palette unless it sends `on_hero`
  // / `hero_shade`: the ink is the light card surface, the shade the darkest
  // charcoal. Never Colors.white / Colors.black on a hero — these.
  // ══════════════════════════════════════════════════════════════════════

  /// Text and icons over a hero / the sidebar / the primary top bar.
  Color get onHero => _model?.onHero ?? _model?.surfaceCard ?? AppTheme.surfaceCard;

  /// Secondary text over a hero (the old `Colors.white70`).
  Color get onHeroMuted => onHero.withValues(alpha: _hc ? 0.92 : 0.72);

  /// Unselected icons / labels over the sidebar (the old `white.withValues(alpha: .42)`).
  Color get onHeroFaint => onHero.withValues(alpha: _hc ? 0.75 : 0.45);

  /// A glass chip / button / logo well over a hero.
  Color get heroGlass => onHero.withValues(alpha: 0.16);

  /// The hairline of a glass chip.
  Color get heroGlassBorder => onHero.withValues(alpha: _hc ? 0.45 : 0.24);

  /// A hairline divider over the sidebar.
  Color get heroDivider => onHero.withValues(alpha: 0.08);

  /// The dark tone a hero gradient fades into — use [heroEnd].
  Color get heroShade => _model?.heroShade ?? _model?.charcoalDark ?? AppTheme.charcoalDark;

  /// The darker end of a hero gradient built on [base] (the old `alphaBlend(black @ .3, base)`).
  Color heroEnd(Color base, [double amount = 0.30]) => Color.alphaBlend(heroShade.withValues(alpha: amount), base);

  /// The lighter start of a gradient built on [base] (the old `lerp(base, white, .28)`).
  Color heroTint(Color base, [double amount = 0.28]) => Color.lerp(base, onHero, amount)!;

  // ══════════════════════════════════════════════════════════════════════
  // RADII  (not server-configurable — pure design tokens)
  // ══════════════════════════════════════════════════════════════════════

  double get radiusSmall => AppTheme.radiusSmall;

  double get radiusMedium => AppTheme.radiusMedium;

  double get radiusLarge => AppTheme.radiusLarge;

  double get radiusXL => AppTheme.radiusXL;

  BorderRadius get brSmall => BorderRadius.circular(AppTheme.radiusSmall);

  BorderRadius get brMedium => BorderRadius.circular(AppTheme.radiusMedium);

  BorderRadius get brLarge => BorderRadius.circular(AppTheme.radiusLarge);

  BorderRadius get brXL => BorderRadius.circular(AppTheme.radiusXL);

  // ══════════════════════════════════════════════════════════════════════
  // GRADIENTS
  // Each one is a single ready-to-use LinearGradient — no separate
  // List<Color> + LinearGradient pair for the same concept. Fallback stops
  // reference AppTheme's own gradients (colors) instead of duplicating the
  // hex values here a second time, so the two files can never drift apart.
  // ══════════════════════════════════════════════════════════════════════

  // ── Brand gradients (D-136) ────────────────────────────────────────────
  // Derived from the primary family the server already sends (primary_light → primary → primary_dark), never from
  // the server's `gradient_primary`: that one is built from the two ACCENT colours and painted every "brand" tab,
  // pill and hero gold / olive (M22). The optional `primary_gradient_start` / `primary_gradient_end` keys replace
  // the outer stops when a theme sends them. Every stop keeps the on-hero ink (button labels, hero titles) at WCAG AA
  // (4.5:1): the light stop moves toward primary_light only as far as that holds, so the light end is a sheen, not a
  // pale corner under white text. 135° (top-start → bottom-end), mirrored in Arabic. Flat [primary] stays THE colour
  // for text, icons, outlines and focus rings.

  /// The three stops of the brand fill in [dark] mode: lift (toward primary_light) · primary · deep.
  List<Color> brandStops({required bool dark}) {
    final key = Object.hash(_model, dark, onHero);
    final hit = _stopCache[key];
    if (hit != null) return hit;
    final ink = onHero;
    Color safe(Color c) => ensureContrast(c, [ink], min: _kBrandInk);
    final mid = safe(primary);
    // light: up to 55 % of the way to primary_light; dark: a shorter lift (a bright edge glares on a dark page)
    // a lift of the SAME hue barely shows (the contrast guard keeps it within a shade of primary), so the derived
    // ends also turn the hue: a fresher light end, a cooler, deeper end — a visible sweep at the same contrast
    final lift = _model?.primaryGradientStart != null
        ? safe(_model!.primaryGradientStart!)
        : safe(_turn(_liftToward(mid, primaryLight, dark ? 0.35 : 0.55, ink), -7, 1.08, 1));
    final deepBase = _model?.primaryGradientEnd ?? _turn(primaryDark, 16, 1, dark ? 1 : 0.86);
    // dark: stop short of primary_dark so the fill still separates from the dark page around it
    final deep = safe(dark ? Color.lerp(mid, deepBase, 0.7)! : deepBase);
    if (_stopCache.length > 8) _stopCache.clear();
    return _stopCache[key] = [lift, mid, deep];
  }

  static const double _kBrandInk = 4.6; // WCAG AA (4.5) with a rounding margin
  final Map<int, List<Color>> _stopCache = {};

  /// [from] moved toward [to] by at most [maxT], as far as [ink] keeps [_kBrandInk] on it.
  static Color _liftToward(Color from, Color to, double maxT, Color ink) {
    for (var t = maxT; t > 0; t -= 0.01) {
      final c = Color.lerp(from, to, t)!;
      if (contrastRatio(ink, c) >= _kBrandInk) return c;
    }
    return from;
  }

  /// [c] with its hue turned by [deg], its saturation and lightness scaled.
  static Color _turn(Color c, double deg, double sat, double light) {
    final h = HSLColor.fromColor(c);
    return h
        .withHue((h.hue + deg) % 360)
        .withSaturation((h.saturation * sat).clamp(0.0, 1.0))
        .withLightness((h.lightness * light).clamp(0.0, 1.0))
        .toColor();
  }

  LinearGradient _brand(List<Color> stops) => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: stops,
    stops: const [0, 0.45, 1],
  );

  /// A glass sheen over a brand fill: a soft top light that fades out above a centred label (it never sits under
  /// the text, so the label keeps the fill's contrast). Paint it ABOVE the fill (a foreground decoration).
  LinearGradient get primaryGloss => LinearGradient(
    begin: Alignment.topCenter,
    end: const Alignment(0, -0.38),
    colors: [onHero.withValues(alpha: isDark ? 0.12 : 0.2), onHero.withValues(alpha: 0)],
  );

  /// The brand fill for a primary button / selected pill / active tab, in the open mode.
  LinearGradient get primaryGradient => _brand(brandStops(dark: isDark));

  /// [primaryGradient] pressed: every stop a shade deeper (hover is the ripple's overlay).
  LinearGradient get primaryGradientPressed => primaryGradientPressedFor(dark: isDark);

  LinearGradient primaryGradientPressedFor({required bool dark}) =>
      _brand([for (final s in brandStops(dark: dark)) heroEnd(s, 0.16)]);

  /// Always the light-mode brand gradient, whatever the mode (content drawn ON a coloured surface).
  LinearGradient get primaryGradientOnColor => _brand(brandStops(dark: false));

  /// A hero header / banner: primary at the start (where the title sits, so its muted subtitle keeps the contrast
  /// it had on the flat primary) deepening toward the end. Pair it with [heroGlow] (a warm accent2 light in the
  /// top-end corner) as an inner layer behind the content — see AppHero.
  LinearGradient get heroGradient {
    final s = brandStops(dark: isDark);
    return LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [s[1], Color.lerp(s[1], s[2], 0.55)!, heroEnd(s[2], isDark ? 0.18 : 0.10)],
      stops: const [0, 0.5, 1],
    );
  }

  /// A faint warm glow (accent2) for the top-end corner of a hero, at most as strong as the on-hero ink allows
  /// over every hero stop.
  RadialGradient get heroGlow {
    final stops = heroGradient.colors;
    var a = 0.22;
    while (a > 0 && stops.any((s) => contrastRatio(onHero, Color.alphaBlend(accent2.withValues(alpha: a), s)) < _kBrandInk)) {
      a -= 0.02;
    }
    return RadialGradient(
      center: AlignmentDirectional.topEnd,
      radius: 1.1,
      colors: [accent2.withValues(alpha: a.clamp(0.0, 1.0)), accent2.withValues(alpha: 0)],
    );
  }

  /// A soft brand wash for a card / page header (top → transparent). Decorative only: text on it reads as on the
  /// surface below.
  LinearGradient get surfaceGlow => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primary.withValues(alpha: isDark ? 0.10 : 0.05), primary.withValues(alpha: 0)],
  );

  /// The soft coloured shadow under a gradient button (smaller than [primaryShadow], which suits heroes).
  List<BoxShadow> get primaryButtonShadow {
    final shadowColor = isDark
        ? (_model?.primaryShadowColorDark ?? AppTheme.primaryShadowColorDark)
        : (_model?.primaryShadowColor ?? AppTheme.primaryShadowColor);
    return [BoxShadow(color: shadowColor, blurRadius: 14, offset: const Offset(0, 5))];
  }

  /// Same "charcoal instead of brand colour" behaviour as [primaryGradient].
  LinearGradient get primarySliderGradient => _sliderGradient;

  LinearGradient get disableGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientDisable ?? AppTheme.disableGradient.colors,
  );

  LinearGradient get accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientAccent ?? AppTheme.accentGradient.colors,
  );
  LinearGradient get lightAccentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      primary.withValues(alpha:0.3),
      accent.withValues(alpha:0.3)
    ],
  );

  LinearGradient get sliderGradient => isDark? AppTheme.darkSlideBarGradient: _sliderGradient;

  LinearGradient get tealGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientTeal ?? AppTheme.tealGradient.colors,
  );

  LinearGradient get successGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientSuccess ?? AppTheme.successGradient.colors,
  );

  LinearGradient get dangerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientDanger ?? AppTheme.dangerGradient.colors,
  );

  LinearGradient get goldCharcoalGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientGoldCharcoal ?? AppTheme.goldCharcoalGradient.colors,
  );

  /// Background gradient adapts to mode.
  LinearGradient get backgroundGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isDark
        ? (_model?.gradientDarkBackground ?? AppTheme.darkBackgroundGradient.colors)
        : (_model?.gradientBackground ?? AppTheme.backgroundGradient.colors),
  );

  /// Background gradient adapts to mode; light/dark variants use different
  /// alignments (matching the original hand-tuned AppTheme definitions).
  ///
  /// Light: the brand gradient running down the sidebar (D-136), not the server's `gradient_slider`, which fades
  /// to the cream accent at the bottom where the on-hero labels fell below AA.
  LinearGradient get slideBarGradient {
    if (isDark) return _darkSlideBarGradient;
    final s = brandStops(dark: false);
    return LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [s[1], Color.lerp(s[1], s[2], 0.7)!],
    );
  }

  // Shared building blocks for the gradients above that reuse the same
  // stops under more than one name (primaryGradient in dark mode,
  // primarySliderGradient in light mode, slideBarGradient, etc).
  // LinearGradient get _darkSlideBarGradient => LinearGradient(
  //   begin: Alignment.topCenter,
  //   end: Alignment.bottomCenter,
  //   colors: _model?.gradientDarkSlideBar ?? AppTheme.darkSlideBarGradient.colors,
  // );
  LinearGradient get _darkSlideBarGradient => LinearGradient(
    colors: [_model?.darkCard ?? AppTheme.darkCard,_model?.darkCard ?? AppTheme.darkCard],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  LinearGradient get _sliderGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientSlider ?? AppTheme.sliderGradient.colors,
  );

  // ══════════════════════════════════════════════════════════════════════
  // SHADOWS
  // ══════════════════════════════════════════════════════════════════════

  List<BoxShadow> get cardShadow {
    final base = isDark
        ? (_model?.cardShadowColorDark ?? AppTheme.cardShadowColorDark)
        : (_model?.cardShadowColor ?? AppTheme.cardShadowColor);
    return isDark
        ? [
      BoxShadow(color: base.withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 8)),
      BoxShadow(color: base.withValues(alpha: 0.20), blurRadius: 4, offset: const Offset(0, 2)),
    ]
        : [
      BoxShadow(color: base.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)),
      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
    ];
  }

  List<BoxShadow> get primaryShadow {
    final shadowColor = isDark
        ? (_model?.primaryShadowColorDark ?? AppTheme.primaryShadowColorDark)
        : (_model?.primaryShadowColor ?? AppTheme.primaryShadowColor);
    return [BoxShadow(color: shadowColor, blurRadius: 20, offset: const Offset(0, 8))];
  }

  List<BoxShadow> get dangerShadow => isDark
      ? [BoxShadow(color: danger.withValues(alpha: 0.50), blurRadius: 20, offset: const Offset(0, 6))]
      : [BoxShadow(color: danger.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))];

  List<BoxShadow> get disableShadow => [
    BoxShadow(color: const Color(0x001A1A1A).withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
  ];

  List<BoxShadow> get bottomNavShadow => isDark
      ? [
    BoxShadow(color: Colors.black.withValues(alpha: 0.40), blurRadius: 20, offset: const Offset(0, -4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 8, offset: const Offset(0, -2)),
  ]
      : [
    BoxShadow(color: const Color(0xFF1A1A1A).withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, -2)),
  ];

  // ══════════════════════════════════════════════════════════════════════
  // TEXT STYLES  (font/weight/family are fixed design tokens; only the
  // colour is resolved per mode/config, via the getters above)
  // ══════════════════════════════════════════════════════════════════════

  TextStyle get h1 => AppTheme.h1.copyWith(color: textDark);

  TextStyle get h2 => AppTheme.h2.copyWith(color: textDark);

  TextStyle get h3 => AppTheme.h3.copyWith(color: textDark);

  TextStyle get h4 => AppTheme.h4.copyWith(color: textDark);

  TextStyle get body => AppTheme.body.copyWith(color: textMedium);

  TextStyle get bodyBold => AppTheme.bodyBold.copyWith(color: textDark);

  TextStyle get caption => AppTheme.caption.copyWith(color: textLight);

  TextStyle get label => AppTheme.label.copyWith(color: textMedium);

  /// Button text — white on the indigo primary (readable contrast).
  TextStyle get button => AppTheme.button.copyWith(color: Colors.white);

  TextStyle get buttonSm => AppTheme.buttonSmall.copyWith(color: Colors.white);

  TextStyle get navLabelSelected => AppTheme.navLabelSelected.copyWith(color: primary);

  TextStyle get navLabelUnselected => AppTheme.navLabelUnselected.copyWith(color: textLight);

  // ── Helpers for one-off overrides ─────────────────────────────────────────

  /// Body text in any colour — e.g. `context.themeConfig.bodyColored(primary)`.
  TextStyle bodyColored(Color color) => AppTheme.body.copyWith(color: color);

  /// h3 in any colour.
  TextStyle h3Colored(Color color) => AppTheme.h3.copyWith(color: color);

  /// label at a custom font size.
  TextStyle labelSized(double size) =>
      AppTheme.label.copyWith(fontSize: size, color: textMedium);

  // ══════════════════════════════════════════════════════════════════════
  // MATERIAL THEME  (MaterialApp.theme / darkTheme)
  // ══════════════════════════════════════════════════════════════════════

  /// AppTheme's static ThemeData with the server palette laid on top, so
  /// Material widgets (buttons, tabs, checkboxes, scaffold) follow a live
  /// theme change too — not only widgets that read `context.colors`.
  /// The ONE source of the app's look. Every Material widget in every role (raw dialogs, sheets, buttons,
  /// inputs, chips, switches, snackbars …) inherits these component themes from the LIVE palette chosen by the
  /// super admin — so a screen nobody restyled still looks like the rest of the app (Data Lab design language:
  /// generous radii, tajawal weights, tinted chips, floating snackbars, calm surfaces).
  ThemeData materialTheme({required bool dark}) {
    final base = dark ? AppTheme.darkThemeData : AppTheme.themeData;
    final m = _model;
    final p = m?.primary ?? AppTheme.primary;
    final pLight = m?.primaryLight ?? AppTheme.primaryLight;
    final danger = m?.danger ?? AppTheme.danger;
    final success = m?.success ?? AppTheme.success;
    final accent2 = m?.accent2 ?? AppTheme.accent2;
    final bg = m == null ? base.scaffoldBackgroundColor : (dark ? m.darkBackground : m.background);
    final card = m == null ? base.cardColor : (dark ? m.darkCard : m.cardBg);
    final surface = m == null ? base.colorScheme.surface : (dark ? m.darkSurface : m.surfaceCard);
    final divider = m == null ? base.dividerColor : (dark ? m.darkDivider : m.divider);
    final input = m == null ? (base.inputDecorationTheme.fillColor ?? card) : (dark ? m.inputBgDark : m.inputBg);
    final text = m == null ? (dark ? Colors.white : const Color(0xFF1F2430)) : (dark ? m.darkTextPrimary : m.textDark);
    final muted = m == null ? Colors.grey : (dark ? m.darkTextMuted : m.textMedium);
    final faint = m == null ? Colors.grey : (dark ? m.darkTextLight : m.textLight);
    final ink = m?.charcoal ?? const Color(0xFF1F2430);
    // The primary as TEXT on the page / card / sheet surfaces (text and outlined buttons): the raw indigo is about
    // 2:1 on the dark surfaces, so its lightness is moved until it reaches WCAG AA (4.5:1) on all of them, hue
    // kept. A primary that already passes (the light theme) is unchanged. Fills and borders keep the raw primary.
    final pText = ensureContrast(p, [bg, card, surface]);
    // The same for a selected chip's label and check: it sits on the 14 % primary tint, where the raw indigo was
    // 1.9:1 in dark (every selected ChoiceChip / FilterChip); light is unchanged (6.6:1 already).
    final chipTint = p.withValues(alpha: 0.14);
    final pOnChip = ensureContrast(p, [for (final s in [bg, card, surface, input]) Color.alphaBlend(chipTint, s)]);

    TextStyle ts(double size, [FontWeight w = FontWeight.w600, Color? c]) =>
        TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: c);
    // D-136: a Filled / Elevated button whose fill IS the brand primary (the theme default, or a screen that asks
    // for `backgroundColor: c.primary`) is painted with the brand gradient; any other fill (danger, success, a
    // tint, the disabled well) keeps its own colour. The gradient is an Ink on the button's own Material, so the
    // ripple, hover and focus overlays still draw on top of it.
    final brand = _brand(brandStops(dark: dark));
    final brandPressed = primaryGradientPressedFor(dark: dark);
    final gloss = LinearGradient(
      begin: Alignment.topCenter,
      end: const Alignment(0, -0.38),
      colors: [Colors.white.withValues(alpha: dark ? 0.12 : 0.2), Colors.white.withValues(alpha: 0)],
    );
    Widget brandFill(BuildContext context, Set<WidgetState> states, Widget? child) {
      if (states.contains(WidgetState.disabled)) return child ?? const SizedBox.shrink();
      return Builder(builder: (context) {
        // the button's own Material (the nearest one above this builder): its colour says whether this is a brand
        // fill, its shape clips the gradient (a FilledButton does not clip its Material by default)
        final m = context.findAncestorWidgetOfExactType<Material>();
        if (m == null || m.color != p) return child ?? const SizedBox.shrink();
        final shape = m.shape;
        return Ink(
          decoration: ShapeDecoration(
            shape: shape is OutlinedBorder ? shape.copyWith(side: BorderSide.none) : (shape ?? const RoundedRectangleBorder()),
            gradient: states.contains(WidgetState.pressed) ? brandPressed : brand,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: shape is OutlinedBorder ? shape.copyWith(side: BorderSide.none) : (shape ?? const RoundedRectangleBorder()),
              gradient: gloss,
            ),
            child: child,
          ),
        );
      });
    }
    final r14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    WidgetStateProperty<Color?> on(Color sel, Color off) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? sel : off);
    OutlineInputBorder ob(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      cardColor: card,
      dividerColor: divider,
      colorScheme: base.colorScheme.copyWith(
        primary: p,
        onPrimary: Colors.white,
        primaryContainer: p.withValues(alpha: 0.12),
        onPrimaryContainer: p,
        secondary: accent2,
        tertiary: success,
        error: danger,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        outline: divider,
        outlineVariant: divider,
      ),
      textSelectionTheme: TextSelectionThemeData(
          cursorColor: p, selectionColor: p.withValues(alpha: 0.25), selectionHandleColor: p),
      // ── buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? divider : p),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(r14),
          textStyle: WidgetStatePropertyAll(ts(14.5, FontWeight.w800)),
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          elevation: const WidgetStatePropertyAll(0),
          backgroundBuilder: brandFill,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.withValues(alpha: 0.35),
          shape: r14,
          minimumSize: const Size(64, 48),
          textStyle: ts(14.5, FontWeight.w800),
          backgroundBuilder: brandFill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: pText,
          side: BorderSide(color: p.withValues(alpha: 0.45), width: 1.3),
          shape: r14,
          minimumSize: const Size(64, 48),
          textStyle: ts(14, FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: pText, shape: r14, textStyle: ts(13.5, FontWeight.w700)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: text)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: ts(14, FontWeight.w800),
      ),
      // ── inputs & selection ──
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: input,
        labelStyle: ts(13, FontWeight.w500, muted),
        hintStyle: ts(13, FontWeight.w400, faint),
        floatingLabelStyle: ts(13, FontWeight.w700, p),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: ob(divider),
        enabledBorder: ob(divider),
        focusedBorder: ob(p, 1.6),
        errorBorder: ob(danger),
        focusedErrorBorder: ob(danger, 1.6),
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        fillColor: on(p, Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(fillColor: on(p, faint)),
      switchTheme: SwitchThemeData(
        thumbColor: on(Colors.white, Colors.white),
        trackColor: on(p, divider),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        // Safety net for any stray Material Switch: same white knob + check as AppSwitch.
        thumbIcon: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Icon(Icons.check_rounded, size: 14, color: p) : null),
      ),
      sliderTheme: base.sliderTheme.copyWith(
          activeTrackColor: p, thumbColor: p, inactiveTrackColor: p.withValues(alpha: 0.18)),
      chipTheme: ChipThemeData(
        backgroundColor: input,
        selectedColor: chipTint,
        secondarySelectedColor: chipTint,
        checkmarkColor: pOnChip,
        side: BorderSide(color: divider),
        shape: const StadiumBorder(),
        labelStyle: ts(12.5, FontWeight.w600, text),
        secondaryLabelStyle: ts(12.5, FontWeight.w800, pOnChip),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: p, linearTrackColor: p.withValues(alpha: 0.14), circularTrackColor: Colors.transparent),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: p,
        indicatorColor: p,
        unselectedLabelColor: muted,
        labelStyle: ts(13.5, FontWeight.w800),
        unselectedLabelStyle: ts(13.5, FontWeight.w500),
      ),
      // ── surfaces ──
      cardTheme: base.cardTheme.copyWith(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: divider)),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: ts(18, FontWeight.w800, text),
        contentTextStyle: ts(14, FontWeight.w500, muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        modalBackgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxWidth: 720),     // comfortable on tablets & web
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: ts(13.5, FontWeight.w600, text),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? card : ink,
        contentTextStyle: ts(13.5, FontWeight.w600, Colors.white),
        actionTextColor: pLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: ink.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(10)),
        textStyle: ts(12, FontWeight.w600, Colors.white),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: ts(14, FontWeight.w700, text),
        subtitleTextStyle: ts(12.5, FontWeight.w500, muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: divider, space: 1),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        headerBackgroundColor: p,
        headerForegroundColor: Colors.white,
        todayBorder: BorderSide(color: p),
      ),
    );
  }

  // ── Network ───────────────────────────────────────────────────────────────

  /// Returns true on success (model populated + cached), false on failure.
  /// The theme request started while the app is still starting (main.dart's `_initCore`, D-171): the first fetch takes
  /// it instead of asking again, so the first real frame no longer waits for the start-up steps AND then the request.
  static Future<dynamic>? _early;

  static void prefetch(ApiClient api) {
    if (_early != null) return;
    final f = api.get('/api/v1/theme/$_currentPlatform').timeout(const Duration(seconds: 30));
    f.ignore(); // a failure is the first fetch's to handle
    _early = f;
  }

  Future<bool> _fetchFromServer({bool silent = false}) async {
    try {
      final early = _early;
      _early = null;
      final platform = _currentPlatform;
      final json = await (early ?? _api
          .get('/api/v1/theme/$platform')
          .timeout(const Duration(seconds: 30))) as Map<String, dynamic>;
      final colors = json['colors'] as Map<String, dynamic>;
      _model = ThemeConfigModel.fromJson(colors);

      final disableItems = (json['disable_list'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final platformSettings = json['platform_settings'] is Map
          ? Map<String, dynamic>.from(json['platform_settings'] as Map)
          : <String, dynamic>{};
      _applyPlatformSettings(platformSettings);
      AppConfig.setDisableList(disableItems);

      await _saveCache(_model!, disableItems, platformSettings);
      _serverUnreachable = false;
      _error = null;
      _lastFetchAt = DateTime.now();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[ThemeConfigProvider] fetch error: $e');
      if (silent) return false; // keep the current palette, no banner
      _error = e.toString();
      _serverUnreachable = true;
      notifyListeners();
      return false;
    }
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  /// Reads the last-known-good palette (and disable list) back out of
  /// SharedPreferences. Called first on every launch.
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getString(_kCacheKey);
      if (raw != null) {
        _model = ThemeConfigModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }

      final platformRaw = prefs.getString(_kPlatformCacheKey);
      if (platformRaw != null) {
        final decoded = jsonDecode(platformRaw);
        if (decoded is Map) _applyPlatformSettings(Map<String, dynamic>.from(decoded));
      } else {
        _applyPlatformSettings(const {}); // new install: Africa/Cairo · 12h until the server answers
      }

      final disableRaw = prefs.getString(_kDisableListCacheKey);
      if (disableRaw != null) {
        AppConfig.setDisableList((jsonDecode(disableRaw) as List<dynamic>)
            .map((e) => e.toString())
            .toList());
      }
    } catch (e) {
      debugPrint('[ThemeConfigProvider] cache load error: $e');
    }
  }

  Future<void> _saveCache(ThemeConfigModel model, List<String> disableItems,
      Map<String, dynamic> platformSettings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, jsonEncode(model.toJson()));
      await prefs.setString(_kDisableListCacheKey, jsonEncode(disableItems));
      if (platformSettings.isNotEmpty) {
        await prefs.setString(_kPlatformCacheKey, jsonEncode(platformSettings));
      }
    } catch (e) {
      debugPrint('[ThemeConfigProvider] cache save error: $e');
    }
  }

  // ── Platform settings (super admin) ───────────────────────────────────────

  /// Last `platform` block of the theme response: {orgs_enabled, timezone, time_format, org_creation_fee}.
  Map<String, dynamic> _platform = const {};
  Map<String, dynamic> get platformSettings => _platform;

  /// Organization creation fee as the server announced it ({required, amount, currency, methods}).
  Map<String, dynamic> get orgCreationFee =>
      _platform['org_creation_fee'] is Map ? Map<String, dynamic>.from(_platform['org_creation_fee'] as Map) : const {};

  /// Applies the organizations master switch and the platform timezone / time format. An old server that
  /// sends no `platform` block keeps organizations ON and the Cairo / 12h defaults.
  void _applyPlatformSettings(Map<String, dynamic> p) {
    if (p.isNotEmpty) _platform = p;
    AppTime.configurePlatform(
      zone: (p['timezone'] as String?) ?? AppTime.fallbackZone,
      timeFormat: (p['time_format'] as String?) ?? '12h',
    );
    AppConfig.setOrgsEnabled(p['orgs_enabled'] != false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext extension — context.themeConfig anywhere in the widget tree.
// This is the ONLY theme accessor in the app (context.colors was removed).
// ─────────────────────────────────────────────────────────────────────────────

extension ThemeConfigX on BuildContext {
  ThemeConfigProvider get colors {
    final provider = _ThemeConfigScope.of(this);
    provider.isDark = Theme.of(this).brightness == Brightness.dark;
    return provider;
  }
}

/// Internal InheritedWidget that avoids a full Provider dependency
/// (works seamlessly alongside your existing MultiProvider setup).
class _ThemeConfigScope extends InheritedNotifier<ThemeConfigProvider> {
  const _ThemeConfigScope({
    required ThemeConfigProvider notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ThemeConfigProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeConfigScope>();
    assert(scope != null,
    'ThemeConfigProvider not found. Wrap your app with ThemeConfigScope.');
    return scope!.notifier!;
  }
}

/// Wrap your widget tree (or MaterialApp) with this to expose
/// `context.themeConfig` everywhere below.
///
/// ```dart
/// ThemeConfigScope(
///   provider: context.read<ThemeConfigProvider>(),
///   child: MaterialApp(...),
/// )
/// ```
class ThemeConfigScope extends StatelessWidget {
  final ThemeConfigProvider provider;
  final Widget child;

  const ThemeConfigScope({
    super.key,
    required this.provider,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => _ThemeConfigScope(
    notifier: provider,
    child: child,
  );
}