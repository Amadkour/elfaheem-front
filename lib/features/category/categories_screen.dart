import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/app_config.dart' as Helpers;
import '../../config/theme/theme_config_provider.dart';
import '../../utils/widget/app_network_image.dart';
import '../../utils/widget/app_bar.dart';
import '../student/courses/details/course_detail_screen.dart';
import '../student/models.dart';
import 'categories_provider.dart';
import 'model.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesProvider>().fetchCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'categories'.tr),
              const SizedBox(height: 8),
              const Expanded(
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CategoryGrid(),
                      SizedBox(height: 28),
                      _FilteredCoursesSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category Grid ─────────────────────────────────────────────────────────────

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final categories = provider.categories;

    if (provider.isLoading && categories.isEmpty) {
      return  Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.colors.primary),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: categories.length,
      itemBuilder: (_, i) {
        final cat = categories[i];
        final isSelected = provider.selectedCategoryId == cat.id;

        return GestureDetector(
          onTap: () =>
              context.read<CategoriesProvider>().selectCategory(cat.id),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.colors.primary.withValues(alpha: 0.12)
                      : context.colors.cardBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? context.colors.primary : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow:
                      isSelected ? context.colors.primaryShadow : context.colors.cardShadow,
                ),
                child: AppNetworkImage(
                  url: cat.imageUrl,
                  height: 40,
                  width: 40,
                  padding: const EdgeInsets.all(8),
                  color: isSelected ? context.colors.primary : context.colors.cardBg,
                  borderRadius: BorderRadius.circular(30),
                  heroTag: "category-profile-${cat.id}",

                ),
              ),
              Expanded(
                child: Text(cat.name,
                    style: context.colors.caption.copyWith(
                      color: isSelected ? context.colors.primary : context.colors.textDark,
                      fontFamily: 'tajawal',
                      overflow: TextOverflow.ellipsis,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Filtered Courses Section ──────────────────────────────────────────────────

class _FilteredCoursesSection extends StatelessWidget {
  const _FilteredCoursesSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final courses = provider.filteredCourses;

    if (courses.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Text('الكورسات المتعلقة', style: context.colors.h2),
            if (provider.selectedCategoryId != null)
              GestureDetector(
                onTap: () => context.read<CategoriesProvider>().clearFilter(),
                child: Text(
                  'عرض الكل',
                  style: context.colors.label.copyWith(color: context.colors.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: courses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _SmallCourseCard(course: courses[i]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Small Course Card ─────────────────────────────────────────────────────────

class _SmallCourseCard extends StatelessWidget {
  final CategoryCourseModel course;

  const _SmallCourseCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            course: CourseModel.fromCategoryModel(course),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
          boxShadow: context.colors.cardShadow,
        ),
        child: Row(
          children: [
            AppNetworkImage(
              url: course.imageUrl,
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(12),
              heroTag: "category-course-${course.id}",

            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    style: context.colors.h3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(course.instructorName, style: context.colors.caption),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                       Icon(Icons.star_rounded,
                          color: context.colors.accent, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        course.rating.toStringAsFixed(1),
                        style:
                            context.colors.caption.copyWith(color: context.colors.textDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '\$ ${course.price.toStringAsFixed(2)}',
              style: context.colors.h3.copyWith(color: context.colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
