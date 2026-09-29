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
  // API's auth interceptor (different host — MinIO, not our backend — and
  // an Authorization header has no business being sent there) and must not
  // have a send/receive timeout (large files legitimately take a while).
  // [dio] passed into enqueueFileUpload is still used for the two small
  // JSON calls to our own API (presign, finalize) — this one is ONLY for
  // the raw file bytes.
  static final Dio _rawDio = Dio(BaseOptions(sendTimeout: null, receiveTimeout: null));
  final List<UploadTask> _tasks = [];

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  bool get hasActive =>
      _tasks.any((t) => t.status == UploadStatus.uploading);

  /// 0..1 progress for the (at most one, in practice) active upload on this
  /// session, or null if nothing is uploading for it — used to switch the
  /// session card's progress bar from indeterminate to determinate.
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

  Future<Map<String, dynamic>?> enqueueFileUpload({
    required Dio dio,
    required int sessionId,
    required String path,
    required String fileName,
    Uint8List? bytes, // null on mobile/desktop video: streamed from [path]
    required String endpoint, // now the JSON "finalize" route, e.g. .../materials/from-upload
    required Map<String, String> fields,
    MediaType? contentType,
  }) async {
    final cancelToken = CancelToken();
    final task = UploadTask(
      sessionId: sessionId,
      fileName: fileName,
      cancelToken: cancelToken,
    );
    _tasks.add(task);
    notifyListeners();

    try {
      final fileLength = bytes?.length ?? await File(path).length();
      task.totalBytes = fileLength;

      // 1) presign — small JSON call through the authenticated API
      final presignEndpoint = _siblingPath(endpoint, 'presign');
      print("1-===================presign API --------");
      final presign = await dio.post(
        presignEndpoint,
        queryParameters: {'filename': fileName},
        cancelToken: cancelToken,
      );
      final presignData = presign.data as Map<String, dynamic>;
      print(presignData);
      final uploadUrl = presignData['upload_url'] as String;
      final objectKey = presignData['object_key'] as String;
      final resolvedContentType = presignData['content_type'] as String? ??
          contentType?.toString() ??
          'application/octet-stream';

      // 2) PUT straight to MinIO — the only step that streams real bytes,
      // so it's the only one wired to progress tracking.
      await _rawDio.put(
        uploadUrl,
        data: bytes ?? File(path).openRead(),
        options: Options(headers: {
          Headers.contentTypeHeader: resolvedContentType,
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

      // 3) finalize — creates the material row now that the file is
      // confirmed to actually be in MinIO (server re-checks via stat_object).
      final response = await dio.post(
        endpoint,
        data: {
          ...fields,
          'order': int.tryParse(fields['order'] ?? '0') ?? 0,
          'object_key': objectKey,
        },
        options: Options(contentType: Headers.jsonContentType),
        cancelToken: cancelToken,
      );

      task.status = UploadStatus.success;
      notifyListeners();
      _scheduleRemoval(task);

      return response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : null;
    } on DioException catch (e) {
      final cancelled = e.type == DioExceptionType.cancel;
      task.status = cancelled ? UploadStatus.cancelled : UploadStatus.failed;
      task.errorMessage = cancelled
          ? null
          : (e.response?.data?.toString() ?? e.message);
      log('Upload failed for1 $fileName: ${task.errorMessage}');
      notifyListeners();
      _scheduleRemoval(task, delay: const Duration(seconds: 4));
      return null;
    } catch (e) {
      task.status = UploadStatus.failed;
      task.errorMessage = e.toString();
      log('Upload failed for2 $fileName: $e');
      notifyListeners();
      _scheduleRemoval(task, delay: const Duration(seconds: 4));
      return null;
    }
  }

  /// '.../materials/from-upload' -> '.../materials/presign'. Keeps the
  /// presign route discoverable from the one endpoint sessions_provider.dart
  /// already passes in, instead of adding a second required parameter to
  /// every call site.
  String _siblingPath(String finalizeEndpoint, String siblingSegment) {
    final i = finalizeEndpoint.lastIndexOf('/');
    return '${finalizeEndpoint.substring(0, i)}/$siblingSegment';
  }

  void cancel(UploadTask task) {
    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel('user_cancelled');
    }
  }

  void _scheduleRemoval(UploadTask task,
      {Duration delay = const Duration(seconds: 2)}) {
    Future.delayed(delay, () {
      _tasks.remove(task);
      notifyListeners();
    });
  }
}