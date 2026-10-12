import 'dart:math';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/app_config.dart' as Helpers;
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../utils/widget/app_network_image.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../shared/course/home_course_list.dart';
import '../student/courses/details/course_detail_screen.dart';
import '../student/models.dart';
import 'categories_provider.dart';
import 'model.dart';

const double _kWideBreakpoint = 840;

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, this.selectedId});

  final String? selectedId;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesProvider>().fetchCategories();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.selectedId != null) {
        context.read<CategoriesProvider>().selectCategory(widget.selectedId!);
      } else {
        context.read<CategoriesProvider>().clearSelection();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'categories'.tr),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= _kWideBreakpoint;
                  return isWide
                      ? _WideLayout(searchCtrl: _searchCtrl)
                      : _NarrowLayout(searchCtrl: _searchCtrl);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;

  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CategoriesProvider>();
    final isSearching = context.watch<CategoriesProvider>().isSearching;

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow: context.colors.cardShadow,
      ),
      child: TextField(
        controller: controller,
        textDirection: Helpers.pageDirection,
        onChanged: provider.onSearchChanged,
        style: context.colors.h3.copyWith(fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          hintText: 'ابحث عن قسم أو كورس...',
          hintStyle: context.colors.caption,
          prefixIcon: Icon(Icons.search_rounded, color: context.colors.primary),
          suffixIcon: isSearching
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.colors.textDark,
                  ),
                  onPressed: () {
                    controller.clear();
                    provider.clearSearch();
                  },
                )
              : null,
        ),
      ),
    );
  }
}

// ── Narrow (mobile) layout ────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final TextEditingController searchCtrl;

  const _NarrowLayout({required this.searchCtrl});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(
            child: ParentComponent(
              featureKey: 'categories.search',
              child: _SearchField(controller: searchCtrl),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 18),
          sliver: SliverToBoxAdapter(
            child: ParentComponent(
              featureKey: 'categories.chips',
              child: SizedBox(
                height: min(MediaQuery.of(context).size.width / 6, 100) + 34,
                child: const _CategoryChipsRow(),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          sliver: SliverToBoxAdapter(
            child: ParentComponent(
              featureKey: 'categories.section_header',
              child: _SectionHeader(provider: provider),
            ),
          ),
        ),
        _CoursesSliver(crossAxisCount: 2),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ── Wide (web) layout ──────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final TextEditingController searchCtrl;

  const _WideLayout({required this.searchCtrl});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParentComponent(
          featureKey: 'categories.side_list',
          child: Container(
            width: 280,
            margin: const EdgeInsets.fromLTRB(20, 16, 0, 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(context.colors.radiusMedium),
              boxShadow: context.colors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الأقسام', style: context.colors.h2),
                const SizedBox(height: 14),
                Expanded(child: _CategorySideList()),
              ],
            ),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: ParentComponent(
                    featureKey: 'categories.search',
                    child: _SearchField(controller: searchCtrl),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: ParentComponent(
                    featureKey: 'categories.section_header',
                    child: _SectionHeader(provider: provider),
                  ),
                ),
              ),
              _CoursesSliver(crossAxisCount: 4),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section header (title + clear) ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final CategoriesProvider provider;

  const _SectionHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final title = provider.isSearching
        ? 'نتائج البحث'
        : provider.selectedCategory != null
        ? AppConfig.lang == 'ar'
              ? provider.selectedCategory!.nameAr
              : provider.selectedCategory!.nameEn
        : 'كل الكورسات';

    final showClear =
        provider.selectedCategoryId != null || provider.isSearching;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: context.colors.h2),
        if (provider.selectedCategory != null) ...[
          SizedBox(width: 2),
          Flexible(
            child: Text(
              provider.selectedCategory!.description,
              style: context.colors.h4.copyWith(
                overflow: TextOverflow.ellipsis,
                color: context.colors.secondText,
                fontSize: 12,
              ),
            ),
          ),
        ],
        if (showClear)
          GestureDetector(
            onTap: () async => await provider.clearSelection(),
            child: Text(
              'عرض الكل',
              style: context.colors.label.copyWith(
                color: context.colors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Category chips (mobile, horizontal) ───────────────────────────────────────

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final categories = provider.filteredCategories;

    if (provider.isLoadingCategory && categories.isEmpty) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => const _ShimmerCircle(),
      );
    }

    if (categories.isEmpty) {
      return Center(
        child: Text('لا توجد أقسام مطابقة', style: context.colors.caption),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, i) {
        final cat = categories[i];
        final isSelected = provider.selectedCategoryId == cat.id;
        return GestureDetector(
          onTap: () => provider.selectCategory(cat.id),
          child: CategoryAvatar(isSelected, categoryModel: cat, index: i),
        );
      },
    );
  }
}

// ── Category list (web, vertical sidebar) ──────────────────────────────────────

class _CategorySideList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final categories = provider.filteredCategories;

    if (provider.isLoadingCategory && categories.isEmpty) {
      return ListView.separated(
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => const _ShimmerRow(),
      );
    }

    if (categories.isEmpty) {
      return Center(
        child: Text('لا توجد أقسام مطابقة', style: context.colors.caption),
      );
    }

    return ListView.separated(
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final cat = categories[i];
        final isSelected = provider.selectedCategoryId == cat.id;
        return _CategorySideTile(
          category: cat,
          isSelected: isSelected,
          onTap: () => provider.selectCategory(cat.id),
        );
      },
    );
  }
}

class _CategorySideTile extends StatefulWidget {
  final CategoryModel category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategorySideTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CategorySideTile> createState() => _CategorySideTileState();
}

class _CategorySideTileState extends State<_CategorySideTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isSelected
        ? context.colors.primary.withValues(alpha: 0.12)
        : _hovering
        ? context.colors.background
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            textDirection: Helpers.pageDirection,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: widget.category.imageUrl != null
                      ? AppNetworkImage(
                          url: widget.category.imageUrl!,
                          width: 34,
                          height: 34,
                          fit: BoxFit.cover,
                          enableFullscreen: false,
                          heroTag: 'side_cat_${widget.category.id}',
                        )
                      : Container(
                          color: context.colors.primary.withValues(alpha: 0.15),
                          child: Center(
                            child: Text(
                              widget.category.nameEn.isNotEmpty
                                  ? widget.category.nameEn.split(' ').first[0] +
                                        widget.category.nameEn
                                            .split(' ')
                                            .last[0]
                                  : '?',
                              style: TextStyle(
                                color: context.colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppConfig.lang == 'ar'
                      ? widget.category.nameAr
                      : widget.category.nameEn,
                  style: context.colors.navLabelSelected.copyWith(
                    fontSize: 14,
                    color: widget.isSelected ? context.colors.primary : null,
                    fontWeight: widget.isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: context.colors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category avatar (mobile chip) ─────────────────────────────────────────────

class CategoryAvatar extends StatelessWidget {
  final CategoryModel categoryModel;
  final int index;
  final bool isSelected;

  CategoryAvatar(
    this.isSelected, {
    super.key,
    required this.categoryModel,
    required this.index,
  });

  final List<Color> colors = [
    AppTheme.accent,
    AppTheme.accent2,
    AppTheme.primary,
  ];

  @override
  Widget build(BuildContext context) {
    double size = min(context.width / 6, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? context.colors.warning
                  : context.colors.background,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isSelected ? 0.28 : 0.16),
                blurRadius: isSelected ? 20 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: categoryModel.imageUrl != null
                ? AppNetworkImage(
                    url: categoryModel.imageUrl!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    enableFullscreen: false,
                    heroTag: 'category_avatar_${categoryModel.id}',
                  )
                : Container(
                    color: isSelected
                        ? context.colors.warning
                        : colors[index % 3].withValues(alpha: 0.5),
                    child: Center(
                      child: Text(
                        categoryModel.nameEn.isNotEmpty
                            ? categoryModel.nameEn.split(' ').first[0] +
                                  categoryModel.nameEn.split(' ').last[0]
                            : '?',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: size / 5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: size,
          child: Text(
            AppConfig.lang == 'ar'
                ? categoryModel.nameAr
                : categoryModel.nameAr,
            style: context.colors.navLabelSelected.copyWith(
              color: isSelected ? context.colors.warning : null,
              height: 1,
              fontSize: size / 7,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
          ),
        ),
      ],
    );
  }
}

// ── Courses sliver (grid, shared by both layouts) ──────────────────────────────

class _CoursesSliver extends StatelessWidget {
  final int crossAxisCount;

  const _CoursesSliver({required this.crossAxisCount});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final courses = provider.filteredCourses;
    final loading = provider.isLoadingCourse;

    if (loading && courses.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, _) => const _ShimmerCard(),
            childCount: crossAxisCount * 2,
          ),
        ),
      );
    }

    if (courses.isEmpty) {
      final hasFilter =
          provider.selectedCategoryId != null || provider.isSearching;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(
                hasFilter ? Icons.search_off_rounded : Icons.category_outlined,
                size: 48,
                color: context.colors.textDark.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                hasFilter ? 'لا توجد نتائج مطابقة' : 'اختر قسمًا لعرض الكورسات',
                style: context.colors.caption,
              ),
            ],
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: ParentComponent(
        featureKey: 'categories.courses',
        child: HomeCourseList(
          courses: courses
              .map((e) => e.toCourseModel)
              .cast<CourseModel>()
              .toList(),
          pageName: 'category-my-courses',
          isTeacher: false,
          onTap: (CourseModel c) {
            Navigator.pushNamed(context, '/course-detail', arguments: c);
          },
          hasMore: true,
        ),
      ),
    );
  }
}

// ── Course card (premium, hoverable on web) ─────────────────────────────────

class _CourseCard extends StatefulWidget {
  final CategoryCourseModel course;

  const _CourseCard({required this.course});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final course = widget.course;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(
              course: CourseModel.fromCategoryModel(course),
            ),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _hovering ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : context.colors.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(context.colors.radiusMedium),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      course.imageUrl.isNotEmpty
                          ? AppNetworkImage(
                              url: course.imageUrl,
                              fit: BoxFit.cover,
                              heroTag: 'category-course-${course.id}',
                            )
                          : Container(
                              color: context.colors.primary.withValues(
                                alpha: 0.1,
                              ),
                            ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _Badge(
                          icon: Icons.star_rounded,
                          label: course.rating.toStringAsFixed(1),
                          color: context.colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        course.title,
                        style: context.colors.h3.copyWith(fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (course.instructorName.isNotEmpty)
                        Text(
                          course.instructorName,
                          style: context.colors.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            course.price > 0
                                ? '\$ ${course.price.toStringAsFixed(2)}'
                                : 'مجاني',
                            style: context.colors.h3.copyWith(
                              color: context.colors.accent,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
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

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lightweight shimmer placeholders (no external package) ───────────────────

class _ShimmerBase extends StatefulWidget {
  final Widget child;

  const _ShimmerBase({required this.child});

  @override
  State<_ShimmerBase> createState() => _ShimmerBaseState();
}

class _ShimmerBaseState extends State<_ShimmerBase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) =>
          Opacity(opacity: 0.4 + (_ctrl.value * 0.35), child: widget.child),
    );
  }
}

class _ShimmerCircle extends StatelessWidget {
  const _ShimmerCircle();

  @override
  Widget build(BuildContext context) {
    final double size = min(context.width / 6, 100);
    return _ShimmerBase(
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: size * 0.6, height: 8, color: Colors.grey.shade300),
        ],
      ),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow();

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 12, color: Colors.grey.shade300)),
        ],
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        ),
      ),
    );
  }
}
