// features/auth/auth_shell.dart
// ─────────────────────────────────────────────────────────────────────────────
// The page chrome of every auth screen (D-073; redesign Stu1Auth, phase 2 S-A):
//   AuthScaffold  – BasePage + AuthLayout + the language / theme switches; rebuilds when the language changes
//   AuthLayout    – plain values (no provider), so the layout harness can pump it. One student area scope (home):
//                   phone / tablet: the hero band (the area's radial gradient, the drifting shapes) with the brand row
//                   (back · logo + name · switches), the gold kicker and the hero line (one word carries the squiggle,
//                   M7); the form card rides up over the band's lower edge (AppHeroOverlap) with an optional glyph,
//                   its heading, one line and the form;
//                   wide (≥ 900): the same hero as a full-height panel on the reading-start side, the form card centred
//                   on the canvas beside it.
//   AuthHeroBar   – back · logo tile · wordmark / tagline · actions
//   AuthHeader    – title + subtitle inside the card (wide) or anywhere on a surface
//   AuthInfoBanner– a small sky-tinted hint with an icon
//   AuthTopBar    – a compact logo + name row (kept for screens that draw their own page)
//   AuthLangSwitch / AuthThemeSwitch / AuthSwitches – chips: glass on the hero, paper on the canvas
// The form scrolls (keyboard-aware, dismissed by a drag), safe areas are respected and every target is 48 dp.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/display/app_fonts.dart';
import '../../design/app_area.dart';
import '../../design/app_blocks.dart';
import '../../design/app_hero.dart';
import '../../design/app_motion_kit.dart' show AppEase, AppSquiggle;
import '../../design/app_responsive.dart' show Breakpoints;
import '../../design/app_tokens.dart';
import 'package:flutter_education_app/features/profile/legal/legal_links.dart' show LegalLinksRow;
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
    this.kicker,
    this.heroTitle,
    this.squiggle,
    this.heroSubtitle,
    this.glyph,
    this.glyphTone,
  });

  /// Builds the page content. It is called again whenever the language changes,
  /// so every `.tr` text refreshes.
  final AuthBodyBuilder builder;

  /// The card's heading (on the hero when [heroTitle] is null).
  final String title;
  final String? subtitle;

  /// Max width of the form.
  final double maxWidth;

  /// The BasePage key (a `ValueKey('<feature id>')` turns the page into "coming soon" when switched off).
  final Key? pageKey;

  /// null = a back button only when there is a page to go back to.
  final bool? showBack;

  /// false = no heading in the card (the body draws its own heading).
  final bool header;

  /// "Privacy policy · Terms of service" under the form (D-308; kill switch terms.links).
  final bool legalLinks;

  /// The hero: the gold line above the title, the hero line, its ONE squiggled word and (wide only) one line under it.
  final String? kicker;
  final String? heroTitle;
  final String? squiggle;
  final String? heroSubtitle;

  /// A large glyph above the card's heading (the design's key, lock, hourglass…) in [glyphTone].
  final IconData? glyph;
  final KitTone? glyphTone;

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
          kicker: kicker,
          heroTitle: heroTitle,
          squiggle: squiggle,
          heroSubtitle: heroSubtitle,
          glyph: glyph,
          glyphTone: glyphTone,
          actions: (onHero) => AuthSwitches(onHero: onHero),
          body: builder,
          footer: legalLinks ? const LegalLinksRow() : null,
        ),
      ),
    );
  }
}

/// The auth page layout from plain values. [actions] draws the switches; its argument says whether they sit on the
/// hero (glass) or on the canvas (paper).
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
    this.kicker,
    this.heroTitle,
    this.squiggle,
    this.heroSubtitle,
    this.glyph,
    this.glyphTone,
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

  final String? kicker;
  final String? heroTitle;
  final String? squiggle;
  final String? heroSubtitle;
  final IconData? glyph;
  final KitTone? glyphTone;

  /// The hero line: [heroTitle], else the page title (then the card shows no second heading).
  String get _heroLine => (heroTitle?.trim().isNotEmpty ?? false) ? heroTitle! : title;
  bool get _cardHeading => header && (heroTitle?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final canBack = showBack ?? (ModalRoute.of(context)?.canPop ?? false);
    return AppAreaScope(
      area: AppArea.home,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // the phone hero is dark: light status-bar icons over it
        value: SystemUiOverlayStyle.light,
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= kAuthWideBreakpoint
              ? _wide(context, box, canBack)
              : _narrow(context, box, canBack),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, bool wide) => _AuthFormCard(
        title: title,
        subtitle: subtitle,
        heading: _cardHeading,
        // without a hero title the card still carries the page's one line under the hero
        lead: !_cardHeading && header ? subtitle : null,
        glyph: glyph,
        glyphTone: glyphTone,
        child: Builder(builder: (context) => body(context, wide)),
      );

  // ── phone / tablet ──────────────────────────────────────────────────────
  Widget _narrow(BuildContext context, BoxConstraints box, bool canBack) {
    final mq = MediaQuery.of(context);
    final overlap = AppHeroOverlap.defaultOverlap(context);
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: mq.padding.bottom + AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeroOverlap(
            overlap: overlap,
            hero: AppHeroSurface(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpace.md, mq.padding.top + AppSpace.xs, AppSpace.md, AppHeroMetrics.padBottom(overlap)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AuthHeroBar(showBack: canBack, onHero: true, actions: actions?.call(true)),
                    const SizedBox(height: AppSpace.sm),
                    AuthHeroText(kicker: kicker, title: _heroLine, squiggle: squiggle),
                  ],
                ),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth + 2 * AppSpace.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: AuthEntrance(rise: 8, child: _card(context, false)),
                ),
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: AppSpace.lg),
            footer!,
          ],
        ],
      ),
    );
  }

  // ── wide: hero panel + form card ────────────────────────────────────────
  Widget _wide(BuildContext context, BoxConstraints box, bool canBack) {
    final panel = (box.maxWidth * 0.44).clamp(380.0, 600.0);
    return Row(
      children: [
        SizedBox(
          width: panel,
          child: AppHeroSurface(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: AuthHeroPanelBody(kicker: kicker, title: _heroLine, squiggle: squiggle, subtitle: heroSubtitle),
              ),
            ),
          ),
        ),
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
                          AuthEntrance(child: _card(context, true)),
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

/// The hero's words: the gold kicker, then the hero line in the on-hero ink with ONE word squiggled (M7).
class AuthHeroText extends StatelessWidget {
  const AuthHeroText({super.key, this.kicker, required this.title, this.squiggle, this.subtitle, this.large = false});

  final String? kicker;
  final String title;
  final String? squiggle;
  final String? subtitle;

  /// The wide panel's display size.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = (large ? AppType.display(context) : AppType.headline(context)).copyWith(color: c.onHero);
    final word = squiggle?.trim();
    final at = word == null || word.isEmpty ? -1 : title.indexOf(word);
    final line = at < 0
        ? Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: style)
        : Text.rich(
            TextSpan(children: [
              if (at > 0) TextSpan(text: title.substring(0, at)),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: AppSquiggle(child: Text(word!, style: style)),
              ),
              if (at + word.length < title.length) TextSpan(text: title.substring(at + word.length)),
            ]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker != null && kicker!.isNotEmpty) ...[
          Text(kicker!,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.kicker(context).copyWith(color: c.kit.warmOnDark)),
          const SizedBox(height: AppSpace.xxs),
        ],
        Semantics(header: true, label: title, child: ExcludeSemantics(child: line)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(subtitle!, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: AppType.body(context).copyWith(color: c.onHeroMuted, height: 1.5)),
        ],
      ],
    );
  }
}

/// The wide hero panel's content: the brand at the top, the hero words, three things the platform does as glass
/// rows, and the admin's tagline at the foot.
class AuthHeroPanelBody extends StatelessWidget {
  const AuthHeroPanelBody({super.key, this.kicker, required this.title, this.squiggle, this.subtitle});

  final String? kicker;
  final String title;
  final String? squiggle;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomScrollView(slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const AuthLogoTile(size: AppTouch.min, hero: true),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: AuthBrandName(ink: c.onHero, muted: c.onHeroMuted)),
          ]),
          const Spacer(),
          const SizedBox(height: AppSpace.xl),
          AuthHeroText(kicker: kicker, title: title, squiggle: squiggle, subtitle: subtitle, large: true),
          const SizedBox(height: AppSpace.xl),
          for (final (icon, key) in const [
            (Icons.live_tv_rounded, 'sa_feat_live'),
            (Icons.groups_rounded, 'sa_feat_teachers'),
            (Icons.insights_rounded, 'sa_feat_progress'),
          ]) ...[
            _GlassRow(icon: icon, text: key.tr),
            const SizedBox(height: AppSpace.sm),
          ],
          const Spacer(),
        ]),
      ),
    ]);
  }
}

/// One glass row on the hero panel: a glass glyph box and a short line.
class _GlassRow extends StatelessWidget {
  const _GlassRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Row(children: [
        Container(
          width: AppDashSize.glyph,
          height: AppDashSize.glyph,
          decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.glyph)),
          child: Icon(icon, size: AppIconSize.md, color: c.kit.warmOnDark),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(text, style: AppType.row(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// The form card: paper with the kit shadow, the card radius of the width, an optional large glyph, the heading and
/// its one line (centred under a glyph, at the start otherwise), then the form.
class _AuthFormCard extends StatelessWidget {
  const _AuthFormCard({
    required this.title,
    required this.subtitle,
    required this.heading,
    required this.child,
    this.lead,
    this.glyph,
    this.glyphTone,
  });

  final String title;
  final String? subtitle;
  final bool heading;
  final String? lead;
  final IconData? glyph;
  final KitTone? glyphTone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= Breakpoints.mobile;
    final centred = glyph != null;
    final align = centred ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centred ? TextAlign.center : TextAlign.start;
    return Container(
      padding: EdgeInsets.all(wide ? AppSpace.xl : AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.cardFor(w)),
        boxShadow: AppShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            Center(child: AuthGlyph(icon: glyph!, tone: glyphTone)),
            const SizedBox(height: AppSpace.md),
          ],
          if (heading) ...[
            Semantics(
              header: true,
              child: Text(title, textAlign: textAlign, style: AppType.pageTitle(context)),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(subtitle!, textAlign: textAlign, style: AppType.body(context).copyWith(color: c.textMedium, height: 1.5)),
            ],
            const SizedBox(height: AppSpace.lg),
          ] else if (lead != null && lead!.isNotEmpty) ...[
            Column(crossAxisAlignment: align, children: [
              Text(lead!, textAlign: textAlign, style: AppType.body(context).copyWith(color: c.textMedium, height: 1.5)),
            ]),
            const SizedBox(height: AppSpace.lg),
          ],
          child,
        ],
      ),
    );
  }
}

/// The design's large squircle glyph (72): the tone's colour fading toward its tint, the icon in the tone's ink.
class AuthGlyph extends StatelessWidget {
  const AuthGlyph({super.key, required this.icon, this.tone});

  final IconData icon;

  /// Default: the sun accent (the design's key and hourglass).
  final KitTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tone ?? c.kit.accent(AppAccent.sun);
    return ExcludeSemantics(
      child: Container(
        width: AppDashSize.avatar,
        height: AppDashSize.avatar,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.cardWide),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [t.color, Color.lerp(t.color, t.ink, .18)!],
          ),
        ),
        child: Icon(icon, size: AppIconSize.xl, color: t.ink),
      ),
    );
  }
}

// ── Hero bar: [back] logo wordmark ............ [switches] ───────────────────
class AuthHeroBar extends StatelessWidget {
  const AuthHeroBar({super.key, this.showBack = false, this.actions, this.onHero = false});

  final bool showBack;
  final Widget? actions;

  /// On the hero band: the name in the on-hero ink, the back chip glass.
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // a narrow phone with large text keeps back and the switches (targets stay 48 dp); the brand gives way first
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 360 || MediaQuery.textScalerOf(context).scale(1) <= 1;
      return Row(
        children: [
          if (showBack) ...[AuthBackButton(onHero: onHero), const SizedBox(width: AppSpace.xxs)],
          if (roomy) ...[
            const AuthLogoTile(size: AppTouch.min - AppSpace.xs, hero: true),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: onHero ? AuthBrandName(ink: c.onHero, muted: c.onHeroMuted) : const AuthBrandName(onHero: false),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: AppSpace.xs),
          if (actions != null) actions!,
        ],
      );
    });
  }
}

/// A back button (48 dp): glass on the hero, a paper chip on the canvas. The arrow mirrors itself in Arabic.
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, this.onHero = true});

  final bool onHero;

  @override
  Widget build(BuildContext context) => _RoundButton(
        tooltip: AppConfig.lang == 'ar' ? 'رجوع' : 'Back',
        onHero: onHero,
        onTap: () => Navigator.of(context).maybePop(),
        child: Icon(Icons.arrow_back_rounded, size: AppIconSize.md, color: onHero ? context.colors.onHero : context.colors.textDark),
      );
}

/// 48 dp hit area around a 40 dp chip (wider when [child] is): glass on the hero, paper with a hairline on the
/// canvas, radius pill, a press that sinks it a little (none under Reduce motion).
class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.tooltip, required this.onTap, required this.child, this.semanticLabel, this.onHero = false});

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;
  final bool onHero;

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
                color: widget.onHero ? c.heroGlass : c.cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  side: BorderSide(color: widget.onHero ? c.heroGlassBorder : c.divider, width: AppBorder.hairline),
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
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
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

  /// Glass on the hero, paper on the canvas.
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final tip = dark ? (ar ? 'الوضع الفاتح' : 'Light mode') : (ar ? 'الوضع الداكن' : 'Dark mode');
    return _RoundButton(
      tooltip: tip,
      onHero: onHero,
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
          color: onHero ? c.onHero : c.textDark,
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

  /// Glass on the hero, paper on the canvas.
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _RoundButton(
      tooltip: arabic ? 'English' : 'العربية',
      semanticLabel: arabic ? 'Switch to English' : 'التبديل إلى العربية',
      onHero: onHero,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.translate_rounded, size: AppIconSize.sm, color: onHero ? c.onHeroMuted : c.textMedium),
          const SizedBox(width: AppSpace.xxs + 2),
          AnimatedSwitcher(
            duration: AppMotion.of(context).base,
            child: Text(
              arabic ? 'English' : 'عربي',
              key: ValueKey(arabic),
              // the other language's name: its own font is the fallback (Inter has no Arabic letters)
              style: AppType.label(context).copyWith(
                  color: onHero ? c.onHero : c.textDark, fontWeight: FontWeight.w600, height: 1.1, fontFamilyFallback: AppFonts.fallback),
            ),
          ),
        ],
      ),
    );
  }
}
