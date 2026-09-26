// lib/features/shared/upload/upload_task.dart
//
// Plain, mutable data holder for one in-progress (or just-finished) file
// upload. Owned entirely by [UploadQueueManager] — nothing else should
// mutate a task's fields directly.

import 'package:dio/dio.dart';

enum UploadStatus { uploading, success, failed, cancelled }

class UploadTask {
  UploadTask({
    required this.sessionId,
    required this.fileName,
    required this.cancelToken,
  });

  final int sessionId;
  final String fileName;
  final CancelToken cancelToken;

  int sentBytes = 0;
  int totalBytes = 0;
  UploadStatus status = UploadStatus.uploading;
  String? errorMessage;

  /// Last percentage (0-100) a listener was notified for — lets the manager
  /// throttle `notifyListeners()` to roughly once per percentage point
  /// instead of once per network chunk (which can fire dozens of times a
  /// second on a fast connection).
  int lastNotifiedPercent = -1;

  double get progress =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0, 1);

  bool get isDone =>
      status == UploadStatus.success ||
      status == UploadStatus.failed ||
      status == UploadStatus.cancelled;
}
