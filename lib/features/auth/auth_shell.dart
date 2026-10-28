// features/auth/auth_shell.dart
// ─────────────────────────────────────────────────────────────────────────────
// The page chrome of every auth screen (D-073):
//   AuthScaffold  – BasePage + AuthLayout + the language / theme switches; rebuilds when the language changes
//   AuthLayout    – plain values (no provider), so the layout harness can pump it:
//                   phone / tablet: a brand-gradient hero (back · logo + name · switches, then the page's
//                   title and subtitle in on-hero ink) with the form card rising over its rounded bottom;
//                   wide (≥ 900): the brand panel (AuthSidebar) beside a calm surface holding the form card
//                   (title inside the card, max width [AuthLayout.maxWidth]).
//   AuthHeroBar   – back · logo tile · app name / tagline · actions, on the hero
//   AuthHeader    – title + subtitle inside the card (wide) or anywhere on a surface
//   AuthInfoBanner– small tinted hint with an icon
//   AuthTopBar    – a compact logo + name row (kept for screens that draw their own page)
//   AuthLangSwitch / AuthThemeSwitch / AuthSwitches – glass on the hero, quiet on a surface
// The form scrolls (keyboard-aware, dismissed by a drag), safe areas are respected and every target is 48 dp.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import 'auth_widgets.dart';

typedef AuthBodyBuilder = Widget Function(BuildContext context, bool isWide);

/// Window width from which the brand panel sits beside the form.
const double kAuthWideBreakpoint = 900;

// ── Page scaffold ────────────────────────────────────────────────────────────
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.builder,
    this.maxWidth = 440,
    this.pageKey,
    required this.title,
    this.subtitle,
    this.showBack,
    this.header = true,
  });

  /// Builds the page content. It is called again whenever the language changes,
  /// so every `.tr` text refreshes.
  final AuthBodyBuilder builder;

  /// The page's heading (on the hero on phones, inside the card on wide screens).
  final String title;
  final String? subtitle;

  /// Max width of the form card.
  final double maxWidth;

  /// The BasePage key (a `ValueKey('<feature id>')` turns the page into "coming soon" when switched off).
  final Key? pageKey;

  /// null = a back button only when there is a page to go back to.
  final bool? showBack;

  /// false = no title block (the body draws its own heading).
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Consumer<LangProvider>(
      builder: (context, l, _) => BasePage(
        key: pageKey,
        child: AuthLayout(
          title: title,
          subtitle: subtitle,
          maxWidth: maxWidth,
          showBack: showBack,
          header: header,
          actions: (onHero) => AuthSwitches(onHero: onHero),
          body: builder,
        ),
      ),
    );
  }
}

/// The auth page layout from plain values. [actions] draws the switches (on the hero when its argument is true).
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.body,
    required this.title,
    this.subtitle,
    this.maxWidth = 440,
    this.showBack,
    this.header = true,
    this.actions,
  });

  final AuthBodyBuilder body;
  final String title;
  final String? subtitle;
  final double maxWidth;
  final bool? showBack;
  final bool header;
  final Widget Function(bool onHero)? actions;

  @override
  Widget build(BuildContext context) {
    final canBack = showBack ?? (ModalRoute.of(context)?.canPop ?? false);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= kAuthWideBreakpoint
          ? _wide(context, box, canBack)
          : _narrow(context, box, canBack),
    );
  }

  // ── phone / tablet ──────────────────────────────────────────────────────
  Widget _narrow(BuildContext context, BoxConstraints box, bool canBack) {
    final mq = MediaQuery.of(context);
    final compact = box.maxHeight < 700;
    const overlap = 36.0;
    final hero = Stack(
      children: [
        const Positioned.fill(child: AuthHeroBackdrop(radius: 32)),
        Padding(
          padding: EdgeInsets.fromLTRB(12, mq.padding.top + 8, 12, (header ? 24 : 16) + overlap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthHeroBar(showBack: canBack, actions: actions?.call(true)),
              if (header) ...[
                SizedBox(height: compact ? 16 : 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _HeroTitle(title: title, subtitle: subtitle),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // the card's lift leaves [overlap] px of breathing room below it
        padding: EdgeInsets.only(bottom: mq.padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            Transform.translate(
              offset: const Offset(0, -overlap),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth + 32),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AuthEntrance(
                      child: AuthCard(
                        child: Builder(builder: (context) => body(context, false)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── wide: brand panel + form card ───────────────────────────────────────
  Widget _wide(BuildContext context, BoxConstraints box, bool canBack) {
    final c = context.colors;
    final panel = (box.maxWidth * 0.42).clamp(380.0, 560.0);
    return Row(
      children: [
        AuthSidebar(width: panel),
        Expanded(
          child: Stack(
            children: [
              // a faint brand glow in the corner keeps the surface from feeling empty
              PositionedDirectional(
                top: -220,
                end: -180,
                child: Container(
                  width: 520,
                  height: 520,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [c.primary.withValues(alpha: c.isDark ? 0.16 : 0.08), c.primary.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        children: [
                          if (canBack) const AuthBackButton(onHero: false),
                          const Spacer(),
                          if (actions != null) actions!(false),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: AuthEntrance(
                              child: AuthCard(
                                padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
                                child: Builder(
                                  builder: (context) => Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (header) ...[
                                        AuthHeader(title: title, subtitle: subtitle),
                                        const SizedBox(height: 28),
                                      ],
                                      body(context, true),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: authText(28, w: FontWeight.w800, c: c.onHero, h: 1.2, ls: authTracking(-0.4))),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: authText(15, c: c.onHeroMuted, h: 1.5)),
          ],
        ],
      ),
    );
  }
}

// ── Hero bar: [back] logo name ............ [switches] ───────────────────────
class AuthHeroBar extends StatelessWidget {
  const AuthHeroBar({super.key, this.showBack = false, this.actions});

  final bool showBack;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack) ...[const AuthBackButton(onHero: true), const SizedBox(width: 4)] else const SizedBox(width: 12),
        const AuthLogoTile(size: 40, hero: true),
        const SizedBox(width: 10),
        const Expanded(child: AuthBrandName()),
        const SizedBox(width: 8),
        if (actions != null) actions!,
      ],
    );
  }
}

/// A round back button (48 dp): glass on the hero, quiet on a surface. The arrow mirrors itself in Arabic.
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, this.onHero = true});

  final bool onHero;

  @override
  Widget build(BuildContext context) => _RoundButton(
        onHero: onHero,
        tooltip: AppConfig.lang == 'ar' ? 'رجوع' : 'Back',
        onTap: () => Navigator.of(context).maybePop(),
        child: Icon(Icons.arrow_back_rounded, size: 20, color: onHero ? context.colors.onHero : context.colors.textDark),
      );
}

/// 48 dp hit area around a 40 dp visual circle (or pill when [child] is wider).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.onHero, required this.tooltip, required this.onTap, required this.child, this.semanticLabel});

  final bool onHero;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: semanticLabel ?? tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              widthFactor: 1,
              child: Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: onHero ? c.heroGlass : c.cardBg,
                  shape: StadiumBorder(
                    side: BorderSide(color: onHero ? c.heroGlassBorder : c.divider.withValues(alpha: c.isDark ? 0.9 : 0.75)),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header: title + subtitle (on a surface) ──────────────────────────────────
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: authText(26, w: FontWeight.w800, c: c.textDark, h: 1.2, ls: authTracking(-0.4))),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: authText(15, c: c.secondText, h: 1.5)),
          ],
        ],
      ),
    );
  }
}

// ── Compact logo + name row (for screens that draw their own page) ───────────
class AuthTopBar extends StatelessWidget {
  const AuthTopBar({super.key, this.compact = false, this.showBack});

  /// Smaller logo, for long forms.
  final bool compact;

  /// Kept for older callers; the back button lives in the page chrome now.
  final bool? showBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AuthLogoTile(size: compact ? 40 : 52),
        const SizedBox(width: 12),
        const Flexible(child: AuthBrandName(onHero: false)),
      ],
    );
  }
}

// ── Small tinted hint (icon + text) ──────────────────────────────────────────
class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? c.primaryLight : c.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: c.isDark ? 0.14 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.primary.withValues(alpha: c.isDark ? 0.30 : 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: c.isDark ? 0.22 : 0.10), shape: BoxShape.circle),
            child: Icon(icon ?? Icons.info_outline_rounded, size: 17, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(text, style: authText(13.5, w: FontWeight.w500, c: c.textMedium, h: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Switches ─────────────────────────────────────────────────────────────────

/// Language + theme, side by side.
class AuthSwitches extends StatelessWidget {
  const AuthSwitches({super.key, this.onHero = true});

  final bool onHero;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [AuthLangSwitch(onHero: onHero), AuthThemeSwitch(onHero: onHero)],
      );
}

class AuthThemeSwitch extends StatelessWidget {
  const AuthThemeSwitch({super.key, this.onHero = true});

  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    return AuthThemeButton(
      dark: provider.darkMode,
      onHero: onHero,
      onTap: () => provider.changeMode(!provider.darkMode),
    );
  }
}

/// The theme toggle from plain values: a sun / moon that turns as it swaps.
class AuthThemeButton extends StatelessWidget {
  const AuthThemeButton({super.key, required this.dark, required this.onTap, this.onHero = true});

  final bool dark;
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final tip = dark ? (ar ? 'الوضع الفاتح' : 'Light mode') : (ar ? 'الوضع الداكن' : 'Dark mode');
    return _RoundButton(
      onHero: onHero,
      tooltip: tip,
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: authDuration(context, 320),
        transitionBuilder: (child, a) => RotationTransition(
          turns: Tween(begin: 0.6, end: 1.0).animate(a),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Icon(
          dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          key: ValueKey(dark),
          size: 19,
          color: onHero ? c.onHero : (dark ? c.primaryLight : c.warning),
        ),
      ),
    );
  }
}

class AuthLangSwitch extends StatelessWidget {
  const AuthLangSwitch({super.key, this.onHero = true});

  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    return AuthLangButton(
      arabic: ar,
      onHero: onHero,
      onTap: () => context.read<LangProvider>().changeLang(ar ? 'en' : 'ar'),
    );
  }
}

/// The language toggle from plain values: names the language it switches TO.
class AuthLangButton extends StatelessWidget {
  const AuthLangButton({super.key, required this.arabic, required this.onTap, this.onHero = true});

  final bool arabic;
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = onHero ? c.onHero : c.textDark;
    return _RoundButton(
      onHero: onHero,
      tooltip: arabic ? 'English' : 'العربية',
      semanticLabel: arabic ? 'Switch to English' : 'التبديل إلى العربية',
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.translate_rounded, size: 16, color: ink),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: authDuration(context, 220),
            child: Text(
              arabic ? 'EN' : 'عربي',
              key: ValueKey(arabic),
              style: authText(13, w: FontWeight.w700, c: ink, h: 1.1),
            ),
          ),
        ],
      ),
    );
  }
}
