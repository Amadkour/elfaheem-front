// lib/features/games/engines/word_puzzle_engine.dart — the `word_puzzle` engine (Learning Hub v2 §3, D-1585): one
// word at a time, its clue (`hint`) on top and its letters shuffled under it; tap the letters in order to rebuild it
// (tap a placed one to take it back). The word is checked once every letter is placed, after the Arabic
// normalization of game_text.dart. The Hint button places the next right letter; a word rebuilt with a hint (or after a wrong try) is
// solved but scores nothing (like a pair matched after a slip). Score = words rebuilt right with no hint, max = words.
// config = {prompt_ar, prompt_en, words: [{word, hint}]} (1..15)
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_text.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

typedef PuzzleWord = ({String word, String hint});

class WordPuzzleEngine extends StatefulWidget {
  const WordPuzzleEngine({super.key, required this.config, required this.onFinished, this.random});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  static List<PuzzleWord> wordsOf(Map<String, dynamic> config) => [
        if (config['words'] is List)
          for (final w in config['words'] as List)
            if (w is Map && lettersOf('${w['word'] ?? ''}').length >= 2)
              (word: '${w['word']}'.trim(), hint: '${w['hint'] ?? ''}'.trim()),
      ];

  /// The tiles of [word]: its letters (a letter keeps its own tashkeel), spaces dropped.
  static List<String> lettersOf(String word) => [
        for (final g in word.trim().characters)
          if (g.trim().isNotEmpty) g,
      ];

  /// Whether the placed letters spell [word].
  static bool isRight(List<String> placed, String word) => gameSameAnswer(placed.join(), lettersOf(word).join());

  @override
  State<WordPuzzleEngine> createState() => _WordPuzzleEngineState();
}

class _WordPuzzleEngineState extends State<WordPuzzleEngine> {
  late final List<PuzzleWord> _words;
  int _i = 0, _score = 0;

  late List<String> _letters;

  /// Indexes into _letters: the pool in its shuffled order, and the letters placed so far.
  late List<int> _pool;
  final List<int> _placed = [];
  bool _hinted = false;

  /// A wrong try on this word (it may be tried again, but no longer scores).
  bool _slipped = false;

  /// null = not checked yet.
  bool? _right;

  @override
  void initState() {
    super.initState();
    _words = WordPuzzleEngine.wordsOf(widget.config);
    _setUp();
  }

  void _setUp() {
    _letters = _words.isEmpty ? const [] : WordPuzzleEngine.lettersOf(_words[_i].word);
    _pool = learnShuffle([for (var k = 0; k < _letters.length; k++) k], random: widget.random);
    _placed.clear();
    _hinted = _slipped = false;
    _right = null;
  }

  void _place(int k) {
    if (_right != null || _placed.contains(k)) return;
    setState(() => _placed.add(k));
    _maybeCheck();
  }

  void _unplace(int pos) {
    if (_right != null) return;
    setState(() => _placed.removeAt(pos));
  }

  /// Takes back every letter after the right beginning, then places the next right one.
  void _hint() {
    if (_right != null) return;
    final word = _letters;
    var ok = 0;
    while (ok < _placed.length && gameSameAnswer(word[_placed[ok]], word[ok])) {
      ok++;
    }
    setState(() {
      _hinted = true;
      _placed.removeRange(ok, _placed.length);
      if (ok < word.length) {
        // the first unused tile that shows the needed letter
        final need = word[ok];
        final k = [for (var j = 0; j < word.length; j++) j].firstWhere(
            (j) => !_placed.contains(j) && gameSameAnswer(word[j], need),
            orElse: () => -1);
        if (k >= 0) _placed.add(k);
      }
    });
    _maybeCheck();
  }

  void _maybeCheck() {
    if (_placed.length < _letters.length) return;
    final right = WordPuzzleEngine.isRight([for (final k in _placed) _letters[k]], _words[_i].word);
    setState(() {
      _right = right;
      if (right && !_hinted && !_slipped) _score++;
      if (!right) _slipped = true;
    });
    GameShellScope.maybeOf(context)?.report(done: _i + 1, score: _score, correct: right && !_hinted && !_slipped);
  }

  void _retry() => setState(() {
        _placed.clear();
        _right = null;
      });

  void _next() {
    if (_i + 1 >= _words.length) {
      widget.onFinished(_score, _words.length);
      return;
    }
    setState(() {
      _i++;
      _setUp();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_words.isEmpty) {
      return AppEmpty(icon: Icons.abc_rounded, title: t('لا توجد كلمات في هذه اللعبة', 'This game has no words'));
    }
    final w = _words[_i];
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final inShell = GameShellScope.maybeOf(context) != null;
    final last = _i + 1 >= _words.length;
    final right = _right;
    final pool = [for (final k in _pool) if (!_placed.contains(k)) k];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(current: _i + 1, total: _words.length, score: _score),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(
        key: ValueKey('word.q.$_i'),
        caption: prompt.isEmpty ? t('رتّب الحروف لتكوّن الكلمة', 'Put the letters together into the word') : prompt,
        text: w.hint.isEmpty ? t('كلمة من ${_letters.length} حروف', 'A word of ${_letters.length} letters') : w.hint,
      ),
      const SizedBox(height: AppSpace.sm),
      // the word so far: one slot per letter
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
        for (var p = 0; p < _letters.length; p++)
          WordPuzzleSlot(
            key: ValueKey('word.slot.$p'),
            letter: p < _placed.length ? _letters[_placed[p]] : null,
            mark: right == null ? LearnMark.selected : (right ? LearnMark.correct : LearnMark.wrong),
            onTap: p < _placed.length && right == null ? () => _unplace(p) : null,
          ),
      ]),
      const SizedBox(height: AppSpace.md),
      if (right == null) ...[
        Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in pool)
            WordPuzzleTile(key: ValueKey('word.tile.$k'), letter: _letters[k], onTap: () => _place(k)),
        ]),
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(
            key: const ValueKey('word.hint'),
            label: t('تلميح', 'Hint'),
            icon: Icons.lightbulb_outline_rounded,
            onPressed: _hint,
          ),
        ),
      ] else
        LearnFeedback(
          correct: right,
          neutral: right && (_hinted || _slipped),
          title: right && _hinted ? t('حُلّت بتلميح', 'Solved with a hint') : null,
          explanation: right ? null : t('الكلمة: ${w.word}', 'The word: ${w.word}'),
          actionLabel: right ? (last ? t('النتيجة', 'See result') : t('التالي', 'Next')) : t('حاول مرة أخرى', 'Try again'),
          onAction: right ? _next : _retry,
        ),
      if (right == false) ...[
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.ghost(
            key: const ValueKey('word.skip'),
            label: last ? t('النتيجة', 'See result') : t('الكلمة التالية', 'Next word'),
            onPressed: _next,
          ),
        ),
      ],
      if (_placed.isEmpty && right == null)
        Text(t('اضغط الحروف بالترتيب.', 'Tap the letters in order.'),
            textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
    ]);
  }
}

/// One slot of the word: empty (a line), or a placed letter (tap to take it back).
class WordPuzzleSlot extends StatelessWidget {
  const WordPuzzleSlot({super.key, this.letter, this.mark = LearnMark.selected, this.onTap});

  final String? letter;
  final LearnMark mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = switch (mark) {
      LearnMark.correct => c.success,
      LearnMark.wrong => c.danger,
      _ => c.primary,
    };
    final l = letter;
    return Semantics(
      button: onTap != null,
      label: l ?? t('خانة فارغة', 'Empty slot'),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: l == null ? c.inputBg : appTintOn(context, tone),
            borderRadius: AppRadius.chipAll,
            border: Border(bottom: BorderSide(color: tone, width: 2)),
          ),
          child: Text(l ?? '', style: AppType.section(context).copyWith(color: l == null ? c.textLight : appInkOn(context, tone, appTintOn(context, tone)))),
        ),
      ),
    );
  }
}

/// One letter in the pool.
class WordPuzzleTile extends StatelessWidget {
  const WordPuzzleTile({super.key, required this.letter, this.onTap});

  final String letter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: letter,
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            alignment: Alignment.center,
            child: Text(letter, style: AppType.section(context).copyWith(color: c.textDark)),
          ),
        ),
      ),
    );
  }
}
