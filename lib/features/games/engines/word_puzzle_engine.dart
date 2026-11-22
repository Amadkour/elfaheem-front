// lib/features/games/engines/word_puzzle_engine.dart — the `word_puzzle` engine (Learning Hub v2 §3, D-1585): one
// word at a time, its clue (`hint`) on top and its letters shuffled under it; tap the letters in order to rebuild it
// (tap a placed one to take it back). The word is checked once every letter is placed, after the Arabic
// normalization of game_text.dart. The Hint button places the next right letter; a word rebuilt with a hint (or after a wrong try) is
// solved but scores nothing (like a pair matched after a slip). Score = words rebuilt right with no hint, max = words.
// config = {prompt_ar, prompt_en, words: [{word, hint}]} (1..15)
//
// Layout (D-1670): the word built so far is ONE Text ([WordPuzzleEngine.builtText]), so Arabic letters join as they
// do in the word; under it one small square slot per letter (tap a placed one to take it back) and the pool of
// square tiles, both wrapping rows sized by the touch tokens, laid out in the WORD's direction (an Arabic word runs
// right to left in the English interface too).
//
// Games v3 (§1, D-1740): a tapped letter flies from the pool to its slot (`snap`) and the slot pops; a solved word
// waves (each slot to 1.12, `stagger` apart) and turns green; a wrong word shakes. The built word stays ONE Text.
// Trace (CONTRACT §3): one entry per check of a full word, `i` = the word's index, `a` = the letter indices in the
// order they were placed, `h: true` when Hint was used on this word before the check.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_text.dart';
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
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

  /// The word as far as [placed] goes, as one string: the letters joined (so Arabic ones connect) with the word's own
  /// spaces put back between them.
  static String builtText(String word, List<String> placed) {
    final out = StringBuffer();
    var k = 0;
    for (final g in word.trim().characters) {
      if (k >= placed.length) break;
      if (g.trim().isEmpty) {
        out.write(' ');
      } else {
        out.write(placed[k++]);
      }
    }
    return out.toString();
  }

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

  /// Slots whose letter is still flying in; the moves per slot; the word's shake.
  final Set<int> _landing = {};
  final Map<int, int> _slotPulse = {};
  int _seq = 0, _wordShake = 0;
  final List<GlobalKey> _slotKeys = [], _tileKeys = [];

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
    _landing.clear();
    _slotPulse.clear();
    _hinted = _slipped = false;
    _right = null;
    while (_slotKeys.length < _letters.length) {
      _slotKeys.add(GlobalKey());
      _tileKeys.add(GlobalKey());
    }
  }

  void _place(int k) {
    if (_right != null || _placed.contains(k)) return;
    final p = _placed.length;
    final fly = !GameMotion.of(context).off && _tileKeys[k].currentContext != null && _slotKeys[p].currentContext != null;
    if (fly) {
      final word = _i;
      GameFlight.fly(context, from: _tileKeys[k], to: _slotKeys[p], child: WordPuzzleTile(letter: _letters[k])).then((_) {
        if (!mounted || word != _i) return;
        setState(() {
          _landing.remove(p);
          _slotPulse[p] = ++_seq;
        });
        GameShellScope.maybeOf(context)?.sound(GameSound.snap);
      });
    } else {
      GameShellScope.maybeOf(context)?.sound(GameSound.snap);
    }
    setState(() {
      _placed.add(k);
      if (fly) _landing.add(p);
    });
    _maybeCheck();
  }

  void _unplace(int pos) {
    if (_right != null) return;
    setState(() {
      _placed.removeAt(pos);
      _landing.clear();
    });
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
    final shell = GameShellScope.maybeOf(context);
    shell?.record(_i, List<int>.of(_placed), hint: _hinted);
    setState(() {
      _right = right;
      _seq++;
      if (right) {
        // the wave: every slot, one after another
        for (var p = 0; p < _placed.length; p++) {
          _slotPulse[p] = _seq;
        }
      } else {
        _wordShake = _seq;
      }
      if (right && !_hinted && !_slipped) _score++;
      if (!right) _slipped = true;
    });
    shell?.report(done: _i + 1, score: _score, correct: right && !_hinted && !_slipped);
  }

  void _retry() => setState(() {
        _placed.clear();
        _landing.clear();
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
    if (_words.isEmpty) {
      return AppEmpty(icon: Icons.abc_rounded, title: t('لا توجد كلمات في هذه اللعبة', 'This game has no words'));
    }
    final w = _words[_i];
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final inShell = GameShellScope.maybeOf(context) != null;
    final last = _i + 1 >= _words.length;
    final right = _right;
    final pool = [for (final k in _pool) if (!_placed.contains(k)) k];
    final dir = contentDirection(w.word) ?? Directionality.of(context);
    final mark = right == null ? LearnMark.selected : (right ? LearnMark.correct : LearnMark.wrong);
    final n = _letters.length;
    final m = GameMotion.of(context);
    final sacred = GameShellScope.maybeOf(context)?.sacred ?? false;
    final slots = Wrap(textDirection: dir, alignment: WrapAlignment.center, spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
      for (var p = 0; p < n; p++)
        GamePulse(
          trigger: _slotPulse[p],
          peak: right == true ? GameMotion.wave : GameMotion.pulse,
          delay: right == true ? m.stagger * p : Duration.zero,
          child: WordPuzzleSlot(
            key: _slotKeys[p],
            slotKey: ValueKey('word.slot.$p'),
            letter: p < _placed.length && !_landing.contains(p) ? _letters[_placed[p]] : null,
            mark: mark,
            onTap: p < _placed.length && right == null ? () => _unplace(p) : null,
          ),
        ),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(current: _i + 1, total: _words.length, score: _score),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(
        key: ValueKey('word.q.$_i'),
        caption: prompt.isEmpty ? t('رتّب الحروف لتكوّن الكلمة', 'Put the letters together into the word') : prompt,
        text: w.hint.isEmpty
            ? countText(n,
                ar1: 'كلمة من حرف واحد',
                ar2: 'كلمة من حرفين',
                arFew: 'كلمة من $n حروف',
                arMany: 'كلمة من $n حرفًا',
                en1: 'A one-letter word',
                en: 'A word of $n letters')
            : w.hint,
      ),
      const SizedBox(height: AppSpace.sm),
      GameShake(
        trigger: _wordShake == 0 ? null : _wordShake,
        enabled: !sacred,
        child: WordPuzzleAnswer(
          key: const ValueKey('word.built'),
          text: WordPuzzleEngine.builtText(w.word, [for (final k in _placed) _letters[k]]),
          mark: mark,
          direction: dir,
          placeholder: t('اضغط الحروف بالترتيب', 'Tap the letters in order'),
        ),
      ),
      // one slot per letter: how many are left, and a placed one taps back into the pool (shown after the check
      // too, for the wave)
      const SizedBox(height: AppSpace.sm),
      slots,
      if (right == null) ...[
        const SizedBox(height: AppSpace.md),
        Wrap(textDirection: dir, alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in pool)
            KeyedSubtree(
              key: _tileKeys[k],
              child: WordPuzzleTile(key: ValueKey('word.tile.$k'), letter: _letters[k], onTap: () => _place(k)),
            ),
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
      ] else ...[
        const SizedBox(height: AppSpace.md),
        LearnFeedback(
          correct: right,
          neutral: right && (_hinted || _slipped),
          title: right && _hinted ? t('حُلّت بتلميح', 'Solved with a hint') : null,
          explanation: right ? null : t('الكلمة: ${bidiIsolate(w.word)}', 'The word: ${bidiIsolate(w.word)}'),
          actionLabel: right ? (last ? t('النتيجة', 'See result') : t('التالي', 'Next')) : t('حاول مرة أخرى', 'Try again'),
          onAction: right ? _next : _retry,
        ),
      ],
      if (right == false) ...[
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          // its own node, never merged into the feedback's text (N18)
          child: Semantics(
            container: true,
            child: AppButton.ghost(
              key: const ValueKey('word.skip'),
              label: last ? t('النتيجة', 'See result') : t('الكلمة التالية', 'Next word'),
              onPressed: _next,
            ),
          ),
        ),
      ],
    ]);
  }
}

/// The word built so far, as ONE Text so its letters join (Arabic), in the word's own [direction]; its frame takes
/// the check's colour once every letter is placed. Empty: the [placeholder] instruction.
class WordPuzzleAnswer extends StatelessWidget {
  const WordPuzzleAnswer({super.key, required this.text, required this.direction, this.mark = LearnMark.selected, this.placeholder = ''});

  final String text;
  final TextDirection direction;
  final LearnMark mark;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final checked = mark == LearnMark.correct || mark == LearnMark.wrong;
    final tone = switch (mark) {
      LearnMark.correct => c.success,
      LearnMark.wrong => c.danger,
      _ => c.primary,
    };
    final bg = checked ? appTintOn(context, tone) : c.inputBg;
    final empty = text.isEmpty;
    return Semantics(
      liveRegion: true,
      label: empty ? placeholder : text,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: AppMotion.of(context).fast,
        constraints: const BoxConstraints(minHeight: AppTouch.primary),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: checked ? tone : c.divider, width: checked ? AppBorder.strong : AppBorder.hairline),
        ),
        child: empty
            ? Text(placeholder, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium))
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  textDirection: direction,
                  maxLines: 1,
                  style: AppType.display(context).copyWith(color: checked ? appInkOn(context, tone, bg) : c.textDark),
                ),
              ),
      ),
    );
  }
}

/// One slot of the word, a small square: empty (a line), or a placed letter (tap to take it back).
class WordPuzzleSlot extends StatelessWidget {
  const WordPuzzleSlot({super.key, this.letter, this.mark = LearnMark.selected, this.onTap, this.slotKey});

  /// The key of the slot's box (tests), when [key] is the flight's GlobalKey.
  final Key? slotKey;

  /// The slot's side: the smallest touch target.
  static const double size = AppTouch.min;

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
          key: slotKey,
          width: WordPuzzleSlot.size,
          height: WordPuzzleSlot.size,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(AppSpace.xxs),
          decoration: BoxDecoration(
            color: l == null ? c.inputBg : appTintOn(context, tone),
            borderRadius: AppRadius.chipAll,
            border: Border(bottom: BorderSide(color: l == null ? c.divider : tone, width: AppBorder.strong)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(l ?? '', style: AppType.section(context).copyWith(color: appInkOn(context, tone, appTintOn(context, tone)))),
          ),
        ),
      ),
    );
  }
}

/// One letter in the pool, a square tile.
class WordPuzzleTile extends StatelessWidget {
  const WordPuzzleTile({super.key, required this.letter, this.onTap});

  /// The tile's side: a primary touch target (four or five fit a row on a 320 px phone).
  static const double size = AppTouch.primary;

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
            width: WordPuzzleTile.size,
            height: WordPuzzleTile.size,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(AppSpace.xxs),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(letter, style: AppType.headline(context).copyWith(color: c.textDark)),
            ),
          ),
        ),
      ),
    );
  }
}
