library;

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/main.dart'; // navigatorKey

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
  static const _accessKey = 'access_token';
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

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  factory ApiClient() => instance;

  static const String _base = AppConfig.baseUrl;
  static const Duration _timeout = Duration(seconds: 30);

  final _storage = TokenStorage();

  // ── Dio (used for multipart only) ─────────────────────────────────────────

  late final Dio dio = _buildDio();

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: _base,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      receiveDataWhenStatusError: true,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      // inject token
      onRequest: (options, handler) async {
        final token = await _storage.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      // on 401 → refresh once → retry
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          if (await _tryRefresh()) {
            try {
              final retried = await dio.request(
                error.requestOptions.path,
                data: error.requestOptions.data,
                queryParameters: error.requestOptions.queryParameters,
                options: Options(
                  method: error.requestOptions.method,
                  headers: error.requestOptions.headers,
                ),
              );
              return handler.resolve(retried);
            } catch (_) {}
          }
          // refresh failed → go to login
          await _redirectToLogin();
        }
        handler.next(error);
      },
    ));

    return dio;
  }

  // ── package:http helpers ──────────────────────────────────────────────────

  Future<Map<String, String>> _headers({bool auth = true}) async {
    return {
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.acceptLanguageHeader: AppConfig.lang,
      if (auth) 'Authorization': 'Bearer ${await _storage.accessToken}',
    };
  }

  Future<http.Response> _send(
      Future<http.Response> Function(http.Client) fn,
      ) async {
    final client = http.Client();
    try {
      return await fn(client).timeout(_timeout);
    } finally {
      client.close();
    }
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.refreshToken;
    if (refresh == null) return false;

    try {
      final uri = Uri.parse('$_base/api/v1/auth/refresh')
          .replace(queryParameters: {'refresh_token': refresh});

      final res = await _send(
            (c) async => c.post(uri, headers: await _headers(auth: false)),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await _storage.save(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String? ?? refresh,
        );
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<void> _redirectToLogin() async {
    await _storage.clear();
    log("redirect to login===============>");
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ── Response handler ──────────────────────────────────────────────────────

  Future<dynamic> _handle(dynamic res) async {
    final int statusCode;
    final String requestPath;
    dynamic body;
    if (res is http.Response) {
      statusCode = res.statusCode;
      requestPath = res.request?.url.path ?? '';
      body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    } else if (res is Response) {
      statusCode = res.statusCode ?? 0;
      requestPath = res.realUri.path;
      body = res.data;
    } else {
      throw const ApiException(statusCode: 0, message: 'Unknown response type');
    }
    print("-------[$requestPath]---[ status code is ]-----[$statusCode]");
    // ── 204 No Content ────────────────────────────────────────────────────
    if (statusCode == 204) return true;

    // ── 401 Unauthorised → clear session → login ──────────────────────────
    if (statusCode == 401) {
      await _redirectToLogin();
      return null;
    }

    // ── 403 Forbidden → go to OTP / verification screen ──────────────────
    if (statusCode == 403) {
      navigatorKey.currentState?.pushNamed('/verify');
      return null;
    }

    // ── 2xx success ───────────────────────────────────────────────────────
    if (statusCode >= 200 && statusCode < 300) {
      log('[$requestPath] ${body ?? 'null'}');
      return body;
    }

    // ── All other errors ──────────────────────────────────────────────────
    String message = 'Request failed';
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      message = detail is String
          ? detail
          : (detail as List).map((e) => e['msg']).join(', ');
    }
    throw ApiException(statusCode: statusCode, message: message, body: body);
  }

  // ── URI builder ───────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, dynamic>? params]) {
    final q = params?.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return Uri.parse('$_base$path')
        .replace(queryParameters: (q?.isEmpty ?? true) ? null : q);
  }

  // ── GET ───────────────────────────────────────────────────────────────────

  Future<dynamic> get(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    var res = await _send(
          (c) async =>
          c.get(_uri(path, queryParams), headers: await _headers(auth: auth)),
    );
    // Mirror the Dio interceptor: on 401 try refresh once then redirect
    if (res.statusCode == 401 && auth) {
      if (await _tryRefresh()) {
        res = await _send(
              (c) async => c.get(_uri(path, queryParams),
              headers: await _headers(auth: auth)),
        );
      } else {
        await _redirectToLogin();
        return null;
      }
    }
    return _handle(res);
  }

  // ── POST ──────────────────────────────────────────────────────────────────

  Future<dynamic> post(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    var res = await _send(
          (c) async => c.post(
        _uri(path, queryParams),
        headers: await _headers(auth: auth),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    if (res.statusCode == 401 && auth) {
      if (await _tryRefresh()) {
        res = await _send(
              (c) async => c.post(
            _uri(path, queryParams),
            headers: await _headers(auth: auth),
            body: body != null ? jsonEncode(body) : null,
          ),
        );
      } else {
        await _redirectToLogin();
        return null;
      }
    }
    return _handle(res);
  }

  // ── PUT ───────────────────────────────────────────────────────────────────

  Future<dynamic> put(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    var res = await _send(
          (c) async => c.put(
        _uri(path, queryParams),
        headers: await _headers(auth: auth),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    if (res.statusCode == 401 && auth) {
      if (await _tryRefresh()) {
        res = await _send(
              (c) async => c.put(
            _uri(path, queryParams),
            headers: await _headers(auth: auth),
            body: body != null ? jsonEncode(body) : null,
          ),
        );
      } else {
        await _redirectToLogin();
        return null;
      }
    }
    return _handle(res);
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<dynamic> delete(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    var res = await _send(
          (c) async => c.delete(_uri(path, queryParams),
          headers: await _headers(auth: auth)),
    );
    if (res.statusCode == 401 && auth) {
      if (await _tryRefresh()) {
        res = await _send(
              (c) async => c.delete(_uri(path, queryParams),
              headers: await _headers(auth: auth)),
        );
      } else {
        await _redirectToLogin();
        return null;
      }
    }
    return _handle(res);
  }

  // ── Upload image (Dio multipart) ──────────────────────────────────────────

  Future<dynamic> uploadImage(
      String path, {
        required XFile file,
        String fieldName = 'file',
      }) async {
    final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final mime = _imageMime(ext);
    final bytes = await file.readAsBytes();
    final name = p.basename(file.path).isNotEmpty
        ? p.basename(file.path)
        : 'upload.${ext.isEmpty ? 'jpg' : ext}';

    final res = await dio.post(
      _uri(path).toString(),
      data: FormData.fromMap({
        fieldName: MultipartFile.fromBytes(
          bytes,
          filename: name,
          contentType: MediaType.parse(mime),
        ),
      }),
    );
    return _handle(res);
  }

  // ── POST multipart (fields + file) ───────────────────────────────────────

  Future<dynamic> postMultipart(
      String path, {
        required Map<String, String> fields,
        required String fileField,
        required String fileName,
        required Uint8List fileBytes,
      }) async {
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final mime = _fileMime(ext);

    final res = await dio.post(
      _uri(path).toString(),
      data: FormData.fromMap({
        ...fields,
        fileField: MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
          contentType: MediaType.parse(mime),
        ),
      }),
    );
    return _handle(res);
  }

  // ── Token helpers (called by AuthProvider) ────────────────────────────────

  Future<void> saveTokens({required String access, required String refresh}) =>
      _storage.save(access: access, refresh: refresh);

  Future<void> clearTokens() => _storage.clear();

  // ── MIME helpers ──────────────────────────────────────────────────────────

  static String _imageMime(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };

  static String _fileMime(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'jpg' || 'jpeg' => 'image/jpeg',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}