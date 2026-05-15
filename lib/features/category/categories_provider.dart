/// ─────────────────────────────────────────────────────────────────────────────
/// categories_provider.dart
/// Manages state for [CategoriesScreen].
///
/// API endpoints:
///   GET /api/v1/categories          — flat root-level categories (no parent_id)
///   GET /api/v1/courses?category_id — courses for the selected category
///
/// FLAT ONLY — no nested/child categories.
///
/// Screen contract (categories_screen.dart):
///   categories          → List<CategoryModel>
///   selectedCategoryId  → String?
///   filteredCourses     → List<CategoryCourseModel>
///   selectCategory(id)  → toggle + fetch courses
///   clearFilter()       → deselect + clear list
/// ─────────────────────────────────────────────────────────────────────────────
library;


import '../../core/api_client.dart';
import '../../core/base_provider.dart';
import 'model.dart';

// ── CategoryModel ─────────────────────────────────────────────────────────────

/// Flat category tile shown in the 4-column grid.
///
/// Fields read by [_CategoryGrid]:
///   id, name, iconAsset
class CategoryModel {
  final String id;
  final String name;
  final String imageUrl;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
    );
  }

  static Map<String, dynamic> fromJsonToSpecializationMap(
      Map<String, dynamic> json) {
    return {
      'id': json['id'].toString(),
      'text': json['name'] as String? ?? '',
      'logo': json['image_url'] as String? ?? ''
    };
  }
}
// ── CategoriesProvider ────────────────────────────────────────────────────────

class CategoriesProvider extends BaseProvider {
  final ApiClient _api;

  CategoriesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ────────────────────────────────────────────────────────────────────

  List<CategoryModel> _categories = [];
  List<CategoryCourseModel> _filteredCourses = [];
  String? _selectedId;

  // ── Getters ──────────────────────────────────────────────────────────────────

  List<CategoryModel> get categories => List.unmodifiable(_categories);

  List<CategoryCourseModel> get filteredCourses =>
      List.unmodifiable(_filteredCourses);

  String? get selectedCategoryId => _selectedId;
  bool isLoadingCategory = false;
  bool isLoadingCourse = false;

  // ── fetchCategories ───────────────────────────────────────────────────────────
  Future<void> fetchCategories() async {
    isLoadingCategory = true;
    notifyListeners();
    final result = await run(
      () => _api.get('/api/v1/categories', auth: true),
    );
    if (result is List) {
      _categories = result
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    isLoadingCategory = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getSpecialization() async {
    final result = await run(
      () => _api.get('/api/v1/categories', auth: true),
    );
    if (result is List) {
      return result
          .map((e) => CategoryModel.fromJsonToSpecializationMap(
              e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ── selectCategory ────────────────────────────────────────────────────────────

  Future<void> selectCategory(String id) async {
    if (_selectedId == id) {
      clearFilter();
      return;
    }
    isLoadingCourse = true;
    notifyListeners();
    _selectedId = id;
    _filteredCourses = [];
    await _fetchCoursesFor(id);
    isLoadingCourse = false;
    notifyListeners();
  }

  // ── clearFilter ───────────────────────────────────────────────────────────────

  void clearFilter() {
    _selectedId = null;
    _filteredCourses = [];
    notifyListeners();
  }

  // ── Private ───────────────────────────────────────────────────────────────────

  Future<void> _fetchCoursesFor(String categoryId) async {

    final result = await run(() => _api.get(
          '/api/v1/courses',
          queryParams: {'category_id': categoryId, 'limit': 20, 'skip': 0},
          auth: false,
        ));

    if (result is List) {
      _filteredCourses = result
          .map((e) => CategoryCourseModel.fromJson(e as Map<String, dynamic>))
          .toList();

    }
  }
}
