// lib/features/org/students/student_timeline.dart — the student's timeline (D-1400, phase 1, PLAN.md §3.2a).
//
//   StudentTimelineController(fetch)   the loaded pages: newest first, the next page through `before`, one kind filter
//   StudentTimeline(controller:)       the loader: skeleton, error with Retry, the view
//   StudentTimelineView(…)             plain values: filter chips, academic-year blocks, day labels, one row per item
//
// The list is append-only and read only: a merged read of the existing tables, so nothing on it can be edited. The
// kinds the caller may not see come back in `hidden_kinds` and get no chip. Tests: test/ui/student_file_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'student_file_models.dart';

/// One page of the timeline: [kinds] null = every kind the caller may see, [before] the previous page's `next_before`.
typedef StudentTimelineFetch = Future<TimelinePage> Function({List<String>? kinds, String? before, int limit});

class StudentTimelineController extends ChangeNotifier {
  StudentTimelineController(this.fetch, {this.pageSize = 30});

  final StudentTimelineFetch fetch;
  final int pageSize;

  List<TimelineItem> items = const [];
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
    error = null;
    _notify();
    try {
      final p = await fetch(kinds: kind == null ? null : [kind!], before: null, limit: pageSize);
      if (gen != _generation) return;
      items = p.items;
      nextBefore = p.nextBefore;
      if (kind == null || p.hiddenKinds.isNotEmpty) hiddenKinds = p.hiddenKinds;
      loaded = true;
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
    } catch (e) {
      if (gen != _generation) return;
      showAppNotice(ApiException.from(e).message, error: true);
    }
    loadingMore = false;
    _notify();
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
  const StudentTimeline({super.key, required this.controller});

  final StudentTimelineController controller;

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
                for (final (i, item) in d.items.indexed) StudentTimelineRow(item: item, last: i == d.items.length - 1),
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
  const StudentTimelineRow({super.key, required this.item, this.last = false});

  final TimelineItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = timelineTone(item.kind);
    final color = appToneColor(context, tone);
    final meta = AppType.meta(context).copyWith(color: c.textMedium);
    final when = item.at == null ? null : AppTime.time(item.at!.toUtc());
    return MergeSemantics(
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
                          label: t('قرار رقم ${item.decisionNo}', 'Decision no. ${item.decisionNo}'),
                          icon: Icons.gavel_rounded,
                          tone: AppTone.info,
                          dense: true),
                    if (item.reason != null)
                      Text(t('السبب: ${item.reason}', 'Reason: ${item.reason}'),
                          maxLines: 3, overflow: TextOverflow.ellipsis, style: meta),
                  ]),
                ],
                const SizedBox(height: AppSpace.xxs),
                Text(
                  [timelineKindText(item.kind), item.actor, ?when].join(' · '),
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
  }
}
