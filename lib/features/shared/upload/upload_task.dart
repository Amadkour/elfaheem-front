// lib/features/shared/upload/upload_task.dart
//
// Mutable data holder for one in-progress (or finished) file upload.
// Owned entirely by [UploadQueueManager] — nothing else should mutate a
// task's fields directly.
//
// The task now keeps everything needed to run the upload again, so a failed
// upload can be retried from the footer without the caller being involved.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

enum UploadStatus { uploading, success, failed, cancelled }

class UploadTask {
  UploadTask({
    required this.sessionId,
    required this.fileName,
    required this.cancelToken,
    required this.dio,
    required this.path,
    required this.endpoint,
    required this.fields,
    this.bytes,
    this.contentType,
    this.onSuccess,
  });

  final int sessionId;
  final String fileName;

  // ---- request data kept for retry ---------------------------------------
  final Dio dio;
  final String path;
  final Uint8List? bytes;
  final String endpoint;
  final Map<String, String> fields;
  final MediaType? contentType;

  /// Called with the finalize response when the upload succeeds — on the
  /// first attempt AND on any retry. Use it to refresh the session's
  /// materials, because the original `await enqueueFileUpload(...)` has
  /// already returned null by the time the user taps "retry".
  final void Function(Map<String, dynamic>? data)? onSuccess;

  // ---- runtime state ------------------------------------------------------
  /// Replaced on every retry (a used CancelToken can't be reused).
  CancelToken cancelToken;

  int sentBytes = 0;
  int totalBytes = 0;
  UploadStatus status = UploadStatus.uploading;
  String? errorMessage;

  /// Set once the PUT to storage succeeded. If only the finalize call
  /// failed, a retry skips presign + PUT and just finalizes.
  bool uploadDone = false;
  String? objectKey;
  String? resolvedContentType;

  /// True when the task failed AND the file is still available to re-send.
  bool canRetry = false;

  /// Last percentage (0-100) a listener was notified for — throttles
  /// `notifyListeners()` to roughly once per percentage point.
  int lastNotifiedPercent = -1;

  double get progress =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0, 1);

  bool get isDone =>
      status == UploadStatus.success ||
          status == UploadStatus.failed ||
          status == UploadStatus.cancelled;

  void resetForRetry() {
    status = UploadStatus.uploading;
    errorMessage = null;
    canRetry = false;
    cancelToken = CancelToken();
    lastNotifiedPercent = -1;
    if (!uploadDone) sentBytes = 0;
  }
}