// features/auth/auth_shell.dart
// ─────────────────────────────────────────────────────────────────────────────
// Shared "premium" chrome for every auth screen (same look as LoginScreen):
//   AuthScaffold  – sidebar + centered panel (web) / scrollable page (mobile),
//                   rebuilds when the language changes
//   AuthTopBar    – back button (when there is a page to go back to), logo,
//                   and the language + theme pill switches
//   AuthHeader    – accent line, big title, soft subtitle
//   AuthInfoBanner– small tinted hint with an icon
//   AuthPillSwitch / AuthLangSwitch / AuthThemeSwitch
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import 'auth_widgets.dart';

typedef AuthBodyBuilder = Widget Function(BuildContext context, bool isWide);

// ── Page scaffold ────────────────────────────────────────────────────────────
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.builder,
    this.maxWidth = 480,
    this.pageKey,
    required this.title,
  });

  /// Builds the page content. It is called again whenever the language changes,
  /// so every `.tr` text refreshes.
  final AuthBodyBuilder builder;
  final String title;

  /// Max width of the form panel on wide (web) screens.
  final double maxWidth;

  final Key? pageKey;

  @override
  Widget build(BuildContext context) {
    return Consumer<LangProvider>(
      builder: (context, l, _) {
        final isWide = MediaQuery.of(context).size.width > 800;
        return BasePage(
          appBar: ScreenAppBar(title: title, showBack: true,background:context.colors.primary, titleColor: context.colors.onHero,),
          key: pageKey,
          child: isWide
              ? Row(
                  children: [
                    AuthSidebar(),
                    Spacer(),
                    Container(
                      constraints:  BoxConstraints(maxWidth: maxWidth),
                      margin: EdgeInsets.all(10),
                      child: ClipRRect(
                        borderRadius: BorderRadiusGeometry.circular(
                          context.colors.radiusXL,
                        ),
                        child: ColoredBox(
                          color: context.colors.isDark
                              ? context.colors.cardBg
                              : context.colors.primary.withAlpha(30),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 24,
                            ),
                            child: ConstrainedBox(
                              constraints:  BoxConstraints(maxWidth: maxWidth),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 32,
                                ),
                                child: builder(context, true),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Spacer(),
                  ],
                )
              : Center(
                  child: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: builder(context, false),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

// ── Top bar: [back] logo ............ [lang / theme switches] ────────────────
class AuthTopBar extends StatelessWidget {
  const AuthTopBar({super.key, this.compact = false, this.showBack});

  /// Smaller logo, for long forms (register, complete profile, verification).
  final bool compact;

  /// null = show the back button only when there is a page to go back to.
  final bool? showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = compact ? 86.0 : 130.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppNetworkImage(
          url: 'assets/images/logo.png',
          width: size,
          height: size,
          heroTag: 'logo-login',
          fit: BoxFit.scaleDown,
          color: c.background,
        ),
        Container(
          width: 100,
          height: 5,
          decoration: BoxDecoration(
            gradient: c.accentGradient,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ],
    );
  }
}

// ── Header: accent line + title + subtitle ───────────────────────────────────
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: c.textDark,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.secondText,
            ),
          ),
        ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.primary.withAlpha(c.isDark ? 28 : 16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.primary.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline_rounded, size: 18, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Switches ─────────────────────────────────────────────────────────────────
Gradient _switchGradient(BuildContext context, bool dark) => dark
    ? LinearGradient(colors: [context.colors.heroShade, context.colors.heroTint(context.colors.heroShade, 0.12)])
    : context.colors.accentGradient;

class AuthThemeSwitch extends StatelessWidget {
  const AuthThemeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final dark = provider.darkMode;
    return AuthPillSwitch(
      tooltip: dark ? 'Light' : 'Dark',
      isEnd: dark,
      dark: dark,
      gradient: _switchGradient(context, dark),
      knob: Icon(
        dark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
        key: ValueKey(dark),
        color: dark ? context.colors.primary : context.colors.warning,
        size: 18,
      ),
      onTap: () => provider.changeMode(!provider.darkMode),
    );
  }
}

class AuthLangSwitch extends StatelessWidget {
  const AuthLangSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.watch<ProfileProvider>().darkMode;
    final ar = AppConfig.lang == 'ar';
    return AuthPillSwitch(
      tooltip: ar ? 'English' : 'العربية',
      isEnd: ar,
      // EN on the left, AR on the right
      dark: dark,
      gradient: _switchGradient(context, dark),
      knob: Text(
        ar ? 'ع' : 'EN',
        key: ValueKey(ar),
        style: TextStyle(
          fontFamily: 'tajawal',
          fontSize: ar ? 17 : 12,
          fontWeight: FontWeight.w800,
          color: dark ? context.colors.primary : context.colors.primary,
        ),
      ),
      onTap: () => context.read<LangProvider>().changeLang(ar ? 'en' : 'ar'),
    );
  }
}

/// Animated pill toggle shared by the theme and language switches.
class AuthPillSwitch extends StatelessWidget {
  const AuthPillSwitch({
    super.key,
    required this.isEnd,
    required this.dark,
    required this.gradient,
    required this.knob,
    required this.onTap,
    required this.tooltip,
  });

  final bool isEnd;
  final bool dark;
  final Gradient gradient;
  final Widget knob;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final alignment = isEnd ? Alignment.centerRight : Alignment.centerLeft;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 72,
          height: 38,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: context.colors.heroShade.withAlpha(dark ? 80 : 30),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          // Force LTR inside so the knob always slides the same physical way.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              alignment: alignment,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Container(
                  key: ValueKey('$isEnd$dark'),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.onHero,
                    shape: BoxShape.circle,
                  ),
                  child: knob,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
