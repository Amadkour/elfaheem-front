// A fake HTTP backend for widget tests: plugged into `ApiClient.instance.dio` as its HttpClientAdapter, it answers
// every request from a route table (fixture payloads), records each call and how long it was in flight, so a test
// can count requests, spot duplicates and measure the waterfall (how many calls had to wait for an earlier answer).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// One answered request.
class FakeCall {
  FakeCall(this.method, this.path, this.query, this.depth, [this.origin = '']);
  final String method;
  final String path;
  final Map<String, dynamic> query;

  /// 1 = started before any answer arrived; n = started after an answer of depth n-1 (a waterfall step).
  final int depth;

  /// The app frames (lib/) of the stack that issued the call, innermost first — who asked.
  final String origin;
  bool done = false;

  String get key => query.isEmpty ? '$method $path' : '$method $path?${(query.keys.toList()..sort()).map((k) => '$k=${query[k]}').join('&')}';

  @override
  String toString() => '$key (d$depth)';
}

/// A route's answer: a body (Map / List / String) with a status, built from the request.
typedef FakeHandler = Object? Function(RequestOptions o);

class FakeApi implements HttpClientAdapter {
  FakeApi(this.routes, {this.latency = const Duration(milliseconds: 100), this.fallback});

  /// `'GET /api/v1/me/home'` → handler. The longest matching prefix of the path (query excluded) wins; a key ending
  /// in `*` matches by prefix, any other key matches exactly.
  final Map<String, FakeHandler> routes;

  /// The answer to a request no route matches (default: 404 with FastAPI's body, so it reads as "not routed").
  final FakeHandler? fallback;
  final Duration latency;

  final calls = <FakeCall>[];
  final unmatched = <String>[];

  /// The adapter the client had before [install] (restored by [uninstall]).
  HttpClientAdapter? _previous;
  final _removed = <Interceptor>[];
  late final _tracer = InterceptorsWrapper(onRequest: (o, h) {
    o.extra['_fakeOrigin'] = StackTrace.current;
    h.next(o);
  });

  /// Plugs this backend into the app's one Dio. The envelope encryption interceptor is taken out for the test (its
  /// handshake uses its own Dio, outside this fake); auth, logging and the rest stay.
  void install() {
    final dio = ApiClient.instance.dio;
    _previous = dio.httpClientAdapter;
    dio.httpClientAdapter = this;
    final enc = dio.interceptors.where((i) => i.runtimeType.toString() == '_EncryptionInterceptor').toList();
    for (final i in enc) {
      dio.interceptors.remove(i);
    }
    _removed
      ..clear()
      ..addAll(enc);
    dio.interceptors.insert(0, _tracer);
  }

  void uninstall() {
    final dio = ApiClient.instance.dio;
    if (_previous != null) dio.httpClientAdapter = _previous!;
    dio.interceptors.remove(_tracer);
    for (final i in _removed.reversed) {
      dio.interceptors.insert(0, i);
    }
    _removed.clear();
  }

  void reset() {
    calls.clear();
    unmatched.clear();
  }

  int get count => calls.length;

  /// Calls whose method + path + query was already requested in this window.
  List<String> get duplicates {
    final seen = <String, int>{};
    for (final c in calls) {
      seen[c.key] = (seen[c.key] ?? 0) + 1;
    }
    return [for (final e in seen.entries) if (e.value > 1) '${e.key} ×${e.value}'];
  }

  /// The longest chain of requests that each started only after an earlier answer arrived.
  int get waterfallDepth => calls.isEmpty ? 0 : calls.map((c) => c.depth).reduce(math.max);

  bool get idle => calls.every((c) => c.done);

  FakeHandler? _match(String method, String path) {
    FakeHandler? best;
    var bestLen = -1;
    for (final e in routes.entries) {
      final sp = e.key.indexOf(' ');
      if (e.key.substring(0, sp) != method) continue;
      final p = e.key.substring(sp + 1);
      final ok = p.endsWith('*') ? path.startsWith(p.substring(0, p.length - 1)) : path == p;
      if (ok && p.length > bestLen) {
        best = e.value;
        bestLen = p.length;
      }
    }
    return best;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final method = o.method.toUpperCase();
    // the paths the app passes to ApiClient start after the base URL's own path (/api)
    final base = Uri.parse(o.baseUrl).path;
    final full = o.uri.path;
    final path = base.length > 1 && full.startsWith('$base/api/') ? full.substring(base.length) : full;
    final origin = (o.extra['_fakeOrigin']?.toString() ?? '')
        .split('\n')
        .where((l) => l.contains('package:flutter_education_app/') && !l.contains('core/api_client.dart'))
        .take(3)
        .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').replaceAll('package:flutter_education_app/', ''))
        .join(' < ');
    final finished = calls.where((c) => c.done).map((c) => c.depth);
    final call = FakeCall(method, path, Map.of(o.uri.queryParameters), 1 + (finished.isEmpty ? 0 : finished.reduce(math.max)), origin);
    calls.add(call);
    await Future<void>.delayed(latency);
    final h = _match(method, path);
    if (h == null) unmatched.add(call.key);
    var body = (h ?? fallback ?? (_) => const FakeResponse(404, {'detail': 'Not Found'}))(o);
    var status = 200;
    if (body is FakeResponse) {
      status = body.status;
      body = body.body;
    }
    call.done = true;
    return ResponseBody.fromString(body is String ? body : jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A non-200 answer (or a 200 with an explicit status) from a [FakeHandler].
class FakeResponse {
  const FakeResponse(this.status, this.body);
  final int status;
  final Object? body;
}

/// A JSON fixture from `test/fixtures/payloads/` (the recorded body under `payload`, without the `_source` note).
Object? payload(String name) {
  final j = jsonDecode(File('test/fixtures/payloads/$name').readAsStringSync());
  return j is Map && j.containsKey('_source') && j.containsKey('payload') ? j['payload'] : j;
}

/// Answers the plugin channels every request touches (the access token, the device id / name headers): in a widget
/// test an unanswered channel never completes inside the fake clock, so every request would hang before the adapter.
void mockRequestPlugins({String accessToken = 'test-access-token'}) {
  FlutterSecureStorage.setMockInitialValues({'access_token': accessToken, 'refresh_token': 'test-refresh-token'});
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('android_id'), (_) async => 'test-device');
  m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/device_info'), (_) async => null);
}
