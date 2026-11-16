library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';   // add cryptography: ^2.7.0 to pubspec.yaml
import 'package:dio/dio.dart';
import 'package:dio/io.dart';           // IOHttpClientAdapter — mobile only
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/token_storage.dart';
import 'package:flutter_education_app/core/cert_pin.dart';
import 'package:flutter_education_app/core/attention/decision_refresh.dart';
import 'package:flutter_education_app/main.dart';
import 'package:flutter/material.dart' show MaterialPageRoute, RouteSettings;
import '../features/admin/admin_mfa_page.dart' show AdminMfaPage;
import '../features/auth/account_fee_page.dart' show AccountFeePage;
import '../features/auth/teacher_onboarding_token.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'guest_link_visit.dart';
import 'package:flutter_education_app/features/courses/student/security/device_blocked_dialog.dart';
import 'package:flutter_education_app/features/courses/student/security/device_id_service.dart';
import 'package:flutter_education_app/features/courses/student/security/device_security_provider.dart';
import '../utils/widget/view_as_state.dart';

// ── User-facing messages (single place to translate / edit) ──────────────────

class ApiMessages {
  ApiMessages._();

  static const network = 'No internet connection. Please check your network and try again.';
  static const timeout = 'The request took too long. Please try again.';
  static const cancelled = 'The request was cancelled.';
  static const badCertificate = 'Could not establish a secure connection.';
  static const badRequest = 'The request could not be processed.';
  static const unauthorized = 'Your session has expired. Please log in again.';
  static const forbidden = 'Sorry, this action isn\'t available for your account right now.';
  static const notFound = 'The requested item was not found.';
  static const conflict = 'This action conflicts with existing data.';
  static const validation = 'Some of the submitted data is invalid.';
  static const rateLimited = 'Too many requests. Please wait a moment and try again.';
  // 503 `server_busy`: the Exam Engine / RAG in-flight cap (back D-038) — a moment's wait, not a failure
  static const serverBusyAr = 'الخادم مشغول الآن — أعد المحاولة بعد لحظات';
  static const serverBusyEn = 'The server is busy right now — try again in a moment.';
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

/// What kind of failure an [ApiException] is, for the person reading it (UX v3): the server's `kind` when it sends
/// one, otherwise derived from the status. [network] = no HTTP response at all.
enum ApiErrorKind { validation, permission, conflict, notFound, rateLimit, network, server, unknown }

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

  /// Machine code for our own coded errors: DEVICE_MISMATCH, DEVICE_ID_MISSING,
  /// VIEW_LIMIT_REACHED, SWITCH_LIMIT, ... (null for everything else).
  final String? code;

  /// The response's `X-Request-Id` header (null when there was no response or the server sent none).
  final String? requestId;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.type = ApiErrorType.unknown,
    this.body,
    this.code,
    this.requestId,
  });

  // ── UX v3: actionable errors (every value below is derived from [body], so a hand-built exception works too) ──

  static bool get _en => AppConfig.lang != 'ar';

  /// Arabic `x` / English `x_en` from [m], in the current language (falls back to whichever exists).
  static String? _pick(Map m, String key) {
    final ar = m[key]?.toString();
    final en = m['${key}_en']?.toString();
    final a = (ar == null || ar.trim().isEmpty) ? null : ar;
    final e = (en == null || en.trim().isEmpty) ? null : en;
    return _en ? (e ?? a) : (a ?? e);
  }

  /// The coded `detail` object (`{}` when detail is a string, a pydantic list or absent).
  Map get detail => asMap(asMap(body)?['detail']) ?? const {};

  /// The top-level `error` object a 422 carries next to pydantic's `detail` list (`{}` when absent).
  Map get _error => asMap(asMap(body)?['error']) ?? const {};

  /// The object that carries kind / fields / fix: the coded detail first, then the 422 `error`.
  Map get _rich => detail.isNotEmpty ? detail : _error;

  ApiErrorKind get kind {
    final k = (_rich['kind'] ?? '').toString();
    switch (k) {
      case 'validation': return ApiErrorKind.validation;
      case 'permission': return ApiErrorKind.permission;
      case 'conflict': return ApiErrorKind.conflict;
      case 'not_found': return ApiErrorKind.notFound;
      case 'rate_limit': return ApiErrorKind.rateLimit;
      case 'server': return ApiErrorKind.server;
      case 'network': return ApiErrorKind.network;
    }
    return switch (type) {
      ApiErrorType.network || ApiErrorType.timeout => ApiErrorKind.network,
      ApiErrorType.badRequest || ApiErrorType.validation => ApiErrorKind.validation,
      ApiErrorType.forbidden => ApiErrorKind.permission,
      ApiErrorType.conflict => ApiErrorKind.conflict,
      ApiErrorType.notFound => ApiErrorKind.notFound,
      ApiErrorType.rateLimited => ApiErrorKind.rateLimit,
      ApiErrorType.server => ApiErrorKind.server,
      _ => statusCode >= 500 ? ApiErrorKind.server : ApiErrorKind.unknown,
    };
  }

  /// Every bad field with its text in the current language: the server's `fields`, else (older server) the
  /// pydantic `detail` list's `loc` / `msg`, else the single `field` with the message.
  List<(String, String)> get fields {
    final out = <(String, String)>[];
    final raw = _rich['fields'];
    if (raw is List) {
      for (final f in raw) {
        if (f is! Map) continue;
        final name = f['field']?.toString() ?? '';
        if (name.isEmpty) continue;
        out.add((name, _pick(f, 'message') ?? message));
      }
    }
    if (out.isEmpty) {
      final d = asMap(body)?['detail'];
      if (d is List) {
        for (final item in d) {
          if (item is! Map) continue;
          final loc = item['loc'];
          final name = (loc is List && loc.isNotEmpty) ? loc.last.toString() : '';
          final msg = item['msg']?.toString() ?? '';
          if (name.isNotEmpty && name != 'body') out.add((name, msg.isEmpty ? message : msg));
        }
      }
    }
    final one = field;
    if (out.isEmpty && one != null) out.add((one, message));
    return out;
  }

  /// The one field the error is about (`detail.field`), or the first of [fields]' server list.
  String? get field {
    final f = _rich['field']?.toString();
    if (f != null && f.isNotEmpty) return f;
    final raw = _rich['fields'];
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      final n = (raw.first as Map)['field']?.toString();
      if (n != null && n.isNotEmpty) return n;
    }
    return null;
  }

  /// The server's "how to fix it" sentence in the current language.
  String? get fix => _pick(_rich, 'fix');

  /// A one-tap fix the server offers (`add_member`, …); the caller decides whether it can run it.
  String? get fixAction {
    final a = _rich['fix_action']?.toString();
    return (a == null || a.isEmpty) ? null : a;
  }

  /// The reference id to quote to support: the body's `ref`, else the `X-Request-Id` header on a 5xx.
  String? get ref {
    final r = _rich['ref']?.toString();
    if (r != null && r.isNotEmpty) return r;
    return (statusCode >= 500 && requestId != null && requestId!.isNotEmpty) ? requestId : null;
  }

  bool get isDeviceBlocked => code == 'DEVICE_MISMATCH' || code == 'DEVICE_ID_MISSING';
  bool get isViewLimit => code == 'VIEW_LIMIT_REACHED';

  /// {"detail": {"code": "X", "message": "..."}} -> (code, message)
  ///
  /// Accepts a Map, a JSON String (some web/proxy paths deliver the body as a
  /// raw String) or null. Never throws.
  static (String?, String?) codedDetail(dynamic body) {
    final map = asMap(body);
    if (map != null && map['detail'] is Map) {
      final d = map['detail'] as Map;
      final code = d['code']?.toString();
      if (code != null && code.isNotEmpty) return (code, d['message']?.toString());
    }
    return (null, null);
  }

  /// Normalises a response body: Map as-is, JSON String decoded, anything
  /// else (null, HTML, bytes, list, invalid JSON) -> null. Never throws.
  static Map? asMap(dynamic body) {
    if (body is Map) return body;
    if (body is String && body.isNotEmpty) {
      try {
        final d = jsonDecode(body);
        if (d is Map) return d;
      } catch (_) {}
    }
    return null;
  }

  /// True when [body] is still an encrypted envelope (decryption did not run
  /// or failed) — such a body must never be interpreted as a real error.
  static bool isEncryptedEnvelope(dynamic body) {
    final m = asMap(body);
    return m != null && m.containsKey('n') && m.containsKey('ct');
  }

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

    // The API host showed a real-looking certificate whose key this build does not pin (D-946): the server moved
    // to a new key, only an update can fix it — say that instead of "could not connect".
    if (CertPin.isUpdateFailure(nested) ||
        (e.type == DioExceptionType.badCertificate && CertPin.updateRequired)) {
      return ApiException(
        statusCode: 0,
        type: ApiErrorType.network,
        message: translate('tls_pin_update_required'),
        code: kPinUpdateCode,
      );
    }

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
    final (code, codedAr) = codedDetail(body);
    final m = asMap(body);
    final d = asMap(m?['detail']);
    final err = asMap(m?['error']);
    // coded messages are already user-ready: Arabic `message` / English `message_en` by the app's language;
    // a 422 with the top-level `error` object says it better than pydantic's list
    final codedMsg = code != null && d != null ? (_pick(d, 'message') ?? codedAr) : null;
    final errMsg = err != null ? _pick(err, 'message') : null;
    final serverMsg = codedMsg ?? errMsg ?? _messageFromBody(body);
    final rid = res?.headers.value('x-request-id');   // coded messages are already user-ready

    // Never leak raw 5xx internals to users; the body is still available.
    // A plain 403 with NO readable server message gets the friendly generic
    // text; if the server sent a readable message, it is shown instead.
    final message = code == 'server_busy'
        ? (AppConfig.lang == 'ar' ? ApiMessages.serverBusyAr : ApiMessages.serverBusyEn)
        : type == ApiErrorType.server
        ? ApiMessages.server
        : (type == ApiErrorType.unauthorized && GuestState.active)
        ? translate('guest_login_required') // guest hit something that needs an account
        : (type == ApiErrorType.forbidden && ViewAsState.active)
        ? translate('admin_view_as_readonly') // every write is refused by the server in view-as: say so clearly
        : (type == ApiErrorType.forbidden && code == null && serverMsg == null)
        ? ApiMessages.forbidden
        : (serverMsg ?? _defaultMessage(type));

    return ApiException(
      statusCode: status,
      type: type,
      message: message,
      body: body,
      code: code,
      requestId: (rid == null || rid.isEmpty) ? null : rid,
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
        if (m != null) return _translateIfKey(m);
      }
      return null;
    }

    if (body is List) return _messageFromValue(body);
    return null;
  }

  /// Only ASCII messages are treated as translation keys
  /// ("User not found" -> "user_not_found"). Anything else (e.g. Arabic) is
  /// already user-ready and returned untouched. If no translation exists for
  /// the key, the original text is shown instead of "some_key_with_underscores".
  static String _translateIfKey(String m) {
    final isAscii = RegExp(r'^[\x00-\x7F]+$').hasMatch(m);
    if (!isAscii) return m;
    final key = m.replaceAll(' ', '_').toLowerCase();
    final t = key.tr;
    return t == key ? m : t;
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

// ── Logging interceptor (only attached when AppConfig.showLogs == true) ──────

class _ApiLogInterceptor extends Interceptor {
  static const _tsKey = '_log_ts';
  static const _maxBodyChars = 4000;

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

  dynamic _redact(dynamic v) => redactForLog(v);
}

/// Keys whose values never reach the debug console (compared lower-case). MFA: `secret` and `otpauth_uri` carry the
/// TOTP seed, `recovery_codes` / `recovery_code` sign in without the phone.
const logSensitiveKeys = {
  'authorization',
  'x-exam-session',
  'x-enc-session',
  'exam_session',
  'password',
  'new_password',
  'old_password',
  'current_password',
  'access_token',
  'refresh_token',
  'token',
  'secret',
  'x-onboarding-token',
  'onboarding_token',
  'mfa_token',
  'mfa_enroll_token',
  'otpauth_uri',
  'recovery_codes',
  'recovery_code',
  'otp',
  // fingerprint / Face ID sign-in (D-082): the enrol proof, the one-time challenge and its signature, the key seed
  'biometric_enroll_token',
  'enroll_token',
  'challenge',
  'signature',
  'seed',
  'private_key',
  // S8: the Google sign-in id token, the SSE stream ticket (POST /me/events/ticket), passcodes and PINs
  'id_token',
  'ticket',
  'passcode',
  'pin',
};

/// Time to open a connection to the API (S14).
const kApiConnectTimeout = Duration(seconds: 20);

/// Time to wait for an answer (and, off the web, to send a JSON body) on an ordinary call (S14).
const kApiReceiveTimeout = Duration(seconds: 30);

/// Uploads (FormData, a byte stream) and binary downloads: a large file on a slow line may take this long.
const kApiTransferTimeout = Duration(minutes: 60);

/// A request that moves a file: FormData or a stream body, a bytes / stream answer, `extra['transfer'] == true`
/// (`post(..., transfer: true)`: a JSON body carrying a base64 file), or a JSON body with a string field over
/// [kApiLargeBodyChars] (the safety net for a base64 post nobody marked; the encrypted envelope's `ct` counts).
bool isTransferRequest(RequestOptions o) =>
    o.data is FormData ||
    o.data is Stream ||
    o.responseType == ResponseType.bytes ||
    o.responseType == ResponseType.stream ||
    o.extra['transfer'] == true ||
    _hasLargeString(o.data);

/// A JSON string this long (about 192 KB of base64-encoded bytes) is a file, not a form.
const kApiLargeBodyChars = 256 * 1024;

bool _hasLargeString(Object? data) {
  if (data is String) return data.length > kApiLargeBodyChars;
  if (data is Map) return data.values.any((v) => v is String && v.length > kApiLargeBodyChars);
  return false;
}

/// Gives a transfer request the long timeouts, unless its caller picked its own receive timeout. The send timeout
/// stays unset on the web (a non-null one forces a CORS preflight, see `_buildDio`).
RequestOptions applyTransferTimeouts(RequestOptions o) {
  if (!isTransferRequest(o)) return o;
  if (o.receiveTimeout == null || o.receiveTimeout == kApiReceiveTimeout) o.receiveTimeout = kApiTransferTimeout;
  if (!kIsWeb) o.sendTimeout = kApiTransferTimeout;
  return o;
}

/// Server error codes (`mfa_code_invalid`, `DEVICE_MISMATCH`) stay readable in a `code` field; any other `code`
/// value (a 6-digit TOTP, a recovery code, a join or coupon code) is masked.
final _errorCodeShape = RegExp(r'^[A-Za-z]+(_[A-Za-z0-9]+)+$');

/// Recursively masks sensitive values so secrets never reach the console. A JSON text body is decoded first (some
/// web / proxy paths deliver bodies as a String); any other value is returned as is.
dynamic redactForLog(dynamic v) {
  if (v is String && v.length > 1 && (v.startsWith('{') || v.startsWith('['))) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map || decoded is List) return redactForLog(decoded);
    } catch (_) {}
    return v;
  }
  if (v is Map) {
    return {
      for (final e in v.entries)
        e.key.toString(): _maskLogValue(e.key.toString().toLowerCase(), e.value),
    };
  }
  if (v is List) return v.map(redactForLog).toList();
  return v;
}

dynamic _maskLogValue(String key, dynamic value) {
  if (logSensitiveKeys.contains(key)) return '***';
  if (key == 'code' && value != null && !(value is String && _errorCodeShape.hasMatch(value))) return '***';
  return redactForLog(value);
}

// ── Pure request rules (unit-tested in test/auth/onboarding_token_rules_test.dart) ──

/// True for the teacher onboarding routes the server guards with `onboarding_user` (back/services/auth_service.py):
/// POST /auth/teacher-profile and /auth/teacher-documents overview / upload-attachment/{email} / create / finalize,
/// plus DELETE /auth/teacher-documents/{id}. Not `teacher-profile-extras`, `required-types` or `{id}/public`.
///
/// Only a RELATIVE path (resolved against the API base) matches: the pattern is anchored, so an absolute URL to
/// another host whose path happens to end the same way never receives the onboarding token.
bool isTeacherOnboardingPath(String path) {
  final q = path.indexOf('?');
  final p = (q < 0 ? path : path.substring(0, q)).replaceFirst(RegExp(r'/+$'), '');
  return _onboardingPath.hasMatch(p);
}

final _onboardingPath = RegExp(
  r'^/?api/v1/auth/(teacher-profile|teacher-documents(/(overview|finalize|upload-attachment/[^/?#]+|\d+))?)$',
);

/// The `X-Onboarding-Token` header an onboarding request still lacks (empty when it is not an onboarding route,
/// there is no token, or the caller already set the header itself — a header the caller set always wins).
Map<String, String> onboardingHeaderFor(String path, String? token, Map<String, dynamic> existing) {
  if (token == null || token.isEmpty || !isTeacherOnboardingPath(path)) return const {};
  final has = existing.keys.any((k) => k.toLowerCase() == 'x-onboarding-token');
  return has ? const {} : {'X-Onboarding-Token': token};
}

/// After the user backs out of the enrollment page, a refused call does not reopen it for this long: the burst of
/// parallel 403s a dashboard fires, or a screen that reloads when it is shown again, would otherwise push the page
/// straight back and trap the user. After the pause the next refused call opens it again, until MFA is on.
const mfaPromptCooldown = Duration(seconds: 30);

/// Whether a failed request should open the MFA enrollment page: a 403 `mfa_enrollment_required` on an
/// authenticated call by a signed-in user (never a guest, never while viewing as someone else), not from the MFA
/// routes themselves (they are exempt server-side; this also keeps the page from re-opening itself), not while the
/// page is already open, and not within [mfaPromptCooldown] of the user leaving it ([sinceDismissed]; null = it was
/// not dismissed in this session).
bool shouldOpenMfaEnrollment({
  required int? status,
  required String? code,
  required String path,
  required bool needsAuth,
  required bool guest,
  required bool viewingAs,
  required bool pageOpen,
  Duration? sinceDismissed,
}) =>
    status == 403 &&
    code == 'mfa_enrollment_required' &&
    needsAuth &&
    !guest &&
    !viewingAs &&
    !pageOpen &&
    (sinceDismissed == null || sinceDismissed >= mfaPromptCooldown) &&
    !path.contains('/api/v1/auth/mfa/');

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

// ── Application-layer envelope encryption (X25519 ECDH -> AES-256-GCM) ──────
// Encrypts JSON request/response bodies on top of TLS. This is meant to keep
// a body unreadable to anything sitting between TLS termination and the app
// itself (a misconfigured proxy, request logging that captures raw bodies) —
// it is NOT a defense against a rooted device running Frida hooked directly
// onto this very code, since the app must have the plaintext to work at all.
//
// UNVERIFIED: written from pubspec.yaml/requirements.txt, not compiled
// against a real Flutter build. The most likely thing to need a small fix
// against your installed `cryptography` version is the Hkdf.deriveKey named
// parameter for the salt (called `nonce` below, matching the package's API
// at the time this was written — check that against `flutter pub deps` if
// it doesn't compile).
//
// Wire format matches helpers/encryption_middleware.py on the server:
//   header: X-Enc-Session: <session_id>
//   body:   {"n": "<base64 nonce>", "ct": "<base64 ciphertext+tag>"}

class _EncSession {
  _EncSession(this.sessionId, this.key);
  final String sessionId;
  final SecretKey key;
}

class _EncryptionInterceptor extends Interceptor {
  /// [bare]: the pinned client WITHOUT interceptors, for the handshake (it bootstraps the session this interceptor
  /// is part of, so it cannot go through itself). [owner]: the Dio this interceptor sits in, for the retry after
  /// `encryption_session_expired`, so the retry runs every interceptor again (fresh bearer, 401 refresh, device
  /// headers, decryption). Both are pinned: nothing here opens an unpinned connection (D-946, S2).
  _EncryptionInterceptor({required Dio Function() bare, required Dio Function() owner})
      : _bare = bare,
        _owner = owner;

  final Dio Function() _bare;
  final Dio Function() _owner;

  /// Set on the one retry after `encryption_session_expired`; a second expiry on it is passed on, not retried.
  static const retriedKey = '_encRetried';

  static final _algo = AesGcm.with256bits();
  static final _kdfAlgo = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  // Must be byte-identical to services/crypto_session_service.py's
  // _HKDF_INFO / _HKDF_SALT. Built with utf8.encode rather than a hardcoded
  // byte list — a hand-typed list here is exactly how this broke the first
  // time (wrong bytes, silent key mismatch, decrypt failures on both ends).
  static final _hkdfInfo = utf8.encode('elfaheem-envelope-v1');
  static final _hkdfSalt = utf8.encode('elfaheem-envelope-salt-v1');

  _EncSession? _session;
  Future<_EncSession>? _handshake;

  // `noEnc`: binary downloads (scan images, PDFs) opt out — the server would otherwise wrap the bytes in a JSON
  // envelope. Auth, TLS and certificate pinning still apply to them.
  bool _skips(RequestOptions o) =>
      o.path.contains('/security/handshake') || o.data is FormData || o.extra['noEnc'] == true;

  Future<_EncSession> _ensureSession() {
    final cached = _session;
    if (cached != null) return Future.value(cached);
    return _handshake ??= _handshakeNow().whenComplete(() => _handshake = null);
  }

  Future<_EncSession> _handshakeNow() async {
    final algo = X25519();
    final clientKeyPair = await algo.newKeyPair();
    final clientPublic = await clientKeyPair.extractPublicKey();

    // The pinned client without interceptors: the handshake bootstraps the very session this interceptor is part
    // of, so it can't go through itself — but it must not skip the pin either (a proxy in the handshake would
    // hold the key of every encrypted body after it).
    final res = await _bare().post(
      '/api/v1/security/handshake',
      data: {'client_public_key': base64Encode(clientPublic.bytes)},
    );
    final serverPublicBytes = base64Decode(res.data['server_public_key'] as String);
    final sessionId = res.data['session_id'] as String;

    final serverPublic = SimplePublicKey(serverPublicBytes, type: KeyPairType.x25519);
    final shared = await algo.sharedSecretKey(
      keyPair: clientKeyPair,
      remotePublicKey: serverPublic,
    );
    final sharedBytes = await shared.extractBytes();
    final derived = await _kdfAlgo.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: _hkdfSalt,   // HKDF salt — must match server's explicit _HKDF_SALT
      info: _hkdfInfo,
    );

    final session = _EncSession(sessionId, derived);
    _session = session;
    return session;
  }

  Future<void> _tryDecrypt(Response? response) async {
    if (response == null) return;
    // Body may be a Map (normal), a JSON String (some web paths) or null
    // (empty body / nginx error page) — only a real envelope is touched.
    final data = ApiException.asMap(response.data);
    final session = _session;
    if (data == null || !data.containsKey('n') || !data.containsKey('ct') || session == null) {
      return;
    }
    try {
      final nonce = base64Decode(data['n'] as String);
      final ctFull = base64Decode(data['ct'] as String);
      const macBytes = 16;
      final mac = Mac(ctFull.sublist(ctFull.length - macBytes));
      final cipherText = ctFull.sublist(0, ctFull.length - macBytes);
      final box = SecretBox(cipherText, nonce: nonce, mac: mac);
      final plain = await _algo.decrypt(box, secretKey: session.key);
      response.data = jsonDecode(utf8.decode(plain));
    } catch (_) {
      // leave as-is; callers treat an undecrypted envelope as "unknown body"
      // (see ApiException.isEncryptedEnvelope) instead of misreading it.
    }
  }

  // The ORIGINAL (plaintext) body is remembered here so a retried request —
  // after a token refresh or an expired encryption session — is encrypted
  // from the plaintext again, never encrypted twice.
  static const _plainKey = '_encPlain';

  Future<void> _encryptInto(RequestOptions options, _EncSession session) async {
    // GET/HEAD have no body: encrypting `null` would turn it into an
    // {"n","ct"} body, which browsers refuse to send on GET (Dio: "GET request
    // with a body data are not support on the web platform"). Send only the
    // session header so the server can still encrypt the RESPONSE.
    final method = options.method.toUpperCase();
    if (method == 'GET' || method == 'HEAD') {
      options.headers['X-Enc-Session'] = session.sessionId;
      return;
    }
    if (!options.extra.containsKey(_plainKey)) {
      options.extra[_plainKey] = options.data;
    }
    final plaintext = utf8.encode(jsonEncode(options.extra[_plainKey]));
    final nonce = _algo.newNonce();
    final box = await _algo.encrypt(plaintext, secretKey: session.key, nonce: nonce);
    options.data = {
      'n': base64Encode(nonce),
      'ct': base64Encode(box.cipherText + box.mac.bytes),
    };
    options.headers['X-Enc-Session'] = session.sessionId;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_skips(options)) return handler.next(options);
    try {
      final session = await _ensureSession();
      await _encryptInto(options, session);
    } catch (_) {
      // Handshake/network failure -> fall through unencrypted rather than
      // hard-fail every request; auth + TLS + pinning still apply regardless.
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    await _tryDecrypt(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    await _tryDecrypt(err.response);   // decrypt the error body too, before the session-expired check
    final data = ApiException.asMap(err.response?.data);
    final o = err.requestOptions;
    if (data != null && data['error'] == 'encryption_session_expired' && o.extra[retriedKey] != true) {
      _session = null;
      try {
        // Back through the owning Dio, so the retry is pinned AND runs every interceptor again: this one encrypts
        // the ORIGINAL body (kept in extra[_plainKey]) with a NEW session, the auth interceptor sets the current
        // bearer and refreshes on a 401, and the response is decrypted on the way back.
        final retry = o.copyWith(
          extra: {...o.extra, retriedKey: true},
          data: o.data is FormData ? (o.data as FormData).clone() : o.data,
        );
        return handler.resolve(await _owner().fetch(retry));
      } on DioException catch (e) {
        // The retry itself failed (e.g. 403 DEVICE_MISMATCH): surface THAT error, which the retry's own chain
        // already decrypted and handled, not the stale "session expired" one.
        return handler.reject(e);
      } catch (_) {}
    }
    handler.next(err);
  }
}

class ApiClient {

  ApiClient._();

  static final ApiClient instance = ApiClient._();

  factory ApiClient() => instance;

  static final String _base = AppConfig.baseUrl;

  // Public so room.dart can read the base URL for the JS compositor.
  String get baseUrl => _base;

  final _storage = TokenStorage();

  late final Dio _dio = _buildDio();

  // Kept for external code that accessed `apiClient.dio` directly.
  Dio get dio => _dio;

  // ── Dio setup ─────────────────────────────────────────────────────────────

  // ── Certificate pinning (mobile only — a browser tab controls its own TLS,
  // nothing here can change that) ─────────────────────────────────────────
  //
  // Pinned by PUBLIC KEY, not by certificate (D-946, lib/core/cert_pin.dart): the server renews with
  // `certbot renew --reuse-key`, the key stays, the pin keeps matching. A renewal that changes the key is still
  // accepted when Let's Encrypt signed it (backup intermediates); anything else fails closed, and the app says
  // "update the app" (tls_pin_update_required) when it was our own host.
  //
  // withTrustedRoots: false -> the OS/system CA list is NOT consulted at all, so a proxy's CA being "trusted" on
  // this device (rooted/test builds, a user CA) does not matter: every connection falls through to CertPin.check,
  // the only thing deciding whether the cert is accepted. EVERY client that talks to the API host is built here:
  // the main one and the bare one of the encryption handshake (S2), and the Server-Sent Events stream
  // (`LiveEventsClient`, through [pinnedHttpClient]).
  static HttpClient pinnedHttpClient() => _pinnedHttpClient();

  static HttpClient _pinnedHttpClient() {
    CertPin.apiHost = Uri.parse(_base).host;
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = CertPin.check;
    return client;
  }

  /// Web has no dart:io HttpClient, so pinning is mobile / desktop only.
  static Dio _pinned(Dio d) {
    if (!kIsWeb) (d.httpClientAdapter as IOHttpClientAdapter).createHttpClient = _pinnedHttpClient;
    return d;
  }

  /// The pinned client WITHOUT interceptors (the encryption handshake). One per ApiClient.
  late final Dio _bareDio = _pinned(Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {HttpHeaders.acceptHeader: 'application/json'},
  )));

  /// Tests: the bare client and whether a Dio carries the pinned HttpClient factory.
  @visibleForTesting
  Dio get debugBareDio => _bareDio;

  @visibleForTesting
  static bool debugIsPinned(Dio d) =>
      d.httpClientAdapter is IOHttpClientAdapter &&
      (d.httpClientAdapter as IOHttpClientAdapter).createHttpClient == _pinnedHttpClient;

  /// Tests: the encryption interceptor over the given clients (the handshake on [bare], the retry on [owner]).
  @visibleForTesting
  static Interceptor debugEncryptionInterceptor({required Dio Function() bare, required Dio Function() owner}) =>
      _EncryptionInterceptor(bare: bare, owner: owner);

  Dio _buildDio() {
    final d = Dio(
      BaseOptions(
        baseUrl: _base,
        // S14: short by default, so a hung server ends in "took too long" instead of an hour-long spinner;
        // uploads and binary downloads get the long transfer timeouts in [applyTransferTimeouts].
        connectTimeout: kApiConnectTimeout,

        // Web: a non-null sendTimeout makes Dio attach an XHR upload-progress
        // listener, which FORCES a CORS preflight on every request — so it is
        // left unset in the browser (XHR has no real send timeout anyway).
        sendTimeout: kIsWeb ? null : kApiReceiveTimeout,
        receiveTimeout: kApiReceiveTimeout,

        // Keep the error body so we can read {"detail": ...}.
        receiveDataWhenStatusError: true,

        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.acceptLanguageHeader: AppConfig.lang,
        },
      ),
    );

    // ORDER MATTERS: Dio runs onResponse/onError in the SAME order the
    // interceptors were added (not reversed). The encryption interceptor must
    // therefore be FIRST, so it decrypts every response/error body before the
    // logger and the auth interceptor read it. (Added last, the auth
    // interceptor saw raw {"n","ct"} envelopes: device_allowed / DEVICE_MISMATCH
    // were never detected, so the "switch device" dialog never opened.)
    // Auth headers (Authorization, X-Device-*) are not part of the encrypted
    // body, so attaching them after encryption is fine.
    d.interceptors.add(_EncryptionInterceptor(bare: () => _bareDio, owner: () => d));

    // Logger next: it sees every request, response and error (including the
    // first 401 that the auth interceptor later recovers from).
    if (AppConfig.testMode) {
      d.interceptors.add(_ApiLogInterceptor());
    }

    d.interceptors.add(_authInterceptor());

    // Uploads / binary downloads, also the ones that call `ApiClient().dio` directly: the long timeouts (S14).
    d.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.next(applyTransferTimeouts(o))));

    // Pinned (see _pinnedHttpClient above).
    // IMPORTANT: this Dio instance must only ever talk to _base's host. If any
    // other code reuses `ApiClient().dio` against a different domain (MinIO,
    // LiveKit REST, …), that request will now fail closed — by design, but
    // worth grepping `apiClient.dio` / `ApiClient().dio` for before shipping.
    return _pinned(d);
  }

  Interceptor _authInterceptor() => InterceptorsWrapper(
    // ── Inject Bearer token ────────────────────────────────────────────────
    onRequest: (options, handler) async {
      // ── GUEST MODE: strictly read-only ─────────────────────────────────
      // Only GETs (and the /auth/* endpoints) leave the device. Any other call is refused HERE,
      // before it reaches the server, and the "log in to continue" sheet opens.
      // The server is still the real guard: a guest has no token, so it answers 401 anyway.
      if (GuestState.active) {
        final readOnly = options.method.toUpperCase() == 'GET' ||
            options.path.contains('/api/v1/auth/');
        if (!readOnly) {
          GuestGuard.promptLogin();
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: ApiException(
                statusCode: 0,
                type: ApiErrorType.forbidden,
                message: translate('guest_login_required'),
                code: 'GUEST_RESTRICTED',
              ),
            ),
            false,
          );
        }
      }

      // A guest never sends a token (and never X-View-As).
      if (options.extra['auth'] != false && !GuestState.active) {
        final token = await _storage.accessToken;
        final viewAs = ViewAsState.targetId;
        if (viewAs != null) options.headers['X-View-As'] = viewAs.toString();

        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }

      // Teacher onboarding: every onboarding route carries the onboarding token (docs/SECURITY_SCAN.md F2), also
      // the ones a caller forgot to pass it to. The server reads it before `Authorization`, so a stale bearer left
      // from an earlier session can't turn the call into a 401.
      options.headers.addAll(onboardingHeaderFor(options.path, TeacherOnboardingToken.value, options.headers));

      // Device identity on EVERY request (server binds / checks it).
      // If it cannot be produced we send nothing: the server answers
      // DEVICE_ID_MISSING and the blocked-device dialog explains it, rather
      // than the app inventing an ID that would never match.
      try {
        options.headers.addAll(await DeviceIdService.instance.headers());
      } catch (e) {
        if (AppConfig.testMode) log('device headers unavailable: $e', name: 'API');
      }

      handler.next(options);
    },

    // ── Login from a device that isn't the registered one -> dialog ───────
    onResponse: (response, handler) {
      // Body can be a Map, a JSON String or null — asMap() covers all three.
      final d = ApiException.asMap(response.data);
      if (response.requestOptions.path.endsWith('/auth/login') &&
          d != null &&
          d['device_allowed'] == false) {
        _showDeviceBlocked(delay: const Duration(milliseconds: 900));
      }
      // A decision (approve / reject / …) went through: the badges that counted it reload (decision_refresh.dart).
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        DecisionRefresh.onSuccess(response.requestOptions.method, response.requestOptions.path);
      }
      handler.next(response);
    },

    // ── 401 → refresh once → retry; 403 → device dialog or friendly message ─
    onError: (error, handler) async {
      // Guest: no refresh, no "session expired → login" redirect, no device dialog, no paywall.
      // The screen shows the (friendly) error; writes were already refused in onRequest.
      if (GuestState.active) return handler.next(error);

      final req = error.requestOptions;
      final status = error.response?.statusCode;
      final needsAuth = req.extra['auth'] != false;

      if (status == 403 && needsAuth) {
        final raw = error.response?.data;
        final (code, _) = ApiException.codedDetail(raw);
        if (shouldOpenMfaEnrollment(
          status: status,
          code: code,
          path: req.path,
          needsAuth: needsAuth,
          guest: GuestState.active,
          viewingAs: ViewAsState.targetId != null,
          pageOpen: _mfaPageOpen,
          sinceDismissed: _mfaDismissedAt == null ? null : DateTime.now().difference(_mfaDismissedAt!),
        )) {
          _openMfaEnrollment();
        }
        if (code == 'DEVICE_MISMATCH' || code == 'DEVICE_ID_MISSING') {
          if (error.requestOptions.path.endsWith('/sessions')) {
            final courseId = error.requestOptions.path
                .split('/sessions')
                .first
                .split('/')
                .last;
            _showDeviceBlocked(courseId: int.parse(courseId));
          }
        }
        // Any other 403 (VIEW_LIMIT_REACHED, SWITCH_LIMIT, plain forbidden,
        // ...): NO navigation. The error is passed to the caller, which shows
        // ApiException.message (the server's message if readable, otherwise a
        // friendly generic text).
        return handler.next(error);
      }

      // 402 SUBSCRIPTION_REQUIRED → the admin turned subscriptions on and this
      // student has no active plan: send them to the paywall (once).
      if (status == 402 && needsAuth) {
        final (code, _) = ApiException.codedDetail(error.response?.data);
        if (code == 'SUBSCRIPTION_REQUIRED') _showPaywall();
        // D-1120: a teacher / parent account that owes the account fee → the pay page (never while viewing as)
        if (code == 'account_fee_required' && ViewAsState.targetId == null) _showAccountFee();
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
  /// `headers`: extra request headers a feature needs (the Exam Engine's `X-Exam-Session`); auth / device headers
  /// are still added by the interceptors and win on conflict.
  /// `transfer`: a JSON body that carries a file as base64 (an image, a PDF, a background): it takes the long
  /// transfer timeouts like an upload, since a few MB on a phone line can outlast the 30 s send timeout.
  Options _jsonOpts({
    bool auth = true,
    required String method,
    Map<String, String>? headers,
    bool transfer = false,
  }) =>
      Options(
        method: method,
        contentType: Headers.jsonContentType,
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
        extra: {'auth': auth, if (transfer) 'transfer': true},
      );

  /// GET calls: no Content-Type (avoids needless preflight on public GETs).
  /// Authenticated GETs may still preflight because of `Authorization`.
  Options _getOpts({bool auth = true, Map<String, String>? headers}) => Options(
    method: 'GET',
    receiveTimeout: const Duration(seconds: 30),
    headers: headers,
    extra: {'auth': auth},
  );

  /// File uploads/downloads: the long transfer timeouts ([applyTransferTimeouts]).
  Options _fileOpts({bool auth = true, String method = 'POST', Map<String, String>? headers}) => Options(
    method: method,
    headers: headers,
    extra: {'auth': auth, 'transfer': true},
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
      // Body only (the query parameter leaked into access logs). The reply carries a NEW refresh token;
      // the old one is dead, and reusing it signs the whole session out (401 refresh_reuse).
      final res = await _dio.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refresh},
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

      // Server said the refresh token is no good → real logout (a 429 is the throttle, not a verdict).
      if (refreshStatusRejects(s)) return _RefreshResult.rejected;

      // Offline / timeout / 5xx → don't log the user out.
      return _RefreshResult.failed;
    } catch (_) {
      return _RefreshResult.failed;
    }
  }

  // ── Navigation side-effects (guarded against duplicate pushes) ────────────

  bool _redirecting = false;

  Future<void> _redirectToLogin() async {
    if (GuestState.active) return; // a guest has no session to lose
    if (GuestLinkVisit.active) return; // a guest link's page is open: never throw the visitor out of it (D-840)
    if (_redirecting) return;
    _redirecting = true;

    try {
      ViewAsState.instance.stop(); // session is dead → leave view-as too
      await _storage.clear();
      _mfaDismissedAt = null;
      TeacherOnboardingToken.clear();

      if (AppConfig.testMode) log('redirect to login', name: 'API');

      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
            (_) => false,
      );
    } finally {
      Future.delayed(const Duration(seconds: 2), () => _redirecting = false);
    }
  }

  /// The MFA enrollment page this client opened is on screen (a second refused call never stacks another one).
  bool _mfaPageOpen = false;

  /// When the user last backed out of that page; cleared by a new session ([saveTokens]) and by signing out. A
  /// refused call opens the page again once [mfaPromptCooldown] has passed, so the requirement is never lost
  /// until the account has MFA (the profile / settings entry opens it any time).
  DateTime? _mfaDismissedAt;

  /// 403 `mfa_enrollment_required`: the session predates `MFA_REQUIRED_ROLES` for this role. Opens the enrollment
  /// page (A07's [AdminMfaPage], which works with the normal session: `/auth/mfa/*` stays open server-side).
  void _openMfaEnrollment() {
    final nav = navigatorKey.currentState;
    if (_mfaPageOpen || nav == null) return;
    _mfaPageOpen = true;
    nav.push(MaterialPageRoute<void>(builder: (_) => const AdminMfaPage())).whenComplete(() {
      _mfaPageOpen = false;
      _mfaDismissedAt = DateTime.now();
    });
  }

  bool _deviceDialogOpen = false;

  /// Shows the "this device isn't allowed / switch device" dialog once
  /// (guarded against the burst of parallel 403s a dashboard produces).
  ///
  /// Called only on a definitive server signal (403 DEVICE_MISMATCH /
  /// DEVICE_ID_MISSING, or login with device_allowed == false), so it does
  /// not second-guess the server. DeviceSecurityProvider.check() is only used
  /// to fill the dialog (pending request, monthly limit, can-request); if it
  /// fails the dialog still opens with the plain message.
  bool _paywallOpen = false;

  bool _accountFeeOpen = false;

  /// The account-fee page in place of everything (no way back into the app until it is paid; it signs out).
  void _showAccountFee() {
    if (_accountFeeOpen || AccountFeePage.isOpen) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _accountFeeOpen = true;
    nav
        .pushAndRemoveUntil(
            MaterialPageRoute<void>(
                builder: (_) => const AccountFeePage(), settings: const RouteSettings(name: AccountFeePage.route)),
            (_) => false)
        .whenComplete(() => _accountFeeOpen = false);
  }

  void _showPaywall() {
    if (_paywallOpen) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _paywallOpen = true;
    nav
        .pushNamedAndRemoveUntil('/subscription', (route) => false)
        .whenComplete(() => _paywallOpen = false);
  }

  void _showDeviceBlocked({Duration delay = Duration.zero,int? courseId}) {
    if (_deviceDialogOpen) return;
    _deviceDialogOpen = true;
    () async {
      try {
        if (delay > Duration.zero) await Future.delayed(delay);

        // Web cold start / mid-navigation: the navigator may not have a
        // mounted context yet — wait up to ~3s instead of silently giving up.
        var ctx = navigatorKey.currentContext;
        for (var i = 0; (ctx == null || !ctx.mounted) && i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 300));
          ctx = navigatorKey.currentContext;
        }
        if (ctx == null || !ctx.mounted) return;

        final p = DeviceSecurityProvider();
        try {
          await p.check();
        } catch (_) {}
        if (!ctx.mounted) return;
        await showDeviceBlockedDialog(ctx, p,courseId: courseId);
      } catch (e) {
        if (AppConfig.testMode) log('device dialog failed: $e', name: 'API');
      } finally {
        _deviceDialogOpen = false;
      }
    }();
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
        Map<String, String>? headers,
      }) =>
      _execute(
            () => _dio.get(
          path,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _getOpts(auth: auth, headers: headers),
        ),
      );

  // ── POST ──────────────────────────────────────────────────────────────────

  Future<dynamic> post(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
        Map<String, String>? headers,
        ProgressCallback? onSendProgress,
        bool transfer = false,
      }) =>
      _execute(
            () => _dio.post(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          options: _jsonOpts(auth: auth, method: 'POST', headers: headers, transfer: transfer),
        ),
      );

  // ── PUT ───────────────────────────────────────────────────────────────────

  Future<dynamic> put(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
        Map<String, String>? headers,
        bool transfer = false,
      }) =>
      _execute(
            () => _dio.put(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'PUT', headers: headers, transfer: transfer),
        ),
      );

  // ── Binary downloads and multi-file uploads (Exam Engine scans, answer sheets) ──

  /// GET raw bytes (an image, a PDF). Outside the envelope encryption (see `noEnc` in the interceptor).
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? queryParams, Map<String, String>? headers}) async {
    final res = await _execute(() => _dio.get(path, queryParameters: queryParams,
        options: Options(method: 'GET', responseType: ResponseType.bytes, headers: headers,
            extra: {'auth': true, 'noEnc': true})));
    return _asBytes(res);
  }

  /// POST a JSON body and receive raw bytes (e.g. a generated PDF). The body is small and not sensitive (ids).
  /// [onHeaders] hears the answer's headers (e.g. `X-Design-Adjustments` on printed sheets).
  Future<Uint8List> postForBytes(String path, {dynamic body, Map<String, String>? headers, void Function(Map<String, List<String>> headers)? onHeaders}) async {
    final res = await _execute(() async {
      final r = await _dio.post(path, data: body,
          options: Options(method: 'POST', contentType: Headers.jsonContentType, responseType: ResponseType.bytes,
              headers: headers, extra: {'auth': true, 'noEnc': true}));
      if (onHeaders != null) {
        try {
          onHeaders(r.headers.map);
        } catch (_) {
          // a listener never breaks the download
        }
      }
      return r;
    });
    return _asBytes(res);
  }

  /// multipart/form-data POST with several files under one field (`files`), plus plain fields.
  Future<dynamic> postFiles(String path, {required List<(String, Uint8List)> files, String field = 'files',
      Map<String, dynamic> fields = const {}, Map<String, String>? headers}) {
    final form = FormData();
    for (final e in fields.entries) {
      if (e.value != null) form.fields.add(MapEntry(e.key, '${e.value}'));
    }
    for (final (name, bytes) in files) {
      final lower = name.toLowerCase();
      final mime = lower.endsWith('.pdf') ? 'application/pdf' : lower.endsWith('.png') ? 'image/png'
          : lower.endsWith('.webp') ? 'image/webp' : lower.endsWith('.csv') ? 'text/csv'
          : lower.endsWith('.xlsx') ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'image/jpeg';
      form.files.add(MapEntry(field, MultipartFile.fromBytes(bytes, filename: name, contentType: MediaType.parse(mime))));
    }
    return _execute(() => _dio.post(path, data: form, options: _fileOpts(headers: headers)));
  }

  static Uint8List _asBytes(dynamic res) =>
      res is Uint8List ? res : (res is List ? Uint8List.fromList(List<int>.from(res)) : Uint8List(0));

  // ── DELETE ────────────────────────────────────────────────────────────────

  /// multipart/form-data POST where the file is OPTIONAL (e.g. the subscription
  /// form: a free plan has no receipt image, a paid plan does).
  Future<dynamic> postForm(
      String path, {
        required Map<String, dynamic> fields,
        String? fileField,
        String? fileName,
        Uint8List? fileBytes,
        bool auth = true,
        Map<String, String>? headers,
      }) {
    String mime = 'image/jpeg';
    final lower = (fileName ?? '').toLowerCase();
    if (lower.endsWith('.png')) mime = 'image/png';
    if (lower.endsWith('.webp')) mime = 'image/webp';
    if (lower.endsWith('.gif')) mime = 'image/gif';
    final form = FormData.fromMap({
      for (final e in fields.entries)
        if (e.value != null) e.key: e.value,
      if (fileField != null && fileBytes != null)
        fileField: MultipartFile.fromBytes(
          fileBytes,
          filename: (fileName == null || fileName.isEmpty) ? 'receipt.jpg' : fileName,
          contentType: MediaType.parse(mime),
        ),
    });
    return _execute(
          () => _dio.post(path, data: form, options: _fileOpts(auth: auth, headers: headers)),
    );
  }

  /// PATCH (used by the About / Terms / app-version admin endpoints).
  Future<dynamic> patch(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
        Map<String, String>? headers,
        bool transfer = false,
      }) =>
      _execute(
            () => _dio.patch(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'PATCH', headers: headers, transfer: transfer),
        ),
      );

  Future<dynamic> delete(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
        Map<String, String>? headers,
      }) =>
      _execute(
            () => _dio.delete(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'DELETE', headers: headers),
        ),
      );

  // ── Upload image ──────────────────────────────────────────────────────────

  Future<dynamic> uploadImage(
      String path, {
        required XFile file,
        String fieldName = 'file',
        void Function(int sent, int total)? onSendProgress,
        CancelToken? cancelToken,
        Map<String, String>? headers,
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
        options: _fileOpts(headers: headers),
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
        Map<String, String>? headers,
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
            options: _fileOpts(auth: auth, headers: headers),
            onSendProgress: onSendProgress,
            cancelToken: cancelToken,
          ),
        );
      } on ApiException catch (e) {
        if (!e.isRetryable || attempt > maxRetries) rethrow;

        final wait = retryDelay * attempt;

        if (AppConfig.testMode) {
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
  }) {
    _mfaDismissedAt = null; // a new session (login, MFA confirm): a later refusal may open the page right away
    // A new session never inherits an earlier account's onboarding token; the login answer that carries this
    // session's token is read right after (MyAuthProvider.completeSession). Token refreshes don't come here.
    TeacherOnboardingToken.clear();
    return _storage.save(access: access, refresh: refresh);
  }

  Future<void> clearTokens() {
    _mfaDismissedAt = null;
    TeacherOnboardingToken.clear();
    return _storage.clear();
  }

  Future<String?> get accessToken => _storage.accessToken;

  Future<String?> get refreshToken => _storage.refreshToken;

  /// `POST /auth/logout` with this device's refresh token, so the server revokes the session family (S15).
  /// Offline / timeout / any error: logged and swallowed — signing out locally never waits on the server.
  Future<void> signOutServer() async {
    try {
      final refresh = await _storage.refreshToken;
      await post(
        '/api/v1/auth/logout',
        body: refresh == null ? const <String, dynamic>{} : {'refresh_token': refresh},
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      log('logout: server call failed: $e', name: 'API');
    }
  }

  /// Synchronous session flag (see TokenStorage.hasSession); `primeSession()` loads it at start-up.
  bool get hasSession => _storage.hasSession;

  Future<void> primeSession() => _storage.prime();

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
    'vtt' => 'text/vtt',
    'mp4' => 'video/mp4',
    'm4a' => 'audio/mp4',
    'webm' => 'video/webm',
    'ogg' => 'audio/ogg',
    _ => 'application/octet-stream',
  };
}

/// Whether a failed `POST /auth/refresh` with this HTTP status means the refresh token is dead (sign the
/// person out) rather than a passing failure (keep the session, try again later): any 4xx except 429, the
/// server's rate limit (S16 — one busy NAT must not sign everyone out).
bool refreshStatusRejects(int? status) =>
    status != null && status >= 400 && status < 500 && status != 429;

enum _RefreshResult { ok, rejected, failed }