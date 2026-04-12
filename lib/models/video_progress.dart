/// Video progress model for tracking lesson completion.
class VideoProgress {
  final int id;
  final int lessonId;
  final int watchedDuration;
  final bool completed;
  final DateTime lastWatched;

  VideoProgress({
    required this.id,
    required this.lessonId,
    required this.watchedDuration,
    required this.completed,
    required this.lastWatched,
  });

  factory VideoProgress.fromJson(Map<String, dynamic> json) {
    return VideoProgress(
      id: json['id'] as int,
      lessonId: json['lesson_id'] as int,
      watchedDuration: json['watched_duration'] as int,
      completed: json['completed'] as bool,
      lastWatched: DateTime.parse(json['last_watched'] as String),
    );
  }

  double getProgressPercentage(int totalDuration) {
    if (totalDuration == 0) return 0;
    return (watchedDuration / totalDuration * 100).clamp(0, 100);
  }
}