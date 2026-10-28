import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import '../../student/courses/details/components/app_responsive.dart';
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
  });

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

  Widget _card(CourseModel c) => CourseCard(
    course: c,
    pageName: widget.pageName,
    fixedWidth: 188,
    isTeacher: widget.isTeacher,
    fullScreen: true,
    onTap: (CourseModel c) => widget.onTap.call(c),
  );

  @override
  Widget build(BuildContext context) {
    final cols = context.screenW >= 700 ? 3 : 2;
    // Cell height is computed from the card's own content (image + info area)
    // instead of a fixed aspect ratio, so nothing overflows or wastes space.
    final gridW = math.min(context.screenW, Breakpoints.contentMax);
    final cellW = (gridW - 40 - 14 * (cols - 1)) / cols;
    final delegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      mainAxisExtent: CourseCard.cellHeight(context, cellW),
    );

    Widget body;
    if (_paged) {
      body = CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            sliver: SliverGrid(
              gridDelegate: delegate,
              delegate: SliverChildBuilderDelegate(
                    (_, i) => _card(widget.courses[i]),
                childCount: widget.courses.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PagedListFooter(
                loadingMore: widget.loadingMore,
                hasMore: widget.hasMore,
              ),
            ),
          ),
        ],
      );
      if (widget.onRefresh != null) {
        body = AppRefresh(onRefresh: widget.onRefresh!, child: body);
      }
    } else {
      // Old behaviour (home screen etc.)
      body = GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: delegate,
        itemCount: widget.courses.length + (widget.hasMore ? 1 : 0),
        itemBuilder: (_, i) => i >= widget.courses.length
            ? Center(child: AppLoadingIndicator())
            : _card(widget.courses[i]),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Breakpoints.contentMax),
        child: body,
      ),
    );
  }
}