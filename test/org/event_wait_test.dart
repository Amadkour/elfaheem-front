// The "poll only when no stream" helpers (lib/core/live/event_wait.dart): a matching event polls at once, the
// interval follows `connected`, dispose releases the bind. A fake bus and a fake stream handle — no network.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStream {
  final connected = ValueNotifier<bool>(false);
  int binds = 0;
  int releases = 0;
  late final handle = LiveStreamHandle(connected: connected, bind: () => binds++, release: () => releases++);
}

LiveEvents get _bus => LiveEvents.instance;

void main() {
  group('pure', () {
    test('liveEventMatches: name, kind and id (each only when given)', () {
      final e = LiveEvent(LiveEvents.jobUpdated, {'kind': 'export', 'id': 12, 'status': 'done'});
      expect(liveEventMatches(e, names: {LiveEvents.jobUpdated}), isTrue);
      expect(liveEventMatches(e, names: {LiveEvents.jobUpdated}, kind: 'export'), isTrue);
      expect(liveEventMatches(e, names: {LiveEvents.jobUpdated}, kind: 'export', id: '12'), isTrue);
      expect(liveEventMatches(e, names: {LiveEvents.jobUpdated}, kind: 'export', id: '13'), isFalse);
      expect(liveEventMatches(e, names: {LiveEvents.jobUpdated}, kind: 'caption'), isFalse);
      expect(liveEventMatches(e, names: {LiveEvents.lobbyUpdated}), isFalse);
    });

    test('pollInterval: the fallback only while connected, 4 x by default, never shorter than every', () {
      const every = Duration(seconds: 5);
      expect(pollInterval(every, connected: false), every);
      expect(pollInterval(every, connected: false, fallbackEvery: const Duration(seconds: 20)), every);
      expect(pollInterval(every, connected: true), const Duration(seconds: 20));
      expect(pollInterval(every, connected: true, fallbackEvery: const Duration(seconds: 30)), const Duration(seconds: 30));
      expect(pollInterval(every, connected: true, fallbackEvery: const Duration(seconds: 1)), every);
    });
  });

  group('EventOrPoll', () {
    late _FakeStream s;
    late int polls;
    late EventOrPoll w;

    EventOrPoll make({Duration every = const Duration(seconds: 5), Duration? fallback, String? id, void Function(LiveEvent)? onEvent}) =>
        EventOrPoll(
          kind: 'export',
          id: id,
          every: every,
          fallbackEvery: fallback,
          poll: () async => polls++,
          onEvent: onEvent,
          bus: _bus,
          stream: s.handle,
        );

    setUp(() {
      s = _FakeStream();
      polls = 0;
    });

    testWidgets('polls every [every] while the stream is down, [fallbackEvery] while it is connected', (tester) async {
      w = make(fallback: const Duration(seconds: 20))..start();
      expect(s.binds, 1);
      expect(polls, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(polls, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(polls, 2);
      s.connected.value = true;
      expect(w.interval, const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 19));
      expect(polls, 2, reason: 'the fallback cadence runs while connected');
      await tester.pump(const Duration(seconds: 1));
      expect(polls, 3);
      s.connected.value = false;
      await tester.pump(const Duration(seconds: 5));
      expect(polls, 4, reason: 'back to the fast cadence from the moment the stream dropped');
      w.dispose();
    });

    testWidgets('a matching event polls at once; another kind / id is ignored; the timer restarts after it', (tester) async {
      final seen = <LiveEvent>[];
      w = make(id: '12', onEvent: seen.add)..start();
      await tester.pump(const Duration(seconds: 2));
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'caption', 'id': '12'});
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'export', 'id': '13'});
      await tester.pump();
      expect(polls, 0);
      expect(seen, isEmpty);
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'export', 'id': '12', 'status': 'done'});
      await tester.pump();
      expect(polls, 1);
      expect(seen.single.status, 'done');
      await tester.pump(const Duration(seconds: 4));
      expect(polls, 1, reason: 'the next poll is booked from the event-triggered one');
      await tester.pump(const Duration(seconds: 1));
      expect(polls, 2);
      w.dispose();
    });

    testWidgets('an event during a poll in flight polls once more right after it', (tester) async {
      var release = Completer<void>();
      var n = 0;
      w = EventOrPoll(kind: 'export', every: const Duration(seconds: 5), bus: _bus, stream: s.handle, poll: () {
        n++;
        return release.future;
      })
        ..start(pollNow: true);
      expect(n, 1);
      expect(w.polling, isTrue);
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'export'});
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'export'});
      await tester.pump();
      expect(n, 1, reason: 'never two polls at once');
      final first = release;
      release = Completer<void>();
      first.complete();
      await tester.pump();
      expect(n, 2, reason: 'one catch-up poll for the events that came meanwhile');
      release.complete();
      await tester.pump();
      expect(n, 2);
      w.dispose();
    });

    testWidgets('stop / dispose cancels the timer, the subscription and releases the bind; start is idempotent', (tester) async {
      w = make()..start();
      w.start();
      expect(s.binds, 1);
      w.dispose();
      expect(s.releases, 1);
      expect(w.running, isFalse);
      await tester.pump(const Duration(seconds: 10));
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'export'});
      await tester.pump();
      expect(polls, 0);
      w.dispose();
      expect(s.releases, 1);
    });
  });

  group('JobWatch', () {
    late _FakeStream s;

    setUp(() => s = _FakeStream());

    testWidgets('next() ends at the interval, or at once on the job\'s event (with the event)', (tester) async {
      final j = JobWatch(kind: 'rag_query', id: '7', bus: _bus, stream: s.handle);
      expect(s.binds, 1);
      LiveEvent? got;
      var done = false;
      j.next(const Duration(seconds: 2)).then((e) {
        got = e;
        done = true;
      });
      await tester.pump(const Duration(seconds: 1));
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(done, isTrue);
      expect(got, isNull);

      done = false;
      j.next(const Duration(seconds: 2)).then((e) {
        got = e;
        done = true;
      });
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'rag_query', 'id': '8', 'stage': 'x'});
      await tester.pump();
      expect(done, isFalse, reason: 'another job');
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'rag_query', 'id': '7', 'stage': 'write'});
      await tester.pump();
      expect(done, isTrue);
      expect(got?.stage, 'write');
      await tester.pump(const Duration(seconds: 5));
      j.dispose();
      expect(s.releases, 1);
    });

    testWidgets('an event that arrived between two next() calls is returned by the next one', (tester) async {
      final j = JobWatch(kind: 'export', bus: _bus, stream: s.handle);
      _bus.emit(LiveEvents.jobUpdated, {'kind': 'export', 'status': 'ready'});
      await tester.pump();
      LiveEvent? got;
      j.next(const Duration(seconds: 30)).then((e) => got = e);
      await tester.pump();
      expect(got?.status, 'ready');
      j.dispose();
    });

    testWidgets('pace stretches while connected; a stream that drops during the wait ends it', (tester) async {
      final j = JobWatch(kind: 'export', bus: _bus, stream: s.handle);
      expect(j.pace(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20)), const Duration(seconds: 5));
      s.connected.value = true;
      expect(j.pace(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20)), const Duration(seconds: 20));
      var done = false;
      j.next(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20)).then((_) => done = true);
      await tester.pump(const Duration(seconds: 6));
      expect(done, isFalse, reason: 'the fallback interval while connected');
      s.connected.value = false;
      await tester.pump();
      expect(done, isTrue, reason: 'the stream dropped: poll now');
      j.dispose();
    });

    testWidgets('callback style: onEvent fires on the job\'s event; dispose ends a pending wait and releases', (tester) async {
      final seen = <String?>[];
      final j = JobWatch(names: {LiveEvents.joinDecided}, match: (e) => e.data['request_id'] == 'r1', onEvent: (e) => seen.add(e.status), bus: _bus, stream: s.handle);
      _bus.emit(LiveEvents.joinDecided, {'request_id': 'r2', 'status': 'admitted'});
      _bus.emit(LiveEvents.joinDecided, {'request_id': 'r1', 'status': 'admitted'});
      await tester.pump();
      expect(seen, ['admitted']);
      var done = false;
      j.next(const Duration(minutes: 1)).then((_) => done = true);
      j.dispose();
      await tester.pump();
      expect(done, isTrue);
      expect(s.releases, 1);
      _bus.emit(LiveEvents.joinDecided, {'request_id': 'r1', 'status': 'rejected'});
      await tester.pump();
      expect(seen, ['admitted'], reason: 'nothing after dispose');
    });
  });
}
