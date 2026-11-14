// lib/core/models_hub/model_downloads.dart
//
// The model hub's downloads as the app sees them (D-152, requirement 7.7): ONE ChangeNotifier the floating download
// bar (lib/features/admin/models/model_download_bar.dart) and the AI Models page both read.
//
// Fed by the `model_download` live event — the whole Download row, at most every second while it runs — applied in
// place, so the bar moves without a request. `GET /api/v1/models/downloads` is the fallback, through EventOrPoll
// (never a bare timer): every 2 s while a download is queued / running / paused and the stream is down (10 s while it
// is up), every minute when nothing runs (5 min with the stream), and at once when an event names a download the list
// does not know or a status change (paused, done, failed, …) — or `model_changed` says an activation started one.
//
// Only the host watches, and only for a super admin (the hub answers 403 to anyone else; a 401 / 403 stops it).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/live_events.dart';
import '../live/event_wait.dart';
import 'models_hub_api.dart';

class ModelDownloads extends ChangeNotifier {
  ModelDownloads({ModelsHubApi api = const ModelsHubApi(), LiveEvents? bus, LiveStreamHandle Function()? stream})
      : _api = api,
        _bus = bus,
        _stream = stream;

  /// The app's one instance (tests may swap it before pumping the host).
  static ModelDownloads instance = ModelDownloads();

  final ModelsHubApi _api;
  final LiveEvents? _bus;
  final LiveStreamHandle Function()? _stream;

  static const fastEvery = Duration(seconds: 2);
  static const fastFallback = Duration(seconds: 10);
  static const idleEvery = Duration(minutes: 1);
  static const idleFallback = Duration(minutes: 5);

  List<HubDownload> _rows = const [];
  bool _watching = false;
  bool _minimised = false;
  bool _fast = false;
  bool _stopped = false; // 401 / 403: not a super admin (any more)
  EventOrPoll? _poller;
  final _ended = StreamController<HubDownload>.broadcast();

  /// The downloads the hub listed last (newest first), with the live events applied.
  List<HubDownload> get rows => _rows;

  /// Queued, running or paused — running ones first.
  List<HubDownload> get live {
    final l = _rows.where((d) => d.live).toList();
    l.sort((a, b) => (a.paused ? 1 : 0) - (b.paused ? 1 : 0));
    return l;
  }

  /// The one the bar shows.
  HubDownload? get current {
    final l = live;
    return l.isEmpty ? null : l.first;
  }

  bool get watching => _watching;

  /// The bar is drawn: watching, and a download is queued / running / paused.
  bool get visible => _watching && !_stopped && live.isNotEmpty;

  bool get minimised => _minimised;
  set minimised(bool v) {
    if (v == _minimised) return;
    _minimised = v;
    notifyListeners();
  }

  /// The live download of a model, if any.
  HubDownload? forModel(int modelId) {
    for (final d in _rows) {
      if (d.modelId == modelId && d.live) return d;
    }
    return null;
  }

  /// A download that stopped being live while watched (done, failed, cancelled): the host says so, the page reloads.
  Stream<HubDownload> get ended => _ended.stream;

  /// The poller's cadence now (tests).
  @visibleForTesting
  bool get fast => _fast;

  /// Starts following the downloads (idempotent): the first fetch at once.
  void watch() {
    if (_watching) return;
    _watching = true;
    _stopped = false;
    _restart(fast: false, pollNow: true);
  }

  /// Stops following them and forgets the rows (signed out, not a super admin, view-as).
  void unwatch() {
    if (!_watching) return;
    _watching = false;
    _poller?.dispose();
    _poller = null;
    _rows = const [];
    _minimised = false;
    notifyListeners();
  }

  /// Fetch now (after an action on the page, or to pick up a download the page just started).
  Future<void> refresh() async {
    if (!_watching || _stopped) return;
    try {
      _set(await _api.downloads(limit: 20));
    } catch (e) {
      final f = HubFailure.from(e);
      if (f.status == 401 || f.status == 403) {
        _stopped = true;
        _poller?.dispose();
        _poller = null;
        _rows = const [];
        notifyListeners();
      }
      // anything else (the hub restarting, no network): the next poll tries again
    }
  }

  /// A row the page got back from an action (start / pause / resume / cancel): shown at once, then followed.
  void track(HubDownload? d) {
    if (d == null) return;
    _merge(d);
    if (_watching) _poller?.poke();
  }

  Future<HubDownload?> pause(HubDownload d) => _action(d, 'pause');
  Future<HubDownload?> resume(HubDownload d) => _action(d, 'resume');
  Future<HubDownload?> cancel(HubDownload d) => _action(d, 'cancel');

  Future<HubDownload?> _action(HubDownload d, String action) async {
    final r = await _api.downloadAction(d.id, action);
    track(r);
    return r;
  }

  void _restart({required bool fast, bool pollNow = false}) {
    _poller?.dispose();
    _fast = fast;
    _poller = EventOrPoll(
      poll: refresh,
      every: fast ? fastEvery : idleEvery,
      fallbackEvery: fast ? fastFallback : idleFallback,
      names: const {LiveEvents.modelDownload, LiveEvents.modelChanged},
      match: _absorb,
      bus: _bus,
      stream: _stream?.call(),
    )..start(pollNow: pollNow);
  }

  /// Applies a `model_download` event in place; true when it calls for a fetch (a download the list does not know, a
  /// status change, or an activation that started one).
  bool _absorb(LiveEvent e) {
    if (e.type == LiveEvents.modelChanged) return e.action == 'downloading';
    final d = HubDownload.fromJson(e.data);
    if (d == null) return false;
    final before = _byId(d.id);
    _merge(d);
    return before == null || before.status != d.status;
  }

  HubDownload? _byId(int id) {
    for (final d in _rows) {
      if (d.id == id) return d;
    }
    return null;
  }

  void _merge(HubDownload d) {
    final i = _rows.indexWhere((x) => x.id == d.id);
    final before = i < 0 ? null : _rows[i];
    _rows = i < 0 ? [d, ..._rows] : [for (final x in _rows) x.id == d.id ? d : x];
    if (before != null && before.live && !d.live) _ended.add(d);
    _changed();
  }

  void _set(List<HubDownload> list) {
    final was = {for (final d in _rows) d.id: d};
    _rows = list;
    for (final d in list) {
      final b = was[d.id];
      if (b != null && b.live && !d.live) _ended.add(d);
    }
    _changed();
  }

  void _changed() {
    final needFast = live.isNotEmpty;
    if (live.isEmpty) _minimised = false;
    notifyListeners();
    // the cadence follows what runs; switched after the current poll / event handler returns, never inside it
    if (_watching && !_stopped && needFast != _fast) {
      scheduleMicrotask(() {
        if (_watching && !_stopped && needFast != _fast) _restart(fast: needFast);
      });
    }
  }

  @override
  void dispose() {
    _poller?.dispose();
    _ended.close();
    super.dispose();
  }
}
