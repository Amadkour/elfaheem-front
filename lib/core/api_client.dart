library;

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;


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

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, accessToken);
    await prefs.setString(_refreshKey, refreshToken);
  }

  Future<String?> getAccessToken() async =>
      (await SharedPreferences.getInstance()).getString(_accessKey);

  Future<String?> getRefreshToken() async =>
      (await SharedPreferences.getInstance()).getString(_refreshKey);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}

// ── API Client ────────────────────────────────────────────────────────────────

class ApiClient {
  ApiClient._internal();
  BuildContext? context;
  static final ApiClient instance = ApiClient._internal();

  factory ApiClient() => instance;

  static const String baseUrl = AppConfig.baseUrl;
  static const Duration _timeout = Duration(seconds: 30);

  static const int _sendMaxTries = 3;
  static const List<Duration> _sendDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final _storage = TokenStorage();

  // ── Shared Dio instance with interceptor ──────────────────────────────────

  late final Dio _dio = _buildDio();

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      receiveDataWhenStatusError: true,
    ));

    dio.interceptors.add(
      InterceptorsWrapper(
        // ── Inject Bearer token before every request ──────────────────────
        onRequest: (options, handler) async {
          final token = await _storage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          handler.next(options);
        },

        // ── On 401 → refresh token → retry once ──────────────────────────
        onError: (DioException error, handler) async {
          final response = error.response;

          if (response?.statusCode == 401) {
            final refreshed = await _refreshToken();
            if (refreshed) {
              try {
                // Retry the failed request — onRequest interceptor will
                // re-inject the new token automatically.
                final retryOptions = Options(
                  method: error.requestOptions.method,
                  headers: error.requestOptions.headers,
                );

                final retryResponse = await dio.request(
                  error.requestOptions.path,
                  data: error.requestOptions.data,
                  queryParameters: error.requestOptions.queryParameters,
                  options: retryOptions,
                );

                return handler.resolve(retryResponse);
              } catch (e) {
                return handler.next(error);
              }
            }
          }

          handler.next(error);
        },
      ),
    );

    return dio;
  }

  /// Exposed so providers can call _api.dio.post(...) directly for multipart.
  Dio get dio => _dio;

  // ── package:http transport ────────────────────────────────────────────────

  Future<http.Response> _send(
      Future<http.Response> Function(http.Client) fn,
      ) async {
    for (int attempt = 1; attempt <= _sendMaxTries; attempt++) {
      final client = http.Client();
      try {
        return await fn(client);
      } on ApiException {
        rethrow;
      } catch (e) {
        final isLast = attempt >= _sendMaxTries;
        debugPrint(
          '🔌 _send attempt $attempt/$_sendMaxTries: $e'
              '${isLast ? " → giving up" : " → retrying…"}',
        );
        if (isLast) rethrow;
        await Future.delayed(_sendDelays[attempt - 1]);
      } finally {
        client.close();
      }
    }
    throw StateError('_send: unreachable');
  }

  // ── Auth headers (for package:http requests only) ─────────────────────────

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.connectionHeader: 'keep-alive',
    };
    if (auth) {
      final token = await _storage.getAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  Future<bool> _refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;

    final uri =
    Uri.parse('$baseUrl/api/v1/auth/refresh?refresh_token=$refresh');

    final res = await _send(
          (c) async =>
          c.post(uri, headers: await _headers(auth: false)).timeout(_timeout),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _storage.saveTokens(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String? ??
            (await _storage.getRefreshToken())!,
      );
      return true;
    }
    return false;
  }

  // ── Response handler (http + dio) ─────────────────────────────────────────

  dynamic _handleResponse(dynamic res) {
    final int statusCode;
    dynamic body;
    String? requestPath;

    if (res is http.Response) {
      statusCode = res.statusCode;
      requestPath = res.request?.url.path;
      body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    } else if (res is Response) {
      // dio.Response — JSON already decoded by dio
      statusCode = res.statusCode ?? 0;
      requestPath = res.realUri.path;
      body = res.data;
    } else {
      throw ApiException(
        statusCode: 0,
        message: 'Unknown response type: ${res.runtimeType}',
        body: null,
      );
    }

    if (statusCode == 204) return true;

    if (statusCode == 403 && context != null) {
      Navigator.of(context!).push(MaterialPageRoute(builder: (c) {
        final UserModel? u = c.read<AuthProvider>().currentUser;
        return OtpVerificationScreen(
          email: u?.gmail ?? '',
          role: u?.role ?? '',
        );
      }));
    }

    if (statusCode >= 200 && statusCode < 300) {
      log('=================[$requestPath]====================');
      log(body?.toString() ?? 'null');
      log('====================================');
      return body;
    }

    String message = 'Request failed';
    if (body is Map && body.containsKey('detail')) {
      final detail = body['detail'];
      message = detail is String
          ? detail
          : (detail as List?)?.map((e) => e['msg']).join(', ') ?? message;
    }

    throw ApiException(statusCode: statusCode, message: message, body: body);
  }

  // ── GET ───────────────────────────────────────────────────────────────────

  Future<dynamic> get(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final uri = _buildUri(path, queryParams);
    var res = await _send(
          (c) async =>
          c.get(uri, headers: await _headers(auth: auth)).timeout(_timeout),
    );
    if (res.statusCode == 401 && auth) {
      if (await _refreshToken()) {
        res = await _send(
              (c) async => c.get(uri, headers: await _headers()).timeout(_timeout),
        );
      }
    }
    return _handleResponse(res);
  }

  // ── POST ──────────────────────────────────────────────────────────────────

  Future<dynamic> post(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final uri = _buildUri(path, queryParams);
    var res = await _send(
          (c) async => c
          .post(uri,
          headers: await _headers(auth: auth),
          body: body != null ? jsonEncode(body) : null)
          .timeout(_timeout),
    );
    if (res.statusCode == 401 && auth) {
      if (await _refreshToken()) {
        res = await _send(
              (c) async => c
              .post(uri,
              headers: await _headers(),
              body: body != null ? jsonEncode(body) : null)
              .timeout(_timeout),
        );
      }
    }
    return _handleResponse(res);
  }

  // ── PUT ───────────────────────────────────────────────────────────────────

  Future<dynamic> put(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final uri = _buildUri(path, queryParams);
    var res = await _send(
          (c) async => c
          .put(uri,
          headers: await _headers(auth: auth),
          body: body != null ? jsonEncode(body) : null)
          .timeout(_timeout),
    );
    if (res.statusCode == 401 && auth) {
      if (await _refreshToken()) {
        res = await _send(
              (c) async => c
              .put(uri,
              headers: await _headers(),
              body: body != null ? jsonEncode(body) : null)
              .timeout(_timeout),
        );
      }
    }
    return _handleResponse(res);
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<dynamic> delete(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
      }) async {
    final uri = _buildUri(path, queryParams);
    var res = await _send(
          (c) async => c
          .delete(uri, headers: await _headers(auth: auth))
          .timeout(_timeout),
    );
    if (res.statusCode == 401 && auth) {
      if (await _refreshToken()) {
        res = await _send(
              (c) async =>
              c.delete(uri, headers: await _headers()).timeout(_timeout),
        );
      }
    }
    return _handleResponse(res);
  }

  // ── Upload image (multipart POST via Dio) ─────────────────────────────────
  //
  // Token is injected automatically by the Dio interceptor — no manual
  // _applyDioAuth() call needed.

  Future<dynamic> uploadImage(
      String path, {
        required XFile file,
        String fieldName = 'file',
        bool auth = true,
      }) async {
    final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final bytes = await file.readAsBytes();

    final filename = p.basename(file.path).isNotEmpty
        ? p.basename(file.path)
        : 'upload.${ext.isEmpty ? 'jpg' : ext}';

    final formData = FormData.fromMap({
      fieldName: MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: MediaType.parse(mime),
      ),
    });

    final uri = _buildUri(path, null);

    final response = await _dio
        .post(
      uri.toString(),
      data: formData,
    )
        .timeout(_timeout);

    return _handleResponse(response);
  }

  // ── POST multipart (form fields + optional image) ─────────────────────────
  //
  // Token is injected automatically by the Dio interceptor — no manual
  // _applyDioAuth() call needed.

  Future<dynamic> postMultipart(
      String path, {
        required Map<String, String> fields,
        XFile? imageFile,
        String imageFieldName = 'logo',
        bool auth = true,
      }) async {
    final formMap = <String, dynamic>{...fields};

    if (imageFile != null) {
      final ext =
      p.extension(imageFile.path).replaceFirst('.', '').toLowerCase();
      final mime = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

      final bytes = await imageFile.readAsBytes();
      final filename = p.basename(imageFile.path).isNotEmpty
          ? p.basename(imageFile.path)
          : 'upload.${ext.isEmpty ? 'jpg' : ext}';

      formMap[imageFieldName] = MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: MediaType.parse(mime),
      );
    }

    final formData = FormData.fromMap(formMap);
    final uri = _buildUri(path, null);

    final response =
    await _dio.post(uri.toString(), data: formData).timeout(_timeout);

    return _handleResponse(response);
  }

  // ── Legacy uploadFile (kept for backward compat, mobile only) ────────────

  Future<dynamic> uploadFile(
      String path, {
        required File file,
        required Map<String, String> fields,
        bool auth = true,
      }) async {
    final uri = _buildUri(path, null);
    final headers = await _headers(auth: auth)
      ..remove(HttpHeaders.contentTypeHeader);

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }

  // ── URI builder ───────────────────────────────────────────────────────────

  Uri _buildUri(String path, Map<String, dynamic>? queryParams) {
    final params = queryParams?.map(
          (k, v) => MapEntry(k, v?.toString() ?? ''),
    );
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: (params?.isEmpty ?? true) ? null : params,
    );
  }

  // ── Token helpers ─────────────────────────────────────────────────────────

  Future<void> clearTokens() => _storage.clear();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      _storage.saveTokens(
          accessToken: accessToken, refreshToken: refreshToken);
}