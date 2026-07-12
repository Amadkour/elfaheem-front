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
//   2. Hit the API first.
//        • Success → parse the model, cache it to SharedPreferences, done.
//        • Failure → fall back to whatever was last cached in
//          SharedPreferences. If nothing was ever cached, every getter
//          below falls back to the hard-coded AppTheme constants, so the
//          app never breaks or shows blank colours.
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
import '../app_config.dart';
import 'app_theme.dart';
import 'theme_config_model.dart';

const _kCacheKey = 'theme_config_v1';
const _kDisableListCacheKey = 'disable_list_v1';

/// Detects which platform string to send to the API.
String get _currentPlatform {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  return 'android';
}

class ThemeConfigProvider extends ChangeNotifier {
  final ApiClient _api;

  ThemeConfigProvider({required ApiClient api}) : _api = api;

  // ── Loading / model state ─────────────────────────────────────────────────

  ThemeConfigModel? _model;
  ThemeConfigModel? get model => _model;

  /// True from construction until the first [load] call resolves (either
  /// from the API or, on failure, from the SharedPreferences cache).
  /// The app should show a loading/splash screen while this is true.
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// Kept for backwards compatibility with existing call sites.
  bool get isFetching => _isLoading;

  String? _error;
  String? get error => _error;

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

  /// Call this once at app startup (and again for a manual refresh).
  /// Always hits the API first; only reads the SharedPreferences cache if
  /// the API call fails.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final fetchedFromServer = await _fetchFromServer();
    if (!fetchedFromServer) {
      await _loadFromCache();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Alias for [load] — call after an admin colour change to force a
  /// fresh fetch.
  Future<void> refresh() => load();

  // ══════════════════════════════════════════════════════════════════════
  // SURFACES
  // ══════════════════════════════════════════════════════════════════════

  Color get background => isDark
      ? (_model?.darkBackground ?? AppTheme.darkBackground)
      : (_model?.background ?? AppTheme.background);

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
      ? (_model?.inputBgDark ?? AppTheme.darkInput)
      : (_model?.inputBg ?? AppTheme.textFieldBackground);

  Color get divider => isDark
      ? (_model?.darkDivider ?? AppTheme.darkDivider)
      : (_model?.divider ?? AppTheme.divider);

  // ══════════════════════════════════════════════════════════════════════
  // TEXT
  // ══════════════════════════════════════════════════════════════════════

  Color get textDark => isDark
      ? (_model?.darkTextPrimary ?? AppTheme.darkTextPrimary)
      : (_model?.textDark ?? AppTheme.textDark);

  Color get textMedium => isDark
      ? (_model?.darkTextMuted ?? AppTheme.darkTextMuted)
      : (_model?.textMedium ?? AppTheme.textMedium);

  Color get textLight => isDark
      ? (_model?.darkTextLight ?? AppTheme.darkTextLight)
      : (_model?.textLight ?? AppTheme.textLight);

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

  Color get secondText => _model?.secondText ?? AppTheme.secondText;

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
      ? (_model?.primaryTintDark ?? primary.withValues(alpha: 0.20))
      : (_model?.primaryTint ?? primary.withValues(alpha: 0.12));

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

  /// Always the light brand gradient, regardless of dark mode — for
  /// content painted *on top of* a coloured surface (e.g. button icons),
  /// which shouldn't flip to the charcoal variant in dark mode.
  LinearGradient get primaryGradientOnColor => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientPrimary ?? AppTheme.primaryGradient.colors,
  );

  /// In dark mode this intentionally resolves to the charcoal slide-bar
  /// gradient rather than a dark variant of the brand gradient — a large
  /// brand-coloured block doesn't read as premium in dark mode.
  LinearGradient get primaryGradient =>
      isDark ? _darkSlideBarGradient : primaryGradientOnColor;

  /// Same "charcoal instead of brand colour" behaviour as [primaryGradient].
  LinearGradient get primarySliderGradient =>
      isDark ? _darkSlideBarGradient : _sliderGradient;

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

  LinearGradient get sliderGradient => _sliderGradient;

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

  LinearGradient get purpleGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientPurple ?? AppTheme.purpleGradient.colors,
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
  LinearGradient get slideBarGradient =>
      isDark ? _darkSlideBarGradient : _lightSlideBarGradient;

  // Shared building blocks for the gradients above that reuse the same
  // stops under more than one name (primaryGradient in dark mode,
  // primarySliderGradient in light mode, slideBarGradient, etc).
  LinearGradient get _darkSlideBarGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: _model?.gradientDarkSlideBar ?? AppTheme.darkSlideBarGradient.colors,
  );

  LinearGradient get _lightSlideBarGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _model?.gradientLightSlideBar ?? AppTheme.lightSlideBarGradient.colors,
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
        ? (_model?.cardShadowColorDark ?? Colors.black)
        : (_model?.cardShadowColor ?? const Color(0xFF1A1A1A));
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
        ? (_model?.primaryShadowColorDark ?? primary.withValues(alpha: 0.15))
        : (_model?.primaryShadowColor ?? primary.withValues(alpha: 0.30));
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

  /// Button text — charcoal on yellow (premium contrast).
  TextStyle get button => AppTheme.button.copyWith(color: charcoalDark);

  TextStyle get buttonSm => AppTheme.buttonSmall.copyWith(color: charcoalDark);

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

  // ── Network ───────────────────────────────────────────────────────────────

  /// Returns true on success (model populated + cached), false on failure.
  Future<bool> _fetchFromServer() async {
    try {
      final platform = _currentPlatform;
      final json = await _api.get('/api/v1/theme/$platform') as Map<String, dynamic>;
      final colors = json['colors'] as Map<String, dynamic>;
      _model = ThemeConfigModel.fromJson(colors);

      final disableItems = (json['disable_list'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      AppConfig.disableList = disableItems;

      await _saveCache(_model!, disableItems);
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[ThemeConfigProvider] fetch error: $e');
      return false;
    }
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  /// Only called when the API call fails — reads the last-known-good
  /// palette (and disable list) back out of SharedPreferences.
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getString(_kCacheKey);
      if (raw != null) {
        _model = ThemeConfigModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }

      final disableRaw = prefs.getString(_kDisableListCacheKey);
      if (disableRaw != null) {
        AppConfig.disableList = (jsonDecode(disableRaw) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      }
    } catch (e) {
      debugPrint('[ThemeConfigProvider] cache load error: $e');
    }
  }

  Future<void> _saveCache(ThemeConfigModel model, List<String> disableItems) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, jsonEncode(model.toJson()));
      await prefs.setString(_kDisableListCacheKey, jsonEncode(disableItems));
    } catch (e) {
      debugPrint('[ThemeConfigProvider] cache save error: $e');
    }
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