/// lib/services/screen_video_recorder.dart
///
/// Wraps  flutter_screen_recording: ^2.0.25
///
///   Android → MediaProjection + MediaRecorder → .mp4
///   iOS     → ReplayKit                       → .mp4
///   Web     → getDisplayMedia + MediaRecorder → .webm  (auto-downloaded by browser)
///
/// After the session ends, the recorded file is uploaded to the Python backend
/// in 5 MB chunks via  POST /sessions/{id}/upload-chunk  then finalized via
/// POST /sessions/{id}/finalize-recording.
/// This gives upload progress and survives network hiccups on individual chunks.
library;

import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';

class ScreenVideoRecorder {
  ScreenVideoRecorder({required this.sessionId});

  final int sessionId;

  static const _chunkSize    = 5 * 1024 * 1024;   // 5 MB per POST
  static const _uploadTimeout = Duration(minutes: 5);

  bool          _isRecording = false;
  final List<String> uploadErrors = [];

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Shows the system screen-recording permission dialog, then starts recording.
  /// Returns true if recording started successfully.
  Future<bool> start() async {
    if (_isRecording) return true;
    try {
      // startRecordScreenAndAudio records video + microphone on all platforms.
      // The notification title/message appear in the Android status bar.
      final started = await FlutterScreenRecording.startRecordScreenAndAudio(
        'session_$sessionId',
        titleNotification:   'تسجيل الحصة المباشرة',
        messageNotification: 'التسجيل جارٍ…',
      );
      _isRecording = started;
      debugPrint('[REC] start → $started');
      return started;
    } catch (e) {
      debugPrint('[REC] start error: $e');
      return false;
    }
  }

  // ── Stop + upload ─────────────────────────────────────────────────────────

  /// Stops recording and returns the local file path.
  /// On web, the browser downloads the file automatically and this returns null.
  Future<String?> stop() async {
    if (!_isRecording) return null;
    try {
      final path = await FlutterScreenRecording.stopRecordScreen;
      _isRecording = false;
      debugPrint('[REC] stopped → path=$path');
      return (path.isNotEmpty) ? path : null;
    } catch (e) {
      debugPrint('[REC] stop error: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Upload the recorded file in 5 MB chunks, then tell the server to finalize.
  /// [onProgress] receives 0–100.
  /// Returns true on success.
  Future<bool> uploadAndFinalize(
      String filePath, {
        void Function(int percent)? onProgress,
      }) async {
    final file = File(filePath);

    if (!await file.exists()) {
      debugPrint('[REC] file not found: $filePath');
      return false;
    }

    final fileSize = await file.length();
    debugPrint('[REC] uploading ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB');

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    // ── Send chunks ─────────────────────────────────────────────────────────
    final raf        = await file.open();
    int  chunkIndex  = 0;
    int  bytesUploaded = 0;

    try {
      while (bytesUploaded < fileSize) {
        final end      = min(bytesUploaded + _chunkSize, fileSize);
        final count    = end - bytesUploaded;
        final bytes    = await raf.read(count);

        final ok = await _postChunk(
          token:      token,
          chunkIndex: chunkIndex,
          bytes:      bytes,
          filename:   '${filePath.split('/').last.split('.').first}.${_ext(filePath)}',
        );

        if (!ok) {
          uploadErrors.add('chunk $chunkIndex failed');
          // Continue anyway — the server tolerates missing chunks
        }

        bytesUploaded += count;
        chunkIndex++;
        onProgress?.call((bytesUploaded / fileSize * 100).round());
      }
    } finally {
      await raf.close();
    }

    // ── Finalize on server ───────────────────────────────────────────────────
    final finalized = await _postFinalize(token);
    debugPrint('[REC] finalize → $finalized  errors=${uploadErrors.length}');

    // Clean up local file
    await file.delete().catchError((_) {});

    return finalized;
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  Future<bool> _postChunk({
    required String token,
    required int    chunkIndex,
    required Uint8List bytes,
    required String filename,
  }) async {
    final mimeType = filename.endsWith('.webm') ? 'video/webm' : 'video/mp4';
    try {
      final uri = Uri.parse(
        '${AppConfig.baseUrl}/api/v1/sessions/$sessionId'
            '/upload-chunk?chunk_index=$chunkIndex',
      );
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename:    'chunk_$chunkIndex.${filename.split('.').last}',
        ));

      // Manually set content-type on the file part
      req.files.first;  // ensure added

      final streamed = await req.send().timeout(_uploadTimeout);
      debugPrint('[REC] chunk $chunkIndex → HTTP ${streamed.statusCode}');
      return streamed.statusCode >= 200 && streamed.statusCode < 300;
    } catch (e) {
      debugPrint('[REC] chunk $chunkIndex error: $e');
      return false;
    }
  }

  Future<bool> _postFinalize(String token) async {
    try {
      final res = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/v1/sessions/$sessionId/finalize-recording',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type':  'application/json',
        },
      ).timeout(_uploadTimeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[REC] finalize error: $e');
      return false;
    }
  }

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot + 1).toLowerCase() : 'mp4';
  }
}