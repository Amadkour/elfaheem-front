/// courses_list_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../../utils/widget/base_page.dart';
import '../../models.dart';
import '../details/components/app_responsive.dart';
import '../details/course_detail_screen.dart';
import 'courses_provider.dart';

class CoursesListScreen extends StatefulWidget {
  const CoursesListScreen({super.key, this.openSearch = false});

  final bool openSearch;

  @override
  State<CoursesListScreen> createState() => _CoursesListScreenState();
}

class _CoursesListScreenState extends State<CoursesListScreen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.openSearch) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String q) => context.read<CoursesProvider>().fetchCourses(
        search: q.trim().isEmpty ? null : q.trim(),
      );

  void _clearSearch() {
    _searchCtrl.clear();
    context.read<CoursesProvider>().fetchCourses();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      child: SafeArea(
        child: Column(
          children: [
            // Only show app-bar on mobile (web uses sidebar topbar)
              ScreenAppBar(title: 'explorer_courses'.tr),

            ContentBox(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              child: _SearchBar(
                controller: _searchCtrl,
                focusNode: _focusNode,
                onChanged: _onSearch,
                onClear: _clearSearch,
              ),
            ),
            const SizedBox(height: 14),
            const Expanded(child: _CourseList()),
          ],
        ),
      ),
    );
  }
}
// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textDirection: TextDirection.rtl,
          onChanged: onChanged,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: context.colors.textDark),
          decoration: InputDecoration(
            hintText: 'بحث عن كورس...',
            hintStyle: context.colors.caption.copyWith(fontSize: 14),
            hintTextDirection: TextDirection.rtl,
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.search_rounded,
                  color: context.colors.primary, size: 18),
            ),
            suffixIcon: ListenableBuilder(
              listenable: controller,
              builder: (_, __) => controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: context.colors.textLight, size: 18),
                      onPressed: onClear)
                  : const SizedBox.shrink(),
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      );
}

// ── Course list ───────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CoursesProvider>();
    final w = context.screenW;
    final cols = w >= 1100 ? 3 : (w >= 700 ? 2 : 1);
    final isGrid = cols > 1;

    if (provider.isLoading && provider.courses.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.colors.primary),
          strokeWidth: 2.5,
        ),
      );
    }

    if (!provider.isLoading && provider.courses.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        message: 'لا توجد كورسات',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          provider.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        color: context.colors.primary,
        onRefresh: provider.fetchCourses,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            // child: isGrid
            child: isGrid
                ? GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 2.3,
                    ),
                    itemCount:
                        provider.courses.length + (provider.hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= provider.courses.length) {
                        return Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation(context.colors.primary),
                            strokeWidth: 2,
                          ),
                        );
                      }
                      return _CourseCard(course: provider.courses[i]);
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    physics: const BouncingScrollPhysics(),
                    itemCount:
                        provider.courses.length + (provider.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i == provider.courses.length) {
                        return Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  context.colors.primary),
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      }
                      return _CourseCard(course: provider.courses[i]);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  final CourseModel course;

  const _CourseCard({required this.course});

  void _open(BuildContext ctx) => Navigator.of(ctx).push(
        MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)),
      );

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Thumbnail column
              SizedBox(
                width: 104,
                height: context.height / 7,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    AppNetworkImage(
                      url: course.imageUrl,
                      width: 104,
                      height: double.infinity,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.32),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 0,
                      left: 0,
                      child: Center(
                        child: _PricePill(price: course.price),
                      ),
                    ),
                  ],
                ),
              ),

              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        _TypeTag(type: course.type),
                        if (course.categoryName != null) ...[
                          const SizedBox(width: 6),
                          _CatTag(label: course.categoryName!),
                        ],
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        course.title,
                        style: context.colors.h3.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (course.instructorName.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: context.colors.primary
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                course.instructorName[0],
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: context.colors.primary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'أ. ${course.instructorName}',
                              style:
                                  context.colors.caption.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          _MetaItem(
                            Icons.star_rounded,
                            course.rate?.toStringAsFixed(1) ?? '–',
                            color: context.colors.accent,
                          ),
                          _MetaItem(Icons.people_rounded,
                              '${course.studentsCount} طالب'),
                          if (course.sessions.isNotEmpty)
                            _MetaItem(Icons.video_library_rounded,
                                '${course.sessions.length} محاضرة'),
                          if (course.hoursCount > 0)
                            _MetaItem(Icons.access_time_rounded,
                                '${course.hoursCount} ساعة'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.chevron_left_rounded,
                    color: context.colors.textLight, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final num price;

  const _PricePill({required this.price});

  @override
  Widget build(BuildContext context) {
    final isFree = price == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isFree ? const Color(0xFF0F6E56) : context.colors.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: (isFree ? const Color(0xFF0F6E56) : context.colors.primary)
                .withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        isFree ? 'مجاني' : '\$${price.toStringAsFixed(0)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String type;

  const _TypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final isLive = type == 'live';
    final c = isLive ? context.colors.danger : context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLive ? Icons.sensors_rounded : Icons.play_arrow_rounded,
            size: 10,
            color: c,
          ),
          const SizedBox(width: 3),
          Text(
            isLive ? 'مباشر' : 'مسجّل',
            style: context.colors.caption
                .copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _CatTag extends StatelessWidget {
  final String label;

  const _CatTag({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.colors.primaryLight.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: context.colors.caption.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 10),
        ),
      );
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? context.colors.textLight),
          const SizedBox(width: 3),
          Text(label, style: context.colors.caption.copyWith(fontSize: 11)),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.primaryLight.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: context.colors.primary),
            ),
            const SizedBox(height: 16),
            Text(message,
                style:
                    context.colors.body.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
