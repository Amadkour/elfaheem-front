// lib/features/games/admin/v4/bank_page.dart — the Content bank (Games v4 T65, CONTRACT §3, §10).
//
//   BankPage   GET /api/v1/admin/games/v4/items with the filters below, 50 at a time; tap a row to edit it, tick
//              rows for a bulk change (POST …/items/bulk: status, difficulty, topic, ages, or delete), "New" opens
//              the editor of a chosen type
//   BankBody   the list over plain values (test/games/v4_admin_test.dart)
//
// Filters: subject, topic, type, status, difficulty (all server side), age (client side: the server has no age
// filter, so it narrows the page already loaded), and a search of the question text. Deleting asks first; a seeded
// item is remembered as deleted by the server so a re-seed never restores it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/item_editor.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';

/// The bank's filters; null = any.
class BankFilters {
  const BankFilters({this.subjectId, this.topic = '', this.type, this.status, this.difficulty, this.age, this.q = ''});
  final int? subjectId;
  final String topic;
  final String? type;
  final String? status;
  final int? difficulty;
  final int? age;
  final String q;

  BankFilters copy({Object? subjectId = _keep, String? topic, Object? type = _keep, Object? status = _keep, Object? difficulty = _keep, Object? age = _keep, String? q}) =>
      BankFilters(
        subjectId: identical(subjectId, _keep) ? this.subjectId : subjectId as int?,
        topic: topic ?? this.topic,
        type: identical(type, _keep) ? this.type : type as String?,
        status: identical(status, _keep) ? this.status : status as String?,
        difficulty: identical(difficulty, _keep) ? this.difficulty : difficulty as int?,
        age: identical(age, _keep) ? this.age : age as int?,
        q: q ?? this.q,
      );

  bool get any => subjectId != null || topic.isNotEmpty || type != null || status != null || difficulty != null || age != null || q.isNotEmpty;
}

const Object _keep = Object();

String itemPromptText(Json item) {
  final p = jmap(item['prompt']);
  final first = AppConfig.lang == 'ar' ? p['ar'] : p['en'];
  final s = '${first ?? p['ar'] ?? p['en'] ?? ''}';
  return s.isEmpty ? t('(بلا نص)', '(no text)') : s;
}

class BankPage extends StatefulWidget {
  const BankPage({super.key, this.api});
  final ItemsV4Api? api;

  @override
  State<BankPage> createState() => _BankPageState();
}

class _BankPageState extends State<BankPage> {
  late final ItemsV4Api _api = widget.api ?? ItemsV4Api();
  BankFilters _f = const BankFilters();
  List<Json> _subjects = [];
  List<Json> _items = [];
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final Set<int> _sel = {};
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _api.subjects().then((s) {
      if (mounted) setState(() => _subjects = s);
    }, onError: (_) {});
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final seq = ++_seq;
    if (!more) setState(() { _loading = true; _error = null; });
    try {
      final p = await _api.items(
          subjectId: _f.subjectId, topic: _f.topic, type: _f.type, status: _f.status, difficulty: _f.difficulty, q: _f.q, skip: more ? _items.length : 0);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = more ? [..._items, ...p.items] : p.items;
        _total = p.total;
        _hasMore = p.hasMore;
        _loading = false;
        if (!more) _sel.clear();
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() { _loading = false; _error = itemErrorText(e); });
    }
  }

  void _filter(BankFilters f) {
    _f = f;
    _load();
  }

  Future<void> _openEditor([Json? item]) async {
    String? type = item == null ? await _pickType() : null;
    if (item == null && type == null) return;
    if (!mounted) return;
    final saved = await Navigator.of(context).push<Json>(
      MaterialPageRoute(builder: (_) => ItemEditorPage(itemId: item == null ? null : jint(item['id']), initialType: type ?? 'mcq', api: _api)),
    );
    if (saved != null) _load();
  }

  Future<String?> _pickType() => showAppSheet<String>(
        context,
        (ctx) => AppSheetContent(title: t('نوع السؤال', 'Question type'), children: [
          for (final k in kItemTypes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppButton.secondary(label: itemTypeName(k), expand: true, onPressed: () => Navigator.of(ctx).pop(k)),
            ),
        ]),
      );

  Future<void> _delete(Json item) async {
    if (!await appConfirm(context, message: t('حذف هذا السؤال؟', 'Delete this question?'), danger: true, confirmLabel: t('حذف', 'Delete'))) return;
    try {
      await _api.delete(jint(item['id']));
      if (mounted) setState(() { _items = [for (final x in _items) if (x['id'] != item['id']) x]; _total -= 1; });
    } catch (e) {
      showAppNotice(itemErrorText(e), error: true);
    }
  }

  Future<void> _bulk(Json? set, {bool delete = false}) async {
    if (delete && !await appConfirm(context, message: t('حذف ${_sel.length} سؤالاً؟', 'Delete ${_sel.length} questions?'), danger: true, confirmLabel: t('حذف', 'Delete'))) return;
    setState(() => _busy = true);
    try {
      final r = await _api.bulk(_sel.toList(), set: set, delete: delete);
      final skipped = r['skipped'] is List ? (r['skipped'] as List).length : 0;
      showAppNotice(skipped == 0 ? t('تم تعديل ${r['changed']}', '${r['changed']} changed') : t('تم تعديل ${r['changed']} وتخطّي $skipped', '${r['changed']} changed, $skipped skipped'), error: skipped > 0 && jint(r['changed']) == 0);
      await _load();
    } catch (e) {
      showAppNotice(itemErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bulkSheet() async {
    final set = await showAppSheet<Json>(context, (_) => const BulkEditSheet());
    if (set != null) _bulk(set);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _f.age == null ? _items : [for (final x in _items) if (jint(x['age_min'], 4) <= _f.age! && _f.age! <= jint(x['age_max'], 99)) x];
    return AdminPage(
      title: t('بنك الأسئلة', 'Question bank'),
      subtitle: t('$_total سؤالاً', '$_total questions'),
      icon: Icons.quiz_rounded,
      onRefresh: _load,
      primaryAction: AppButton.primary(label: t('سؤال جديد', 'New question'), icon: Icons.add_rounded, onPressed: _openEditor),
      body: BankBody(
        items: shown,
        subjects: _subjects,
        filters: _f,
        selected: _sel,
        loading: _loading,
        busy: _busy,
        error: _error,
        hasMore: _hasMore,
        onFilters: _filter,
        onToggle: (id) => setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id)),
        onSelectAll: (all) => setState(() => all ? _sel.addAll(shown.map((x) => jint(x['id']))) : _sel.clear()),
        onOpen: _openEditor,
        onDelete: _delete,
        onBulkEdit: _bulkSheet,
        onBulkDelete: () => _bulk(null, delete: true),
        onMore: () => _load(more: true),
        onRetry: _load,
      ),
    );
  }
}

class BankBody extends StatelessWidget {
  const BankBody({
    super.key,
    required this.items,
    required this.subjects,
    required this.filters,
    required this.selected,
    required this.onFilters,
    required this.onToggle,
    required this.onSelectAll,
    required this.onOpen,
    required this.onDelete,
    required this.onBulkEdit,
    required this.onBulkDelete,
    this.onMore,
    this.onRetry,
    this.loading = false,
    this.busy = false,
    this.hasMore = false,
    this.error,
  });

  final List<Json> items;
  final List<Json> subjects;
  final BankFilters filters;
  final Set<int> selected;
  final bool loading;
  final bool busy;
  final bool hasMore;
  final String? error;
  final ValueChanged<BankFilters> onFilters;
  final ValueChanged<int> onToggle;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<Json> onOpen;
  final ValueChanged<Json> onDelete;
  final VoidCallback onBulkEdit;
  final VoidCallback onBulkDelete;
  final VoidCallback? onMore;
  final VoidCallback? onRetry;

  Widget _cell(BuildContext context, double w, Widget child) => SizedBox(width: w, child: child);

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    return LayoutBuilder(builder: (context, box) {
      final gap = AppSpace.sm;
      final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 560 ? 3 : 2);
      final w = (box.maxWidth - AppSpace.md * 2 - gap * (cols - 1)) / cols;
      final f = filters;
      return ListView(padding: AdminPage.bodyPadding(context), children: [
        AppSearchField(hint: t('ابحث في نص السؤال', 'Search the question text'), onChanged: (v) => onFilters(f.copy(q: v))),
        AppSpace.gapSm,
        Wrap(spacing: gap, runSpacing: gap, children: [
          _cell(context, w, EdSelect<int>(
            label: t('المادة', 'Subject'),
            value: f.subjectId ?? -1,
            options: [(-1, t('الكل', 'All')), for (final s in subjects) (jint(s['id']), '${ar ? s['name_ar'] : s['name_en']}')],
            onChanged: (v) => onFilters(f.copy(subjectId: v < 0 ? null : v)),
          )),
          _cell(context, w, EdSelect<String>(
            label: t('النوع', 'Type'),
            value: f.type ?? '',
            options: [('', t('الكل', 'All')), for (final k in kItemTypes) (k, itemTypeName(k))],
            onChanged: (v) => onFilters(f.copy(type: v.isEmpty ? null : v)),
          )),
          _cell(context, w, EdSelect<String>(
            label: t('الحالة', 'Status'),
            value: f.status ?? '',
            options: [('', t('الكل', 'All')), for (final k in kItemStatuses) (k, itemStatusName(k))],
            onChanged: (v) => onFilters(f.copy(status: v.isEmpty ? null : v)),
          )),
          _cell(context, w, EdSelect<int>(
            label: t('الصعوبة', 'Difficulty'),
            value: f.difficulty ?? 0,
            options: [(0, t('الكل', 'All')), for (var i = 1; i <= 5; i++) (i, '$i')],
            onChanged: (v) => onFilters(f.copy(difficulty: v == 0 ? null : v)),
          )),
          _cell(context, w, EdSelect<int>(
            label: t('العمر', 'Age'),
            value: f.age ?? 0,
            options: [(0, t('الكل', 'All')), for (final a in [4, 6, 8, 10, 12, 15, 18, 25]) (a, t('$a سنة', 'Age $a'))],
            onChanged: (v) => onFilters(f.copy(age: v == 0 ? null : v)),
          )),
          _cell(context, w, _TopicField(value: f.topic, onChanged: (v) => onFilters(f.copy(topic: v)))),
        ]),
        AppSpace.gapSm,
        if (selected.isNotEmpty)
          AppCard(
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t('${selected.length} محدد', '${selected.length} selected'), style: AppType.bodyStrong(context)),
              AppButton.tonal(label: t('تعديل المحدد', 'Edit selected'), size: AppButtonSize.sm, busy: busy, onPressed: onBulkEdit),
              AppButton.danger(label: t('حذف المحدد', 'Delete selected'), size: AppButtonSize.sm, dangerOutline: true, onPressed: busy ? null : onBulkDelete),
              AppButton.ghost(label: t('إلغاء التحديد', 'Clear'), size: AppButtonSize.sm, onPressed: () => onSelectAll(false)),
            ]),
          )
        else if (items.isNotEmpty)
          Align(alignment: AlignmentDirectional.centerStart, child: AppButton.ghost(label: t('تحديد الكل', 'Select all shown'), size: AppButtonSize.sm, onPressed: () => onSelectAll(true))),
        AppSpace.gapSm,
        if (error != null)
          AppErrorState(message: error!, onRetry: onRetry)
        else if (loading)
          const AppListSkeleton(items: 5)
        else if (items.isEmpty)
          AppEmpty(
            icon: Icons.quiz_rounded,
            title: f.any ? t('لا أسئلة بهذه المرشحات', 'No questions match these filters') : t('البنك فارغ', 'The bank is empty'),
            message: f.any ? t('غيّر المرشحات أو امسحها.', 'Change or clear the filters.') : t('أضف سؤالاً أو شغّل التعبئة من صفحة البذور.', 'Add a question or run the seed.'),
            actionLabel: f.any ? t('مسح المرشحات', 'Clear filters') : null,
            onAction: f.any ? () => onFilters(const BankFilters()) : null,
          )
        else ...[
          for (final x in items)
            Padding(
              key: ValueKey('item${x['id']}'),
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: BankRow(item: x, selected: selected.contains(jint(x['id'])), subjects: subjects, onToggle: () => onToggle(jint(x['id'])), onOpen: () => onOpen(x), onDelete: () => onDelete(x)),
            ),
          if (hasMore) Center(child: AppButton.secondary(label: t('عرض المزيد', 'Show more'), onPressed: onMore)),
        ],
      ]);
    });
  }
}

class _TopicField extends StatelessWidget {
  const _TopicField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => EdText(label: t('الموضوع', 'Topic'), value: value, onChanged: onChanged);
}

class BankRow extends StatelessWidget {
  const BankRow({super.key, required this.item, required this.selected, required this.subjects, required this.onToggle, required this.onOpen, required this.onDelete});
  final Json item;
  final bool selected;
  final List<Json> subjects;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  AppTone _tone(String s) => switch (s) {
        'approved' => AppTone.success,
        'rejected' => AppTone.danger,
        'pending_review' => AppTone.warning,
        _ => AppTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    final status = '${item['status'] ?? 'draft'}';
    final subject = subjects.cast<Json?>().firstWhere((s) => s!['id'] == item['subject_id'], orElse: () => null);
    final topic = '${item['topic'] ?? ''}';
    return AppCard(
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppRadius.cardAll,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(value: selected, onChanged: (_) => onToggle()),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(itemPromptText(item), style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppStatusBadge(label: itemTypeName('${item['type']}'), tone: AppTone.info, dense: true),
                AppStatusBadge(label: itemStatusName(status), tone: _tone(status), dense: true),
                AppStatusBadge(label: t('صعوبة ${item['difficulty']}', 'Level ${item['difficulty']}'), dense: true),
                if (subject != null) AppStatusBadge(label: '${ar ? subject['name_ar'] : subject['name_en']}', tone: AppTone.brand, dense: true),
              ]),
              if (topic.isNotEmpty) Text(topic, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          AppIconButton(icon: Icons.delete_outline_rounded, tooltip: t('حذف', 'Delete'), onPressed: onDelete),
        ]),
      ),
    );
  }
}

/// What a bulk change can set (CONTRACT §10: topic, difficulty, ages, status); only filled fields are sent.
class BulkEditSheet extends StatefulWidget {
  const BulkEditSheet({super.key});

  @override
  State<BulkEditSheet> createState() => _BulkEditSheetState();
}

class _BulkEditSheetState extends State<BulkEditSheet> {
  String _status = '';
  int _difficulty = 0;
  String _topic = '';
  int? _min;
  int? _max;

  @override
  Widget build(BuildContext context) => AppSheetContent(title: t('تعديل جماعي', 'Change many at once'), children: [
        Text(t('يُغيَّر ما تملؤه فقط.', 'Only what you fill in changes.'), style: AppType.meta(context)),
        AppSpace.gapSm,
        EdSelect<String>(
          label: t('الحالة', 'Status'),
          value: _status,
          options: [('', t('بلا تغيير', 'No change')), ('draft', itemStatusName('draft')), ('approved', itemStatusName('approved')), ('rejected', itemStatusName('rejected'))],
          onChanged: (v) => setState(() => _status = v),
        ),
        AppSpace.gapSm,
        EdSelect<int>(
          label: t('الصعوبة', 'Difficulty'),
          value: _difficulty,
          options: [(0, t('بلا تغيير', 'No change')), for (var i = 1; i <= 5; i++) (i, '$i')],
          onChanged: (v) => setState(() => _difficulty = v),
        ),
        AppSpace.gapSm,
        EdText(label: t('الموضوع', 'Topic'), value: _topic, onChanged: (v) => _topic = v),
        AppSpace.gapSm,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: AppNumberField(label: t('أصغر عمر', 'Youngest age'), min: 4, max: 99, onChanged: (v) => _min = v?.toInt())),
          AppSpace.gapSm,
          Expanded(child: AppNumberField(label: t('أكبر عمر', 'Oldest age'), min: 4, max: 99, onChanged: (v) => _max = v?.toInt())),
        ]),
        AppSpace.gapMd,
        AppButton.primary(
          label: t('تطبيق', 'Apply'),
          expand: true,
          onPressed: () {
            final set = <String, dynamic>{
              if (_status.isNotEmpty) 'status': _status,
              if (_difficulty > 0) 'difficulty': _difficulty,
              if (_topic.trim().isNotEmpty) 'topic': _topic.trim(),
              if (_min != null) 'age_min': _min,
              if (_max != null) 'age_max': _max,
            };
            if (set.isEmpty) {
              showAppNotice(t('لم تملأ شيئاً', 'Nothing filled in'), error: true);
              return;
            }
            Navigator.of(context).pop(set);
          },
        ),
      ]);
}
