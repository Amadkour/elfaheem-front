
import 'package:flutter/foundation.dart';
import '../models/video_progress.dart';
import '../services/api_service.dart';

class VideoProvider with ChangeNotifier {
  final ApiService _apiService;

  Map<int, VideoProgress> _progressMap = {};
  bool _isLoading = false;
  String? _errorMessage;

  VideoProvider(this._apiService);

  // Getters
  Map<int, VideoProgress> get progressMap => _progressMap;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get progress for specific lesson
  VideoProgress? getProgress(int lessonId) {
    return _progressMap[lessonId];
  }

  /// Load progress for a lesson
  Future<void> loadProgress(int lessonId) async {
    try {
      final response = await _apiService.getVideoProgress(lessonId);
      if (response != null) {
        _progressMap[lessonId] = VideoProgress.fromJson(response);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading progress: $e');
    }
  }

  /// Update progress
  Future<void> updateProgress(
      int lessonId,
      int watchedDuration,
      bool completed,
      ) async {
    try {
      final response = await _apiService.updateVideoProgress(
        lessonId,
        watchedDuration,
        completed,
      );
      _progressMap[lessonId] = VideoProgress.fromJson(response);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update progress: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
