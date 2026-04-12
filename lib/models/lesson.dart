/// Lesson model representing video lessons.
class Lesson {
  final int id;
  final String title;
  final String? description;
  final int moduleId;
  final int order;
  final String? videoUrl;
  final int duration;
  final int fileSize;
  final String? thumbnailUrl;
  final DateTime createdAt;

  Lesson({
    required this.id,
    required this.title,
    this.description,
    required this.moduleId,
    required this.order,
    this.videoUrl,
    required this.duration,
    required this.fileSize,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      moduleId: json['module_id'] as int,
      order: json['order'] as int,
      videoUrl: json['video_url'] as String?,
      duration: json['duration'] as int,
      fileSize: json['file_size'] as int,
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedFileSize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
}