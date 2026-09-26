import 'package:flutter_education_app/features/student/models.dart';

class CategoryCourseModel {
  final String id;
  final String title;
  final String categoryId;
  final String imageUrl;
  final double price;
  final double rating;
  final String instructorName;
  final int coursesCount;

  const CategoryCourseModel({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.imageUrl,
    required this.price,
    required this.rating,
    required this.instructorName,
    required this.coursesCount,
  });

  factory CategoryCourseModel.fromJson(Map<dynamic, dynamic> json) =>
      CategoryCourseModel(
        id: json['id'].toString(),
        title: json['name'] as String? ?? '',
        categoryId: json['category_id']?.toString() ?? '',
        imageUrl: json['image_url'] as String? ?? '',
        price: (json['fees'] as num?)?.toDouble() ?? 0.0,
        rating:
            (json['rating'] as num?)?.toDouble() ??
            (json['rate'] as num?)?.toDouble() ??
            0.0,
        instructorName:
            json['teacher']?['name'] as String? ??
            json['teacher_name'] as String? ??
            '',
        coursesCount: (json['courses_count'] as num?)?.toInt() ?? 0,
      );

  CourseModel get toCourseModel=>CourseModel.fromCategoryModel(this);
}
