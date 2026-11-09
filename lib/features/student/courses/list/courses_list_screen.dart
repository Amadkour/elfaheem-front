/// courses_list_screen.dart
/// Two lists behind one look:
///   • forMyCourses: the student's own enrolments (MyCoursesProvider, seeded with the home's list);
///   • otherwise the CATALOGUE — "Explore other courses" and the home's search box (H5): GET /api/v1/courses through
///     CoursesProvider, searched on the server; courses the student already follows are left out until they search.
library;

import 'dart:async';

import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/design/app_kit.dart' show AppEmpty, AppListSkeleton;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/student/courses/list/courses_provider.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart' as Helpers;
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/paged_progress.dart';
import '../../../../utils/widget/search_text_field.dart';
import '../../models.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;

class CoursesListScreen extends StatefulWidget {
  const CoursesListScreen({
    super.key,
    this.openSearch = false,
    required this.homeCourses,
    required this.forMyCourses,
  });

  final List<CourseModel> homeCourses;
  final bool forMyCourses;
  final bool openSearch;

  @override
  State<CoursesListScreen> createState() => _CoursesListScreenState();
}

class _CoursesListScreenState extends State<CoursesListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.forMyCourses) {
        context.read<MyCoursesProvider>().init(widget.homeCourses);
      } else {
        context.read<CoursesProvider>().fetchCourses();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    if (widget.forMyCourses) {
      context.read<MyCoursesProvider>().setQuery(q);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = q.trim());
      context.read<CoursesProvider>().fetchCourses(search: _query.isEmpty ? null : _query);
    });
  }

  String? get _search => _query.isEmpty ? null : _query;

  @override
  Widget build(BuildContext context) {
    final mine = widget.forMyCourses;
    final List<CourseModel> courses;
    final bool loading, error, hasMore, loadingMore;
    var loadFailed = false;
    Future<void> Function()? retry;
    final int loaded, total;
    final String? errorText;
    final Future<void> Function() refresh;
    final Future<void> Function() loadMore;
    if (mine) {
      final p = context.watch<MyCoursesProvider>();
      courses = p.filteredCourses;
      loading = p.isLoading && p.allCourses.isEmpty;
      error = p.hasError && p.allCourses.isEmpty;
      errorText = p.errorMessage;
      hasMore = p.hasMore;
      loadingMore = p.isLoadingMore;
      loaded = p.allCount;
      total = p.total;
      refresh = p.refresh;
      loadMore = p.loadMore;
      loadFailed = p.pageFailed;
      retry = () => p.loadMore(retry: true);
    } else {
      final p = context.watch<CoursesProvider>();
      // exploring = what the student does not follow yet; a search finds every match
      courses = _search == null ? p.explorHomecourses : p.courses;
      loading = p.isLoading && p.courses.isEmpty;
      error = p.hasError && p.courses.isEmpty;
      errorText = p.errorMessage;
      hasMore = p.hasMore;
      loadingMore = p.isLoadingMore;
      loaded = p.courses.length;
      total = p.total;
      loadFailed = p.pageFailed;
      // page 1's filter is kept by the provider for every next page (and for a mode switch's reload)
      refresh = () => p.fetchCourses(search: _search);
      loadMore = p.loadMore;
      retry = () => p.loadMore(retry: true);
    }
    final shownTotal = total > loaded ? total : loaded;
    return BasePage(
      key: const ValueKey('courses_list'),
      useWebCard: true,
      width: AppWidth.wide,
      enableFooterWidget: false,
      appBar: ScreenAppBar(
        title: mine ? 'my_courses'.tr : (widget.openSearch ? 'search'.tr : 'explorer_courses'.tr),
      ),
      child: SafeArea(
        child: Column(
          children: [
            ParentComponent(
              featureKey: 'courses_list.search',
              // a search box reads best at a form's width, even on a wide window
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                  child: MySearchBar(
                    controller: _searchCtrl,
                    hint: 'search_course_by_name_description',
                    onChanged: _onQuery,
                  ),
                ),
              ),
            ),
            if (loaded > 0 && (total > 0 || !hasMore) && shownTotal > 20)
              PagedCountCard(
                loaded: loaded,
                total: shownTotal,
                loadingMore: loadingMore,
                done: !hasMore,
                icon: Icons.library_books_rounded,
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              ),
            Expanded(
              child: loading
                  ? const AppListSkeleton()
                  : error
                  ? ErrorRetry(message: errorText ?? 'retry'.tr, onRetry: refresh)
                  : (courses.isEmpty && !hasMore)
                  ? AppEmpty(
                icon: Icons.menu_book_rounded,
                title: 'no_courses_in_section'.tr,
              )
                  : ParentComponent(
                featureKey: 'courses_list.list',
                child: HomeCourseList(
                  hasMore: hasMore,
                  courses: courses,
                  loadingMore: loadingMore,
                  loadFailed: loadFailed,
                  onLoadMore: loadMore,
                  onRetry: retry,
                  onRefresh: refresh,
                  onTap: (CourseModel c) {
                    Navigator.pushNamed(context, '/course-detail',
                        arguments: c);
                  },
                  isTeacher: false,
                  maxWidth: AppWidth.wide.max,
                  pageName: mine
                      ? 'my-courses-profile'
                      : 'other-courses-profile',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
