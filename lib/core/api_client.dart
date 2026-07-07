library;

import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/main.dart';

// ── Exception ─────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic body;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}

// ── Token Storage ─────────────────────────────────────────────────────────────

class TokenStorage {
  static const _accessKey  = 'access_token';
  static const _refreshKey = 'refresh_token';

  Future<void> save({required String access, required String refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  Future<String?> get accessToken async =>
      (await SharedPreferences.getInstance()).getString(_accessKey);

  Future<String?> get refreshToken async =>
      (await SharedPreferences.getInstance()).getString(_refreshKey);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}

// ── ApiClient ─────────────────────────────────────────────────────────────────
//
// Unified: every method (GET, POST, PUT, DELETE, multipart) goes through Dio.
// No more split between package:http and Dio — one interceptor chain,
// one timeout configuration, one token-refresh flow.
//
// Timeout strategy:
//   connectTimeout  30s  — time to open the TCP connection
//   sendTimeout      0   — unlimited send time (large file uploads)
//   receiveTimeout   0   — unlimited receive time (large file downloads)
//
// For normal JSON calls we override receiveTimeout to 30s at the call site.
// Chunk uploads use the unlimited defaults so Dio never interrupts a slow upload.

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();
  factory ApiClient() => instance;

  static const String _base = AppConfig.baseUrl;

  // Public so room.dart can read the base URL for the JS compositor
  String get baseUrl => _base;

  final _storage = TokenStorage();

  // ── Dio instance ──────────────────────────────────────────────────────────

  late final Dio _dio = _buildDio();

  /// Kept for external code that accessed `apiClient.dio` directly.
  Dio get dio => _dio;

  Dio _buildDio() {
    final d = Dio(BaseOptions(
      baseUrl:        _base,
      connectTimeout: const Duration(seconds: 30),
      // sendTimeout and receiveTimeout default to null (unlimited).
      // Normal calls override receiveTimeout to 30s via _jsonOpts().
      // File upload/download calls leave them unlimited.
      sendTimeout:    null,
      receiveTimeout: null,
      receiveDataWhenStatusError: true,
      headers: {
        HttpHeaders.acceptHeader:          'application/json',
        HttpHeaders.acceptLanguageHeader:  AppConfig.lang,
      },
    ));

    d.interceptors.add(InterceptorsWrapper(
      // ── Inject Bearer token ────────────────────────────────────────────
      onRequest: (options, handler) async {
        final token = await _storage.accessToken;
        if (token != null && options.extra['auth'] != false) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },

      // ── 401 → refresh once → retry ────────────────────────────────────
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['auth'] != false &&
            error.requestOptions.extra['_retried'] != true) {
          if (await _tryRefresh()) {
            try {
              final opts = error.requestOptions
                ..headers['Authorization'] =
                    'Bearer ${await _storage.accessToken}'
                ..extra['_retried'] = true;
              final retried = await _dio.fetch(opts);
              return handler.resolve(retried);
            } catch (_) {}
          }
          await _redirectToLogin();
        }
        handler.next(error);
      },

      // ── Log responses ─────────────────────────────────────────────────
      onResponse: (response, handler) {
        if(AppConfig.showLogs) {
          log('[${response.requestOptions.path}] ${response.statusCode} '
              '${response.data.runtimeType}');
          log(response.data.toString());

        }
        handler.next(response);
      },
    ));

    return d;
  }

  // ── Options helpers ───────────────────────────────────────────────────────

  /// Options for normal JSON calls — 30s receive timeout, JSON content-type.
  Options _jsonOpts({bool auth = true, String method = 'GET'}) => Options(
    method:         method,
    contentType:    Headers.jsonContentType,
    receiveTimeout: const Duration(seconds: 30),
    extra:          {'auth': auth},
  );

  /// Options for file uploads/downloads — no receive timeout.
  Options _fileOpts({bool auth = true, String method = 'POST'}) => Options(
    method:  method,
    extra:   {'auth': auth},
    // sendTimeout / receiveTimeout intentionally left null = unlimited
  );

  // ── Response handler ──────────────────────────────────────────────────────

  Future<dynamic> _handle(Response res) async {
    final status = res.statusCode ?? 0;
    final path   = res.requestOptions.path;

    if (status == 204) return true;

    if (status == 401) {
      await _redirectToLogin();
      return null;
    }

    if (status == 403) {
      navigatorKey.currentState?.pushNamed('/verify');
      return null;
    }

    if (status >= 200 && status < 300) {
      return res.data;
    }

    // Error response
    String message = 'Request failed';
    final body = res.data;
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      message = detail is String
          ? detail
          : (detail as List).map((e) => e['msg']).join(', ');
    }
    throw ApiException(statusCode: status, message: message, body: body);
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await _dio.post(
        '/api/v1/auth/refresh',
        queryParameters: {'refresh_token': refresh},
        options: Options(extra: {'auth': false, '_retried': true}),
      );
      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        await _storage.save(
          access:  data['access_token']  as String,
          refresh: data['refresh_token'] as String? ?? refresh,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _redirectToLogin() async {
    await _storage.clear();
    if(AppConfig.showLogs) {
      log('redirect to login ──────────────────────────────>');
    }
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ── Version check ─────────────────────────────────────────────────────────

  /// GET /app/version-check?version=x.y.z&platform=android|ios|web
  /// Returns the raw JSON map from the server.
  Future<Map<String, dynamic>> checkVersion({
    required String version,
    required String platform,
  }) async {
    final res = await _dio.get(
      '/app/version-check',
      queryParameters: {'version': version, 'platform': platform},
      options: Options(
        receiveTimeout: const Duration(seconds: 15),
        extra: {'auth': false},   // public endpoint — no token needed
      ),
    );
    final data = await _handle(res);
    return (data as Map<String, dynamic>?) ?? {};
  }

  // ── GET ───────────────────────────────────────────────────────────────────

  Future<dynamic> get(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final res = await _dio.get(
      path,
      queryParameters: queryParams,
      options: _jsonOpts(auth: auth),
    );
    return _handle(res);
  }

  // ── POST ──────────────────────────────────────────────────────────────────

  Future<dynamic> post(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final res = await _dio.post(
      path,
      data:            body,
      queryParameters: queryParams,
      options:         _jsonOpts(auth: auth, method: 'POST'),
    );
    return _handle(res);
  }

  // ── PUT ───────────────────────────────────────────────────────────────────

  Future<dynamic> put(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final res = await _dio.put(
      path,
      data:            body,
      queryParameters: queryParams,
      options:         _jsonOpts(auth: auth, method: 'PUT'),
    );
    return _handle(res);
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<dynamic> delete(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final res = await _dio.delete(
      path,
      queryParameters: queryParams,
      options:         _jsonOpts(auth: auth, method: 'DELETE'),
    );
    return _handle(res);
  }

  // ── Upload image ──────────────────────────────────────────────────────────

  Future<dynamic> uploadImage(
      String path, {
        required XFile file,
        String fieldName = 'file',
      }) async {
    final ext  = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final mime = _imageMime(ext);
    final name = p.basename(file.path).isNotEmpty
        ? p.basename(file.path)
        : 'upload.${ext.isEmpty ? 'jpg' : ext}';
    final bytes = await file.readAsBytes();

    final res = await _dio.post(
      path,
      data: FormData.fromMap({
        fieldName: MultipartFile.fromBytes(
          bytes,
          filename:    name,
          contentType: MediaType.parse(mime),
        ),
      }),
      options: _fileOpts(),
    );
    return _handle(res);
  }

  // ── POST multipart ────────────────────────────────────────────────────────
  //
  // Supports both in-memory bytes and on-disk file streaming.
  // For chunk uploads always prefer [filePath] — it streams from disk and
  // never triggers a receive timeout because sendTimeout is unlimited.
  //
  // Parameters:
  //   filePath  — path to a file on disk (preferred: streams, low memory use)
  //   fileBytes — fallback when no file is on disk (e.g. web blob)
  //
  // Both [fileField] + ([filePath] or [fileBytes]) are required.

  Future<dynamic> postMultipart(
      String path, {
        required Map<String, String> fields,
        required String fileField,
        required String fileName,
        String?    filePath,    // preferred: stream from disk, no receive timeout
        Uint8List? fileBytes,  // fallback: in-memory bytes
        bool auth = true,
      }) async {
    assert(filePath != null || fileBytes != null,
    'postMultipart: provide filePath or fileBytes');

    final ext  = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final mime = _fileMime(ext);

    MultipartFile multipartFile;
    if (!kIsWeb && filePath != null && File(filePath).existsSync()) {
      // Stream from disk — memory-efficient and no timeout issues.
      // dart:io's File is unavailable on web (throws "Unsupported
      // operation: _Namespace"), so web always falls through to bytes below.
      multipartFile = await MultipartFile.fromFile(
        filePath,
        filename:    fileName,
        contentType: MediaType.parse(mime),
      );
    } else {
      // Fallback: bytes (web, or when file was already deleted)
      if (fileBytes == null) {
        throw Exception(
          'postMultipart: no fileBytes provided and filePath is unusable '
              '(web platform, or file missing on disk).',
        );
      }
      multipartFile = MultipartFile.fromBytes(
        fileBytes,
        filename:    fileName,
        contentType: MediaType.parse(mime),
      );
    }

    final form = FormData.fromMap({
      ...fields,
      fileField: multipartFile,
    });

    final res = await _dio.post(
      path,
      data:    form,
      options: _fileOpts(auth: auth),   // unlimited send + receive timeout
    );
    return _handle(res);
  }

  // ── Token helpers ─────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) => _storage.save(access: access, refresh: refresh);

  Future<void> clearTokens() => _storage.clear();

  Future<String?> get accessToken => _storage.accessToken;

  // ── MIME helpers ──────────────────────────────────────────────────────────

  static String _imageMime(String ext) => switch (ext) {
    'png'  => 'image/png',
    'webp' => 'image/webp',
    'gif'  => 'image/gif',
    _      => 'image/jpeg',
  };

  static String _fileMime(String ext) => switch (ext) {
    'png'          => 'image/png',
    'webp'         => 'image/webp',
    'gif'          => 'image/gif',
    'jpg' || 'jpeg'=> 'image/jpeg',
    'pdf'          => 'application/pdf',
    'doc'          => 'application/msword',
    'docx'         => 'application/vnd.openxmlformats-officedocument'
        '.wordprocessingml.document',
    'xls'          => 'application/vnd.ms-excel',
    'xlsx'         => 'application/vnd.openxmlformats-officedocument'
        '.spreadsheetml.sheet',
    'ppt'          => 'application/vnd.ms-powerpoint',
    'pptx'         => 'application/vnd.openxmlformats-officedocument'
        '.presentationml.presentation',
    'txt'          => 'text/plain',
    'mp4'          => 'video/mp4',
    'm4a'          => 'audio/mp4',
    'webm'         => 'video/webm',
    'ogg'          => 'audio/ogg',
    _              => 'application/octet-stream',
  };
}