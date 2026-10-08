import 'package:flutter_education_app/features/student/models.dart';

import '../shared/course/discount_info.dart';


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
  });

  factory CategoryCourseModel.fromJson(Map<dynamic, dynamic> json) =>
      CategoryCourseModel(
        id: json['id'].toString(),
        title: json['name'] as String? ?? '',
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
      );

  CourseModel get toCourseModel => CourseModel.fromCategoryModel(this);
}