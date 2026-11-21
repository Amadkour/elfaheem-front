// lib/features/nahw/nahw_exercise_view.dart — one nahw exercise over plain values, drawn with the learn kit
// (D-1349): `choose` = a lettered option list, `fill` = the sentence with its gap + choice chips, `classify` = each
// word with a chip per category. After the check every choice shows right / wrong / the missed answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

import 'nahw_models.dart';

/// The marks of a single-pick question: [picked] and, once [checked], right / wrong / missed against [answer].
List<LearnMark> nahwPickMarks(int count, int? picked, int answer, bool checked) => [
      for (var i = 0; i < count; i++)
        !checked
            ? (i == picked ? LearnMark.selected : LearnMark.idle)
            : i == answer
                ? (picked == answer ? LearnMark.correct : LearnMark.missed)
                : (i == picked ? LearnMark.wrong : LearnMark.idle),
    ];

class NahwExerciseView extends StatelessWidget {
  const NahwExerciseView({
    super.key,
    required this.exercise,
    required this.response,
    required this.onChanged,
    this.checked = false,
  });

  final NahwExercise exercise;
  final NahwResponse response;
  final ValueChanged<NahwResponse> onChanged;

  /// Graded: the choices are locked and marked.
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    switch (e.kind) {
      case 'choose':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LearnPrompt(text: e.title, icon: Icons.help_outline_rounded),
          AppSpace.gapSm,
          LearnOptionList(
            options: e.options,
            marks: nahwPickMarks(e.options.length, response.choice, (e.answer['index'] as num).toInt(), checked),
            onSelect: checked ? null : (i) => onChanged(response.withChoice(i)),
          ),
        ]);
      case 'fill':
        final answer = e.options.indexWhere((o) => o.trim() == '${e.answer['text']}'.trim());
        final picked = response.choice;
        final shown = picked != null && picked < e.options.length ? e.options[picked] : '___';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LearnPrompt(
            text: e.text.isEmpty ? e.title : e.text.replaceFirst('___', shown),
            caption: e.text.isEmpty ? null : e.title,
            icon: Icons.edit_note_rounded,
          ),
          AppSpace.gapSm,
          LearnChoiceChips(
            keyPrefix: 'nahw.fill.${e.id}',
            options: e.options,
            marks: nahwPickMarks(e.options.length, picked, answer, checked),
            onSelect: checked ? null : (i) => onChanged(response.withChoice(i)),
          ),
        ]);
      case 'classify':
        final cats = e.categories;
        final want = e.answerItems;
        final items = e.items;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LearnPrompt(text: e.title, icon: Icons.category_rounded),
          AppSpace.gapSm,
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.xs),
            _ClassifyRow(
              key: ValueKey('nahw.classify.${e.id}.$i'),
              index: i,
              exerciseId: e.id,
              text: items[i],
              categories: [for (final c in cats) c.label],
              marks: nahwPickMarks(
                cats.length,
                i < response.items.length ? cats.indexWhere((c) => c.key == response.items[i]) : null,
                cats.indexWhere((c) => c.key == want[i]),
                checked,
              ),
              onSelect: checked ? null : (k) => onChanged(response.withItem(i, cats[k].key, items.length)),
            ),
          ],
        ]);
    }
    return const SizedBox.shrink();
  }
}

class _ClassifyRow extends StatelessWidget {
  const _ClassifyRow({
    super.key,
    required this.index,
    required this.exerciseId,
    required this.text,
    required this.categories,
    required this.marks,
    this.onSelect,
  });

  final int index;
  final int exerciseId;
  final String text;
  final List<String> categories;
  final List<LearnMark> marks;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(text, style: AppType.bodyStrong(context).copyWith(color: context.colors.textDark)),
        const SizedBox(height: AppSpace.xs),
        LearnChoiceChips(
          keyPrefix: 'nahw.classify.$exerciseId.$index',
          options: categories,
          marks: marks,
          onSelect: onSelect,
        ),
      ]),
    );
  }
}

/// The checked exercise's verdict line for a classify (how many of the items were sorted right).
String nahwPartText(NahwGrade g) => t('${g.score} من ${g.max} صحيحة', '${g.score} of ${g.max} right');
