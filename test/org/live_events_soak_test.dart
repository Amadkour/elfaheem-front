// LiveEventsClient (lib/core/live/live_events_client.dart) driven over real HTTP.
//
// Fast part (always, CI): a local dart:io server that plays the backend's stream (the frames are shaped exactly as
// helpers/live_bus.sse writes them) and its failure modes: a 200 that closes at once (Redis down), the `retry:`
// hint, a silent stream (the stall watchdog), a rollover with Last-Event-ID, 401 → ticket, release / background.
//
// Soak part (opt-in): against a real core server, e.g. the one `../back/tests/load/sse_stress.py --serve-only
// --max-seconds 3` leaves up (it prints the three variables below). Events are published straight to Redis (the
// same keys as helpers/live_bus.publish), several clients per user, rollovers every 3 s:
//
//   LIVE_SOAK_URL=http://127.0.0.1:18431 LIVE_SOAK_REDIS=127.0.0.1:6379/15 LIVE_SOAK_USERS=<id:token,…> \
//   [LIVE_SOAK_SECONDS=30] flutter test test/org/live_events_soak_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

/// One frame as the server writes it: the whole event is the data line.
String serverFrame(String id, String event, Map<String, dynamic> data) =>
    'id: $id\nevent: $event\ndata: ${jsonEncode({'id': id, 'event': event, 'data': data, 'ts': '2026-10-28T00:00:00.000'})}\n\n';

class _Srv {
  late HttpServer _server;
  final requests = <HttpRequest>[];
  final times = <Duration>[];
  final _clock = Stopwatch()..start();
  final open = <HttpResponse>[];
  Future<void> Function(HttpRequest req, int n) handler = (req, n) async {};

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) {
      requests.add(req);
      times.add(_clock.elapsed);
      handler(req, requests.length);
    });
  }

  Future<void> stop() async {
    for (final r in open) {
      try {
        await r.close();
      } catch (_) {}
    }
    await _server.close(force: true);
  }

  /// Starts an event stream: [first] is written at once; [close] ends it right after.
  Future<HttpResponse> sse(HttpRequest req, {String first = ': connected\n\n', bool close = false}) async {
    final res = req.response
      ..statusCode = 200
      ..bufferOutput = false;
    res.headers.contentType = ContentType('text', 'event-stream');
    res.write(first);
    await res.flush();
    if (close) {
      await res.close();
    } else {
      open.add(res);
    }
    return res;
  }

  Future<void> deny(HttpRequest req, int status) async {
    req.response.statusCode = status;
    await req.response.close();
  }
}

Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 5), String? what}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) fail('timed out waiting for ${what ?? 'a condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _Srv srv;
  late LiveEventsClient c;
  String? token;
  final received = <LiveEvent>[];
  StreamSubscription<LiveEvent>? busSub;

  LiveEventsClient make({
    Duration stallAfter = const Duration(seconds: 30),
    Duration healthyAfter = const Duration(seconds: 20),
    double delayScale = 0.002,
    Future<String?> Function()? ticket,
  }) =>
      LiveEventsClient.test(
        token: () async => token,
        ticket: ticket,
        baseUrl: srv.base,
        stallAfter: stallAfter,
        healthyAfter: healthyAfter,
        delayScale: delayScale,
      );

  setUp(() async {
    srv = _Srv();
    await srv.start();
    token = 'tok-1';
    received.clear();
    busSub = LiveEvents.instance.listen(
        {LiveEvents.jobUpdated, LiveEvents.attentionChanged, 'soak_x'}, received.add);
  });

  tearDown(() async {
    c.release();
    await busSub?.cancel();
    await srv.stop();
  });

  test('server-shaped frames reach the bus as flat data, and JobWatch matches them by kind and id', () async {
    srv.handler = (req, n) => srv.sse(req,
        first: ': connected\n\n${serverFrame('e-1', 'job_updated', {'kind': 'rag_query', 'id': 42, 'status': 'done'})}');
    c = make();
    final watch = JobWatch(kind: 'rag_query', id: '42', stream: LiveStreamHandle(connected: c.connected, bind: c.bind, release: c.release));
    final next = watch.next(const Duration(seconds: 10));
    final e = await next.timeout(const Duration(seconds: 5));
    expect(e, isNotNull, reason: 'the job event must match kind + id (it used to carry the server envelope)');
    expect(e!.kind, 'rag_query');
    expect(e.id, '42');
    expect(e.status, 'done');
    expect(srv.requests.single.headers.value('authorization'), 'Bearer tok-1');
    watch.dispose();
    c.bind(); // tearDown releases once
  });

  test('a 200 that closes at once (Redis down) is a failed attempt: the backoff keeps growing', () async {
    srv.handler = (req, n) => srv.sse(req, close: true);
    c = make()..bind();
    await until(() => srv.requests.length >= 6, what: '6 attempts');
    expect(c.attempt, greaterThanOrEqualTo(5), reason: 'the attempt counter used to reset on every 200');
    final gaps = [for (var i = 1; i < srv.times.length; i++) srv.times[i] - srv.times[i - 1]];
    // 2, 4, 8, 16, 32 ms (+ jitter): the fifth gap is clearly longer than the first
    expect(gaps[4], greaterThan(gaps[0]));
  });

  test("the server's retry: hint is the minimum delay", () async {
    srv.handler = (req, n) => srv.sse(req, first: 'retry: 30000\n: unavailable\n\n', close: true);
    c = make(delayScale: 0.004)..bind(); // 30 s → 120 ms; the first backoff would be 4 ms
    await until(() => srv.requests.length >= 3, what: '3 attempts');
    for (var i = 1; i < 3; i++) {
      expect(srv.times[i] - srv.times[i - 1], greaterThanOrEqualTo(const Duration(milliseconds: 110)));
    }
  });

  test('a healthy stream that ends (rollover) reconnects at once and resends Last-Event-ID', () async {
    srv.handler = (req, n) async {
      if (n == 1) {
        final res = await srv.sse(req, first: ': connected\n\n${serverFrame('e-9', 'job_updated', {'kind': 'x', 'id': 1})}');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        res.write(': reconnect\n\n');
        await res.close();
      } else {
        await srv.sse(req);
      }
    };
    c = make(healthyAfter: const Duration(milliseconds: 50))..bind();
    await until(() => srv.requests.length >= 2, what: 'the reconnect');
    expect(srv.requests[1].headers.value('last-event-id'), 'e-9');
    expect(c.attempt, 1, reason: 'a healthy stream starts the backoff over');
    await until(() => c.connected.value, what: 'connected again');
    expect(received.where((e) => e.kind == 'x' && e.id == '1'), hasLength(1), reason: 'not replayed twice');
  });

  test('a silent stream is dropped by the watchdog and reopened', () async {
    srv.handler = (req, n) => srv.sse(req);
    c = make(stallAfter: const Duration(milliseconds: 200))..bind();
    await until(() => srv.requests.length >= 3, timeout: const Duration(seconds: 15), what: 'two stall reconnects');
  });

  test('the FCM and the SSE copy of one event reach the bus once, whichever comes first', () async {
    // The client can read the headers (connected) before the server's flush() future resolves, so the server's
    // response is awaited on its own rather than read from a variable the handler may not have set yet.
    final opened = Completer<HttpResponse>();
    srv.handler = (req, n) async {
      final r = await srv.sse(req);
      if (!opened.isCompleted) opened.complete(r);
    };
    c = make()..bind();
    await until(() => c.connected.value, what: 'connected');
    final res = await opened.future.timeout(const Duration(seconds: 5));
    expect(c.ingest('job_updated', 'a-1', {'kind': 'k', 'id': '1', 'event_id': 'a-1'}), isTrue); // the FCM twin first
    res.write(serverFrame('a-1', 'job_updated', {'kind': 'k', 'id': '1'}));
    res.write(serverFrame('b-2', 'job_updated', {'kind': 'k', 'id': '2'}));
    await res.flush();
    await until(() => received.any((e) => e.id == '2'), what: 'b-2 over SSE');
    expect(c.ingest('job_updated', 'b-2', {'kind': 'k', 'id': '2'}), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received.map((e) => e.id).toList(), ['1', '2']);
  });

  test('release closes the stream and leaves no timer, also during a backoff', () async {
    srv.handler = (req, n) => srv.sse(req);
    c = make()..bind();
    await until(() => c.connected.value, what: 'connected');
    expect(c.busy, isTrue);
    c.release();
    await until(() => !c.busy && !c.connected.value, what: 'idle after release');
    final n = srv.requests.length;
    // during a backoff
    srv.handler = (req, n) => srv.deny(req, 503);
    c.bind();
    await until(() => srv.requests.length > n, what: 'an attempt');
    c.release();
    await until(() => !c.busy, what: 'the retry timer cancelled');
    final m = srv.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(srv.requests.length, m, reason: 'no attempt after the last release');
    c.bind(); // tearDown releases once
  });

  test('background closes the stream; coming back reconnects at once', () async {
    srv.handler = (req, n) => srv.sse(req);
    // Every backoff ×10 (≥ 10 s): coming back within 5 s can only be the immediate reconnect, however slow the
    // machine (a 900 ms wall-clock window against the 1 s minimum backoff failed under load).
    c = make(delayScale: 10)..bind();
    const slow = Duration(seconds: 15); // a loaded machine (the full suite) misses 5 s on a real socket
    await until(() => c.connected.value, what: 'connected', timeout: slow);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    await until(() => !c.busy && !c.connected.value, what: 'closed in the background', timeout: slow);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(srv.requests, hasLength(1));
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await until(() => c.connected.value, what: 'back without a backoff', timeout: slow);
    expect(srv.requests, hasLength(2));
  });

  test('401 → one ticket in the query; a refused ticket halts until the token changes', () async {
    var tickets = 0;
    srv.handler = (req, n) async {
      if (req.uri.queryParameters['t'] == 'tk-ok') {
        await srv.sse(req);
      } else {
        await srv.deny(req, 401);
      }
    };
    c = make(ticket: () async => ++tickets == 1 ? 'tk-ok' : 'tk-bad')..bind();
    await until(() => c.connected.value, what: 'connected through the ticket');
    expect(srv.requests.last.headers.value('authorization'), isNull);
    c.release();
    await until(() => !c.busy);
    c.bind();
    await until(() => c.halted, what: 'halted on the refused ticket');
    final n = srv.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(srv.requests.length, n);
    token = 'tok-2';
    tickets = 0;
    c.poke();
    await until(() => c.connected.value, what: 'a new token reconnects');
  });

  // ── soak against a real server (opt-in) ──────────────────────────────────
  final env = Platform.environment;
  final soakUrl = env['LIVE_SOAK_URL'];
  test('soak: several clients per user against a real server, rollovers, no loss, no leak', () async {
    final users = [
      for (final p in (env['LIVE_SOAK_USERS'] ?? '').split(','))
        if (p.contains(':')) (int.parse(p.split(':').first), p.substring(p.indexOf(':') + 1)),
    ];
    final redis = await _Resp.connect(env['LIVE_SOAK_REDIS'] ?? '127.0.0.1:6379/15');
    final seconds = int.tryParse(env['LIVE_SOAK_SECONDS'] ?? '') ?? 30;
    const perUser = 3;
    final clients = [
      for (final (_, tok) in users)
        for (var i = 0; i < perUser; i++)
          LiveEventsClient.test(token: () async => tok, baseUrl: soakUrl!, healthyAfter: const Duration(seconds: 2)),
    ];
    final counts = <String, int>{};
    // a fresh connect replays the recent list (10 min): count only this run's events
    final run = 'soak-${DateTime.now().microsecondsSinceEpoch}';
    final sub = LiveEvents.instance.listen({'soak_x'}, (e) {
      if (e.kind != run) return;
      final id = '${e.id}';
      counts[id] = (counts[id] ?? 0) + 1;
    });
    for (final x in clients) {
      x.bind();
    }
    await until(() => clients.every((x) => x.connected.value), timeout: const Duration(seconds: 20), what: 'all connected');
    final sent = <String>[];
    final sw = Stopwatch()..start();
    var n = 0;
    while (sw.elapsed < Duration(seconds: seconds)) {
      final (uid, _) = users[n % users.length];
      await redis.publish(uid, 'soak_x', {'kind': run, 'id': n});
      sent.add('$n');
      n++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(seconds: 8)); // the last rollover + backoff
    final lost = sent.where((id) => (counts[id] ?? 0) < perUser).length;
    final dup = sent.where((id) => (counts[id] ?? 0) > perUser).length;
    // ignore: avoid_print
    print('soak: ${clients.length} clients, ${sent.length} events, lost $lost, duplicated $dup; short: '
        '${[for (final id in sent) if ((counts[id] ?? 0) != perUser) '#$id x${counts[id] ?? 0}']}; '
        'attempts ${clients.map((x) => x.attempt).toList()}');
    expect(lost, 0);
    expect(dup, 0);
    for (final x in clients) {
      x.release();
    }
    await until(() => clients.every((x) => !x.busy), what: 'every client idle after release');
    await sub.cancel();
    await redis.close();
    c = make(); // tearDown
  }, skip: soakUrl == null ? 'set LIVE_SOAK_URL / LIVE_SOAK_USERS / LIVE_SOAK_REDIS to soak against a real server' : false,
      timeout: const Timeout(Duration(minutes: 5)));
}

/// Just enough RESP to publish like helpers/live_bus.publish (PUBLISH + the capped recent list).
class _Resp {
  _Resp(this._s) {
    _s.listen((b) {
      _replies += utf8.decode(b, allowMalformed: true).split('\r\n').length - 1;
    });
  }

  final Socket _s;
  int _replies = 0;
  int _sent = 0;
  int _seq = 0;

  static Future<_Resp> connect(String spec) async {
    final hostPort = spec.split('/').first;
    final db = spec.contains('/') ? spec.split('/').last : '0';
    final s = await Socket.connect(hostPort.split(':').first, int.parse(hostPort.split(':').last));
    final r = _Resp(s);
    await r._cmd(['SELECT', db]);
    return r;
  }

  /// Sends [args] and [more] in ONE write (a pipeline, as redis-py does) and waits for every reply.
  Future<void> _cmd(List<String> args, [List<List<String>> more = const []]) async {
    final b = StringBuffer();
    for (final c in [args, ...more]) {
      b.write('*${c.length}\r\n');
      for (final a in c) {
        b.write('\$${utf8.encode(a).length}\r\n$a\r\n');
      }
      _sent++;
    }
    _s.add(utf8.encode(b.toString()));
    final want = _sent;
    await until(() => _replies >= want, what: 'Redis reply');
  }

  Future<String> publish(int uid, String event, Map<String, dynamic> data) async {
    final id = 'soak-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final raw = jsonEncode({'id': id, 'event': event, 'data': data, 'ts': DateTime.now().toUtc().toIso8601String()});
    // one pipeline, in the order helpers/live_bus.publish uses
    await _cmd(['PUBLISH', 'nb:live:$uid', raw], [
      ['LPUSH', 'nb:live:recent:$uid', raw],
      ['LTRIM', 'nb:live:recent:$uid', '0', '99'],
      ['EXPIRE', 'nb:live:recent:$uid', '600'],
    ]);
    return id;
  }

  Future<void> close() => _s.close();
}
