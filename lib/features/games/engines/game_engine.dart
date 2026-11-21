// lib/features/games/engines/game_engine.dart — the game engine registry (D-1346, PLAN §3.5): a game is data
// (`engine` + `config`), and each engine key maps to ONE widget that plays it with the learn kit and reports
// (score, max score) once. Engines: `quiz`, `match`, `order`, and since Learning Hub v2 (D-1584) `memory`,
// `fill_blank`, `word_puzzle` (config shapes: front docs/learning-hub-v2/CONTRACT.md §3). Every engine is played inside
// the GameShell (shell/game_shell.dart), which it tells each step through `GameShellScope.maybeOf(context)`. A key this
// app does not know (a newer engine) is listed as "needs a newer version", never a crash.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/fill_blank_engine.dart';
import 'package:flutter_education_app/features/games/engines/match_engine.dart';
import 'package:flutter_education_app/features/games/engines/memory_engine.dart';
import 'package:flutter_education_app/features/games/engines/order_engine.dart';
import 'package:flutter_education_app/features/games/engines/quiz_engine.dart';
import 'package:flutter_education_app/features/games/engines/word_puzzle_engine.dart';

/// Called once when a round ends.
typedef GameFinished = void Function(int score, int maxScore);

/// One engine: its name and glyph for the list, how many steps a config has, and the widget that plays it.
class GameEngineSpec {
  const GameEngineSpec({required this.key, required this.nameAr, required this.nameEn, required this.icon, required this.steps, required this.build});

  final String key, nameAr, nameEn;
  final IconData icon;

  /// The number of questions / pairs / items in [config] (0 = nothing to play).
  final int Function(Map<String, dynamic> config) steps;
  final Widget Function(Map<String, dynamic> config, GameFinished onFinished, Random? random) build;

  String get name => t(nameAr, nameEn);
}

List<Object?> _list(Object? v) => v is List ? v : const [];

/// The engines this app plays.
final Map<String, GameEngineSpec> kGameEngines = {
  'quiz': GameEngineSpec(
    key: 'quiz',
    nameAr: 'اختبار سريع',
    nameEn: 'Quiz',
    icon: Icons.quiz_rounded,
    steps: (c) => QuizEngine.questionsOf(c).length,
    build: (c, done, r) => QuizEngine(config: c, onFinished: done, random: r),
  ),
  'match': GameEngineSpec(
    key: 'match',
    nameAr: 'توصيل',
    nameEn: 'Match',
    icon: Icons.join_inner_rounded,
    steps: (c) => _list(c['pairs']).whereType<Map>().length,
    build: (c, done, r) => MatchEngine(config: c, onFinished: done, random: r),
  ),
  'order': GameEngineSpec(
    key: 'order',
    nameAr: 'ترتيب',
    nameEn: 'Order',
    icon: Icons.format_list_numbered_rounded,
    steps: (c) => _list(c['items']).length,
    build: (c, done, r) => OrderEngine(config: c, onFinished: done, random: r),
  ),
  'memory': GameEngineSpec(
    key: 'memory',
    nameAr: 'ذاكرة',
    nameEn: 'Memory',
    icon: Icons.grid_view_rounded,
    steps: (c) => MemoryEngine.pairsOf(c).length,
    build: (c, done, r) => MemoryEngine(config: c, onFinished: done, random: r),
  ),
  'fill_blank': GameEngineSpec(
    key: 'fill_blank',
    nameAr: 'أكمل الفراغ',
    nameEn: 'Fill the blank',
    icon: Icons.edit_note_rounded,
    steps: (c) => FillBlankEngine.itemsOf(c).length,
    build: (c, done, r) => FillBlankEngine(config: c, onFinished: done, random: r),
  ),
  'word_puzzle': GameEngineSpec(
    key: 'word_puzzle',
    nameAr: 'كوّن الكلمة',
    nameEn: 'Word puzzle',
    icon: Icons.abc_rounded,
    steps: (c) => WordPuzzleEngine.wordsOf(c).length,
    build: (c, done, r) => WordPuzzleEngine(config: c, onFinished: done, random: r),
  ),
};

GameEngineSpec? gameEngine(String key) => kGameEngines[key];

/// The engine's glyph (a generic puzzle piece for an engine this app does not know).
IconData gameEngineIcon(String key) => kGameEngines[key]?.icon ?? Icons.extension_rounded;

/// The engine's name ("Quiz") or "Game".
String gameEngineName(String key) => kGameEngines[key]?.name ?? t('لعبة', 'Game');
