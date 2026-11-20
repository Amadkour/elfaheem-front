/// ─────────────────────────────────────────────────────────────────────────────
/// categories_provider.dart
/// Manages state for [CategoriesScreen].
///
/// API endpoints:
///   GET /api/v1/categories                          — flat root-level categories
///   GET /api/v1/courses?category_id=...              — courses for a category
///   GET /api/v1/courses?search=...&category_id=...   — search courses
///                                                       (optionally scoped to a category)
///
/// FLAT ONLY — no nested/child categories.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart' show modeCourseScopeQuery;
import 'package:flutter_education_app/features/courses/category/model.dart';

// ── CategoryModel ─────────────────────────────────────────────────────────────

class CategoryModel {
  final String id;
  final String nameAr;
  final String nameEn;
  final String description;
  final String? imageUrl;

  const CategoryModel({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.imageUrl,
    required this.description,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'].toString(),
      description: json['description'] as String? ?? '',
      nameAr: json['name_ar'] as String? ?? '',
      nameEn: json['name_en'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
    );
  }

  Map<String, dynamic> toSpecializationMap() {
    return {
      'id': id,
      'text': AppConfig.lang == 'ar' ? nameAr : nameEn,
      'logo': imageUrl,
    };
  }

  static Map<String, dynamic> fromJsonToSpecializationMap(
    Map<String, dynamic> json,
  ) {
    return {
      'id': json['id'].toString(),
      'text': json['name_${AppConfig.lang}'] as String? ?? '',
      'logo': json['image_url'] as String? ?? '',
    };
  }
}

// ── CategoriesProvider ────────────────────────────────────────────────────────

class CategoriesProvider extends BaseProvider {
  final ApiClient _api;
  Timer? _debounce;

  CategoriesProvider({ApiClient? api}) : _api = api ?? ApiClient() {
    fetchCategories();
  }

  // ── State ────────────────────────────────────────────────────────────────

  List<CategoryModel> _categories = [];
  List<CategoryCourseModel> _courses = [];
  String? _selectedId;
  String _query = '';

  bool isLoadingCategory = false;
  bool isLoadingCourse = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  /// All fetched categories, unfiltered.
  List<CategoryModel> get categories => List.unmodifiable(_categories);

  /// Categories filtered by the current search query (client-side, instant).
  List<CategoryModel> get filteredCategories {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return categories;
    return _categories
        .where(
          (c) =>
              c.nameAr.toLowerCase().contains(q) ||
              c.nameEn.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  List<CategoryCourseModel> get filteredCourses => List.unmodifiable(_courses);

  String? get selectedCategoryId => _selectedId;

  String get query => _query;

  bool get isSearching => _query.trim().isNotEmpty;

  // ── The filter bar (D-1325) ────────────────────────────────────────────────

  /// The course filter bar's GET /courses params (CourseFilters.toQuery: stage_id, grade_id, subject_id, delivery,
  /// area_id, country), sent with every course call of this page.
  Map<String, dynamic> _filterQuery = const {};
  Map<String, dynamic> get filterQuery => _filterQuery;

  /// The server's `total` of the last course answer (null before one, or from an older server).
  int? _total;
  int? get total => _total;

  /// New filters from the bar: the bar owns them from now on (the join flow's start filters are folded into them),
  /// and the list on screen is asked again ([fetch] false: the caller's own first fetch carries them).
  Future<void> setFilters(Map<String, dynamic> query, {bool fetch = true}) async {
    _filterQuery = {...query};
    _exploreFilters = const {};
    if (!fetch) return;
    if (isSearching) {
      await _runSearch();
    } else if (_selectedId != null) {
      await _fetchCoursesFor(_selectedId!);
    } else {
      await _fetchAllCourses();
    }
  }

  CategoryModel? get selectedCategory {
    if (_selectedId == null) return null;
    for (final c in _categories) {
      if (c.id == _selectedId) return c;
    }
    return null;
  }

  // ── fetchCategories ─────────────────────────────────────────────────────

  Future<void> fetchCategories() async {
    isLoadingCategory = true;
    notifyListeners();
    final result = await run(() => _api.get('/api/v1/categories', auth: true));
    if (result is List) {
      _categories = result
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    isLoadingCategory = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getSpecialization() async {
    if (categories.isEmpty) {
      await fetchCategories();
    }
    return categories.map((e) => e.toSpecializationMap()).toList();
  }

  // ── Search ───────────────────────────────────────────────────────────────

  /// Call on every keystroke. Categories filter instantly (client-side);
  /// course search is debounced to avoid hammering the API.
  void onSearchChanged(String value) {
    _query = value;
    notifyListeners(); // filteredCategories updates immediately

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  void clearSearch() {
    _debounce?.cancel();
    _query = '';
    notifyListeners();
    if (_selectedId != null) {
      _fetchCoursesFor(_selectedId!);
    } else {
      _courses = [];
      notifyListeners();
    }
  }

  Future<void> _runSearch() async {
    final q = _query.trim();

    if (q.isEmpty) {
      if (_selectedId != null) {
        await _fetchCoursesFor(_selectedId!);
      } else {
        _courses = [];
        notifyListeners();
      }
      return;
    }

    isLoadingCourse = true;
    notifyListeners();

    final params = <String, dynamic>{'search': q, 'limit': 30, 'skip': 0, ..._side, ..._explore, ..._filterQuery};
    if (_selectedId != null) params['category_id'] = _selectedId;

    final result = await run(
      () => _api.get('/api/v1/courses', queryParams: params, auth: _sideNeedsAuth),
    );

    _applyCoursesResult(result);
    isLoadingCourse = false;
    notifyListeners();
  }

  /// Pull-to-refresh: the categories again, then whatever course list is on screen (same calls as before).
  Future<void> refresh() async {
    await fetchCategories();
    if (isSearching) {
      await _runSearch();
    } else if (_selectedId != null) {
      await _fetchCoursesFor(_selectedId!);
    } else if (_courses.isNotEmpty) {
      await _fetchAllCourses();
    }
  }

  // ── selectCategory ──────────────────────────────────────────────────────

  Future<void> selectCategory(String id, {bool force = false}) async {
    if (_selectedId == id && !force) {
      await clearSelection();
      return;
    }
    _selectedId = id;
    isLoadingCourse = true;
    notifyListeners();

    if (isSearching) {
      await _runSearch();
    } else {
      await _fetchCoursesFor(id);
    }

    isLoadingCourse = false;
    notifyListeners();
  }

  Future<void> clearSelection() async {
    _selectedId = null;
    if (isSearching) {
      _runSearch();
    } else {
      _courses = [];
      await _fetchAllCourses();
      notifyListeners();
    }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  /// The guest search's "explore" filter: null = off (every other caller); else 'any' / 'online' / 'center'.
  String? _exploreMode;
  String? get exploreMode => _exploreMode;
  void setExploreMode(String? mode, {Map<String, dynamic>? filters}) {
    _exploreMode = mode;
    _exploreFilters = mode == null ? const {} : {...?filters};
  }

  /// The join flow's filters (CONTRACT §4: country, stage_id, grade_id, delivery, area_id), sent with the explore
  /// mode only.
  Map<String, dynamic> _exploreFilters = const {};

  /// `mode` and, with a category, its sub-categories too (a subject lists its levels' courses). `any` / `center`
  /// widen the server's default personal scope to the whole public catalogue, so the list matches the landing's count.
  Map<String, dynamic> get _explore => _exploreMode == null
      ? const {}
      : {'mode': _exploreMode, if (_selectedId != null) 'with_subcategories': true, ..._exploreFilters};

  /// The mode's side on GET /courses (the server's default is the personal account). An organization's side is
  /// for its members only, so that request goes signed in; the personal catalogue stays public (guests). The guest
  /// explore sends no side at all: an explicit `scope` would cancel its `mode` (D-270).
  Map<String, dynamic> get _side => _exploreMode != null ? const {} : modeCourseScopeQuery();
  bool get _sideNeedsAuth => _side['scope'] == 'org';

  Future<void> _fetchCoursesFor(String categoryId) async {
    isLoadingCourse = true;
    notifyListeners();
    final result = await run(
      () => _api.get(
        '/api/v1/courses',
        queryParams: {'category_id': categoryId, 'limit': 20, 'skip': 0, ..._side, ..._explore, ..._filterQuery},
        auth: _sideNeedsAuth,
      ),
    );
    _applyCoursesResult(result);
    isLoadingCourse = false;
    notifyListeners();
  }

  Future<void> _fetchAllCourses() async {
    isLoadingCourse = true;
    notifyListeners();
    final result = await run(
      () => _api.get(
        '/api/v1/courses',
        queryParams: {'limit': 20, 'skip': 0, ..._side, ..._explore, ..._filterQuery},
        auth: _sideNeedsAuth,
      ),
    );
    _applyCoursesResult(result);
    isLoadingCourse = false;
    notifyListeners();
  }

  void _applyCoursesResult(dynamic result) {
    if (result is Map && result['items'] is List) {
      _courses = (result['items'] as List)
          .map((e) => CategoryCourseModel.fromJson(e as Map))
          .toList();
      final t = result['total'];
      _total = t is num ? t.toInt() : _courses.length;
    } else {
      _courses = [];
      _total = null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
