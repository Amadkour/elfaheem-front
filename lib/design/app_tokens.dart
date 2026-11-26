// lib/design/app_tokens.dart
//
// THE design tokens every screen builds on (the organization dashboard first). Colours, shadows, type styles and
// radii already live in the server theme (`context.colors`, ThemeConfigProvider) — this file names them in one
// place and adds what had no name yet: the spacing scale, the motion durations / curves and the touch target.
// Never write a raw number for these in a screen: `AppSpace.md`, `AppRadius.card`, `AppMotion.of(context).base`.
//
//   AppSpace    4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 (8 pt grid with the 4 pt half step; D-612)
//   AppRadius   by hierarchy (D-612, KIT_SPEC §3.1): chip 10 · glyph 13 · control 14 (button, input) · nav 16 ·
//               tile 18 · card 20 (24 from 700 px: cardFor) · block 24 · sheet 24 · hero 32 · plate · pill
//   AppMotion   fast 180 ms · base 220 ms · slow 300 ms on easeOutCubic; every duration is zero under Reduce motion
//   AppTouch    48 px minimum target (Material / WCAG), 56 px for a primary action on phones
//   AppShadow   the theme's soft card / raised shadows, by role
//   AppElevation  0 flat · 1 card · 2 raised (hover, sticky bar) · 3 overlay (menu, drawer) · 4 modal (dialog);
//               depth is TONE first (tinted canvas → white card → tinted block); a resting card is white on the
//               tinted page with one soft shadow and no visible border (`AppLift`, `AppShadow.cardEdge`, D-632),
//               what floats casts the clearer shadows, in the theme's shadow tone (D-612)
//   AppIconSize   xs 14 · sm 16 · md 20 · lg 24 · xl 32 · hero 40
//   AppBorder     hairline 1 · strong 1.5 · focus 2
//   AppDashSize   the dashboard kit's fixed sizes: avatar 56 / 72 · disc 64 · ring 76 · course tile 220 · the kit's
//               glyph 42 · ringSm 44 · navItem 44 · top bars 68 / 58 · bottom bar 70 · sidebar 260
//   AppHeroMetrics  the redesign hero's overlap and height budget (KIT_SPEC §3.2)
//   AppType     the type roles (display · headline · page title · section · body · row · label · meta · overline ·
//               figure · figureLarge) mapped onto the theme's styles; display → section are EDITORIAL (Amiri /
//               Playfair Display, AppFonts.editorial, D-611, D-631) unless the person chose "Headings: Same as text"
//   AppWidth    the page-width roles (D-304): form 600 · reading 860 · content 1120 · wide 1440 · full, plus the
//               responsive side gutter (AppSpace.gutter: 16 phone · 24 above); `AppWidthBox` / `BasePage(width:)` apply them
// The whole system (gradient rules, components, examples) is described in lib/design/README.md.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/display/display_settings.dart' show ReadingSpacing;

import 'app_responsive.dart' show Breakpoints;

/// The spacing scale. Between sections: [lg]; inside a card: [md]; between a label and its value: [xs].
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  /// A card's padding from 700 px (KIT_SPEC §3.2).
  static const double ml = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// The widest step: between the big parts of a page on wide screens, above a hero on desktop.
  static const double xxxl = 64;

  /// The page gutter: 16 on phones, 24 from tablet width.
  static double gutter(double width) => width < 600 ? md : lg;

  static const EdgeInsets card = EdgeInsets.all(md);

  /// A card's padding from 700 px.
  static const EdgeInsets cardWide = EdgeInsets.all(ml);
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);

  /// Editorial rhythm (system.md §4): a section heading has more room above it than below.
  static const EdgeInsetsDirectional sectionHead = EdgeInsetsDirectional.only(top: xl, bottom: sm);

  /// A hero block's padding: [lg] on the sides and bottom, [xl] on top.
  static const EdgeInsetsDirectional hero = EdgeInsetsDirectional.fromSTEB(lg, xl, lg, lg);

  /// A content block's padding (AppBlock): [lg] around, [md] on phones' dense rows is the block's own choice.
  static const EdgeInsets block = EdgeInsets.all(lg);
}

/// Corner radii by hierarchy (D-612), never one radius on everything: the smaller the thing, the tighter the corner.
///   chip 10 · glyph 13 (an icon box) · control 14 (buttons, inputs) · nav 16 (a bottom-bar item, a count box) ·
///   tile 18 (tiles, stat tiles) · card 20 (24 from 700 px, [cardFor]) · block 24 (AppBlock, a KPI highlight) ·
///   sheet 24 (bottom sheets, dialogs) · hero 32 (the old floating heroes) · plate (an empty-state plate) · pill
abstract final class AppRadius {
  static const double chip = AppTheme.radiusSmall;
  static const double control = AppTheme.radiusControl;
  static const double card = AppTheme.radiusMedium;
  static const double block = AppTheme.radiusLarge;
  static const double sheet = AppTheme.radiusSheet;
  static const double hero = AppTheme.radiusXL;

  /// An icon box (`AppIconBox`).
  static const double glyph = 13;

  /// A bottom-bar item, a count box, the sidebar's user box.
  static const double nav = 16;

  /// A tile, a stat tile, a rule row.
  static const double tile = 18;

  /// A card from 700 px.
  static const double cardWide = 24;

  /// The card radius at [width]: [card] on phones, [cardWide] from [Breakpoints.mobile].
  static double cardFor(double width) => width < Breakpoints.mobile ? card : cardWide;

  /// The empty-state plate: 34 on three corners, 10 on the bottom end.
  static const BorderRadiusDirectional plate = BorderRadiusDirectional.only(
    topStart: Radius.circular(_plateR),
    topEnd: Radius.circular(_plateR),
    bottomStart: Radius.circular(_plateR),
    bottomEnd: Radius.circular(_plateTail),
  );

  /// A full stadium at any height a badge or pill reaches.
  static const double pill = 999;

  static BorderRadius get cardAll => BorderRadius.circular(card);
  static BorderRadius get chipAll => BorderRadius.circular(chip);
  static BorderRadius get controlAll => BorderRadius.circular(control);
  static BorderRadius get blockAll => BorderRadius.circular(block);
  static BorderRadius get sheetTop => const BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Motion: subtle and short. Read through [AppMotion.of] so Reduce motion (MediaQuery.disableAnimations) turns
/// every transition into an instant change.
class AppMotion {
  const AppMotion._(this._off);
  final bool _off;

  static AppMotion of(BuildContext context) => AppMotion._(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;

  Duration get fast => _off ? Duration.zero : const Duration(milliseconds: 180);
  Duration get base => _off ? Duration.zero : const Duration(milliseconds: 220);
  Duration get slow => _off ? Duration.zero : const Duration(milliseconds: 300);
  bool get off => _off;
}

/// Touch targets.
abstract final class AppTouch {
  static const double min = 48;
  static const double primary = 56;
}

/// Shadows by role (the theme's, so dark mode and the server palette follow). [card] is the faint level-1 lift of a
/// card that must float a little (a hovered row, a pinned bar); a card at rest uses tone + [AppBorder.hairline].
abstract final class AppShadow {
  static List<BoxShadow> card(BuildContext context) => context.colors.cardShadow;
  static List<BoxShadow> raised(BuildContext context) => context.colors.primaryShadow;

  /// A filled button's glow in its first stop (KIT_SPEC §3.4): `0 10 22 -6` at .45 (.30 in dark mode).
  static List<BoxShadow> button(BuildContext context, Color stop) => [
        BoxShadow(
          color: stop.withValues(alpha: context.colors.isDark ? 0.30 : 0.45),
          blurRadius: 22,
          offset: const Offset(0, 10),
          spreadRadius: -6,
        ),
      ];

  /// The selected pill of a segmented strip: `0 4 12` in the ink at .12.
  static List<BoxShadow> pill(BuildContext context) => [
        BoxShadow(
          color: context.colors.kit.ink.withValues(alpha: context.colors.isDark ? 0.30 : 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// The edge of a resting card (D-632): a near-invisible hairline in light mode, a quiet step in dark mode.
  static BorderSide cardEdge(BuildContext context) =>
      BorderSide(color: context.colors.cardEdge, width: AppBorder.hairline);
}

/// Casts the resting card shadow ([AppShadow.card]) under [child], a card drawn with a `Material` of the same
/// [radius] (default [AppRadius.cardAll]; a `Material` takes no shadow list). The white card on the tinted page
/// (D-632).
///
/// [hover] (a tappable card, D-948): under a mouse the card rises to [AppElevation] level 2 while the pointer is on
/// it, easing over [AppMotion.base] (instant under Reduce motion). Touch screens never see it.
class AppLift extends StatefulWidget {
  const AppLift({super.key, required this.child, this.radius, this.hover = false});

  final Widget child;
  final BorderRadius? radius;

  /// Rise on mouse hover.
  final bool hover;

  @override
  State<AppLift> createState() => _AppLiftState();
}

class _AppLiftState extends State<AppLift> {
  bool _over = false;

  void _set(bool v) {
    if (mounted && v != _over) setState(() => _over = v);
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.hover && _over;
    final box = AnimatedContainer(
      duration: AppMotion.of(context).base,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        borderRadius: widget.radius ?? AppRadius.cardAll,
        boxShadow: up ? AppElevation.of(context, 2) : AppShadow.card(context),
      ),
      child: widget.child,
    );
    if (!widget.hover) return box;
    return MouseRegion(onEnter: (_) => _set(true), onExit: (_) => _set(false), child: box);
  }
}

/// Elevation by level, in the theme's warm shadow tone (`card_shadow_color`, charcoal; never a neutral grey). Depth
/// is tone first (D-612): level 1 is a whisper, the clear shadows belong to what floats (2 raised · 3 overlay ·
/// 4 modal). Dark mode, where a shadow barely shows, adds a hairline in the divider colour (`AppElevation.border`).
///   0 flat (inside a card) · 1 card · 2 raised (hover, sticky save bar) · 3 overlay (menu, drawer) · 4 modal (dialog)
abstract final class AppElevation {
  static List<BoxShadow> of(BuildContext context, int level) {
    if (level <= 0) return const [];
    if (level == 1) return context.colors.cardShadow;
    final dark = context.colors.isDark;
    final base = context.colors.shadowTone;
    final (blur, y, a) = switch (level) {
      2 => (18.0, 6.0, dark ? 0.32 : 0.08),
      3 => (28.0, 10.0, dark ? 0.40 : 0.11),
      _ => (44.0, 16.0, dark ? 0.48 : 0.15),
    };
    return [
      BoxShadow(color: base.withValues(alpha: a), blurRadius: blur, offset: Offset(0, y)),
      BoxShadow(color: base.withValues(alpha: a / 3), blurRadius: blur / 6, offset: Offset(0, y / 4)),
    ];
  }

  /// The hairline a raised surface carries in dark mode (null in light mode: the shadow does the work).
  static Border? border(BuildContext context, int level) =>
      level > 0 && context.colors.isDark ? Border.all(color: context.colors.divider, width: AppBorder.hairline) : null;
}

/// Icon sizes: [sm] inside chips and dense rows, [md] in buttons and list rows, [lg] in app bars, [xl] in stat tiles,
/// [hero] in empty states.
abstract final class AppIconSize {
  static const double xs = 14;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double hero = 40;
}

/// The dashboard kit's fixed sizes (D-631): the hero's avatar (phone [avatarSm], desktop [avatar]), a shortcut
/// tile's glyph [disc], a stat card's progress [ring] and the width of a course tile in a home's sideways row
/// ([courseTile]: a second tile always peeks in at the end).
abstract final class AppDashSize {
  static const double avatarSm = 56;
  static const double avatar = 72;
  static const double disc = 64;
  static const double ring = 76;
  static const double courseTile = 220;

  /// The kit's icon box (`AppIconBox`).
  static const double glyph = 42;

  /// The small progress ring of a course row.
  static const double ringSm = 44;

  /// A sidebar row.
  static const double navItem = 44;

  /// The web top bar.
  static const double topBarWide = 68;

  /// The phone top bar.
  static const double topBarPhone = 58;

  /// The phone bottom bar (8 + 50 + 12).
  static const double bottomBar = 70;

  /// The web sidebar ([Breakpoints.sidebarW]).
  static const double sidebar = 260;
}

/// The redesign hero's metrics (KIT_SPEC §3.2).
abstract final class AppHeroMetrics {
  /// How far the body rides up over a student hero below 700 px.
  static const double overlapStudentPhone = 54;

  /// The same for the other roles.
  static const double overlapPhone = 62;

  /// From 700 px.
  static const double overlapWide = 66;

  /// The tallest a student hero may be at 390 px, text scale 1.0.
  static const double maxStudentPhone = 190;

  /// The first card's top edge, same conditions.
  static const double firstCardBy = 260;

  static const double padTopPhone = AppSpace.sm;
  static const double padTopWide = AppSpace.lg;

  /// The hero's bottom padding: the overlap plus [AppSpace.md].
  static double padBottom(double overlap) => overlap + AppSpace.md;
}

/// Border widths.
abstract final class AppBorder {
  static const double hairline = 1;
  static const double strong = 1.5;
  static const double focus = 2;

  /// A drawn line that carries meaning (the match game's connectors, D-1740).
  static const double line = 3;
}

/// Type roles over the theme's styles (fonts follow DisplaySettings, never a family name here). Weights stay at
/// w400 – w600 (D-102).
///
/// Headings are EDITORIAL (D-611, D-631): display · headline · pageTitle · section draw in Amiri (Arabic) or Playfair
/// Display (Latin) ([AppFonts.editorial]) at the system.md sizes 32 · 24 · 22 · 18, which are OPTICAL sizes — what the
/// heading reads like next to the UI sans. Amiri's letters are small on their body (the alef about 0.5 em against
/// Plex's 0.74), so the face is drawn at [editorialScale] × that size (Arabic 1.3, Latin 1.05), negative tracking on Latin only (spaced Arabic loses its joins). With "Headings: Same as text" they fall
/// back to the text font at the sans scale 28 · 22 · 20 · 16.
///   body 14 · row 14 w500 · label 13 · meta 12 · overline 11 · figure 17 w600 · figureLarge 28 w600 (tabular digits)
abstract final class AppType {
  /// How much larger the editorial face is drawn than its optical size, per language.
  static double editorialScale([String? lang]) => AppFonts.editorialScale(lang);

  /// A heading role: the editorial face at [optical] × [editorialScale], or the text font at [sans].
  static TextStyle heading(BuildContext context, {required double optical, required double sans, double? height}) {
    final c = context.colors;
    if (!AppFonts.editorialHeadings) {
      return TextStyle(
          fontFamily: AppFonts.family,
          fontFamilyFallback: AppFonts.fallback,
          fontSize: sans,
          fontWeight: FontWeight.w600,
          height: ReadingSpacing.current.height(height),
          letterSpacing: AppConfig.lang == 'ar' ? null : -0.2,
          color: c.textDark);
    }
    final ar = AppConfig.lang == 'ar';
    final size = (optical * editorialScale()).roundToDouble();
    return TextStyle(
      fontFamily: AppFonts.editorialFamily,
      fontFamilyFallback: AppFonts.editorialFallback,
      fontSize: size,
      fontWeight: FontWeight.w600,
      // a tight line for the display faces; Arabic marks want a little more air
      height: ReadingSpacing.current.height(ar ? 1.3 : 1.15),
      letterSpacing: ar ? null : -size * 0.01,
      color: c.textDark,
    );
  }

  /// A dashboard greeting, the one big line of a page.
  static TextStyle display(BuildContext context) => heading(context, optical: 32, sans: 28, height: 1.25);

  /// A hero title.
  static TextStyle headline(BuildContext context) => heading(context, optical: 24, sans: 22, height: 1.3);

  /// The page header's title.
  static TextStyle pageTitle(BuildContext context) => heading(context, optical: 22, sans: 20);

  /// A section heading, a card's title.
  static TextStyle section(BuildContext context) => heading(context, optical: 18, sans: 16);

  static TextStyle body(BuildContext context) =>
      context.colors.body.copyWith(fontWeight: FontWeight.w400, color: context.colors.textMedium);
  static TextStyle bodyStrong(BuildContext context) =>
      context.colors.body.copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark);
  static TextStyle label(BuildContext context) =>
      context.colors.label.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: context.colors.textMedium);
  static TextStyle overline(BuildContext context) => context.colors.caption
      .copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: context.colors.textMedium);
  static TextStyle figureLarge(BuildContext context) => context.colors.h1.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.15,
      color: context.colors.textDark,
      fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle row(BuildContext context) =>
      context.colors.body.copyWith(fontWeight: FontWeight.w500, color: context.colors.textDark);
  static TextStyle meta(BuildContext context) =>
      context.colors.caption.copyWith(fontWeight: FontWeight.w400, color: context.colors.textMedium);
  static TextStyle figure(BuildContext context) =>
      context.colors.h3.copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark);

  /// The hero's greeting line (KIT_SPEC §3.3): the editorial face, w600; the caller sets the colour
  /// (`kit.warmOnDark` on a hero). 20 from 700 px, 18 below.
  static TextStyle kicker(BuildContext context) {
    final wide = (MediaQuery.maybeSizeOf(context)?.width ?? Breakpoints.mobile) >= Breakpoints.mobile;
    return heading(context, optical: wide ? 20 : 18, sans: wide ? 18 : 16, height: 1.3);
  }

  /// A tile's title: the body style at 15, w600, `textDark`.
  static TextStyle tileTitle(BuildContext context) =>
      context.colors.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textDark);

  /// A stat figure: [figureLarge] (28) from 700 px, [figure] scaled to 21 below; tabular digits.
  static TextStyle statFigure(BuildContext context, {required bool wide}) => wide
      ? figureLarge(context)
      : figure(context).copyWith(fontSize: 21, height: 1.15, fontFeatures: const [FontFeature.tabularFigures()]);
}

/// THE page-width roles (D-304). A page names what its body is and gets the matching max width; no screen writes its
/// own `maxWidth: 900` any more. Narrower windows give every role the whole width less [gutter] on each side.
///
///   form      600   one column of fields: a complaint, a payment, a profile form, a sign-in step
///   reading   860   text and detail pages: a profile, an exam result, a help article (about 75 characters a line)
///   content  1120   mixed pages: card lists, a course page, a hub (BasePage's default)
///   wide     1440   tables, dashboards, analytics, master-detail lists, editors
///   full      inf   canvases that use every pixel (a board, a designer); gutters only
enum AppWidth {
  form(600),
  reading(860),
  content(1120),
  wide(1440),
  full(double.infinity);

  const AppWidth(this.max);

  /// The widest this role's body ever gets.
  final double max;

  /// Below this a page is a phone page: no centred card, the body uses the whole width.
  static const double phoneMax = 600;

  /// The side gutter of a body [available] wide: the page gutter, [AppSpace.gutter] (16 on phones, 24 above).
  static double gutter(double available) => AppSpace.gutter(available);

  /// The width of this role's body inside [available]: the role's max (or [max] when a page still names its own),
  /// never wider than the room left between the two gutters.
  double inside(double available, {double? max}) {
    final cap = max ?? this.max;
    final room = math.max(0.0, available - 2 * gutter(available));
    return math.min(cap, room);
  }
}

const double _plateR = 34;
const double _plateTail = 10;
