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
import 'dart:math' as math;
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

  /// The canvas. Dark mode uses `dark_background` (D-610): it used to be the card tone at 90 %, so a card on the page
  /// had no tone step under it, and depth is tone first (canvas → paper card → tinted block).
  Color get background => isDark
      ? (_model?.darkBackground ?? AppTheme.darkBackground)
      : (_model?.background ?? AppTheme.background);

  /// [background] made opaque, for a pinned header (a tab strip) that content scrolls under. Blended over the
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
  // BLOCKS (D-610, D-613, D-630) — the tinted containers that group one subject (AppBlock). Peach is `accent`
  // (accent1), sky (now sage) is `accent3` (derived when the theme sends none), forest the one home hero, gold is a tint of accent2, emerald a tint of the primary.
  // Dark mode: each becomes a dark surface tinted with its hue. Ink on every block keeps WCAG AA: [blockInk] /
  // [blockMuted] / [blockFaint], and [blockAccentInk] darkens gold / success / warning until they read as text.
  // ══════════════════════════════════════════════════════════════════════

  /// The sage block tone (`accent3`, the API keeps the old name `sky`; D-630), light mode: the theme's `accent3`,
  /// else [deriveAccent3] from this palette. The warm_editorial preset's first value, the cool sky #DCE7F5, clashed
  /// with the warm canvas: a server that still sends exactly it gets the sage that replaced it.
  Color get accent3 {
    final m = _model;
    if (m == null) return AppTheme.accent3;
    final sent = m.accent3;
    if (sent != null && sent.toARGB32() != _retiredSky) return sent;
    return _accent3Cache[m] ??= deriveAccent3(primary: m.primary, background: m.background, ink: m.textLight);
  }

  /// The retired cool sky of the first warm_editorial preset (see [accent3]).
  static const int _retiredSky = 0xFFDCE7F5;

  final Map<ThemeConfigModel, Color> _accent3Cache = {};

  /// A sage block tone for a palette without `accent3`: a pale grey-green (hue 120, about the default preset's
  /// #E4ECE3) turned 15 % toward the primary's hue and mixed 15 % into the canvas so it sits in the same warm light,
  /// then lightened until the caption ink [ink] still reads at AA on it.
  static Color deriveAccent3({required Color primary, required Color background, required Color ink}) {
    final ph = HSLColor.fromColor(primary);
    var d = ((ph.hue - 120 + 540) % 360) - 180; // the shortest way from 120° to the primary's hue
    if (ph.saturation < 0.12) d = 0; // a grey primary has no hue to lean toward
    final sage = HSLColor.fromAHSL(1, (120 + d * 0.15) % 360, 0.2, 0.9).toColor();
    return blockSurface(Color.lerp(sage, background, 0.15)!, ink);
  }

  /// [c] made into a light block surface: at least 0.86 lightness, at most 0.85 saturation, and light enough for
  /// [ink] at AA (a theme whose accent is a saturated mid tone still gets a calm block).
  static Color blockSurface(Color c, Color ink) {
    var h = HSLColor.fromColor(c.withValues(alpha: 1));
    if (h.lightness < 0.86) h = h.withLightness(0.9);
    if (h.saturation > 0.85) h = h.withSaturation(0.85);
    while (contrastRatio(ink, h.toColor()) < kWcagAaText && h.lightness < 0.975) {
      h = h.withLightness(h.lightness + 0.005);
    }
    return h.toColor();
  }

  /// A block's dark-mode surface: the hue of [tone] on a deep, low-saturation tone, a step above the dark card.
  static Color darkBlock(Color tone) {
    final h = HSLColor.fromColor(tone);
    final sat = h.saturation < 0.08 ? h.saturation : 0.3;
    return HSLColor.fromAHSL(1, h.hue, sat, 0.18).toColor();
  }

  Color get _lightInk => _model?.textLight ?? AppTheme.textLight;

  /// Peach: learning / progress blocks (`accent`).
  Color get blockPeach {
    final light = blockSurface(accent, _lightInk);
    return isDark ? darkBlock(light) : light;
  }

  /// Sage (the `sky` tone's new colour, D-630): schedule / information / calm empty blocks (`accent3`). Dark mode
  /// keeps it a quiet grey-green (about #1E2A23), not the saturated step [darkBlock] gives the other tones.
  Color get blockSky {
    final light = blockSurface(accent3, _lightInk);
    if (!isDark) return light;
    final h = HSLColor.fromColor(light);
    return HSLColor.fromAHSL(1, h.hue, math.min(h.saturation, 0.17), 0.145).toColor();
  }

  /// Gold: streaks, achievements, top marks (a tint of accent2; about #F6E7C4 for the editorial preset).
  Color get blockGold {
    final g = HSLColor.fromColor(accent2);
    final light = blockSurface(
        g.withSaturation((g.saturation * 1.08).clamp(0.0, 0.85)).withLightness(0.87).toColor(), _lightInk);
    return isDark ? darkBlock(light) : light;
  }

  /// Emerald: done / correct / the primary subject (a tint of the primary).
  Color get blockEmerald {
    final p = HSLColor.fromColor(primary);
    final light = blockSurface(p.withSaturation(p.saturation.clamp(0.0, 0.42)).withLightness(0.9).toColor(), _lightInk);
    return isDark ? darkBlock(light) : light;
  }

  /// The signature hero (D-630): ONE deep forest block per home, from the theme's `primary_dark` — its hue, the
  /// saturation held at 0.62 and the lightness at most 0.145, then deepened until the cream ink reads at 7:1 (about
  /// #0E3B2E for the default preset). Dark mode lifts it a step (about #14392D) so it still stands off the dark canvas.
  Color get blockForest {
    final light = _forestCache[(primaryDark, heroInk)] ??= deriveForest(primaryDark, heroInk);
    if (!isDark) return light;
    final h = HSLColor.fromColor(light);
    return h.withSaturation(math.min(h.saturation, 0.48)).withLightness(math.max(h.lightness, 0.15)).toColor();
  }

  final Map<(Color, Color), Color> _forestCache = {};

  /// [primaryDark] made into the forest hero for [ink] (see [blockForest]).
  static Color deriveForest(Color primaryDark, Color ink) {
    var h = HSLColor.fromColor(primaryDark.withValues(alpha: 1));
    h = h.withSaturation(math.min(h.saturation, 0.62)).withLightness(math.min(h.lightness, 0.145));
    while (contrastRatio(ink, h.toColor()) < 7 && h.lightness > 0.02) {
      h = h.withLightness(h.lightness - 0.005);
    }
    return h.toColor();
  }

  /// Ink on the forest hero: the LIGHT canvas cream in both modes.
  Color get heroInk => _model?.background ?? AppTheme.background;

  /// Secondary ink on the forest hero: cream at 78 % (about 9:1), raised until it keeps AA.
  Color get heroInkMuted => ensureContrast(Color.alphaBlend(heroInk.withValues(alpha: _hc ? 0.92 : 0.78), blockForest), [blockForest]);

  /// Caption ink on the forest hero: cream at 66 %, at AA.
  Color get heroInkFaint => ensureContrast(Color.alphaBlend(heroInk.withValues(alpha: _hc ? 0.85 : 0.66), blockForest), [blockForest]);

  /// Main ink on a block (titles, figures): `text_dark` / `dark_text_primary`.
  Color get blockInk => textDark;

  /// Secondary ink on [block], at AA.
  Color blockMuted(Color block) => ensureContrast(textMedium, [block]);

  /// Caption ink on [block], at AA.
  Color blockFaint(Color block) => ensureContrast(textLight, [block]);

  /// [accent] (gold, success, warning, danger, the primary) as TEXT on [block]: the same hue, darkened (lifted in
  /// dark mode) until it reaches AA. Gold / success / warning are only 2.9 – 4.3:1 on the light blocks as they come.
  Color blockAccentInk(Color accent, Color block) => ensureContrast(accent, [block]);

  /// The one shadow tone (system.md §4): the theme's `card_shadow_color` (warm charcoal) in light mode, black in dark.
  Color get shadowTone => isDark
      ? (_model?.cardShadowColorDark ?? AppTheme.cardShadowColorDark)
      : (_model?.cardShadowColor ?? AppTheme.cardShadowColor);

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
  // 0.90: at 0.72 a subtitle on a hero stop that just passes AA fell to about 3:1 (the a11y guideline test found it)
  Color get onHeroMuted => onHero.withValues(alpha: _hc ? 0.96 : 0.9);

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
  //
  // D-622 (the editorial theme): the fill stays in ONE family — primary_light → primary → primary_dark — with no hue
  // turn at either end (the old sweep drifted from emerald into blue and the warm glow turned olive). The gradient
  // is a touch again (a button, the selected tab, a page header's band); heroes are tinted blocks (AppBlock).

  /// The three stops of the brand fill in [dark] mode: lift (toward primary_light) · primary · deep (toward
  /// primary_dark). All three the primary's own hue.
  List<Color> brandStops({required bool dark}) {
    final key = Object.hash(_model, dark, onHero);
    final hit = _stopCache[key];
    if (hit != null) return hit;
    final ink = onHero;
    Color safe(Color c) => ensureContrast(c, [ink], min: _kBrandInk);
    final mid = safe(primary);
    // light: up to 55 % of the way to primary_light; dark: a shorter lift (a bright edge glares on a dark page)
    final lift = _model?.primaryGradientStart != null
        ? safe(_model!.primaryGradientStart!)
        : safe(_liftToward(mid, primaryLight, dark ? 0.35 : 0.55, ink));
    // the deep end: primary_dark (a server stop wins); dark mode stops short of it so the fill still separates from
    // the dark page around it
    final deepBase = _model?.primaryGradientEnd ?? _settle(primaryDark, mid);
    final deep = safe(dark ? Color.lerp(mid, deepBase, 0.7)! : deepBase);
    if (_stopCache.length > 8) _stopCache.clear();
    return _stopCache[key] = [lift, mid, deep];
  }

  /// [deep] kept in [mid]'s family: the same hue (a palette whose primary_dark drifted toward another hue is pulled
  /// back), at least a shade darker than [mid] so the gradient reads at all.
  static Color _settle(Color deep, Color mid) {
    final m = HSLColor.fromColor(mid);
    var d = HSLColor.fromColor(deep).withHue(m.hue);
    if (d.lightness > m.lightness * 0.82) d = d.withLightness((m.lightness * 0.72).clamp(0.0, 1.0));
    return d.toColor();
  }

  static const double _kBrandInk = 5.5; // so onHeroMuted (90 % ink) still reads at WCAG AA on every stop
  final Map<int, List<Color>> _stopCache = {};

  /// [from] moved toward [to] by at most [maxT], as far as [ink] keeps [_kBrandInk] on it.
  static Color _liftToward(Color from, Color to, double maxT, Color ink) {
    for (var t = maxT; t > 0; t -= 0.01) {
      final c = Color.lerp(from, to, t)!;
      if (contrastRatio(ink, c) >= _kBrandInk) return c;
    }
    return from;
  }

  // D-622: one family, three shades (lift · primary · deep) on a 135° sweep, start → end. Every stop passes the ink
  // check (the stops come from [brandStops]).
  LinearGradient _brand(List<Color> stops) => LinearGradient(
    begin: const AlignmentDirectional(-1, -0.7),
    end: const AlignmentDirectional(1, 0.5),
    colors: [stops[0], stops[1], stops[2]],
    stops: const [0, 0.5, 1],
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

  /// A faint light for the top-end corner of a hero gradient: the family's lift stop (D-622: the old accent2 glow
  /// turned olive on emerald), at most as strong as the on-hero ink allows over every hero stop.
  RadialGradient get heroGlow {
    final stops = heroGradient.colors;
    final light = brandStops(dark: isDark).first;
    var a = 0.22;
    while (a > 0 && stops.any((s) => contrastRatio(onHero, Color.alphaBlend(light.withValues(alpha: a), s)) < _kBrandInk)) {
      a -= 0.02;
    }
    return RadialGradient(
      center: AlignmentDirectional.topEnd,
      radius: 1.1,
      colors: [light.withValues(alpha: a.clamp(0.0, 1.0)), light.withValues(alpha: 0)],
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
    // level 1 (D-612): a whisper in the warm shadow tone; a resting card leans on tone + hairline instead
    return isDark
        ? [
      BoxShadow(color: base.withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 6)),
      BoxShadow(color: base.withValues(alpha: 0.16), blurRadius: 3, offset: const Offset(0, 1)),
    ]
        : [
      BoxShadow(color: base.withValues(alpha: 0.035), blurRadius: 16, offset: const Offset(0, 6)),
      BoxShadow(color: base.withValues(alpha: 0.03), blurRadius: 3, offset: const Offset(0, 1)),
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
    BoxShadow(color: shadowTone.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 6)),
    BoxShadow(color: shadowTone.withValues(alpha: 0.02), blurRadius: 3, offset: const Offset(0, 1)),
  ];

  List<BoxShadow> get bottomNavShadow => isDark
      ? [
    BoxShadow(color: Colors.black.withValues(alpha: 0.40), blurRadius: 20, offset: const Offset(0, -4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 8, offset: const Offset(0, -2)),
  ]
      : [
    BoxShadow(color: shadowTone.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4)),
    BoxShadow(color: shadowTone.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, -2)),
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

  /// Button text — white on the emerald primary (readable contrast).
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
    final pDark = m?.primaryDark ?? AppTheme.primaryDark;
    final pLight = m?.primaryLight ?? AppTheme.primaryLight;
    final danger = m?.danger ?? AppTheme.danger;
    final accent2 = m?.accent2 ?? AppTheme.accent2;
    final bg = dark ? (m?.darkBackground ?? AppTheme.darkBackground) : (m?.background ?? AppTheme.background);
    final card = dark ? (m?.darkCard ?? AppTheme.darkCard) : (m?.cardBg ?? AppTheme.cardBg);
    final surface = dark ? (m?.darkSurface ?? AppTheme.darkSurface) : (m?.surfaceCard ?? AppTheme.surfaceCard);
    final divider = dark ? (m?.darkDivider ?? AppTheme.darkDivider) : (m?.divider ?? AppTheme.divider);
    final input = dark ? (m?.inputBgDark ?? AppTheme.inputBgDark) : (m?.inputBg ?? AppTheme.inputBg);
    final text = dark ? (m?.darkTextPrimary ?? AppTheme.darkTextPrimary) : (m?.textDark ?? AppTheme.textDark);
    final muted = dark ? (m?.darkTextMuted ?? AppTheme.darkTextMuted) : (m?.textMedium ?? AppTheme.textMedium);
    final faint = dark ? (m?.darkTextLight ?? AppTheme.darkTextLight) : (m?.textLight ?? AppTheme.textLight);
    final ink = m?.charcoal ?? AppTheme.charcoal;
    final shadow = dark ? (m?.cardShadowColorDark ?? AppTheme.cardShadowColorDark) : (m?.cardShadowColor ?? AppTheme.cardShadowColor);
    final heroInk = onHero;
    // The primary as TEXT on the page / card / sheet surfaces (text and outlined buttons, the focus ring, the selected
    // tab): the raw primary is about 2:1 on the dark surfaces, so its lightness is moved until it reaches WCAG AA
    // (4.5:1) on all of them, hue kept. A primary that already passes (the light theme) is unchanged. Fills keep
    // the raw primary (white ink on it).
    final pText = ensureContrast(p, [bg, card, surface, input]);
    // The same for a selected chip's label and check: it sits on the 14 % primary tint.
    final chipTint = p.withValues(alpha: 0.14);
    final pOnChip = ensureContrast(p, [for (final s in [bg, card, surface, input]) Color.alphaBlend(chipTint, s)]);

    // ── blocks, mode by mode (the getters read [isDark]) ──
    final wasDark = isDark;
    isDark = dark;
    final peach = blockPeach, gold = blockGold, emerald = blockEmerald;
    isDark = wasDark;

    // ── Material 3 colour roles (D-610): a strict scheme from the palette, so dialogs, menus, date pickers, chips,
    // the FAB and every other Material widget wear the theme without a per-widget colour. ──
    // light: paper is the lightest surface, the canvas a step down, the input well the deepest;
    // dark: the canvas is the deepest, paper a step up, the input well the highest.
    final lowest = dark ? bg : card;
    final highest = input;
    final mid = dark ? Color.lerp(surface, card, 0.5)! : bg;
    final errorContainer = dark ? darkBlock(danger) : Color.lerp(card, danger, 0.1)!;
    // the dark primary role is the AA-lifted one (selection, focus, a date picker's chosen day on a dark sheet);
    // its ink is whichever of the two inks reads better on it
    final schemePrimary = dark ? pText : p;
    Color inkOn(Color fill) =>
        contrastRatio(heroInk, fill) >= contrastRatio(ink, fill) ? heroInk : (m?.charcoalDark ?? AppTheme.charcoalDark);
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: schemePrimary,
      onPrimary: inkOn(schemePrimary),
      primaryContainer: emerald,
      onPrimaryContainer: ensureContrast(dark ? pLight : pDark, [emerald]),
      secondary: dark ? muted : (m?.charcoalLight ?? AppTheme.charcoalLight),
      onSecondary: dark ? bg : heroInk,
      secondaryContainer: peach,
      onSecondaryContainer: text,
      tertiary: ensureContrast(accent2, [bg, card]),
      onTertiary: inkOn(ensureContrast(accent2, [bg, card])),
      tertiaryContainer: gold,
      onTertiaryContainer: ensureContrast(accent2, [gold]),
      error: ensureContrast(danger, [bg, card]),
      onError: inkOn(ensureContrast(danger, [bg, card])),
      errorContainer: errorContainer,
      onErrorContainer: ensureContrast(danger, [errorContainer]),
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceDim: dark ? bg : Color.lerp(bg, input, 0.5)!,
      surfaceBright: dark ? Color.lerp(card, input, 0.5)! : card,
      surfaceContainerLowest: lowest,
      surfaceContainerLow: Color.lerp(lowest, mid, 0.5)!,
      surfaceContainer: mid,
      surfaceContainerHigh: Color.lerp(mid, highest, 0.5)!,
      surfaceContainerHighest: highest,
      surfaceTint: Colors.transparent, // tone comes from the palette, never from an elevation tint
      outline: Color.lerp(divider, faint, 0.45)!,
      outlineVariant: divider,
      shadow: shadow,
      scrim: m?.charcoalDark ?? AppTheme.charcoalDark,
      inverseSurface: dark ? text : ink,
      onInverseSurface: dark ? bg : card,
      inversePrimary: dark ? p : pLight,
    );

    TextStyle ts(double size, [FontWeight w = FontWeight.w600, Color? c]) =>
        TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: c);
    // D-611: headings in the editorial face (or the text font, "Headings: Same as text"), sized as AppType does
    final editorial = AppFonts.editorialHeadings;
    final scale = editorial ? AppFonts.editorialScale() : 1.0;
    final ar = AppConfig.lang == 'ar';
    TextStyle? head(TextStyle? s, double optical) => s?.copyWith(
          fontFamily: AppFonts.editorial,
          fontFamilyFallback: AppFonts.editorialFallback,
          fontSize: editorial ? (optical * scale).roundToDouble() : s.fontSize,
          fontWeight: FontWeight.w600,
          height: editorial ? (ar ? 1.3 : 1.15) : s.height,
          letterSpacing: ar ? 0 : (editorial ? -optical * scale * 0.01 : s.letterSpacing),
          color: text,
        );
    final tt = base.textTheme;
    final textTheme = tt.copyWith(
      displayLarge: head(tt.displayLarge, 44),
      displayMedium: head(tt.displayMedium, 38),
      displaySmall: head(tt.displaySmall, 32),
      headlineLarge: head(tt.headlineLarge, 28),
      headlineMedium: head(tt.headlineMedium, 24),
      headlineSmall: head(tt.headlineSmall, 22),
      titleLarge: head(tt.titleLarge, 20),
    );
    TextStyle heading(double optical, double sans) => editorial
        ? TextStyle(
            fontFamily: AppFonts.editorialFamily,
            fontFamilyFallback: AppFonts.editorialFallback,
            fontSize: (optical * scale).roundToDouble(),
            fontWeight: FontWeight.w600,
            height: ar ? 1.3 : 1.15,
            color: text)
        : ts(sans, FontWeight.w600, text);

    // D-136: a Filled / Elevated button whose fill IS the brand primary (the theme default, or a screen that asks
    // for `backgroundColor: c.primary`) is painted with the brand gradient; any other fill (danger, success, a
    // tint, the disabled well) keeps its own colour. The gradient is an Ink on the button's own Material, so the
    // ripple, hover and focus overlays still draw on top of it.
    final brand = _brand(brandStops(dark: dark));
    final brandPressed = primaryGradientPressedFor(dark: dark);
    final gloss = LinearGradient(
      begin: Alignment.topCenter,
      end: const Alignment(0, -0.38),
      colors: [heroInk.withValues(alpha: dark ? 0.12 : 0.2), heroInk.withValues(alpha: 0)],
    );
    // FilledButton.tonal shares the one FilledButtonTheme with FilledButton, so the theme's `backgroundColor: p`
    // would force the primary fill (and white ink) on it too. Its own M3 default (secondaryContainer) tells it
    // apart; it gets the kit's tonal look instead: the emerald tint with emerald ink (system.md §4).
    final tonalFill = Color.alphaBlend(chipTint, dark ? card : bg);
    Widget brandFill(BuildContext context, Set<WidgetState> states, Widget? child) {
      if (states.contains(WidgetState.disabled)) return child ?? const SizedBox.shrink();
      return Builder(builder: (context) {
        // the button's own Material (the nearest one above this builder): its colour says whether this is a brand
        // fill, its shape clips the gradient (a FilledButton does not clip its Material by default)
        final m = context.findAncestorWidgetOfExactType<Material>();
        if (m == null || m.color != p) return child ?? const SizedBox.shrink();
        final shape = m.shape;
        final button = context.findAncestorWidgetOfExactType<FilledButton>();
        final tonal = button != null &&
            button.defaultStyleOf(context).backgroundColor?.resolve(const {}) == scheme.secondaryContainer;
        if (tonal) {
          final lit = states.contains(WidgetState.pressed) || states.contains(WidgetState.hovered);
          return Ink(
            decoration: ShapeDecoration(
              shape: shape is OutlinedBorder ? shape.copyWith(side: BorderSide.none) : (shape ?? const RoundedRectangleBorder()),
              color: lit ? Color.lerp(tonalFill, pOnChip, 0.08) : tonalFill,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: pOnChip),
              child: IconTheme.merge(data: IconThemeData(color: pOnChip), child: child ?? const SizedBox.shrink()),
            ),
          );
        }
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

    // ── component geometry (D-612): controls 14 · cards 16 · sheets and dialogs 28; 48 px targets ──
    final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl));
    const buttonSize = Size(64, 48);
    const buttonPad = EdgeInsets.symmetric(horizontal: 24);
    final buttonText = ts(15, FontWeight.w600);
    WidgetStateProperty<Color?> on(Color sel, Color off) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? sel : off);
    OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl), borderSide: BorderSide(color: c, width: w));
    // a 2 px focus ring in the primary for keyboard focus on any button
    WidgetStateProperty<BorderSide?> focusSide([BorderSide? rest]) => WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused) ? BorderSide(color: pText, width: 2) : rest);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: card,
      dividerColor: divider,
      shadowColor: shadow,
      colorScheme: scheme,
      textTheme: textTheme,
      textSelectionTheme: TextSelectionThemeData(
          cursorColor: pText, selectionColor: p.withValues(alpha: 0.25), selectionHandleColor: p),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        titleTextStyle: heading(22, 20),
        iconTheme: IconThemeData(color: text),
      ),
      // ── buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? divider : p),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? faint : heroInk),
          shape: WidgetStatePropertyAll(control),
          textStyle: WidgetStatePropertyAll(buttonText),
          minimumSize: const WidgetStatePropertyAll(buttonSize),
          padding: const WidgetStatePropertyAll(buttonPad),
          elevation: const WidgetStatePropertyAll(0),
          side: focusSide(),
          backgroundBuilder: brandFill,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p,
          foregroundColor: heroInk,
          disabledBackgroundColor: divider,
          disabledForegroundColor: faint,
          shape: control,
          minimumSize: buttonSize,
          padding: buttonPad,
          textStyle: buttonText,
          backgroundBuilder: brandFill,
        ).copyWith(side: focusSide()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: pText,
          shape: control,
          minimumSize: buttonSize,
          padding: buttonPad,
          textStyle: buttonText,
        ).copyWith(side: focusSide(BorderSide(color: Color.lerp(divider, pText, 0.45)!, width: 1.2))),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: pText,
          shape: control,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: ts(14, FontWeight.w600),
        ).copyWith(side: focusSide()),
      ),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: text, minimumSize: const Size(48, 48))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p,
        foregroundColor: heroInk,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        extendedTextStyle: buttonText,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(control),
          textStyle: WidgetStatePropertyAll(ts(13.5, FontWeight.w600)),
          side: WidgetStatePropertyAll(BorderSide(color: divider)),
          backgroundColor: on(emerald, Colors.transparent),
          foregroundColor: on(ensureContrast(pText, [emerald]), muted),
        ),
      ),
      // ── inputs & selection: a warm inset well, a hairline at rest, a 2 px primary ring on focus ──
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: input,
        labelStyle: ts(13.5, FontWeight.w500, muted),
        hintStyle: ts(14, FontWeight.w400, faint),
        helperStyle: ts(12, FontWeight.w400, faint),
        floatingLabelStyle: ts(13.5, FontWeight.w600, pText),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: ob(divider),
        enabledBorder: ob(divider),
        disabledBorder: ob(divider.withValues(alpha: 0.6)),
        focusedBorder: ob(pText, 2),
        errorBorder: ob(scheme.error),
        focusedErrorBorder: ob(scheme.error, 2),
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        fillColor: on(p, Colors.transparent),
        checkColor: WidgetStatePropertyAll(heroInk),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(fillColor: on(dark ? pText : p, faint)),
      switchTheme: SwitchThemeData(
        thumbColor: on(heroInk, heroInk),
        trackColor: on(p, divider),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        // Safety net for any stray Material Switch: same white knob + check as AppSwitch.
        thumbIcon: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Icon(Icons.check_rounded, size: 14, color: p) : null),
      ),
      sliderTheme: base.sliderTheme.copyWith(
          activeTrackColor: dark ? pText : p, thumbColor: dark ? pText : p, inactiveTrackColor: p.withValues(alpha: 0.18)),
      chipTheme: ChipThemeData(
        backgroundColor: input,
        selectedColor: chipTint,
        secondarySelectedColor: chipTint,
        checkmarkColor: pOnChip,
        side: BorderSide(color: divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
        labelStyle: ts(13, FontWeight.w500, text),
        secondaryLabelStyle: ts(13, FontWeight.w600, pOnChip),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? pText : p,
        linearTrackColor: emerald,
        circularTrackColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: pText,
        indicatorColor: pText,
        unselectedLabelColor: muted,
        dividerColor: divider,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: ts(14, FontWeight.w600),
        unselectedLabelStyle: ts(14, FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: emerald,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? ensureContrast(pText, [emerald]) : muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? ts(12, FontWeight.w600, text)
            : ts(12, FontWeight.w500, muted)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bg,
        indicatorColor: emerald,
        selectedIconTheme: IconThemeData(size: 24, color: ensureContrast(pText, [emerald])),
        unselectedIconTheme: IconThemeData(size: 24, color: muted),
        selectedLabelTextStyle: ts(12, FontWeight.w600, text),
        unselectedLabelTextStyle: ts(12, FontWeight.w500, muted),
      ),
      // ── surfaces: tone + hairline at rest (D-612); only what floats casts a shadow ──
      cardTheme: base.cardTheme.copyWith(
        color: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium), side: BorderSide(color: divider)),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSheet)),
        titleTextStyle: heading(22, 18),
        contentTextStyle: ts(14, FontWeight.w400, muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        modalBackgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        dragHandleColor: divider,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet))),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxWidth: 720), // comfortable on tablets & web
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        elevation: 6,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium), side: BorderSide(color: divider)),
        textStyle: ts(14, FontWeight.w500, text),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(shadow),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium), side: BorderSide(color: divider))),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: ts(14, FontWeight.w500, scheme.onInverseSurface),
        actionTextColor: dark ? p : pLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
            color: scheme.inverseSurface.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
        textStyle: ts(12.5, FontWeight.w500, scheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        titleTextStyle: ts(15, FontWeight.w500, text),
        subtitleTextStyle: ts(13, FontWeight.w400, muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 12,
        shape: control,
      ),
      dividerTheme: base.dividerTheme.copyWith(color: divider, space: 1, thickness: 1),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: muted,
        collapsedIconColor: muted,
        textColor: text,
        collapsedTextColor: text,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      badgeTheme: BadgeThemeData(backgroundColor: scheme.error, textColor: scheme.onError),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSheet)),
        headerBackgroundColor: emerald,
        headerForegroundColor: ensureContrast(dark ? pLight : pDark, [emerald]),
        headerHeadlineStyle: heading(28, 24),
        todayBorder: BorderSide(color: pText),
        dayStyle: ts(14, FontWeight.w500),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSheet)),
        hourMinuteShape: control,
        dayPeriodShape: control,
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