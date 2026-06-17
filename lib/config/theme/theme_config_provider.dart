// lib/config/theme_config_provider.dart
//
// Lifecycle
// ─────────
//   1. On construction → load cached palette from SharedPreferences (instant).
//   2. Immediately fire a background fetch from the server.
//   3. On success → update in-memory model + re-cache + notifyListeners().
//   4. Widgets call context.themeConfig.primary, .gradientPrimary, etc.
//
// AppTheme fallback
// ─────────────────
//   If the server is unreachable AND no cache exists, every getter falls
//   back to the hard-coded AppTheme constant, so the app never breaks.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Color, Colors, BoxShadow, LinearGradient …
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import 'app_theme.dart';
import 'theme_config_model.dart';

// ─────────────────────────────────────────────────────────────────────────────

const _kCacheKey = 'theme_config_v1';

/// Detects which platform string to send to the API.
String get _currentPlatform {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  return 'android';
}

// ─────────────────────────────────────────────────────────────────────────────

class ThemeConfigProvider extends ChangeNotifier {
  final ApiClient _api;

  ThemeConfigProvider({required ApiClient api}) : _api = api {
    _loadCache().then((_) => _fetchFromServer());
  }

  // ── State ─────────────────────────────────────────────────────────────────

  ThemeConfigModel? _model;
  bool _isFetching = false;
  String? _error;

  ThemeConfigModel? get model    => _model;
  bool              get isFetching => _isFetching;
  String?           get error    => _error;

  // ── Convenience getters — fall back to AppTheme constants ─────────────────

  Color get primary          => _model?.primary          ?? AppTheme.primary;
  Color get primaryDark      => _model?.primaryDark      ?? AppTheme.primaryDark;
  Color get primaryLight     => _model?.primaryLight     ?? AppTheme.primaryLight;
  Color get lightPrimary     => _model?.lightPrimary     ?? AppTheme.lightPrimary;
  Color get accent           => _model?.accent           ?? AppTheme.accent;
  Color get primaryTint      => _model?.primaryTint      ?? AppTheme.lightPrimary;
  Color get primaryTintDark  => _model?.primaryTintDark  ?? AppTheme.lightPrimary;

  Color get charcoal         => _model?.charcoal         ?? AppTheme.charcoal;
  Color get charcoalLight    => _model?.charcoalLight    ?? AppTheme.charcoalLight;
  Color get charcoalDark     => _model?.charcoalDark     ?? AppTheme.charcoalDark;
  Color get accent2          => _model?.accent2          ?? AppTheme.accent2;
  Color get success          => _model?.success          ?? AppTheme.success;
  Color get danger           => _model?.danger           ?? AppTheme.danger;
  Color get warning          => _model?.warning          ?? AppTheme.warning;
  Color get purple           => _model?.purple           ?? AppTheme.purple;
  Color get secondText       => _model?.secondText       ?? AppTheme.secondText;

  Color get background           => _model?.background           ?? AppTheme.background;
  Color get surfaceCard          => _model?.surfaceCard          ?? AppTheme.surfaceCard;
  Color get cardBg               => _model?.cardBg               ?? AppTheme.cardBg;
  Color get textFieldBackground  => _model?.textFieldBackground  ?? AppTheme.textFieldBackground;
  Color get divider              => _model?.divider              ?? AppTheme.divider;

  Color get textDark    => _model?.textDark    ?? AppTheme.textDark;
  Color get textMedium  => _model?.textMedium  ?? AppTheme.textMedium;
  Color get textLight   => _model?.textLight   ?? AppTheme.textLight;
  Color get textAction  => _model?.textAction  ?? AppTheme.textAction;

  Color get darkBackground => _model?.darkBackground ?? AppTheme.darkBackground;
  Color get darkSurface    => _model?.darkSurface    ?? AppTheme.darkSurface;
  Color get darkCard       => _model?.darkCard       ?? AppTheme.darkCard;
  Color get darkInput      => _model?.darkInput      ?? AppTheme.darkInput;
  Color get darkDivider    => _model?.darkDivider    ?? AppTheme.darkDivider;

  Color get darkTextPrimary => _model?.darkTextPrimary ?? AppTheme.darkTextPrimary;
  Color get darkTextMuted   => _model?.darkTextMuted   ?? AppTheme.darkTextMuted;
  Color get darkTextLight   => _model?.darkTextLight   ?? AppTheme.darkTextLight;

  // ── Gradient getters ──────────────────────────────────────────────────────

  List<Color> get gradientPrimary =>
      _model?.gradientPrimary ??
          const [Color(0xFFF4C542), Color(0xFFF8D670), Color(0xFFF4C542)];

  List<Color> get gradientAccent =>
      _model?.gradientAccent ??
          const [Color(0xFFF4C542), Color(0xFFF8D670)];

  List<Color> get gradientAccent2 =>
      _model?.gradientAccent2 ??
          const [Color(0xFFF4C542), Color(0xFFF8D670)];

  List<Color> get gradientSlider =>
      _model?.gradientSlider ??
          const [Color(0xFF2E2E2E), Color(0xFF4A4A4A), Color(0xFF2E2E2E)];

  List<Color> get gradientLightSlideBar =>
      _model?.gradientLightSlideBar ??
          const [Color(0xFF2E2E2E), Color(0xFF4A4A4A), Color(0xFF2E2E2E)];

  List<Color> get gradientDarkSlideBar =>
      _model?.gradientDarkSlideBar ??
          const [Color(0xFF1A1A1A), Color(0xFF2E2E2E)];

  List<Color> get gradientBackground =>
      _model?.gradientBackground ??
          const [Color(0xFFF5F5F5), Color(0xFFFAFAFA)];

  List<Color> get gradientDarkBackground =>
      _model?.gradientDarkBackground ??
          const [Color(0xFF1A1A1A), Color(0xFF222222)];

  List<Color> get gradientDisable =>
      _model?.gradientDisable ??
          const [Color(0x501A1A1A), Color(0x504A4A4A)];

  List<Color> get gradientGoldCharcoal =>
      _model?.gradientGoldCharcoal ??
          const [Color(0xFFF4C542), Color(0xFF2E2E2E)];

  List<Color> get gradientSuccess =>
      _model?.gradientSuccess ??
          const [Color(0xFF34C270), Color(0xFF4ADE80)];

  List<Color> get gradientDanger =>
      _model?.gradientDanger ??
          const [Color(0xFFFF3B5C), Color(0xFFFF6B85)];

  List<Color> get gradientPurple =>
      _model?.gradientPurple ??
          const [Color(0xFF8B6FFF), Color(0xFFB39DFF)];

  List<Color> get gradientTeal =>
      _model?.gradientTeal ??
          const [Color(0xFF2E2E2E), Color(0xFF4A4A4A)];

  /// Primary brand slider — identical stops to gradientPrimary by default,
  /// but kept as a separate token so the admin can style sliders independently.
  List<Color> get primarySliderGradient =>
      _model?.primarySliderGradient ??
          const [Color(0xFFF4C542), Color(0xFFF8D670), Color(0xFFF4C542)];

  // ── Input background ──────────────────────────────────────────────────────

  /// Input field fill colour — auto-switches with [isDark].
  Color inputBg({bool isDark = false}) => isDark
      ? (_model?.inputBgDark ?? AppTheme.darkInput)
      : (_model?.inputBg    ?? AppTheme.textFieldBackground);

  // ── Shadows (BoxShadow lists) ─────────────────────────────────────────────

  /// Primary-coloured glow shadow — uses the live primary colour from server.
  /// Pass [isDark] to get the lower-opacity dark-mode variant.
  List<BoxShadow> primaryShadow({bool isDark = false}) {
    final shadowColor = isDark
        ? (_model?.primaryShadowColorDark ?? primary.withValues(alpha: 0.15))
        : (_model?.primaryShadowColor     ?? primary.withValues(alpha: 0.30));
    return [
      BoxShadow(
        color:      shadowColor,
        blurRadius: 20,
        offset:     const Offset(0, 8),
      ),
    ];
  }

  /// Neutral card drop-shadow. Uses fixed charcoal/black colours (not
  /// primary-derived) but still respects the server values for cache round-trips.
  List<BoxShadow> cardShadow({bool isDark = false}) {
    if (isDark) {
      final base = _model?.cardShadowColorDark ?? Colors.black;
      return [
        BoxShadow(
          color:      base.withValues(alpha: 0.30),
          blurRadius: 24,
          offset:     const Offset(0, 8),
        ),
        BoxShadow(
          color:      base.withValues(alpha: 0.20),
          blurRadius: 4,
          offset:     const Offset(0, 2),
        ),
      ];
    }
    final base = _model?.cardShadowColor ?? const Color(0xFF1A1A1A);
    return [
      BoxShadow(
        color:      base.withValues(alpha: 0.04),
        blurRadius: 24,
        offset:     const Offset(0, 8),
      ),
      BoxShadow(
        color:      Colors.black.withValues(alpha: 0.02),
        blurRadius: 4,
        offset:     const Offset(0, 2),
      ),
    ];
  }

  // ── LinearGradient helpers (ready to drop into BoxDecoration) ─────────────

  LinearGradient get linearPrimary => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientPrimary,
  );

  LinearGradient get linearAccent => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientAccent,
  );
  LinearGradient get linearAccent2 => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientAccent2,
  );

  LinearGradient get linearSlider => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientSlider,
  );
  LinearGradient get linearPrimarySlider => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: primarySliderGradient,
  );

  LinearGradient get linearDisable => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientDisable,
  );

  LinearGradient get linearBackground => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: gradientBackground,
  );

  LinearGradient get linearDarkBackground => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: gradientDarkBackground,
  );

  LinearGradient get linearSuccess => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientSuccess,
  );

  LinearGradient get linearDanger => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientDanger,
  );

  LinearGradient get linearPurple => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradientPurple,
  );

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _model = ThemeConfigModel.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ThemeConfigProvider] cache load error: $e');
    }
  }

  Future<void> _saveCache(ThemeConfigModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, jsonEncode(model.toJson()));
    } catch (e) {
      debugPrint('[ThemeConfigProvider] cache save error: $e');
    }
  }

  // ── Network ───────────────────────────────────────────────────────────────

  Future<void> _fetchFromServer() async {
    _isFetching = true;
    _error = null;

    try {
      final platform = _currentPlatform;
      // ApiClient.get returns the parsed JSON body (Map or List).
      // Adjust the call signature to match your ApiClient implementation.
      final json = await _api.get('/api/v1/theme/$platform') as Map<String, dynamic>;
      final colors = json['colors'] as Map<String, dynamic>;
      _model = ThemeConfigModel.fromJson(colors);
      await _saveCache(_model!);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      debugPrint('[ThemeConfigProvider] fetch error: $e');
      // Keep showing cached / fallback colours — do NOT crash.
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  /// Call this to force a manual refresh (e.g. after an admin colour change).
  Future<void> refresh() => _fetchFromServer();
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext extension — context.themeConfig anywhere in the widget tree
// ─────────────────────────────────────────────────────────────────────────────

extension ThemeConfigX on BuildContext {
  ThemeConfigProvider get themeConfig =>
      _ThemeConfigScope.of(this);
}

/// Internal InheritedWidget that avoids a full Provider dependency
/// (works seamlessly alongside your existing MultiProvider setup).
class _ThemeConfigScope extends InheritedNotifier<ThemeConfigProvider> {
  const _ThemeConfigScope({
    required ThemeConfigProvider notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ThemeConfigProvider of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_ThemeConfigScope>();
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