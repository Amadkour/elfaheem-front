library;

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../models/user.dart';

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

  /// How many times _send() will attempt the raw TCP+HTTP call.
  /// 3 = first attempt + 2 automatic retries inside the transport layer,
  /// completely transparent to BaseProvider.
  static const int _sendMaxTries = 3;

  /// Pause between consecutive _send() tries.
  /// Index 0 → delay after attempt 1 (1 s).
  /// Index 1 → delay after attempt 2 (2 s).
  static const List<Duration> _sendDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final _storage = TokenStorage();

  Future<http.Response> _send(
    Future<http.Response> Function(http.Client) fn,
  ) async {
    for (int attempt = 1; attempt <= _sendMaxTries; attempt++) {
      final client = http.Client();
      try {
        return await fn(client); // happy path — return immediately
      } on ApiException {
        rethrow; // server error: never retry at transport level
      } catch (e) {
        final isLast = attempt >= _sendMaxTries;
        debugPrint(
          '🔌 _send attempt $attempt/$_sendMaxTries: $e'
          '${isLast ? " → giving up, re-throwing" : " → retrying…"}',
        );
        if (isLast) rethrow;
        await Future.delayed(_sendDelays[attempt - 1]);
      } finally {
        client.close(); // always release the socket, even on success
      }
    }
    throw StateError('_send: unreachable'); // satisfies the compiler
  }

  // ── Auth header ───────────────────────────────────────────────────────────

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

  // ── Response handler ──────────────────────────────────────────────────────

  dynamic _handleResponse(http.Response res) {
    if (res.statusCode == 204) return true;

    final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if(res.statusCode==403) {
      if(context!=null) {
        Navigator.of(context!).push(MaterialPageRoute(builder: (c){
          UserModel? u=c.read<AuthProvider>().currentUser;

          return OtpVerificationScreen(email: u?.gmail??'', role: u?.role??'');
        }));
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300){
      log("=================[${res.request?.url.path}]====================");
      log(res.body);
      log("====================================");
      return body;}

    String message = 'Request failed';
    if (body is Map && body.containsKey('detail')) {
      final detail = body['detail'];
      message = detail is String
          ? detail
          : (detail as List?)?.map((e) => e['msg']).join(', ') ?? message;
    }

    throw ApiException(
        statusCode: res.statusCode, message: message, body: body);
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
      (c) async =>
          c.delete(uri, headers: await _headers(auth: auth)).timeout(_timeout),
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

  // ── POST multipart ────────────────────────────────────────────────────────

  /// Used for `POST /api/v1/courses` — multipart/form-data with optional logo.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    File? imageFile,
    String imageFieldName = 'logo',
    bool auth = true,
  }) async {
    final uri = _buildUri(path, null);
    final headers = await _headers(auth: auth)
        // ..remove(HttpHeaders.contentTypeHeader)
        ;

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields.addAll(fields);

    if (imageFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath(imageFieldName, imageFile.path,
            contentType: http.MediaType.parse('image/jpeg')),
      );
    }

    final streamed = await request.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }

  // ── Upload image ──────────────────────────────────────────────────────────

  Future<dynamic> uploadImage(
    String path, {
    required File file,
    String fieldName = 'file',
    bool auth = true,
  }) async {
    final uri = _buildUri(path, null);
    final headers = await _headers(auth: auth)
      ..remove(HttpHeaders.contentTypeHeader);

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..files.add(await http.MultipartFile.fromPath(fieldName, file.path));

    final streamed = await request.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }

  // ── Legacy uploadFile ─────────────────────────────────────────────────────

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
      _storage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
}
