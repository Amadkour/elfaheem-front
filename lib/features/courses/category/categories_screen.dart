// lib/features/courses/category/categories_screen.dart
//
// Browse by category (Warm Editorial Blocks, D-610 – D-629). Every category wears ONE block tone wherever it
// appears (AppBlockTone.forKey(id): peach or sky) and a vector glyph picked from its name (categoryIconFor), never a
// letter or an emoji. The page's one memorable element is the chosen category's block: its glyph, its name in the
// editorial headline and its description; with nothing chosen the list just says "All courses".
//
//   phone   search well · a row of category tiles · the chosen category's block · the course cards
//   wide    a paper column of categories on the start side · search, the block and the cards beside it
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_kit.dart' show AppShimmer, AppSkeletonBox;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale, AppTilt;
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_states.dart' show AppEmpty;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/courses/home_course_list.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';

const double _kWideBreakpoint = 840;

/// The wide layout's category column.
const double _kSideWidth = 280;

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, this.selectedId, this.mode});

  final String? selectedId;

  /// The guest search's filter ('any' / 'online' / 'center'); null for every other caller.
  final String? mode;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<CategoriesProvider>().setExploreMode(widget.mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesProvider>().fetchCategories();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.selectedId != null) {
        context.read<CategoriesProvider>().selectCategory(widget.selectedId!, force: widget.mode != null);
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
      width: AppWidth.wide,
      appBar: ScreenAppBar(title: 'categories'.tr),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= _kWideBreakpoint
              ? _WideLayout(searchCtrl: _searchCtrl)
              : _NarrowLayout(searchCtrl: _searchCtrl),
        ),
      ),
    );
  }
}

// ── Category glyphs ───────────────────────────────────────────────────────────

/// The glyph of a category, from its name in either language: a subject it names gets its own symbol, anything
/// else one of a few learning glyphs, always the same one for the same category.
IconData categoryIconFor(CategoryModel category) {
  final name = '${category.nameEn} ${category.nameAr}'.toLowerCase();
  bool has(List<String> words) => words.any(name.contains);
  // most specific first: "رياضيات" (maths) before "رياضة" (sport)
  if (has(const ['math', 'algebra', 'رياضيات', 'جبر', 'حساب ', 'calcul'])) return Icons.calculate_rounded;
  // "computer science" is computing, not a lab science
  if (has(const ['program', 'comput', 'coding', 'software', 'tech', 'برمج', 'حاسب', 'حاسوب', 'تقنية'])) {
    return Icons.computer_rounded;
  }
  if (has(const ['physic', 'chemi', 'biolog', 'science', 'فيزياء', 'كيمياء', 'أحياء', 'احياء', 'علوم'])) {
    return Icons.science_rounded;
  }
  if (has(const ['quran', 'islam', 'relig', 'قرآن', 'قران', 'إسلام', 'اسلام', 'دين', 'تجويد', 'فقه'])) {
    return Icons.menu_book_rounded;
  }
  if (has(const ['arabic', 'english', 'french', 'german', 'language', 'لغة', 'عربي', 'إنجليزي', 'انجليزي', 'فرنس'])) {
    return Icons.translate_rounded;
  }
  if (has(const ['history', 'geograph', 'social', 'تاريخ', 'جغرافيا', 'دراسات'])) return Icons.public_rounded;
  if (has(const ['art', 'design', 'draw', 'فن', 'رسم', 'تصميم'])) return Icons.palette_rounded;
  if (has(const ['music', 'موسيق'])) return Icons.music_note_rounded;
  if (has(const ['photo', 'تصوير'])) return Icons.photo_camera_rounded;
  if (has(const ['business', 'account', 'market', 'econom', 'financ', 'محاسب', 'إدارة', 'ادارة', 'تسويق', 'اقتصاد'])) {
    return Icons.business_center_rounded;
  }
  if (has(const ['health', 'medic', 'nurs', 'طب', 'صحة', 'تمريض'])) return Icons.medical_services_rounded;
  if (has(const ['sport', 'fitness', 'رياضة', 'لياقة'])) return Icons.sports_soccer_rounded;
  const fallback = [Icons.auto_stories_rounded, Icons.school_rounded, Icons.lightbulb_rounded, Icons.interests_rounded];
  final h = category.id.codeUnits.fold<int>(7, (a, u) => (a * 31 + u) & 0x7fffffff);
  return fallback[h % fallback.length];
}

String _nameOf(CategoryModel c) => AppConfig.lang == 'ar'
    ? (c.nameAr.isNotEmpty ? c.nameAr : c.nameEn)
    : (c.nameEn.isNotEmpty ? c.nameEn : c.nameAr);

/// A category's mark: its picture, or its glyph on its block tone (on a paper [plate] inside its own block), in a
/// [size] square.
class _CategoryMark extends StatelessWidget {
  const _CategoryMark({required this.category, required this.size, required this.radius, this.heroTag, this.plate = false});

  final CategoryModel category;
  final double size;
  final double radius;
  final String? heroTag;
  final bool plate;

  /// The glyph as a share of the mark.
  static const double _glyph = 0.46;

  @override
  Widget build(BuildContext context) {
    final b = AppBlockColors.of(context, AppBlockTone.forKey(category.id));
    final url = category.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: url != null && url.isNotEmpty
            ? AppNetworkImage(
                url: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                enableFullscreen: false,
                heroTag: heroTag,
              )
            : ColoredBox(
                color: plate ? context.colors.cardBg : b.surface,
                child: Center(child: Icon(categoryIconFor(category), size: size * _glyph, color: b.ink)),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: TextField(
        controller: controller,
        textDirection: pageDirection,
        onChanged: provider.onSearchChanged,
        textInputAction: TextInputAction.search,
        style: appFieldTextStyle(context),
        decoration: appFieldDecoration(
          context,
          hint: _tx('ابحث عن قسم أو كورس...', 'Search a category or course...'),
          icon: Icons.search_rounded,
          suffix: isSearching
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                  icon: const Icon(Icons.close_rounded, size: AppIconSize.md),
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

    return AppRefresh(
      onRefresh: provider.refresh,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
            sliver: SliverToBoxAdapter(
              child: ParentComponent(
                featureKey: 'categories.search',
                child: _SearchField(controller: searchCtrl),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            sliver: SliverToBoxAdapter(
              child: ParentComponent(
                featureKey: 'categories.chips',
                child: SizedBox(
                  height: CategoryAvatar.extentOf(context),
                  child: const _CategoryChipsRow(),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.md),
            sliver: SliverToBoxAdapter(
              child: ParentComponent(
                featureKey: 'categories.section_header',
                child: _SectionHeader(provider: provider),
              ),
            ),
          ),
          const _CoursesSliver(crossAxisCount: 2),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
        ],
      ),
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
    final c = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParentComponent(
          featureKey: 'categories.side_list',
          child: Container(
            width: _kSideWidth,
            margin: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, 0, AppSpace.md),
            padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.md, AppSpace.xs, AppSpace.xs),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: c.divider, width: AppBorder.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, bottom: AppSpace.sm),
                  child: Text(_tx('الأقسام', 'Categories'), style: AppType.section(context)),
                ),
                const Expanded(child: _CategorySideList()),
              ],
            ),
          ),
        ),
        Expanded(
          child: AppRefresh(
            onRefresh: context.read<CategoriesProvider>().refresh,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
                  sliver: SliverToBoxAdapter(
                    child: ParentComponent(
                      featureKey: 'categories.search',
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                          child: _SearchField(controller: searchCtrl),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
                  sliver: SliverToBoxAdapter(
                    child: ParentComponent(
                      featureKey: 'categories.section_header',
                      child: _SectionHeader(provider: provider),
                    ),
                  ),
                ),
                const _CoursesSliver(crossAxisCount: 4),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Section header: the chosen category's block, or the plain heading ─────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final CategoriesProvider provider;

  const _SectionHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cat = provider.isSearching ? null : provider.selectedCategory;
    final showClear = provider.selectedCategoryId != null || provider.isSearching;
    final clear = AppButton.ghost(
      label: _tx('عرض الكل', 'Show all'),
      size: AppButtonSize.sm,
      onPressed: () async => await provider.clearSelection(),
    );
    final Widget body;
    if (cat != null) {
      body = _CategoryBlock(key: ValueKey('cat-${cat.id}'), category: cat, action: clear);
    } else {
      final title = provider.isSearching ? _tx('نتائج البحث', 'Search results') : _tx('كل الكورسات', 'All courses');
      body = Row(
        key: ValueKey('plain-${provider.isSearching}'),
        children: [
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
          if (showClear) Flexible(child: clear),
        ],
      );
    }
    // a new choice crossfades in place (it answers the tap); nothing moves on its own
    return AnimatedSwitcher(
      duration: AppMotion.of(context).fast,
      switchInCurve: AppMotion.curve,
      layoutBuilder: (current, previous) =>
          Stack(alignment: AlignmentDirectional.topStart, children: [...previous, ?current]),
      child: body,
    );
  }
}

/// The chosen category: ONE block in its own tone, its glyph on a paper plate, the name in the editorial headline
/// and the description under it. It leans a little under the pointer (the screen's hero).
class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({super.key, required this.category, required this.action});

  final CategoryModel category;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final tone = AppBlockTone.forKey(category.id);
    final description = category.description.trim();
    return AppTilt(
      radius: AppRadius.block,
      maxTilt: 2,
      child: AppBlock(
        tone: tone,
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _CategoryMark(category: category, size: AppTouch.primary, radius: AppRadius.card, plate: true),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _nameOf(category),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.headline(context).copyWith(color: b.ink),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(context).copyWith(color: b.muted),
                  ),
                ],
                const SizedBox(height: AppSpace.sm),
                Align(alignment: AlignmentDirectional.centerStart, child: action),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}

// ── Category tiles (mobile, horizontal) ───────────────────────────────────────

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final categories = provider.filteredCategories;
    final size = CategoryAvatar.sizeOf(context);

    if (provider.isLoadingCategory && categories.isEmpty) {
      return AppShimmer(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
          itemBuilder: (_, _) => Column(children: [
            AppSkeletonBox(width: size, height: size, radius: CategoryAvatar.radiusFor(size)),
            const SizedBox(height: AppSpace.xs),
            AppSkeletonBox(width: size * 0.6, height: AppSpace.xs),
          ]),
        ),
      );
    }

    if (categories.isEmpty) {
      return Center(
        child: Text(_tx('لا توجد أقسام مطابقة', 'No matching categories'), style: AppType.meta(context)),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xxs),
      itemBuilder: (_, i) {
        final cat = categories[i];
        final isSelected = provider.selectedCategoryId == cat.id;
        return Semantics(
          button: true,
          selected: isSelected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => provider.selectCategory(cat.id),
            child: AppPressScale(child: CategoryAvatar(isSelected, categoryModel: cat, index: i)),
          ),
        );
      },
    );
  }
}

// ── Category list (web, vertical sidebar) ──────────────────────────────────────

class _CategorySideList extends StatelessWidget {
  const _CategorySideList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final categories = provider.filteredCategories;

    if (provider.isLoadingCategory && categories.isEmpty) {
      return AppShimmer(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (_, _) => const Row(children: [
            AppSkeletonBox(width: AppIconSize.xl, height: AppIconSize.xl, radius: AppRadius.chip),
            SizedBox(width: AppSpace.sm),
            Expanded(child: AppSkeletonBox(height: AppSpace.sm)),
          ]),
        ),
      );
    }

    if (categories.isEmpty) {
      return Center(
        child: Text(_tx('لا توجد أقسام مطابقة', 'No matching categories'), style: AppType.meta(context)),
      );
    }

    return ListView.separated(
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xxs),
      itemBuilder: (_, i) {
        final cat = categories[i];
        return _CategorySideTile(
          category: cat,
          isSelected: provider.selectedCategoryId == cat.id,
          onTap: () => provider.selectCategory(cat.id),
        );
      },
    );
  }
}

/// One category in the side column: its mark, its name, and — when chosen — the primary tint and a chevron toward
/// the courses.
class _CategorySideTile extends StatelessWidget {
  final CategoryModel category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategorySideTile({required this.category, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: isSelected,
      child: Material(
        color: isSelected ? c.primaryTint : Colors.transparent,
        borderRadius: AppRadius.controlAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.controlAll,
          hoverColor: c.inputBg,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
              child: Row(
                textDirection: pageDirection,
                children: [
                  _CategoryMark(
                    category: category,
                    size: AppIconSize.xl,
                    radius: AppRadius.chip,
                    heroTag: 'side_cat_${category.id}',
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      _nameOf(category),
                      style: AppType.row(context).copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? c.textDark : c.textMedium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected) Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Category tile (the mobile row here and on the student's home) ─────────────────────────────────────────

/// A category as a square tile on its block tone with its glyph (or its picture), the name under it. A chosen one
/// is ringed in the primary. Its height is [extentOf]; the student home's category row reserves the same.
class CategoryAvatar extends StatelessWidget {
  final CategoryModel categoryModel;

  /// The tile's place in its row (kept for callers; the tone comes from the category itself).
  final int index;
  final bool isSelected;

  const CategoryAvatar(
    this.isSelected, {
    super.key,
    required this.categoryModel,
    required this.index,
  });

  /// The ONE letter drawn without a picture, from the name in the app's language (N7 / L7): the first letter of the
  /// first word, after the Arabic article "ال" (every "ال…" name drew the same alef, read as a Latin "I"). Two
  /// letters read as broken glyphs in Arabic ("لع", "حآ"), so a Latin name gets one letter too.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final w = words.first;
    final stem = w.startsWith('ال') && w.characters.length > 3 ? w.substring(2) : w;
    return stem.characters.first.toUpperCase();
  }

  /// The tile's side: a sixth of the screen, at most 100.
  static double sizeOf(BuildContext context) => min(context.width / 6, 100);

  /// The name's size: a seventh of the tile, at least 11 (the home's row is sized from this).
  static double _labelSize(double size) => max(11, size / 7);

  static const double _labelHeight = 1.15;

  /// A tile's corner: the block radius on a large tile, the card radius on a small one.
  static double radiusFor(double size) => size >= 72 ? AppRadius.block : AppRadius.card;

  /// The whole tile's height (square, gap, two lines of name) at the current text scale.
  static double extentOf(BuildContext context) {
    final size = sizeOf(context);
    return size +
        AppSpace.xs +
        2 * _labelHeight * _labelSize(size) * MediaQuery.textScalerOf(context).scale(1) +
        AppSpace.xxs;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = _nameOf(categoryModel);
    final size = sizeOf(context);
    final radius = radiusFor(size);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: AppMotion.of(context).fast,
          curve: AppMotion.curve,
          width: size,
          height: size,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isSelected ? c.primary : Colors.transparent,
              width: AppBorder.focus,
            ),
          ),
          child: _CategoryMark(
            category: categoryModel,
            size: size,
            radius: radius,
            heroTag: 'category_avatar_${categoryModel.id}',
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        SizedBox(
          // a little wider than the tile, so a long single word ("Mathematics") is not split
          width: size + AppSpace.sm,
          child: Text(
            name,
            style: AppType.label(context).copyWith(
              color: isSelected ? c.textDark : c.textMedium,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              height: _labelHeight,
              fontSize: _labelSize(size),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Courses (shared by both layouts) ──────────────────────────────────────────────

class _CoursesSliver extends StatelessWidget {
  final int crossAxisCount;

  const _CoursesSliver({required this.crossAxisCount});

  /// A skeleton tile's shape: a 16:9 cover over three lines.
  static const double _skeletonAspect = 0.9;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final courses = provider.filteredCourses;
    final loading = provider.isLoadingCourse;
    final side = crossAxisCount > 2 ? AppSpace.lg : AppSpace.md;

    if (loading && courses.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: side),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: _skeletonAspect,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, _) => const AppShimmer(child: AppSkeletonBox(radius: AppRadius.card)),
            childCount: crossAxisCount * 2,
          ),
        ),
      );
    }

    if (courses.isEmpty) {
      final hasFilter = provider.selectedCategoryId != null || provider.isSearching;
      return SliverToBoxAdapter(
        child: AppEmpty(
          icon: hasFilter ? Icons.search_off_rounded : Icons.category_rounded,
          title: hasFilter
              ? _tx('لا توجد نتائج مطابقة', 'Nothing matches')
              : _tx('اختر قسمًا لعرض الكورسات', 'Pick a category to see its courses'),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: ParentComponent(
        featureKey: 'categories.courses',
        child: HomeCourseList(
          maxWidth: AppWidth.wide.max,
          courses: courses.map((e) => e.toCourseModel).cast<CourseModel>().toList(),
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

/// Inline bilingual text (this screen used to show Arabic only, also in English).
String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;
