/// Course model representing educational courses.
class Course {
  final int id;
  final String title;
  final String? description;
  final int instructorId;
  final String? thumbnailUrl;
  final double price;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;

  Course({
    required this.id,
    required this.title,
    this.description,
    required this.instructorId,
    this.thumbnailUrl,
    required this.price,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      instructorId: json['instructor_id'] as int,
      thumbnailUrl: json['thumbnail_url'] as String?,
      price: (json['price'] as num).toDouble(),
      isPublished: json['is_published'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isFree => price == 0.0;
}
