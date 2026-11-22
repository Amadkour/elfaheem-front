// lib/features/nahw/admin/nahw_exercise_draft.dart — one nahw exercise as the admin editor holds it (6.R #8, D-1349):
// typed fields per kind, the payload the server takes, the first thing missing, and the learn-kit exercise the preview
// draws. Plain Dart; the shapes are the server's `check_exercise` (back features/nahw/nahw_service.py):
//
//   choose    data {options: [text ≥ 2]}                                answer {index}
//   fill      data {text: "… ___ …", options: [text ≥ 2]}              answer {text} (one of the options)
//   classify  data {categories: [{key, label_ar, label_en} ≥ 2],       answer {items: [category key per item]}
//                   items: [{text} ≥ 1]}
//
// `order` is not offered (the app skips it). `data.prompt_en` carries the English prompt; any other data key the
// exercise already had is kept as it was.
library;

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import '../nahw_models.dart';

const kNahwEditableKinds = ['choose', 'fill', 'classify'];

String nahwKindName(String kind) => switch (kind) {
      'choose' => t('اختيار من متعدد', 'Multiple choice'),
      'fill' => t('أكمل الفراغ', 'Fill the gap'),
      'classify' => t('صنّف', 'Classify'),
      'order' => t('ترتيب (لا يظهر في التطبيق)', 'Order (not shown in the app)'),
      _ => kind,
    };

class NahwCategoryDraft {
  NahwCategoryDraft({required this.key, this.labelAr = '', this.labelEn = ''});

  final String key;
  String labelAr;
  String labelEn;
}

class NahwItemDraft {
  NahwItemDraft({this.text = '', this.category});

  String text;

  /// The category's key (null = not chosen yet).
  String? category;
}

class NahwExerciseDraft {
  NahwExerciseDraft({
    this.id,
    this.kind = 'choose',
    this.prompt = '',
    this.promptEn = '',
    this.explanation = '',
    this.sort = 0,
    this.text = '',
    List<String>? options,
    this.answerIndex,
    List<NahwCategoryDraft>? categories,
    List<NahwItemDraft>? items,
    Map<String, dynamic>? extraData,
  })  : options = options ?? ['', ''],
        categories = categories ?? [NahwCategoryDraft(key: 'c1'), NahwCategoryDraft(key: 'c2')],
        items = items ?? [NahwItemDraft()],
        extraData = extraData ?? {};

  /// Null: a new exercise.
  final int? id;
  String kind;
  String prompt;
  String promptEn;
  String explanation;
  int sort;

  /// fill: the sentence, `___` where the answer goes.
  String text;

  /// choose / fill.
  List<String> options;

  /// choose / fill: the right option.
  int? answerIndex;

  /// classify.
  List<NahwCategoryDraft> categories;
  List<NahwItemDraft> items;

  /// The exercise's other data keys, sent back unchanged.
  final Map<String, dynamic> extraData;

  static List<String> _texts(dynamic v) => v is List ? [for (final x in v) '$x'] : <String>[];

  factory NahwExerciseDraft.from(Map<String, dynamic> m) {
    final data = m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : <String, dynamic>{};
    final answer = m['answer'] is Map ? Map<String, dynamic>.from(m['answer'] as Map) : <String, dynamic>{};
    final kind = '${m['kind'] ?? 'choose'}';
    final options = _texts(data['options']);
    int? index;
    if (kind == 'choose' && answer['index'] is num) index = (answer['index'] as num).toInt();
    if (kind == 'fill') {
      final i = options.indexWhere((o) => o.trim() == '${answer['text'] ?? ''}'.trim());
      index = i < 0 ? null : i;
    }
    final cats = [
      for (final c in (data['categories'] is List ? data['categories'] as List : const []))
        if (c is Map) NahwCategoryDraft(key: '${c['key'] ?? ''}', labelAr: '${c['label_ar'] ?? ''}', labelEn: '${c['label_en'] ?? ''}'),
    ];
    final want = _texts(answer['items']);
    final rawItems = data['items'] is List ? data['items'] as List : const [];
    final items = [
      for (var i = 0; i < rawItems.length; i++)
        NahwItemDraft(
          text: rawItems[i] is Map ? '${(rawItems[i] as Map)['text'] ?? ''}' : '${rawItems[i]}',
          category: i < want.length && want[i].isNotEmpty ? want[i] : null,
        ),
    ];
    final extra = Map<String, dynamic>.from(data)
      ..remove('prompt_en')
      ..remove('options')
      ..remove('text')
      ..remove('categories')
      ..remove('items');
    return NahwExerciseDraft(
      id: m['id'] is num ? (m['id'] as num).toInt() : null,
      kind: kind,
      prompt: '${m['prompt'] ?? ''}',
      promptEn: '${data['prompt_en'] ?? ''}',
      explanation: '${m['explanation'] ?? ''}',
      sort: m['sort'] is num ? (m['sort'] as num).toInt() : 0,
      text: '${data['text'] ?? ''}',
      options: options.length < 2 ? [...options, for (var i = options.length; i < 2; i++) ''] : options,
      answerIndex: index,
      categories: cats.length < 2 ? null : cats,
      items: items.isEmpty ? null : items,
      extraData: extra,
    );
  }

  bool get editable => kNahwEditableKinds.contains(kind);

  /// A key no category of this exercise uses yet.
  String nextCategoryKey() {
    var n = categories.length + 1;
    while (categories.any((c) => c.key == 'c$n')) {
      n++;
    }
    return 'c$n';
  }

  List<String> get _cleanOptions => [for (final o in options) o.trim()];

  /// The first thing missing, in the app's language; null = ready to save.
  String? problem() {
    if (!editable) return t('هذا النوع لا يُعدَّل من هنا', 'This kind cannot be edited here');
    if (prompt.trim().isEmpty) return t('اكتب نص السؤال', 'Write the question');
    switch (kind) {
      case 'choose':
      case 'fill':
        final o = _cleanOptions;
        if (o.length < 2 || o.any((x) => x.isEmpty)) return t('اكتب خيارين على الأقل ولا تترك خياراً فارغاً', 'Write at least two options and leave none empty');
        if (o.toSet().length != o.length) return t('لا تكرر الخيار نفسه', 'Do not repeat an option');
        if (answerIndex == null || answerIndex! < 0 || answerIndex! >= o.length) return t('اختر الإجابة الصحيحة', 'Choose the right answer');
        if (kind == 'fill' && text.trim().isNotEmpty && !text.contains('___')) {
          return t('ضع ___ في الجملة مكان الإجابة', 'Put ___ in the sentence where the answer goes');
        }
      case 'classify':
        if (categories.length < 2 || categories.any((c) => c.labelAr.trim().isEmpty)) {
          return t('اكتب اسمين للأقسام على الأقل', 'Name at least two categories');
        }
        if (items.isEmpty || items.any((i) => i.text.trim().isEmpty)) return t('اكتب كل الكلمات المطلوب تصنيفها', 'Write every word to sort');
        final keys = {for (final c in categories) c.key};
        if (items.any((i) => i.category == null || !keys.contains(i.category))) {
          return t('اختر القسم الصحيح لكل كلمة', 'Choose the right category for every word');
        }
    }
    return null;
  }

  /// The body of POST …/exercises and PUT /exercises/{id}.
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{...extraData, if (promptEn.trim().isNotEmpty) 'prompt_en': promptEn.trim()};
    Map<String, dynamic> answer = {};
    switch (kind) {
      case 'choose':
        data['options'] = _cleanOptions;
        answer = {'index': answerIndex};
      case 'fill':
        final o = _cleanOptions;
        if (text.trim().isNotEmpty) data['text'] = text.trim();
        data['options'] = o;
        answer = {'text': answerIndex != null && answerIndex! >= 0 && answerIndex! < o.length ? o[answerIndex!] : ''};
      case 'classify':
        data['categories'] = [
          for (final c in categories)
            {'key': c.key, 'label_ar': c.labelAr.trim(), 'label_en': c.labelEn.trim()},
        ];
        data['items'] = [for (final i in items) {'text': i.text.trim()}];
        answer = {'items': [for (final i in items) i.category ?? '']};
    }
    return {
      'kind': kind,
      'prompt': prompt.trim(),
      'data': data,
      'answer': answer,
      'explanation': explanation.trim(),
      'sort': sort,
    };
  }

  /// What the preview draws (the student's own widget, so the admin sees exactly what the student will).
  NahwExercise toExercise() => NahwExercise.from({...toJson(), 'id': id ?? 0});
}
