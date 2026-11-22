// lib/features/games/shell/game_round.dart — one round of one engine inside the GameShell (D-1580): owns the shell's
// controller (its total = the engine's `steps`), so the player page and the admin editor's live preview draw a round
// the same way. Key it by the round number (or the config) to start over.
//
// Games v3: [category] makes a quran / tajweed round `sacred` (no shake, no wrong sound); [onTrace] gets the round's
// trace (CONTRACT §3) just before [onFinished]; with [showMute] false (the editor's preview) the round is silent.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';

class GameRound extends StatefulWidget {
  const GameRound({
    super.key,
    required this.spec,
    required this.config,
    required this.onFinished,
    this.theme,
    this.random,
    this.showMute = true,
    this.category = '',
    this.onTrace,
  });

  final GameEngineSpec spec;
  final Map<String, dynamic> config;
  final GameFinished onFinished;
  final String? theme;
  final Random? random;
  final bool showMute;
  final String category;
  final ValueChanged<List<Map<String, Object>>>? onTrace;

  @override
  State<GameRound> createState() => _GameRoundState();
}

class _GameRoundState extends State<GameRound> {
  late final GameShellController _shell =
      GameShellController(total: widget.spec.steps(widget.config), category: widget.category, silent: !widget.showMute);

  void _finished(int score, int max) {
    widget.onTrace?.call(List.of(_shell.trace));
    widget.onFinished(score, max);
  }

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      controller: _shell,
      theme: widget.theme,
      showMute: widget.showMute,
      // the engine keeps its own state; the shell's reports rebuild only the header, never this
      child: widget.spec.build(widget.config, _finished, widget.random),
    );
  }
}
