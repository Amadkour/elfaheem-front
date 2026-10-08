import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

import 'upload_task.dart';

class UploadQueueManager extends ChangeNotifier {
  UploadQueueManager._();

  static final UploadQueueManager instance = UploadQueueManager._();

  // Separate, bare Dio for the PUT straight to MinIO. It must NOT carry the
  // API's auth interceptor (different host, and an Authorization header has
  // no business being sent there) and must not have a send/receive timeout
  // (large files legitimately take a while).
  static final Dio _rawDio =
  Dio(BaseOptions(sendTimeout: null, receiveTimeout: null));

  final List<UploadTask> _tasks = [];

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  // ---- footer UI state (kept here so it survives page changes) -----------
  bool _expanded = false;
  bool get expanded => _expanded;

  void toggleExpanded() {
    _expanded = !_expanded;
    notifyListeners();
  }

  // ---- queries -------------------------------------------------------------
  bool get hasActive => _tasks.any((t) => t.status == UploadStatus.uploading);

  bool get hasFailed => _tasks.any((t) => t.status == UploadStatus.failed);

  int get activeCount =>
      _tasks.where((t) => t.status == UploadStatus.uploading).length;

  /// Combined 0..1 progress of all active uploads, or null if none active.
  double? get overallProgress {
    var sent = 0, total = 0;
    var any = false;
    for (final t in _tasks) {
      if (t.status != UploadStatus.uploading) continue;
      any = true;
      sent += t.sentBytes;
      total += t.totalBytes;
    }
    if (!any) return null;
    return total <= 0 ? 0 : (sent / total).clamp(0.0, 1.0);
  }

  /// 0..1 progress for the active upload on this session, or null.
  double? progressForSession(int sessionId) {
    for (final t in _tasks) {
      if (t.sessionId == sessionId && t.status == UploadStatus.uploading) {
        return t.progress;
      }
    }
    return null;
  }

  bool isUploadingForSession(int sessionId) => _tasks.any(
          (t) => t.sessionId == sessionId && t.status == UploadStatus.uploading);

  // ---- public actions ------------------------------------------------------
  Future<Map<String, dynamic>?> enqueueFileUpload({
    required Dio dio,
    required int sessionId,
    required String path,
    required String fileName,
    Uint8List? bytes, // null on mobile/desktop video: streamed from [path]
    required String endpoint, // JSON "finalize" route, e.g. .../materials/from-upload
    required Map<String, String> fields,
    MediaType? contentType,
    void Function(Map<String, dynamic>? data)? onSuccess,
  }) {
    final task = UploadTask(
      sessionId: sessionId,
      fileName: fileName,
      cancelToken: CancelToken(),
      dio: dio,
      path: path,
      bytes: bytes,
      endpoint: endpoint,
      fields: fields,
      contentType: contentType,
      onSuccess: onSuccess,
    );
    _tasks.add(task);
    notifyListeners();
    return _run(task);
  }

  /// Re-runs a failed task in place (same row in the footer).
  Future<Map<String, dynamic>?> retry(UploadTask task) {
    if (task.status != UploadStatus.failed ||
        !task.canRetry ||
        !_tasks.contains(task)) {
      return Future.value(null);
    }
    task.resetForRetry();
    notifyListeners();
    return _run(task);
  }

  /// Removes a finished (failed / cancelled / success) task from the queue.
  void dismiss(UploadTask task) {
    if (task.status == UploadStatus.uploading) return;
    _tasks.remove(task);
    notifyListeners();
  }

  void cancel(UploadTask task) {
    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel('user_cancelled');
    }
  }

  // ---- core pipeline -------------------------------------------------------
  Future<Map<String, dynamic>?> _run(UploadTask task) async {
    final dio = task.dio;
    final cancelToken = task.cancelToken;

    try {
      final fileLength = task.bytes?.length ?? await File(task.path).length();
      task.totalBytes = fileLength;

      // Steps 1+2 are skipped on retry if the bytes already reached storage
      // and only the finalize call failed.
      if (!task.uploadDone) {
        // 1) presign — small JSON call through the authenticated API
        final presign = await dio.post(
          _siblingPath(task.endpoint, 'presign'),
          queryParameters: {'filename': task.fileName},
          cancelToken: cancelToken,
        );
        final presignData = presign.data as Map<String, dynamic>;
        final uploadUrl = presignData['upload_url'] as String;
        task.objectKey = presignData['object_key'] as String;
        task.resolvedContentType = presignData['content_type'] as String? ??
            task.contentType?.toString() ??
            'application/octet-stream';

        // 2) PUT straight to MinIO — the only step that streams real bytes.
        await _rawDio.put(
          uploadUrl,
          data: task.bytes ?? File(task.path).openRead(),
          options: Options(headers: {
            Headers.contentTypeHeader: task.resolvedContentType,
            Headers.contentLengthHeader: fileLength,
          }),
          cancelToken: cancelToken,
          onSendProgress: (sent, total) {
            task.sentBytes = sent;
            if (total > 0) task.totalBytes = total;
            final pct = task.totalBytes > 0
                ? ((sent / task.totalBytes) * 100).floor()
                : 0;
            if (pct != task.lastNotifiedPercent) {
              task.lastNotifiedPercent = pct;
              notifyListeners();
            }
          },
        );
        task.uploadDone = true;
        task.sentBytes = task.totalBytes;
      }

      // 3) finalize — creates the material row.
      final response = await dio.post(
        task.endpoint,
        data: {
          ...task.fields,
          'order': int.tryParse(task.fields['order'] ?? '0') ?? 0,
          'object_key': task.objectKey,
        },
        options: Options(contentType: Headers.jsonContentType),
        cancelToken: cancelToken,
      );

      task.status = UploadStatus.success;
      notifyListeners();
      _scheduleRemoval(task);

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : null;
      task.onSuccess?.call(data);
      return data;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task.status = UploadStatus.cancelled;
        task.errorMessage = null;
        notifyListeners();
        // Cancelled by the user on purpose → tidy it away shortly.
        _scheduleRemoval(task, delay: const Duration(seconds: 2));
      } else {
        await _markFailed(
            task, e.response?.data?.toString() ?? e.message ?? e.toString());
      }
      return null;
    } catch (e) {
      await _markFailed(task, e.toString());
      return null;
    }
  }

  /// Failed tasks stay in the queue until the user retries or dismisses them.
  Future<void> _markFailed(UploadTask task, String message) async {
    task.status = UploadStatus.failed;
    task.errorMessage = message;
    log('Upload failed for ${task.fileName}: $message');

    // Retry only makes sense if we can still read the file.
    var available = task.bytes != null;
    if (!available) {
      try {
        available = await File(task.path).exists();
      } catch (_) {
        available = false;
      }
    }
    task.canRetry = available;
    notifyListeners();
  }

  /// '.../materials/from-upload' -> '.../materials/presign'.
  String _siblingPath(String finalizeEndpoint, String siblingSegment) {
    final i = finalizeEndpoint.lastIndexOf('/');
    return '${finalizeEndpoint.substring(0, i)}/$siblingSegment';
  }

  void _scheduleRemoval(UploadTask task,
      {Duration delay = const Duration(seconds: 2)}) {
    Future.delayed(delay, () {
      // Never auto-remove a task that was retried or failed in the meantime.
      if (task.status == UploadStatus.success ||
          task.status == UploadStatus.cancelled) {
        _tasks.remove(task);
        notifyListeners();
      }
    });
  }
}