// lib/core/live/live_events_client.dart
//
// The app's real-time client (Track D, docs/polish/realtime-inventory.md "Recommended design" 2 and 4):
// ONE Server-Sent Events stream, GET /api/v1/me/events, fed into LiveEvents.instance — the same bus the
// silent FCM pushes use — so a screen subscribes once and gets the event from whichever channel is faster.
//
//   LiveEventsClient.instance.bind()            "someone wants live events" (AttentionService while it polls,
//                                               a job screen while it waits); release() when done
//   LiveEventsClient.instance.connected         ValueNotifier<bool>; AttentionService stretches its poll on it
//   LiveEventsClient.instance.ingest(name, id)  a push from another channel (FCM data push, the web service
//                                               worker) goes through the same dedupe and the same bus
//   LiveEventsClient.instance.sessionChanged()  login / logout: drop the stream, reconnect with the new token
//   LiveEventsClient.instance.poke()            cheap "re-check now" (AttentionService calls it after a token
//                                               was seen, so the stream opens right after login)
//
// The stream is open only while (a) an access token exists, (b) the app is in front and (c) something is bound.
// It reconnects with exponential backoff (1 s → 30 s plus jitter) and resends Last-Event-ID; a 401 is retried
// once through a ticket (POST /api/v1/me/events/ticket goes through ApiClient, so the Dio interceptor refreshes
// the token on the way) and then the client stops until the access token changes. Events are deduplicated by
// id (the last 200). A stream that stays silent longer than [stallAfter] (the server pings every 25 s) is dropped
// and reopened.
//
// Web: package:http's BrowserClient streams a fetch() body, and fetch may send the Authorization and
// Last-Event-ID headers, which EventSource cannot (and the app's envelope encryption does not apply to this
// plain stream). The pure parts (SseParser, EventDedupe, backoffFor, shouldConnect, streamHeaders) are
// unit-tested in test/org/live_events_client_test.dart.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../utils/live_events.dart';
import '../api_client.dart';

// ── Pure parts ───────────────────────────────────────────────────────────────

/// One parsed SSE frame.
class SseEvent {
  const SseEvent({this.id, required this.name, required this.data});

  final String? id;
  final String name;
  final String data;

  /// The frame's data as a map (`{"value": …}` when the server sent a scalar, `{}` when it is not JSON).
  Map<String, dynamic> get json {
    if (data.isEmpty) return const {};
    try {
      final v = jsonDecode(data);
      if (v is Map) return Map<String, dynamic>.from(v);
      return {'value': v};
    } catch (_) {
      return const {};
    }
  }
}

/// Incremental parser of a `text/event-stream` (https://html.spec.whatwg.org/multipage/server-sent-events.html):
/// feed it text chunks in any split and it returns the frames that became complete. Comment lines (`: ping`)
/// are ignored, `data:` lines of one frame are joined with newlines, `id:` sets [lastId] even on a frame that
/// carries no data, `retry:` lands in [retryMs].
class SseParser {
  String _pending = '';
  String? _id;
  String _name = '';
  final List<String> _data = [];

  /// The last `id:` seen on the stream (what Last-Event-ID resends).
  String? lastId;
  int? retryMs;

  List<SseEvent> feed(String chunk) {
    var text = _pending + chunk;
    var carry = '';
    if (text.endsWith('\r')) {
      // may be the first half of a "\r\n" split across chunks
      carry = '\r';
      text = text.substring(0, text.length - 1);
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n');
    _pending = lines.removeLast() + carry;
    final out = <SseEvent>[];
    for (final line in lines) {
      if (line.isEmpty) {
        final e = _dispatch();
        if (e != null) out.add(e);
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          _name = value;
        case 'data':
          _data.add(value);
        case 'id':
          if (!value.contains(String.fromCharCode(0))) {
            _id = value;
            lastId = value;
          }
        case 'retry':
          retryMs = int.tryParse(value) ?? retryMs;
        default:
          break;
      }
    }
    return out;
  }

  SseEvent? _dispatch() {
    final id = _id;
    final name = _name.isEmpty ? 'message' : _name;
    final data = _data.join('\n');
    _id = null;
    _name = '';
    _data.clear();
    if (data.isEmpty) return null;
    return SseEvent(id: id, name: name, data: data);
  }
}

/// Remembers the last [capacity] event ids so the same event, seen over SSE and again as an FCM push, is
/// delivered once.
class EventDedupe {
  EventDedupe([this.capacity = 200]);

  final int capacity;
  final Set<String> _ids = {};
  final ListQueue<String> _order = ListQueue();

  int get length => _ids.length;

  /// True when [id] was already seen; otherwise records it (and forgets the oldest beyond [capacity]).
  bool seen(String id) {
    if (id.isEmpty) return false;
    if (_ids.contains(id)) return true;
    _ids.add(id);
    _order.addLast(id);
    while (_order.length > capacity) {
      _ids.remove(_order.removeFirst());
    }
    return false;
  }

  void clear() {
    _ids.clear();
    _order.clear();
  }
}

/// Reconnect delay for the n-th failed attempt (0-based): 1, 2, 4, 8, 16 s, then 30 s, plus up to one second of
/// jitter ([jitter] in 0..1, the caller's random number).
Duration backoffFor(int attempt, double jitter) {
  final a = attempt < 0 ? 0 : attempt;
  final base = a >= 5 ? 30 : (1 << a);
  final j = jitter.isNaN ? 0.0 : jitter.clamp(0.0, 1.0);
  return Duration(milliseconds: base * 1000 + (j * 1000).round());
}

/// The stream is open only with a token, in front, and while something listens.
bool shouldConnect({required bool hasToken, required bool foreground, required int binds}) =>
    hasToken && foreground && binds > 0;

/// Request headers of the stream: bearer auth unless a ticket is in the query, Last-Event-ID on a reconnect.
Map<String, String> streamHeaders({String? token, String? lastId}) => {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (lastId != null && lastId.isNotEmpty) 'Last-Event-ID': lastId,
    };

// ── The client ───────────────────────────────────────────────────────────────

class LiveEventsClient with WidgetsBindingObserver {
  LiveEventsClient._();

  static final LiveEventsClient instance = LiveEventsClient._();

  static const streamPath = '/api/v1/me/events';
  static const ticketPath = '/api/v1/me/events/ticket';
  static const stallAfter = Duration(seconds: 90);

  /// True while the stream is open (AttentionService polls every 5 min instead of 60 s then).
  final ValueNotifier<bool> connected = ValueNotifier(false);

  final EventDedupe _dedupe = EventDedupe(200);
  final Random _random = Random();

  int _binds = 0;
  bool _foreground = true;
  bool _observing = false;
  bool _evaluating = false;
  bool _again = false;
  bool _connecting = false;
  int _gen = 0;
  int _attempt = 0;
  String? _lastId;
  String? _haltedToken;
  http.Client? _http;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  Timer? _stall;

  /// Diagnostics.
  int get binds => _binds;
  bool get halted => _haltedToken != null;

  static Uri streamUri({String? ticket}) {
    final base = Uri.parse('${AppConfig.baseUrl}$streamPath');
    if (ticket == null || ticket.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, 't': ticket});
  }

  /// Someone wants live events; pair with [release].
  void bind() {
    _binds++;
    _ensureObserver();
    _evaluate();
  }

  void release() {
    if (_binds > 0) _binds--;
    _evaluate();
  }

  /// Login or logout: the stream is dropped and reopened with the current token (if any).
  void sessionChanged() {
    _haltedToken = null;
    _lastId = null;
    _attempt = 0;
    _retry?.cancel();
    _retry = null;
    _disconnect();
    _evaluate();
  }

  /// Re-check the conditions (cheap; nothing happens while the stream is open).
  void poke() {
    if (_sub != null || _connecting || _retry != null) return;
    _evaluate();
  }

  /// An event that arrived on another channel (FCM data push, web service worker): same dedupe, same bus.
  /// Returns false when it was a duplicate.
  bool ingest(String name, String? eventId, Map<String, dynamic> data) {
    if (name.isEmpty) return false;
    if (eventId != null && eventId.isNotEmpty && _dedupe.seen(eventId)) return false;
    LiveEvents.instance.emit(name, data);
    return true;
  }

  void _ensureObserver() {
    if (_observing) return;
    _observing = true;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final s = binding.lifecycleState;
    _foreground = s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached => false,
    };
    if (front == _foreground) return;
    _foreground = front;
    if (front) {
      // come back at once, not after the backoff that was running
      _retry?.cancel();
      _retry = null;
      _attempt = 0;
    }
    _evaluate();
  }

  Future<void> _evaluate() async {
    if (_evaluating) {
      _again = true;
      return;
    }
    _evaluating = true;
    try {
      String? token;
      try {
        token = await ApiClient().accessToken;
      } catch (_) {}
      if (token != null && token.isEmpty) token = null;
      if (_haltedToken != null && _haltedToken != token) _haltedToken = null;
      final want = _haltedToken == null &&
          shouldConnect(hasToken: token != null, foreground: _foreground, binds: _binds);
      if (!want) {
        _retry?.cancel();
        _retry = null;
        _disconnect();
        return;
      }
      if (_sub != null || _connecting || _retry != null) return;
      _connect(token!);
    } finally {
      _evaluating = false;
      if (_again) {
        _again = false;
        _evaluate();
      }
    }
  }

  Future<void> _connect(String token, {String? ticket}) async {
    _connecting = true;
    final gen = ++_gen;
    final client = http.Client();
    _http = client;
    final req = http.Request('GET', streamUri(ticket: ticket))
      ..headers.addAll(streamHeaders(token: ticket == null ? token : null, lastId: _lastId));
    http.StreamedResponse res;
    try {
      res = await client.send(req);
    } catch (e) {
      if (gen != _gen) return;
      _log('connect failed: $e');
      _connecting = false;
      _closeHttp();
      _scheduleRetry();
      return;
    }
    if (gen != _gen) return;
    if (res.statusCode == 401) {
      _closeHttp();
      if (ticket != null) {
        _halt(token);
        return;
      }
      // once through the ticket: the POST goes through ApiClient, whose interceptor refreshes the token
      String t = '';
      try {
        final r = await ApiClient().post(ticketPath);
        t = r is Map ? '${r['ticket'] ?? ''}' : '';
      } catch (e) {
        _log('ticket failed: $e');
      }
      if (gen != _gen) return;
      if (t.isEmpty) {
        _halt(token);
        return;
      }
      _connecting = false;
      return _connect(token, ticket: t);
    }
    if (res.statusCode != 200) {
      _log('status ${res.statusCode}');
      _connecting = false;
      _closeHttp();
      _scheduleRetry();
      return;
    }
    _connecting = false;
    _attempt = 0;
    final parser = SseParser();
    _sub = res.stream.transform(utf8.decoder).listen(
      (chunk) {
        _armStall(gen);
        for (final e in parser.feed(chunk)) {
          _deliver(e);
        }
      },
      onError: (Object e) => _lost(gen, 'stream error: $e'),
      onDone: () => _lost(gen, 'stream closed'),
      cancelOnError: true,
    );
    _armStall(gen);
    connected.value = true;
  }

  void _deliver(SseEvent e) {
    final id = e.id;
    if (id != null && id.isNotEmpty) {
      _lastId = id;
      if (_dedupe.seen(id)) return;
    }
    if (e.name == 'message' || e.name == 'ping') return;
    LiveEvents.instance.emit(e.name, e.json);
  }

  void _armStall(int gen) {
    _stall?.cancel();
    _stall = Timer(stallAfter, () => _lost(gen, 'stalled'));
  }

  void _lost(int gen, String why) {
    if (gen != _gen) return;
    _log(why);
    _sub?.cancel();
    _sub = null;
    _stall?.cancel();
    _stall = null;
    _closeHttp();
    connected.value = false;
    _scheduleRetry();
  }

  void _halt(String token) {
    _log('unauthorised: waiting for a new token');
    _haltedToken = token;
    _connecting = false;
    connected.value = false;
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(backoffFor(_attempt, _random.nextDouble()), () {
      _retry = null;
      _evaluate();
    });
    _attempt = min(_attempt + 1, 8);
  }

  void _disconnect() {
    _gen++;
    _connecting = false;
    _sub?.cancel();
    _sub = null;
    _stall?.cancel();
    _stall = null;
    _closeHttp();
    if (connected.value) connected.value = false;
  }

  void _closeHttp() {
    final c = _http;
    _http = null;
    try {
      c?.close(); // aborts an in-flight fetch / socket on every platform
    } catch (_) {}
  }

  void _log(String s) {
    if (kDebugMode) debugPrint('[live] $s');
  }
}
