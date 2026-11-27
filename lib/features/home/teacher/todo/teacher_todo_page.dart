// lib/features/home/teacher/todo/teacher_todo_page.dart — the teacher's whole to-do list (D-303).
//
//   hero      T1 (Tea1Home todo): "Your to-do", how much is urgent over it, the three counts as glass tiles on the
//             hero (Urgent · Soon · When you can: a tap filters by it); the list rides up over it
//   filters   All · Grading & exams · Students · Schedule · Lessons · Requests (only the groups that hold items)
//   list      TodoRow(card) per item, highest score first: the evidence, the one action, ⋯ Done / Snooze / Dismiss (Undo
//             in the notice); at-risk items list their students and why
//   hidden    "Done, snoozed and dismissed (n)" folded at the end, each with Restore
//   empty     "You're all caught up" — the list fills by itself as things need you
// Data: TeacherTodoApi.load (the core list + the engine's queues, merged), on open / pull-to-refresh / Refresh; a
// state change is applied at once on the screen, then sent; a failure puts the item back. Opened from the home card,
// the attention badge (AppNavigator module `teacher_todo`) and nothing else. Kill switch `teacher_home.todo`
// (BasePage ValueKey). TeacherTodoView takes plain values (layout tests and renders).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppReveal;
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2HeroScroll, T2Scope;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_actions.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_api.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_widgets.dart';

export 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_actions.dart' show openTodoAction;

const kTeacherTodoFeatureKey = 'teacher_home.todo';

class TeacherTodoPage extends StatefulWidget {
  const TeacherTodoPage({super.key, this.api});
  final TeacherTodoApi? api;

  @override
  State<TeacherTodoPage> createState() => _TeacherTodoPageState();
}

class _TeacherTodoPageState extends State<TeacherTodoPage> {
  late final TeacherTodoApi _api = widget.api ?? TeacherTodoApi();
  TodoList? _list;
  String? _error;
  bool _loading = true;
  DateTime? _updated;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _list == null;
      _error = null;
    });
    try {
      final l = await _api.load();
      if (!mounted) return;
      setState(() {
        _list = l;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiException.from(e).message);
      if (_list != null) showAppNotice(_error!, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(TodoItem x) async {
    final opened = await openTodoAction(context, x);
    if (!opened) showAppNotice('todo_cannot_open'.tr, error: true);
    if (mounted) _load(); // the work done there may have closed the item
  }

  Future<void> _choose(TodoItem x, TodoMenu m) async {
    final before = _list;
    if (before == null) return;
    setState(() => _list = TodoList(
          items: [for (final i in before.items) if (i.key != x.key) i],
          hidden: [x.withState(m == TodoMenu.done ? 'done' : m == TodoMenu.dismiss ? 'dismiss' : 'snooze'), ...before.hidden],
          states: before.states,
        ));
    final ok = await sendTodoChoice(x, m, api: _api, onUndone: () {
      if (mounted) _load();
    });
    if (!ok && mounted) setState(() => _list = before);
  }

  Future<void> _restore(TodoItem x) async {
    setState(() => _busy.add(x.key));
    try {
      await _api.setState(x, 'restore');
      AttentionService.instance.refresh();
      await _load();
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(x.key));
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey(kTeacherTodoFeatureKey),
        enableFooterWidget: false,
        appBar: AppHeader(title: 'todo_title'.tr),
        child: T2Scope(
          child: TeacherTodoView(
            list: _list,
            loading: _loading,
            error: _list == null ? _error : null,
            updatedAt: _updated,
            busy: _busy,
            onBack: () => Navigator.of(context).maybePop(),
            onRefresh: _load,
            onOpen: _open,
            onMenu: _choose,
            onRestore: _restore,
          ),
        ),
      );
}

/// The page's body from plain values.
class TeacherTodoView extends StatefulWidget {
  const TeacherTodoView({
    super.key,
    required this.list,
    required this.onRefresh,
    required this.onOpen,
    required this.onMenu,
    required this.onRestore,
    this.loading = false,
    this.error,
    this.updatedAt,
    this.busy = const {},
    this.onBack,
  });

  final TodoList? list;
  final bool loading;
  final String? error;
  final DateTime? updatedAt;
  final Set<String> busy;
  final VoidCallback? onBack;
  final Future<void> Function() onRefresh;
  final void Function(TodoItem) onOpen;
  final void Function(TodoItem, TodoMenu) onMenu;
  final void Function(TodoItem) onRestore;

  @override
  State<TeacherTodoView> createState() => _TeacherTodoViewState();
}

class _TeacherTodoViewState extends State<TeacherTodoView> {
  String? _filter;
  bool _showHidden = false;

  static const _groups = [TodoGroup.grading, TodoGroup.students, TodoGroup.schedule, TodoGroup.content, TodoGroup.requests];

  String _groupLabel(TodoGroup g) => switch (g) {
        TodoGroup.grading => 'todo_g_grading'.tr,
        TodoGroup.students => 'todo_g_students'.tr,
        TodoGroup.schedule => 'todo_g_schedule'.tr,
        TodoGroup.content => 'todo_g_content'.tr,
        TodoGroup.requests => 'todo_g_requests'.tr,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = widget.list;
    final items = list?.items ?? const <TodoItem>[];
    final high = items.where((x) => x.isHigh).length;
    final present = {for (final x in items) x.group};
    final filter = _filter != null && _filter != 'high' && _filter != 'medium' && _filter != 'low' && !present.any((g) => g.name == _filter) ? null : _filter;
    final shown = filter == 'medium' || filter == 'low' ? [for (final x in items) if (x.priority == filter) x] : todoFiltered(items, filter);
    final subtitle = list == null
        ? null
        : items.isEmpty
            ? 'todo_all_clear_short'.tr
            : high > 0
                ? countText(high, ar1: 'مهمة عاجلة واحدة', ar2: 'مهمتان عاجلتان', arFew: '{n} مهام عاجلة', arMany: '{n} مهمة عاجلة', en1: '1 urgent item', en: '{n} urgent items')
                : countText(items.length, ar1: 'مهمة واحدة', ar2: 'مهمتان', arFew: '{n} مهام', arMany: '{n} مهمة', en1: '1 item', en: '{n} items');

    final Widget hero = AppHero(
      title: 'todo_title'.tr,
      subtitle: 't1_hm_todo_sub'.tr,
      kicker: subtitle,
      bottom: items.isEmpty ? null : AppReveal(index: 0, group: 'todo', child: TodoSummary(items: items, selected: filter, onSelect: (p) => setState(() => _filter = p))),
    );
    final List<Widget> body;
    if (widget.loading && list == null) {
      body = [const AppListSkeleton(items: 5, withAvatar: true, padding: EdgeInsets.zero)];
    } else if (widget.error != null && list == null) {
      body = [AppErrorState(message: widget.error, onRetry: widget.onRefresh)];
    } else if (list != null && !list.enabled) {
      body = [AppEmpty(icon: Icons.checklist_rounded, title: 'todo_off'.tr)];
    } else {
      body = [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (items.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  AppChoiceChip(label: '${'todo_all'.tr} · ${items.length}', selected: filter == null, onTap: () => setState(() => _filter = null)),
                  for (final g in _groups)
                    if (present.contains(g)) ...[
                      const SizedBox(width: AppSpace.xs),
                      AppChoiceChip(
                        label: '${_groupLabel(g)} · ${items.where((x) => x.group == g).length}',
                        selected: filter == g.name,
                        onTap: () => setState(() => _filter = filter == g.name ? null : g.name),
                      ),
                    ],
                ]),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                child: AppEmpty(icon: Icons.task_alt_rounded, title: 'todo_all_clear'.tr, message: 'todo_all_clear_hint'.tr, tone: AppBlockTone.emerald),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                child: AppEmpty(icon: Icons.filter_alt_off_outlined, title: 'todo_filter_empty'.tr, actionLabel: 'todo_all'.tr, onAction: () => setState(() => _filter = null)),
              )
            else
              AppReveal(
                index: 1,
                group: 'todo',
                // a card that leaves (done, snoozed, dismissed) closes its gap instead of jumping
                child: AnimatedSize(
                  duration: AppMotion.of(context).base,
                  curve: AppEase.out,
                  alignment: AlignmentDirectional.topStart,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpace.sm),
                      TodoRow(
                        key: ValueKey('todo:${shown[i].key}'),
                        item: shown[i],
                        card: true,
                        busy: widget.busy.contains(shown[i].key),
                        onOpen: () => widget.onOpen(shown[i]),
                        onMenu: (m) => widget.onMenu(shown[i], m),
                      ),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
        if ((list?.hidden ?? const []).isNotEmpty) ...[
          _HiddenHeader(count: list!.hidden.length, open: _showHidden, onTap: () => setState(() => _showHidden = !_showHidden)),
          // the folded list opens under its header (and closes) on the kit's ease-out, from where it is
          AnimatedSize(
            duration: AppMotion.of(context).base,
            curve: AppEase.out,
            alignment: AlignmentDirectional.topStart,
            child: !_showHidden
                ? const SizedBox(width: double.infinity)
                : AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < list.hidden.length; i++) ...[
                        if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: kTodoRowIndent, color: c.divider),
                        TodoRow(
                          item: list.hidden[i],
                          busy: widget.busy.contains(list.hidden[i].key),
                          onRestore: () => widget.onRestore(list.hidden[i]),
                        ),
                      ],
                    ]),
                  ),
          ),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.auto_awesome_outlined, size: AppIconSize.sm, color: c.textLight),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text('todo_how'.tr, style: AppType.meta(context).copyWith(height: 1.45))),
        ]),
      ];
    }
    return T2Scope(
      child: AppRefresh(
        onRefresh: widget.onRefresh,
        child: T2HeroScroll(hero: hero, width: AppWidth.content, children: body),
      ),
    );
  }
}

class _HiddenHeader extends StatelessWidget {
  const _HiddenHeader({required this.count, required this.open, required this.onTap});
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Row(children: [
            Icon(Icons.inventory_2_outlined, size: AppIconSize.md, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text('todo_hidden_n'.tr.replaceAll('{n}', '$count'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: AppMotion.of(context).base,
              curve: AppEase.out,
              child: Icon(Icons.expand_more_rounded, size: AppIconSize.lg, color: c.textMedium),
            ),
          ]),
        ),
      ),
    );
  }
}
