// lib/features/store/store_tab.dart — the student's Store tab (Learning Hub Phase 5, D-1333; kill switch
// `student_tab_store`): e-books, summaries and notes to buy.
//
//   StoreTab         the tab: GET /api/v1/store/items with THE course filter bar (CourseFilters / CourseFilterBar,
//                    stage → grade and subject only, remembered with the courses' filters) plus the category row and a
//                    search; the cart button opens the checkout for every item in the cart, the library button My
//                    Library. Browsing works for a guest (optional auth); buying asks them to sign in.
//   StoreBrowseView  the tab's body with plain values (test/ui/store_layout_test.dart)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/store/store_api.dart';
import 'package:flutter_education_app/features/store/store_checkout.dart';
import 'package:flutter_education_app/features/store/store_item_page.dart';
import 'package:flutter_education_app/features/store/store_library.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/store/store_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

String storeCountText(int n) => countText(n,
    ar1: 'عنصر واحد',
    ar2: 'عنصران',
    arFew: '$n عناصر',
    arMany: '$n عنصراً',
    en1: '1 item',
    en: '$n items',
    ar0: 'لا توجد عناصر',
    en0: 'No items');

/// A category the row offers: its id and its name in the app's language.
typedef StoreCategory = ({int id, String name});

class StoreTab extends StatefulWidget {
  const StoreTab({super.key, this.api});

  final StoreApi? api;

  @override
  State<StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<StoreTab> {
  late final StoreApi _api = widget.api ?? StoreApi();
  static const _page = 24;

  CourseFilters _filters = CourseFilters.empty;
  CourseFilterEdu? _edu;
  String _user = 'guest';
  int? _categoryId;
  String _search = '';
  List<StoreCategory> _categories = const [];

  List<StoreItem> _items = const [];
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true, _loadingMore = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    StoreCart.instance.addListener(_changed);
    StoreLibraryBus.revision.addListener(_reload);
    _start();
  }

  @override
  void dispose() {
    StoreCart.instance.removeListener(_changed);
    StoreLibraryBus.revision.removeListener(_reload);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _reload() => _load();

  /// The courses' remembered filters (level + subject) are the store's start too: one set of choices per person.
  Future<void> _start() async {
    final u = await CourseFilterStore.user();
    var f = courseFiltersOff() ? CourseFilters.empty : await CourseFilterStore.initial(u.id);
    f = CourseFilters(country: f.country, stageId: f.stageId, gradeId: f.gradeId, subjectId: f.subjectId);
    if (!mounted) return;
    setState(() {
      _user = u.id;
      _filters = f;
    });
    _load();
    _loadCategories();
    CourseFilterEdu.load(f.country, storedOnly: true).then((e) {
      if (mounted && e != null) setState(() => _edu = e);
    });
  }

  Future<void> _loadCategories() async {
    try {
      final p = context.read<CategoriesProvider>();
      if (p.categories.isEmpty) await p.fetchCategories();
      if (!mounted) return;
      setState(() => _categories = [
            for (final c in p.categories)
              if (int.tryParse(c.id) != null) (id: int.parse(c.id), name: storeText(c.nameAr, c.nameEn)),
          ]);
    } catch (_) {}
  }

  Future<CourseFilterEdu?> _loadEdu() async {
    final edu = await CourseFilterEdu.load(_filters.country);
    if (mounted && edu != null) setState(() => _edu = edu);
    return edu;
  }

  StoreQuery get _query => StoreQuery(
        country: _filters.country,
        stageId: courseFiltersOff() ? null : _filters.stageId,
        gradeId: courseFiltersOff() ? null : _filters.gradeId,
        subjectId: courseFiltersOff() ? null : _filters.subjectId,
        categoryId: _categoryId,
        search: _search,
      );

  Future<void> _load({bool more = false}) async {
    final seq = ++_seq;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final r = await _api.items(_query, skip: more ? _items.length : 0, limit: _page);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = more ? [..._items, ...r.items] : r.items;
        _total = r.total;
        _hasMore = r.hasMore;
        _loading = _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = _loadingMore = false;
        if (more) {
          showAppNotice(storeErrorText(e), error: true);
        } else {
          _error = storeErrorText(e);
        }
      });
    }
  }

  void _onFilters(CourseFilters f) {
    setState(() => _filters = f);
    // the courses keep their own delivery / area: only the level and the subject come from here
    CourseFilterStore.initial(_user).then((saved) => CourseFilterStore.save(
        _user,
        CourseFilters(
            country: f.country ?? saved.country,
            stageId: f.stageId,
            gradeId: f.gradeId,
            subjectId: f.subjectId,
            delivery: saved.delivery,
            areaId: saved.areaId,
            areaAr: saved.areaAr,
            areaEn: saved.areaEn)));
    _load();
  }

  void _onCategory(int? id) {
    setState(() => _categoryId = id);
    _load();
  }

  void _onSearch(String q) {
    if (q.trim() == _search.trim()) return;
    _search = q;
    _load();
  }

  void _open(StoreItem it) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/store/${it.id}'),
        builder: (_) => StoreItemPage(itemId: it.id, initial: it, api: _api),
      ));

  void _openCart() {
    final items = StoreCart.instance.value;
    if (items.isEmpty) return;
    GuestGuard.run(context, () async {
      final paid = await showStoreCheckout(context, items, api: _api);
      if (paid && mounted) _openLibrary();
    });
  }

  void _openLibrary() => GuestGuard.run(
      context,
      () => Navigator.of(context).push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/store/library'),
            builder: (_) => StoreLibraryPage(api: _api),
          )));

  @override
  Widget build(BuildContext context) {
    final cart = StoreCart.instance.value.length;
    return BasePage(
      width: AppWidth.wide,
      appBar: ScreenAppBar(
        title: t('المتجر', 'Store'),
        showBack: false,
        helpPageId: 'store.browse',
        actions: [
          IconButton(
            key: const ValueKey('store.library'),
            tooltip: t('مكتبتي', 'My Library'),
            icon: const Icon(Icons.local_library_rounded),
            onPressed: _openLibrary,
          ),
          IconButton(
            key: const ValueKey('store.cart'),
            tooltip: cart == 0 ? t('السلة', 'Cart') : '${t('السلة', 'Cart')} ($cart)',
            icon: Badge(
              isLabelVisible: cart > 0,
              label: Text('$cart'),
              child: const Icon(Icons.shopping_cart_rounded),
            ),
            onPressed: cart == 0 ? null : _openCart,
          ),
        ],
      ),
      child: SafeArea(
        child: StoreBrowseView(
          filters: _filters,
          edu: _edu,
          loadEdu: _loadEdu,
          onFilters: _onFilters,
          categories: _categories,
          categoryId: _categoryId,
          onCategory: _onCategory,
          onSearch: _onSearch,
          items: _items,
          total: _loading ? null : _total,
          loading: _loading,
          loadingMore: _loadingMore,
          hasMore: _hasMore,
          error: _error,
          cartIds: {for (final e in StoreCart.instance.value) e.id},
          onOpen: _open,
          onRetry: _load,
          onLoadMore: () => _load(more: true),
          onRefresh: _load,
        ),
      ),
    );
  }
}

/// The browse body with plain values.
class StoreBrowseView extends StatelessWidget {
  const StoreBrowseView({
    super.key,
    required this.filters,
    required this.onFilters,
    required this.items,
    this.edu,
    this.loadEdu,
    this.categories = const [],
    this.categoryId,
    this.onCategory,
    this.onSearch,
    this.total,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
    this.cartIds = const {},
    this.onOpen,
    this.onRetry,
    this.onLoadMore,
    this.onRefresh,
  });

  final CourseFilters filters;
  final ValueChanged<CourseFilters> onFilters;
  final CourseFilterEdu? edu;
  final Future<CourseFilterEdu?> Function()? loadEdu;
  final List<StoreCategory> categories;
  final int? categoryId;
  final ValueChanged<int?>? onCategory;
  final ValueChanged<String>? onSearch;
  final List<StoreItem> items;
  final int? total;
  final bool loading, loadingMore, hasMore;
  final String? error;
  final Set<int> cartIds;
  final ValueChanged<StoreItem>? onOpen;
  final VoidCallback? onRetry, onLoadMore;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final head = <Widget>[
      AppSearchField(
        key: const ValueKey('store.search'),
        hint: t('ابحث في المتجر', 'Search the store'),
        onChanged: (q) => onSearch?.call(q),
      ),
      const SizedBox(height: AppSpace.sm),
      ParentComponent(
        featureKey: kCourseFiltersKey,
        child: CourseFilterBar(
          value: filters,
          edu: edu,
          loadEdu: loadEdu,
          resultCount: total,
          withPlace: false,
          countLabel: storeCountText,
          sheetTitle: t('تصفية المتجر', 'Filter the store'),
          applyLabel: t('عرض النتائج', 'Show results'),
          onChanged: onFilters,
        ),
      ),
      if (categories.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        SingleChildScrollView(
          key: const ValueKey('store.categories'),
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            AppChoiceChip(label: t('كل الأقسام', 'All categories'), selected: categoryId == null, onTap: () => onCategory?.call(null)),
            for (final c in categories) ...[
              const SizedBox(width: AppSpace.xs),
              AppChoiceChip(
                key: ValueKey('store.category.${c.id}'),
                label: c.name,
                selected: c.id == categoryId,
                onTap: () => onCategory?.call(c.id == categoryId ? null : c.id),
              ),
            ],
          ]),
        ),
      ],
      const SizedBox(height: AppSpace.md),
    ];
    final Widget body;
    if (loading && items.isEmpty) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (items.isEmpty) {
      body = AppEmpty(
        key: const ValueKey('store.empty'),
        icon: Icons.local_mall_rounded,
        title: filters.hasLevel || categoryId != null
            ? t('لا توجد عناصر لهذه الاختيارات بعد', 'Nothing for these choices yet')
            : t('المتجر فارغ الآن', 'The store is empty for now'),
        message: filters.hasLevel || categoryId != null ? t('غيّر الاختيارات أو امسح التصفية.', 'Change the choices or clear the filters.') : null,
        actionLabel: filters.hasLevel ? t('اعرض كل المستويات', 'Show every level') : null,
        onAction: filters.hasLevel ? () => onFilters(filters.withLevel(null, null)) : null,
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppGrid(
          minTile: 140,
          children: [
            for (final it in items) StoreItemCard(item: it, inCart: cartIds.contains(it.id), onTap: () => onOpen?.call(it)),
          ],
        ),
        if (hasMore) ...[
          const SizedBox(height: AppSpace.md),
          Center(
            child: AppButton.secondary(
              key: const ValueKey('store.more'),
              label: t('عرض المزيد', 'Show more'),
              busy: loadingMore,
              onPressed: loadingMore ? null : onLoadMore,
            ),
          ),
        ],
      ]);
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [...head, body, const SizedBox(height: AppSpace.lg)],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}
