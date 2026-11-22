// lib/features/self_learning/admin/sl_admin_page.dart — ADMIN: the self-learning content (Learning Hub v2 §5,
// D-1607..D-1609), kill switch `admin.self_learning`, opened from the services hub next to the grammar content and
// from the module switches' self-learning card.
//
//   SlAdminPage        filters (subject, kind), the items of one page in their delivery order (drag to reorder:
//                      POST …/items/reorder with that page's ids), pagination, Add, Edit, Publish / Unpublish, Delete
//   SlAdminListBody    the list over plain values (test/ui/self_learning_test.dart)
//   SlItemForm         one lesson or question: subject, category, title, body; a question's options with the right
//                      one marked, its explanation and the lesson it reviews; an optional source nahw lesson; published
//   slItemProblem()    what is still missing (Save stays off until it is null) — the server's own rules
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart' show learnOptionLetter;
import 'package:flutter_education_app/features/nahw/admin/nahw_admin_api.dart' show NahwAdminApi;

import '../sl_api.dart';
import '../sl_models.dart';

const int kSlAdminPageSize = 20;
const int kSlMaxOptions = 6;

String slKindLabel(String k) => k == 'question' ? t('سؤال مراجعة', 'Review question') : t('درس', 'Lesson');

/// What is still missing in [item] (null = it can be saved).
String? slItemProblem(SlItem item) {
  if (!kSlSubjects.contains(item.subject)) return t('اختر المادة', 'Pick the subject');
  if (item.title.trim().isEmpty) return t('اكتب العنوان', 'Write the title');
  if (item.isLesson && item.body.trim().isEmpty) return t('اكتب نص الدرس', 'Write the lesson text');
  if (item.isQuestion) {
    final q = item.question;
    if (q == null || q.prompt.trim().isEmpty) return t('اكتب السؤال', 'Write the question');
    final filled = q.options.where((o) => o.trim().isNotEmpty).length;
    if (filled < 2 || filled != q.options.length) return t('اكتب خيارين على الأقل، ولا تترك خياراً فارغاً', 'Write at least two options, none left empty');
    if (q.answer < 0 || q.answer >= q.options.length) return t('حدّد الإجابة الصحيحة', 'Mark the right answer');
  }
  return null;
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class SlAdminPage extends StatefulWidget {
  const SlAdminPage({super.key, this.api, this.nahwApi});

  final SlApi? api;
  final NahwAdminApi? nahwApi;

  @override
  State<SlAdminPage> createState() => _SlAdminPageState();
}

class _SlAdminPageState extends State<SlAdminPage> {
  late final SlApi _api = widget.api ?? SlApi();
  late final NahwAdminApi _nahw = widget.nahwApi ?? NahwAdminApi();

  String? _subject;
  String? _kind;
  int _page = 1;
  SlItemPage? _data;
  String? _error;
  DateTime? _loadedAt;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final d = await _api.items(subject: _subject, kind: _kind, page: _page, size: kSlAdminPageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = d;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = slErrorText(e));
    }
  }

  void _filter({String? subject, String? kind, bool subjectSet = false, bool kindSet = false}) {
    setState(() {
      if (subjectSet) _subject = subject;
      if (kindSet) _kind = kind;
      _page = 1;
      _data = null;
    });
    _load();
  }

  Future<List<SlItem>> _lessonsOf(String subject) async =>
      (await _api.items(subject: subject, kind: 'lesson', size: 100)).items;

  Future<List<(int, String)>> _nahwLessons() async => [
        for (final l in await _nahw.levels())
          for (final s in l.lessons) (s.id, '${l.title} · ${s.title}'),
      ];

  Future<void> _edit([SlItem? item]) async {
    await showAppSheet<void>(
      context,
      (ctx) => SlItemForm(
        initial: item,
        subject: _subject,
        kind: _kind,
        lessonsOf: _lessonsOf,
        nahwLessons: _nahwLessons,
        onSave: (body) async {
          try {
            if (item == null) {
              await _api.create(body);
            } else {
              await _api.save(item.id, body);
            }
          } catch (e) {
            return slErrorText(e);
          }
          showAppNotice(item == null ? t('أُضيف العنصر', 'Item added') : t('حُفظ العنصر', 'Item saved'));
          _load();
          return null;
        },
      ),
    );
  }

  Future<void> _publish(SlItem item, bool on) async {
    final body = SlItem(
      id: item.id,
      subject: item.subject,
      kind: item.kind,
      category: item.category,
      title: item.title,
      body: item.body,
      lessonId: item.lessonId,
      question: item.question,
      source: item.source,
      sort: item.sort,
      published: on,
    ).toJson();
    try {
      await _api.save(item.id, body);
      showAppNotice(on ? t('نُشر للطلاب', 'Published to students') : t('أُخفي عن الطلاب', 'Hidden from students'));
      _load();
    } catch (e) {
      showAppNotice(slErrorText(e), error: true);
    }
  }

  Future<void> _delete(SlItem item) async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف «${item.title}»؟ يختفي من مراجعات الطلاب أيضاً.', 'Delete "${item.title}"? It leaves the students\' reviews too.'));
    if (!ok) return;
    try {
      await _api.delete(item.id);
      showAppNotice(t('حُذف العنصر', 'Item deleted'));
      _load();
    } catch (e) {
      showAppNotice(slErrorText(e), error: true);
    }
  }

  Future<void> _reorder(int from, int to) async {
    final d = _data;
    if (d == null) return;
    final list = [...d.items];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    setState(() => _data = SlItemPage(items: list, total: d.total, page: d.page, size: d.size));
    try {
      await _api.reorder([for (final i in list) i.id]);
    } catch (e) {
      showAppNotice(slErrorText(e), error: true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.content,
      title: t('محتوى التعلّم الذاتي', 'Self-learning content'),
      subtitle: t('الدروس القصيرة وأسئلة المراجعة التي تصل الطلاب كل يوم.', 'The short lessons and review questions students get every day.'),
      icon: Icons.auto_stories_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      primaryAction: AppButton.primary(
        key: const ValueKey('sl.admin.add'),
        label: t('إضافة', 'Add'),
        icon: Icons.add_rounded,
        onPressed: () => _edit(),
      ),
      body: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: AdminPage.bodyPadding(context), children: [
          SlAdminListBody(
            data: _data,
            error: _error,
            subject: _subject,
            kind: _kind,
            onSubject: (s) => _filter(subject: s, subjectSet: true),
            onKind: (k) => _filter(kind: k, kindSet: true),
            onRetry: _load,
            onEdit: _edit,
            onPublish: _publish,
            onDelete: _delete,
            onReorder: _reorder,
            onPage: (p) {
              setState(() => _page = p);
              _load();
            },
          ),
        ]),
      ),
    );
  }
}

/// The filters, the list and the pager over plain values.
class SlAdminListBody extends StatelessWidget {
  const SlAdminListBody({
    super.key,
    required this.data,
    this.error,
    this.subject,
    this.kind,
    this.onSubject,
    this.onKind,
    this.onRetry,
    this.onEdit,
    this.onPublish,
    this.onDelete,
    this.onReorder,
    this.onPage,
  });

  /// null = loading.
  final SlItemPage? data;
  final String? error;
  final String? subject;
  final String? kind;
  final ValueChanged<String?>? onSubject;
  final ValueChanged<String?>? onKind;
  final VoidCallback? onRetry;
  final ValueChanged<SlItem>? onEdit;
  final void Function(SlItem item, bool on)? onPublish;
  final ValueChanged<SlItem>? onDelete;
  /// [to] is the index after the item was taken out (onReorderItem).
  final void Function(int from, int to)? onReorder;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final filters = AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDropdown<String?>(
          key: const ValueKey('sl.admin.subject'),
          value: subject,
          decoration: InputDecoration(labelText: t('المادة', 'Subject')),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(t('كل المواد', 'Every subject'))),
            for (final s in kSlSubjects) DropdownMenuItem<String?>(value: s, child: Text(slSubjectLabel(s))),
          ],
          onChanged: (v) => onSubject?.call(v),
        ),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in const [null, 'lesson', 'question'])
            AppChoiceChip(
              key: ValueKey('sl.admin.kind.${k ?? 'all'}'),
              label: k == null ? t('الكل', 'All') : (k == 'lesson' ? t('الدروس', 'Lessons') : t('الأسئلة', 'Questions')),
              selected: kind == k,
              onTap: () => onKind?.call(k),
            ),
        ]),
      ]),
    );
    final d = data;
    final Widget body;
    if (d == null) {
      body = error != null ? AppErrorState(message: error, onRetry: onRetry) : const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (d.items.isEmpty) {
      body = AppEmpty(
        key: const ValueKey('sl.admin.empty'),
        icon: Icons.auto_stories_rounded,
        title: subject == null && kind == null ? t('لا يوجد محتوى بعد', 'No content yet') : t('لا شيء لهذه الاختيارات', 'Nothing for these choices'),
        message: t('أضف درساً قصيراً أو سؤال مراجعة.', 'Add a short lesson or a review question.'),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('اسحب لتغيير ترتيب الوصول', 'Drag to change the delivery order'), style: AppType.meta(context)),
        AppSpace.gapXs,
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: d.items.length,
          onReorderItem: (a, b) => onReorder?.call(a, b),
          itemBuilder: (context, i) => Padding(
            key: ValueKey('sl.admin.item.${d.items[i].id}'),
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: _ItemTile(
              item: d.items[i],
              index: i,
              onEdit: onEdit,
              onPublish: onPublish,
              onDelete: onDelete,
              draggable: onReorder != null,
            ),
          ),
        ),
        if (d.pageCount > 1) ...[
          AppSpace.gapSm,
          AppPagination(page: d.page, pageCount: d.pageCount, total: d.total, pageSize: d.size, onPage: (p) => onPage?.call(p)),
        ],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [filters, AppSpace.gapMd, body]);
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.index, this.onEdit, this.onPublish, this.onDelete, this.draggable = true});

  final SlItem item;
  final int index;
  final ValueChanged<SlItem>? onEdit;
  final void Function(SlItem item, bool on)? onPublish;
  final ValueChanged<SlItem>? onDelete;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preview = item.isQuestion ? (item.question?.prompt ?? '') : item.plainBody;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
      onTap: onEdit == null ? null : () => onEdit!(item),
      child: Row(children: [
        if (draggable)
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: t('اسحب لتغيير الترتيب', 'Drag to reorder'),
              child: SizedBox.square(
                dimension: AppTouch.min,
                child: Icon(Icons.drag_indicator_rounded, size: AppIconSize.md, color: c.textLight),
              ),
            ),
          ),
        Icon(item.isQuestion ? Icons.help_outline_rounded : Icons.auto_stories_rounded, size: AppIconSize.md, color: c.primary),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // what the admin wrote keeps its own direction (an Arabic question in the English interface, S13)
            AutoDirText(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            if (preview.isNotEmpty) AutoDirText(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              AppStatusBadge(label: slSubjectLabel(item.subject), tone: AppTone.brand, dense: true),
              AppStatusBadge(label: slKindLabel(item.kind), tone: AppTone.neutral, dense: true),
              AppStatusBadge(
                label: item.published ? t('منشور', 'Published') : t('مسودة', 'Draft'),
                tone: item.published ? AppTone.success : AppTone.warning,
                dense: true,
              ),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          key: ValueKey('sl.admin.menu.${item.id}'),
          tooltip: t('خيارات', 'Options'),
          onSelected: (v) => switch (v) {
            'edit' => onEdit?.call(item),
            'publish' => onPublish?.call(item, !item.published),
            'delete' => onDelete?.call(item),
            _ => null,
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
            PopupMenuItem(value: 'publish', child: Text(item.published ? t('إخفاء عن الطلاب', 'Unpublish') : t('نشر للطلاب', 'Publish'))),
            PopupMenuItem(value: 'delete', child: Text(t('حذف', 'Delete'))),
          ],
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The form
// ═════════════════════════════════════════════════════════════════════════════

class SlItemForm extends StatefulWidget {
  const SlItemForm({
    super.key,
    this.initial,
    this.subject,
    this.kind,
    required this.onSave,
    this.lessonsOf,
    this.nahwLessons,
  });

  /// Null: a new item (starting on the page's [subject] / [kind] filter).
  final SlItem? initial;
  final String? subject;
  final String? kind;

  /// The body → null when saved (the sheet closes), else the error (it stays open).
  final Future<String?> Function(Map<String, dynamic> body) onSave;

  /// The lessons a question can review (same subject).
  final Future<List<SlItem>> Function(String subject)? lessonsOf;

  /// The nahw lessons an item can be taken from: (id, "level · lesson").
  final Future<List<(int, String)>> Function()? nahwLessons;

  @override
  State<SlItemForm> createState() => _SlItemFormState();
}

class _SlItemFormState extends State<SlItemForm> {
  late final SlItem? _i = widget.initial;
  late String _kind = _i?.kind ?? widget.kind ?? 'lesson';
  late String _subject = _i?.subject ?? widget.subject ?? kSlSubjects.first;
  late final _title = TextEditingController(text: _i?.title ?? '');
  late final _category = TextEditingController(text: _i?.category ?? '');
  late final _body = TextEditingController(text: _i?.body ?? '');
  late final _prompt = TextEditingController(text: _i?.question?.prompt ?? '');
  late final _explanation = TextEditingController(text: _i?.question?.explanation ?? '');
  late final List<TextEditingController> _options = [
    for (final o in (_i?.question?.options ?? const ['', ''])) TextEditingController(text: o),
  ];
  late int _answer = _i?.question?.answer ?? 0;
  late int? _lessonId = _i?.lessonId;
  late int? _nahwLessonId = _i?.source.type == 'nahw_lesson' ? _i?.source.id : null;
  /// A new item starts published (N11): a quick Save gives the students the item; a draft is the deliberate choice.
  late bool _published = _i?.published ?? true;

  List<SlItem>? _lessons;
  String? _lessonsFor;
  List<(int, String)>? _nahw;
  bool _busy = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _body, _prompt, _explanation, ..._options]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLinks() async {
    final subject = _subject;
    if (_kind == 'question' && widget.lessonsOf != null && _lessonsFor != subject) {
      _lessonsFor = subject;
      try {
        final l = await widget.lessonsOf!(subject);
        if (mounted && _lessonsFor == subject) setState(() => _lessons = l);
      } catch (_) {
        if (mounted) setState(() => _lessons = const []);
      }
    }
    if (subject == 'nahw' && _nahw == null && widget.nahwLessons != null) {
      try {
        final n = await widget.nahwLessons!();
        if (mounted) setState(() => _nahw = n);
      } catch (_) {
        if (mounted) setState(() => _nahw = const []);
      }
    }
  }

  SlItem get _draft => SlItem(
        id: _i?.id ?? 0,
        subject: _subject,
        kind: _kind,
        category: _category.text.trim(),
        title: _title.text.trim(),
        body: _body.text.trim(),
        lessonId: _kind == 'question' ? _lessonId : null,
        question: _kind == 'question'
            ? SlQuestion(
                prompt: _prompt.text.trim(),
                options: [for (final o in _options) o.text.trim()],
                answer: _answer,
                explanation: _explanation.text.trim(),
              )
            : null,
        source: _subject == 'nahw' && _nahwLessonId != null ? SlSource(type: 'nahw_lesson', id: _nahwLessonId) : const SlSource(),
        sort: _i?.sort ?? 0,
        published: _published,
      );

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _serverError = null;
    });
    final body = _draft.toJson();
    if (_i == null) body['sort'] = null; // the server puts a new item last in its subject (D-1712)
    final err = await widget.onSave(body);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _busy = false;
        _serverError = err;
      });
    }
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isNew = _i == null;
    final problem = slItemProblem(_draft);
    final lessons = _lessons;
    final nahw = _nahw;
    final fields = <Widget>[
          Text(isNew ? t('عنصر جديد', 'New item') : t('تعديل العنصر', 'Edit item'), style: AppType.section(context)),
          AppSpace.gapMd,
          if (isNew) ...[
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final k in const ['lesson', 'question'])
                AppChoiceChip(
                  key: ValueKey('sl.form.kind.$k'),
                  label: slKindLabel(k),
                  icon: k == 'lesson' ? Icons.auto_stories_rounded : Icons.help_outline_rounded,
                  selected: _kind == k,
                  onTap: () {
                    setState(() => _kind = k);
                    _loadLinks();
                  },
                ),
            ]),
            AppSpace.gapSm,
          ],
          AppDropdown<String>(
            key: const ValueKey('sl.form.subject'),
            value: _subject,
            decoration: InputDecoration(labelText: t('المادة', 'Subject')),
            items: [for (final s in kSlSubjects) DropdownMenuItem(value: s, child: Text(slSubjectLabel(s)))],
            onChanged: (v) {
              if (v == null || v == _subject) return;
              setState(() {
                _subject = v;
                _lessonId = null;
                _lessons = null;
                if (v != 'nahw') _nahwLessonId = null;
              });
              _loadLinks();
            },
          ),
          AppSpace.gapSm,
          AppField(
            controller: _category,
            label: t('التصنيف (اختياري)', 'Category (optional)'),
            hint: t('مثلاً: أحكام النون الساكنة', 'e.g. Rules of the silent noon'),
            maxLength: 80,
            onChanged: (_) => _changed(),
          ),
          AppField(
            key: const ValueKey('sl.form.title'),
            controller: _title,
            label: t('العنوان', 'Title'),
            required: true,
            maxLength: 200,
            onChanged: (_) => _changed(),
          ),
          AppField(
            controller: _body,
            label: _kind == 'lesson' ? t('نص الدرس', 'Lesson text') : t('تمهيد (اختياري)', 'Lead-in (optional)'),
            helper: t('قصير: فقرة أو فقرتان. سطر لكل فقرة، و**نص** للتأكيد.', 'Short: one or two paragraphs. One line per paragraph, **text** for emphasis.'),
            maxLines: 6,
            maxLength: 4000,
            keyboard: TextInputType.multiline,
            onChanged: (_) => _changed(),
          ),
          if (_kind == 'question') ...[
            AppField(
              key: const ValueKey('sl.form.prompt'),
              controller: _prompt,
              label: t('السؤال', 'Question'),
              required: true,
              maxLines: 3,
              maxLength: 500,
              onChanged: (_) => _changed(),
            ),
            Text(t('الخيارات (اضغط الدائرة لتحديد الإجابة الصحيحة)', 'Options (tap the circle to mark the right one)'),
                style: AppType.label(context).copyWith(color: c.textMedium)),
            AppSpace.gapXs,
            for (var i = 0; i < _options.length; i++)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconButton(
                  key: ValueKey('sl.form.right.$i'),
                  tooltip: t('الإجابة الصحيحة', 'The right answer'),
                  isSelected: _answer == i,
                  icon: Icon(Icons.radio_button_unchecked_rounded, color: c.textMedium),
                  selectedIcon: Icon(Icons.check_circle_rounded, color: c.success),
                  onPressed: () => setState(() => _answer = i),
                ),
                Expanded(
                  child: AppField(
                    key: ValueKey('sl.form.option.$i'),
                    controller: _options[i],
                    label: t('الخيار ${learnOptionLetter(i)}', 'Option ${learnOptionLetter(i)}'),
                    maxLength: 200,
                    onChanged: (_) => _changed(),
                  ),
                ),
                if (_options.length > 2)
                  IconButton(
                    tooltip: t('حذف الخيار', 'Remove option'),
                    icon: Icon(Icons.close_rounded, color: c.textMedium),
                    onPressed: () => setState(() {
                      _options.removeAt(i).dispose();
                      if (_answer > i) _answer--;
                      if (_answer >= _options.length) _answer = _options.length - 1;
                    }),
                  ),
              ]),
            if (_options.length < kSlMaxOptions)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.ghost(
                  key: const ValueKey('sl.form.addOption'),
                  label: t('إضافة خيار', 'Add option'),
                  icon: Icons.add_rounded,
                  onPressed: () => setState(() => _options.add(TextEditingController())),
                ),
              ),
            AppSpace.gapSm,
            AppField(
              controller: _explanation,
              label: t('الشرح بعد الإجابة', 'Explanation after the answer'),
              maxLines: 3,
              maxLength: 1000,
              onChanged: (_) => _changed(),
            ),
            if (lessons != null)
              AppDropdown<int?>(
                key: const ValueKey('sl.form.lesson'),
                value: lessons.any((l) => l.id == _lessonId) ? _lessonId : null,
                decoration: InputDecoration(labelText: t('الدرس الذي يراجعه (اختياري)', 'The lesson it reviews (optional)')),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(t('بلا درس', 'No lesson'))),
                  for (final l in lessons) DropdownMenuItem<int?>(value: l.id, child: Text(l.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _lessonId = v),
              ),
            AppSpace.gapSm,
          ],
          if (_subject == 'nahw' && nahw != null && nahw.isNotEmpty) ...[
            AppDropdown<int?>(
              key: const ValueKey('sl.form.nahw'),
              value: nahw.any((n) => n.$1 == _nahwLessonId) ? _nahwLessonId : null,
              decoration: InputDecoration(labelText: t('مأخوذ من درس النحو (اختياري)', 'Taken from the grammar lesson (optional)')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t('بلا مصدر', 'No source'))),
                for (final n in nahw) DropdownMenuItem<int?>(value: n.$1, child: Text(n.$2, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _nahwLessonId = v),
            ),
            AppSpace.gapSm,
          ],
          AppSwitchTile(
            key: const ValueKey('sl.form.published'),
            title: t('منشور للطلاب', 'Published to students'),
            subtitle: t('عند الإيقاف يبقى مسودة لا تصل أحداً.', 'Off: it stays a draft nobody gets.'),
            value: _published,
            onChanged: (v) => setState(() => _published = v),
          ),
    ];
    // the actions stay in view under the scrolling fields (S16): what is missing, the server's error, Cancel / Save
    final footer = <Widget>[
          if (problem != null) ...[Text(problem, style: AppType.meta(context)), AppSpace.gapXs],
          if (_serverError != null) ...[
            Semantics(liveRegion: true, child: Text(_serverError!, style: AppType.body(context).copyWith(color: appInk(context, c.danger)))),
            AppSpace.gapXs,
          ],
          Row(children: [
            Expanded(child: AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).maybePop())),
            AppSpace.gapSm,
            Expanded(
              child: AppButton.primary(
                key: const ValueKey('sl.form.save'),
                label: t('حفظ', 'Save'),
                busy: _busy,
                onPressed: problem == null && !_busy ? _save : null,
              ),
            ),
          ]),
    ];
    const pad = EdgeInsets.all(AppSpace.md);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: LayoutBuilder(builder: (context, box) {
        Widget column(List<Widget> children) =>
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        if (!box.hasBoundedHeight) return Padding(padding: pad, child: column([...fields, AppSpace.gapSm, ...footer]));
        return column([
          Flexible(child: SingleChildScrollView(padding: pad, child: column(fields))),
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
            child: Padding(padding: pad, child: column(footer)),
          ),
        ]);
      }),
    );
  }
}
