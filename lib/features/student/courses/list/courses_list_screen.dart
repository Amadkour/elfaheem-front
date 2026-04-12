/// courses_list_screen.dart  —  v3.2.0
/// Shows averageRating, sessionsCount on cards.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../models.dart';
import '../details/course_detail_provider.dart';
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
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String q) => context
      .read<CoursesProvider>()
      .fetchCourses(search: q.trim().isEmpty ? null : q.trim());

  void _clearSearch() {
    _searchCtrl.clear();
    context.read<CoursesProvider>().fetchCourses();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'استكشف الكورسات'),
            const SizedBox(height: 4),
            _SearchBar(
                controller: _searchCtrl,
                focusNode: _focusNode,
                onChanged: _onSearch,
                onClear: _clearSearch),
            const SizedBox(height: 12),
            const Expanded(child: _CourseList()),
          ]),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar(
      {required this.controller,
      required this.focusNode,
      required this.onChanged,
      required this.onClear});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            boxShadow: AppTheme.cardShadow,
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textDirection: TextDirection.rtl,
            onChanged: onChanged,
            style: const TextStyle(fontFamily: 'bahji', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'بحث عن كورس...',
              hintStyle: AppTheme.caption.copyWith(fontSize: 14),
              hintTextDirection: TextDirection.rtl,
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppTheme.textLight),
              suffixIcon: ListenableBuilder(
                listenable: controller,
                builder: (_, __) => controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppTheme.textLight, size: 20),
                        onPressed: onClear)
                    : const SizedBox.shrink(),
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      );
}

class _CourseList extends StatelessWidget {
  const _CourseList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CoursesProvider>();

    if (provider.isLoading && provider.courses.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primary)));
    }
    if (!provider.isLoading && provider.courses.isEmpty) {
      return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded, size: 64, color: AppTheme.textLight),
        SizedBox(height: 12),
        Text('لا توجد كورسات', style: AppTheme.body),
      ]));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          provider.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () => provider.fetchCourses(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          physics: const BouncingScrollPhysics(),
          itemCount: provider.courses.length + (provider.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) {
            if (i == provider.courses.length) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(AppTheme.primary))));
            }
            return _CourseCard(course: provider.courses[i]);
          },
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseModel course;

  const _CourseCard({required this.course});

  void _openDetail(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            course: course,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(children: [
          AppNetworkImage(
              url: course.imageUrl,
              width: 100,
              height: 110,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(AppTheme.radiusMedium),
                bottomRight: Radius.circular(AppTheme.radiusMedium),
              )),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                      style: AppTheme.h3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(course.instructorName, style: AppTheme.caption),
                  const SizedBox(height: 6),
                  // Stats row
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    _MetaChip(Icons.star_rounded,
                        course.rate?.toStringAsFixed(1) ?? '',
                        color: AppTheme.accent),
                    _MetaChip(
                        Icons.people_rounded, '${course.studentsCount} طالب'),
                    if (course.sessions.isNotEmpty)
                      _MetaChip(Icons.video_library_rounded,
                          '${course.sessions.length} محاضرة'),
                    _MetaChip(Icons.access_time_rounded,
                        '${course.hoursCount.toStringAsFixed(0)} ساعه'),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    _TypeBadge(type: course.type),
                    const Spacer(),
                    Text(
                      course.price == 0
                          ? 'مجاني'
                          : '\$ ${course.price.toStringAsFixed(2)}',
                      style: AppTheme.h3.copyWith(
                        color: course.price == 0
                            ? AppTheme.success
                            : AppTheme.accent,
                        fontSize: 14,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.chevron_left_rounded, color: AppTheme.textLight),
          ),
        ]),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip(this.icon, this.label, {this.color = AppTheme.textLight});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: AppTheme.caption),
      ]);
}

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isLive = type == 'live';
    final color = isLive ? AppTheme.danger : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? '🔴 مباشر' : '▶ مسجّل',
        style: AppTheme.caption
            .copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
