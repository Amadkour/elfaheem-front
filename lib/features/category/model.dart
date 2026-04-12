class CategoryCourseModel {
  final String id;
  final String title;
  final String categoryId;
  final String imageUrl;
  final double price;
  final double rating;
  final String instructorName;

  const CategoryCourseModel({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.imageUrl,
    required this.price,
    required this.rating,
    required this.instructorName,
  });

  factory CategoryCourseModel.fromJson(Map<String, dynamic> json) =>
      CategoryCourseModel(
        id: json['id'].toString(),
        title: json['name'] as String? ?? '',
        categoryId: json['category_id']?.toString() ?? '',
        imageUrl: json['image_url'] as String? ?? '',
        price: (json['fees'] as num?)?.toDouble() ?? 0.0,
        rating: (json['rating'] as num?)?.toDouble() ??
            (json['rate'] as num?)?.toDouble() ??
            0.0,
        instructorName: json['teacher']?['name'] as String? ??
            json['teacher_name'] as String? ??
            '',
      );
}