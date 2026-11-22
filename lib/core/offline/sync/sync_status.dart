// lib/core/offline/sync/sync_status.dart — ONE answer to "is what I did offline on the server yet?" (D-1351).
//
// offline | online | syncing, plus how many writes still wait on this device. The outbox reports its own count;
// the older queues (offline attendance, offline exam sittings) keep their own code and only REPORT their counts
// here through [SyncStatus.report]. SyncStatusChip draws it.
library;

import 'package:flutter/foundation.dart';

import '../app_connectivity.dart';

enum SyncPhase { offline, online, syncing }

@immutable
class SyncSnapshot {
  const SyncSnapshot({required this.phase, required this.pending, this.attention = 0});

  static const idle = SyncSnapshot(phase: SyncPhase.online, pending: 0);

  final SyncPhase phase;

  /// Writes still on this device (the outbox and every reported queue).
  final int pending;

  /// Writes that failed again and again (parked): tried only on app start and on a manual "Sync now".
  final int attention;

  /// Nothing to tell: online and nothing waiting (the chip draws nothing).
  bool get quiet => phase == SyncPhase.online && pending == 0 && attention == 0;

  @override
  bool operator ==(Object other) =>
      other is SyncSnapshot && other.phase == phase && other.pending == pending && other.attention == attention;

  @override
  int get hashCode => Object.hash(phase, pending, attention);

  @override
  String toString() => 'SyncSnapshot(${phase.name}, $pending${attention == 0 ? '' : ', $attention parked'})';
}

class SyncStatus extends ValueNotifier<SyncSnapshot> {
  SyncStatus() : super(SyncSnapshot.idle);

  static final SyncStatus instance = SyncStatus();

  /// The queue names [report] knows today; any other name works as well.
  static const outbox = 'outbox', attendance = 'attendance', exams = 'exams';

  /// The outbox's parked rows: counted apart from [SyncSnapshot.pending] ("needs attention").
  static const parked = 'outbox.parked';

  bool _online = true;
  bool _syncing = false;
  final _counts = <String, int>{};
  ValueListenable<bool>? _source;

  bool get online => _online;
  bool get syncing => _syncing;

  /// Follows [online] (the app's [AppConnectivity] unless given). Idempotent.
  void bindOnline([ValueListenable<bool>? online]) {
    final src = online ?? AppConnectivity.instance.online;
    if (identical(src, _source)) return;
    _source?.removeListener(_follow);
    _source = src..addListener(_follow);
    _follow();
  }

  void _follow() => setOnline(_source?.value ?? true);

  void setOnline(bool v) {
    _online = v;
    _publish();
  }

  void setSyncing(bool v) {
    _syncing = v;
    _publish();
  }

  /// [queue] has [count] writes waiting on this device.
  void report(String queue, int count) {
    _counts[queue] = count < 0 ? 0 : count;
    _publish();
  }

  /// The count [queue] reported last (0 when it never did).
  int countOf(String queue) => _counts[queue] ?? 0;

  /// Forgets every count (sign-out) and the syncing flag.
  void reset() {
    _counts.clear();
    _syncing = false;
    _publish();
  }

  void _publish() {
    var pending = 0;
    _counts.forEach((k, n) {
      if (k != parked) pending += n;
    });
    final phase = !_online ? SyncPhase.offline : (_syncing ? SyncPhase.syncing : SyncPhase.online);
    value = SyncSnapshot(phase: phase, pending: pending, attention: _counts[parked] ?? 0);
  }
}
