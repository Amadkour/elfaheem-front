library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherCourseStatus, TeacherCourse;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/app_bar.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../home/teacher_home_provider.dart';
import '../schedules/schedules_screen.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';
import 'course_form_screen.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final courses = context.read<TeacherCoursesProvider>();
    // Any mutation made from this screen (create/update/publish/delete)
    // marks the home dashboard's stats + course preview stale, so it
    // refetches next time it's shown — without a hard dependency between
    // the two providers.
    courses.onCoursesChanged =
        () => context.read<TeacherHomeProvider>().refreshSilently();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (courses.allCourses.isEmpty) courses.fetchPage(0);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherCoursesProvider>();

    return BasePage(
      useWebCard: true,
      appBar: ScreenAppBar(
        title: '${'my_courses'.tr} '
            '${p.totalCount > 0 ? p.totalCount : p.filteredCourses.length}',
        showBack: !kIsWeb,
      ),
      floatingActionButton: context.showSidebar ? null : _FloatingAddBtn(),
      child: SafeArea(
        bottom: false,
        child: p.isLoading && p.allCourses.isEmpty
            ? Center(child: AppLoadingIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            _CourseSearchBar(controller: _searchCtrl, p: p),
            const SizedBox(height: 10),
            _FilterTabs(p: p),
            const SizedBox(height: 10),
            Expanded(child: _CourseList(p: p)),
            _PaginationFooter(p: p),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Header variants
// ═══════════════════════════════════════════════════════════════════════════════

class _WebHeader extends StatelessWidget {
  const _WebHeader();

  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text('my_courses'.tr, style: context.colors.h2.copyWith(fontSize: 17)),
        const Spacer(),
        _AddCourseButton(compact: false),
      ],
    ),
  );
}

class _FloatingAddBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FloatingActionButton(
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CourseFormScreen())),
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: context.colors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: context.colors.primaryShadow,
      ),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );
}

class _AddCourseButton extends StatelessWidget {
  final bool compact;

  const _AddCourseButton({required this.compact});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CourseFormScreen())),
    child: Container(
      height: 38,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
      decoration: BoxDecoration(
        gradient: context.colors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            compact ? 'add'.tr : 'add_course'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'bahji',
            ),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Filter tabs
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Search bar — server-side search by course name/description, debounced in
//  TeacherCoursesProvider.setQuery so it re-fetches page 1 shortly after the
//  teacher stops typing rather than filtering the (partial) loaded page.
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseSearchBar extends StatefulWidget {
  const _CourseSearchBar({required this.controller, required this.p});

  final TextEditingController controller;
  final TeacherCoursesProvider p;

  @override
  State<_CourseSearchBar> createState() => _CourseSearchBarState();
}

class _CourseSearchBarState extends State<_CourseSearchBar> {
  @override
  void initState() {
    super.initState();
    // Local listener (independent of provider rebuilds) so the clear "×"
    // button appears/disappears immediately as the teacher types, rather
    // than waiting for the search debounce to fire.
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final p = widget.p;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 19, color: context.colors.textLight),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: (v) => p.setQuery(v),
                textInputAction: TextInputAction.search,
                style: context.colors.label.copyWith(color: context.colors.textDark),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'search_course_by_name_description'.tr,
                  hintStyle: context.colors.label.copyWith(
                    color: context.colors.textLight,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  p.setQuery('');
                },
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.colors.textLight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.p});

  final TeacherCoursesProvider p;
  static const _tabs = [
    (TeacherCourseStatus.all, 'filter_all', Icons.apps_rounded),
    (TeacherCourseStatus.published, 'filter_published', Icons.public_rounded),
    (TeacherCourseStatus.draft, 'filter_drafts', Icons.drafts_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: _tabs.map((t) {
            final (status, labelKey, icon) = t;
            final active = p.activeFilter == status;
            return Expanded(
              child: GestureDetector(
                onTap: () => context.read<TeacherCoursesProvider>().setFilter(status),
                child: Container(
                  //  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    // gradient: active ? context.colors.primaryGradient : null,
                    border: active
                        ? Border(
                      bottom: BorderSide(
                        color: context.colors.primary,
                        width: 1,
                      ),
                    )
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 13,
                          color: active
                              ? context.colors.primary
                              : context.colors.textLight,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          labelKey.tr,
                          style: context.colors.label.copyWith(
                            color: active
                                ? context.colors.primary
                                : context.colors.textLight,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course list
//  Web → _TwoColumnMasonry (self-sizing, no childAspectRatio)
//  Mobile → plain ListView
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseList extends StatelessWidget {
  const _CourseList({required this.p});

  final TeacherCoursesProvider p;

  @override
  Widget build(BuildContext context) {
    final isWide = context.showSidebar;

    if (p.isLoading && p.filteredCourses.isEmpty) {
      return Center(child: AppLoadingIndicator());
    }

    final courses = p.filteredCourses;
    if (courses.isEmpty) return const _EmptyState();

    return RefreshIndicator(
      color: context.colors.primary,
      // force: true — pull-to-refresh means "get me the latest", not
      // "show me what I last saw", so it must bypass the page cache.
      onRefresh: () => p.fetchPage(p.currentPage, force: true),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: isWide
              ? _TwoColumnMasonry(courses: courses)
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            physics: const BouncingScrollPhysics(),
            itemCount: courses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, i) => _CourseCard(course: courses[i]),
          ),
        ),
      ),
    );
  }
}

/// Two-column masonry: splits courses into left/right lists so each card
/// sizes itself naturally — no fixed childAspectRatio, no overflow.
class _TwoColumnMasonry extends StatelessWidget {
  final List<TeacherCourse> courses;

  const _TwoColumnMasonry({required this.courses});

  @override
  Widget build(BuildContext context) {
    final left = <TeacherCourse>[];
    final right = <TeacherCourse>[];
    for (var i = 0; i < courses.length; i++) {
      (i.isEven ? left : right).add(courses[i]);
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: left
                  .map(
                    (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _CourseCard(course: c),
                ),
              )
                  .toList(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: right
                  .map(
                    (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _CourseCard(course: c),
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Empty state
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  context.colors.primaryLight.withValues(alpha: 0.5),
                  context.colors.primaryLight.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.school_outlined,
              size: 40,
              color: context.colors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'no_courses_section'.tr,
            style: context.colors.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'add_first_course_hint'.tr,
            style: context.colors.caption.copyWith(
              color: context.colors.textLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CourseFormScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: context.colors.primaryShadow,
              ),
              child: Text(
                'add_new_course'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'bahji',
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course card
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseCard extends StatefulWidget {
  final TeacherCourse course;

  const _CourseCard({required this.course});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _expanded = false;

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: Helpers.pageDirection,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'delete_course'.tr,
            style: const TextStyle(
              fontFamily: 'bahji',
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            '${'delete_course_confirm'.tr} "${widget.course.title}"؟',
            style: const TextStyle(fontFamily: 'bahji'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'cancel'.tr,
                style: TextStyle(
                  fontFamily: 'bahji',
                  color: context.colors.textMedium,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: context.colors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'delete'.tr,
                  style: const TextStyle(
                    fontFamily: 'bahji',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final deleted = await context.read<TeacherCoursesProvider>().deleteCourse(
        widget.course.id,
      );
      if (mounted && deleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'course_deleted'.tr,
              style: const TextStyle(fontFamily: 'bahji', color: Colors.white),
            ),
            backgroundColor: context.colors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _togglePublish() async {
    final p = context.read<TeacherCoursesProvider>();
    await (widget.course.isPublished
        ? p.unpublishCourse(widget.course.id)
        : p.publishCourse(widget.course.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final isDraft = !c.isPublished;
    final statusColor =
    isDraft ? const Color(0xFFf59e0b) : context.colors.accent2;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: statusColor.withValues(alpha: 0.32), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Full-width 16:9 thumbnail with a bottom gradient scrim and
          //    floating status / type / rating chips ────────────────────
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AppNetworkImage(
                  url: c.imageUrl,
                  width: double.infinity,
                  borderRadius: BorderRadius.zero,
                  heroTag: "courses-screen-${c.id}",
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.55, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: _GlassChip(
                  icon: c.type == 'live'
                      ? Icons.podcasts_rounded
                      : Icons.play_circle_fill_rounded,
                  label: c.type == 'live' ? 'live'.tr : 'recorded'.tr,
                  dark: true,
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _GlassChip(
                  icon: isDraft ? Icons.drafts_rounded : Icons.public_rounded,
                  label: isDraft ? 'status_draft'.tr : 'status_published'.tr,
                  color: statusColor,
                ),
              ),
              if (c.rateSummary != null)
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: _GlassChip(
                    icon: Icons.star_rounded,
                    label: c.rateSummary!.average.toStringAsFixed(1),
                    color: context.colors.accent,
                    dark: true,
                  ),
                ),
            ],
          ),

          // ── Title + stats ────────────────────────────────────────────
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider(
                  create: (_) => TeacherCourseScreenProvider(initialCourse: c),
                  child: TeacherSessionsScreen(),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.title,
                    style: context.colors.h3.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // 2×2 stats grid — deterministic height, no Wrap
                  _StatsGrid(course: c),
                ],
              ),
            ),
          ),

          // ── Expand toggle ────────────────────────────────────────────
          InkWell(
            onTap: () {
              if (mounted) setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'hide_details'.tr : 'show_details'.tr,
                    style: context.colors.label.copyWith(
                      color: context.colors.primary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable extras ────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            child: _expanded
                ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.07),
                ),
                _ExtrasPanel(course: c),
              ],
            )
                : const SizedBox.shrink(),
          ),

          Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),

          // ── Premium management toolbar ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _ToolbarAction(
                    icon: Icons.edit_rounded,
                    label: 'edit'.tr,
                    color: context.colors.primary,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CourseFormScreen(course: c),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _ToolbarAction(
                    icon: isDraft
                        ? Icons.upload_rounded
                        : Icons.visibility_off_rounded,
                    label: isDraft ? 'publish_course'.tr : 'unpublish_course'.tr,
                    color: statusColor,
                    filled: true,
                    onTap: _togglePublish,
                  ),
                ),
                const SizedBox(width: 8),
                _ToolbarAction(
                  icon: Icons.delete_rounded,
                  color: Colors.red,
                  onTap: _confirmDelete,
                  iconOnly: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Stats — 2×2 fixed grid so height is always deterministic
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  final TeacherCourse course;

  const _StatsGrid({required this.course});

  @override
  Widget build(BuildContext context) {
    final c = course;
    final rows = [
      [
        (
        Icons.people_alt_rounded,
        '${c.studentsCount} ${'student'.tr}',
        context.colors.primary,
        ),
        (
        Icons.video_library_rounded,
        '${c.sessionsCount} ${'session'.tr}',
        const Color(0xFF185FA5),
        ),
      ],
      [
        (
        Icons.access_time_rounded,
        '${c.totalHours.toStringAsFixed(0)}${'h'.tr}',
        const Color(0xFFBA7517),
        ),
        (
        Icons.star_rounded,
        c.rateSummary?.average.toStringAsFixed(1),
        context.colors.accent,
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        final isLast = row == rows.last;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
          child: Row(
            children: row.map((item) {
              final (icon, label, color) = item;
              final isLastInRow = item == row.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: isLastInRow ? 0 : 4),
                  child: _StatCell(icon, label ?? '', color),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatCell(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: context.colors.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Glass chip — floats on top of the thumbnail (status / type / rating)
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool dark;

  const _GlassChip({
    required this.icon,
    required this.label,
    this.color,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? Colors.black.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: dark ? 0.55 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: dark ? Colors.white : c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: dark ? Colors.white : c,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Toolbar action — one button in the card's bottom management bar
// ═══════════════════════════════════════════════════════════════════════════════

class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final bool iconOnly;

  const _ToolbarAction({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: filled ? Colors.white : color),
        if (!iconOnly && label != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : color,
              ),
            ),
          ),
        ],
      ],
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        width: iconOnly ? 42 : null,
        padding: iconOnly ? null : const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
        ),
        alignment: Alignment.center,
        child: content,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Extras panel
// ═══════════════════════════════════════════════════════════════════════════════

class _ExtrasPanel extends StatelessWidget {
  final TeacherCourse course;

  const _ExtrasPanel({required this.course});

  @override
  Widget build(BuildContext context) {
    final hasContent =
        course.schedules.isNotEmpty ||
            course.certificates.isNotEmpty ||
            course.tools.isNotEmpty ||
            course.prerequisites.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasContent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'no_extra_details'.tr,
                style: context.colors.caption.copyWith(
                  color: context.colors.textLight,
                ),
              ),
            ),
          if (course.schedules.isNotEmpty)
            _ExtRow(
              Icons.calendar_month_rounded,
              'weekly_schedule'.tr,
              course.schedules
                  .map((s) => '${s.dayLabel}  ${s.startTime} – ${s.endTime}')
                  .toList(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeacherSchedulesScreen(course: course),
                ),
              ),
            ),
          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.workspace_premium_rounded,
              'certificates'.tr,
              course.certificates.map((c) => c.title).toList(),
            ),
          ],
          if (course.tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.build_rounded,
              'required_tools'.tr,
              course.tools.map((t) => t.name).toList(),
            ),
          ],
          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.checklist_rounded,
              'prerequisites'.tr,
              course.prerequisites.map((p) => p.title).toList(),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ExtRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> items;
  final VoidCallback? onTap;

  const _ExtRow(this.icon, this.label, this.items, {this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 13, color: context.colors.primary),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: context.colors.label.copyWith(
                  color: context.colors.primary,
                  fontSize: 12,
                ),
              ),
            ),
            if (onTap != null)
              Icon(
                CupertinoIcons.settings,
                size: 16,
                color: context.colors.primary,
              ),
          ],
        ),
        const SizedBox(height: 5),
        ...items
            .take(3)
            .map(
              (item) => Padding(
            padding: const EdgeInsets.only(right: 29, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.colors.textLight,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(child: Text(item, style: context.colors.caption)),
              ],
            ),
          ),
        ),
        if (items.length > 3)
          Padding(
            padding: const EdgeInsets.only(right: 29, top: 2),
            child: Text(
              '+ ${items.length - 3} ${'others'.tr}',
              style: context.colors.caption.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Pagination footer — page arrows + indicator, shared by web and mobile
// ═══════════════════════════════════════════════════════════════════════════════
//
// The `/api/v1/my-courses` endpoint takes skip/limit but returns a plain
// list with no total-count field, so "is there a next page" is inferred
// from whether the last fetch returned a full page (see
// TeacherCoursesProvider.hasMore). That's enough to drive simple
// prev/next arrows without over-claiming a page count we don't have.

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.p});

  final TeacherCoursesProvider p;

  @override
  Widget build(BuildContext context) {
    // Nothing to paginate yet (empty first page, still on page 0, no more
    // to come) — skip the footer entirely rather than showing dead arrows.
    // Once the server has reported a total (totalCount > 0) this is exact;
    // otherwise it falls back to the previous "was the last page empty"
    // heuristic, kept for a not-yet-updated server (see fetchMyCourses).
    final noPages = p.totalCount > 0 ? p.totalPages <= 1 && p.allCourses.isEmpty
        : (p.currentPage == 0 && !p.hasMore && p.allCourses.isEmpty);
    if (noPages) {
      return const SizedBox.shrink();
    }

    final busy = p.isLoading;
    final isFirst = p.currentPage == 0;
    final isLast = !p.hasMore;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(29),
                border: Border.all(
                  color: context.colors.primary.withValues(alpha: 0.14),
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.primary.withValues(alpha: 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _PageArrow(
                    icon: Icons.chevron_left_rounded,
                    enabled: !isFirst && !busy,
                    onTap: () => p.goToPreviousPage(),
                  ),
                  Expanded(
                    child: Center(
                      child: busy
                          ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: context.colors.primary,
                        ),
                      )
                          : _PagePill(
                        page: p.currentPage,
                        totalPages: p.totalCount > 0 ? p.totalPages : null,
                      ),
                    ),
                  ),
                  _PageArrow(
                    icon: Icons.chevron_right_rounded,
                    enabled: !isLast && !busy,
                    onTap: () => p.goToNextPage(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PagePill extends StatelessWidget {
  const _PagePill({required this.page, this.totalPages});

  final int page;

  /// Total number of pages, from the server's total count. Null while that
  /// isn't known yet (e.g. a not-yet-updated server) — shows just the
  /// current page number in that case, same as before this change.
  final int? totalPages;

  @override
  Widget build(BuildContext context) {
    final total = totalPages;
    final label = total != null
        ? '${'page_word'.tr} ${page + 1} ${'of_word'.tr} $total'
        : '${'page_word'.tr} ${page + 1}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: context.colors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'bahji',
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PageArrow extends StatelessWidget {
  const _PageArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.35,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: context.colors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Icon(icon, size: 22, color: context.colors.primary),
      ),
    ),
  );
}