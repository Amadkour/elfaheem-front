// lib/features/games/shell/game_round.dart — one round of one engine inside the GameShell (D-1580): owns the shell's
// controller (its total = the engine's `steps`), so the player page and the admin editor's live preview draw a round
// the same way. Key it by the round number (or the config) to start over.
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
  });

  final GameEngineSpec spec;
  final Map<String, dynamic> config;
  final GameFinished onFinished;
  final String? theme;
  final Random? random;
  final bool showMute;

  @override
  State<GameRound> createState() => _GameRoundState();
}

class _GameRoundState extends State<GameRound> {
  late final GameShellController _shell = GameShellController(total: widget.spec.steps(widget.config));

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
      child: widget.spec.build(widget.config, widget.onFinished, widget.random),
    );
  }
}
