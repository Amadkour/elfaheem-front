// lib/features/learn_kit/learn_question.dart — the question parts of the learn kit (D-1346): the prompt card, one
// answer row, a list of them, small wrapping choices and the right / wrong feedback panel. Plain values only; the
// caller owns the state (which option is picked, when to reveal).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/learn_kit/learn_grading.dart';

const _arLetters = ['أ', 'ب', 'ج', 'د', 'هـ', 'و', 'ز', 'ح'];
const _enLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

/// The letter of option [i] in the app's language (أ ب ج … / A B C …).
String learnOptionLetter(int i) {
  final l = AppConfig.lang == 'ar' ? _arLetters : _enLetters;
  return i < l.length ? l[i] : '${i + 1}';
}

String _markWord(LearnMark m) => switch (m) {
      LearnMark.correct => AppConfig.lang == 'ar' ? 'صحيح' : 'correct',
      LearnMark.wrong => AppConfig.lang == 'ar' ? 'خطأ' : 'wrong',
      LearnMark.missed => AppConfig.lang == 'ar' ? 'الإجابة الصحيحة' : 'the right answer',
      LearnMark.selected => AppConfig.lang == 'ar' ? 'مختار' : 'selected',
      LearnMark.idle => '',
    };

/// The colours of a mark: (fill, edge, ink, glyph).
({Color fill, Color edge, Color ink, IconData? glyph}) _markStyle(BuildContext context, LearnMark m) {
  final c = context.colors;
  switch (m) {
    case LearnMark.correct:
      final tint = appTintOn(context, c.success);
      return (fill: tint, edge: c.success, ink: appInkOn(context, c.success, tint), glyph: Icons.check_circle_rounded);
    case LearnMark.wrong:
      final tint = appTintOn(context, c.danger);
      return (fill: tint, edge: c.danger, ink: appInkOn(context, c.danger, tint), glyph: Icons.cancel_rounded);
    case LearnMark.missed:
      return (fill: c.cardBg, edge: c.success, ink: c.textDark, glyph: Icons.check_circle_outline_rounded);
    case LearnMark.selected:
      return (fill: c.primaryWash, edge: c.primary, ink: c.textDark, glyph: null);
    case LearnMark.idle:
      return (fill: c.cardBg, edge: c.divider, ink: c.textDark, glyph: null);
  }
}

/// The question card: an optional small caption above ("Question 3"), the prompt in the section role.
class LearnPrompt extends StatelessWidget {
  const LearnPrompt({super.key, required this.text, this.caption, this.icon});

  final String text;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSize.lg, color: c.primary),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (caption != null && caption!.isNotEmpty) ...[
              // each line its own leaf: on the web a label on a node that has children becomes an aria-label on a
              // generic element, which the browser drops (the question was missing, QA Phase 6)
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
              label: text,
              excludeSemantics: true,
              // an author's text keeps its own direction ("كم عدد أركان الإسلام؟" in the English interface, S13)
              child: AutoDirText(text, style: AppType.section(context)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// One answer row: a letter well, the text, and a ✓ / ✗ glyph once it is marked. 48 px at least; a mark is never
/// colour alone (the glyph and the screen-reader word carry it too).
class LearnOptionTile extends StatelessWidget {
  const LearnOptionTile({super.key, required this.label, this.mark = LearnMark.idle, this.onTap, this.index});

  final String label;
  final LearnMark mark;

  /// Null: not tappable (after the answer is revealed).
  final VoidCallback? onTap;

  /// Draws the option's letter (أ / A …) in a well at the start.
  final int? index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _markStyle(context, mark);
    final motion = AppMotion.of(context);
    final word = _markWord(mark);
    final letter = index == null ? null : learnOptionLetter(index!);
    return Semantics(
      button: onTap != null,
      selected: mark == LearnMark.selected,
      label: [?letter, label, if (word.isNotEmpty) word].join(', '),
      excludeSemantics: true,
      child: AppPressScale(
        enabled: onTap != null,
        child: AnimatedContainer(
          duration: motion.base,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          decoration: BoxDecoration(
            color: s.fill,
            borderRadius: AppRadius.controlAll,
            border: Border.all(
                color: s.edge, width: mark == LearnMark.idle ? AppBorder.hairline : AppBorder.strong),
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
                    Container(
                      width: AppIconSize.xl,
                      height: AppIconSize.xl,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: mark == LearnMark.idle ? c.inputBg : s.edge,
                        borderRadius: AppRadius.chipAll,
                      ),
                      child: Text(letter,
                          style: AppType.label(context)
                              .copyWith(color: mark == LearnMark.idle ? c.textMedium : appInkOnFill(context, s.edge))),
                    ),
                    const SizedBox(width: AppSpace.sm),
                  ],
                  Expanded(child: AutoDirText(label, style: AppType.row(context).copyWith(color: s.ink))),
                  if (s.glyph != null) ...[
                    const SizedBox(width: AppSpace.xs),
                    Icon(s.glyph, size: AppIconSize.md, color: s.edge),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A column of [LearnOptionTile]s. [marks] (same length as [options], or empty = all idle) says how each is drawn;
/// [onSelect] null = locked (after the reveal).
class LearnOptionList extends StatelessWidget {
  const LearnOptionList({super.key, required this.options, this.marks = const [], this.onSelect, this.lettered = true});

  final List<String> options;
  final List<LearnMark> marks;
  final ValueChanged<int>? onSelect;
  final bool lettered;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.xs),
        LearnOptionTile(
          key: ValueKey('learn.option.$i'),
          label: options[i],
          index: lettered ? i : null,
          mark: i < marks.length ? marks[i] : LearnMark.idle,
          onTap: onSelect == null ? null : () => onSelect!(i),
        ),
      ],
    ]);
  }
}

/// Small wrapping choices (a category for a word, the next step of an order): each a pill at least 48 px high.
class LearnChoiceChips extends StatelessWidget {
  const LearnChoiceChips({
    super.key,
    required this.options,
    this.marks = const [],
    this.onSelect,
    this.keyPrefix = 'learn.chip',
    this.semanticsPrefix,
  });

  final List<String> options;
  final List<LearnMark> marks;
  final ValueChanged<int>? onSelect;

  /// The chips' keys are `<keyPrefix>.<i>` (tests).
  final String keyPrefix;

  /// Read before each chip's label ("كتاب: اسم"), for rows whose chips repeat the same names.
  final String? semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (var i = 0; i < options.length; i++)
        _Chip(
          key: ValueKey('$keyPrefix.$i'),
          label: options[i],
          semanticsPrefix: semanticsPrefix,
          mark: i < marks.length ? marks[i] : LearnMark.idle,
          onTap: onSelect == null ? null : () => onSelect!(i),
        ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.mark, this.onTap, this.semanticsPrefix});

  final String label;
  final String? semanticsPrefix;
  final LearnMark mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = _markStyle(context, mark);
    final word = _markWord(mark);
    final r = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: onTap != null,
      selected: mark == LearnMark.selected,
      label: [
        if (semanticsPrefix != null && semanticsPrefix!.isNotEmpty) '${semanticsPrefix!}: $label' else label,
        if (word.isNotEmpty) word,
      ].join(', '),
      excludeSemantics: true,
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
          color: s.fill,
          shape: RoundedRectangleBorder(
            borderRadius: r,
            side: BorderSide(color: s.edge, width: mark == LearnMark.idle ? AppBorder.hairline : AppBorder.strong),
          ),
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.glyph != null) ...[
                    Icon(s.glyph, size: AppIconSize.sm, color: s.edge),
                    const SizedBox(width: AppSpace.xxs),
                  ],
                  Flexible(child: AutoDirText(label, style: AppType.row(context).copyWith(color: s.ink))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The right / wrong panel after a check: a glyph, a title ("Correct!" / "Not quite"), an optional explanation and
/// ONE action (Next, Finish). Announced to screen readers when it appears.
class LearnFeedback extends StatelessWidget {
  const LearnFeedback({
    super.key,
    required this.correct,
    this.title,
    this.explanation,
    this.actionLabel,
    this.onAction,
    this.neutral = false,
  });

  final bool correct;

  /// A finished round that is neither right nor wrong ("All pairs matched" after a slip): the calm primary tone and a
  /// flag glyph, never the error style.
  final bool neutral;

  /// Defaults to "Correct!" / "Not quite".
  final String? title;
  final String? explanation;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = neutral ? c.primary : (correct ? c.success : c.danger);
    final tint = appTintOn(context, tone);
    final ink = appInkOn(context, tone, tint);
    final head = title ?? (AppConfig.lang == 'ar' ? (correct ? 'إجابة صحيحة!' : 'ليست صحيحة') : (correct ? 'Correct!' : 'Not quite'));
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: AppSpace.card,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: tone, width: AppBorder.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(neutral ? Icons.flag_rounded : (correct ? Icons.check_circle_rounded : Icons.error_outline_rounded), color: ink, size: AppIconSize.lg),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(head, style: AppType.section(context).copyWith(color: ink))),
          ]),
          if (explanation != null && explanation!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(explanation!, style: AppType.body(context).copyWith(color: ink)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton.primary(key: const ValueKey('learn.feedback.action'), label: actionLabel!, onPressed: onAction),
            ),
          ],
        ]),
      ),
    );
  }
}
