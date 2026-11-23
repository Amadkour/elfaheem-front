// lib/features/games/admin/v4/editors/item_editor.dart — one item, edited (Games v4 T65, CONTRACT §3, §10).
//
//   ItemEditorPage   loads / saves through ItemsV4Api; the preview re-checks the draft on the server (debounced)
//   ItemEditorForm   the whole form over plain values: the common fields, ONE editor per item type, the sacred-text
//                    picker row and the live preview card (test/games/v4_admin_test.dart)
//   defaultItem(type, subject)   a valid-looking blank item of a type
//   ItemTypeEditor   the dispatch to choice_editors / sequence_editor / group_editors / math_editors
//
// Sacred text (a subject marked `sacred`, source kind quran / hadith) is never typed: a sequence item's tokens are a
// reference filled by the Quran / Hadith picker, and the form shows it read-only. Save as draft sends status `draft`;
// Save sends `approved` (the server turns it into `pending_review` where the subject needs review).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/choice_editors.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/group_editors.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/item_preview.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/math_editors.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/sequence_editor.dart';
import 'package:flutter_education_app/features/games/admin/v4/hadith_picker.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/quran_picker.dart';

Json defaultBody(String type) => switch (type) {
      'mcq' => {'options': [{'text': ''}, {'text': ''}], 'answer': 0},
      'true_false' => {'answer': true},
      'select_all' => {'options': [{'text': ''}, {'text': ''}, {'text': ''}], 'answers': [0]},
      'sequence' => {'mode': 'order', 'unit': 'word', 'tokens': ['', ''], 'distractors': 0},
      'classify' => {
          'buckets': [{'key': 'g1', 'label': {'ar': '', 'en': ''}}, {'key': 'g2', 'label': {'ar': '', 'en': ''}}],
          'tokens': [{'text': '', 'bucket': 'g1'}, {'text': '', 'bucket': 'g2'}],
        },
      'pair' => {'pairs': [{'a': '', 'b': ''}, {'a': '', 'b': ''}]},
      'fraction' => {'shape': 'pizza', 'n': 1, 'd': 4},
      'program' => {'w': 5, 'h': 5, 'start': [0, 0, 1], 'goal': [4, 4], 'walls': <List<int>>[], 'cmds': ['F', 'L', 'R'], 'max': 10, 'par': 8},
      'combine' => {
          'ingredients': [for (final i in [1, 2, 3]) {'key': 'i$i', 'label': {'ar': '', 'en': ''}}],
          'answer': ['i1', 'i2'],
          'fx': 'fizz',
        },
      _ => <String, dynamic>{},
    };

Json defaultItem(String type, {int? subjectId}) => {
      'subject_id': subjectId,
      'topic': '',
      'type': type,
      'difficulty': 1,
      'age_min': 6,
      'age_max': 30,
      'lang': 'ar',
      'status': 'draft',
      'prompt': {'ar': null, 'en': null},
      'media': {'image': null, 'audio': null},
      'body': defaultBody(type),
      'explain': {'ar': null, 'en': null},
      'source': {'kind': 'curated', 'ref': null, 'note': null},
      'tags': <String>[],
    };

class ItemTypeEditor extends StatelessWidget {
  const ItemTypeEditor({super.key, required this.type, required this.body, required this.onChanged, this.sacredKind, this.onPick});
  final String type;
  final Json body;
  final ValueChanged<Json> onChanged;
  final String? sacredKind;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => switch (type) {
        'mcq' => McqEditor(body: body, onChanged: onChanged),
        'true_false' => TrueFalseEditor(body: body, onChanged: onChanged),
        'select_all' => SelectAllEditor(body: body, onChanged: onChanged),
        'sequence' => SequenceEditor(body: body, onChanged: onChanged, sacredKind: sacredKind, onPick: onPick),
        'classify' => ClassifyEditor(body: body, onChanged: onChanged),
        'pair' => PairEditor(body: body, onChanged: onChanged),
        'fraction' => FractionEditor(body: body, onChanged: onChanged),
        'program' => ProgramEditor(body: body, onChanged: onChanged),
        'combine' => CombineEditor(body: body, onChanged: onChanged),
        _ => const SizedBox.shrink(),
      };
}

/// The form. [item] is the draft; every change calls [onChanged] with a whole new map.
class ItemEditorForm extends StatelessWidget {
  const ItemEditorForm({
    super.key,
    required this.item,
    required this.subjects,
    required this.onChanged,
    required this.onPickQuran,
    required this.onPickHadith,
    this.resolved,
    this.checkError,
    this.checking = false,
    this.lockType = false,
  });

  final Json item;
  final List<Json> subjects;
  final ValueChanged<Json> onChanged;
  final VoidCallback onPickQuran;
  final VoidCallback onPickHadith;
  final Json? resolved;
  final String? checkError;
  final bool checking;

  /// A saved item keeps its type: its body would not fit another one.
  final bool lockType;

  Json get _src => jmap(item['source']);

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    final type = '${item['type']}';
    final subject = subjects.cast<Json?>().firstWhere((s) => s!['id'] == item['subject_id'], orElse: () => null);
    final sacredSubject = subject?['sacred'] == true;
    final kind = '${_src['kind'] ?? 'curated'}';
    final sacredKind = sacredSubject && (kind == 'quran' || kind == 'hadith') ? kind : null;
    void set(String k, Object? v) => onChanged({...item, k: v});

    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdSelect<int>(
        label: t('المادة', 'Subject'),
        value: subjects.any((s) => s['id'] == item['subject_id']) ? jint(item['subject_id']) : null,
        options: [for (final s in subjects) (jint(s['id']), '${ar ? s['name_ar'] : s['name_en']}')],
        onChanged: (v) {
          final s = subjects.firstWhere((x) => x['id'] == v);
          onChanged({
            ...item,
            'subject_id': v,
            'source': s['sacred'] == true
                ? {...jmap(item['source']), 'kind': '${s['key']}' == 'hadith' ? 'hadith' : 'quran'}
                : {'kind': 'curated', 'ref': null, 'note': null},
          });
        },
      ),
      AppSpace.gapSm,
      EdSelect<String>(
        label: t('نوع السؤال', 'Question type'),
        value: type,
        options: [for (final k in kItemTypes) (k, itemTypeName(k))],
        onChanged: lockType
            ? (_) {}
            : (v) => onChanged({...item, 'type': v, 'body': defaultBody(v)}),
      ),
      AppSpace.gapSm,
      EdText(label: t('الموضوع', 'Topic'), value: '${item['topic'] ?? ''}', hint: t('مثل: الجمع والطرح', 'Like: adding and taking away'), onChanged: (v) => set('topic', v)),
      AppSpace.gapSm,
      EdBilingual(label: t('نص السؤال', 'The question'), value: jmap(item['prompt']), onChanged: (v) => set('prompt', v)),
      if (sacredSubject) ...[
        AppSpace.gapSm,
        EdSelect<String>(
          label: t('مصدر النص', 'Text source'),
          value: kind == 'hadith' ? 'hadith' : 'quran',
          options: [('quran', t('القرآن', 'Quran')), ('hadith', t('الحديث', 'Hadith'))],
          onChanged: (v) => onChanged({...item, 'source': {..._src, 'kind': v, 'ref': null}}),
        ),
      ],
      AppSpace.gapSm,
      ItemTypeEditor(
        type: type,
        body: jmap(item['body']),
        sacredKind: sacredKind,
        onPick: sacredKind == 'hadith' ? onPickHadith : onPickQuran,
        onChanged: (b) => set('body', b),
      ),
      EdTitle(t('تفاصيل', 'Details')),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: EdSelect<int>(
            label: t('الصعوبة', 'Difficulty'),
            value: jint(item['difficulty'], 1).clamp(1, 5),
            options: [for (var i = 1; i <= 5; i++) (i, '$i')],
            onChanged: (v) => set('difficulty', v),
          ),
        ),
        AppSpace.gapSm,
        Expanded(
          child: EdSelect<String>(
            label: t('اللغة', 'Language'),
            value: '${item['lang'] ?? 'ar'}',
            options: [('ar', t('عربي', 'Arabic')), ('en', t('إنجليزي', 'English')), ('both', t('الاثنتان', 'Both'))],
            onChanged: (v) => set('lang', v),
          ),
        ),
      ]),
      AppSpace.gapSm,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: AppNumberField(label: t('أصغر عمر', 'Youngest age'), initialValue: jint(item['age_min'], 6), min: 4, max: 99, onChanged: (v) => set('age_min', v?.toInt() ?? 6))),
        AppSpace.gapSm,
        Expanded(child: AppNumberField(label: t('أكبر عمر', 'Oldest age'), initialValue: jint(item['age_max'], 30), min: 4, max: 99, onChanged: (v) => set('age_max', v?.toInt() ?? 30))),
      ]),
      AppSpace.gapSm,
      EdBilingual(label: t('شرح الإجابة (اختياري)', 'Explanation (optional)'), value: jmap(item['explain']), onChanged: (v) => set('explain', v)),
    ]);

    final preview = ItemPreviewCard(item: item, resolved: resolved, error: checkError, checking: checking);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: form),
          AppSpace.gapMd,
          Expanded(flex: 2, child: preview),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, AppSpace.gapMd, form]);
    });
  }
}

class ItemEditorPage extends StatefulWidget {
  const ItemEditorPage({super.key, this.itemId, this.initialType = 'mcq', this.api});
  final int? itemId;
  final String initialType;
  final ItemsV4Api? api;

  @override
  State<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _ItemEditorPageState extends State<ItemEditorPage> {
  late final ItemsV4Api _api = widget.api ?? ItemsV4Api();
  Json? _item;
  List<Json> _subjects = [];
  Json? _resolved;
  String? _checkError;
  String? _loadError;
  bool _checking = false;
  bool _saving = false;
  bool _dirty = false;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final subs = await _api.subjects();
      final item = widget.itemId == null
          ? defaultItem(widget.initialType, subjectId: subs.isEmpty ? null : jint(subs.first['id']))
          : await _api.item(widget.itemId!);
      if (!mounted) return;
      setState(() { _subjects = subs; _item = item; _resolved = item['resolved'] is Map ? jmap(item['resolved']) : null; });
    } catch (e) {
      if (mounted) setState(() => _loadError = itemErrorText(e));
    }
  }

  Json _payload([String? status]) {
    final i = {..._item!}..remove('resolved');
    for (final k in ['id', 'rev', 'subject', 'seed_key', 'edited_by_admin', 'reviewed_by', 'reviewed_at', 'review_note', 'created_at', 'updated_at']) {
      i.remove(k);
    }
    if (status != null) i['status'] = status;
    return i;
  }

  void _changed(Json next) {
    setState(() {
      _item = next;
      _dirty = true;
      _checking = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _check);
  }

  Future<void> _check() async {
    final seq = ++_seq;
    try {
      final r = await _api.check(_payload());
      if (mounted && seq == _seq) setState(() { _resolved = r; _checkError = null; _checking = false; });
    } catch (e) {
      if (mounted && seq == _seq) setState(() { _checkError = itemErrorText(e); _checking = false; });
    }
  }

  Future<void> _pickQuran() async {
    final p = await showQuranPicker(context, api: _api);
    if (p == null || !mounted) return;
    final body = jmap(_item!['body']);
    _changed({
      ..._item!,
      'body': {...body, 'tokens': p.tokens, if (p.to != p.from) 'unit': 'ayah'},
      'source': {...jmap(_item!['source']), 'kind': 'quran', 'ref': p.sourceRef},
      'media': {...jmap(_item!['media']), 'audio': {'kind': 'quran'}},
      'topic': '${_item!['topic']}'.isEmpty ? p.label : _item!['topic'],
    });
  }

  Future<void> _pickHadith() async {
    final p = await showHadithPicker(context, api: _api);
    if (p == null || !mounted) return;
    _changed({
      ..._item!,
      'body': {...jmap(_item!['body']), 'tokens': p.tokens},
      'source': {...jmap(_item!['source']), 'kind': 'hadith', 'ref': p.sourceRef},
      'topic': '${_item!['topic']}'.isEmpty ? p.label : _item!['topic'],
    });
  }

  Future<void> _save(String status) async {
    setState(() => _saving = true);
    try {
      final body = _payload(status);
      final saved = widget.itemId == null ? await _api.create(body) : await _api.update(widget.itemId!, body);
      if (!mounted) return;
      showAppNotice(status == 'draft' ? t('حُفظت المسودة', 'Draft saved') : t('حُفظ السؤال', 'Question saved'));
      _dirty = false;
      Navigator.of(context).pop(saved);
    } catch (e) {
      showAppNotice(itemErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: widget.itemId == null ? t('سؤال جديد', 'New question') : t('تعديل السؤال', 'Edit the question'),
        icon: Icons.quiz_rounded,
        dirty: _dirty,
        primaryAction: _item == null ? null : AppButton.primary(label: t('حفظ', 'Save'), busy: _saving, onPressed: () => _save('approved')),
        actions: [
          if (_item != null) AppButton.secondary(label: t('حفظ كمسودة', 'Save as draft'), onPressed: _saving ? null : () => _save('draft')),
        ],
        body: _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : _item == null
                ? const AppListSkeleton(items: 4)
                : ListView(
                    padding: AdminPage.bodyPadding(context),
                    children: [
                      ItemEditorForm(
                        item: _item!,
                        subjects: _subjects,
                        resolved: _resolved,
                        checkError: _checkError,
                        checking: _checking,
                        lockType: widget.itemId != null,
                        onChanged: _changed,
                        onPickQuran: _pickQuran,
                        onPickHadith: _pickHadith,
                      ),
                    ],
                  ),
      );
}
