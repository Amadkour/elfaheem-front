// lib/features/admin/app_releases/app_releases_api.dart
//
// The super admin's App versions API (D-143, docs/release/APP_RELEASES.md "API"). Core, super admins only:
//
//   GET    /api/v1/admin/app-releases?platform=&status=&page=&page_size= newest first, {items, total, live, next_build_number}
//   GET    /api/v1/admin/app-releases/{id}                              + last 500 log lines, artifacts, commit
//   POST   /api/v1/admin/app-releases                                   {platform, version, …, password} → 201
//          (422 *_invalid / store_url_required · 400 branch_invalid · 403 reauth_failed · 409 version_exists /
//          build_running / version_not_greater / build_number_not_greater · 503 releases_not_configured)
//   POST   /api/v1/admin/app-releases/{id}/cancel | retry
//   POST   /api/v1/admin/app-releases/{id}/publish | rollback          {password}
//   GET    /api/v1/admin/app-releases/{id}/log?after=<seq>                {lines [{seq, line}], log_count, status, progress}
//   GET    /api/v1/admin/app-releases/{id}/artifacts/{name}             the file (e.g. the AAB for the Play Console)
//   GET    /api/v1/admin/app-releases/builder/status                    {online, last_seen, version, busy_job, token_set,
//                                                                         token_rotated_at, configured}
//   POST   /api/v1/admin/app-releases/builder/token {password}          {token} — shown once
//
// D-144 (docs/release/APP_RELEASES_CODEMAGIC.md): Codemagic builds every version.
//   GET    /api/v1/admin/app-releases/config                            {codemagic {ready, missing}, channels {"android:store":
//                                                                         {ready, missing}}, defaults {android: {workflow, …}}}
//   POST   /api/v1/admin/app-releases gains channel (store | website) + config {workflow, track, package_name, store_url,
//          branch}; 400 channel_not_configured {missing} when the chosen channel is not set up.
//
// As built: ../back docs/app_releases.md. Errors are `{"detail": {code, message (ar), message_en, …extra}}`
// ([ReleaseFailure.from]; a bare `{"detail": "<code>"}` is read too).
library;

import 'dart:typed_data';

import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import 'app_releases_models.dart';
import 'app_releases_text.dart';

class ReleaseFailure implements Exception {
  const ReleaseFailure({required this.status, this.code, required this.serverMessage, this.extra = const {}});

  factory ReleaseFailure.from(Object error) {
    if (error is ReleaseFailure) return error;
    final e = ApiException.from(error);
    final body = ApiException.asMap(e.body);
    String? code = e.code;
    String? msg;
    var extra = const <String, dynamic>{};
    final d = body?['detail'];
    if (d is Map) {
      code ??= d['code']?.toString();
      final ar = d['message']?.toString(), en = d['message_en']?.toString();
      msg = AppConfig.lang == 'ar' ? (ar ?? en) : (en ?? ar);
      extra = {for (final e in d.entries) if (!const {'code', 'message', 'message_en'}.contains(e.key)) '${e.key}': e.value};
    } else if (d is String && RegExp(r'^[a-z_]+$').hasMatch(d)) {
      code ??= d;
    } else if (body?['code'] != null) {
      code ??= body!['code'].toString();
    }
    return ReleaseFailure(status: e.statusCode, code: code, serverMessage: msg ?? e.message, extra: extra);
  }

  final int status;
  final String? code;
  final String serverMessage;

  /// The other fields of the error (`live` of version_not_greater, `next_build_number` of build_number_not_greater).
  final Map<String, dynamic> extra;

  /// The releases folder is missing on the server (503).
  bool get notConfigured => code == 'releases_not_configured';

  /// Bilingual text for the known codes, the server's own words otherwise.
  String get message => releaseErrorText(code, serverMessage, extra: extra);

  @override
  String toString() => 'ReleaseFailure($status $code: $serverMessage)';
}

class AppReleasesApi {
  const AppReleasesApi();

  static const base = '/api/v1/admin/app-releases';

  ApiClient get _api => ApiClient.instance;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ReleaseFailure.from(e);
    }
  }

  Future<ReleasePage> list({String? platform, String? status, int page = 1, int size = 100}) => _call(() async =>
      ReleasePage.fromJson(await _api.get(base, queryParams: {'platform': ?platform, 'status': ?status, 'page': page, 'page_size': size})));

  Future<AppRelease> get(int id) => _call(() async => AppRelease.fromJson(_m(await _api.get('$base/$id'))));

  Future<AppRelease> create(AppReleaseDraft d, {required String password}) =>
      _call(() async => AppRelease.fromJson(_m(await _api.post(base, body: d.toJson(password: password)))));

  Future<AppRelease?> cancel(int id) => _call(() async => _maybe(await _api.post('$base/$id/cancel')));

  Future<AppRelease?> retry(int id) => _call(() async => _maybe(await _api.post('$base/$id/retry')));

  Future<AppRelease?> publish(int id, {required String password}) =>
      _call(() async => _maybe(await _api.post('$base/$id/publish', body: {'password': password})));

  Future<AppRelease?> rollback(int id, {required String password}) =>
      _call(() async => _maybe(await _api.post('$base/$id/rollback', body: {'password': password})));

  Future<List<ReleaseLogLine>> log(int id, {int after = 0}) =>
      _call(() async => ReleaseLogLine.listFrom(await _api.get('$base/$id/log', queryParams: {'after': after}), after: after));

  Future<Uint8List> artifact(int id, String name) =>
      _call(() => _api.getBytes('$base/$id/artifacts/${Uri.encodeComponent(name)}'));

  /// D-144: the Codemagic setup, per-channel readiness and the form's defaults (never a secret: `set` flags only).
  Future<ReleaseConfig> config() => _call(() async => ReleaseConfig.fromJson(await _api.get('$base/config')));

  Future<BuilderStatus> builderStatus() => _call(() async => BuilderStatus.fromJson(await _api.get('$base/builder/status')));

  /// A new build-server token; the old one stops working at once. The server keeps only its hash, so this is the
  /// only time it can be read.
  Future<String> rotateBuilderToken({required String password}) => _call(() async {
        final r = _m(await _api.post('$base/builder/token', body: {'password': password}));
        final t = r['token']?.toString() ?? '';
        if (t.isEmpty) throw const ReleaseFailure(status: 0, code: 'no_token', serverMessage: 'No token in the answer');
        return t;
      });

  static Map<String, dynamic> _m(Object? r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  static AppRelease? _maybe(Object? r) => r is Map && r['id'] != null ? AppRelease.fromJson(Map<String, dynamic>.from(r)) : null;
}
