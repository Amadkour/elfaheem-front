// lib/features/games/admin/v4/editors/group_editors.dart — `classify` (buckets + tokens) and `pair` (a ↔ b)
// editors (Games v4 T65, CONTRACT §3). Keys of buckets are made for the admin (`g1`, `g2` …): nobody types a key.
// A classify body's optional `cases` / `board` are kept untouched (they are not edited here).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

class ClassifyEditor extends StatelessWidget {
  const ClassifyEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  String _label(Json b) {
    final l = b['label'];
    return l is Map ? '${l['ar'] ?? l['en'] ?? ''}' : '${l ?? ''}';
  }

  String _newKey(List<Json> buckets) {
    var n = buckets.length + 1;
    while (buckets.any((b) => b['key'] == 'g$n')) {
      n++;
    }
    return 'g$n';
  }

  @override
  Widget build(BuildContext context) {
    final buckets = jlist(body['buckets']);
    final tokens = jlist(body['tokens']);
    void emit(List<Json> b, List<Json> tk) => onChanged({...body, 'buckets': b, 'tokens': tk});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdTitle(t('المجموعات', 'Groups'), hint: t('من 2 إلى 6 مجموعات.', '2 to 6 groups.')),
      for (var i = 0; i < buckets.length; i++)
        EdRow(
          key: edIndexKey('bk', i, buckets.length),
          onRemove: buckets.length > 2
              ? () {
                  final gone = '${buckets[i]['key']}';
                  final first = '${buckets.firstWhere((b) => b['key'] != gone)['key']}';
                  emit([...buckets]..removeAt(i), [for (final x in tokens) x['bucket'] == gone ? {...x, 'bucket': first} : x]);
                }
              : null,
          child: Column(children: [
            EdText(
              label: t('اسم المجموعة ${i + 1} · عربي', 'Group ${i + 1} name · Arabic'),
              value: jmap(buckets[i]['label'])['ar']?.toString() ?? '',
              onChanged: (v) {
                final next = [...buckets];
                next[i] = {...next[i], 'label': {...jmap(next[i]['label']), 'ar': v}};
                emit(next, tokens);
              },
            ),
            AppSpace.gapSm,
            EdText(
              label: t('اسم المجموعة ${i + 1} · إنجليزي', 'Group ${i + 1} name · English'),
              value: jmap(buckets[i]['label'])['en']?.toString() ?? '',
              ltr: true,
              onChanged: (v) {
                final next = [...buckets];
                next[i] = {...next[i], 'label': {...jmap(next[i]['label']), 'en': v}};
                emit(next, tokens);
              },
            ),
          ]),
        ),
      if (buckets.length < 6)
        EdAdd(
          label: t('إضافة مجموعة', 'Add a group'),
          onPressed: () => emit([...buckets, {'key': _newKey(buckets), 'label': {'ar': '', 'en': ''}}], tokens),
        ),
      EdTitle(t('العناصر', 'Things to sort'), hint: t('من 2 إلى 12 عنصراً، ولكل عنصر مجموعته الصحيحة.', '2 to 12 things, each with its right group.')),
      for (var i = 0; i < tokens.length; i++)
        EdRow(
          key: edIndexKey('tk', i, tokens.length),
          onRemove: tokens.length > 2 ? () => emit(buckets, [...tokens]..removeAt(i)) : null,
          child: Column(children: [
            EdText(
              label: t('العنصر ${i + 1}', 'Thing ${i + 1}'),
              value: '${tokens[i]['text'] ?? ''}',
              onChanged: (v) {
                final next = [...tokens];
                next[i] = {...next[i], 'text': v};
                emit(buckets, next);
              },
            ),
            AppSpace.gapSm,
            EdSelect<String>(
              label: t('مجموعته الصحيحة', 'Its right group'),
              value: buckets.any((b) => b['key'] == tokens[i]['bucket']) ? '${tokens[i]['bucket']}' : null,
              options: [
                for (var j = 0; j < buckets.length; j++)
                  ('${buckets[j]['key']}', _label(buckets[j]).isEmpty ? t('المجموعة ${j + 1}', 'Group ${j + 1}') : _label(buckets[j])),
              ],
              onChanged: (v) {
                final next = [...tokens];
                next[i] = {...next[i], 'bucket': v};
                emit(buckets, next);
              },
            ),
          ]),
        ),
      if (tokens.length < 12)
        EdAdd(
          label: t('إضافة عنصر', 'Add a thing'),
          onPressed: () => emit(buckets, [...tokens, {'text': '', 'bucket': buckets.isEmpty ? 'g1' : '${buckets.first['key']}'}]),
        ),
    ]);
  }
}

class PairEditor extends StatelessWidget {
  const PairEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  @override
  Widget build(BuildContext context) {
    final pairs = jlist(body['pairs']);
    void emit(List<Json> p) => onChanged({...body, 'pairs': p});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdTitle(t('الأزواج', 'Pairs'), hint: t('من 2 إلى 8 أزواج، ولا يتكرر طرف.', '2 to 8 pairs, no side repeated.')),
      for (var i = 0; i < pairs.length; i++)
        EdRow(
          key: edIndexKey('pr', i, pairs.length),
          onRemove: pairs.length > 2 ? () => emit([...pairs]..removeAt(i)) : null,
          child: Column(children: [
            EdText(
              label: t('الطرف الأول ${i + 1}', 'First side ${i + 1}'),
              value: '${pairs[i]['a'] ?? ''}',
              onChanged: (v) {
                final next = [...pairs];
                next[i] = {...next[i], 'a': v};
                emit(next);
              },
            ),
            AppSpace.gapSm,
            EdText(
              label: t('الطرف الثاني ${i + 1}', 'Second side ${i + 1}'),
              value: '${pairs[i]['b'] ?? ''}',
              onChanged: (v) {
                final next = [...pairs];
                next[i] = {...next[i], 'b': v};
                emit(next);
              },
            ),
          ]),
        ),
      if (pairs.length < 8) EdAdd(label: t('إضافة زوج', 'Add a pair'), onPressed: () => emit([...pairs, {'a': '', 'b': ''}])),
    ]);
  }
}
