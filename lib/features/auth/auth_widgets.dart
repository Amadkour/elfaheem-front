// auth_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────
// The auth design language (D-073): every sign-in screen is built from these
// pieces, so one change here restyles login, register, forgot password, the
// code screens and the teacher's profile step together. Colours come from the
// live theme (`context.colors`), text from AppFonts, motion honours
// MediaQuery.disableAnimations.
//
//   authText / authTracking         the type scale (letter spacing for Latin only)
//   authHeroGradient                the hero / brand panel: primary 70 % · accent 30 % (D-088)
//   AuthHeroBackdrop · AuthLogoTile the hero surface and the app-icon style logo
//   AuthSidebar                     the brand panel of the wide (web / tablet) layout
//   AuthCard · AuthEntrance         the form surface and its entrance
//   authInputDecoration             filled, rounded field with an animated focus ring
//   IconTextField · IconPasswordField · AuthEmailField   the fields (label above)
//   AuthButton                      gradient primary button: press, loading, haptic
//   AuthTextAction · LinkRow        secondary actions
//   AuthOrDivider                   "or" between the form and Google
//   AuthPasswordStrength · AuthRequirement   password meter + checklist
//   AuthOtpBox                      one code box (focus / filled / error)
//   ProgressBar · RolePicker        the register steps and the role cards
//   ScreenIcon · SectionLabel · StyledDropdown · LangRow · LangDropdown
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_identity.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_inputs.dart' show validateEmail, kEmailRegex;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../utils/widget/primary_menue.dart' show MyPrimaryMenu;
import 'auth_provider.dart';

// ── 0. Foundations ────────────────────────────────────────────────────────────

/// True when the person asked the system for less motion.
bool authReduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [ms] of animation, or none under reduced motion.
Duration authDuration(BuildContext context, int ms) =>
    authReduceMotion(context) ? Duration.zero : Duration(milliseconds: ms);

/// Letter spacing for Latin text only (spacing breaks Arabic joining).
double? authTracking(double v) => AppConfig.lang == 'ar' ? null : v;

/// The auth type scale: the current language's font, explicit size / weight / line height.
/// The other language's font is the fallback, so an Arabic word in English UI (and the reverse) still draws.
TextStyle authText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h, double? ls}) => TextStyle(
      fontFamily: AppFonts.family,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: size,
      fontWeight: w,
      color: c,
      height: h,
      letterSpacing: ls,
    );

/// WCAG contrast ratio of two opaque colours (1 … 21).
double authContrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// One stop of a hero gradient, deepened until even the MUTED on-hero ink (subtitles, the tagline: [ink] at 72 %)
/// reads on it at 4.5:1 with a little margin for the glows drawn over it — and at a stricter 6.4:1 in dark mode, the
/// step deeper a bright brand block needs there. The deepening keeps the stop's own hue and only lowers its
/// lightness (saturation capped a little, so a vivid light tone does not turn garish), so a light accent becomes
/// its own deep tone — a cream gold turns bronze — instead of greying toward the shade (D-088).
Color authHeroStop(Color stop, Color ink, Color shade, {required bool dark}) {
  // dark mode: the step deeper is a stricter target on the same hue path (a blend toward the shade greyed a light
  // accent into taupe); [shade] stays for callers and older themes' sake
  final target = dark ? 6.4 : 4.9;
  return authDeepen(stop, (bg) => authContrast(Color.alphaBlend(ink.withValues(alpha: 0.72), bg), bg) >= target);
}

/// [color] with its lightness lowered (hue kept, saturation capped at 0.62) until [ok] holds; unchanged when it
/// already does.
Color authDeepen(Color color, bool Function(Color) ok) {
  if (ok(color)) return color;
  final hsl = HSLColor.fromColor(color);
  final tone = hsl.withSaturation(hsl.saturation.clamp(0.0, 0.62));
  var c = color;
  var l = hsl.lightness;
  for (var i = 0; i < 80 && !ok(c); i++) {
    l = (l - 0.012).clamp(0.0, 1.0);
    c = tone.withLightness(l).toColor();
  }
  return c;
}

/// The accent's share of the sign-in hero: the surface is a blend of the theme's primary (70 %) and accent (30 %),
/// the two colours the super admin picks on the Theme page ("Primary", "Accent 1") — D-088.
const authHeroAccentShare = 0.30;

/// Where the run into the accent starts, so the gradient's mean colour is exactly [authHeroAccentShare] accent:
/// pure primary over the first part of the surface, then a straight run into the accent whose area is half
/// primary, half accent → (1 − s) / 2 = 0.30 → s = 0.40.
const authHeroBlendStart = 1 - 2 * authHeroAccentShare;

/// The raw 70 / 30 brand stops before any contrast guard: primary · primary · accent at 0 · 0.40 · 1 — or, when the
/// accent is (almost) the primary itself (a monochrome palette), shades of the primary at even stops (null).
(List<Color>, List<double>?) authBrandStops(ThemeConfigProvider c) {
  final p = c.primary;
  final a = c.accent;
  if (authContrast(p, a) < 1.15) return ([c.heroTint(p, 0.14), p, c.heroEnd(p, 0.34)], null);
  return ([p, p, a], const [0, authHeroBlendStart, 1]);
}

/// The brand gradient of the sign-in hero (D-088, amends D-082): the theme's primary over 70 % of the surface and its
/// accent over 30 % — primary from the [begin] corner (top-start), running into the accent toward [end]
/// (bottom-end; the short phone hero runs toward the end side, so its visible top keeps the accent). Every stop
/// passes [authHeroStop]: deeper in dark mode, never too light for the on-hero ink.
LinearGradient authHeroGradient(
  ThemeConfigProvider c, {
  AlignmentGeometry begin = AlignmentDirectional.topStart,
  AlignmentGeometry end = AlignmentDirectional.bottomEnd,
}) {
  final (colors, stops) = authBrandStops(c);
  return LinearGradient(
    begin: begin,
    end: end,
    stops: stops,
    colors: [for (final s in colors) authHeroStop(s, c.onHero, c.heroShade, dark: c.isDark)],
  );
}

/// The hero surface, in the dashboard hero's language: the brand gradient, a soft top sheen, a brand glow, and the
/// home hero's signature — one wide ring bleeding off the end edge — with a hairline echo. Fills its box. With a
/// [radius] (the phone hero) it floats on a soft brand glow like HomeHeroCard.
class AuthHeroBackdrop extends StatelessWidget {
  const AuthHeroBackdrop({super.key, this.radius = 0, this.panel = false});

  /// Bottom corner radius (the phone hero is rounded, the brand panel is not).
  final double radius;

  /// The wide layout's tall brand panel: one more soft glow half-way down, so the long surface keeps its depth.
  final bool panel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.vertical(bottom: Radius.circular(radius));
    final ink = c.onHero;
    Widget glow(Color color, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        );
    Widget ring(double size, double width, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ink.withValues(alpha: alpha), width: width),
          ),
        );
    final brandGlow = c.heroTint(c.primary, 0.45).withValues(alpha: c.isDark ? 0.16 : 0.24);
    // the tall panel runs corner to corner; the short phone hero runs toward its end side, so the accent's 30 % is in
    // the part above the card instead of under it
    final gradient = panel || radius <= 0
        ? authHeroGradient(c)
        : authHeroGradient(c, end: const AlignmentDirectional(1, 0.4));
    final surface = ClipRRect(
      borderRadius: r,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // a soft top sheen: light falling on the surface
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [ink.withValues(alpha: c.isDark ? 0.03 : 0.05), ink.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            // the primary's glow sits on the primary side; the accent end keeps its own tone
            PositionedDirectional(top: -150, start: -130, child: glow(brandGlow, 380)),
            PositionedDirectional(bottom: -170, end: -140, child: glow(ink.withValues(alpha: 0.04), 360)),
            if (panel)
              PositionedDirectional(top: 280, start: -140, child: glow(c.heroTint(c.primary, 0.3).withValues(alpha: c.isDark ? 0.08 : 0.12), 340)),
            // the home hero's signature ring (HomeHeroCard), scaled to the larger surface, and a hairline echo
            PositionedDirectional(top: -96, end: -84, child: ring(260, 30, 0.08)),
            PositionedDirectional(top: -170, end: -160, child: ring(420, 1, 0.10)),
          ],
        ),
      ),
    );
    if (radius <= 0) return surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: c.isDark ? 0.22 : 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: surface,
    );
  }
}

/// The logo as an app icon: the admin's logo (or the bundled mark) on a light rounded tile with a soft shadow.
/// [hero] gives it the shared `auth-logo` Hero tag, so it flies between the auth pages (one per page).
class AuthLogoTile extends StatelessWidget {
  const AuthLogoTile({super.key, this.size = 44, this.hero = false});

  final double size;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tile = ListenableBuilder(
      listenable: AppIdentity.instance,
      builder: (context, _) {
        final url = AppIdentity.instance.logoUrl;
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.14),
          decoration: BoxDecoration(
            color: c.onHero,
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(color: c.heroShade.withValues(alpha: 0.28), blurRadius: size * 0.4, offset: Offset(0, size * 0.12)),
            ],
          ),
          child: url != null && url.isNotEmpty
              ? AppNetworkImage(url: url, fit: BoxFit.contain, color: c.onHero)
              : Image.asset('assets/images/logo_mark.png', fit: BoxFit.contain),
        );
      },
    );
    return Semantics(
      image: true,
      label: AppIdentity.instance.name.isNotEmpty ? AppIdentity.instance.name : 'logo',
      child: hero ? Hero(tag: 'auth-logo', child: tile) : tile,
    );
  }
}

/// The app's name + tagline as the admin set them (fallbacks before the first fetch).
class AuthBrandName extends StatelessWidget {
  const AuthBrandName({super.key, this.onHero = true, this.large = false});

  final bool onHero;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: AppIdentity.instance,
      builder: (context, _) {
        final id = AppIdentity.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              id.name.isNotEmpty ? id.name : 'El-faheem',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: authText(large ? 20 : 15.5, w: FontWeight.w800, c: onHero ? c.onHero : c.textDark, h: 1.2),
            ),
            Text(
              id.tagline.isNotEmpty ? id.tagline : 'learning_platform'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // full on-hero ink: the muted one is under 4.5:1 on the gradient's light end at this size
              style: authText(large ? 13 : 11.5, w: FontWeight.w500, c: onHero ? c.onHero : c.textLight, h: 1.3, ls: authTracking(0.3)),
            ),
          ],
        );
      },
    );
  }
}

// ── 1. Brand panel (wide layout) ──────────────────────────────────────────────
class AuthSidebar extends StatelessWidget {
  const AuthSidebar({super.key, this.width});

  /// Panel width; null = a third of the window, at most 400 (the old size, still used by the password page).
  final double? width;

  @override
  Widget build(BuildContext context) {
    // Name / logo / tagline / mission / stats come from the admin's "About us" data.
    return ListenableBuilder(
      listenable: AppIdentity.instance,
      builder: (context, _) => _buildPanel(context, AppIdentity.instance),
    );
  }

  Widget _buildPanel(BuildContext context, AppIdentity id) {
    final c = context.colors;
    final w = width ?? (context.width / 3 > 400 ? 400 : context.width / 3);
    final pad = w < 320 ? 16.0 : 40.0;
    return SizedBox(
      width: w,
      child: Stack(
        children: [
          const Positioned.fill(child: AuthHeroBackdrop(panel: true)),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad, vertical: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AuthLogoTile(size: 48, hero: true),
                            const SizedBox(width: 14),
                            const Expanded(child: AuthBrandName(large: true)),
                          ],
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [c.onHero, c.heroTint(c.primary, 0.5)]),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'unlock_potential'.tr,
                          style: authText(36, w: FontWeight.w800, c: c.onHero, h: 1.15, ls: authTracking(-0.6)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          id.mission.isNotEmpty ? id.mission : 'join_students_hint'.tr,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: authText(15, c: c.onHeroMuted, h: 1.65),
                        ),
                        const SizedBox(height: 32),
                        _SidebarFeature(icon: Icons.live_tv_rounded, text: 'feature_live_sessions'.tr),
                        const SizedBox(height: 12),
                        _SidebarFeature(icon: Icons.groups_rounded, text: 'feature_expert_teachers'.tr),
                        const SizedBox(height: 12),
                        _SidebarFeature(icon: Icons.insights_rounded, text: 'feature_assessments'.tr),
                        const Spacer(),
                        const SizedBox(height: 32),
                        // Statistics: the stats banner of the admin's "About us" page.
                        // (Falls back to the old fixed badges until the admin adds some.)
                        if (id.stats.isNotEmpty)
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final st in id.stats.take(4)) _SidebarStat(value: st.value, label: st.label),
                            ],
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _TrustBadge(label: 'badge_students'.tr),
                              _TrustBadge(label: 'badge_teachers'.tr),
                              _TrustBadge(label: 'badge_secure'.tr),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Circle extends StatelessWidget {
  final double size;
  final double opacity;

  const Circle({super.key, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colors.onHero.withValues(alpha: opacity),
        ),
      );
}

class _SidebarFeature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SidebarFeature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: c.heroGlass,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.heroGlassBorder),
          ),
          child: Icon(icon, size: 18, color: c.onHero),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: authText(14.5, w: FontWeight.w600, c: c.onHero.withValues(alpha: 0.88), h: 1.4)),
        ),
      ],
    );
  }
}

class _SidebarStat extends StatelessWidget {
  final String value;
  final String label;

  const _SidebarStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.heroGlassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: authText(22, w: FontWeight.w800, c: c.onHero)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: authText(11.5, c: c.onHeroMuted, h: 1.3),
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final String label;

  const _TrustBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.heroGlassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: c.onHero),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: authText(12, w: FontWeight.w700, c: c.onHero)),
          ),
        ],
      ),
    );
  }
}

// ── 2. Surfaces ───────────────────────────────────────────────────────────────

/// The form surface: the card colour, a large radius, a hairline border and a soft, wide shadow.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.divider.withValues(alpha: c.isDark ? 0.7 : 0.55)),
        boxShadow: [
          BoxShadow(
            color: c.heroShade.withValues(alpha: c.isDark ? 0.40 : 0.10),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: c.heroShade.withValues(alpha: c.isDark ? 0.20 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Fades the child in and lifts it 16 px on first build (nothing under reduced motion).
class AuthEntrance extends StatelessWidget {
  const AuthEntrance({super.key, required this.child, this.delayFactor = 0});

  final Widget child;

  /// 0..1: a later item starts a little later (staggered lists).
  final double delayFactor;

  @override
  Widget build(BuildContext context) {
    if (authReduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 460 + (delayFactor * 200).round()),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

// ── 3. Fields ─────────────────────────────────────────────────────────────────

/// An outline border that also paints a soft halo outside the stroke (the focus ring). It lerps, so the
/// InputDecorator's own border animation grows the ring in and out.
class AuthFieldBorder extends OutlineInputBorder {
  const AuthFieldBorder({
    super.borderSide,
    super.borderRadius,
    this.ring = Colors.transparent,
    this.ringWidth = 0,
  });

  final Color ring;
  final double ringWidth;

  @override
  AuthFieldBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    Color? ring,
    double? ringWidth,
  }) =>
      AuthFieldBorder(
        borderSide: borderSide ?? this.borderSide,
        borderRadius: borderRadius ?? this.borderRadius,
        ring: ring ?? this.ring,
        ringWidth: ringWidth ?? this.ringWidth,
      );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is AuthFieldBorder) return _lerp(a, this, t);
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is AuthFieldBorder) return _lerp(this, b, t);
    return super.lerpTo(b, t);
  }

  static AuthFieldBorder _lerp(AuthFieldBorder a, AuthFieldBorder b, double t) => AuthFieldBorder(
        borderSide: BorderSide.lerp(a.borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, b.borderRadius, t)!,
        ring: Color.lerp(a.ring, b.ring, t)!,
        ringWidth: lerpDouble(a.ringWidth, b.ringWidth, t)!,
      );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (ringWidth > 0 && ring.a > 0) {
      final halo = borderRadius.toRRect(rect).inflate(ringWidth / 2);
      canvas.drawRRect(
        halo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..color = ring,
      );
    }
    super.paint(canvas, rect,
        gapStart: gapStart, gapExtent: gapExtent, gapPercentage: gapPercentage, textDirection: textDirection);
  }

  @override
  bool operator ==(Object other) =>
      other is AuthFieldBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius &&
      other.gapPadding == gapPadding &&
      other.ring == ring &&
      other.ringWidth == ringWidth;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, gapPadding, ring, ringWidth);
}

/// The auth field look: tinted fill that turns to the card colour on focus, hairline border, a primary stroke
/// + halo on focus, a danger stroke on error; the prefix icon follows the state (muted → primary → danger).
InputDecoration authInputDecoration(
  BuildContext context, {
  String? hint,
  IconData? icon,
  Widget? suffix,
  bool dense = false,
}) {
  final c = context.colors;
  final r = BorderRadius.circular(16);
  AuthFieldBorder b(Color color, {double w = 1.2, Color? ring}) => AuthFieldBorder(
        borderRadius: r,
        borderSide: BorderSide(color: color, width: w),
        ring: ring ?? color.withValues(alpha: 0),
        ringWidth: ring == null ? 0 : 4,
      );
  Color stateInk(Set<WidgetState> s, Color rest) {
    if (s.contains(WidgetState.error)) return c.danger;
    if (s.contains(WidgetState.focused)) return c.primary;
    return rest;
  }

  return InputDecoration(
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    prefixIconColor: WidgetStateColor.resolveWith((s) => stateInk(s, c.textLight)),
    prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    suffixIcon: suffix,
    suffixIconColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.error) ? c.danger : c.textLight),
    hintText: hint,
    hintStyle: authText(15, c: c.textLight.withValues(alpha: 0.85)),
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (s) => s.contains(WidgetState.focused) && !c.isDark ? c.cardBg : c.inputBg,
    ),
    hoverColor: c.primary.withValues(alpha: 0.03),
    isDense: dense,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 12 : 16),
    border: b(c.divider),
    enabledBorder: b(c.divider.withValues(alpha: c.isDark ? 0.9 : 0.75)),
    disabledBorder: b(c.divider.withValues(alpha: 0.4)),
    focusedBorder: b(c.primary, w: 1.6, ring: c.primary.withValues(alpha: c.isDark ? 0.30 : 0.14)),
    errorBorder: b(c.danger.withValues(alpha: 0.7)),
    focusedErrorBorder: b(c.danger, w: 1.6, ring: c.danger.withValues(alpha: c.isDark ? 0.26 : 0.12)),
    errorStyle: authText(12, w: FontWeight.w600, c: c.danger, h: 1.35),
    errorMaxLines: 3,
  );
}

/// The style of what the person types.
TextStyle authFieldText(BuildContext context) => authText(15.5, w: FontWeight.w500, c: context.colors.textDark, h: 1.3);

class IconTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;

  /// Placeholder; null = the label.
  final String? hint;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  const IconTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard = TextInputType.text,
    this.hint,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(label: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboard,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          textCapitalization: textCapitalization,
          autocorrect: autocorrect,
          style: authFieldText(context),
          cursorColor: context.colors.primary,
          decoration: authInputDecoration(context, hint: hint ?? label, icon: icon),
          validator: (v) => (v == null || v.isEmpty) ? '$label is required' : null,
        ),
      ],
    );
  }
}

class IconPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool? obscure;
  final VoidCallback? onToggle;
  final ValueChanged<String>? onChange;

  /// [AutofillHints.password] at sign-in, [AutofillHints.newPassword] when creating one.
  final Iterable<String> autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const IconPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure,
    this.onToggle,
    this.onChange,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<IconPasswordField> createState() => _IconPasswordFieldState();
}

class _IconPasswordFieldState extends State<IconPasswordField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscure ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final tip = _obscure ? (ar ? 'إظهار كلمة المرور' : 'Show password') : (ar ? 'إخفاء كلمة المرور' : 'Hide password');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(label: widget.label),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          obscuringCharacter: '•',
          onChanged: widget.onChange,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          style: authFieldText(context),
          cursorColor: c.primary,
          decoration: authInputDecoration(
            context,
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              tooltip: tip,
              onPressed: () {
                HapticFeedback.selectionClick();
                if (mounted) setState(() => _obscure = !_obscure);
                widget.onToggle?.call();
              },
              icon: AnimatedSwitcher(
                duration: authDuration(context, 180),
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  key: ValueKey(_obscure),
                  size: 20,
                  color: c.textLight,
                ),
              ),
            ),
          ),
          validator: (v) => (v == null || v.isEmpty) ? '${widget.label} is required' : null,
        ),
      ],
    );
  }
}

/// The registration e-mail in the auth look: the same rule as AppEmailField (`validateEmail`, checked once the
/// person has typed), a live ✓ at the end, left-to-right, e-mail keyboard and autofill.
class AuthEmailField extends StatefulWidget {
  const AuthEmailField({
    super.key,
    required this.controller,
    required this.label,
    this.required = true,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final TextInputAction textInputAction;

  @override
  State<AuthEmailField> createState() => _AuthEmailFieldState();
}

class _AuthEmailFieldState extends State<AuthEmailField> {
  bool _touched = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = widget.controller.text.trim();
    final valid = kEmailRegex.hasMatch(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(label: widget.label),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: widget.textInputAction,
          style: authFieldText(context),
          cursorColor: c.primary,
          autovalidateMode: _touched ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          validator: (v) => validateEmail(v, required: widget.required),
          onChanged: (_) => setState(() => _touched = true),
          decoration: authInputDecoration(
            context,
            hint: 'name@example.com',
            icon: Icons.alternate_email_rounded,
            suffix: value.isEmpty
                ? null
                : AnimatedSwitcher(
                    duration: authDuration(context, 180),
                    child: Icon(
                      valid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      key: ValueKey(valid),
                      size: 20,
                      color: valid ? c.success : c.warning,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// A date of birth in the auth field look. Opens the same picker as MyDatePicker (1960 → five years ago, the
/// theme's colours) and hands the picked day to [onChange].
class AuthDateField extends StatelessWidget {
  const AuthDateField({
    super.key,
    required this.controller,
    required this.label,
    required this.selectedDate,
    required this.onChange,
  });

  final TextEditingController controller;
  final String label;
  final DateTime selectedDate;
  final void Function(DateTime) onChange;

  Future<void> _pick(BuildContext context) async {
    final c = context.colors;
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1960),
      lastDate: DateTime.now().subtract(const Duration(days: 360 * 5)),
      locale: const Locale('ar', 'AR'),
      builder: (context, child) {
        final scheme = c.isDark
            ? ColorScheme.dark(primary: c.primary, onPrimary: c.onHero, surface: c.cardBg, onSurface: c.textDark)
            : ColorScheme.light(primary: c.primary, onPrimary: c.onHero, surface: c.cardBg, onSurface: c.textDark);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: scheme,
            textTheme: TextTheme.of(context).copyWith(
              displaySmall: TextStyle(fontFamily: AppFonts.family),
              titleLarge: TextStyle(fontFamily: AppFonts.family),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) onChange(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: () => _pick(context),
      textDirection: TextDirection.ltr,
      style: authFieldText(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      decoration: authInputDecoration(
        context,
        hint: label,
        // one icon (L12: a cake AND a calendar read as two controls)
        icon: Icons.calendar_month_rounded,
      ),
    );
  }
}

// ── 4. Buttons and links ──────────────────────────────────────────────────────

/// The primary action: brand gradient, 54 dp, a soft coloured shadow, a gentle press, a spinner while
/// [loading], a light haptic. It is a FilledButton underneath, so the keyboard support (Enter on the last field)
/// and screen readers treat it as the form's button.
class AuthButton extends StatefulWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.enabled = true,
    this.iconBefore = false,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool enabled;
  final bool iconBefore;

  /// null = the brand gradient; a colour paints the button in that colour instead.
  final Color? tone;

  @override
  State<AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<AuthButton> {
  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  void _onStates() {
    final p = _states.value.contains(WidgetState.pressed);
    if (p != _pressed && mounted) setState(() => _pressed = p);
  }

  @override
  void dispose() {
    _states.removeListener(_onStates);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = widget.enabled && !widget.loading && widget.onPressed != null;
    // a busy button keeps its colour (it is working, not disabled)
    final lit = active || widget.loading;
    final tone = widget.tone;
    // no tone: THE brand gradient (D-136, every stop AA under the label) with its glass sheen, like every primary
    // button; a tone keeps a flat-ish two-stop fill. The hero keeps its own blend (M22).
    final base = tone ?? authDeepen(c.primary, (bg) => authContrast(c.onHero, bg) >= 4.7);
    final LinearGradient fill = tone == null
        ? (_pressed ? c.primaryGradientPressed : c.primaryGradient)
        : LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [base, c.heroEnd(base, 0.22)],
          );
    final fg = lit ? c.onHero : c.textLight;
    const radius = 16.0;

    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: authText(16, w: FontWeight.w700, c: fg, h: 1.2, ls: authTracking(0.2)),
    );
    final icon = widget.icon == null
        ? null
        : Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: lit ? c.onHero.withValues(alpha: 0.18) : c.textLight.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 17, color: fg),
          );
    final content = AnimatedSwitcher(
      duration: authDuration(context, 200),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
      ),
      child: widget.loading
          ? SizedBox(
              key: const ValueKey('busy'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: c.onHero),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null && widget.iconBefore) ...[icon, const SizedBox(width: 10)],
                Flexible(child: label),
                if (icon != null && !widget.iconBefore) ...[const SizedBox(width: 10), icon],
              ],
            ),
    );

    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: box.hasBoundedWidth ? double.infinity : null,
        child: AnimatedScale(
          scale: _pressed && !authReduceMotion(context) ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: authDuration(context, 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: lit
                  ? [
                      BoxShadow(
                        color: fill.colors[fill.colors.length ~/ 2].withValues(alpha: c.isDark ? 0.38 : 0.32),
                        blurRadius: _pressed ? 12 : 22,
                        spreadRadius: -6,
                        offset: Offset(0, _pressed ? 6 : 12),
                      ),
                    ]
                  : const [],
            ),
            child: FilledButton(
              statesController: _states,
              onPressed: active
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onPressed!();
                    }
                  : null,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(64, 54),
                elevation: 0,
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: c.onHero,
                overlayColor: c.onHero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: lit ? fill : null,
                  color: lit ? null : (c.isDark ? c.inputBg : c.divider.withValues(alpha: 0.7)),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Container(
                  foregroundDecoration: lit && tone == null
                      ? BoxDecoration(gradient: c.primaryGloss, borderRadius: BorderRadius.circular(radius))
                      : null,
                  constraints: const BoxConstraints(minHeight: 54),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet secondary action: a tinted pill with an icon (guest mode, apply as an institution, …). 44 dp tall.
class AuthTextAction extends StatelessWidget {
  const AuthTextAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary); // AA on its tint in both modes
    return Material(
      color: c.primary.withValues(alpha: c.isDark ? 0.16 : 0.07),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: authText(13.5, w: FontWeight.w700, c: ink, h: 1.25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Message  Link" — wraps on a narrow phone; the link has a 48 dp target.
class LinkRow extends StatelessWidget {
  final String message;
  final String linkText;
  final VoidCallback onTap;

  const LinkRow({
    super.key,
    required this.message,
    required this.linkText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? c.primaryLight : c.primary;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(message, style: authText(14.5, c: c.textMedium, h: 1.4)),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: ink,
          ),
          child: Text(linkText, style: authText(14.5, w: FontWeight.w700, c: ink, h: 1.4)),
        ),
      ],
    );
  }
}

/// A hairline that fades out toward both ends, with a small label in the middle ("or").
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget line(bool toEnd) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: toEnd ? [c.divider.withValues(alpha: 0), c.divider] : [c.divider, c.divider.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return Row(
      children: [
        line(true),
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: authText(12.5, w: FontWeight.w600, c: c.textLight, ls: authTracking(0.4)),
            ),
          ),
        ),
        line(false),
      ],
    );
  }
}

// ── 5. Password strength + requirements ───────────────────────────────────────

/// Four segments that fill with the strength (0..4) and its word at the end. [color] is the strength's colour.
class AuthPasswordStrength extends StatelessWidget {
  const AuthPasswordStrength({super.key, required this.strength, required this.label, required this.color, this.title});

  final int strength;
  final String label;
  final Color color;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = authDuration(context, 260);
    return Semantics(
      label: '${title ?? ''} $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: d,
                    curve: Curves.easeOutCubic,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < strength ? color : c.divider.withValues(alpha: c.isDark ? 0.9 : 0.7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (title != null)
                Expanded(child: Text(title!, style: authText(12.5, c: c.textMedium, h: 1.3)))
              else
                const Spacer(),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AnimatedSwitcher(
                    duration: d,
                    child: Text(
                      label,
                      key: ValueKey(label),
                      textAlign: TextAlign.end,
                      style: authText(12.5, w: FontWeight.w700, c: color, h: 1.3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line of a requirement checklist: an empty ring that turns into a green check when [met].
class AuthRequirement extends StatelessWidget {
  const AuthRequirement({super.key, required this.met, required this.label});

  final bool met;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: authDuration(context, 220),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Icon(
              met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              key: ValueKey(met),
              size: 18,
              color: met ? c.success : c.textLight,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: authDuration(context, 220),
              style: authText(13, w: met ? FontWeight.w600 : FontWeight.w500, c: met ? c.textDark : c.textMedium, h: 1.4),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 6. Code box ───────────────────────────────────────────────────────────────

/// One box of a one-time code. The caller puts its TextField in [child]; the box draws the state:
/// empty (tinted), filled (a primary hairline), focused (the card colour, a primary stroke and halo), error.
class AuthOtpBox extends StatelessWidget {
  const AuthOtpBox({
    super.key,
    required this.child,
    this.focused = false,
    this.filled = false,
    this.error = false,
    this.height = 64,
  });

  final Widget child;
  final bool focused, filled, error;
  final double height;

  /// The digit style: big, bold, tabular figures.
  static TextStyle digitStyle(BuildContext context) =>
      authText(28, w: FontWeight.w700, c: context.colors.textDark, h: 1.0)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color border;
    final Color bg;
    if (error) {
      border = c.danger;
      bg = c.danger.withValues(alpha: c.isDark ? 0.14 : 0.06);
    } else if (focused) {
      border = c.primary;
      bg = c.isDark ? c.inputBg : c.cardBg;
    } else if (filled) {
      border = c.primary.withValues(alpha: 0.45);
      bg = c.primary.withValues(alpha: c.isDark ? 0.14 : 0.05);
    } else {
      border = c.divider.withValues(alpha: c.isDark ? 0.9 : 0.75);
      bg = c.inputBg;
    }
    return AnimatedContainer(
      duration: authDuration(context, 180),
      curve: Curves.easeOut,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: focused || error ? 1.8 : 1.2),
        boxShadow: focused || error
            ? [BoxShadow(color: (error ? c.danger : c.primary).withValues(alpha: c.isDark ? 0.30 : 0.14), spreadRadius: 4)]
            : const [],
      ),
      child: child,
    );
  }
}

// ── 7. Screen icon header ─────────────────────────────────────────────────────
class ScreenIcon extends StatelessWidget {
  final IconData icon;

  const ScreenIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: authHeroGradient(c),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: c.primary.withValues(alpha: 0.30), blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 8)),
        ],
      ),
      child: Icon(icon, color: c.onHero, size: 26),
    );
  }
}

// ── 8. Field label ────────────────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: authText(13.5, w: FontWeight.w600, c: context.colors.textMedium, h: 1.3, ls: authTracking(0.1)),
      );
}

// ── 9. Progress bar (step indicator) ─────────────────────────────────────────
class ProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const ProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: AppConfig.lang == 'ar' ? 'الخطوة ${currentStep + 1} من $totalSteps' : 'Step ${currentStep + 1} of $totalSteps',
      child: Row(
        children: List.generate(totalSteps, (i) {
          final done = i <= currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: authDuration(context, 320),
              curve: Curves.easeOutCubic,
              margin: EdgeInsetsDirectional.only(end: i < totalSteps - 1 ? 6 : 0),
              height: 6,
              decoration: BoxDecoration(
                gradient: done ? LinearGradient(colors: [c.primary, c.heroTint(c.primary, 0.25)]) : null,
                color: done ? null : c.divider.withValues(alpha: c.isDark ? 0.9 : 0.7),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── 10. Role picker cards ─────────────────────────────────────────────────────
class RolePicker extends StatelessWidget {
  final MyAuthProvider provider;
  final ExpansibleController rolController;

  const RolePicker({
    super.key,
    required this.provider,
    required this.rolController,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: provider.roles.map<Widget>((role) {
        final isSelected = provider.selectedRole == role;
        final teacher = role['text'] == 'teacher';
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              button: true,
              selected: isSelected,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    provider.onChangeRole(provider.roles.indexOf(role), rolController);
                  },
                  child: AnimatedContainer(
                    duration: authDuration(context, 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
                    decoration: BoxDecoration(
                      color: isSelected ? c.primary.withValues(alpha: c.isDark ? 0.18 : 0.06) : c.inputBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? c.primary : c.divider.withValues(alpha: c.isDark ? 0.9 : 0.75),
                        width: isSelected ? 1.6 : 1.2,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: authDuration(context, 220),
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: isSelected ? authHeroGradient(c) : null,
                                  color: isSelected ? null : c.textLight.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  teacher
                                      ? Icons.cast_for_education_rounded
                                      : role['text'] == 'parent'
                                          ? Icons.family_restroom_rounded
                                          : Icons.school_rounded,
                                  color: isSelected ? c.onHero : c.textMedium,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                role['text'].toString().tr,
                                textAlign: TextAlign.center,
                                style: authText(14, w: FontWeight.w700, c: isSelected ? c.textDark : c.textMedium),
                              ),
                            ],
                          ),
                        ),
                        PositionedDirectional(
                          top: -6,
                          end: -4,
                          child: AnimatedScale(
                            scale: isSelected ? 1 : 0,
                            duration: authDuration(context, 220),
                            curve: Curves.easeOutBack,
                            child: Icon(Icons.check_circle_rounded, size: 20, color: c.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── 11. Styled dropdown (wraps MyPrimaryMenu with icon + label) ───────────────
class StyledDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final ExpansibleController controller;
  final dynamic initValue;
  final List<Map<String, dynamic>> options;
  final Function(dynamic) onChange;

  const StyledDropdown({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    required this.initValue,
    required this.options,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider.withValues(alpha: c.isDark ? 0.9 : 0.75), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 20, 0, 0),
            child: Icon(icon, size: 20, color: c.textLight),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
              child: MyPrimaryMenu(
                label: label,
                controller: controller,
                initValue: initValue,
                options: options,
                haveLogo: false,
                onChange: onChange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 12. Language switcher row ─────────────────────────────────────────────────
class LangRow extends StatelessWidget {
  const LangRow({super.key});

  @override
  Widget build(BuildContext context) {
    LangProvider provider = context.watch<LangProvider>();
    return Row(
      children: provider.languages.map<Widget>((l) {
        final isActive = AppConfig.lang == l;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: GestureDetector(
            onTap: () => provider.changeLang(l),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? context.colors.primaryTint : context.colors.inputBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? context.colors.primary : context.colors.divider,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 14,
                    color: isActive ? context.colors.primary : context.colors.textMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l.tr,
                    style: authText(13, c: isActive ? context.colors.primary : context.colors.textMedium),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class LangDropdown extends StatelessWidget {
  const LangDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LangProvider>();

    return GestureDetector(
      onTap: () async {
        final RenderBox button = context.findRenderObject() as RenderBox;
        final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

        const double dropdownSpacing = 20;

        final Offset topLeft = button.localToGlobal(
          Offset.zero,
          ancestor: overlay,
        );
        final Offset bottomRight = button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        );

        final Rect rect = Rect.fromPoints(
          topLeft.translate(0, dropdownSpacing),
          bottomRight.translate(0, dropdownSpacing),
        );

        final position = RelativeRect.fromRect(
          rect,
          Offset.zero & overlay.size,
        );
        final selected = await showMenu<String>(
          context: context,
          position: position,
          items: provider.languages.map((l) {
            return PopupMenuItem(value: l, child: Text(l.tr));
          }).toList(),
        );

        if (selected != null) {
          provider.changeLang(selected);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.language, size: 20, color: context.colors.primary),
          const SizedBox(width: 5),
          Text(AppConfig.lang.tr, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}
