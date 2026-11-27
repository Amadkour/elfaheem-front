// lib/features/courses/roadmap/roadmap_editor.dart
//
// The teacher's "Edit path" sheet (D-120): next courses (add · reorder by dragging or from each row's ⋮ menu /
// the screen reader's actions — Move up · Move down, so a keyboard or a screen reader can too · remove), this course's
// prerequisites, its level and its topic words — ONE save (PUT /api/v1/roadmap/courses/{id}). The edit itself is
// the pure RoadmapDraft (roadmap_api.dart); [RoadmapEditorForm] draws it from plain values for the layout test.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';

/// Opens the editor for [roadmap]; returns the saved roadmap, null when closed without saving.
Future<Roadmap?> showRoadmapEditor(BuildContext context, {required int courseId, required Roadmap roadmap, RoadmapApi api = const RoadmapApi()}) =>
    showAppSheet<Roadmap>(context, mode: AppSheetMode.side, (_) => RoadmapEditorSheet(courseId: courseId, roadmap: roadmap, api: api));

class RoadmapEditorSheet extends StatefulWidget {
  const RoadmapEditorSheet({super.key, required this.courseId, required this.roadmap, required this.api});

  final int courseId;
  final Roadmap roadmap;
  final RoadmapApi api;

  @override
  State<RoadmapEditorSheet> createState() => _RoadmapEditorSheetState();
}

class _RoadmapEditorSheetState extends State<RoadmapEditorSheet> {
  List<RmCourse>? _candidates;
  RoadmapDraft? _draft;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.api.candidates(widget.courseId);
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _draft = RoadmapDraft.of(widget.roadmap, list);
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  Future<void> _pick({required bool prereq}) async {
    final d = _draft!;
    final picked = await showAppSheet<RmCourse>(
      context,
      (_) => _CoursePicker(
        title: prereq ? t('أضف متطلب', 'Add a requirement') : t('أضف دورة بعدها', 'Add a course after it'),
        courses: d.available(_candidates ?? const []),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => prereq ? d.addPrereq(picked) : d.addNext(picked));
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.api.save(widget.courseId, d);
      if (!mounted) return;
      showAppNotice(t('تم حفظ المسار', 'Path saved'));
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(t('مسار التعلّم', 'Learning path')),
        Flexible(
          child: d != null
              ? RoadmapEditorForm(
                  draft: d,
                  canAdd: d.available(_candidates ?? const []).isNotEmpty,
                  course: widget.roadmap.course,
                  onAddNext: () => _pick(prereq: false),
                  onAddPrereq: () => _pick(prereq: true),
                  onChanged: () => setState(() {}),
                )
              : _error != null
              ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
              : const Padding(padding: EdgeInsets.all(16), child: AppListSkeleton(items: 4)),
        ),
        if (d != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: AppPrimaryButton(label: t('حفظ المسار', 'Save the path'), icon: Icons.check_rounded, busy: _saving, onPressed: _save),
          ),
      ],
    );
  }
}

/// The editor's body (plain values: the draft and callbacks).
class RoadmapEditorForm extends StatefulWidget {
  const RoadmapEditorForm({
    super.key,
    required this.draft,
    required this.onAddNext,
    required this.onAddPrereq,
    required this.onChanged,
    this.canAdd = true,
    this.course,
  });

  final RoadmapDraft draft;
  final VoidCallback onAddNext, onAddPrereq, onChanged;
  final bool canAdd;

  /// This course: drawn between what comes before and after it (null: left out).
  final RmCourse? course;

  @override
  State<RoadmapEditorForm> createState() => _RoadmapEditorFormState();
}

class _RoadmapEditorFormState extends State<RoadmapEditorForm> {
  Widget _nextColumn(BuildContext context) {
    final d = widget.draft;
    final full = d.next.length >= RoadmapDraft.maxCourses;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Head(
        title: t('الدورات بعدها', 'Courses after it'),
        subtitle: t('بالترتيب الذي يدرسه الطالب. اسحب لإعادة الترتيب.', 'In the order a student takes them. Drag to reorder.'),
      ),
      if (d.next.isEmpty)
        _Hint(t('لا دورات بعدها بعد', 'No courses after it yet'))
      else
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            d.moveNext(a, b);
            widget.onChanged();
          },
          children: [
            for (var i = 0; i < d.next.length; i++)
              _CourseRow(
                key: ValueKey('next-${d.next[i].id}'),
                index: i,
                course: d.next[i],
                leading: Text('${i + 1}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                draggable: d.next.length > 1,
                onMoveUp: i > 0
                    ? () {
                        d.moveNext(i, i - 1);
                        widget.onChanged();
                      }
                    : null,
                onMoveDown: i < d.next.length - 1
                    ? () {
                        d.moveNext(i, i + 1);
                        widget.onChanged();
                      }
                    : null,
                onRemove: () {
                  d.next.removeAt(i);
                  widget.onChanged();
                },
              ),
          ],
        ),
      _AddButton(
        label: t('أضف دورة بعدها', 'Add a course after it'),
        onTap: widget.canAdd && !full ? widget.onAddNext : null,
      ),
    ]);
  }

  Widget _prereqColumn(BuildContext context) {
    final c = context.colors;
    final d = widget.draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Head(
        title: t('المتطلبات قبلها', 'Requirements before it'),
        subtitle: t('يراها الطالب مكتملة أو لا. لا تمنع الاشتراك.', 'Students see whether they are done. They never block enrolling.'),
      ),
      for (var i = 0; i < d.prereqs.length; i++)
        _CourseRow(
          key: ValueKey('pre-${d.prereqs[i].id}'),
          course: d.prereqs[i],
          leading: Icon(Icons.link_rounded, size: AppIconSize.md, color: c.textMedium),
          onRemove: () {
            d.prereqs.removeAt(i);
            widget.onChanged();
          },
        ),
      if (d.prereqs.isEmpty) _Hint(t('بدون متطلبات', 'None')),
      _AddButton(
        label: t('أضف متطلب', 'Add a requirement'),
        onTap: widget.canAdd && d.prereqs.length < RoadmapDraft.maxCourses ? widget.onAddPrereq : null,
      ),
    ]);
  }

  /// This course, between what comes before and after it.
  Widget _centerNode(BuildContext context) {
    final c = context.colors;
    final course = widget.course;
    if (course == null) return const SizedBox.shrink();
    final ink = appInkOnFill(context, c.primary);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: c.primary, borderRadius: AppRadius.cardAll),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.fact_check_outlined, size: AppIconSize.lg, color: ink),
        AppSpace.gapXs,
        Text(course.name, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: ink)),
        Text(t('هذه الدورة', 'This course'), textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: ink.withValues(alpha: 0.85))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xs),
      children: [
        Text(
            t('حدد وش لازم يخلّص الطالب قبل هالدورة، ووش ننصحه ياخذ بعدها. نعرضها للطالب في صفحة الدورة ونقترحها له لما يخلّص.',
                'Set what a student should finish before this course and what we suggest after it. We show it on the course page and suggest it when he finishes.'),
            style: AppType.body(context).copyWith(color: context.colors.textMedium)),
        AppSpace.gapMd,
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 720) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _prereqColumn(context),
              if (widget.course != null) ...[AppSpace.gapSm, _centerNode(context), AppSpace.gapMd],
              _nextColumn(context),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _prereqColumn(context)),
            if (widget.course != null) ...[
              AppSpace.gapMd,
              Expanded(child: Padding(padding: const EdgeInsets.only(top: AppSpace.xxl), child: _centerNode(context))),
              AppSpace.gapMd,
            ] else
              AppSpace.gapMd,
            Expanded(child: _nextColumn(context)),
          ]);
        }),
        AppSpace.gapMd,
        _Head(title: t('المستوى', 'Level')),
        RoadmapLevelChips(
          value: d.level,
          onChanged: (l) {
            d.level = l;
            widget.onChanged();
          },
        ),
        AppSpace.gapMd,
        _Head(
          title: t('كلمات مفتاحية', 'Topic words'),
          subtitle: t('حتى ${RoadmapDraft.maxTags} كلمات تساعد على اقتراح دورتك لمن يهتم بها.', 'Up to ${RoadmapDraft.maxTags} words that help suggest your course to the right students.'),
        ),
        RoadmapTagsInput(
          tags: d.tags,
          onAdd: (s) {
            final added = d.addTag(s);
            if (added) widget.onChanged();
            return added;
          },
          onRemove: (tag) {
            d.tags.remove(tag);
            widget.onChanged();
          },
        ),
        AppSpace.gapMd,
        AppBanner(
          icon: Icons.info_outline_rounded,
          color: context.colors.accent3,
          text: t('المسار متاح لدوراتك الشخصية. الطلاب اللي خلّصوا ٨٠٪ يوصلهم اقتراح «الخطوة الجاية».',
              'The path works for your personal courses. Students who finish 80% get the "next step" suggestion.'),
        ),
      ],
    );
  }
}

/// No level · Beginner · Intermediate · Advanced (the editor and the course form).
class RoadmapLevelChips extends StatelessWidget {
  const RoadmapLevelChips({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final l in <String?>[null, ...roadmapLevels])
        AppChoiceChip(label: roadmapLevelLabel(l), selected: value == l, onTap: () => onChanged(l)),
    ],
  );
}

/// The topic words: chips with a remove button + a field that adds one (Enter or +). [onAdd] answers whether the
/// word was taken (trimmed, unique, at most [RoadmapDraft.maxTags]).
class RoadmapTagsInput extends StatefulWidget {
  const RoadmapTagsInput({super.key, required this.tags, required this.onAdd, required this.onRemove});

  final List<String> tags;
  final bool Function(String) onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<RoadmapTagsInput> createState() => _RoadmapTagsInputState();
}

class _RoadmapTagsInputState extends State<RoadmapTagsInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    if (widget.onAdd(_ctrl.text)) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in widget.tags)
                  InputChip(
                    label: Text(tag, style: AppType.label(context).copyWith(color: c.textDark)),
                    onDeleted: () => widget.onRemove(tag),
                    deleteButtonTooltipMessage: t('حذف', 'Remove'),
                  ),
              ],
            ),
          ),
        if (widget.tags.length < RoadmapDraft.maxTags)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLength: RoadmapDraft.tagLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(hintText: t('مثال: بايثون', 'e.g. Python'), counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _add, tooltip: t('إضافة', 'Add'), icon: const Icon(Icons.add_rounded)),
            ],
          ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.section(context)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppType.meta(context)),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: AppType.body(context)),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: onTap == null ? c.inputBg : Color.alphaBlend(c.primaryTint, c.cardBg),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_rounded, size: AppIconSize.md, color: onTap == null ? c.textLight : c.primary),
            AppSpace.gapXs,
            Flexible(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(color: onTap == null ? c.textLight : appInk(context, c.primary))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    super.key,
    required this.course,
    required this.leading,
    required this.onRemove,
    this.index,
    this.draggable = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  final RmCourse course;
  final Widget leading;
  final VoidCallback onRemove;
  final int? index;
  final bool draggable;

  /// A next course: its ⋮ menu (and the screen reader's actions) move it; null = already first / last.
  final VoidCallback? onMoveUp, onMoveDown;

  bool get _ordered => index != null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final draft = !course.isPublished;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: t('نقل لأعلى', 'Move up')): ?onMoveUp,
          CustomSemanticsAction(label: t('نقل لأسفل', 'Move down')): ?onMoveDown,
        },
        child: Container(
        padding: const EdgeInsetsDirectional.only(start: 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: leading)),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    if (draft || course.level != null)
                      Text(
                        [if (draft) t('مسودة', 'Draft'), if (course.level != null) roadmapLevelLabel(course.level)].join(' · '),
                        style: AppType.meta(context).copyWith(color: draft ? appInk(context, c.warning) : c.textMedium),
                      ),
                  ],
                ),
              ),
            ),
            if (_ordered)
              PopupMenuButton<String>(
                tooltip: t('خيارات', 'Options'),
                icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
                onSelected: (v) => switch (v) {
                  'up' => onMoveUp?.call(),
                  'down' => onMoveDown?.call(),
                  _ => onRemove(),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'up',
                    enabled: onMoveUp != null,
                    child: Row(children: [const Icon(Icons.arrow_upward_rounded, size: 18), const SizedBox(width: 10), Text(t('نقل لأعلى', 'Move up'))]),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: onMoveDown != null,
                    child: Row(children: [const Icon(Icons.arrow_downward_rounded, size: 18), const SizedBox(width: 10), Text(t('نقل لأسفل', 'Move down'))]),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(children: [const Icon(Icons.close_rounded, size: 18), const SizedBox(width: 10), Text(t('إزالة', 'Remove'))]),
                  ),
                ],
              )
            else
              IconButton(
                onPressed: onRemove,
                tooltip: t('إزالة', 'Remove'),
                icon: Icon(Icons.close_rounded, size: 20, color: c.textMedium),
              ),
            if (draggable && index != null)
              ReorderableDragStartListener(
                index: index!,
                child: Tooltip(
                  message: t('اسحب لإعادة الترتيب', 'Drag to reorder'),
                  child: SizedBox(width: 44, height: 48, child: Icon(Icons.drag_indicator_rounded, color: c.textLight)),
                ),
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
      ),
    );
  }
}

/// Picks one of the teacher's courses (search when the list is long).
class _CoursePicker extends StatefulWidget {
  const _CoursePicker({required this.title, required this.courses});

  final String title;
  final List<RmCourse> courses;

  @override
  State<_CoursePicker> createState() => _CoursePickerState();
}

class _CoursePickerState extends State<_CoursePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? widget.courses : [for (final x in widget.courses) if (x.name.toLowerCase().contains(q)) x];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(widget.title),
        if (widget.courses.length > 6)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('ابحث في دوراتك', 'Search your courses'), isDense: true),
            ),
          ),
        Flexible(
          child: list.isEmpty
              ? AppEmpty(icon: Icons.search_off_rounded, title: t('لا دورات أخرى', 'No other courses'))
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final x in list)
                      ListTile(
                        minVerticalPadding: 12,
                        leading: Icon(Icons.menu_book_rounded, color: appInk(context, c.primary)),
                        title: Text(x.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                        subtitle: !x.isPublished ? Text(t('مسودة', 'Draft'), style: AppType.meta(context).copyWith(color: appInk(context, c.warning))) : null,
                        onTap: () => Navigator.of(context).pop(x),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
