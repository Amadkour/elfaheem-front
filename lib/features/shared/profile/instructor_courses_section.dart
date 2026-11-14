// lib/features/shared/profile/instructor_courses_section.dart
//
// The "Courses" block of the teacher profile students open from a course page or the home's instructor row
// (course_instractor_profile.dart): that teacher's PUBLISHED, PUBLIC, PERSONAL courses — never an organization's.
//
//   InstructorCoursesController  the pages, from the catalogue: GET /api/v1/courses?teacher_id=…&scope=personal
//                                (published, not private, not archived; scope=personal leaves every organization
//                                course out). First page 6, then 12 per "Show more"; paged on `has_more`
//                                (else `total`, else "a full page came back"); a course is never listed twice;
//                                one page request at a time; an answer from before a reload is dropped.
//   InstructorCoursesSection     plain values only (no provider, no API): header + skeleton / empty / error with
//                                Retry / the cards (THE course card, CourseCard → CourseListCard: rows on a phone,
//                                a grid of tiles from 600 px) / "Show more". Tested by the layout harness.
//   InstructorCoursesBlock       the controller drawn as the section; a tap opens the usual course page.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../design/app_kit.dart'
    show appCompactNumber, AppButton, AppShimmer, AppSkeletonBox, AppStatePlate, AppStatusBadge, AppTone;
import '../../../design/app_tokens.dart';
import '../../../utils/widget/app_navigator.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/course_row.dart' show CourseCard;

// ── Data ────────────────────────────────────────────────────────────────────

/// One teacher's public, personal courses, page by page.
class InstructorCoursesController extends ChangeNotifier {
  InstructorCoursesController({required this.teacherId, ApiClient? api, this.firstPage = 6, this.nextPage = 12})
      : _api = api ?? ApiClient();

  final int teacherId;
  final int firstPage;
  final int nextPage;
  final ApiClient _api;

  List<CourseModel> _courses = const [];
  int _skip = 0;
  int? _total;
  int _dropped = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _started = false;
  String? _error;
  int _gen = 0;
  bool _disposed = false;

  List<CourseModel> get courses => _courses;
  bool get hasMore => _hasMore;
  String? get error => _error;

  /// Page 1 in flight (nothing listed yet), or not asked yet.
  bool get loading => (_loading || !_started) && _courses.isEmpty;

  /// A further page in flight below the listed courses.
  bool get loadingMore => _loading && _courses.isNotEmpty;

  /// How many courses the teacher has on this side (null until the server said so).
  int? get total {
    final t = _total;
    if (t == null) return _hasMore ? null : _courses.length;
    return (t - _dropped).clamp(_courses.length, 1 << 30).toInt();
  }

  /// Page 1 again (first open, Retry on an empty list).
  Future<void> load() async {
    _gen++;
    _started = true;
    _courses = const [];
    _skip = 0;
    _total = null;
    _dropped = 0;
    _hasMore = false;
    _error = null;
    await _page(firstPage);
  }

  /// The next page; no-op while a page is in flight or once everything is listed.
  Future<void> loadMore() async {
    if (!_started || _loading || !_hasMore) return;
    await _page(nextPage);
  }

  /// Retry after a failure: page 1 when nothing is listed, else the page that failed.
  Future<void> retry() async {
    if (_loading) return;
    await (_courses.isEmpty ? load() : _page(nextPage));
  }

  Future<void> _page(int limit) async {
    final gen = _gen;
    _loading = true;
    _error = null;
    _notify();
    try {
      final r = await _api.get('/api/v1/courses', queryParams: {
        'skip': _skip,
        'limit': limit,
        'teacher_id': teacherId,
        'scope': 'personal',
      });
      if (gen != _gen || _disposed) return;
      final raw = r is Map && r['items'] is List ? r['items'] as List : null;
      if (raw == null) throw const FormatException('items');
      final page = raw.whereType<Map>().map((m) => CourseModel.fromJson(Map<String, dynamic>.from(m))).toList();
      _skip += page.length;
      final seen = {for (final c in _courses) c.id};
      final fresh = <CourseModel>[];
      for (final c in page) {
        if (!seen.add(c.id)) continue; // rows shifted on the server: never the same course twice
        // an older server without `scope` lists every side: keep the profile to the teacher's own public courses
        if (c.org != null || c.isPrivate || !c.isPublished) {
          _dropped++;
          continue;
        }
        fresh.add(c);
      }
      _courses = [..._courses, ...fresh];
      final total = r['total'];
      final more = r['has_more'];
      _total = total is num ? total.toInt() : null;
      _hasMore = page.isNotEmpty &&
          (more is bool ? more : (total is num ? _skip < total.toInt() : page.length >= limit));
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _error = e is FormatException ? 'failed_to_load'.tr : ApiException.from(e).message;
    } finally {
      if (gen == _gen) _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The controller drawn as [InstructorCoursesSection]; a tap opens the course page (AppNavigator.openCourse).
class InstructorCoursesBlock extends StatelessWidget {
  const InstructorCoursesBlock({super.key, required this.controller});

  final InstructorCoursesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => InstructorCoursesSection(
          courses: controller.courses,
          total: controller.total,
          loading: controller.loading,
          loadingMore: controller.loadingMore,
          error: controller.error,
          hasMore: controller.hasMore,
          onRetry: controller.retry,
          onLoadMore: controller.loadMore,
          onOpen: (c) {
            final id = int.tryParse(c.id);
            if (id != null) AppNavigator.openCourse(id);
          },
        ),
      );
}

// ── View ────────────────────────────────────────────────────────────────────

/// The teacher's courses: header, then skeleton / error / empty / cards, then "Show more". Plain values only.
class InstructorCoursesSection extends StatelessWidget {
  const InstructorCoursesSection({
    super.key,
    required this.courses,
    required this.onOpen,
    required this.onRetry,
    required this.onLoadMore,
    this.total,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<CourseModel> courses;
  final int? total;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final void Function(CourseModel course) onOpen;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (loading) {
      body = const _CoursesSkeleton();
    } else if (courses.isEmpty && error != null) {
      body = CourseListError(message: error!, onRetry: onRetry, margin: EdgeInsets.zero);
    } else if (courses.isEmpty) {
      body = const _CoursesEmpty();
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _CoursesGrid(courses: courses, onOpen: onOpen),
        if (error != null) ...[
          AppSpace.gapSm,
          CourseListError(message: error!, onRetry: onRetry, margin: EdgeInsets.zero),
        ] else if (hasMore) ...[
          AppSpace.gapSm,
          _ShowMore(busy: loadingMore, onTap: onLoadMore),
        ],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Header(count: loading ? null : total),
      SizedBox(height: AppSpace.sectionHead.bottom),
      AnimatedSwitcher(
        duration: AppMotion.of(context).base,
        child: KeyedSubtree(key: ValueKey(loading ? 'loading' : (courses.isEmpty ? 'empty' : 'list')), child: body),
      ),
    ]);
  }
}

/// The profile's section header in the editorial face (a quiet glyph · the title) with the course count beside the
/// title as a small pill; the heading brings no space above itself (the page sets the rhythm).
class _Header extends StatelessWidget {
  const _Header({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(Icons.menu_book_rounded, color: c.textMedium, size: AppIconSize.md),
      const SizedBox(width: AppSpace.xs),
      Flexible(
        child: Semantics(
          header: true,
          child: Text('courses'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        ),
      ),
      if (count != null && count! > 0) ...[
        const SizedBox(width: AppSpace.xs),
        AppStatusBadge(label: appCompactNumber(count!), tone: AppTone.neutral, dense: true),
      ],
    ]);
  }
}

/// Rows on a phone, a grid of tiles from 600 px (the course lists' own CourseCardSliver).
class _CoursesGrid extends StatelessWidget {
  const _CoursesGrid({required this.courses, required this.onOpen});

  final List<CourseModel> courses;
  final void Function(CourseModel course) onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => CustomScrollView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            CourseCardSliver(
              width: box.maxWidth,
              count: courses.length,
              itemBuilder: (context, i, shape) => CourseCard(
                key: ValueKey('instructor-course-${courses[i].id}'),
                course: courses[i],
                isTeacher: false,
                shape: shape,
                pageName: 'instructor_profile',
                onTap: onOpen,
              ),
            ),
          ],
        ),
      );
}

/// "Show more courses": a quiet full-width outline button, a small spinner while the page loads.
class _ShowMore extends StatelessWidget {
  const _ShowMore({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppButton.secondary(
        expand: true,
        busy: busy,
        label: 'instructor_courses_more'.tr,
        onPressed: busy ? null : onTap,
      );
}

/// The teacher has no public course yet: one calm line in a hairline card.
class _CoursesEmpty extends StatelessWidget {
  const _CoursesEmpty();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.lg),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const AppStatePlate(icon: Icons.menu_book_rounded, size: AppTouch.min * 2),
        const SizedBox(height: AppSpace.sm),
        Text(
          'instructor_courses_empty'.tr,
          textAlign: TextAlign.center,
          style: AppType.body(context).copyWith(height: 1.5),
        ),
      ]),
    );
  }
}

/// Two placeholders in the card's own shape (rows on a phone, tiles in a grid).
class _CoursesSkeleton extends StatelessWidget {
  const _CoursesSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final shape = courseCardShapeFor(box.maxWidth);
      final deco = BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      );
      Widget lines(int i) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            AppSkeletonBox(width: 120.0 + (i * 37) % 70, height: 13),
            const SizedBox(height: AppSpace.xs),
            AppSkeletonBox(width: 80.0 + (i * 23) % 50, height: 10),
            const SizedBox(height: AppSpace.md),
            const AppSkeletonBox(width: 64, height: 12),
          ]);
      Widget card(int i) => shape == CourseCardShape.row
          ? Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: deco,
              child: Row(children: [
                const AppSkeletonBox(width: 104, height: 80, radius: AppRadius.control),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: lines(i)),
              ]),
            )
          : Container(
              decoration: deco,
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                const AspectRatio(aspectRatio: 16 / 9, child: AppSkeletonBox(radius: 0)),
                Padding(padding: const EdgeInsets.all(AppSpace.md), child: lines(i)),
              ]),
            );
      final count = shape == CourseCardShape.row ? 2 : courseGridColumns(box.maxWidth);
      return AppShimmer(
        child: CustomScrollView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          slivers: [CourseCardSliver(width: box.maxWidth, count: count, itemBuilder: (_, i, _) => card(i))],
        ),
      );
    });
  }
}
