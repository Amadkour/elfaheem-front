// lib/features/games/engines/fill_blank_engine.dart — the `fill_blank` engine (Learning Hub v2 §3, D-1583): one
// sentence at a time with one blank (`___`); pick the missing word from the options, or type it when the item has
// none. A typed answer is compared after the Arabic normalization of game_text.dart (no tashkeel, one alef). Score =
// right items, max = items.
// config = {prompt_ar, prompt_en, items: [{text, answer, options: [string] | null}]} (1..30)
//
// Games v3 (§1, D-1740): the sentence draws its blank as a real slot ([FillBlankSentence]); the chosen chip flies
// into it (`snap`) and its underline takes the answer's colour; a wrong chip shakes there and flies back to its
// option. The answer is settled at the tap (the flight only decorates it), so nothing waits on the motion.
// Trace (CONTRACT §3): one entry per answered item, `i` = the item's index, `a` = the picked option as written or the
// typed text.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_text.dart';
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/shell/game_tile.dart';
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
  /// exact repeats, and the answer is added when the author left it out (empty = typed). Options are compared as
  /// written, tashkeel included: a "pick the right ending" item offers العلمُ / العلمَ / العلمِ (D-1676).
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
            if ('$o'.trim().isNotEmpty && seen.add('$o'.trim())) '$o'.trim(),
      ];
      if (opts.isNotEmpty && !seen.contains(answer)) opts.add(answer);
      out.add((text: '${it['text'] ?? ''}', answer: answer, options: opts));
    }
    return out;
  }

  /// Whether [given] fills [item]'s blank: a picked option is the answer exactly (the server keeps the answer among
  /// the options as written); a typed answer is compared after the Arabic normalization.
  static bool isRight(FillBlankItem item, String given) =>
      item.options.isNotEmpty ? given.trim() == item.answer : gameSameAnswer(given, item.answer);

  /// [text] with its blank drawn as a line, or as [filled] once answered. A text with no blank stays as written (the
  /// server never stores one; the editor's live preview then shows the mistake rather than a made-up blank, D-1672).
  static String show(String text, {String? filled}) {
    final blank = filled == null ? '______' : '«$filled»';
    return text.replaceFirst(kGameBlank, blank);
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

  /// The picked chip is still flying to the blank (the blank shows it once it lands).
  bool _flying = false;
  int _seq = 0;
  final GlobalKey _blankKey = GlobalKey();
  final List<GlobalKey> _optionKeys = [];

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

  void _answer(String given, {int? option}) {
    if (_given != null || given.trim().isEmpty) return;
    final right = FillBlankEngine.isRight(_items[_i], given);
    final shell = GameShellScope.maybeOf(context);
    // a picked option as written in the config, a typed answer as typed (CONTRACT §3; the server trims)
    shell?.record(_i, option != null ? given.trim() : given);
    final fly = option != null && !GameMotion.of(context).off && _blankKey.currentContext != null;
    setState(() {
      _given = given.trim();
      _seq++;
      _flying = fly;
      if (right) _score++;
    });
    shell?.report(done: _i + 1, score: _score, correct: right);
    if (fly) {
      final item = _i;
      GameFlight.fly(context, from: _optionKeys[option], to: _blankKey, wrong: !right, child: FillBlankChip(label: given.trim()))
          .then((_) {
        if (mounted && _i == item) setState(() => _flying = false);
      });
    }
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
    final shell = GameShellScope.maybeOf(context);
    final inShell = shell != null;
    final sacred = shell?.sacred ?? false;
    final last = _i + 1 >= _items.length;
    while (_optionKeys.length < _options.length) {
      _optionKeys.add(GlobalKey());
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(current: _i + 1, total: _items.length, score: _score),
        const SizedBox(height: AppSpace.md),
      ],
      FillBlankSentence(
        key: ValueKey('fill.q.$_i'),
        blankKey: _blankKey,
        caption: prompt.isEmpty ? t('أكمل الفراغ', 'Fill in the blank') : prompt,
        text: item.text,
        // the blank holds what was given, in its colour; the right answer is the green option and the explanation
        filled: given == null || _flying ? null : given,
        state: given == null || _flying ? GameTileState.idle : (right ? GameTileState.correct : GameTileState.wrong),
      ),
      const SizedBox(height: AppSpace.sm),
      if (item.options.isNotEmpty)
        for (var k = 0; k < _options.length; k++) ...[
          if (k > 0) const SizedBox(height: AppSpace.xs),
          KeyedSubtree(
            key: _optionKeys[k],
            child: GameTile(
              key: ValueKey('learn.option.$k'),
              label: _options[k],
              index: k,
              state: given == null
                  ? GameTileState.idle
                  : _options[k] == given
                      ? (right ? GameTileState.correct : GameTileState.wrong)
                      : (_options[k] == item.answer ? GameTileState.hint : GameTileState.locked),
              pulse: given != null && right && _options[k] == given ? _seq : null,
              shake: given != null && !right && _options[k] == given ? _seq : null,
              shakeEnabled: !sacred,
              onTap: given == null ? () => _answer(_options[k], option: k) : null,
            ),
          ),
        ]
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

/// The sentence with its blank as a slot: the caption above, the text around the blank, and the blank itself an
/// underlined box ([blankKey], the flight's target) that holds [filled] once answered; its underline takes [state]'s
/// colour. A text with no blank is drawn as written. One Semantics label reads the sentence with its answer.
class FillBlankSentence extends StatelessWidget {
  const FillBlankSentence({
    super.key,
    required this.text,
    this.caption,
    this.filled,
    this.state = GameTileState.idle,
    this.blankKey,
  });

  final String text;
  final String? caption, filled;
  final GameTileState state;
  final GlobalKey? blankKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = GameMotion.of(context);
    final at = text.indexOf(kGameBlank);
    final style = AppType.section(context);
    final dir = contentDirection(text) ?? Directionality.of(context);
    final tone = switch (state) {
      GameTileState.correct => c.success,
      GameTileState.wrong => c.danger,
      _ => c.primary,
    };
    final checked = state == GameTileState.correct || state == GameTileState.wrong;
    final Widget body;
    if (at < 0) {
      body = Text(text, textDirection: dir, style: style);
    } else {
      final f = filled;
      final blank = AnimatedContainer(
        key: blankKey,
        duration: m.tap,
        curve: GameMotion.move,
        constraints: const BoxConstraints(minWidth: AppTouch.primary + AppSpace.lg),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
        decoration: BoxDecoration(
          color: checked ? appTintOn(context, tone) : c.inputBg,
          borderRadius: AppRadius.chipAll,
          border: Border(bottom: BorderSide(color: checked ? tone : c.divider, width: AppBorder.line)),
        ),
        child: Text(f ?? ' ',
            textAlign: TextAlign.center,
            textDirection: f == null ? dir : (contentDirection(f) ?? dir),
            style: style.copyWith(color: checked ? appInkOn(context, tone, appTintOn(context, tone)) : c.textDark)),
      );
      body = Text.rich(
        TextSpan(children: [
          TextSpan(text: text.substring(0, at)),
          WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: blank),
          TextSpan(text: text.substring(at + kGameBlank.length)),
        ]),
        textDirection: dir,
        style: style,
      );
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (caption != null && caption!.isNotEmpty) ...[
          Semantics(
            container: true,
            label: caption,
            excludeSemantics: true,
            child: AutoDirText(caption!, style: AppType.overline(context).copyWith(color: c.textMedium)),
          ),
          const SizedBox(height: AppSpace.xxs),
        ],
        Semantics(
          container: true,
          header: true,
          headingLevel: 2,
          label: FillBlankEngine.show(text, filled: filled),
          excludeSemantics: true,
          child: SizedBox(width: double.infinity, child: body),
        ),
      ]),
    );
  }
}

/// The chip that flies into the blank.
class FillBlankChip extends StatelessWidget {
  const FillBlankChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: c.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.primary, width: AppBorder.strong),
        boxShadow: AppElevation.of(context, 2),
      ),
      child: AutoDirText(label, style: AppType.row(context).copyWith(color: c.textDark)),
    );
  }
}
