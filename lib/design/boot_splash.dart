// lib/design/boot_splash.dart
//
// THE splash screen. One widget, [BootSplash], is shared by the instant boot
// screen, the live-theme loading screen and the hand-off overlay ([SplashHandOff]),
// so re-mounting between those three never restarts or jumps the animation:
// every value is derived from one shared clock.
//
// Frame 1 is pixel-identical to the native splash (same artwork, 260×250 logical
// px, centred, cream #FBF7EC / emerald #0F7B5F), so the hand-over from the OS
// splash is invisible. Then, in order:
//   0.35 s  the mark comes alive: it floats (a slow bob), tilts in 3D on a
//           Lissajous path with a shadow that follows it, breathes, a light
//           sweeps across it and a soft ring ripples out of it once per breath;
//           an ambient field of drifting warm light (emerald, gold, peach — one
//           family, no blue; D-622) and a few gold sparks fades in behind;
//   0.9 s   the wordmark (the app's name as the super admin set it, cached by
//           AppIdentity; D-622: the editorial face, Markazi Text, drawn as the
//           display role — the splash has no theme scope for AppType) and the
//           tagline rise below the mark;
//   1.0 s   the footer the super admin set ("Powered by Double Y" + its small
//           logo, cached by AppIdentity) and the version fade in at the bottom;
//   1.2 s   the smart line: a time-of-day greeting with the returning user's
//           first name, and a status that says what the start-up is doing
//           right now ("Connecting securely…", "Preparing your offline
//           lessons…", "You're offline — opening your downloads"), with a
//           progress bar paced by this device's usual boot time ([SplashPacing]);
//   exit    the mark zooms gently and everything dissolves into the first app
//           frame.
// Reduced motion (MediaQuery.disableAnimations): no float, tilt, breathing,
// shimmer, ripple, drift or zoom — only fades.
//
// Everything the splash shows is a plain value on [SplashState.instance]
// (main.dart's bootstrap sets them; a test sets them directly), so the layout
// harness can pump [BootSplash] without any platform service.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart' show StorageService;
import 'package:flutter_education_app/core/app_identity.dart' show AppIdentity;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import '../core/display/display_settings.dart';
import 'app_motion_kit.dart' show appAnimationsOffForAll;

// ─────────────────────────────────────────────────────────────────────────────
// Facts the splash shows (set by the bootstrap, read by the widget)
// ─────────────────────────────────────────────────────────────────────────────

/// Live facts for the splash. Visual only: nothing here influences how the init
/// steps run.
class SplashState extends ChangeNotifier {
  SplashState();

  static final SplashState instance = SplashState();

  /// One clock for every mount of the splash (boot screen → theme loading →
  /// hand-off overlay).
  final Stopwatch clock = Stopwatch();

  /// Finished init steps (see [stepDone]).
  int steps = 0;

  /// Init steps the bootstrap runs on this platform (progress denominator).
  int expected = 8;

  /// 0 core init · 1 app mounted (live theme loading) · 2 ready → hand-off.
  int stage = 0;

  /// The init step running right now (its `_safe` name), '' when none.
  String step = '';

  /// First name of the cached (returning) user, '' for a fresh install / signed out.
  String userName = '';

  /// The device has no connection: the app will open on the downloads.
  bool offline = false;

  /// The app's name for the wordmark under the mark; '' = [AppIdentity.instance.name] (nothing when that is empty).
  String appName = '';
  String tagline = '';
  String version = '';

  /// The footer line the super admin set ("Powered by Double Y"), '' for none.
  String footerText = '';

  /// Its small logo: the cached bytes (first frame, offline), else the URL (fetched when online).
  Uint8List? footerLogoBytes;
  String footerLogoUrl = '';

  /// Added to the clock (tests: pretend the splash has been up for this long).
  double clockOffset = 0;

  double get elapsed => clock.elapsedMicroseconds / 1e6 + clockOffset;

  void beginStep(String name) {
    step = name;
    notifyListeners();
  }

  void stepDone(String name) {
    steps++;
    if (step == name) step = '';
    notifyListeners();
  }

  void setStage(int s) {
    if (stage == s) return;
    stage = s;
    notifyListeners();
  }

  void setUser(Map<String, dynamic>? user) {
    final raw = (user?['name'] ?? '').toString().trim();
    userName = firstName(raw);
    notifyListeners();
  }

  void setIdentity({String? tagline, String? version, String? name}) {
    if (tagline != null) this.tagline = tagline.trim();
    if (version != null) this.version = version.trim();
    if (name != null) appName = name.trim();
    notifyListeners();
  }

  void setFooter({String? text, Uint8List? logoBytes, String? logoUrl}) {
    if (text != null) footerText = text.trim();
    footerLogoBytes = logoBytes;
    if (logoUrl != null) footerLogoUrl = logoUrl.trim();
    notifyListeners();
  }

  void setOffline(bool v) {
    if (offline == v) return;
    offline = v;
    notifyListeners();
  }

  /// Back to a fresh launch (tests, and a retry after a fatal start).
  void reset() {
    clock
      ..reset()
      ..stop();
    clockOffset = 0;
    steps = 0;
    stage = 0;
    step = '';
    userName = '';
    offline = false;
    appName = '';
    tagline = '';
    version = '';
    footerText = '';
    footerLogoBytes = null;
    footerLogoUrl = '';
    notifyListeners();
  }

  /// The first word of a full name, without titles ("Dr." / "د.") or a
  /// trailing comma; '' when the name is empty.
  static String firstName(String full) {
    const titles = {'dr', 'dr.', 'mr', 'mr.', 'mrs', 'mrs.', 'ms', 'ms.', 'prof', 'prof.', 'د', 'د.', 'أ', 'أ.', 'م', 'م.'};
    for (final part in full.split(RegExp(r'\s+'))) {
      final p = part.replaceAll(RegExp(r'[,،]+$'), '').trim();
      if (p.isEmpty || titles.contains(p.toLowerCase())) continue;
      return p.length > 16 ? '${p.substring(0, 15)}…' : p;
    }
    return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pacing: the progress bar follows the init steps AND this device's usual boot time
// ─────────────────────────────────────────────────────────────────────────────

/// The saved dark-mode choice (ProfileProvider.darkMode, [StorageService.darkModeKey]): the splash follows it when
/// one is cached, else the OS brightness — so a dark-mode user never gets a light flash at launch. main.dart's
/// bootstrap starts [load] before the first frame and never awaits it (the value lands while the artwork decodes).
abstract final class SplashTheme {
  static final ValueNotifier<bool?> dark = ValueNotifier(null);

  static Future<void> load() async {
    try {
      dark.value = (await SharedPreferences.getInstance()).getBool(StorageService.darkModeKey);
    } catch (e) {
      debugPrint('[splash] theme load: $e');
    }
  }
}

/// Progress pacing. The step count is coarse (one slow step would freeze the
/// bar), so the bar also follows the elapsed time against the boot time this
/// device usually needs, remembered across launches (exponential moving
/// average). Pure: [target] is unit-tested.
abstract final class SplashPacing {
  static const _kKey = 'splash_usual_boot_ms_v1';

  /// Usual boot time in seconds on this device (0 = unknown yet).
  static double usual = 0;

  static Future<void> load() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_kKey) ?? 0;
      usual = ms > 0 ? ms / 1000 : 0;
    } catch (e) {
      debugPrint('[splash] pacing load: $e');
    }
  }

  /// Remembers how long this launch took, as a 1:3 blend with the previous
  /// value (an unusually slow launch moves it a little, not all the way).
  static Future<void> remember(double seconds) async {
    if (seconds <= 0 || seconds > 60) return;
    usual = usual <= 0 ? seconds : (usual * 0.7 + seconds * 0.3);
    try {
      await (await SharedPreferences.getInstance()).setInt(_kKey, (usual * 1000).round());
    } catch (e) {
      debugPrint('[splash] pacing save: $e');
    }
  }

  /// The progress the bar aims at (0–1).
  ///  * stage 2 → 1 (hand-off);
  ///  * stage 1 → 0.82 (app mounted, live theme loading);
  ///  * stage 0 → the finished-step share, OR the elapsed share of the usual
  ///    boot time when that is ahead — never above 0.78 while steps are
  ///    still running, so the bar never looks finished before the app is.
  static double target({
    required int stage,
    required int steps,
    required int expected,
    required double elapsed,
    required double usual,
  }) {
    if (stage >= 2) return 1;
    if (stage == 1) return 0.82;
    final byStep = 0.06 + 0.62 * (steps / math.max(1, expected)).clamp(0.0, 1.0);
    if (usual <= 0) return byStep;
    final byTime = 0.06 + 0.72 * (elapsed / usual).clamp(0.0, 1.0);
    return math.min(0.78, math.max(byStep, byTime));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Texts
// ─────────────────────────────────────────────────────────────────────────────

/// The words the splash says. Pure, unit-tested.
abstract final class SplashTexts {
  /// Time-of-day greeting, with the first name when there is one.
  static String greeting({required String name, required bool en, DateTime? now}) {
    final h = (now ?? DateTime.now()).hour;
    final String base;
    if (en) {
      base = h < 5 ? 'Good night' : (h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening'));
    } else {
      base = h < 5 ? 'ليلة سعيدة' : (h < 12 ? 'صباح الخير' : 'مساء الخير');
    }
    if (name.isEmpty) return en ? 'Welcome' : 'أهلاً بك';
    return en ? '$base, $name' : '$base، $name';
  }

  /// What the start-up is doing right now.
  static String status({
    required String step,
    required int stage,
    required bool offline,
    required double elapsed,
    required bool en,
  }) {
    if (offline) return en ? "You're offline — opening your downloads" : 'لا يوجد اتصال — نفتح تنزيلاتك';
    if (stage >= 2) return en ? 'Ready' : 'جاهز';
    if (elapsed > 9) return en ? 'Taking a little longer than usual…' : 'يستغرق وقتًا أطول من المعتاد…';
    if (stage == 1) return en ? 'Applying your theme…' : 'نطبّق المظهر…';
    return switch (step) {
      'language' => en ? 'Loading your language…' : 'نحمّل لغتك…',
      'firebase' => en ? 'Connecting securely…' : 'نتصل بأمان…',
      'remoteConfig' => en ? 'Fetching the latest settings…' : 'نجلب أحدث الإعدادات…',
      'connectivity' => en ? 'Checking your connection…' : 'نتحقق من الاتصال…',
      'offlineVideos' => en ? 'Preparing your offline lessons…' : 'نجهّز دروسك دون اتصال…',
      'attendanceCourses' => en ? 'Loading your courses…' : 'نحمّل دوراتك…',
      'identity' => en ? 'Loading…' : 'جارٍ التحميل…',
      'crashlytics' => en ? 'Almost there…' : 'أوشكنا على الانتهاء…',
      _ => en ? 'Getting everything ready…' : 'نجهّز لك كل شيء…',
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Artwork
// ─────────────────────────────────────────────────────────────────────────────

/// The native splash artwork, decoded BEFORE the first Flutter frame so that
/// frame already shows the logo (no blank flash between the native splash and
/// Flutter's).
abstract final class SplashArt {
  static const asset = 'assets/images/splash.png';

  /// flutter_native_splash treats the source image as 4x (Android xxxhdpi,
  /// iOS @3x = ¾, web light-4x): assets/images/splash.png is 1040×1000 px →
  /// 260×250 logical px, centred on the whole window on every platform
  /// (android_gravity / ios_content_mode: center, fullscreen, web `.center`).
  static const Size size = Size(260, 250);

  static ui.Image? image;

  /// Reduced motion from the platform: the hand-off overlay sits ABOVE
  /// MaterialApp, where there is no MediaQuery.
  static bool get reduceMotion =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations ||
      DisplaySettings.instance.prefs.reduceMotion || // the app's own "Reduce motion" (loaded right after storage)
      appAnimationsOffForAll; // the Super Admin's switch for every account (cached disable list)

  static Future<void> preload() async {
    if (image != null) return; // retry after a fatal start: keep the decoded art (no second, leaked copy)
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final dpr = views.isEmpty ? 3.0 : views.first.devicePixelRatio;
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: (size.width * dpr).round().clamp(1, 1040),
      );
      image = (await codec.getNextFrame()).image;
    } catch (e) {
      debugPrint('[splash] preload: $e');
    }
  }

  static Widget widget(Size s) {
    final img = image;
    if (img != null) {
      return RawImage(image: img, width: s.width, height: s.height, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
    }
    return Image.asset(asset, width: s.width, height: s.height, fit: BoxFit.fill, gaplessPlayback: true);
  }

  /// Frees the decoded artwork once the hand-off finished (nothing paints it
  /// any more; a later splash — e.g. a theme reload — falls back to Image.asset).
  static void release() {
    final img = image;
    image = null;
    img?.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The splash
// ─────────────────────────────────────────────────────────────────────────────

/// Brand colours of the native splash (must match pubspec `flutter_native_splash`): the warm cream canvas and the
/// emerald the dark splash sits on. Frame 1 must equal the OS splash, so these two never follow the theme.
const splashCream = Color(0xFFFBF7EC);
const splashEmerald = Color(0xFF0F7B5F);

/// The warm lights of the ambient field (D-622: one warm family — gold for the sparks, a peach light, a pale
/// emerald — never a blue or a mint that turns the canvas cold).
const splashGold = Color(0xFFC8923A);
const splashPeach = Color(0xFFF2C4A6);
const splashMint = Color(0xFF8FD1B4);

/// The charcoal ink of the light splash (the theme's `text_dark`) and its muted line.
const splashInk = Color(0xFF211D18);
const splashInkSoft = Color(0xFF6E655A);

class BootSplash extends StatefulWidget {
  const BootSplash({super.key, this.exit, this.state});

  /// Hand-off progress 0 → 1 (null while still loading).
  final Animation<double>? exit;

  /// Defaults to [SplashState.instance].
  final SplashState? state;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> with SingleTickerProviderStateMixin {
  static const _still = 0.35, _taglineAt = 0.9, _lineAt = 1.2, _versionAt = 1.0;

  // Shared across mounts: the bar must not jump back when the splash re-mounts.
  static double _shown = 0, _lastT = 0, _lastTarget = -1, _targetAt = 0;

  late final AnimationController _tick = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  SplashState get _s => widget.state ?? SplashState.instance;

  @override
  void initState() {
    super.initState();
    if (!_s.clock.isRunning) _s.clock.start();
    SplashTheme.dark.addListener(_onTheme);
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SplashTheme.dark.removeListener(_onTheme);
    _tick.dispose();
    super.dispose();
  }

  /// Eases the bar toward its target, creeping slowly inside a long step so it never looks frozen.
  static void _advance(double t, double target) {
    final dt = (t - _lastT).clamp(0.0, 0.25);
    _lastT = t;
    if (target != _lastTarget) {
      _lastTarget = target;
      _targetAt = t;
    }
    final creep = target >= 1 ? 0.0 : 0.09 * (1 - math.exp(-(t - _targetAt) / 5));
    final goal = math.min(0.97, target + creep);
    final next = _shown + (goal - _shown) * (1 - math.exp(-dt * (target >= 1 ? 9 : 2.6)));
    _shown = target >= 1 ? math.max(_shown, next) : math.max(_shown, math.min(next, goal));
  }

  static double _in(double t, double at, double over, bool reduce) =>
      reduce ? (t > at ? 1.0 : 0.0) : Curves.easeOutCubic.transform(((t - at) / over).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final reduce = (mq?.disableAnimations ?? false) || SplashArt.reduceMotion;
    final dark = SplashTheme.dark.value ??
        ((mq?.platformBrightness ?? ui.PlatformDispatcher.instance.platformBrightness) == Brightness.dark);
    final bg = dark ? splashEmerald : splashCream;
    final accent = dark ? splashCream : splashEmerald;
    final ink = dark ? splashCream : splashInk;
    final soft = dark ? splashCream.withValues(alpha: 0.78) : splashInkSoft;
    final en = AppConfig.lang == 'en';
    final exit = widget.exit;
    final s = _s;

    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Semantics(
          label: en ? 'Loading' : 'جارٍ التحميل',
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth.isFinite ? box.maxWidth : SplashArt.size.width + 32;
            final h = box.maxHeight.isFinite ? box.maxHeight : SplashArt.size.height + 32;
            // Native size on every real screen; only a window smaller than the artwork scales it down.
            final fit = math
                .min(1.0, math.min((w - 32) / SplashArt.size.width, (h - 32) / SplashArt.size.height))
                .clamp(0.2, 1.0);
            final art = SplashArt.size * fit;
            final logo = RepaintBoundary(child: SplashArt.widget(art));
            // The visible mark spans ~32–68 % of the artwork's height: the words sit just below it.
            final belowTop = (h / 2 + art.height * 0.18 + 28).clamp(0.0, math.max(0.0, h - 48)).toDouble();
            final contentW = math.min(360.0, math.max(0.0, w - 32));
            final barW = math.min(168.0, contentW);
            final glow = art.width * 1.45;

            return AnimatedBuilder(
              animation: Listenable.merge([_tick, s, ?exit]),
              builder: (context, _) {
                final t = s.elapsed;
                final target = SplashPacing.target(
                  stage: s.stage,
                  steps: s.steps,
                  expected: s.expected,
                  elapsed: t,
                  usual: SplashPacing.usual,
                );
                _advance(t, target);
                final x = exit?.value ?? 0.0;
                final xOut = Curves.easeInOut.transform(x);

                final ramp = reduce ? 0.0 : Curves.easeInOut.transform(((t - _still) / 0.8).clamp(0.0, 1.0));
                final ambient = (reduce ? (t > _still ? 1.0 : 0.0) : ((t - _still) / 1.4).clamp(0.0, 1.0)) * (1 - xOut);
                final breath = 0.5 - 0.5 * math.cos(2 * math.pi * math.max(0.0, t - _still) / 2.8);
                final scale = 1 + 0.028 * ramp * breath + (reduce ? 0.0 : 0.12 * Curves.easeOutCubic.transform(x));
                final cyc = (t - 0.8) % 3.4;
                final sweep = (!reduce && t > 0.8 && cyc < 1.2 && x == 0)
                    ? Curves.easeInOutSine.transform(cyc / 1.2)
                    : -1.0;
                final glowA = (dark ? 0.16 : 0.11) * ramp * (0.55 + 0.45 * breath) * (1 - x);
                // Float + 3D tilt: slow, incommensurable periods so the path never visibly repeats.
                final live = ramp * (1 - xOut);
                final bob = -6.0 * live * math.sin(2 * math.pi * (t - _still) / 2.8);
                final tiltX = 0.10 * live * math.sin(2 * math.pi * t / 4.6);
                final tiltY = 0.14 * live * math.sin(2 * math.pi * t / 3.7 + 1.0);
                final ripple = (!reduce && t > 0.9 && x == 0) ? ((t - 0.9) % 2.8) / 2.8 : -1.0;
                final bgA = 1 - xOut;
                final logoA = 1 - Curves.easeInCubic.transform(x);
                final gone = 1 - (x * 2.2).clamp(0.0, 1.0);
                final tagIn = _in(t, _taglineAt, 0.7, reduce);
                final lineIn = _in(t, _lineAt, 0.6, reduce);
                final verIn = _in(t, _versionAt, 0.8, reduce);

                final tagline = s.tagline;
                final wordmark = s.appName.isNotEmpty ? s.appName : AppIdentity.instance.name;
                final greeting = SplashTexts.greeting(name: s.userName, en: en);
                final status = SplashTexts.status(step: s.step, stage: s.stage, offline: s.offline, elapsed: t, en: en);

                return Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: bg.withValues(alpha: bgA)),
                  if (ambient > 0)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _AmbientPainter(t: reduce ? 0 : t, alpha: ambient, dark: dark, reduce: reduce),
                      ),
                    ),
                  Center(
                    child: IgnorePointer(
                      child: Container(
                        width: glow,
                        height: glow,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            accent.withValues(alpha: glowA),
                            accent.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (ripple >= 0)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _RipplePainter(progress: ripple, color: accent, radius: art.width * 0.5),
                      ),
                    ),
                  // The shadow under the floating mark: it slides opposite to the tilt and softens as the
                  // mark rises, which is what sells the float.
                  Center(
                    child: IgnorePointer(
                      child: Transform.translate(
                        offset: Offset(-tiltY * 60, art.height * 0.24 - bob * 0.6),
                        child: Opacity(
                          opacity: (dark ? 0.35 : 0.22) * live,
                          child: Container(
                            width: art.width * 0.52,
                            height: 14,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: dark ? Colors.black : splashEmerald,
                                  blurRadius: 22 + 6 * breath,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: logoA,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0014)
                          ..translateByDouble(0.0, bob, 0.0, 1.0)
                          ..rotateX(tiltX)
                          ..rotateY(tiltY)
                          ..scaleByDouble(scale, scale, 1.0, 1.0),
                        child: ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (r) {
                            const clear = Color(0x00FFFFFF);
                            if (sweep < 0) return const LinearGradient(colors: [clear, clear]).createShader(r);
                            final c = -0.35 + 1.7 * sweep;
                            return LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [clear, Colors.white.withValues(alpha: dark ? 0.32 : 0.48), clear],
                              stops: [(c - 0.14).clamp(0.0, 1.0), c.clamp(0.0, 1.0), (c + 0.14).clamp(0.0, 1.0)],
                            ).createShader(r);
                          },
                          child: logo,
                        ),
                      ),
                    ),
                  ),
                  // Words below the mark. FittedBox scales the whole block down on a window too short for
                  // it (never an overflow); every line is one line with an ellipsis.
                  Positioned(
                    left: 16,
                    right: 16,
                    top: belowTop,
                    bottom: 40,
                    child: IgnorePointer(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: contentW,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            if (wordmark.isNotEmpty)
                              _Rise(
                                progress: tagIn * gone,
                                child: Text(
                                  wordmark,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: _wordmarkStyle(ink, en: en),
                                ),
                              ),
                            if (tagline.isNotEmpty) ...[
                              if (wordmark.isNotEmpty) const SizedBox(height: 4),
                              _Rise(
                                progress: tagIn * gone,
                                child: Text(
                                  tagline,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppFonts.family,
                                    fontSize: 14,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                    color: soft,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            _Rise(
                              progress: lineIn * gone,
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  greeting,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppFonts.family,
                                    fontSize: 15,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                    color: ink.withValues(alpha: 0.92),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                RepaintBoundary(
                                  child: CustomPaint(
                                    size: Size(barW, 10),
                                    painter: _BarPainter(
                                      progress: _shown.clamp(0.0, 1.0),
                                      track: accent.withValues(alpha: dark ? 0.22 : 0.14),
                                      fill: accent,
                                      head: dark ? splashCream : splashGold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AnimatedSwitcher(
                                  duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  child: Text(
                                    status,
                                    key: ValueKey(status),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: AppFonts.family,
                                      fontSize: 12.5,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      color: soft,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (s.version.isNotEmpty || s.footerText.isNotEmpty || s.footerLogoBytes != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12 + (mq?.padding.bottom ?? 0),
                      child: IgnorePointer(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          _Rise(
                            progress: verIn * gone,
                            child: _SplashFooter(
                              text: s.footerText,
                              logoBytes: s.footerLogoBytes,
                              logoUrl: s.offline ? '' : s.footerLogoUrl,
                              color: soft,
                              dark: dark,
                            ),
                          ),
                          if (s.version.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Opacity(
                              opacity: 0.55 * verIn * gone,
                              child: Text(
                                'v${s.version}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.8,
                                  color: soft,
                                ),
                              ),
                            ),
                          ],
                        ]),
                      ),
                    ),
                ]);
              },
            );
          }),
        ),
      ),
    );
  }
}

/// The wordmark's style: the editorial face at the display role's optical size (32 × the face's scale, as
/// `AppType.display` draws it; D-611 / D-622). Built by hand because the splash runs above the MaterialApp and
/// the theme scope, where `AppType` cannot be asked. Falls back to the text font with "Headings: Same as text".
TextStyle _wordmarkStyle(Color ink, {required bool en}) {
  const optical = 32.0;
  final editorial = AppFonts.editorialHeadings;
  final size = editorial ? (optical * AppFonts.editorialScale(en ? 'en' : 'ar')).roundToDouble() : 28.0;
  return TextStyle(
    fontFamily: editorial ? AppFonts.editorialFamilyFor(en ? 'en' : 'ar') : AppFonts.editorial,
    fontFamilyFallback: AppFonts.editorialFallback,
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: editorial ? (en ? 1.15 : 1.3) : 1.25,
    letterSpacing: en && editorial ? -size * 0.01 : null,
    color: ink,
  );
}

/// The footer the super admin set: a small logo and a line such as "Powered by Double Y".
class _SplashFooter extends StatelessWidget {
  const _SplashFooter({
    required this.text,
    required this.logoBytes,
    required this.logoUrl,
    required this.color,
    required this.dark,
  });

  final String text;
  final Uint8List? logoBytes;
  final String logoUrl;
  final Color color;
  final bool dark;

  static const _logoH = 26.0;

  @override
  Widget build(BuildContext context) {
    final bytes = logoBytes;
    final Widget? logo = bytes != null
        ? Image.memory(bytes, height: _logoH, fit: BoxFit.contain, gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink())
        : (logoUrl.isNotEmpty
            ? Image.network(logoUrl, height: _logoH, fit: BoxFit.contain, gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                frameBuilder: (_, child, frame, sync) =>
                    AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 300), child: child))
            : null);
    if (logo == null && text.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (logo != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96, maxHeight: _logoH),
          child: logo,
        ),
      if (logo != null && text.isNotEmpty) const SizedBox(width: 8),
      if (text.isNotEmpty)
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 12.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: dark ? 0.9 : 0.85),
            ),
          ),
        ),
    ]);
  }
}

/// Fades a line in while it rises 10 px into place.
class _Rise extends StatelessWidget {
  const _Rise({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return Opacity(opacity: 0, child: child);
    return Opacity(
      opacity: p,
      child: Transform.translate(offset: Offset(0, 10 * (1 - p)), child: child),
    );
  }
}

/// One thin ring that grows out of the mark and fades (a "wave" every breath).
class _RipplePainter extends CustomPainter {
  const _RipplePainter({required this.progress, required this.color, required this.radius});

  final double progress, radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final c = Offset(size.width / 2, size.height / 2);
    final r = radius * (0.75 + 1.05 * p);
    final a = 0.30 * (1 - p) * (1 - p);
    if (a <= 0.005) return;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 - 0.8 * p
        ..color = color.withValues(alpha: a),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter o) => o.progress != progress || o.color != color || o.radius != radius;
}

/// A thin progress bar with a gold glowing head.
class _BarPainter extends CustomPainter {
  const _BarPainter({required this.progress, required this.track, required this.fill, required this.head});

  final double progress;
  final Color track, fill, head;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 3.0;
    final y = (size.height - h) / 2;
    final r = Radius.circular(h / 2);
    canvas.drawRRect(RRect.fromLTRBR(0, y, size.width, y + h, r), Paint()..color = track);
    final wFill = size.width * progress;
    if (wFill <= 0) return;
    final rect = Rect.fromLTWH(0, y, wFill, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [fill.withValues(alpha: 0.75), fill, head],
          const [0, 0.7, 1],
        ),
    );
    if (progress < 1) {
      canvas.drawCircle(
        Offset(wFill, y + h / 2),
        4,
        Paint()
          ..color = head.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.progress != progress || o.track != track || o.fill != fill || o.head != head;
}

/// Ambient field: three soft warm lights drifting slowly on Lissajous paths and a
/// few gold sparks twinkling. Cheap: three radial gradients and a dozen dots.
class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({required this.t, required this.alpha, required this.dark, required this.reduce});

  final double t, alpha;
  final bool dark, reduce;

  static const _lights = [
    // (x-centre, y-centre, radius, x-period, y-period, phase, color index)
    (0.18, 0.22, 0.55, 23.0, 17.0, 0.0, 0),
    (0.84, 0.30, 0.50, 19.0, 29.0, 2.1, 1),
    (0.50, 0.86, 0.60, 31.0, 21.0, 4.2, 2),
  ];

  // Deterministic spark positions (fractions of the window) and twinkle phases.
  static const _sparks = [
    (0.12, 0.18, 0.0), (0.88, 0.14, 1.3), (0.22, 0.72, 2.6), (0.80, 0.78, 0.7),
    (0.06, 0.50, 3.4), (0.94, 0.52, 1.9), (0.36, 0.10, 4.6), (0.66, 0.92, 2.2),
    (0.30, 0.90, 5.1), (0.72, 0.08, 3.9), (0.50, 0.04, 0.4), (0.15, 0.34, 2.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final base = math.max(size.width, size.height);
    // one warm family: a pale emerald, gold and a peach light (dark: cream, gold, peach over the emerald)
    final colors = dark
        ? [splashCream, splashGold, splashPeach]
        : [splashMint, splashGold, splashPeach];
    final strength = dark ? 0.18 : 0.12;
    for (final (cx, cy, rr, px, py, ph, ci) in _lights) {
      final dx = reduce ? 0.0 : 0.06 * math.sin(2 * math.pi * t / px + ph);
      final dy = reduce ? 0.0 : 0.05 * math.cos(2 * math.pi * t / py + ph);
      final c = Offset((cx + dx) * size.width, (cy + dy) * size.height);
      final r = rr * base;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            colors[ci].withValues(alpha: strength * alpha),
            colors[ci].withValues(alpha: 0),
          ]),
      );
    }
    final spark = Paint()..color = (dark ? splashCream : splashGold);
    for (final (fx, fy, ph) in _sparks) {
      final tw = reduce ? 0.6 : 0.5 + 0.5 * math.sin(2 * math.pi * t / 3.6 + ph);
      final a = (dark ? 0.55 : 0.42) * alpha * tw;
      if (a <= 0.01) continue;
      final rise = reduce ? 0.0 : 6 * ((t / 9 + ph / 7) % 1.0);
      canvas.drawCircle(Offset(fx * size.width, fy * size.height - rise), 1.2 + 0.8 * tw, spark..color = spark.color.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.t != t || o.alpha != alpha || o.dark != dark || o.reduce != reduce;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hand-off into the first app frame
// ─────────────────────────────────────────────────────────────────────────────

/// Lays the splash over the first real app frame and dissolves it (scale +
/// fade), so the app appears out of the splash instead of replacing it in one
/// cut. Plays once per launch and remembers how long the launch took
/// ([SplashPacing.remember]).
class SplashHandOff extends StatefulWidget {
  const SplashHandOff({super.key, required this.child});

  final Widget child;

  @override
  State<SplashHandOff> createState() => _SplashHandOffState();
}

class _SplashHandOffState extends State<SplashHandOff> with SingleTickerProviderStateMixin {
  static bool _done = false;

  late final AnimationController _out =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void initState() {
    super.initState();
    if (_done) return;
    final s = SplashState.instance;
    s.setStage(2);
    SplashPacing.remember(s.elapsed);
    // Let the app paint its first frame underneath, then dissolve the splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false) || SplashArt.reduceMotion) {
        _out.duration = const Duration(milliseconds: 220);
      }
      _out.forward().whenComplete(() {
        _done = true;
        if (mounted) setState(() {});
        // after the frame that removed the overlay, nothing references the decoded artwork any more
        WidgetsBinding.instance.addPostFrameCallback((_) => SplashArt.release());
        WidgetsBinding.instance.scheduleFrame();
      });
    });
  }

  @override
  void dispose() {
    _done = true;
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app stays the FIRST child at all times, so removing the overlay never re-mounts it.
    return Stack(fit: StackFit.expand, textDirection: TextDirection.ltr, children: [
      widget.child,
      if (!_done) Positioned.fill(child: IgnorePointer(child: BootSplash(exit: _out))),
    ]);
  }
}
