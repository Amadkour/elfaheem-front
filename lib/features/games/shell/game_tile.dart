// lib/features/games/shell/game_tile.dart — one answer tile of the games (Games v3 §1, D-1740): the look of the learn
// kit's LearnOptionTile (the learn kit itself is unchanged), with the games' states and moves:
//
//   idle      the card colour, a hairline edge
//   selected  the primary wash and edge (picked, not checked)
//   correct   the success tint, a check that pops in, a pulse (1 → 1.06 → 1) each time [pulse] changes
//   wrong     the danger tint, a cross, a shake each time [shake] changes (never on a tile that holds an ayah:
//             [shakeEnabled] false keeps the red edge and the cross only)
//   locked    a finished tile that is no longer in play (quiz options not picked): muted ink
//   hint      the right answer the person did not pick: the card colour with the success edge and an outline check
//
// [hover]: a dragged piece is over it (the primary edge, strong). States are colour + icon + one move, never colour
// alone; colours tween over `tap`. 48 px high at least; the Semantics label carries the state's word.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

enum GameTileState { idle, selected, correct, wrong, locked, hint }

/// The learn kit's mark as a tile state (the engines kept their marks).
GameTileState gameTileStateOf(LearnMark m) => switch (m) {
      LearnMark.idle => GameTileState.idle,
      LearnMark.selected => GameTileState.selected,
      LearnMark.correct => GameTileState.correct,
      LearnMark.wrong => GameTileState.wrong,
      LearnMark.missed => GameTileState.hint,
    };

/// The colours of a state: (fill, edge, ink, glyph).
({Color fill, Color edge, Color ink, IconData? glyph}) gameTileStyle(BuildContext context, GameTileState s, {bool hover = false}) {
  final c = context.colors;
  final r = switch (s) {
    GameTileState.correct => () {
        final tint = appTintOn(context, c.success);
        return (fill: tint, edge: c.success, ink: appInkOn(context, c.success, tint), glyph: Icons.check_circle_rounded as IconData?);
      }(),
    GameTileState.wrong => () {
        final tint = appTintOn(context, c.danger);
        return (fill: tint, edge: c.danger, ink: appInkOn(context, c.danger, tint), glyph: Icons.cancel_rounded as IconData?);
      }(),
    GameTileState.hint => (fill: c.cardBg, edge: c.success, ink: c.textDark, glyph: Icons.check_circle_outline_rounded as IconData?),
    GameTileState.selected => (fill: c.primaryWash, edge: c.primary, ink: c.textDark, glyph: null),
    GameTileState.locked => (fill: c.cardBg, edge: c.divider, ink: c.textMedium, glyph: null),
    GameTileState.idle => (fill: c.cardBg, edge: c.divider, ink: c.textDark, glyph: null),
  };
  return hover ? (fill: r.fill, edge: c.primary, ink: r.ink, glyph: r.glyph) : r;
}

String gameTileWord(GameTileState s) {
  final ar = AppConfig.lang == 'ar';
  return switch (s) {
    GameTileState.correct => ar ? 'صحيح' : 'correct',
    GameTileState.wrong => ar ? 'خطأ' : 'wrong',
    GameTileState.hint => ar ? 'الإجابة الصحيحة' : 'the right answer',
    GameTileState.selected => ar ? 'مختار' : 'selected',
    GameTileState.idle || GameTileState.locked => '',
  };
}

class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.label,
    this.state = GameTileState.idle,
    this.onTap,
    this.index,
    this.hover = false,
    this.pulse,
    this.shake,
    this.shakeEnabled = true,
    this.semanticsHint,
    this.trailing,
    this.actions,
  });

  final String label;
  final GameTileState state;

  /// Null: not tappable.
  final VoidCallback? onTap;

  /// Draws the option's letter (أ / A …) in a well at the start.
  final int? index;

  final bool hover;

  /// A change pulses / shakes the tile once.
  final Object? pulse, shake;
  final bool shakeEnabled;

  /// Read after the label (e.g. how to drag it).
  final String? semanticsHint;

  /// Drawn at the end (a drag handle).
  final Widget? trailing;

  /// The screen reader's extra actions (Move up / Move down: the drag's other path).
  final Map<CustomSemanticsAction, VoidCallback>? actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = GameMotion.of(context);
    final s = gameTileStyle(context, state, hover: hover);
    final word = gameTileWord(state);
    final letter = index == null ? null : learnOptionLetter(index!);
    final strong = state != GameTileState.idle && state != GameTileState.locked || hover;
    final glyph = s.glyph;
    Widget tile = AnimatedContainer(
      duration: m.tap,
      curve: GameMotion.move,
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: s.edge, width: strong ? AppBorder.strong : AppBorder.hairline),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.controlAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Row(children: [
              if (letter != null) ...[
                AnimatedContainer(
                  duration: m.tap,
                  width: AppIconSize.xl,
                  height: AppIconSize.xl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: state == GameTileState.idle || state == GameTileState.locked ? c.inputBg : s.edge,
                    borderRadius: AppRadius.chipAll,
                  ),
                  child: Text(letter,
                      style: AppType.label(context).copyWith(
                          color: state == GameTileState.idle || state == GameTileState.locked
                              ? c.textMedium
                              : appInkOnFill(context, s.edge))),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(child: AutoDirText(label, style: AppType.row(context).copyWith(color: s.ink))),
              if (glyph != null) ...[
                const SizedBox(width: AppSpace.xs),
                GamePopIn(key: ValueKey(glyph), child: Icon(glyph, size: AppIconSize.md, color: s.edge)),
              ],
              ?trailing,
            ]),
          ),
        ),
      ),
    );
    tile = GameShake(trigger: shake, enabled: shakeEnabled, child: GamePulse(trigger: pulse, child: tile));
    return Semantics(
      button: onTap != null,
      selected: state == GameTileState.selected,
      label: [?letter, label, if (word.isNotEmpty) word].join(', '),
      hint: semanticsHint,
      customSemanticsActions: actions,
      excludeSemantics: true,
      child: AppPressScale(enabled: onTap != null, child: tile),
    );
  }
}
