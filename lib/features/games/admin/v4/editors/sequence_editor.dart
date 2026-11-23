// lib/features/games/admin/v4/editors/sequence_editor.dart — the `sequence` editor (Games v4 T65, CONTRACT §3, §9).
//
// Typed tokens (one per line, 2..12) for ordinary subjects. For Quran / Hadith the tokens are a REFERENCE
// (`@quran:112:1`, `@hadith:bukhari:1`) that the picker fills: the text is never typed, the editor only shows the
// reference and a button to choose another passage (sacred text is read-only, CONTRACT §8 `sacred_text`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

class SequenceEditor extends StatelessWidget {
  const SequenceEditor({super.key, required this.body, required this.onChanged, this.sacredKind, this.onPick});

  final Json body;
  final ValueChanged<Json> onChanged;

  /// `quran` / `hadith` when the item's source is sacred text: the tokens are then a reference chosen by [onPick].
  final String? sacredKind;
  final VoidCallback? onPick;

  bool get _isRef => body['tokens'] is String;

  @override
  Widget build(BuildContext context) {
    final mode = '${body['mode'] ?? 'order'}';
    final unit = '${body['unit'] ?? 'word'}';
    final typed = body['tokens'] is List ? [for (final x in body['tokens'] as List) '$x'] : <String>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdSelect<String>(
        label: t('طريقة اللعب', 'How it is played'),
        value: mode,
        options: [
          ('order', t('رتّب كل القطع', 'Put every piece in order')),
          ('complete', t('أكمل الفراغات', 'Fill the blanks')),
          ('next_word', t('اختر الكلمة التالية', 'Pick the next word')),
        ],
        onChanged: (v) => onChanged({...body, 'mode': v}),
      ),
      AppSpace.gapSm,
      EdSelect<String>(
        label: t('القطعة', 'The pieces are'),
        value: unit,
        options: [
          ('word', t('كلمات', 'Words')),
          ('letter', t('حروف كلمة', 'Letters of a word')),
          if (sacredKind == 'quran') ('ayah', t('آيات', 'Whole ayat')),
          if (sacredKind == 'quran') ('segment', t('مقاطع الوقف', 'Pause segments')),
        ],
        onChanged: (v) => onChanged({...body, 'unit': v}),
      ),
      AppSpace.gapSm,
      if (sacredKind != null || _isRef) ...[
        EdTitle(t('النص', 'The text'), hint: t('النص الشريف لا يُكتب ولا يُعدَّل: اخترته من المصدر.', 'Sacred text is picked from its source, never typed or edited.')),
        AppCard(
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, size: AppIconSize.md, color: context.colors.textMedium),
            AppSpace.gapSm,
            Expanded(
              child: Text(_isRef ? '${body['tokens']}' : t('لم يُختر نص بعد', 'No text picked yet'),
                  textDirection: TextDirection.ltr, style: AppType.bodyStrong(context)),
            ),
            AppButton.tonal(label: _isRef ? t('تغيير', 'Change') : t('اختيار', 'Pick'), onPressed: onPick),
          ]),
        ),
      ] else
        EdText(
          label: t('القطع (واحدة في كل سطر)', 'Pieces (one per line)'),
          helper: t('من 2 إلى 12 قطعة بالترتيب الصحيح.', '2 to 12 pieces in the right order.'),
          value: typed.join('\n'),
          maxLines: 6,
          onChanged: (v) => onChanged({
            ...body,
            'tokens': [for (final l in v.split('\n')) if (l.trim().isNotEmpty) l.trim()],
          }),
        ),
      AppSpace.gapSm,
      if (mode == 'complete')
        EdText(
          label: t('أرقام الفراغات (مثل 2,4)', 'Blank positions (like 2,4)'),
          helper: t('من 1 إلى 6 فراغات، العدّ يبدأ من صفر.', '1 to 6 blanks, counting from zero.'),
          value: (body['blanks'] is List ? (body['blanks'] as List).join(',') : ''),
          ltr: true,
          onChanged: (v) => onChanged({
            ...body,
            'blanks': [for (final p in v.split(RegExp(r'[,\s،]+'))) if (int.tryParse(p) != null) int.parse(p)],
          }),
        ),
      if (mode == 'next_word')
        AppNumberField(
          label: t('كم قطعة تظهر أولاً', 'Pieces shown first'),
          initialValue: jint(body['given'], 1),
          min: 1,
          max: 11,
          onChanged: (v) => onChanged({...body, 'given': v?.toInt() ?? 1}),
        ),
      AppSpace.gapSm,
      AppNumberField(
        label: t('قطع مضلِّلة (0 إلى 4)', 'Wrong pieces added (0 to 4)'),
        initialValue: jint(body['distractors'], 0),
        min: 0,
        max: 4,
        onChanged: (v) => onChanged({...body, 'distractors': v?.toInt() ?? 0}),
      ),
    ]);
  }
}
