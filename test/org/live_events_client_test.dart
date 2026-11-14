// The pure parts of the real-time client (lib/core/live/live_events_client.dart): the SSE parser, the dedupe
// window, the backoff sequence and the "should the stream be open" decision. No network.
import 'dart:io';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

void main() {
  group('pinned stream client', () {
    test("on devices the stream runs on the API's pinned HttpClient, never the system trust store", () {
      expect(LiveEventsClient.pinnedHttpClientFactory == ApiClient.pinnedHttpClient, isTrue);
      final saved = LiveEventsClient.pinnedHttpClientFactory;
      var built = 0;
      LiveEventsClient.pinnedHttpClientFactory = () {
        built++;
        return saved();
      };
      addTearDown(() => LiveEventsClient.pinnedHttpClientFactory = saved);
      final c = LiveEventsClient.streamHttpClient();
      expect(c, isA<IOClient>());
      expect(built, 1);
      c.close();
      // the connect path uses that client, not a plain http.Client()
      final src = File('lib/core/live/live_events_client.dart').readAsStringSync();
      expect(src, contains('final client = streamHttpClient();'));
      expect(RegExp(r'= http\.Client\(\);').hasMatch(src), isFalse);
    });
  });

  group('SseParser', () {
    test('one frame with id, event and json data', () {
      final p = SseParser();
      final out = p.feed('id: e1\nevent: attention_changed\ndata: {"tab":"home","org_id":"4"}\n\n');
      expect(out, hasLength(1));
      expect(out.single.id, 'e1');
      expect(out.single.name, 'attention_changed');
      expect(out.single.json, {'tab': 'home', 'org_id': '4'});
      expect(p.lastId, 'e1');
    });

    test('frames split across chunks at any byte, including inside "\\r\\n"', () {
      final whole = 'id: a\r\nevent: x\r\ndata: {"n":1}\r\n\r\nid: b\r\nevent: y\r\ndata: {"n":2}\r\n\r\n';
      for (var cut = 1; cut < whole.length; cut++) {
        final p = SseParser();
        final out = [...p.feed(whole.substring(0, cut)), ...p.feed(whole.substring(cut))];
        expect(out.map((e) => e.id).toList(), ['a', 'b'], reason: 'cut at $cut');
        expect(out.map((e) => e.name).toList(), ['x', 'y'], reason: 'cut at $cut');
        expect(out.map((e) => e.json['n']).toList(), [1, 2], reason: 'cut at $cut');
      }
    });

    test('multi-line data is joined with newlines, comments are ignored, a frame without data is dropped', () {
      final p = SseParser();
      var out = p.feed(': ping\n\n');
      expect(out, isEmpty);
      out = p.feed('event: note\ndata: line one\ndata:line two\ndata\n\n');
      expect(out, hasLength(1));
      expect(out.single.data, 'line one\nline two\n');
      expect(out.single.name, 'note');
      expect(out.single.id, isNull);
      // an id without data still moves Last-Event-ID
      out = p.feed('id: only-id\n\n');
      expect(out, isEmpty);
      expect(p.lastId, 'only-id');
      // a retry hint is kept, an unknown field ignored, no event name → "message"
      out = p.feed('retry: 5000\nfoo: bar\ndata: 7\n\n');
      expect(p.retryMs, 5000);
      expect(out.single.name, 'message');
      expect(out.single.json, {'value': 7});
    });

    test('an id of a frame is not inherited by the next frame', () {
      final p = SseParser();
      final out = p.feed('id: 1\nevent: a\ndata: {}\n\nevent: b\ndata: {}\n\n');
      expect(out[0].id, '1');
      expect(out[1].id, isNull);
      expect(p.lastId, '1');
    });

    test('non-json data gives an empty map', () {
      final out = SseParser().feed('event: a\ndata: not json\n\n');
      expect(out.single.json, isEmpty);
    });
  });

  group('EventDedupe', () {
    test('remembers the last N ids and forgets the oldest', () {
      final d = EventDedupe(3);
      expect(d.seen('a'), isFalse);
      expect(d.seen('a'), isTrue);
      expect(d.seen('b'), isFalse);
      expect(d.seen('c'), isFalse);
      expect(d.seen('d'), isFalse); // evicts a
      expect(d.length, 3);
      expect(d.seen('a'), isFalse);
      expect(d.seen('d'), isTrue);
      expect(d.seen(''), isFalse);
      d.clear();
      expect(d.length, 0);
    });

    test('the client keeps 200 ids by default', () {
      final d = EventDedupe();
      for (var i = 0; i < 250; i++) {
        d.seen('id$i');
      }
      expect(d.length, 200);
      expect(d.seen('id50'), isTrue);
      expect(d.seen('id49'), isFalse); // forgotten (and recorded again now)
    });
  });

  group('backoffFor', () {
    test('1, 2, 4, 8, 16 s then 30 s, plus at most one second of jitter', () {
      expect([for (var a = 0; a < 8; a++) backoffFor(a, 0).inSeconds], [1, 2, 4, 8, 16, 30, 30, 30]);
      expect(backoffFor(2, 0.5).inMilliseconds, 4500);
      expect(backoffFor(9, 1).inMilliseconds, 31000);
      expect(backoffFor(0, 2).inMilliseconds, 2000); // jitter clamped
      expect(backoffFor(-1, 0).inSeconds, 1);
    });
  });

  group('shouldConnect', () {
    test('token AND foreground AND a listener', () {
      expect(shouldConnect(hasToken: true, foreground: true, binds: 1), isTrue);
      expect(shouldConnect(hasToken: false, foreground: true, binds: 1), isFalse);
      expect(shouldConnect(hasToken: true, foreground: false, binds: 1), isFalse);
      expect(shouldConnect(hasToken: true, foreground: true, binds: 0), isFalse);
    });
  });

  group('streamHeaders', () {
    test('bearer and Last-Event-ID only when known', () {
      expect(streamHeaders(), {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'});
      expect(streamHeaders(token: 'T', lastId: 'L'), {
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Authorization': 'Bearer T',
        'Last-Event-ID': 'L',
      });
      expect(streamHeaders(token: '', lastId: '').containsKey('Authorization'), isFalse);
    });

    test('the ticket goes in the query', () {
      expect(LiveEventsClient.streamUri().path, endsWith('/api/v1/me/events'));
      expect(LiveEventsClient.streamUri(ticket: 'abc').queryParameters, {'t': 'abc'});
    });
  });

  group('ingest (other channels)', () {
    test('dedupes by event id and emits on the bus; the client stays unbound', () async {
      final got = <LiveEvent>[];
      final sub = LiveEvents.instance.listen({LiveEvents.jobUpdated}, got.add);
      final c = LiveEventsClient.instance;
      expect(c.ingest(LiveEvents.jobUpdated, 'ev-1', {'kind': 'rag_query', 'id': '9', 'status': 'done'}), isTrue);
      expect(c.ingest(LiveEvents.jobUpdated, 'ev-1', {'kind': 'rag_query', 'id': '9', 'status': 'done'}), isFalse);
      expect(c.ingest(LiveEvents.jobUpdated, null, {'kind': 'caption', 'id': '3'}), isTrue);
      expect(c.ingest('', 'ev-2', {}), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(got.map((e) => e.id).toList(), ['9', '3']);
      expect(got.first.kind, 'rag_query');
      expect(got.first.status, 'done');
      expect(c.binds, 0);
      expect(c.connected.value, isFalse);
      await sub.cancel();
    });
  });

  test('every server event name is on the bus list', () {
    expect(LiveEvents.serverTypes, containsAll([
      'attention_changed', 'complaints_updated', 'transfers_updated', 'payments_updated', 'payouts_updated',
      'lobby_updated', 'join_decided', 'job_updated', 'session_live', 'quiz_started',
    ]));
    expect(LiveEvents.silentTypes.length, 4);
  });

  test("reconnectDelay: the backoff, never shorter than the server's retry: hint", () {
    expect(reconnectDelay(0, 0), const Duration(seconds: 1));
    expect(reconnectDelay(0, 0, retryMs: 30000), const Duration(seconds: 30));
    expect(reconnectDelay(6, 0, retryMs: 5000), const Duration(seconds: 30));
  });

  test('attentionEventDelay: an event right after a reload is deferred, never dropped', () {
    final t0 = DateTime(2026, 10, 28, 12);
    expect(attentionEventDelay(last: null, now: t0, running: false), Duration.zero);
    expect(attentionEventDelay(last: t0, now: t0.add(const Duration(seconds: 6)), running: false), Duration.zero);
    expect(attentionEventDelay(last: t0, now: t0.add(const Duration(seconds: 2)), running: false), const Duration(seconds: 3));
    expect(attentionEventDelay(last: t0, now: t0.add(const Duration(seconds: 1)), running: true), const Duration(seconds: 4));
    expect(attentionEventDelay(last: t0, now: t0.add(const Duration(seconds: 9)), running: true), const Duration(seconds: 5));
  });
}
