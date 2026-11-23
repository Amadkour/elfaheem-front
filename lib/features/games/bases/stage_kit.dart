// lib/features/games/bases/stage_kit.dart — the shared parts of the Games v4 stage bases (T37): QuestionStage,
// DragBoard and the templates on them draw with these, so a tap feels the same in every game.
//
//   quranTextStyle      the Quran text role (decision 6, gate G2): Amiri Quran (AppFonts.quranFamily), one weight,
//                       on a tall line so tashkeel and the waqf marks never clip. Every Quran / Hadith word in a
//                       game or an admin picker is drawn with it; nothing else names that family.
//   StageSurface        the palette of a round: the age theme's paper / ink / accent and the right / wrong colours
//                       (calm: never red; a wrong answer is a soft amber)
//   StageTile           a big tactile answer tile: a solid edge that presses in, states idle / selected / correct /
//                       wrong / dim / hint, light haptics
//   StageReact          a bump (right) or a shake (wrong) on a counter change; nothing moves under Reduce motion
//   StageProgress       the slim progress bar + "3 / 8" of a round
//   StageListenButton   plays an item's recitation; StageReciterSwitch the quick reciter switch (CONTRACT §9)
//   stageSegments       an item's media.audio as recitation segments
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/display/lazy_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_art.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart' show MechanicKind;
import 'package:flutter_education_app/features/games/shell/game_shell.dart' show GameSessionShell;
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';

final RegExp _arabic = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

/// True when [s] holds an Arabic letter: such text is laid out right to left whatever the app language is.
bool isArabicText(String s) => _arabic.hasMatch(s);

TextDirection textDirectionOf(String s, [TextDirection? ambient]) =>
    isArabicText(s) ? TextDirection.rtl : (ambient ?? TextDirection.ltr);

/// The Quran text role (see the library header). [size] is the optical size: the face is drawn larger (Amiri's
/// letters are small on their body) and on a tall line, so shadda + kasra and the waqf marks have room. Amiri Quran
/// has one weight: there is no bold Quran text, emphasis is colour or size.
TextStyle quranTextStyle(double size, {Color? color}) => TextStyle(
      fontFamily: AppFonts.quranFamily,
      fontFamilyFallback: AppFonts.quranFallback,
      fontSize: size * kQuranScale,
      fontWeight: FontWeight.w400,
      height: 2.1,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );

/// How much larger than its optical size the Quran face is drawn.
const double kQuranScale = 1.3;

/// A text of an item option / label: a plain string or `{ar, en}`.
String stageText(Object? v) {
  if (v is String) return v;
  if (v is Map) return GameText.from(v).of(AppConfig.lang);
  return '${v ?? ''}';
}

/// A recitation playlist from an item's `media.audio`; empty when it has none.
List<RecitationSegment> stageSegments(GameItem item) => [
      for (final e in item.media.audio ?? const <GameAudioEntry>[])
        RecitationSegment(url: e.url, startMs: e.startMs, endMs: e.endMs, reciter: e.reciter, ref: e.ref),
    ];

/// The colours of one round, from the age theme.
class StageSurface {
  StageSurface(this.theme, this.context);
  final AgeTheme theme;
  final BuildContext context;

  GamePalette get p => theme.palette;
  bool get calm => theme.calm;
  ThemeConfigProvider get _c => context.colors;

  Color get paper => p.paper;
  Color get ink => p.ink;

  /// Text drawn straight on the sky (the round counter): see [AgeTheme.onSky].
  Color get onSky => theme.onSky;
  Color get accent => p.accent;
  Color get gold => p.gold;
  Color get right => _c.success;

  /// A wrong answer: red, except in a calm round (sacred text) where it is a soft amber.
  Color get wrong => calm ? p.accent2 : _c.danger;
  Color get edge => Color.lerp(p.ink, p.paper, 0.78)!;

  /// The solid under-edge of a tile (kids thick, calm and adult thin).
  double get edgeWidth => 1.5 + 3.5 * theme.outline;

  double get radius => theme.age == GameAge.kids && !calm ? 22 : AppRadius.block;

  Color tint(Color c, [double a = 0.16]) => Color.alphaBlend(c.withValues(alpha: a), paper);

  List<BoxShadow> lift({double blur = 18, double dy = 8}) => [
        BoxShadow(color: p.ink.withValues(alpha: 0.22), blurRadius: blur, offset: Offset(0, dy)),
      ];
}

/// The colour set of a [StageTile] state.
enum StageTileState { idle, selected, correct, wrong, dim, hint }

/// Counts a bump (right answer) and a shake (wrong answer) on its child.
class StageReact extends StatefulWidget {
  const StageReact({super.key, required this.child, this.bump = 0, this.shake = 0});
  final Widget child;
  final int bump, shake;

  @override
  State<StageReact> createState() => _StageReactState();
}

class _StageReactState extends State<StageReact> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _isShake = false;

  @override
  void didUpdateWidget(StageReact old) {
    super.didUpdateWidget(old);
    final bump = widget.bump != old.bump, shake = widget.shake != old.shake;
    if ((bump || shake) && !appMotionOff(context)) {
      _isShake = shake && !bump;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _c.value;
        if (v == 0 || v == 1) return child!;
        if (_isShake) {
          return Transform.translate(offset: Offset(math.sin(v * math.pi * 6) * 9 * (1 - v), 0), child: child);
        }
        final s = 1 + 0.09 * math.sin(Curves.easeOut.transform(v) * math.pi);
        return Transform.scale(scale: s, child: child);
      },
    );
  }
}

/// A big tactile tile. [child] is drawn on the paper; the solid edge under it gives the "button you press" feel,
/// which sinks while the finger is down (kids thick, adult thin).
class StageTile extends StatefulWidget {
  const StageTile({
    super.key,
    required this.child,
    required this.surface,
    this.state = StageTileState.idle,
    this.onTap,
    this.badge,
    this.minHeight = AppTouch.primary + 8,
    this.semanticsLabel,
    this.expand = true,
  });

  final Widget child;
  final StageSurface surface;
  final StageTileState state;
  final VoidCallback? onTap;

  /// The small letter / number chip at the start ("A", "١").
  final String? badge;
  final double minHeight;
  final String? semanticsLabel;

  /// The label fills the tile (a list of answers); false = the tile is as wide as its label (a word in a wrap).
  final bool expand;

  @override
  State<StageTile> createState() => _StageTileState();
}

class _StageTileState extends State<StageTile> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.surface;
    final st = widget.state;
    final off = appMotionOff(context);
    final (Color fill, Color edge, Color border) = switch (st) {
      StageTileState.correct => (sf.tint(sf.right, 0.22), sf.right, sf.right),
      StageTileState.wrong => (sf.tint(sf.wrong, sf.calm ? 0.3 : 0.2), sf.wrong, sf.wrong),
      StageTileState.selected => (sf.tint(sf.accent, 0.16), sf.accent, sf.accent),
      StageTileState.hint => (sf.tint(sf.gold, 0.28), sf.gold, sf.gold),
      StageTileState.dim => (sf.tint(sf.ink, 0.04), sf.edge, Colors.transparent),
      StageTileState.idle => (sf.paper, sf.edge, Colors.transparent),
    };
    final e = sf.edgeWidth;
    final pressed = _down && widget.onTap != null;
    final r = BorderRadius.circular(sf.radius);
    final dur = off ? Duration.zero : Duration(milliseconds: pressed ? 70 : 160);
    final tile = AnimatedContainer(
      duration: dur,
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minHeight: widget.minHeight),
      transform: Matrix4.translationValues(0, pressed ? e : 0, 0),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: r,
        border: Border.all(color: border, width: border == Colors.transparent ? 0 : 2),
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, pressed ? 0 : e))],
      ),
      child: Opacity(
        opacity: st == StageTileState.dim ? 0.5 : 1,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.badge != null) ...[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: sf.tint(sf.ink, 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(widget.badge!, style: appText(13, w: FontWeight.w700, c: sf.ink)),
            ),
            AppSpace.gapSm,
          ],
          if (widget.expand) Expanded(child: widget.child) else Flexible(child: widget.child),
          if (st == StageTileState.correct) ...[
            AppSpace.gapXs,
            Icon(Icons.check_circle_rounded, color: sf.right, size: 22),
          ],
        ]),
      ),
    );
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticsLabel,
      selected: st == StageTileState.selected,
      child: Listener(
        onPointerDown: widget.onTap == null ? null : (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          child: Padding(padding: EdgeInsets.only(bottom: e), child: tile),
        ),
      ),
    );
  }
}

/// The slim progress bar of a round with "3 / 8".
class StageProgress extends StatelessWidget {
  const StageProgress({super.key, required this.surface, required this.done, required this.total, this.current});
  final StageSurface surface;
  final int done, total;

  /// The question shown, 1-based (default: the next one after [done]).
  final int? current;

  @override
  Widget build(BuildContext context) {
    final f = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final ms = appMotionOff(context) ? 0 : 420;
    return Semantics(
      label: t('$done من $total', '$done of $total'),
      excludeSemantics: true,
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              height: 12,
              color: surface.tint(surface.ink, 0.1),
              alignment: AlignmentDirectional.centerStart,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: f),
                duration: Duration(milliseconds: ms),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      gradient: LinearGradient(colors: [surface.accent, surface.gold]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AppSpace.gapSm,
        Text('${math.min(current ?? done + 1, total)} / $total',
            textDirection: TextDirection.ltr, style: appText(13, w: FontWeight.w700, c: surface.onSky)),
      ]),
    );
  }
}

/// Replays an item's recitation. Pulses softly while a recitation plays.
class StageListenButton extends StatelessWidget {
  const StageListenButton({super.key, required this.surface, required this.onPressed});
  final StageSurface surface;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GameAudio.instance.recitationActive,
      builder: (context, playing, _) => Semantics(
        button: true,
        label: t('استمع', 'Listen'),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: AnimatedContainer(
            duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 220),
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: playing ? surface.accent : surface.tint(surface.accent, 0.18),
              boxShadow: playing ? [BoxShadow(color: surface.accent.withValues(alpha: 0.4), blurRadius: 16)] : null,
            ),
            child: Icon(playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: playing ? surface.paper : surface.accent),
          ),
        ),
      ),
    );
  }
}

typedef ReciterLoader = Future<GameReciterList> Function();

/// The reciter quick switch (CONTRACT §9): a chip with the current voice; it opens the list, and a pick replays the
/// current ayah with the new voice (GameAudio.switchReciter saves the choice; the score and the trace do not change).
class StageReciterSwitch extends StatefulWidget {
  const StageReciterSwitch({super.key, required this.surface, this.currentKey, this.loader, this.onChanged});
  final StageSurface surface;
  final String? currentKey;

  /// Tests replace the loader.
  final ReciterLoader? loader;
  final ValueChanged<String>? onChanged;

  @override
  State<StageReciterSwitch> createState() => _StageReciterSwitchState();
}

class _StageReciterSwitchState extends State<StageReciterSwitch> {
  String? _key;
  String? _name;

  @override
  void initState() {
    super.initState();
    _key = widget.currentKey ?? GameAudio.instance.reciterKey;
  }

  Future<void> _open() async {
    GameReciterList? list;
    try {
      list = await (widget.loader ?? GameAudio.instance.loadReciters)();
    } catch (_) {}
    if (!mounted) return;
    if (list == null || list.items.isEmpty) {
      showAppNotice(t('تعذّر تحميل القرّاء', 'Could not load the reciters'), error: true);
      return;
    }
    final items = list.items;
    final cur = _key ?? list.effective;
    final picked = await showAppSheet<String>(
      context,
      (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('اختر القارئ', 'Choose the reciter'), style: appText(18, w: FontWeight.w700, c: ctx.colors.textDark)),
          AppSpace.gapSm,
          for (final r in items)
            ListTile(
              key: ValueKey('reciter-${r.key}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.key == cur ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: ctx.colors.primary),
              title: Text(AppConfig.lang == 'ar' ? r.nameAr : r.nameEn),
              trailing: r.sample == null
                  ? null
                  : IconButton(
                      tooltip: t('استمع', 'Listen'),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      onPressed: () => GameAudio.instance.playSample(r),
                    ),
              onTap: () => Navigator.pop(ctx, r.key),
            ),
        ]),
      ),
    );
    if (picked == null || picked == cur) return;
    final ok = await GameAudio.instance.switchReciter(picked);
    if (!mounted) return;
    if (!ok) {
      showAppNotice(t('تعذّر تغيير القارئ', 'Could not switch the reciter'), error: true);
      return;
    }
    final r = items.firstWhere((x) => x.key == picked, orElse: () => items.first);
    setState(() {
      _key = picked;
      _name = AppConfig.lang == 'ar' ? r.nameAr : r.nameEn;
    });
    widget.onChanged?.call(picked);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.surface;
    return Semantics(
      button: true,
      label: t('تغيير القارئ', 'Change the reciter'),
      child: GestureDetector(
        onTap: _open,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          decoration: BoxDecoration(
            color: sf.tint(sf.paper, 1),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: sf.edge),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.record_voice_over_rounded, size: 20, color: sf.accent),
            AppSpace.gapXs,
            Flexible(
              child: Text(
                _name ?? t('القارئ', 'Reciter'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appText(13, w: FontWeight.w600, c: sf.ink),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 20, color: sf.ink),
          ]),
        ),
      ),
    );
  }
}

/// The ambient age theme of a round: the page's scope, turned calm when the round is sacred.
AgeTheme stageThemeOf(BuildContext context, {required bool calm}) {
  final base = AgeThemeScope.of(context);
  if (calm && !base.calm) {
    return AgeTheme.build(base.age, calm: true, night: false, primary: context.colors.primary);
  }
  return base;
}

/// The sound of a tap on a stage (a light tick through the one seam).
void stageTick({bool sacred = false, bool silent = false}) =>
    GameFeedback.instance.play(GameSound.tap, sacred: sacred, silent: silent);

/// The frame every stage template draws in: the age theme (calm for sacred text) as the page's scope, the painted
/// backdrop of the age, and the session shell (lives, timer, hint, pause, effects) over the game.
class StageFrame extends StatelessWidget {
  const StageFrame({
    super.key,
    required this.session,
    required this.kinds,
    required this.child,
    this.onHint,
    this.silent = false,
  });

  final GameSession session;
  final Set<MechanicKind> kinds;
  final Widget child;
  final VoidCallback? onHint;
  final bool silent;

  @override
  Widget build(BuildContext context) {
    final theme = stageThemeOf(context, calm: session.calm || session.sacred);
    final frame = AgeThemeScope(
      theme: theme,
      child: GameBackdrop(
        theme: theme,
        child: SafeArea(
          // the shell's timer, lamp and pause sit on the painted sky
          child: GameSessionShell(session: session, kinds: kinds, onHint: onHint, silent: silent, onScene: theme.onSky, child: child),
        ),
      ),
    );
    // sacred text is drawn in the Quran face, which the web loads on demand
    return session.sacred ? LazyFontGate(families: const [AppFonts.quranFamily], child: frame) : frame;
  }
}

/// AnimatedSwitcher's layout that keeps a short question at the top instead of centring it.
Widget stageSwitcherLayout(Widget? current, List<Widget> previous) => Stack(
      alignment: Alignment.topCenter,
      fit: StackFit.expand,
      children: [...previous, ?current],
    );
