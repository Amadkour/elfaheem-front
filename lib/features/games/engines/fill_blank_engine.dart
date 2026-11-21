// lib/features/games/engines/fill_blank_engine.dart — the `fill_blank` engine (Learning Hub v2 §3, D-1583): one
// sentence at a time with one blank (`___`); pick the missing word from the options, or type it when the item has
// none. A typed answer is compared after the Arabic normalization of game_text.dart (no tashkeel, one alef). Score =
// right items, max = items.
// config = {prompt_ar, prompt_en, items: [{text, answer, options: [string] | null}]} (1..30)
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_text.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

/// The blank as the author writes it.
const String kGameBlank = '___';

typedef FillBlankItem = ({String text, String answer, List<String> options});

class FillBlankEngine extends StatefulWidget {
  const FillBlankEngine({super.key, required this.config, required this.onFinished, this.random});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  /// The playable items of [config]: an item without an answer is skipped; options are kept without blanks and
  /// repeats, and the answer is added when the author left it out (empty = typed).
  static List<FillBlankItem> itemsOf(Map<String, dynamic> config) {
    final raw = config['items'];
    final out = <FillBlankItem>[];
    if (raw is! List) return out;
    for (final it in raw) {
      if (it is! Map) continue;
      final answer = '${it['answer'] ?? ''}'.trim();
      if (answer.isEmpty) continue;
      final seen = <String>{};
      final opts = <String>[
        if (it['options'] is List)
          for (final o in it['options'] as List)
            if ('$o'.trim().isNotEmpty && seen.add(gameNormalize('$o'))) '$o'.trim(),
      ];
      if (opts.isNotEmpty && !seen.contains(gameNormalize(answer))) opts.add(answer);
      out.add((text: '${it['text'] ?? ''}', answer: answer, options: opts));
    }
    return out;
  }

  /// Whether [given] fills [item]'s blank.
  static bool isRight(FillBlankItem item, String given) => gameSameAnswer(given, item.answer);

  /// [text] with its blank drawn as a line, or as [filled] once answered (a text with no blank gets one at the end).
  static String show(String text, {String? filled}) {
    final blank = filled == null ? '______' : '«$filled»';
    return text.contains(kGameBlank) ? text.replaceFirst(kGameBlank, blank) : '$text $blank';
  }

  @override
  State<FillBlankEngine> createState() => _FillBlankEngineState();
}

class _FillBlankEngineState extends State<FillBlankEngine> {
  late final List<FillBlankItem> _items;
  late List<String> _options;
  final TextEditingController _typed = TextEditingController();
  int _i = 0, _score = 0;

  /// The answer given for the current item (null = not yet).
  String? _given;

  @override
  void initState() {
    super.initState();
    _items = FillBlankEngine.itemsOf(widget.config);
    _shuffleOptions();
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _shuffleOptions() =>
      _options = _items.isEmpty ? const [] : learnShuffle(_items[_i].options, random: widget.random, avoidIdentity: false);

  void _answer(String given) {
    if (_given != null || given.trim().isEmpty) return;
    final right = FillBlankEngine.isRight(_items[_i], given);
    setState(() {
      _given = given.trim();
      if (right) _score++;
    });
    GameShellScope.maybeOf(context)?.report(done: _i + 1, score: _score, correct: right);
  }

  void _next() {
    if (_i + 1 >= _items.length) {
      widget.onFinished(_score, _items.length);
      return;
    }
    setState(() {
      _i++;
      _given = null;
      _typed.clear();
      _shuffleOptions();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return AppEmpty(icon: Icons.edit_note_rounded, title: t('لا توجد جمل في هذه اللعبة', 'This game has no sentences'));
    }
    final item = _items[_i];
    final given = _given;
    final right = given != null && FillBlankEngine.isRight(item, given);
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final inShell = GameShellScope.maybeOf(context) != null;
    final last = _i + 1 >= _items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(current: _i + 1, total: _items.length, score: _score),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(
        key: ValueKey('fill.q.$_i'),
        caption: prompt.isEmpty ? t('أكمل الفراغ', 'Fill in the blank') : prompt,
        text: FillBlankEngine.show(item.text, filled: given == null ? null : item.answer),
      ),
      const SizedBox(height: AppSpace.sm),
      if (item.options.isNotEmpty)
        LearnOptionList(
          options: _options,
          marks: [
            for (final o in _options)
              given == null
                  ? LearnMark.idle
                  : gameSameAnswer(o, item.answer)
                      ? (gameSameAnswer(o, given) ? LearnMark.correct : LearnMark.missed)
                      : (o == given ? LearnMark.wrong : LearnMark.idle),
          ],
          onSelect: given == null ? (k) => _answer(_options[k]) : null,
        )
      else ...[
        AppField(
          key: const ValueKey('fill.input'),
          controller: _typed,
          label: t('اكتب الكلمة الناقصة', 'Type the missing word'),
          enabled: given == null,
          textInputAction: TextInputAction.done,
          onSubmitted: _answer,
        ),
        if (given == null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.primary(
              key: const ValueKey('fill.check'),
              label: t('تحقّق', 'Check'),
              icon: Icons.check_rounded,
              onPressed: () => _answer(_typed.text),
            ),
          ),
      ],
      if (given != null) ...[
        const SizedBox(height: AppSpace.md),
        LearnFeedback(
          correct: right,
          explanation: right ? null : t('الإجابة الصحيحة: ${item.answer}', 'The right answer: ${item.answer}'),
          actionLabel: last ? t('النتيجة', 'See result') : t('التالي', 'Next'),
          onAction: _next,
        ),
      ],
    ]);
  }
}
