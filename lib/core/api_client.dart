library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Hmac;   // add crypto: ^3.0.0 to pubspec.yaml if missing
import 'package:cryptography/cryptography.dart';   // add cryptography: ^2.7.0 to pubspec.yaml
import 'package:dio/dio.dart';
import 'package:dio/io.dart';           // IOHttpClientAdapter — mobile only
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/token_storage.dart';
import 'package:flutter_education_app/main.dart';
import '../features/shared/guest/guest_state.dart';
import '../features/student/courses/security/device_blocked_dialog.dart';
import '../features/student/courses/security/device_id_service.dart';
import '../features/student/courses/security/device_security_provider.dart';
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

  /// Machine code for our own coded errors: DEVICE_MISMATCH, DEVICE_ID_MISSING,
  /// VIEW_LIMIT_REACHED, SWITCH_LIMIT, ... (null for everything else).
  final String? code;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.type = ApiErrorType.unknown,
    this.body,
    this.code,
  });

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
    final (code, codedMsg) = codedDetail(body);
    final serverMsg = codedMsg ?? _messageFromBody(body);   // coded messages are already user-ready

    // Never leak raw 5xx internals to users; the body is still available.
    // A plain 403 with NO readable server message gets the friendly generic
    // text; if the server sent a readable message, it is shown instead.
    final message = type == ApiErrorType.server
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
  static const _sensitiveKeys = {
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

  bool _skips(RequestOptions o) =>
      o.path.contains('/security/handshake') || o.data is FormData;

  Future<_EncSession> _ensureSession() {
    final cached = _session;
    if (cached != null) return Future.value(cached);
    return _handshake ??= _handshakeNow().whenComplete(() => _handshake = null);
  }

  Future<_EncSession> _handshakeNow() async {
    final algo = X25519();
    final clientKeyPair = await algo.newKeyPair();
    final clientPublic = await clientKeyPair.extractPublicKey();

    // A bare Dio instance, deliberately NOT the pinned/encrypted one above —
    // the handshake bootstraps the very session this interceptor is part of,
    // so it can't depend on itself. TLS + AppConfig.baseUrl still apply.

    final res = await Dio(BaseOptions(baseUrl: AppConfig.baseUrl)).post(
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
    if (data != null && data['error'] == 'encryption_session_expired') {
      _session = null;
      try {
        final session = await _ensureSession();
        final o = err.requestOptions;
        if (!_skips(o)) await _encryptInto(o, session);   // re-encrypt the ORIGINAL body with the NEW key
        final clone = await Dio(BaseOptions(baseUrl: AppConfig.baseUrl)).fetch(o);
        await _tryDecrypt(clone);                          // the retried response is encrypted too
        return handler.resolve(clone);
      } on DioException catch (e) {
        // The retry itself failed (e.g. 403 DEVICE_MISMATCH): surface THAT
        // error (decrypted), not the stale "session expired" one.
        await _tryDecrypt(e.response);
        return handler.next(e);
      } catch (_) {}
    }
    handler.next(err);
  }
}

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

  // ── Certificate pinning (mobile only — a browser tab controls its own TLS,
  // nothing here can change that) ─────────────────────────────────────────
  //
  // Get the current pin:
  //   openssl s_client -connect nextbrain.site:443 -servername nextbrain.site \
  //     </dev/null 2>/dev/null | openssl x509 -outform der | sha256sum
  //
  // Whenever certbot renews the cert (~every 60–90 days) the hash changes.
  // Add the NEW pin below a few days before the old cert expires, keep BOTH
  // during the overlap, then delete the old one — otherwise the app goes
  // dark for every user the moment it renews.
  static const _pinnedCertSha256 = <String>[
    '93d682e09f1a3f195d50f3ed70e80c4c45206e527f332d7bd36ea03045141402',
    // 'REPLACE_WITH_NEXT_PIN_BEFORE_RENEWAL',
  ];

  static bool _certMatchesPin(X509Certificate cert, String host, int port) {
    final hash = sha256.convert(cert.der).toString();
    return _pinnedCertSha256.contains(hash);
  }

  Dio _buildDio() {
    final d = Dio(
      BaseOptions(
        baseUrl: _base,
        connectTimeout: const Duration(minutes: 60),

        // Unlimited upload/download timeouts.
        // Web: a non-null sendTimeout makes Dio attach an XHR upload-progress
        // listener, which FORCES a CORS preflight on every request — so it is
        // left unset in the browser (XHR has no real send timeout anyway).
        sendTimeout: kIsWeb ? null : const Duration(minutes: 60),
        receiveTimeout: const Duration(minutes: 60),

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
    d.interceptors.add(_EncryptionInterceptor());

    // Logger next: it sees every request, response and error (including the
    // first 401 that the auth interceptor later recovers from).
    if (AppConfig.testMode) {
      d.interceptors.add(_ApiLogInterceptor());
    }

    d.interceptors.add(_authInterceptor());

    // withTrustedRoots: false -> the OS/system CA list is NOT consulted at all,
    // so a proxy's CA being "trusted" on this device (rooted/test builds) no
    // longer matters. Every connection now falls through to our own check,
    // which is the only thing deciding whether the cert is accepted.
    // Web has no dart:io HttpClient, so this whole block is mobile-only.
    // IMPORTANT: this Dio instance must only ever talk to _base's host. If any
    // other code reuses `ApiClient().dio` against a different domain (MinIO,
    // LiveKit REST, …), that request will now fail closed — by design, but
    // worth grepping `apiClient.dio` / `ApiClient().dio` for before shipping.
    if (!kIsWeb) {
      (d.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
        client.badCertificateCallback = _certMatchesPin;
        return client;
      };
    }

    return d;
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
  Options _jsonOpts({
    bool auth = true,
    required String method,
    Map<String, String>? headers,
  }) =>
      Options(
        method: method,
        contentType: Headers.jsonContentType,
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
        extra: {'auth': auth},
      );

  /// GET calls: no Content-Type (avoids needless preflight on public GETs).
  /// Authenticated GETs may still preflight because of `Authorization`.
  Options _getOpts({bool auth = true, Map<String, String>? headers}) => Options(
    method: 'GET',
    receiveTimeout: const Duration(seconds: 30),
    headers: headers,
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

  Future<void> _redirectToLogin() async {
    if (GuestState.active) return; // a guest has no session to lose
    if (_redirecting) return;
    _redirecting = true;

    try {
      ViewAsState.instance.stop(); // session is dead → leave view-as too
      await _storage.clear();

      if (AppConfig.testMode) log('redirect to login', name: 'API');

      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
            (_) => false,
      );
    } finally {
      Future.delayed(const Duration(seconds: 2), () => _redirecting = false);
    }
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
      }) =>
      _execute(
            () => _dio.post(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'POST', headers: headers),
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
      }) =>
      _execute(
            () => _dio.put(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'PUT', headers: headers),
        ),
      );

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
          () => _dio.post(path, data: form, options: _fileOpts(auth: auth)),
    );
  }

  /// PATCH (used by the About / Terms / app-version admin endpoints).
  Future<dynamic> patch(
      String path, {
        dynamic body,
        Map<String, dynamic>? queryParams,
        bool auth = true,
        CancelToken? cancelToken,
      }) =>
      _execute(
            () => _dio.patch(
          path,
          data: body,
          queryParameters: queryParams,
          cancelToken: cancelToken,
          options: _jsonOpts(auth: auth, method: 'PATCH'),
        ),
      );

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
  }) =>
      _storage.save(access: access, refresh: refresh);

  Future<void> clearTokens() => _storage.clear();

  Future<String?> get accessToken => _storage.accessToken;

  Future<String?> get refreshToken => _storage.refreshToken;

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

enum _RefreshResult { ok, rejected, failed }