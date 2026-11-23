// lib/features/games/admin/v4/editors/choice_editors.dart — the editors of the three "pick the answer" types
// (Games v4 T65, CONTRACT §3): `mcq` (2..6 options, one answer), `true_false`, `select_all` (3..8, several answers).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

class McqEditor extends StatelessWidget {
  const McqEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  @override
  Widget build(BuildContext context) => _OptionsEditor(
        body: body,
        onChanged: onChanged,
        multi: false,
        min: 2,
        max: 6,
      );
}

class SelectAllEditor extends StatelessWidget {
  const SelectAllEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  @override
  Widget build(BuildContext context) => _OptionsEditor(
        body: body,
        onChanged: onChanged,
        multi: true,
        min: 3,
        max: 8,
      );
}

class _OptionsEditor extends StatelessWidget {
  const _OptionsEditor({required this.body, required this.onChanged, required this.multi, required this.min, required this.max});
  final Json body;
  final ValueChanged<Json> onChanged;
  final bool multi;
  final int min;
  final int max;

  List<Json> get _opts => jlist(body['options']);
  Set<int> get _answers => multi
      ? {for (final a in (body['answers'] is List ? body['answers'] as List : const [])) jint(a, -1)}
      : {jint(body['answer'], -1)};

  void _emit(List<Json> opts, Set<int> answers) {
    final sorted = answers.where((i) => i >= 0 && i < opts.length).toList()..sort();
    onChanged({...body, 'options': opts, if (multi) 'answers': sorted else 'answer': sorted.isEmpty ? 0 : sorted.first});
  }

  @override
  Widget build(BuildContext context) {
    final opts = _opts;
    final answers = _answers;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdTitle(
        multi ? t('الخيارات (اختر كل الصحيح)', 'Options (tick every correct one)') : t('الخيارات (اختر الصحيح)', 'Options (pick the correct one)'),
        hint: t('من $min إلى $max خيارات، ولا يتكرر نص.', '$min to $max options, none repeated.'),
      ),
      for (var i = 0; i < opts.length; i++)
        EdRow(
          key: edIndexKey('opt', i, opts.length),
          leading: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: multi
                ? Checkbox(
                    value: answers.contains(i),
                    onChanged: (v) => _emit(opts, v == true ? {...answers, i} : ({...answers}..remove(i))),
                  )
                // ignore: deprecated_member_use
                : Radio<int>(value: i, groupValue: answers.first, onChanged: (_) => _emit(opts, {i})),
          ),
          onRemove: opts.length > min
              ? () {
                  final next = [...opts]..removeAt(i);
                  _emit(next, {for (final a in answers) if (a != i) a > i ? a - 1 : a});
                }
              : null,
          child: EdText(
            label: t('الخيار ${i + 1}', 'Option ${i + 1}'),
            value: '${opts[i]['text'] ?? ''}',
            onChanged: (v) {
              final next = [...opts];
              next[i] = {...next[i], 'text': v};
              _emit(next, answers);
            },
          ),
        ),
      if (opts.length < max) EdAdd(label: t('إضافة خيار', 'Add an option'), onPressed: () => _emit([...opts, {'text': ''}], answers)),
    ]);
  }
}

class TrueFalseEditor extends StatelessWidget {
  const TrueFalseEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = body['answer'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdTitle(t('الإجابة الصحيحة', 'The correct answer')),
      Row(children: [
        Expanded(
          child: v
              ? AppButton.primary(label: t('صح', 'True'), icon: Icons.check_rounded, onPressed: () {})
              : AppButton.secondary(label: t('صح', 'True'), icon: Icons.check_rounded, onPressed: () => onChanged({...body, 'answer': true})),
        ),
        AppSpace.gapSm,
        Expanded(
          child: !v
              ? AppButton.primary(label: t('خطأ', 'False'), icon: Icons.close_rounded, onPressed: () {})
              : AppButton.secondary(label: t('خطأ', 'False'), icon: Icons.close_rounded, onPressed: () => onChanged({...body, 'answer': false})),
        ),
      ]),
    ]);
  }
}
