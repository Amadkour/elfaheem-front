// lib/core/in_flight.dart
//
// One request per key at a time: two widgets (or a widget and a page that closed) asking for the same thing while
// the first answer is still on its way share that answer instead of sending a second request (UX v3 phase 5).
//
//   final _flights = InFlight<int, AttentionFlow?>();
//   Future<AttentionFlow?> load(int orgId) => _flights.run(orgId, () => _fetch(orgId));
//
// Nothing is cached once the answer is in: the next call after it asks again.
library;

class InFlight<K, T> {
  final Map<K, Future<T>> _running = {};

  /// The running request of [key], else a new one from [start].
  Future<T> run(K key, Future<T> Function() start) {
    final now = _running[key];
    if (now != null) return now;
    final f = start();
    _running[key] = f;
    void done() {
      if (identical(_running[key], f)) _running.remove(key);
    }

    f.then<void>((_) => done(), onError: (Object _) => done());
    return f;
  }

  bool isRunning(K key) => _running.containsKey(key);
}
