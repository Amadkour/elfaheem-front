// lib/features/org/students/student_timeline.dart — the student's timeline (D-1400, phase 1, PLAN.md §3.2a).
//
//   StudentTimelineController(fetch)   the loaded pages: newest first, the next page through `before`, one kind filter
//   StudentTimeline(controller:)       the loader: skeleton, error with Retry, the view
//   StudentTimelineView(…)             plain values: filter chips, academic-year blocks, day labels, one row per item
//   UndoneBy / statusEventIdOf(item)   who undid a status change and when (phase 2); the event id of a status row
//
// The list is append-only: a merged read of the existing tables, so nothing on it is edited. The one action is
// "Undo" on a status change the server marks `can_undo` (the caller opens confirmUndoStatus, the undo is a NEW event);
// an undone change stays on the list struck through, with who undid it and when (from GET …/status/events, fetched
// only when the page holds an undone row). The kinds the caller may not see come back in `hidden_kinds` and get no
// chip. Tests: test/ui/student_file_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/design/app_bidi.dart' show bidiIsolate;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'student_file_models.dart';

/// One page of the timeline: [kinds] null = every kind the caller may see, [before] the previous page's `next_before`.
typedef StudentTimelineFetch = Future<TimelinePage> Function({List<String>? kinds, String? before, int limit});

/// Who undid a status change, when, and why (the undo event of `reverts_id`).
class UndoneBy {
  const UndoneBy({this.who, this.at, this.reason});
  final String? who;
  final DateTime? at;
  final String? reason;
}

/// Undo lookups by timeline item id (`status:<event id>`).
typedef UndoneByFetch = Future<Map<String, UndoneBy>> Function();

/// The status event id of a timeline row (`status:<id>`); null for every other row.
int? statusEventIdOf(TimelineItem item) {
  if (item.kind != 'status' || !item.id.startsWith('status:')) return null;
  return int.tryParse(item.id.substring('status:'.length));
}

class StudentTimelineController extends ChangeNotifier {
  StudentTimelineController(this.fetch, {this.pageSize = 30, this.undoneFetch});

  final StudentTimelineFetch fetch;
  final int pageSize;

  /// Resolves who undid the undone status rows; null = the rows say only "Undone".
  final UndoneByFetch? undoneFetch;

  List<TimelineItem> items = const [];

  /// Who undid each undone status row, by item id.
  Map<String, UndoneBy> undoneBy = const {};
  List<String> hiddenKinds = const [];
  String? nextBefore;

  /// The one kind shown; null = all.
  String? kind;
  bool loading = false, loadingMore = false, loaded = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;

  bool get hasMore => nextBefore != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The first page (again), with the current [kind].
  Future<void> load() async {
    final gen = ++_generation;
    loading = true;
    loadingMore = false; // an older page still in flight belongs to the previous generation and returns early
    error = null;
    _notify();
    try {
      final p = await fetch(kinds: kind == null ? null : [kind!], before: null, limit: pageSize);
      if (gen != _generation) return;
      items = p.items;
      nextBefore = p.nextBefore;
      if (kind == null || p.hiddenKinds.isNotEmpty) hiddenKinds = p.hiddenKinds;
      loaded = true;
      _resolveUndone(gen);
    } catch (e) {
      if (gen != _generation) return;
      error = ApiException.from(e).message;
    }
    loading = false;
    _notify();
  }

  /// The page after the last one shown.
  Future<void> more() async {
    final before = nextBefore;
    if (before == null || loadingMore || loading) return;
    final gen = _generation;
    loadingMore = true;
    _notify();
    try {
      final p = await fetch(kinds: kind == null ? null : [kind!], before: before, limit: pageSize);
      if (gen != _generation) return;
      items = mergeTimeline(items, p.items);
      nextBefore = p.nextBefore;
      _resolveUndone(gen);
    } catch (e) {
      if (gen != _generation) return;
      showAppNotice(ApiException.from(e).message, error: true);
    }
    loadingMore = false;
    _notify();
  }

  /// Fetches who undid the undone status rows not resolved yet (quietly: a failure keeps the plain "Undone").
  Future<void> _resolveUndone(int gen) async {
    final f = undoneFetch;
    if (f == null) return;
    final open = items.any((i) => i.undone && statusEventIdOf(i) != null && !undoneBy.containsKey(i.id));
    if (!open) return;
    try {
      final m = await f();
      if (gen != _generation || _disposed) return;
      undoneBy = {...undoneBy, ...m};
      _notify();
    } catch (_) {}
  }

  void setKind(String? k) {
    if (k == kind) return;
    kind = k;
    load();
  }

  /// Loads the first page once (a tab opened again keeps what it had).
  void ensureLoaded() {
    if (!loaded && !loading) load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The loader around [StudentTimelineView].
class StudentTimeline extends StatefulWidget {
  const StudentTimeline({super.key, required this.controller, this.onUndo});

  final StudentTimelineController controller;

  /// "Undo" on a status row with `can_undo`; null = no undo action.
  final ValueChanged<TimelineItem>? onUndo;

  @override
  State<StudentTimeline> createState() => _StudentTimelineState();
}

class _StudentTimelineState extends State<StudentTimeline> {
  @override
  void initState() {
    super.initState();
    widget.controller.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          return StudentTimelineView(
            items: c.items,
            hiddenKinds: c.hiddenKinds,
            kind: c.kind,
            onKind: c.setKind,
            loading: c.loading,
            error: c.error,
            onRetry: c.load,
            hasMore: c.hasMore,
            loadingMore: c.loadingMore,
            onLoadMore: c.more,
            undoneBy: c.undoneBy,
            onUndo: widget.onUndo,
          );
        },
      );
}

/// The timeline from plain values: one kind filter, academic-year blocks, day labels and the rows.
class StudentTimelineView extends StatelessWidget {
  const StudentTimelineView({
    super.key,
    required this.items,
    this.hiddenKinds = const [],
    this.kind,
    this.onKind,
    this.loading = false,
    this.error,
    this.onRetry,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
    this.undoneBy = const {},
    this.onUndo,
  });

  final List<TimelineItem> items;
  final List<String> hiddenKinds;
  final String? kind;
  final ValueChanged<String?>? onKind;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final bool hasMore, loadingMore;
  final VoidCallback? onLoadMore;

  /// Who undid each undone status row, by item id.
  final Map<String, UndoneBy> undoneBy;

  /// "Undo" on a status row the server marks `can_undo`; null = the list is read only.
  final ValueChanged<TimelineItem>? onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kinds = [for (final k in kTimelineFilterKinds) if (!hiddenKinds.contains(k)) k];
    final Widget body;
    if (loading && items.isEmpty) {
      body = const AppListSkeleton(items: 4);
    } else if (error != null && items.isEmpty) {
      body = AppErrorState(message: error, onRetry: onRetry, compact: true);
    } else if (items.isEmpty) {
      body = AppCard(
        child: Row(children: [
          Icon(Icons.history_toggle_off_rounded, size: AppIconSize.md, color: c.textMedium),
          AppSpace.gapSm,
          Expanded(
            child: Text(
              kind == null ? t('لا توجد أحداث بعد', 'Nothing has happened yet') : t('لا توجد أحداث من هذا النوع', 'Nothing of this kind yet'),
              style: AppType.body(context).copyWith(color: c.textMedium),
            ),
          ),
        ]),
      );
    } else {
      final groups = groupTimelineByYear(items);
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (gi, g) in groups.indexed) ...[
          Padding(
            padding: EdgeInsets.only(top: gi == 0 ? 0 : AppSpace.lg, bottom: AppSpace.xs),
            child: Semantics(header: true, child: Text(g.label, style: AppType.section(context))),
          ),
          for (final d in g.days) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xs),
              child: Text(d.day == null ? t('بلا تاريخ', 'No date') : AppTime.wall(d.day!, pattern: 'EEEE d MMMM y'),
                  style: AppType.label(context).copyWith(color: c.textMedium)),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
              child: Column(children: [
                for (final (i, item) in d.items.indexed)
                  StudentTimelineRow(
                    item: item,
                    last: i == d.items.length - 1,
                    undoneBy: undoneBy[item.id],
                    onUndo: onUndo == null || !item.canUndo || item.undone || statusEventIdOf(item) == null
                        ? null
                        : () => onUndo!(item),
                  ),
              ]),
            ),
          ],
        ],
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: Center(
              child: AppButton(
                label: t('أحداث أقدم', 'Older events'),
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.secondary,
                busy: loadingMore,
                onPressed: onLoadMore,
              ),
            ),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (kinds.length > 1) ...[
        Semantics(
          container: true,
          label: t('تصفية السجل', 'Filter the timeline'),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(label: t('الكل', 'All'), selected: kind == null, onTap: () => onKind?.call(null)),
            for (final k in kinds)
              AppChoiceChip(label: timelineKindText(k), icon: timelineIcon(k), selected: kind == k, onTap: () => onKind?.call(k)),
          ]),
        ),
        AppSpace.gapMd,
      ],
      if (loading && items.isNotEmpty) ...[const LinearProgressIndicator(minHeight: AppBorder.strong), AppSpace.gapXs],
      body,
    ]);
  }
}

/// One item: the kind's icon on its tone, the sentence, what it adds (detail, reason, decision number), who and when.
class StudentTimelineRow extends StatelessWidget {
  const StudentTimelineRow({super.key, required this.item, this.last = false, this.undoneBy, this.onUndo});

  final TimelineItem item;
  final bool last;

  /// Who undid this change and when (an undone status row).
  final UndoneBy? undoneBy;

  /// The row's "Undo" (a status change the caller may still undo); null = none.
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = timelineTone(item.kind);
    final color = appToneColor(context, tone);
    final meta = AppType.meta(context).copyWith(color: c.textMedium);
    final when = item.at == null ? null : AppTime.time(item.at!.toUtc());
    final undo = undoneBy;
    final undoneLine = !item.undone || undo == null ? null : undoneText(undo);
    final content = MergeSemantics(
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: AppSpace.xl,
            child: Column(children: [
              const SizedBox(height: AppSpace.xs),
              Container(
                width: AppSpace.xl,
                height: AppSpace.xl,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(timelineIcon(item.kind), size: AppIconSize.sm, color: color),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: AppBorder.strong,
                    margin: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                    color: c.divider,
                  ),
                ),
            ]),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  item.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.row(context).copyWith(
                    decoration: item.undone ? TextDecoration.lineThrough : null,
                    color: item.undone ? c.textMedium : null,
                  ),
                ),
                if (item.detail != null) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(item.detail!, maxLines: 4, overflow: TextOverflow.ellipsis, style: meta),
                ],
                if (item.reason != null || item.decisionNo != null || item.undone) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                    if (item.undone) AppStatusBadge(label: t('تم التراجع عنه', 'Undone'), tone: AppTone.neutral, dense: true),
                    if (item.decisionNo != null)
                      AppStatusBadge(
                          // the number keeps its own order ("12/2026", never scrambled by the Arabic around it)
                          label: t('قرار رقم ${bidiIsolate(item.decisionNo!)}', 'Decision no. ${bidiIsolate(item.decisionNo!)}'),
                          icon: Icons.gavel_rounded,
                          tone: AppTone.info,
                          dense: true),
                    if (item.reason != null)
                      Text(t('السبب: ${item.reason}', 'Reason: ${item.reason}'),
                          maxLines: 3, overflow: TextOverflow.ellipsis, style: meta),
                  ]),
                ],
                if (undoneLine != null && undoneLine.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
                      child: Icon(Icons.undo_rounded, size: AppIconSize.xs, color: c.textMedium),
                    ),
                    const SizedBox(width: AppSpace.xxs),
                    Expanded(child: Text(undoneLine, maxLines: 3, overflow: TextOverflow.ellipsis, style: meta)),
                  ]),
                ],
                const SizedBox(height: AppSpace.xxs),
                Text(
                  // each run isolated: a Latin name next to the time must not pull "م" / "ص" away from its clock
                  [timelineKindText(item.kind), if (item.actor.isNotEmpty) bidiIsolate(item.actor), if (when != null) bidiIsolate(when)].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
    final undoTap = onUndo;
    if (undoTap == null) return content;
    // the action sits under the text, outside the merged semantics: a screen reader reads the row, then the button
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      content,
      Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.xl + AppSpace.sm, bottom: AppSpace.xs),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(
            label: t('تراجع عن هذا التغيير', 'Undo this change'),
            icon: Icons.undo_rounded,
            size: AppButtonSize.sm,
            onPressed: undoTap,
          ),
        ),
      ),
    ]);
  }
}

/// "Undone by Mona on 21 Nov, 10:05 · Reason: …" (the parts that are known).
String undoneText(UndoneBy u) {
  final at = u.at == null ? null : AppTime.dateTime(u.at!.toUtc());
  final String? head;
  if (u.who != null && at != null) {
    head = t('تراجع عنه ${bidiIsolate(u.who!)} في ${bidiIsolate(at)}', 'Undone by ${bidiIsolate(u.who!)} on ${bidiIsolate(at)}');
  } else if (u.who != null) {
    head = t('تراجع عنه ${bidiIsolate(u.who!)}', 'Undone by ${bidiIsolate(u.who!)}');
  } else if (at != null) {
    head = t('تم التراجع عنه في ${bidiIsolate(at)}', 'Undone on ${bidiIsolate(at)}');
  } else {
    head = null;
  }
  return [?head, if (u.reason != null) t('السبب: ${u.reason}', 'Reason: ${u.reason}')].join(' · ');
}
