// lib/design/app_infinite_scroll.dart — infinite scroll, ONE way for every paged list (the course lists first).
//
//   AppInfiniteScroll(
//     controller: _scroll,                 // the ScrollController of the list's own scroll view
//     hasMore: p.hasMore,                  // the server has more rows than are loaded
//     loading: p.isLoading,                // a page (first or next) is in flight
//     onLoadMore: p.loadMore,              // appends the next page
//     child: CustomScrollView(controller: _scroll, slivers: [..., SliverToBoxAdapter(child: PagedListFooter(...))]),
//   )
//
// It asks for the next page whenever the end of the list is within [threshold] pixels — not only on a scroll
// event. A scroll listener alone stalls in three real cases (the "only the first 6 courses" bug):
//   • the user already sits at the end when a page lands that adds few or no visible rows (a list filtered on the
//     client: the catalogue hides enrolled courses, My courses filters by status / search), so nothing scrolls;
//   • on the web / desktop a mouse wheel at the end of the list moves nothing, so no scroll event fires at all;
//   • the first pages don't fill the viewport (a wide grid), so there is nothing to scroll.
// So it also checks after every frame its inputs change, after every load it started, and whenever the scroll
// view's content size changes (ScrollMetricsNotification).
//
// Double fetches: one load at a time (its own in-flight flag on top of [loading]); a failed load ([failed]) is not
// retried automatically, only when the person scrolls again (through [onRetry] when given).
// Test: test/ui/app_infinite_scroll_test.dart.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

class AppInfiniteScroll extends StatefulWidget {
  const AppInfiniteScroll({
    super.key,
    required this.controller,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    required this.child,
    this.failed = false,
    this.onRetry,
    this.threshold = 480,
  });

  /// The controller attached to the list's scroll view (the one inside [child]).
  final ScrollController controller;

  /// More rows exist on the server.
  final bool hasMore;

  /// A page request is in flight (the first page included): nothing is asked meanwhile.
  final bool loading;

  /// Loads and appends the next page.
  final FutureOr<void> Function() onLoadMore;

  /// The last page request failed: wait for the person to scroll before asking again.
  final bool failed;

  /// Called instead of [onLoadMore] when the person scrolls after a failure.
  final FutureOr<void> Function()? onRetry;

  /// Load when the end of the list is closer than this (pixels). `double.infinity` = keep loading everything
  /// (a client-side filter that must see every row).
  final double threshold;

  final Widget child;

  @override
  State<AppInfiniteScroll> createState() => _AppInfiniteScrollState();
}

class _AppInfiniteScrollState extends State<AppInfiniteScroll> {
  bool _inFlight = false;
  bool _scheduled = false;

  /// Bumped by every rebuild from above (the list's provider notified). A load that changed nothing (the provider
  /// declined: a guard, a failure it keeps to itself) is not followed by another one — no request loop.
  int _updates = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant AppInfiniteScroll old) {
    super.didUpdateWidget(old);
    _updates++;
    _schedule();
  }

  /// Re-checks once the coming frame is laid out (the scroll extents are only known then).
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _check();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _nearEnd {
    final c = widget.controller;
    if (!c.hasClients || c.positions.length != 1) return false;
    final pos = c.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) return false;
    // not scrollable at all (the pages don't fill the viewport) → extentAfter is 0: near the end too
    return pos.extentAfter <= widget.threshold;
  }

  void _check({bool user = false}) {
    if (!mounted || _inFlight || !widget.hasMore || widget.loading) return;
    if (widget.failed && !user) return;
    if (!_nearEnd) return;
    final load = widget.failed ? (widget.onRetry ?? widget.onLoadMore) : widget.onLoadMore;
    _inFlight = true;
    final before = _updates;
    Future<void>.sync(load).then((_) {}, onError: (Object _) {}).whenComplete(() {
      _inFlight = false;
      // the page landed while this flag still blocked the re-check → check now (still at the end: the next one)
      if (mounted && _updates != before) _schedule();
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && (n is ScrollUpdateNotification || n is OverscrollNotification)) _check(user: true);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0) _schedule();
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
      );
}
