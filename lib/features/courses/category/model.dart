import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/home/student/models.dart';



class CategoryCourseModel with DiscountInfo {
  final String id;
  final String title;
  final String categoryId;
  final String imageUrl;
  @override
  final double price;
  @override
  final double finalPrice;
  final double rating;
  final String instructorName;
  final int coursesCount;
  @override
  final DateTime? discountEndsAt;
  @override
  final bool discountActive;
  @override
  final double discountPercentage;
  final int? discountDays;

  const CategoryCourseModel({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.imageUrl,
    required this.price,
    required this.rating,
    required this.instructorName,
    required this.coursesCount,
    required this.finalPrice,
    this.discountEndsAt,
    required this.discountActive,
    required this.discountPercentage,
    this.discountDays,
    this.raw,
  });

  /// The course as GET /courses sent it (CourseResponse): the card is drawn from it (title, type, teacher, rating,
  /// currency, who / where), D-1326.
  final Map<String, dynamic>? raw;

  /// CourseResponse has `name_ar` / `name_en` (no `name`): the person's language first, then the other one.
  static String _title(Map<dynamic, dynamic> j) {
    String s(Object? v) => v is String ? v.trim() : '';
    final ar = s(j['name_ar']), en = s(j['name_en']), name = s(j['name']);
    final first = AppConfig.lang == 'ar' ? ar : en;
    final other = AppConfig.lang == 'ar' ? en : ar;
    return first.isNotEmpty ? first : (other.isNotEmpty ? other : name);
  }

  factory CategoryCourseModel.fromJson(Map<dynamic, dynamic> json) =>
      CategoryCourseModel(
        id: json['id'].toString(),
        title: _title(json),
        categoryId: json['category_id']?.toString() ?? '',
        imageUrl: json['image_url'] as String? ?? '',
        rating:
        (json['rating'] as num?)?.toDouble() ??
            (json['rate'] as num?)?.toDouble() ??
            0.0,
        instructorName:
        json['teacher']?['name'] as String? ??
            json['teacher_name'] as String? ??
            '',
        coursesCount: (json['courses_count'] as num?)?.toInt() ?? 0,
        price:
        (json['price'] as num?)?.toDouble() ??
            (json['fees'] as num?)?.toDouble() ??
            0.0,
        finalPrice: (json['final_price'] as num?)?.toDouble() ?? 0.0,
        discountEndsAt: json['discount_ends_at'] != null
            ? DateTime.tryParse(json['discount_ends_at'] as String)
            : null,
        discountActive: json['discount_active'] as bool? ?? false,
        discountPercentage:
        (json['discount_percentage'] as num?)?.toDouble() ?? 0.0,
        discountDays: (json['discount_days'] as num?)?.toInt(),
        raw: json['id'] == null ? null : Map<String, dynamic>.from(json),
      );

  /// The full course model when the row came from GET /courses (the same parser as the student home's lists), else
  /// the sparse one.
  CourseModel get toCourseModel {
    final j = raw;
    if (j != null) {
      try {
        return CourseModel.fromJson(j);
      } catch (_) {}
    }
    return CourseModel.fromCategoryModel(this);
  }
}