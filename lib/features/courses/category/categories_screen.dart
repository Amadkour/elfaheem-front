// lib/features/courses/category/categories_screen.dart
//
// Browse by subject (redesign Stu1Discover?screen=category, S-A2): the learn-area hero names the chosen subject
// ("قسم الرياضيات" · "دورات الرياضيات"); under it the delivery segment (الكل · عن بعد · حضوري) and "تصفية" (the
// course filter bar's sheet, D-1325), the subject chips, the count line and the course cards (CourseListCard through
// HomeCourseList). Every category keeps ONE glyph picked from its name (categoryIconFor), never a letter or an emoji.
//
//   phone   segment + تصفية · chips (the search behind the first one) · "24 courses for your grade" · card rows
//   wide    ONE card (search · segment · تصفية) · chips · the count · a grid of cards
library;

import 'package:flutter_education_app/features/guest/sa_hero_page.dart';
import 'package:flutter_education_app/design/app_area.dart' show AppArea;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_kit.dart' show AppCard, AppChip, AppShimmer, AppSkeletonBox, AppTabItem, AppTabs;
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
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart' show StudyProfileApi;

const double _kWideBreakpoint = 840;


class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, this.selectedId, this.mode, this.filters});

  final String? selectedId;

  /// The guest search's filter ('any' / 'online' / 'center'); null for every other caller.
  final String? mode;

  /// The join flow's search filters (CONTRACT §4), sent with [mode].
  final Map<String, dynamic>? filters;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<CategoriesProvider>().setExploreMode(widget.mode, filters: widget.filters);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesProvider>().fetchCategories();
    });
    // the filter bar's start (D-1325) first, so the first course call already carries it
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  // ── The course filter bar (D-1325) ─────────────────────────────────────────
  CourseFilters _filters = CourseFilters.empty;
  CourseFilterEdu? _edu;
  String _user = 'guest';

  /// The filters handed in (the join flow), else the user's remembered ones, else the study profile's level (asked
  /// once for a student who has nothing stored yet); then the course list, then the catalog for the names.
  Future<void> _start() async {
    final u = await CourseFilterStore.user();
    var f = CourseFilters.fromQuery(widget.filters);
    // the bar switched off (courses.filters): only the join flow's start filters apply, nothing remembered (D-1326)
    if (f.isEmpty && !courseFiltersOff()) {
      final country = f.country;
      if (u.student && !await CourseFilterStore.known(u.id)) {
        try {
          await StudyProfileApi().load(); // stores the level as the start
        } catch (_) {}
      }
      f = await CourseFilterStore.initial(u.id);
      if (f.country == null && country != null) f = CourseFilters.fromQuery({...f.toQuery(), 'country': country});
    }
    if (!mounted) return;
    setState(() {
      _user = u.id;
      _filters = f;
    });
    final p = context.read<CategoriesProvider>();
    p.setFilters(f.toQuery(), fetch: false);
    if (widget.selectedId != null) {
      p.selectCategory(widget.selectedId!, force: widget.mode != null);
    } else {
      p.clearSelection();
    }
    _loadEdu();
  }

  Future<CourseFilterEdu?> _loadEdu() async {
    final edu = await CourseFilterEdu.load(_filters.country);
    if (mounted && edu != null) setState(() => _edu = edu);
    return edu;
  }

  /// "Show every level" on the empty list (D-1326).
  void showEveryLevel() => _onFilters(_filters.withLevel(null, null));

  void _onFilters(CourseFilters f) {
    setState(() => _filters = f);
    CourseFilterStore.save(_user, f);
    context.read<CategoriesProvider>().setFilters(f.toQuery());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// "تصفية": the course filter bar's own sheet (D-1325).
  void _openFilters() => CourseFilterBar(value: _filters, edu: _edu, loadEdu: _loadEdu, onChanged: _onFilters).openSheet(context);

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      appBar: ScreenAppBar(title: 'categories'.tr),
      child: SafeArea(
        child: Consumer<CategoriesProvider>(
          builder: (context, p, body) {
            // the chosen subject names the hero ("قسم الرياضيات" · "دورات الرياضيات")
            final cat = p.isSearching ? null : p.selectedCategory;
            return SaHeroPage(
              area: AppArea.learn,
              kicker: cat == null ? 'sa_cat_kicker'.tr : 'sa_cat_kicker_of'.tr.replaceAll('{name}', _nameOf(cat)),
              title: cat == null ? 'sa_cat_title'.tr : 'sa_cat_title_of'.tr.replaceAll('{name}', _nameOf(cat)),
              child: body!,
            );
          },
          child: LayoutBuilder(
            builder: (context, constraints) => _CategoriesBody(
              wide: constraints.maxWidth >= _kWideBreakpoint,
              searchCtrl: _searchCtrl,
              filters: _filters,
              onFilters: _onFilters,
              openFilters: courseFiltersOff() ? null : _openFilters,
            ),
          ),
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

/// A category's mark: its picture, or its glyph on its block tone, in a
/// [size] square.
class _CategoryMark extends StatelessWidget {
  const _CategoryMark({required this.category, required this.size, required this.radius, this.heroTag});

  final CategoryModel category;
  final double size;
  final double radius;
  final String? heroTag;


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
                color: b.surface,
                child: Center(child: Icon(categoryIconFor(category), size: size * _glyph, color: b.ink)),
              ),
      ),
    );
  }
}

// ── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool autofocus;

  const _SearchField({required this.controller, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CategoriesProvider>();
    final isSearching = context.watch<CategoriesProvider>().isSearching;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        textDirection: pageDirection,
        onChanged: provider.onSearchChanged,
        textInputAction: TextInputAction.search,
        style: appFieldTextStyle(context),
        decoration: appFieldDecoration(
          context,
          hint: 'sa_cat_search_hint'.tr,
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

// ── The body (redesign Stu1Discover?screen=category, S-A2) ──────────────────────────────────────────
//
//   phone   الكل · عن بعد · حضوري and "تصفية" · the subject chips (search behind the first one) · "24 courses for
//           your grade, best first" · the course cards
//   wide    ONE card: search · the segment · "تصفية"; then the chips, the count line and a grid of cards

/// The delivery segment's values, in its order (null = every course).
const List<String?> _kDeliveries = [null, 'online', 'in_person'];

class _CategoriesBody extends StatefulWidget {
  const _CategoriesBody({required this.wide, required this.searchCtrl, required this.filters, required this.onFilters, required this.openFilters});

  final bool wide;
  final TextEditingController searchCtrl;
  final CourseFilters filters;
  final ValueChanged<CourseFilters> onFilters;

  /// The filter sheet (CourseFilterBar's), or null while the bar is switched off.
  final VoidCallback? openFilters;

  @override
  State<_CategoriesBody> createState() => _CategoriesBodyState();
}

class _CategoriesBodyState extends State<_CategoriesBody> {
  bool _searchOpen = false;

  Widget _segment() {
    final i = _kDeliveries.indexOf(widget.filters.delivery);
    return AppTabs(
      expand: true,
      items: [AppTabItem('sa_cat_any'.tr), AppTabItem('sa_cat_online'.tr), AppTabItem('sa_cat_center'.tr)],
      index: i < 0 ? 0 : i,
      onChanged: (n) => widget.onFilters(widget.filters.withDelivery(_kDeliveries[n])),
    );
  }

  Widget _filterButton() {
    final n = widget.filters.activeCount;
    return AppButton(
      key: const ValueKey('categories.filters'),
      label: n == 0 ? 'sa_cat_filter'.tr : '${'sa_cat_filter'.tr} · $n',
      icon: Icons.tune_rounded,
      variant: n == 0 ? AppButtonVariant.secondary : AppButtonVariant.tonal,
      onPressed: widget.openFilters,
    );
  }

  /// The segment and "تصفية" (the filter bar's kill switch hides both).
  Widget _controls() {
    final row = Row(children: [
      Expanded(child: _segment()),
      const SizedBox(width: AppSpace.sm),
      _filterButton(),
    ]);
    if (!widget.wide) return ParentComponent(featureKey: kCourseFiltersKey, child: row);
    return AppCard(
      child: Row(children: [
        Expanded(
          flex: 5,
          child: ParentComponent(featureKey: 'categories.search', child: _SearchField(controller: widget.searchCtrl)),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(flex: 6, child: ParentComponent(featureKey: kCourseFiltersKey, child: row)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final side = widget.wide ? AppSpace.lg : AppSpace.md;
    return AppRefresh(
      onRefresh: provider.refresh,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
            sliver: SliverToBoxAdapter(child: _controls()),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            sliver: SliverToBoxAdapter(
              child: ParentComponent(
                featureKey: widget.wide ? 'categories.side_list' : 'categories.chips',
                child: _CategoryChipsRow(
                  side: side,
                  searchOpen: _searchOpen,
                  onSearch: widget.wide ? null : () => setState(() => _searchOpen = !_searchOpen),
                ),
              ),
            ),
          ),
          if (!widget.wide && (_searchOpen || provider.isSearching))
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.xs, side, 0),
              sliver: SliverToBoxAdapter(
                child: ParentComponent(
                  featureKey: 'categories.search',
                  child: _SearchField(controller: widget.searchCtrl, autofocus: _searchOpen && !provider.isSearching),
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.sm),
            sliver: SliverToBoxAdapter(
              child: ParentComponent(
                featureKey: 'categories.section_header',
                child: _CountLine(provider: provider, filters: widget.filters),
              ),
            ),
          ),
          _CoursesSliver(crossAxisCount: widget.wide ? 3 : 1),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
        ],
      ),
    );
  }
}

/// "24 courses for your grade, best first" (the count in bold), or "Search results".
class _CountLine extends StatelessWidget {
  const _CountLine({required this.provider, required this.filters});

  final CategoriesProvider provider;
  final CourseFilters filters;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = provider.isLoadingCourse ? null : provider.total;
    final rest = provider.isSearching
        ? 'sa_cat_results'.tr
        : (filters.hasLevel ? 'sa_cat_best_grade'.tr : 'sa_cat_best'.tr);
    return Semantics(
      liveRegion: true,
      child: Text.rich(
        TextSpan(children: [
          // "24 courses for your grade, …" · "24 courses, best match first"
          if (n != null)
            TextSpan(text: '${courseCountText(n)}${provider.isSearching || filters.hasLevel ? ' ' : (AppConfig.lang == 'ar' ? '، ' : ', ')}', style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
          TextSpan(text: rest),
        ]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta(context),
      ),
    );
  }
}

// ── The subject chips (both layouts) ─────────────────────────────────────────────────────────────────

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({required this.side, this.onSearch, this.searchOpen = false});

  final double side;

  /// Phone: the search toggle at the row's start; null = no toggle (the wide card holds the field).
  final VoidCallback? onSearch;
  final bool searchOpen;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoriesProvider>();
    final categories = provider.filteredCategories;
    if (provider.isLoadingCategory && categories.isEmpty) {
      return SizedBox(
        height: AppTouch.min,
        child: AppShimmer(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: side),
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
            itemBuilder: (_, _) => const Center(
              child: AppSkeletonBox(width: AppTouch.primary * 1.6, height: AppChip.height, radius: AppRadius.pill),
            ),
          ),
        ),
      );
    }
    final none = provider.selectedCategoryId == null && !provider.isSearching;
    final items = <Widget>[
      if (onSearch != null)
        AppIconButton(
          key: const ValueKey('categories.search_toggle'),
          icon: searchOpen ? Icons.close_rounded : Icons.search_rounded,
          tooltip: 'sa_cat_search_hint'.tr,
          onPressed: onSearch,
        ),
      AppChip(
        key: const ValueKey('categories.all'),
        label: 'sa_cat_all'.tr,
        selected: none,
        onTap: () async => await provider.clearSelection(),
      ),
      for (final cat in categories)
        AppChip(
          key: ValueKey('categories.chip.${cat.id}'),
          label: _nameOf(cat),
          leading: _CategoryMark(category: cat, size: AppChip.avatar, radius: AppRadius.pill),
          selected: provider.selectedCategoryId == cat.id,
          onTap: () => provider.selectCategory(cat.id),
        ),
    ];
    return SizedBox(
      height: AppTouch.min,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: side),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
        itemBuilder: (_, i) => Center(child: items[i]),
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

  /// A phone row's skeleton: a card row, not a tile.
  static const double _rowAspect = 2.8;

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
            childAspectRatio: crossAxisCount == 1 ? _rowAspect : _skeletonAspect,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, _) => const AppShimmer(child: AppSkeletonBox(radius: AppRadius.card)),
            childCount: crossAxisCount * 2,
          ),
        ),
      );
    }

    // a level picked and nothing for it: say so, and offer every level (D-1326)
    final screen = context.findAncestorStateOfType<_CategoriesScreenState>();
    if (courses.isEmpty && screen != null && screen._filters.hasLevel && !provider.isSearching) {
      return SliverToBoxAdapter(
        child: CourseFilterEmpty(filters: screen._filters, onChanged: (_) => screen.showEveryLevel()),
      );
    }
    if (courses.isEmpty) {
      final hasFilter = provider.selectedCategoryId != null || provider.isSearching || (screen?._filters.isEmpty == false);
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
