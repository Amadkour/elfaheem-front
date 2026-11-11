import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'course_list_card.dart';
import 'course_row.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppSpace;
import 'package:flutter_education_app/design/app_infinite_scroll.dart';

class HomeCourseList extends StatefulWidget {
  const HomeCourseList({
    super.key,
    required this.hasMore,
    required this.courses,
    required this.onTap,
    required this.isTeacher,
    required this.pageName,
    this.onLoadMore,
    this.onRefresh,
    this.loadingMore = false,
    this.loadFailed = false,
    this.onRetry,
    this.badgeFor,
    this.maxWidth = 1440, // AppWidth.wide: the page card already sets the width role; 860 left empty sides (D-561)
  });

  /// The list's widest; the page around it decides (its width role).
  final double maxWidth;

  /// A small mark drawn over each card's picture (under the favourite heart) — e.g. where the course lives when
  /// the list mixes the personal account and organizations. Null (or a null result) draws nothing.
  final Widget? Function(CourseModel course)? badgeFor;

  final String pageName;
  final List<CourseModel> courses;
  final bool hasMore;
  final void Function(CourseModel course) onTap;
  final bool isTeacher;

  /// Passing this turns on infinite scroll (AppInfiniteScroll: the next page whenever the end is near, also when
  /// the pages don't fill the screen; footer; pull-to-refresh). Without it the list behaves exactly as before
  /// (used by the home screen).
  final FutureOr<void> Function()? onLoadMore;
  final Future<void> Function()? onRefresh;
  final bool loadingMore;

  /// The last next-page request failed: only scrolling again asks again (through [onRetry] when given).
  final bool loadFailed;
  final FutureOr<void> Function()? onRetry;

  @override
  State<HomeCourseList> createState() => _HomeCourseListState();
}

class _HomeCourseListState extends State<HomeCourseList> {
  final _scroll = ScrollController();

  bool get _paged => widget.onLoadMore != null;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _card(CourseModel c, CourseCardShape shape) => CourseCard(
        key: ValueKey('course-${c.id}'),
        course: c,
        pageName: widget.pageName,
        isTeacher: widget.isTeacher,
        fullScreen: true,
        shape: shape,
        // a mixed list says on every card where the course lives (it leads the card's meta line)
        badge: widget.badgeFor?.call(c),
        onTap: (CourseModel c) => widget.onTap.call(c),
      );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: LayoutBuilder(builder: (context, box) {
          // rows on a phone, a grid of tiles once there is room (course_list_card.dart)
          final width = math.max(0.0, box.maxWidth - AppSpace.md * 2);
          final cards = CourseCardSliver(
            width: width,
            count: widget.courses.length,
            itemBuilder: (_, i, shape) => _card(widget.courses[i], shape),
          );

          if (_paged) {
            Widget body = CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0), sliver: cards),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: PagedListFooter(loadingMore: widget.loadingMore, hasMore: widget.hasMore),
                  ),
                ),
              ],
            );
            if (widget.onRefresh != null) body = AppRefresh(onRefresh: widget.onRefresh!, child: body);
            return AppInfiniteScroll(
              controller: _scroll,
              hasMore: widget.hasMore,
              loading: widget.loadingMore,
              failed: widget.loadFailed,
              onLoadMore: widget.onLoadMore!,
              onRetry: widget.onRetry,
              child: body,
            );
          }
          // Inside a page's own scroll (the home, categories) the list sizes itself; given a height (favourites)
          // it scrolls.
          final own = box.hasBoundedHeight;
          return CustomScrollView(
            shrinkWrap: !own,
            physics: own
                ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics())
                : const NeverScrollableScrollPhysics(),
            slivers: [
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), sliver: cards),
              if (widget.hasMore)
                SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: Center(child: AppLoadingIndicator())),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
            ],
          );
        }),
      ),
    );
  }
}
