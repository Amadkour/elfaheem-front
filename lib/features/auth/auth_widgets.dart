// auth_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────
// The auth design language (D-073, Warm Editorial D-610 – D-629): every sign-in screen is built from these pieces,
// so one change here restyles login, register, forgot password, the code screens and the teacher's profile step
// together. Colours come from the live theme (`context.colors`), headings are the editorial roles (`AppType`), the
// wells and the field labels are the kit's (`appFieldDecoration`, system.md §3a), motion parks under Reduce motion.
//
//   authText / authTracking         the older auth type helper (the person's font; kept for callers outside)
//   AuthLogoTile · AuthBrandName    the app-icon style logo on paper and the editorial wordmark
//   AuthSidebar                     the brand panel of the wide layout: the brand gradient block (D-649)
//   AuthCard · AuthEntrance         the paper form surface and the page's one orchestrated entrance
//   authInputDecoration             = the kit's well (appFieldDecoration)
//   IconTextField · IconPasswordField · AuthEmailField · AuthDateField   the fields (label above)
//   AuthButton                      the solid emerald primary: 56 high, press depth, busy, haptic
//   AuthTextAction · LinkRow        secondary actions (paper chips, an inline link)
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
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_buttons.dart' show appFocusRing, appKeyboardFocus;
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_gradients.dart'
    show AppBrandInk, AppBrandLabel, AppBrandLayer, AppBrandPanel, AppBrandSpan, AppGradientIcon, AppHeadingHalo, BrandInk;
import 'package:flutter_education_app/design/app_inputs.dart'
    show validateEmail, kEmailRegex, appFieldDecoration, appFieldTextStyle, appFieldFocusInk;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppEase, AppPressScale;
import 'package:flutter_education_app/design/app_tokens.dart';
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

/// The older auth type helper: the current language's font, explicit size / weight / line height. The other
/// language's font is the fallback, so an Arabic word in English UI (and the reverse) still draws. New auth UI uses
/// the `AppType` roles; this stays for the fields outside the module that still call it.
TextStyle authText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h, double? ls}) => TextStyle(
      fontFamily: AppFonts.family,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: size,
      fontWeight: w,
      color: c,
      height: h,
      letterSpacing: ls,
    );

/// The logo as an app icon: the admin's logo (or the bundled mark) on a paper tile with a warm hairline — it sits on
/// the canvas or on a block, so it does not float (D-612). [hero] gives it the shared `auth-logo` Hero tag, so it
/// flies between the auth pages (one per page).
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
          padding: EdgeInsets.all(size * 0.16),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: size > AppTouch.min ? AppRadius.cardAll : AppRadius.controlAll,
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: url != null && url.isNotEmpty
              ? AppNetworkImage(url: url, fit: BoxFit.contain, color: c.cardBg)
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

/// The app's name as an editorial wordmark (the boot splash's) + its tagline, as the admin set them (fallbacks
/// before the first fetch). Ink on the canvas or on a block; [onHero] is kept for older callers.
class AuthBrandName extends StatelessWidget {
  const AuthBrandName({super.key, this.onHero = true, this.large = false, this.ink, this.muted});

  final bool onHero;
  final bool large;

  /// The name's and the tagline's ink on a coloured surface (the brand panel); null = the canvas ink.
  final Color? ink;
  final Color? muted;

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
              id.name.isNotEmpty ? id.name : 'NextBrain',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (large ? AppType.pageTitle(context) : AppType.section(context)).copyWith(color: ink ?? c.textDark, height: 1.1),
            ),
            Text(
              id.tagline.isNotEmpty ? id.tagline : 'learning_platform'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: muted),
            ),
          ],
        );
      },
    );
  }
}

// ── 1. Brand panel (wide layout) ──────────────────────────────────────────────

/// The brand panel of the wide layout: the forest → emerald gradient block with the faint lattice (D-649) — the logo and wordmark, the
/// editorial headline as the page's memorable line, the mission, three things the platform does, and the admin's
/// "About us" figures counting up once, in the cream ink.
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
    final w = width ?? (context.width / 3 > 400 ? 400 : context.width / 3);
    final narrow = w < 320;
    final inner = narrow ? AppSpace.md : AppSpace.xl;
    return SizedBox(
      width: w,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, 0, AppSpace.md),
          // D-650 r3: the 60 / 40 brand panel (green held to 60 %, then the blend to the cream, top → bottom, the faint
          // lattice); each line picks its ink from the colour under it (AppBrandInk): cream / on-hero on the green, a
          // dark ink on the cream (the figures at the foot)
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.block),
            child: AppBrandPanel(
            borderRadius: BorderRadius.circular(AppRadius.block),
            child: Padding(
            padding: EdgeInsets.all(inner),
            child: Builder(builder: (context) {
              return CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AuthLogoTile(size: AppTouch.min, hero: true),
                            // a very narrow panel (the password page's third of a phone) keeps the logo only
                            if (!narrow) ...[
                              const SizedBox(width: AppSpace.sm),
                              Expanded(
                                child: AppBrandInk(
                                  builder: (context, k) => AuthBrandName(large: true, ink: k.ink, muted: k.muted),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Spacer(),
                        const SizedBox(height: AppSpace.xxl),
                        AppBrandInk(
                          builder: (context, k) => Semantics(
                            header: true,
                            child: Text(
                              'unlock_potential'.tr,
                              style: AppType.display(context).copyWith(color: k.ink),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        AppBrandInk(
                          builder: (context, k) => Text(
                            id.mission.isNotEmpty ? id.mission : 'join_students_hint'.tr,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.body(context).copyWith(color: k.muted, height: 1.6),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        _SidebarFeature(icon: Icons.live_tv_rounded, text: 'feature_live_sessions'.tr),
                        const SizedBox(height: AppSpace.sm),
                        _SidebarFeature(icon: Icons.groups_rounded, text: 'feature_expert_teachers'.tr),
                        const SizedBox(height: AppSpace.sm),
                        _SidebarFeature(icon: Icons.insights_rounded, text: 'feature_assessments'.tr),
                        const Spacer(),
                        const SizedBox(height: AppSpace.xl),
                        // the stats banner of the admin's "About us" page (the fixed badges until the admin adds some)
                        AppBrandInk(
                          builder: (context, k) => Divider(
                              height: AppBorder.hairline, thickness: AppBorder.hairline, color: k.glassBorder),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        if (id.stats.isNotEmpty)
                          Wrap(
                            spacing: AppSpace.xl,
                            runSpacing: AppSpace.md,
                            children: [
                              for (final st in id.stats.take(4)) _SidebarStat(value: st.value, label: st.label),
                            ],
                          )
                        else
                          Wrap(
                            spacing: AppSpace.lg,
                            runSpacing: AppSpace.xs,
                            children: [
                              _TrustBadge(label: 'badge_students'.tr),
                              _TrustBadge(label: 'badge_teachers'.tr),
                              _TrustBadge(label: 'badge_secure'.tr),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
            ),
            ),
          ),
        ),
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
          color: context.colors.textDark.withValues(alpha: opacity),
        ),
      );
}

/// One thing the platform does: a paper well with the icon in the block's ink, the line beside it.
class _SidebarFeature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SidebarFeature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => AppBrandInk(builder: _row);

  Widget _row(BuildContext context, BrandInk ink) {
    return Row(
      children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          // a glass well on the brand panel (D-649), the glyph in the brand family for the spot (D-650 r3)
          decoration: BoxDecoration(
            color: ink.activeFill,
            borderRadius: AppRadius.chipAll,
            border: Border.all(color: ink.glassBorder, width: AppBorder.hairline),
          ),
          child: AppGradientIcon(icon, size: AppIconSize.md, on: ink.activeSurfaces),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(text, style: AppType.row(context).copyWith(color: ink.ink, height: 1.4)),
        ),
      ],
    );
  }
}

/// A login stat as one style, whatever the admin typed: Eastern Arabic / Persian digits become the app's Western
/// digits, and a plain number of five digits or more gets thousands separators ("٦٠٠٠٠" → "60,000", "٥٠+" → "50+").
String loginStatValue(String raw) {
  final b = StringBuffer();
  for (final r in raw.trim().runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066C) {
      b.write(',');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString().replaceAllMapped(RegExp(r'(?<![\d.,])\d{5,}(?![\d.,])'), (m) {
    final d = m[0]!;
    final out = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && (d.length - i) % 3 == 0) out.write(',');
      out.write(d[i]);
    }
    return out.toString();
  });
}

/// One figure of the admin's "About us" banner: the number counts up once in the block's ink (tabular, left to
/// right), its label under it in the muted ink. No box around it: the block is the surface.
class _SidebarStat extends StatelessWidget {
  final String value;
  final String label;

  const _SidebarStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => AppBrandInk(builder: _stat);

  Widget _stat(BuildContext context, BrandInk ink) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCountUp(
            loginStatValue(value),
            memoryKey: 'auth.stat.$label',
            textDirection: TextDirection.ltr,
            style: AppType.figureLarge(context).copyWith(color: ink.ink),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(color: ink.muted, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// A fixed promise (before the admin adds figures): a check in the success ink and the line in the block's ink.
class _TrustBadge extends StatelessWidget {
  final String label;

  const _TrustBadge({required this.label});

  @override
  Widget build(BuildContext context) => AppBrandInk(builder: _badge);

  Widget _badge(BuildContext context, BrandInk ink) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // a status glyph: the success ink, made to read on the spot (3:1)
          Icon(Icons.check_rounded, size: AppIconSize.sm, color: ensureContrast(c.success, ink.surfaces, min: 3)),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(label, style: AppType.label(context).copyWith(color: ink.ink))),
        ],
      ),
    );
  }
}

// ── 2. Surfaces ───────────────────────────────────────────────────────────────

/// The form surface of the wide layout: paper on the canvas with a warm hairline, radius `card`, no resting shadow
/// (D-612: depth is tone first; dark mode keeps the hairline).
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.lg)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
        boxShadow: AppShadow.card(context),
      ),
      child: child,
    );
  }
}

/// The page's one orchestrated entrance (choreograph): the lead fades in and rises [rise] px on its first build;
/// a supporting part passes a [delayFactor] (0..1 = up to 120 ms later) and a shorter rise, so the two read as one
/// wave, never a queue. Nothing moves under Reduce motion, and the form is usable from its first frame.
class AuthEntrance extends StatelessWidget {
  const AuthEntrance({super.key, required this.child, this.delayFactor = 0, this.rise = 12});

  final Widget child;

  /// 0..1: a later part starts a little later.
  final double delayFactor;

  /// How far the part rises into place.
  final double rise;

  @override
  Widget build(BuildContext context) {
    if (authReduceMotion(context)) return child;
    const run = 420;
    final delay = (delayFactor.clamp(0.0, 1.0) * 120).round();
    final total = run + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: AppEase.out),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, rise * (1 - t)), child: child),
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

/// The auth field look = the kit's well (system.md §3a): the warm input fill, radius 14, a hairline at rest, the
/// 2 px ring on focus, the danger hairline on an error; the prefix icon follows the state (muted → focus → danger).
/// The label is drawn ABOVE the well by the field ([SectionLabel]).
InputDecoration authInputDecoration(
  BuildContext context, {
  String? hint,
  IconData? icon,
  Widget? suffix,
  bool dense = false,
}) {
  final base = appFieldDecoration(context, hint: hint, icon: icon, suffix: suffix, dense: dense);
  // a validator's message can be long (an e-mail rule with an example): three lines before it ellipsizes
  return base.copyWith(errorMaxLines: 3);
}

/// The style of what the person types (the kit's field text).
TextStyle authFieldText(BuildContext context) => appFieldTextStyle(context);

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

/// The primary action (system.md §4): the SOLID emerald, 56 high (the phone's hero action), radius 14, the label at
/// 15 · 600 in the on-primary ink, no shadow and no gloss — a button does not float. A press sinks it to 0.97, the
/// keyboard's focus draws the kit's 2 px ring outside it, [loading] swaps the label for a spinner (taps ignored),
/// and a disabled button is a flat neutral well. It is a FilledButton underneath, so the keyboard support (Enter on
/// the last field) and screen readers treat it as the form's button.
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

  /// null = the primary; a (deep) colour paints the button in that colour instead.
  final Color? tone;

  @override
  State<AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<AuthButton> {
  final _states = WidgetStatesController();

  /// Where the label sits, so the brand fill keeps its cream end past it (D-650 r2).
  final _span = AppBrandSpan();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  void _onStates() {
    final f = _states.value.contains(WidgetState.focused);
    if (f != _focused && mounted) setState(() => _focused = f);
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
    final base = widget.tone ?? c.primary;
    final deep = widget.tone == null ? c.primaryDark : Color.lerp(base, c.textDark, 0.3)!;
    final fg = lit ? c.onHero : c.textMedium;
    // D-649: the brand button (no tone) is the gradient primary → primary_dark on a soft tinted shadow
    final brand = widget.tone == null && lit;
    final radius = AppRadius.controlAll;

    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppType.bodyStrong(context).copyWith(color: fg, fontSize: 15, height: 1.2),
    );
    final icon = widget.icon == null ? null : Icon(widget.icon, size: AppIconSize.md, color: fg);
    final content = AnimatedSwitcher(
      duration: AppMotion.of(context).fast,
      switchInCurve: AppEase.out,
      switchOutCurve: AppEase.out,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
      ),
      child: widget.loading
          ? SizedBox(
              key: const ValueKey('busy'),
              width: AppIconSize.md,
              height: AppIconSize.md,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: c.onHero),
            )
          : AppBrandLabel(
              key: const ValueKey('label'),
              span: _span,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null && widget.iconBefore) ...[icon, const SizedBox(width: AppSpace.xs)],
                  Flexible(child: label),
                  if (icon != null && !widget.iconBefore) ...[const SizedBox(width: AppSpace.xs), icon],
                ],
              ),
            ),
    );

    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: box.hasBoundedWidth ? double.infinity : null,
        child: AppPressScale(
          scale: 0.97,
          enabled: active,
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            curve: AppEase.out,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: _focused && active && appKeyboardFocus()
                  ? appFocusRing(context)
                  : brand
                      ? AppBrandLayer.buttonShadow(context)
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
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.lg)),
                minimumSize: const WidgetStatePropertyAll(Size(AppTouch.primary, AppTouch.primary)),
                elevation: const WidgetStatePropertyAll(0),
                shadowColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                foregroundColor: WidgetStatePropertyAll(fg),
                backgroundColor: WidgetStateProperty.resolveWith((s) {
                  if (!lit) return c.inputBg;
                  if (brand) return Colors.transparent;
                  if (s.contains(WidgetState.pressed)) return Color.lerp(base, deep, 0.5);
                  if (s.contains(WidgetState.hovered)) return Color.lerp(base, deep, 0.22);
                  return base;
                }),
                side: WidgetStatePropertyAll(lit ? BorderSide.none : BorderSide(color: c.divider, width: AppBorder.hairline)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
                // the brand gradient (D-649) or the solid fill above, not the theme's painter for raw FilledButtons
                backgroundBuilder: (context, states, child) => brand
                    ? DecoratedBox(
                        decoration: AppBrandLayer.buttonFill(context,
                            hover: states.contains(WidgetState.hovered),
                            pressed: states.contains(WidgetState.pressed),
                            span: _span,
                            borderRadius: radius),
                        child: child ?? const SizedBox.shrink(),
                      )
                    : child ?? const SizedBox.shrink(),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet secondary action (guest mode, apply as an institution, verify a certificate): a paper chip with a warm
/// hairline, the icon muted and the label in ink — the emerald stays on the one primary action. 48 dp tall.
class AuthTextAction extends StatelessWidget {
  const AuthTextAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppPressScale(
      enabled: onTap != null,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlAll,
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: AppIconSize.sm, color: c.textMedium),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: AppType.label(context).copyWith(color: c.textDark, height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Message  Link" — wraps on a narrow phone; the link has a 48 dp target and the primary's readable ink.
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
    final ink = appInk(context, context.colors.primary);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(message, style: AppType.body(context)),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(AppTouch.min, AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            foregroundColor: ink,
          ),
          child: Text(linkText, style: AppType.bodyStrong(context).copyWith(color: ink)),
        ),
      ],
    );
  }
}

/// A warm hairline either side of a small label in the middle ("or").
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget line() => Expanded(child: Container(height: AppBorder.hairline, color: c.divider));
    return Row(
      children: [
        line(),
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            // D-650 r3: on the doodle canvas the label gets the page-colour halo when the doodles would drop it below AA
            child: AppHeadingHalo(child: Text(label, textAlign: TextAlign.center, style: AppType.meta(context))),
          ),
        ),
        line(),
      ],
    );
  }
}

// ── 5. Password strength + requirements ───────────────────────────────────────

/// Four segments that fill with the strength (0..4) and its word at the end. [color] is the strength's colour (the
/// segments take it as is; the word takes its readable ink).
class AuthPasswordStrength extends StatelessWidget {
  const AuthPasswordStrength({super.key, required this.strength, required this.label, required this.color, this.title});

  final int strength;
  final String label;
  final Color color;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = AppMotion.of(context).slow;
    return Semantics(
      label: '${title ?? ''} $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: AnimatedContainer(
                    duration: d,
                    curve: AppEase.out,
                    height: AppSpace.xxs,
                    decoration: BoxDecoration(
                      color: i < strength ? color : c.divider,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              if (title != null)
                Expanded(child: Text(title!, style: AppType.meta(context)))
              else
                const Spacer(),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AnimatedSwitcher(
                    duration: d,
                    child: Text(
                      label,
                      key: ValueKey(label),
                      textAlign: TextAlign.end,
                      style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, color)),
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

/// One line of a requirement checklist: an empty ring that turns into the success check when [met].
class AuthRequirement extends StatelessWidget {
  const AuthRequirement({super.key, required this.met, required this.label});

  final bool met;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = AppMotion.of(context).base;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: d,
            switchInCurve: AppEase.out,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: child),
            ),
            child: Icon(
              met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              key: ValueKey(met),
              size: AppIconSize.sm + 2,
              color: met ? c.success : c.textLight,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: d,
              style: AppType.label(context).copyWith(
                fontWeight: met ? FontWeight.w600 : FontWeight.w500,
                color: met ? c.textDark : c.textMedium,
                height: 1.4,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 6. Code box ───────────────────────────────────────────────────────────────

/// One box of a one-time code. The caller puts its TextField in [child]; the box draws the state in the kit's well
/// language: empty (the input fill, a hairline), filled (paper, an ink hairline), focused (the 2 px focus ring),
/// error (the danger tint and a danger line).
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

  /// The digit style: the large figure role (tabular digits).
  static TextStyle digitStyle(BuildContext context) => AppType.figureLarge(context).copyWith(height: 1.0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color border;
    final Color bg;
    if (error) {
      border = c.danger;
      bg = c.dangerTint;
    } else if (focused) {
      border = appFieldFocusInk(context);
      bg = c.inputBg;
    } else if (filled) {
      border = Color.lerp(c.divider, c.textDark, 0.35)!;
      bg = c.cardBg;
    } else {
      border = c.divider;
      bg = c.inputBg;
    }
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      curve: AppEase.out,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: border, width: focused || error ? AppBorder.focus : AppBorder.hairline),
      ),
      child: child,
    );
  }
}

// ── 7. Screen icon header ─────────────────────────────────────────────────────

/// The mark at the top of a one-subject screen (the two-step code, re-entering the password): the icon in the
/// primary's readable ink on the emerald block tint.
class ScreenIcon extends StatelessWidget {
  final IconData icon;

  const ScreenIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) => AuthMark(icon: icon);
}

/// A subject's mark at any size (a sheet's header, a step's title): the emerald block tint, no shadow, the icon in
/// the primary's readable ink; radius `card` from 56 up, `control` below.
class AuthMark extends StatelessWidget {
  const AuthMark({super.key, required this.icon, this.size = AppTouch.primary});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = AppBlockColors.of(context, AppBlockTone.emerald);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: size >= AppTouch.primary ? AppRadius.cardAll : AppRadius.controlAll,
        border: tone.border == null ? null : Border.all(color: tone.border!, width: AppBorder.hairline),
      ),
      child: Icon(icon, color: tone.accentInk(c.primary), size: size >= AppTouch.primary ? AppIconSize.lg : AppIconSize.md),
    );
  }
}

// ── 8. Field label ────────────────────────────────────────────────────────────

/// The label above a well (the kit's label role).
class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Text(label, style: AppType.label(context).copyWith(height: 1.3));
}

// ── 9. Progress bar (step indicator) ─────────────────────────────────────────

/// The register steps: one slim segment per step, the done ones in the solid primary.
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
              duration: AppMotion.of(context).slow,
              curve: AppEase.out,
              margin: EdgeInsetsDirectional.only(end: i < totalSteps - 1 ? AppSpace.xxs : 0),
              height: AppSpace.xxs + 2,
              decoration: BoxDecoration(
                color: done ? c.primary : c.divider,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── 10. Role picker cards ─────────────────────────────────────────────────────

/// Who is signing up: one paper card per role; the chosen one takes the primary tint, a 2 px primary edge, the icon
/// on the solid primary and a check that settles in (from 60 %, never from nothing).
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
    final d = AppMotion.of(context).base;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: provider.roles.map<Widget>((role) {
        final isSelected = provider.selectedRole == role;
        final teacher = role['text'] == 'teacher';
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
            child: Semantics(
              button: true,
              selected: isSelected,
              child: AppPressScale(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadius.cardAll,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      provider.onChangeRole(provider.roles.indexOf(role), rolController);
                    },
                    child: AnimatedContainer(
                      duration: d,
                      curve: AppEase.out,
                      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.sm),
                      decoration: BoxDecoration(
                        color: isSelected ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
                        borderRadius: AppRadius.cardAll,
                        border: Border.all(
                          color: isSelected ? c.primary : c.divider,
                          width: isSelected ? AppBorder.focus : AppBorder.hairline,
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
                                  duration: d,
                                  curve: AppEase.out,
                                  width: AppTouch.min - AppSpace.xxs,
                                  height: AppTouch.min - AppSpace.xxs,
                                  decoration: BoxDecoration(
                                    color: isSelected ? c.primary : c.inputBg,
                                    borderRadius: AppRadius.controlAll,
                                  ),
                                  child: Icon(
                                    teacher
                                        ? Icons.cast_for_education_rounded
                                        : role['text'] == 'parent'
                                            ? Icons.family_restroom_rounded
                                            : Icons.school_rounded,
                                    color: isSelected ? c.onHero : c.textMedium,
                                    size: AppIconSize.md + 2,
                                  ),
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  role['text'].toString().tr,
                                  textAlign: TextAlign.center,
                                  style: AppType.row(context).copyWith(
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    color: isSelected ? c.textDark : c.textMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PositionedDirectional(
                            top: -AppSpace.xs,
                            end: -AppSpace.xxs,
                            child: AnimatedOpacity(
                              opacity: isSelected ? 1 : 0,
                              duration: d,
                              curve: AppEase.out,
                              child: AnimatedScale(
                                scale: isSelected ? 1 : 0.6,
                                duration: d,
                                curve: AppEase.out,
                                child: Icon(Icons.check_circle_rounded, size: AppIconSize.md, color: appInk(context, c.primary)),
                              ),
                            ),
                          ),
                        ],
                      ),
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
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm + 2, AppSpace.md + 4, 0, 0),
            child: Icon(icon, size: AppIconSize.md, color: c.textLight),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xs + 2, 0, AppSpace.xs + 2, AppSpace.xxs + 1),
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
          Text(AppConfig.lang.tr, style: AppType.label(context)),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}
