// features/auth/auth_shell.dart
// ─────────────────────────────────────────────────────────────────────────────
// The page chrome of every auth screen (D-073, Warm Editorial D-610 – D-629):
//   AuthScaffold  – BasePage + AuthLayout + the language / theme switches; rebuilds when the language changes
//   AuthLayout    – plain values (no provider), so the layout harness can pump it:
//                   phone / tablet: the warm canvas — the brand row (back · logo + wordmark · switches), then the
//                   page's title and subtitle in ONE peach hero block (the editorial welcome), then the form right on
//                   the canvas (no card around it: one surface less);
//                   wide (≥ 900): the brand panel (AuthSidebar, a peach block inset on the canvas) beside a paper
//                   card holding the title and the form (max width [AuthLayout.maxWidth]).
//                   One orchestrated entrance: the block (or the card) rises first, the form follows a beat later.
//   AuthHeroBar   – back · logo tile · wordmark / tagline · actions
//   AuthHeader    – title + subtitle inside the card (wide) or anywhere on a surface
//   AuthInfoBanner– a small sky-tinted hint with an icon
//   AuthTopBar    – a compact logo + name row (kept for screens that draw their own page)
//   AuthLangSwitch / AuthThemeSwitch / AuthSwitches – paper chips on the canvas
// The form scrolls (keyboard-aware, dismissed by a drag), safe areas are respected and every target is 48 dp.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/display/app_fonts.dart';
import '../../design/app_blocks.dart';
import '../../design/app_motion_kit.dart' show AppEase;
import '../../design/app_tokens.dart';
import '../shared/legal/legal_links.dart' show LegalLinksRow;
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
    this.legalLinks = true,
  });

  /// Builds the page content. It is called again whenever the language changes,
  /// so every `.tr` text refreshes.
  final AuthBodyBuilder builder;

  /// The page's heading (in the hero block on phones, inside the card on wide screens).
  final String title;
  final String? subtitle;

  /// Max width of the form.
  final double maxWidth;

  /// The BasePage key (a `ValueKey('<feature id>')` turns the page into "coming soon" when switched off).
  final Key? pageKey;

  /// null = a back button only when there is a page to go back to.
  final bool? showBack;

  /// false = no title block (the body draws its own heading).
  final bool header;

  /// "Privacy policy · Terms of service" under the form (D-308; kill switch terms.links).
  final bool legalLinks;

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
          footer: legalLinks ? const LegalLinksRow() : null,
        ),
      ),
    );
  }
}

/// The auth page layout from plain values. [actions] draws the switches (its argument is kept for older callers;
/// the switches always sit on the canvas now).
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
    this.footer,
  });

  final AuthBodyBuilder body;
  final String title;
  final String? subtitle;
  final double maxWidth;
  final bool? showBack;
  final bool header;
  final Widget Function(bool onHero)? actions;

  /// Under the form (the legal links).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final canBack = showBack ?? (ModalRoute.of(context)?.canPop ?? false);
    final c = context.colors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // ink on the warm canvas: dark status-bar icons in light mode, light ones in dark mode
      value: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= kAuthWideBreakpoint
            ? _wide(context, box, canBack)
            : _narrow(context, box, canBack),
      ),
    );
  }

  // ── phone / tablet ──────────────────────────────────────────────────────
  Widget _narrow(BuildContext context, BoxConstraints box, bool canBack) {
    final mq = MediaQuery.of(context);
    final compact = box.maxHeight < 700;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom + AppSpace.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth + 2 * AppSpace.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: AuthHeroBar(showBack: canBack, actions: actions?.call(false)),
                ),
                SizedBox(height: compact ? AppSpace.sm : AppSpace.md),
                if (header) ...[
                  // the lead of the entrance: the welcome block
                  AuthEntrance(
                    child: AppBlock(
                      tone: AppBlockTone.peach,
                      hero: !compact,
                      child: _HeroTitle(title: title, subtitle: subtitle),
                    ),
                  ),
                  SizedBox(height: compact ? AppSpace.md : AppSpace.lg),
                ],
                // the support: the form follows a beat later, rising less
                AuthEntrance(
                  delayFactor: header ? 0.6 : 0,
                  rise: header ? 8 : 12,
                  child: Builder(builder: (context) => body(context, false)),
                ),
                if (footer != null) ...[
                  const SizedBox(height: AppSpace.lg),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── wide: brand panel + form card ───────────────────────────────────────
  Widget _wide(BuildContext context, BoxConstraints box, bool canBack) {
    final panel = (box.maxWidth * 0.42).clamp(380.0, 560.0);
    return Row(
      children: [
        AuthSidebar(width: panel),
        Expanded(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
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
                      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          AuthEntrance(
                            child: AuthCard(
                              padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.xl, AppSpace.xl, AppSpace.lg),
                              child: Builder(
                                builder: (context) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (header) ...[
                                      AuthHeader(title: title, subtitle: subtitle),
                                      const SizedBox(height: AppSpace.lg),
                                    ],
                                    body(context, true),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (footer != null) ...[
                            const SizedBox(height: AppSpace.md),
                            footer!,
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The welcome inside the hero block: the editorial display line in the block's ink, the subtitle in its muted ink.
class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ink = AppBlock.colorsOf(context);
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppType.display(context).copyWith(color: ink.ink)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(subtitle!, style: AppType.body(context).copyWith(color: ink.muted, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

// ── Hero bar: [back] logo wordmark ............ [switches] ───────────────────
class AuthHeroBar extends StatelessWidget {
  const AuthHeroBar({super.key, this.showBack = false, this.actions});

  final bool showBack;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    // a narrow phone with large text keeps back and the switches (targets stay 48 dp); the brand gives way first
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 360 || MediaQuery.textScalerOf(context).scale(1) <= 1;
      return Row(
        children: [
          if (showBack) ...[const AuthBackButton(onHero: false), const SizedBox(width: AppSpace.xxs)],
          if (roomy) ...[
            const AuthLogoTile(size: AppTouch.min - AppSpace.xs, hero: true),
            const SizedBox(width: AppSpace.sm),
            const Expanded(child: AuthBrandName(onHero: false)),
          ] else
            const Spacer(),
          const SizedBox(width: AppSpace.xs),
          if (actions != null) actions!,
        ],
      );
    });
  }
}

/// A back button (48 dp): a paper chip on the canvas. The arrow mirrors itself in Arabic.
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, this.onHero = true});

  /// Kept for older callers; the chip is paper wherever it sits.
  final bool onHero;

  @override
  Widget build(BuildContext context) => _RoundButton(
        tooltip: AppConfig.lang == 'ar' ? 'رجوع' : 'Back',
        onTap: () => Navigator.of(context).maybePop(),
        child: Icon(Icons.arrow_back_rounded, size: AppIconSize.md, color: context.colors.textDark),
      );
}

/// 48 dp hit area around a 40 dp paper chip (wider when [child] is): the card surface, a warm hairline, radius
/// `chip`, a press that sinks it a little (none under Reduce motion).
class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.tooltip, required this.onTap, required this.child, this.semanticLabel});

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const plate = AppTouch.min - AppSpace.xs;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.semanticLabel ?? widget.tooltip,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          child: Center(
            widthFactor: 1,
            child: AnimatedScale(
              scale: _down ? 0.94 : 1,
              duration: AppMotion.of(context).fast,
              curve: AppEase.out,
              child: Material(
                color: c.cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.chipAll,
                  side: BorderSide(color: c.divider, width: AppBorder.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onTap();
                  },
                  onHighlightChanged: (v) => setState(() => _down = v),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: plate, minHeight: plate),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs + 2),
                    alignment: Alignment.center,
                    child: widget.child,
                  ),
                ),
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
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppType.headline(context)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(subtitle!, style: AppType.body(context).copyWith(height: 1.5)),
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
        AuthLogoTile(size: compact ? AppTouch.min - AppSpace.xs : AppTouch.min + AppSpace.xxs),
        const SizedBox(width: AppSpace.sm),
        const Flexible(child: AuthBrandName(onHero: false)),
      ],
    );
  }
}

// ── Small tinted hint (icon + text) ──────────────────────────────────────────

/// A short piece of information: the sky block tint (system.md §5: sky = information), the icon and the line in the
/// block's ink.
class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = AppBlockColors.of(context, AppBlockTone.sky);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: AppRadius.cardAll,
        border: tone.border == null ? null : Border.all(color: tone.border!, width: AppBorder.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline_rounded, size: AppIconSize.md, color: tone.ink),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(text, style: AppType.label(context).copyWith(color: tone.ink, height: 1.5)),
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

/// The theme toggle from plain values: a sun / moon in ink that turns as it swaps.
class AuthThemeButton extends StatelessWidget {
  const AuthThemeButton({super.key, required this.dark, required this.onTap, this.onHero = true});

  final bool dark;

  /// Kept for older callers; the chip is paper wherever it sits.
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final tip = dark ? (ar ? 'الوضع الفاتح' : 'Light mode') : (ar ? 'الوضع الداكن' : 'Dark mode');
    return _RoundButton(
      tooltip: tip,
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: AppMotion.of(context).slow,
        switchInCurve: AppEase.out,
        transitionBuilder: (child, a) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(a),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Icon(
          dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          key: ValueKey(dark),
          size: AppIconSize.md,
          color: c.textDark,
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

/// The language toggle from plain values: names the language it switches TO, in that language.
class AuthLangButton extends StatelessWidget {
  const AuthLangButton({super.key, required this.arabic, required this.onTap, this.onHero = true});

  final bool arabic;

  /// Kept for older callers; the chip is paper wherever it sits.
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _RoundButton(
      tooltip: arabic ? 'English' : 'العربية',
      semanticLabel: arabic ? 'Switch to English' : 'التبديل إلى العربية',
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.translate_rounded, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs + 2),
          AnimatedSwitcher(
            duration: AppMotion.of(context).base,
            child: Text(
              arabic ? 'English' : 'عربي',
              key: ValueKey(arabic),
              // the other language's name: its own font is the fallback (Inter has no Arabic letters)
              style: AppType.label(context).copyWith(
                  color: c.textDark, fontWeight: FontWeight.w600, height: 1.1, fontFamilyFallback: AppFonts.fallback),
            ),
          ),
        ],
      ),
    );
  }
}
