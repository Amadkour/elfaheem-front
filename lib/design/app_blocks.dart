// lib/design/app_blocks.dart
//
// Blocks (D-613, `.interface-design/system.md` §5): colour used in BLOCKS — a whole tinted container that groups one
// subject (today's lesson, your streak, the next session, a category) — instead of accents sprinkled on cards.
//
//   AppBlock(tone: AppBlockTone.peach, child: …)              a full-width tinted block, radius 24, padding 24
//   AppBlock(tone: AppBlockTone.sky, hero: true, child: …)    a hero block: 32 on top (the editorial rhythm)
//   AppBlock(tone: AppBlockTone.forKey(course.id), onTap: …)  a category keeps its tone everywhere
//   AppBlock.colorsOf(context).accentInk(c.accent2)           gold / success / warning as TEXT inside a block
//
// Tones come from the live palette: peach = `accent` (accent1), sky = `accent3` (derived when the theme sends none),
// gold = a tint of accent2, emerald = a tint of the primary, paper = the card surface with a hairline. Dark mode
// draws each as a dark surface tinted with its hue. The ink inside keeps WCAG AA on every tone (main ink, muted and
// faint captions); gold, success and warning reach AA on a block only as icons, fills or large text — for text use
// [AppBlockColors.accentInk], which darkens them until they read.
//
// Rules (system.md §2, §5): a screen uses at most two or three tones; peach and sky are surfaces, never text; gold
// only for streaks, achievements and top marks, emerald for done / correct / the primary subject — never decoration.
// That is why [AppBlockTone.forKey] picks among the category tones (peach, sky) only.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_tokens.dart';

/// A block's tint.
enum AppBlockTone {
  /// Learning / progress blocks (`accent`).
  peach,

  /// Schedule / information blocks (`accent3`).
  sky,

  /// The warm green-grey of dashboards and book covers (D-630: sage takes sky's place there).
  sage,

  /// Streaks, achievements, top marks only.
  gold,

  /// Done, correct, the primary subject only.
  emerald,

  /// The card surface with a warm hairline: a block without colour.
  paper;

  /// The tones a category may wear (gold and emerald carry meaning and are never handed out by a hash). D-630: the
  /// warm pair, peach and sage (sky stays for the schedule blocks a screen picks on purpose).
  static const categoryTones = [peach, sage];

  /// The tones of a book cover (a course with no picture, CourseCoverArt): sage, peach and amber, so a shelf of
  /// covers reads warm and varied. A cover is a picture, not a mark, so amber may appear here.
  static const coverTones = [sage, peach, gold];

  /// The same tone for the same [key] on every screen, run and platform (FNV-1a over the UTF-16 code units, not
  /// `String.hashCode`, which differs between the VM and the web).
  static AppBlockTone forKey(String key, {List<AppBlockTone> among = categoryTones}) {
    assert(among.isNotEmpty);
    var h = 0x811c9dc5;
    for (final u in key.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return among[h % among.length];
  }
}

/// The colours of one block in the open mode: its surface and the inks that read on it.
@immutable
class AppBlockColors {
  const AppBlockColors({
    required this.surface,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.border,
    required ThemeConfigProvider palette,
  }) : _palette = palette;

  /// The block's fill.
  final Color surface;

  /// Titles, figures and icons (text_dark / dark_text_primary).
  final Color ink;

  /// Secondary lines, at AA on [surface].
  final Color muted;

  /// Captions, at AA on [surface].
  final Color faint;

  /// The block's edge: a warm hairline on paper and in dark mode, none on a light tint.
  final Color? border;

  final ThemeConfigProvider _palette;

  /// [accent] (gold, success, warning, danger, the primary) darkened — lifted in dark mode — until it reads as text
  /// on this block at AA.
  Color accentInk(Color accent) => _palette.blockAccentInk(accent, surface);

  /// The colours of [tone] under [context]'s theme and mode.
  static AppBlockColors of(BuildContext context, AppBlockTone tone) {
    final c = context.colors;
    final surface = switch (tone) {
      AppBlockTone.peach => c.blockPeach,
      AppBlockTone.sky => c.blockSky,
      AppBlockTone.sage => c.blockSage,
      AppBlockTone.gold => c.blockGold,
      AppBlockTone.emerald => c.blockEmerald,
      AppBlockTone.paper => c.cardBg,
    };
    final Color? border = tone == AppBlockTone.paper
        ? c.divider
        : c.isDark
            ? Color.lerp(surface, c.textDark, 0.08)
            : null;
    return AppBlockColors(
      surface: surface,
      ink: c.blockInk,
      muted: c.blockMuted(surface),
      faint: c.blockFaint(surface),
      border: border,
      palette: c,
    );
  }
}

/// A full-width tinted container that groups one subject. It fills the width it is given (inside a Row, give it an
/// Expanded). Text and icons inside default to the block's ink; read [AppBlock.colorsOf] for muted / faint / accent
/// ink.
class AppBlock extends StatelessWidget {
  const AppBlock({
    super.key,
    this.tone = AppBlockTone.peach,
    required this.child,
    this.padding,
    this.hero = false,
    this.onTap,
    this.semanticLabel,
  });

  final AppBlockTone tone;
  final Widget child;

  /// Defaults to [AppSpace.block] (24 around), or [AppSpace.hero] (32 on top) for a [hero] block.
  final EdgeInsetsGeometry? padding;

  /// The screen's one hero block: the editorial rhythm's taller top.
  final bool hero;

  /// Makes the whole block a button (ink ripple, focus highlight, the 48 px target it already exceeds).
  final VoidCallback? onTap;

  /// What a screen reader says for a tappable block (else it reads the content).
  final String? semanticLabel;

  /// The colours of the nearest enclosing block (or of a peach block when there is none).
  static AppBlockColors colorsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppBlockScope>()?.colors ??
      AppBlockColors.of(context, AppBlockTone.peach);

  @override
  Widget build(BuildContext context) {
    final colors = AppBlockColors.of(context, tone);
    final radius = BorderRadius.circular(AppRadius.block);
    Widget body = Padding(
      padding: padding ?? (hero ? AppSpace.hero : AppSpace.block),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.ink),
        child: IconTheme.merge(data: IconThemeData(color: colors.ink), child: child),
      ),
    );
    if (onTap != null) {
      body = InkWell(onTap: onTap, borderRadius: radius, child: body);
    }
    body = SizedBox(
      width: double.infinity,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: colors.border == null ? BorderSide.none : BorderSide(color: colors.border!, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
    if (onTap != null) {
      body = Semantics(button: true, label: semanticLabel, child: body);
    }
    return _AppBlockScope(colors: colors, child: body);
  }
}

class _AppBlockScope extends InheritedWidget {
  const _AppBlockScope({required this.colors, required super.child});
  final AppBlockColors colors;

  @override
  bool updateShouldNotify(_AppBlockScope old) =>
      old.colors.surface != colors.surface || old.colors.ink != colors.ink || old.colors.faint != colors.faint;
}
