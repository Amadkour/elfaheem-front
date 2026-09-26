library;

import 'dart:async';
import 'dart:convert';
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

// ── User-facing messages (single place to translate / edit) ──────────────────

class ApiMessages {
  ApiMessages._();

  static const network = 'No internet connection. Please check your network and try again.';
  static const timeout = 'The request took too long. Please try again.';
  static const cancelled = 'The request was cancelled.';
  static const badCertificate = 'Could not establish a secure connection.';
  static const badRequest = 'The request could not be processed.';
  static const unauthorized = 'Your session has expired. Please log in again.';
  static const forbidden = 'You do not have permission to do this.';
  static const notFound = 'The requested item was not found.';
  static const conflict = 'This action conflicts with existing data.';
  static const validation = 'Some of the submitted data is invalid.';
  static const rateLimited = 'Too many requests. Please wait a moment and try again.';
  static const server = 'Something went wrong on our side. Please try again later.';
  static const unknown = 'Something went wrong. Please try again.';
}

// ── Exception ─────────────────────────────────────────────────────────────────

enum ApiErrorType {
  network,
  timeout,
  cancelled,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  server,
  unknown,
}

/// The ONLY exception type that ApiClient throws.
///
/// [message] is always safe to show to the user.
/// [body] keeps the raw server payload for debugging / special handling.
///
/// Usage in UI:
/// ```dart
/// try {
///   await api.post('/x');
/// } catch (e) {
///   showSnackBar(ApiException.from(e).message);
/// }
/// ```
class ApiException implements Exception {
  final int statusCode; // 0 = no HTTP response (network, timeout, …)
  final ApiErrorType type;
  final String message;
  final dynamic body;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.type = ApiErrorType.unknown,
    this.body,
  });

  bool get isNetwork => type == ApiErrorType.network;
  bool get isTimeout => type == ApiErrorType.timeout;
  bool get isCancelled => type == ApiErrorType.cancelled;
  bool get isUnauthorized => type == ApiErrorType.unauthorized;
  bool get isNotFound => type == ApiErrorType.notFound;
  bool get isValidation => type == ApiErrorType.validation;

  /// Safe to retry automatically (transient failures only).
  bool get isRetryable =>
      type == ApiErrorType.network ||
          type == ApiErrorType.timeout ||
          type == ApiErrorType.server;

  /// Converts ANY error into an [ApiException].
  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) return ApiException.fromDio(error);
    return ApiException(
      statusCode: 0,
      type: ApiErrorType.unknown,
      message: ApiMessages.unknown,
      body: error.toString(),
    );
  }

  factory ApiException.fromDio(DioException e) {
    final nested = e.error;
    if (nested is ApiException) return nested;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          statusCode: 0,
          type: ApiErrorType.timeout,
          message: ApiMessages.timeout,
        );

      case DioExceptionType.cancel:
        return const ApiException(
          statusCode: 0,
          type: ApiErrorType.cancelled,
          message: ApiMessages.cancelled,
        );

      case DioExceptionType.badCertificate:
        return const ApiException(
          statusCode: 0,
          type: ApiErrorType.network,
          message: ApiMessages.badCertificate,
        );

      case DioExceptionType.connectionError:
        return const ApiException(
          statusCode: 0,
          type: ApiErrorType.network,
          message: ApiMessages.network,
        );

      case DioExceptionType.badResponse:
        return ApiException.fromResponse(e.response);

      case DioExceptionType.unknown:
        if (nested is SocketException) {
          return const ApiException(
            statusCode: 0,
            type: ApiErrorType.network,
            message: ApiMessages.network,
          );
        }
        // Flutter Web: CORS / offline failures land here with no response.
        if (e.response == null) {
          return ApiException(
            statusCode: 0,
            type: ApiErrorType.network,
            message: ApiMessages.network,
            body: nested?.toString(),
          );
        }
        return ApiException.fromResponse(e.response);
      case DioExceptionType.transformTimeout:
        return const ApiException(
          statusCode: 0,
          type: ApiErrorType.network,
          message: ApiMessages.network,
        );
    }
  }

  factory ApiException.fromResponse(Response? res) {
    final status = res?.statusCode ?? 0;
    final body = res?.data;
    final type = _typeFor(status);
    final serverMsg = _messageFromBody(body);

    // Never leak raw 5xx internals to users; the body is still available.
    final message = type == ApiErrorType.server
        ? ApiMessages.server
        : (serverMsg ?? _defaultMessage(type));

    return ApiException(
      statusCode: status,
      type: type,
      message: message,
      body: body,
    );
  }

  static ApiErrorType _typeFor(int s) => switch (s) {
    400 => ApiErrorType.badRequest,
    401 => ApiErrorType.unauthorized,
    403 => ApiErrorType.forbidden,
    404 => ApiErrorType.notFound,
    409 => ApiErrorType.conflict,
    422 => ApiErrorType.validation,
    429 => ApiErrorType.rateLimited,
    >= 500 => ApiErrorType.server,
    _ => ApiErrorType.unknown,
  };

  static String _defaultMessage(ApiErrorType t) => switch (t) {
    ApiErrorType.badRequest => ApiMessages.badRequest,
    ApiErrorType.unauthorized => ApiMessages.unauthorized,
    ApiErrorType.forbidden => ApiMessages.forbidden,
    ApiErrorType.notFound => ApiMessages.notFound,
    ApiErrorType.conflict => ApiMessages.conflict,
    ApiErrorType.validation => ApiMessages.validation,
    ApiErrorType.rateLimited => ApiMessages.rateLimited,
    ApiErrorType.server => ApiMessages.server,
    ApiErrorType.network => ApiMessages.network,
    ApiErrorType.timeout => ApiMessages.timeout,
    ApiErrorType.cancelled => ApiMessages.cancelled,
    ApiErrorType.unknown => ApiMessages.unknown,
  };

  /// Understands every shape FastAPI (and common backends) return:
  ///
  ///  {"detail": "User not found"}
  ///  {"detail": [{"loc": ["body","email"], "msg": "field required"}]}
  ///  {"detail": {"message": "..."}}
  ///  {"message": "..."} / {"error": "..."} / plain string / JSON string
  static String? _messageFromBody(dynamic body) {
    if (body is String) {
      final t = body.trim();
      if (t.isEmpty || t.startsWith('<')) return null; // empty or HTML page
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          return _messageFromBody(jsonDecode(t));
        } catch (_) {}
      }
      return t.length <= 200 ? t : null;
    }

    if (body is Map) {
      for (final key in const ['detail', 'message', 'error', 'msg']) {
        final m = _messageFromValue(body[key]);
        if (m != null) return m.replaceAll(" ", "_").toLowerCase().tr;
      }
      return null;
    }

    if (body is List) return _messageFromValue(body);
    return null;
  }

  static String? _messageFromValue(dynamic v) {
    if (v == null) return null;

    if (v is String) return v.trim().isEmpty ? null : v.trim();

    if (v is Map) return _messageFromBody(v);

    if (v is List) {
      final msgs = <String>[];

      for (final item in v) {
        if (item is Map) {
          final msg = item['msg']?.toString();
          if (msg == null || msg.isEmpty) continue;

          final loc = item['loc'];
          final field = (loc is List && loc.isNotEmpty && loc.last is String)
              ? loc.last as String
              : null;

          msgs.add(field != null ? '$field: $msg' : msg);
        } else if (item != null) {
          msgs.add(item.toString());
        }
      }

      return msgs.isEmpty ? null : msgs.join('\n');
    }

    return v.toString();
  }

  @override
  String toString() => 'ApiException($statusCode, ${type.name}): $message';
}

// ── Token Storage ─────────────────────────────────────────────────────────────

class TokenStorage {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  Future<void> save({
    required String access,
    required String refresh,
  }) async {
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

// ── Logging interceptor (only attached when AppConfig.showLogs == true) ──────

class _ApiLogInterceptor extends Interceptor {
  static const _tsKey = '_log_ts';
  static const _maxBodyChars = 4000;
  static const _sensitiveKeys = {
    'authorization',
    'password',
    'new_password',
    'old_password',
    'current_password',
    'access_token',
    'refresh_token',
    'token',
    'secret',
  };

  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_tsKey] = DateTime.now().millisecondsSinceEpoch;

    final b = StringBuffer()
      ..writeln('┌── REQUEST ─────────────────────────────')
      ..writeln('│ ${options.method} ${_safeUri(options)}');

    if (options.queryParameters.isNotEmpty) {
      b.writeln('│ Query   : ${_pretty(_redact(options.queryParameters))}');
    }

    final headers = _redact(options.headers);
    if ((headers as Map).isNotEmpty) {
      b.writeln('│ Headers : ${_pretty(headers)}');
    }

    if (options.data != null) {
      b.writeln('│ Body    : ${_describeBody(options.data)}');
    }

    b.write('└────────────────────────────────────────');
    log(b.toString(), name: 'API');

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final b = StringBuffer()
      ..writeln('┌── RESPONSE ────────────────────────────')
      ..writeln(
        '│ ${response.requestOptions.method} '
            '${_safeUri(response.requestOptions)}',
      )
      ..writeln('│ Status  : ${response.statusCode} '
          '(${_elapsed(response.requestOptions)})')
      ..writeln('│ Body    : ${_describeBody(response.data)}')
      ..write('└────────────────────────────────────────');

    log(b.toString(), name: 'API');

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final b = StringBuffer()
      ..writeln('┌── ERROR ───────────────────────────────')
      ..writeln(
        '│ ${err.requestOptions.method} ${_safeUri(err.requestOptions)}',
      )
      ..writeln('│ Type    : ${err.type.name} '
          '(${_elapsed(err.requestOptions)})');

    if (err.response != null) {
      b
        ..writeln('│ Status  : ${err.response?.statusCode}')
        ..writeln('│ Body    : ${_describeBody(err.response?.data)}');
    } else {
      b.writeln('│ Message : ${err.message ?? err.error}');
    }

    b.write('└────────────────────────────────────────');
    log(b.toString(), name: 'API', level: 900);

    handler.next(err);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _elapsed(RequestOptions o) {
    final start = o.extra[_tsKey];
    if (start is! int) return '-';
    return '${DateTime.now().millisecondsSinceEpoch - start}ms';
  }

  String _safeUri(RequestOptions o) {
    final query = o.queryParameters.isEmpty
        ? ''
        : '?${_redact(o.queryParameters).entries.map((e) => '${e.key}=${e.value}').join('&')}';
    return '${o.baseUrl}${o.path}$query';
  }

  String _describeBody(dynamic data) {
    if (data == null) return 'null';

    if (data is FormData) {
      return _pretty({
        'fields': _redact({for (final f in data.fields) f.key: f.value}),
        'files': [
          for (final f in data.files)
            '${f.key}: ${f.value.filename} (${f.value.length} bytes)',
        ],
      });
    }

    if (data is Uint8List || data is List<int>) {
      return '<binary ${(data as List).length} bytes>';
    }

    return _pretty(_redact(data));
  }

  String _pretty(dynamic data) {
    String out;

    try {
      out = (data is Map || data is List) ? _encoder.convert(data) : '$data';
    } catch (_) {
      out = data.toString();
    }

    if (out.length > _maxBodyChars) {
      out = '${out.substring(0, _maxBodyChars)}… (truncated ${out.length - _maxBodyChars} chars)';
    }

    return out;
  }

  /// Recursively masks sensitive values so secrets never reach the console.
  dynamic _redact(dynamic v) {
    if (v is Map) {
      return {
        for (final e in v.entries)
          e.key.toString(): _sensitiveKeys.contains(e.key.toString().toLowerCase())
              ? '***'
              : _redact(e.value),
      };
    }

    if (v is List) return v.map(_redact).toList();

    return v;
  }
}

// ── ApiClient ─────────────────────────────────────────────────────────────────
//
// Every method (GET, POST, PUT, DELETE, multipart) goes through Dio and
// reports failures ONLY as [ApiException] with a friendly [message].
//
// Behaviour:
// - Non-2xx responses (e.g. 404 {"detail":"User not found"}) are converted
//   to ApiException("User not found") instead of leaking Dio's raw text.
// - 401 → single, de-duplicated token refresh → retry once → else login.
// - Network / timeout / cancel / CORS failures are mapped to clear messages.
// - AppConfig.showLogs == true logs request, response and error (secrets
//   redacted).

class ApiClient {

  ApiClient._();

  static final ApiClient instance = ApiClient._();

  factory ApiClient() => instance;

  static const String _base = AppConfig.baseUrl;

  // Public so room.dart can read the base URL for the JS compositor.
  String get baseUrl => _base;

  final _storage = TokenStorage();

  late final Dio _dio = _buildDio();

  // Kept for external code that accessed `apiClient.dio` directly.
  Dio get dio => _dio;

  // ── Dio setup ─────────────────────────────────────────────────────────────

  Dio _buildDio() {
    final d = Dio(
      BaseOptions(
        baseUrl: _base,
        connectTimeout: const Duration(minutes: 60),

        // Unlimited upload/download timeouts.
        sendTimeout: const Duration(minutes: 60),
        receiveTimeout: const Duration(minutes: 60),

        // Keep the error body so we can read {"detail": ...}.
        receiveDataWhenStatusError: true,

        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.acceptLanguageHeader: AppConfig.lang,
        },
      ),
    );

    // Logger first: it sees every request, response and error (including the
    // first 401 that the auth interceptor later recovers from).
    if (AppConfig.showLogs) {
      d.interceptors.add(_ApiLogInterceptor());
    }

    d.interceptors.add(_authInterceptor());

    return d;
  }

  Interceptor _authInterceptor() => InterceptorsWrapper(
    // ── Inject Bearer token ────────────────────────────────────────────────
    onRequest: (options, handler) async {
      if (options.extra['auth'] != false) {
        final token = await _storage.accessToken;

        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }

      handler.next(options);
    },

    // ── 401 → refresh once → retry; 403 → verify screen ───────────────────
    onError: (error, handler) async {
      final req = error.requestOptions;
      final status = error.response?.statusCode;
      final needsAuth = req.extra['auth'] != false;

      if (status == 403 && needsAuth) {
        _goToVerify();
        return handler.next(error);
      }

      if (status != 401 || !needsAuth) {
        return handler.next(error);
      }

      // Already retried and still 401 → session is really dead.
      if (req.extra['_retried'] == true) {
        await _redirectToLogin();
        return handler.next(error);
      }

      switch (await _refreshTokens()) {
        case _RefreshResult.ok:
          try {
            final retryReq = req.copyWith(
              headers: {
                ...req.headers,
                'Authorization': 'Bearer ${await _storage.accessToken}',
              },
              extra: {...req.extra, '_retried': true},
              // FormData can only be finalized once.
              data: req.data is FormData
                  ? (req.data as FormData).clone()
                  : req.data,
            );

            return handler.resolve(await _dio.fetch(retryReq));
          } on DioException catch (e) {
            return handler.next(e);
          }

        case _RefreshResult.rejected:
          await _redirectToLogin();
          return handler.next(error);

        case _RefreshResult.failed:
        // Network problem while refreshing: keep the session, surface error.
          return handler.next(error);
      }
    },
  );

  // ── Options helpers ───────────────────────────────────────────────────────

  /// POST/PUT/DELETE JSON calls.
  ///
  /// On Flutter Web application/json triggers a CORS preflight (OPTIONS);
  /// FastAPI's CORSMiddleware is expected to answer it.
  Options _jsonOpts({
    bool auth = true,
    required String method,
  }) =>
      Options(
        method: method,
        contentType: Headers.jsonContentType,
        receiveTimeout: const Duration(seconds: 30),
        extra: {'auth': auth},
      );

  /// GET calls: no Content-Type (avoids needless preflight on public GETs).
  /// Authenticated GETs may still preflight because of `Authorization`.
  Options _getOpts({bool auth = true}) => Options(
    method: 'GET',
    receiveTimeout: const Duration(seconds: 30),
    extra: {'auth': auth},
  );

  /// File uploads/downloads: no send/receive timeout.
  Options _fileOpts({bool auth = true, String method = 'POST'}) => Options(
    method: method,
    extra: {'auth': auth},
  );

  // ── Core executor ─────────────────────────────────────────────────────────

  /// Runs a Dio call and guarantees that the ONLY thing that can be thrown
  /// is an [ApiException]. Successful responses are unwrapped.
  Future<dynamic> _execute(Future<Response> Function() call) async {
    try {
      final res = await call();
      return _unwrap(res);
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  dynamic _unwrap(Response res) {
    final status = res.statusCode ?? 0;

    if (status == 204) return true;

    if (status >= 200 && status < 300) return res.data;

    // validateStatus normally prevents this, but stay safe.
    throw ApiException.fromResponse(res);
  }

  // ── Token refresh (de-duplicated) ─────────────────────────────────────────

  Future<_RefreshResult>? _refreshFuture;

  /// Parallel 401s share ONE refresh request.
  Future<_RefreshResult> _refreshTokens() =>
      _refreshFuture ??= _doRefresh().whenComplete(() => _refreshFuture = null);

  Future<_RefreshResult> _doRefresh() async {
    final refresh = await _storage.refreshToken;

    if (refresh == null) return _RefreshResult.rejected;

    try {
      final res = await _dio.post(
        '/api/v1/auth/refresh',
        queryParameters: {'refresh_token': refresh},
        options: Options(extra: {'auth': false, '_retried': true}),
      );

      final data = res.data;

      if (res.statusCode == 200 &&
          data is Map &&
          data['access_token'] is String) {
        await _storage.save(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String? ?? refresh,
        );

        return _RefreshResult.ok;
      }

      return _RefreshResult.rejected;
    } on DioException catch (e) {
      final s = e.response?.statusCode;

      // Server said the refresh token is no good → real logout.
      if (s != null && s >= 400 && s < 500) return _RefreshResult.rejected;

      // Offline / timeout / 5xx → don't log the user out.
      return _RefreshResult.failed;
    } catch (_) {
      return _RefreshResult.failed;
    }
  }

  // ── Navigation side-effects (guarded against duplicate pushes) ────────────

  bool _redirecting = false;
  bool _verifying = false;

  Future<void> _redirectToLogin() async {
    if (_redirecting) return;
    _redirecting = true;

    try {
      await _storage.clear();

      if (AppConfig.showLogs) log('redirect to login', name: 'API');

      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
            (_) => false,
      );
    } finally {
      Future.delayed(const Duration(seconds: 2), () => _redirecting = false);
    }
  }

  void _goToVerify() {
    if (_verifying) return;
    _verifying = true;

    navigatorKey.currentState?.pushNamed('/verify');

    Future.delayed(const Duration(seconds: 2), () => _verifying = false);
  }

  // ── Version check ─────────────────────────────────────────────────────────

  /// GET /app/version-check?version=x.y.z&platform=android|ios|web
  Future<Map<String, dynamic>> checkVersion({
    required String version,
    required String platform,
    CancelToken? cancelToken,
  }) async {
    final data = await _execute(
          () => _dio.get(
        '/app/version-check',
        queryParameters: {'version': version, 'platform': platform},
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          extra: {'auth': false},
        ),
      ),
    );

    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  // ── GET ───────────────────────────────────────────────────────────────────

  Future<dynamic> get(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
      }) =>
      _execute(
            () => _dio.get(
          path,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _getOpts(auth: auth),
        ),
      );

  // ── POST ──────────────────────────────────────────────────────────────────

  Future<dynamic> post(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
      }) =>
      _execute(
            () => _dio.post(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'POST'),
        ),
      );

  // ── PUT ───────────────────────────────────────────────────────────────────

  Future<dynamic> put(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
      }) =>
      _execute(
            () => _dio.put(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'PUT'),
        ),
      );

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<dynamic> delete(
      String path, {
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
      }) =>
      _execute(
            () => _dio.delete(
          path,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'DELETE'),
        ),
      );

  // ── Upload image ──────────────────────────────────────────────────────────

  Future<dynamic> uploadImage(
      String path, {
        required XFile file,
        String fieldName = 'file',
        void Function(int sent, int total)? onSendProgress,
        CancelToken? cancelToken,
      }) async {
    final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final mime = _imageMime(ext);

    final baseName = p.basename(file.path);
    final name = baseName.isNotEmpty
        ? baseName
        : 'upload.${ext.isEmpty ? 'jpg' : ext}';

    final bytes = await file.readAsBytes();

    return _execute(
          () => _dio.post(
        path,
        data: FormData.fromMap({
          fieldName: MultipartFile.fromBytes(
            bytes,
            filename: name,
            contentType: MediaType.parse(mime),
          ),
        }),
        options: _fileOpts(),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      ),
    );
  }

  // ── POST multipart ────────────────────────────────────────────────────────
  //
  // Streams from disk when [filePath] is usable (mobile/desktop), otherwise
  // falls back to [fileBytes] (web).
  //
  // Only transient failures (network, timeout, 5xx) are retried, up to
  // [maxRetries] times with a linear back-off of [retryDelay] * attempt.

  Future<dynamic> postMultipart(
      String path, {
        required Map<String, String> fields,
        required String fileField,
        required String fileName,
        String? filePath,
        Uint8List? fileBytes,
        bool auth = true,
        void Function(int sent, int total)? onSendProgress,
        int maxRetries = 0,
        Duration retryDelay = const Duration(seconds: 2),
        CancelToken? cancelToken,
      }) async {
    assert(
    filePath != null || fileBytes != null,
    'postMultipart: provide filePath or fileBytes',
    );

    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final mime = _fileMime(ext);

    // MultipartFile streams are single-use → build a fresh one per attempt.
    Future<MultipartFile> buildMultipartFile() async {
      if (!kIsWeb && filePath != null && File(filePath).existsSync()) {
        return MultipartFile.fromFile(
          filePath,
          filename: fileName,
          contentType: MediaType.parse(mime),
        );
      }

      if (fileBytes == null) {
        throw const ApiException(
          statusCode: 0,
          type: ApiErrorType.unknown,
          message: 'The selected file could not be read. Please pick it again.',
        );
      }

      return MultipartFile.fromBytes(
        fileBytes,
        filename: fileName,
        contentType: MediaType.parse(mime),
      );
    }

    var attempt = 0;

    while (true) {
      attempt++;

      try {
        final form = FormData.fromMap({
          ...fields,
          fileField: await buildMultipartFile(),
        });

        return await _execute(
              () => _dio.post(
            path,
            data: form,
            options: _fileOpts(auth: auth),
            onSendProgress: onSendProgress,
            cancelToken: cancelToken,
          ),
        );
      } on ApiException catch (e) {
        if (!e.isRetryable || attempt > maxRetries) rethrow;

        final wait = retryDelay * attempt;

        if (AppConfig.showLogs) {
          log(
            '[postMultipart] $path attempt $attempt failed '
                '(${e.type.name}, status=${e.statusCode}) — retrying in '
                '${wait.inSeconds}s',
            name: 'API',
          );
        }

        await Future.delayed(wait);
      }
    }
  }

  // ── Token helpers ─────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) =>
      _storage.save(access: access, refresh: refresh);

  Future<void> clearTokens() => _storage.clear();

  Future<String?> get accessToken => _storage.accessToken;

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
    'mp4' => 'video/mp4',
    'm4a' => 'audio/mp4',
    'webm' => 'video/webm',
    'ogg' => 'audio/ogg',
    _ => 'application/octet-stream',
  };
}

enum _RefreshResult { ok, rejected, failed }