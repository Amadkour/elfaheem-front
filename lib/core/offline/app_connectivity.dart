/// core/offline/app_connectivity.dart
///
/// ONE answer to "is the app online?", used by [TopRouteObserver] and the attendance buttons.
///
///   online = (the phone has a network link)  AND  (our server is reachable)
///
/// The link comes from connectivity_plus (instant). Server reachability has three sources:
///   - the ThemeConfigProvider.serverUnreachable signal, fed in from main.dart ([reportServerReachable]);
///   - every ApiClient request ([ReachabilityInterceptor], QA_PHASE7 W-1): a request that got no answer (no response,
///     a timeout, a refused connection, a gateway's 502 / 504) marks the server unreachable; ANY answer marks it
///     reachable again. A failure of a request that went out before the last answer is stale and changes nothing,
///     so one slow call that times out next to calls that succeed never flips the app offline;
///   - [serverProbe] (main.dart: a theme reload, a public route), so a Wi-Fi that has no real internet counts as
///     OFFLINE until the server answers.
///
/// Re-probe (W-2), EventOrPoll style: while the server is unreachable and the link is up, the next probe is booked
/// when the last one finished — 5 s, doubling, at most 60 s ([probeBackoff]) — never two at once; the link coming
/// back and the app resuming ([onResume]) probe at once. Nothing is booked while the server answers, so a healthy
/// app never sends a probe (test/perf/ budgets). Back online, TopRouteObserver's one listener drains the outbox.
///
/// pubspec.yaml:  connectivity_plus: any   (already pinned in dependency_overrides)
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart' show ApiException;

/// The wait before the [n]-th re-probe in a row (n ≥ 1): 5 s doubling, at most 60 s.
Duration probeBackoff(int n) {
  final s = 5 * (1 << (n - 1).clamp(0, 4));
  return Duration(seconds: s > 60 ? 60 : s);
}

/// What one failed ApiClient request says about the server: true = it answered, false = it did not, null = nothing
/// (a cancel, a certificate refusal: the server may be fine).
bool? serverAnsweredBy(DioException e) {
  // the app's own refusal before sending (a guest's write, the pin update): no word about the server
  if (e.error is ApiException) return null;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return false;
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
      return null;
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
    case DioExceptionType.transformTimeout:
      final s = e.response?.statusCode;
      if (s == null) return e.type == DioExceptionType.unknown ? false : null;
      return !(s == 502 || s == 504); // the gateway is up but the API behind it is not
  }
}

class AppConnectivity {
  AppConnectivity._();
  static final AppConnectivity instance = AppConnectivity._();

  /// Tests: a fresh one with its own clock and timers.
  @visibleForTesting
  factory AppConnectivity.forTest({
    DateTime Function()? now,
    Timer Function(Duration d, void Function() f)? timer,
  }) {
    final c = AppConnectivity._();
    if (now != null) c.now = now;
    if (timer != null) c.timer = timer;
    return c;
  }

  /// Listen to this. `true` = online.
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// Set from main.dart: re-checks the server and returns true when it answered. No probe is ever booked without it;
  /// set while the server is already unreachable (an offline start), the first one is booked.
  Future<bool> Function()? get serverProbe => _serverProbe;
  set serverProbe(Future<bool> Function()? f) {
    _serverProbe = f;
    if (f == null) {
      _stopProbe();
    } else {
      _bookProbe();
    }
  }

  Future<bool> Function()? _serverProbe;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  @visibleForTesting
  Timer Function(Duration d, void Function() f) timer = Timer.new;

  bool _link = true;
  bool _server = true;
  DateTime? _lastAnswer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Timer? _probeTimer;
  bool _probing = false;
  int _probes = 0;

  bool get isOnline => online.value;

  /// The server answered the last time anyone asked.
  bool get serverReachable => _server;

  /// A re-probe is booked (tests).
  bool get probeBooked => _probeTimer != null;

  Future<void> init() async {
    final c = Connectivity();
    try {
      _link = _hasLink(await c.checkConnectivity());
    } catch (_) {}
    _sub ??= c.onConnectivityChanged.listen(onLink);
    _recompute();
  }

  static bool _hasLink(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);

  /// connectivity_plus: the link changed.
  @visibleForTesting
  Future<void> onLink(List<ConnectivityResult> r) async {
    final had = _link;
    _link = _hasLink(r);
    if (!_link) {
      _stopProbe(); // no link: nothing to ask until it comes back
    } else if (!had && serverProbe != null) {
      // Link is back: do NOT trust it yet — ask the server.
      _server = false;
      _recompute();
      await _probeNow(reset: true);
      return;
    } else if (!_server) {
      _bookProbe();
    }
    _recompute();
  }

  /// main.dart: pass `!themeConfig.serverUnreachable` whenever it changes.
  void reportServerReachable(bool reachable) {
    _server = reachable;
    if (reachable) {
      _lastAnswer = now();
      _stopProbe();
    } else {
      _bookProbe();
    }
    _recompute();
  }

  /// The ApiClient: a request got an answer (any status but a gateway's 502 / 504). One answer is enough.
  void noteAnswer() {
    _lastAnswer = now();
    if (_server) return;
    _server = true;
    _stopProbe();
    _recompute();
  }

  /// The ApiClient: a request that went out at [startedAt] got no answer. Stale (an answer came after it went out)
  /// = ignored.
  void noteNoAnswer({DateTime? startedAt}) {
    final last = _lastAnswer;
    if (startedAt != null && last != null && startedAt.isBefore(last)) return;
    if (!_server) return;
    _server = false;
    _recompute();
    _bookProbe();
  }

  /// main.dart, the app came to the front: an unreachable server is asked again at once.
  void onResume() {
    if (_server || !_link) return;
    unawaited(_probeNow(reset: true));
  }

  void _bookProbe() {
    if (_server || !_link || serverProbe == null || _probing || _probeTimer != null) return;
    _probes++;
    _probeTimer = timer(probeBackoff(_probes), () {
      _probeTimer = null;
      unawaited(_probeNow());
    });
  }

  Future<void> _probeNow({bool reset = false}) async {
    final probe = serverProbe;
    if (probe == null || _probing) return;
    if (reset) _probes = 0;
    _probeTimer?.cancel();
    _probeTimer = null;
    _probing = true;
    bool ok;
    try {
      ok = await probe();
    } catch (_) {
      ok = false;
    }
    _probing = false;
    if (ok) {
      _lastAnswer = now();
      _server = true;
      _stopProbe();
    } else {
      _server = false;
      _bookProbe();
    }
    _recompute();
  }

  void _stopProbe() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _probes = 0;
  }

  void _recompute() {
    final v = _link && _server;
    if (v != online.value) online.value = v;
  }

  Future<void> dispose() async {
    _stopProbe();
    await _sub?.cancel();
  }
}

/// Feeds every request's outcome into [AppConnectivity] (ApiClient adds it first, so it sees the raw outcome).
class ReachabilityInterceptor extends Interceptor {
  ReachabilityInterceptor({AppConnectivity Function()? target}) : _target = target ?? (() => AppConnectivity.instance);

  final AppConnectivity Function() _target;

  static const _sentAt = '_reach_sent_at';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_sentAt] = _target().now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final s = response.statusCode ?? 200;
    if (s == 502 || s == 504) {
      _target().noteNoAnswer(startedAt: _sent(response.requestOptions));
    } else {
      _target().noteAnswer();
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final answered = serverAnsweredBy(err);
    if (answered == true) {
      _target().noteAnswer();
    } else if (answered == false) {
      _target().noteNoAnswer(startedAt: _sent(err.requestOptions));
    }
    handler.next(err);
  }

  static DateTime? _sent(RequestOptions o) {
    final v = o.extra[_sentAt];
    return v is DateTime ? v : null;
  }
}
