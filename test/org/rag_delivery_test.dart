// How an assistant answer reached the app (lib/features/rag/rag_chat.dart, [RagDelivery]): `stream` when the
// live event woke the fetch that found it done, `poll` when a timed poll did, `mixed` when both played a part, and
// nothing to report for an answer done before any wake-up (the first response or the first fetch).
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no wake-up: nothing to report (done in the first response or the first fetch)', () {
    final d = RagDelivery();
    expect(d.path, isNull);
    expect(d.body(const Duration(seconds: 3)), isNull);
  });

  test('stream: every fetch woken by the live event, or by the slow poll while connected before it', () {
    final d = RagDelivery()..wake(byEvent: true, connected: true);
    expect(d.path, 'stream');
    final e = RagDelivery()
      ..wake(byEvent: false, connected: true) // the slow fallback poll while the stream is up: still not polling
      ..wake(byEvent: true, connected: true);
    expect(e.path, 'stream');
    expect(e.body(const Duration(milliseconds: 8400)), {'path': 'stream', 'ms': 8400});
  });

  test('poll: the timer found it, no event ever woke a fetch', () {
    final d = RagDelivery()
      ..wake(byEvent: false, connected: false)
      ..wake(byEvent: false, connected: false);
    expect(d.path, 'poll');
    // connected but silent: the stream did not deliver it either
    final e = RagDelivery()..wake(byEvent: false, connected: true);
    expect(e.path, 'poll');
    expect(e.body(const Duration(seconds: 12)), {'path': 'poll', 'ms': 12000});
  });

  test('mixed: the event finished it after polls with the stream down, or a poll finished it after an event', () {
    final a = RagDelivery()
      ..wake(byEvent: false, connected: false)
      ..wake(byEvent: true, connected: true);
    expect(a.path, 'mixed');
    final b = RagDelivery()
      ..wake(byEvent: true, connected: true) // a stage event
      ..wake(byEvent: false, connected: false); // the stream dropped, the poll got the answer
    expect(b.path, 'mixed');
  });

  test('the time to the final answer is never negative', () {
    final d = RagDelivery()..wake(byEvent: true, connected: true);
    expect(d.body(const Duration(milliseconds: -5)), {'path': 'stream', 'ms': 0});
  });
}
