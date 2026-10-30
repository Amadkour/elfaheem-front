import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import '../../student/courses/details/components/app_responsive.dart';
import 'course_list_card.dart';
import 'course_row.dart';
import 'package:flutter_education_app/design/app_refresh.dart';

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
    this.badgeFor,
  });

  /// A small mark drawn over each card's picture (under the favourite heart) — e.g. where the course lives when
  /// the list mixes the personal account and organizations. Null (or a null result) draws nothing.
  final Widget? Function(CourseModel course)? badgeFor;

  final String pageName;
  final List<CourseModel> courses;
  final bool hasMore;
  final void Function(CourseModel course) onTap;
  final bool isTeacher;

  /// Passing this turns on view-as style pagination (scroll trigger, footer, pull-to-refresh).
  /// Without it the list behaves exactly as before (used by the home screen).
  final VoidCallback? onLoadMore;
  final Future<void> Function()? onRefresh;
  final bool loadingMore;

  @override
  State<HomeCourseList> createState() => _HomeCourseListState();
}

class _HomeCourseListState extends State<HomeCourseList> {
  final _scroll = ScrollController();

  bool get _paged => widget.onLoadMore != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _fillViewport();
  }

  @override
  void didUpdateWidget(covariant HomeCourseList old) {
    super.didUpdateWidget(old);
    _fillViewport();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Near the bottom → fetch the next page automatically.
  void _onScroll() {
    if (!_paged || widget.loadingMore || !widget.hasMore) return;
    if (_scroll.hasClients && _scroll.position.extentAfter < 320) {
      widget.onLoadMore!();
    }
  }

  /// If the loaded pages don't fill the screen there is nothing to scroll, so keep loading.
  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_paged || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0 &&
          widget.hasMore &&
          !widget.loadingMore) {
        widget.onLoadMore!();
      }
    });
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
        constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
        child: LayoutBuilder(builder: (context, box) {
          // rows on a phone, a grid of tiles once there is room (course_list_card.dart)
          final width = math.max(0.0, box.maxWidth - 32);
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
                SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), sliver: cards),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PagedListFooter(loadingMore: widget.loadingMore, hasMore: widget.hasMore),
                  ),
                ),
              ],
            );
            if (widget.onRefresh != null) body = AppRefresh(onRefresh: widget.onRefresh!, child: body);
            return body;
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
              SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), sliver: cards),
              if (widget.hasMore)
                SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(16), child: Center(child: AppLoadingIndicator())),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        }),
      ),
    );
  }
}
