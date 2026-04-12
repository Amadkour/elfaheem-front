
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../config/app_config.dart';

class VideoService {
  /// Validate video file
  static Future<Map<String, dynamic>> validateVideo(File videoFile) async {
    try {
      // Check file size
      final fileSize = await videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);

      if (fileSizeMB > AppConfig.maxVideoSizeMB) {
        return {
          'valid': false,
          'error': 'Video size exceeds ${AppConfig.maxVideoSizeMB}MB limit',
        };
      }

      // Check file extension
      final extension = videoFile.path.split('.').last.toLowerCase();
      if (!AppConfig.allowedVideoFormats.contains(extension)) {
        return {
          'valid': false,
          'error': 'Invalid video format. Allowed: ${AppConfig.allowedVideoFormats.join(', ')}',
        };
      }

      // Get video metadata
      final metadata = await getVideoMetadata(videoFile);

      return {
        'valid': true,
        'size': fileSize,
        'duration': metadata['duration'],
        'width': metadata['width'],
        'height': metadata['height'],
      };
    } catch (e) {
      return {
        'valid': false,
        'error': 'Failed to validate video: ${e.toString()}',
      };
    }
  }

  /// Get video metadata (duration, resolution)
  static Future<Map<String, dynamic>> getVideoMetadata(File videoFile) async {
    try {
      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();

      final metadata = {
        'duration': controller.value.duration.inSeconds,
        'width': controller.value.size.width.toInt(),
        'height': controller.value.size.height.toInt(),
      };

      await controller.dispose();
      return metadata;
    } catch (e) {
      debugPrint('Error getting video metadata: $e');
      return {
        'duration': 0,
        'width': 0,
        'height': 0,
      };
    }
  }

  /// Format video duration
  static String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }
}