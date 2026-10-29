// lib/features/shared/live/live_share_arbiter.dart
//
// One screen share at a time, and "Request to share" (live room, item 3 of the owner's device test 2026-10-29).
//
// Rules (Zoom / Teams / Meet):
//   • At most one share is live in a room.
//   • A host who starts sharing takes over: every other share stops (no prompt). Packet `stop` to `*`.
//   • A participant who may not share, or who taps Share while someone else shares, REQUESTS it: every host
//     gets "<name> wants to share their screen" (Accept / Reject). The first answer wins and closes the other
//     hosts' dialogs. Accept = the host's own share stops, every other presenter stops (the accept is a hand-over),
//     and the requester's share starts by itself (the OS picker may still ask on web / Android). A request nobody
//     answers lapses after [kLiveShareRequestTtl].
//   • A host stops anyone's share at any time (`stop` to that identity); a share the host allowed only for this
//     request (a temporary grant) is taken back when that share ends.
//
// Signalling: reliable LiveKit data packets on topic [kLiveShareTopic], broadcast (a requester cannot tell every
// co-host apart), `{"type":"share","signal":…,"id":…,"to":…,"name":…}`. The SENDER is always LiveKit's
// participant (never an identity read from the payload), and answers / stops count only from a host as the
// SERVER set them up ([liveIsServerHost]). The permission itself is never the client's to give: a host's Accept
// first asks the server for `screen_share` (`POST …/permissions`, live_controls_api.dart) when the requester has
// none, and LiveKit refuses a publish the token does not allow.
//
// [LiveShareArbiter] is the pure state machine (no LiveKit, no widgets): the room feeds it packets
// ([receive]), who presents now ([setPresenters]) and the clock ([tick]); it sends packets through [send] and
// tells the room what to do through [events]. [liveShareTapDecision] decides what the Share button does,
// [liveSharesToStop] which shares must end so one remains (run by the lead host, [liveLeadHost]).
// Unit-tested in test/org/live_share_arbiter_test.dart; the widgets are in live_share_widgets.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'live_controls_api.dart' show liveIdentityIsHost, liveIsGuestIdentity;
import 'live_room.dart' show LiveRoomKind;

/// The data topic of the share packets.
const String kLiveShareTopic = 'share';

/// Kill switch of "Request to share" (the one-share rule itself always holds).
const String kLiveShareRequestsFeatureKey = 'live.share_requests';

/// How long a request waits for a host.
const Duration kLiveShareRequestTtl = Duration(seconds: 30);

/// The requester waits a little longer than the hosts: an answer sent at 29.9 s still arrives.
const Duration kLiveShareRequestGrace = Duration(seconds: 3);

/// How long an accepted requester has to start (options sheet, the OS picker) before the approval lapses.
const Duration kLiveShareApprovalTtl = Duration(seconds: 90);

const String _kType = 'share';

/// `to` of a takeover: every presenter but the sender.
const String kLiveShareEveryone = '*';

// ─────────────────────────────────────────────────────────────────────────────
// Who is a host (as the server set it up)
// ─────────────────────────────────────────────────────────────────────────────

/// A host as the SERVER minted them: a course's `teacher_*`, or a member whose permission carries every publish
/// source — the server gives a host `room_admin` and no source list (`can_publish_sources: null`) and everyone else
/// an explicit list (../back/services/LiveKit_service.py `_make_access_token`, `participant_permission`), so an
/// empty list with publishing on is a host. Guests never are. [sources] are the SDK's names (any spelling).
bool liveIsServerHost({
  required String identity,
  required LiveRoomKind kind,
  required bool canPublish,
  required Iterable<dynamic> sources,
}) {
  if (identity.isEmpty || liveIsGuestIdentity(identity)) return false;
  if (liveIdentityIsHost(identity, kind)) return true;
  return canPublish && sources.isEmpty;
}

/// The host that enforces "one share" when several are present: the smallest identity (every host computes the
/// same one, so exactly one sends the stops). Null when there is none.
String? liveLeadHost(Iterable<String> hosts) {
  String? best;
  for (final h in hosts) {
    if (h.isEmpty) continue;
    if (best == null || h.compareTo(best) < 0) best = h;
  }
  return best;
}

// ─────────────────────────────────────────────────────────────────────────────
// Packets
// ─────────────────────────────────────────────────────────────────────────────

enum LiveShareSignal { request, cancel, accept, reject, stop }

class LiveSharePacket {
  const LiveSharePacket({required this.signal, this.id = '', this.to = '', this.name = ''});

  final LiveShareSignal signal;

  /// The request (request / cancel / accept / reject); empty for a stop.
  final String id;

  /// The requester (accept / reject), the presenter asked to stop, or [kLiveShareEveryone].
  final String to;

  /// The sender's display name (what the other side shows: "Ms Sara accepted").
  final String name;

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'type': _kType,
        'signal': signal.name,
        if (id.isNotEmpty) 'id': id,
        if (to.isNotEmpty) 'to': to,
        if (name.isNotEmpty) 'name': name,
      })));

  /// Null for anything that is not a well-formed share packet.
  static LiveSharePacket? decode(List<int> data) {
    try {
      final j = jsonDecode(utf8.decode(data));
      if (j is! Map || j['type'] != _kType) return null;
      final signal = LiveShareSignal.values.where((s) => s.name == j['signal']).firstOrNull;
      if (signal == null) return null;
      String str(String k) {
        final v = j[k];
        final s = v is String ? v.trim() : '';
        return s.length > 128 ? s.substring(0, 128) : s;
      }

      final p = LiveSharePacket(signal: signal, id: str('id'), to: str('to'), name: str('name'));
      final needsId = signal != LiveShareSignal.stop;
      final needsTo = signal == LiveShareSignal.accept || signal == LiveShareSignal.reject || signal == LiveShareSignal.stop;
      if (needsId && p.id.isEmpty) return null;
      if (needsTo && p.to.isEmpty) return null;
      return p;
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Requests and events
// ─────────────────────────────────────────────────────────────────────────────

/// One request as a host sees it.
class LiveShareRequest {
  const LiveShareRequest({required this.id, required this.identity, required this.name, required this.at, this.imageUrl});

  final String id;
  final String identity;
  final String name;
  final String? imageUrl;
  final DateTime at;

  DateTime get expiresAt => at.add(kLiveShareRequestTtl);

  /// Time left, never negative.
  Duration remaining(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

sealed class LiveShareEvent {
  const LiveShareEvent();
}

/// Host: a new request (open the dialog).
class LiveShareRequested extends LiveShareEvent {
  const LiveShareRequested(this.request);
  final LiveShareRequest request;
}

/// Host: a request was answered — by this host ([byMe]) or another one ([byName]).
class LiveShareAnswered extends LiveShareEvent {
  const LiveShareAnswered(this.request, {required this.accepted, required this.byMe, this.byName = ''});
  final LiveShareRequest request;
  final bool accepted;
  final bool byMe;
  final String byName;
}

/// Host: nobody answered in time.
class LiveShareRequestExpired extends LiveShareEvent {
  const LiveShareRequestExpired(this.request);
  final LiveShareRequest request;
}

/// Host: the requester withdrew — before an answer, or after an accept they could not start ([wasAccepted]).
class LiveShareWithdrawn extends LiveShareEvent {
  const LiveShareWithdrawn(this.identity, {required this.wasAccepted});
  final String identity;
  final bool wasAccepted;
}

/// Requester: the host said yes — start the share.
class LiveShareMyRequestAccepted extends LiveShareEvent {
  const LiveShareMyRequestAccepted(this.id, {this.byName = ''});
  final String id;
  final String byName;
}

/// Requester: the host said no.
class LiveShareMyRequestRejected extends LiveShareEvent {
  const LiveShareMyRequestRejected({this.byName = ''});
  final String byName;
}

/// Requester: no host answered.
class LiveShareMyRequestExpired extends LiveShareEvent {
  const LiveShareMyRequestExpired();
}

/// Presenter (anyone who shares now): stop your share — a host stopped it, took over, or handed over to [keep].
class LiveShareStopAsked extends LiveShareEvent {
  const LiveShareStopAsked({this.byName = '', this.keep, this.takeover = false});
  final String byName;

  /// Who presents next (a takeover: the host; a hand-over: the accepted requester); null = a plain stop.
  final String? keep;

  /// The host started sharing themselves.
  final bool takeover;
}

/// The granting host: a share it allowed only for one request is over (ended, or never started in time) —
/// take the permission back.
class LiveShareGrantEnded extends LiveShareEvent {
  const LiveShareGrantEnded(this.identity);
  final String identity;
}

// ─────────────────────────────────────────────────────────────────────────────
// What the Share button does
// ─────────────────────────────────────────────────────────────────────────────

enum LiveShareTap {
  /// Start sharing (a host: after the takeover).
  start,

  /// Stop my share.
  stop,

  /// Ask the hosts.
  request,

  /// My request is pending: withdraw it.
  cancelRequest,

  /// Nobody here can answer a request (no host in the room).
  noHost,

  /// No share, no request (a guest, requests switched off and no permission).
  hidden,
}

/// The Share button's look: share / stop / request / requested — or nothing.
enum LiveShareButton { share, stop, request, requested, hidden }

/// What a tap on Share does. [othersSharing]: someone else presents now; [mayShare]: the server lets me;
/// [requestsOn]: `live.share_requests` is on.
LiveShareTap liveShareTapDecision({
  required bool isHost,
  required bool sharing,
  required bool mayShare,
  required bool othersSharing,
  required bool requestPending,
  required bool hostPresent,
  bool isGuest = false,
  bool requestsOn = true,
}) {
  if (sharing) return LiveShareTap.stop;
  if (isHost) return LiveShareTap.start;
  if (requestPending) return LiveShareTap.cancelRequest;
  if (mayShare && !othersSharing) return LiveShareTap.start;
  if (isGuest || !requestsOn) return mayShare ? LiveShareTap.start : LiveShareTap.hidden;
  if (!hostPresent) return LiveShareTap.noHost;
  return LiveShareTap.request;
}

/// The button for the same facts (a host always gets Share / Stop).
LiveShareButton liveShareButtonFor({
  required bool isHost,
  required bool sharing,
  required bool mayShare,
  required bool othersSharing,
  required bool requestPending,
  bool isGuest = false,
  bool requestsOn = true,
}) {
  if (sharing) return LiveShareButton.stop;
  if (isHost) return LiveShareButton.share;
  if (requestPending) return LiveShareButton.requested;
  if (mayShare && !othersSharing) return LiveShareButton.share;
  if (isGuest || !requestsOn) return mayShare ? LiveShareButton.share : LiveShareButton.hidden;
  return LiveShareButton.request;
}

// ─────────────────────────────────────────────────────────────────────────────
// Which shares must stop
// ─────────────────────────────────────────────────────────────────────────────

/// One presenter as the enforcement sees them.
class LiveSharer {
  const LiveSharer({required this.identity, required this.since, this.isHost = false, this.approvedAt});

  final String identity;

  /// When this room first saw the share.
  final DateTime since;
  final bool isHost;

  /// A host accepted this presenter's request (newest wins).
  final DateTime? approvedAt;
}

/// The identities that must stop so that one share remains, in the input order. Hosts and approved presenters
/// hold a claim — a host from when its share started (a takeover), an approved presenter from when a host
/// accepted them — and the newest claim wins. Without any claim, whoever started first keeps it.
List<String> liveSharesToStop(List<LiveSharer> sharers) {
  if (sharers.length < 2) return const [];
  DateTime? claim(LiveSharer s) => s.isHost ? s.since : s.approvedAt;
  final claimed = sharers.where((s) => claim(s) != null).toList();
  final LiveSharer winner = claimed.isNotEmpty
      ? claimed.reduce((a, b) => claim(b)!.isAfter(claim(a)!) ? b : a)
      : sharers.reduce((a, b) => b.since.isBefore(a.since) ? b : a);
  return [for (final s in sharers) if (s.identity != winner.identity) s.identity];
}

// ─────────────────────────────────────────────────────────────────────────────
// The state machine
// ─────────────────────────────────────────────────────────────────────────────

typedef LiveShareSend = Future<void> Function(Uint8List bytes);

class LiveShareArbiter extends ChangeNotifier {
  LiveShareArbiter({
    required this.localIdentity,
    required this.isHost,
    required this.send,
    DateTime Function()? now,
    String Function()? newId,
    this.autoTick = true,
  })  : _now = now ?? DateTime.now,
        _newId = newId ?? _defaultId;

  /// This participant's identity (read every time: it is known once connected).
  final String Function() localIdentity;

  /// This participant hosts the room (the room's own role: `widget.host`).
  final bool Function() isHost;

  /// Publishes a packet (reliable, topic [kLiveShareTopic], to everyone).
  final LiveShareSend send;

  /// A periodic timer runs [tick] while anything can expire (tests pass false and call [tick]).
  final bool autoTick;

  final DateTime Function() _now;
  final String Function() _newId;

  static int _seq = 0;
  static String _defaultId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_seq++).toRadixString(36)}';

  final _events = StreamController<LiveShareEvent>.broadcast(sync: true);
  Stream<LiveShareEvent> get events => _events.stream;

  bool _disposed = false;
  Timer? _timer;

  // ── requester ──────────────────────────────────────────────────────────────
  String? _pendingId;
  DateTime? _pendingAt;
  String? _acceptedId;
  bool _everAccepted = false;

  /// My request waits for a host.
  bool get requestPending => _pendingId != null;
  String? get pendingId => _pendingId;

  /// The request a host accepted last (withdrawn when the share could not start).
  String? get acceptedId => _acceptedId;

  /// A host accepted one of my requests in this room (the room then keeps its own notices for the share).
  bool get everAccepted => _everAccepted;

  /// Time left on my request.
  Duration get pendingRemaining {
    final at = _pendingAt;
    if (at == null) return Duration.zero;
    final d = at.add(kLiveShareRequestTtl).difference(_now());
    return d.isNegative ? Duration.zero : d;
  }

  // ── host ───────────────────────────────────────────────────────────────────
  final List<LiveShareRequest> _requests = [];
  final Set<String> _answering = {};

  /// Pending requests, oldest first.
  List<LiveShareRequest> get requests => List.unmodifiable(_requests);

  /// The request the dialog shows.
  LiveShareRequest? get current => _requests.firstOrNull;
  int get pendingCount => _requests.length;

  /// This host is answering [id] (the dialog's buttons show busy).
  bool answering(String id) => _answering.contains(id);

  // ── every room ─────────────────────────────────────────────────────────────
  final Map<String, DateTime> _approvals = {};
  final Set<String> _approvalsUsed = {};
  final Set<String> _grants = {};
  final Map<String, DateTime> _presenters = {};

  /// Who presents now, with when this room first saw it.
  Map<String, DateTime> get presenters => Map.unmodifiable(_presenters);

  bool isPresenting(String identity) => _presenters.containsKey(identity);

  /// Someone other than me presents.
  bool get othersSharing => _presenters.keys.any((id) => id != localIdentity());

  DateTime? approvedAt(String identity) => _approvals[identity];

  /// The shares this host allowed for one request only.
  Set<String> get grants => Set.unmodifiable(_grants);

  void _emit(LiveShareEvent e) {
    if (!_disposed) _events.add(e);
  }

  void _changed() {
    _syncTimer();
    if (!_disposed) notifyListeners();
  }

  Future<void> _send(LiveSharePacket p) async {
    try {
      await send(p.encode());
    } catch (_) {
      // A lost packet is like a lost answer: the request lapses on its own.
    }
  }

  // ── requester API ──────────────────────────────────────────────────────────

  /// Asks the hosts; false when a request is already pending.
  bool request({required String name}) {
    if (_pendingId != null) return false;
    _pendingId = _newId();
    _pendingAt = _now();
    unawaited(_send(LiveSharePacket(signal: LiveShareSignal.request, id: _pendingId!, name: name)));
    _changed();
    return true;
  }

  /// Withdraws my pending request.
  void cancelRequest() {
    final id = _pendingId;
    if (id == null) return;
    _pendingId = null;
    _pendingAt = null;
    unawaited(_send(LiveSharePacket(signal: LiveShareSignal.cancel, id: id)));
    _changed();
  }

  /// The share a host accepted could not start (the picker was closed): the hosts take the grant back.
  void withdrawAccepted() {
    final id = _acceptedId;
    if (id == null) return;
    _acceptedId = null;
    unawaited(_send(LiveSharePacket(signal: LiveShareSignal.cancel, id: id)));
    _changed();
  }

  // ── host API ───────────────────────────────────────────────────────────────

  /// Marks [id] as being answered by this host (false when it is gone or already in flight).
  bool beginAnswer(String id) {
    if (!_requests.any((r) => r.id == id) || _answering.contains(id)) return false;
    _answering.add(id);
    _changed();
    return true;
  }

  /// Ends a [beginAnswer] that did not answer (the permission call failed): the request stays.
  void abortAnswer(String id) {
    if (_answering.remove(id)) _changed();
  }

  /// Answers [id] for everyone (the first answer wins). Null when the request is gone (another host answered, it
  /// expired or was withdrawn) — nothing is sent then.
  LiveShareRequest? answer(String id, {required bool accept, required String name}) {
    _answering.remove(id);
    final r = _requests.where((x) => x.id == id).firstOrNull;
    if (r == null) {
      _changed();
      return null;
    }
    _requests.remove(r);
    if (accept) _approve(r.identity);
    unawaited(_send(LiveSharePacket(
        signal: accept ? LiveShareSignal.accept : LiveShareSignal.reject, id: id, to: r.identity, name: name)));
    _emit(LiveShareAnswered(r, accepted: accept, byMe: true, byName: name));
    _changed();
    return r;
  }

  /// This host starts sharing: everyone else stops (no prompt); approvals end.
  void takeOver({required String name}) {
    _approvals.clear();
    _approvalsUsed.clear();
    unawaited(_send(LiveSharePacket(signal: LiveShareSignal.stop, to: kLiveShareEveryone, name: name)));
    _changed();
  }

  /// Asks [identity] to stop sharing (a host's Stop share; the enforcement).
  void askToStop(String identity, {required String name}) {
    if (identity.isEmpty) return;
    _dropApproval(identity, revoke: false);
    unawaited(_send(LiveSharePacket(signal: LiveShareSignal.stop, to: identity, name: name)));
    _changed();
  }

  /// This host allowed [identity] to share for one request: the grant ends with that share.
  void noteGrant(String identity) {
    if (_grants.add(identity)) _changed();
  }

  /// Forgets a temporary grant; true when there was one (the caller takes the permission back).
  bool takeGrant(String identity) {
    final had = _grants.remove(identity);
    if (had) _changed();
    return had;
  }

  // ── inputs ─────────────────────────────────────────────────────────────────

  /// Takes a packet. [sender]: LiveKit's sending participant; [senderIsHost]: [liveIsServerHost] for them;
  /// [senderName] / [senderImageUrl]: what the room knows of them. True when it was a share packet.
  bool receive(List<int> data,
      {required String? sender, required bool senderIsHost, String? senderName, String? senderImageUrl}) {
    final p = LiveSharePacket.decode(data);
    if (p == null) return false;
    final from = sender ?? '';
    if (from.isEmpty || from == localIdentity() || liveIsGuestIdentity(from)) return true;
    final me = localIdentity();
    switch (p.signal) {
      case LiveShareSignal.request:
        if (!isHost() || senderIsHost) return true;
        _requests.removeWhere((r) => r.identity == from);
        final name = (senderName ?? '').trim().isNotEmpty ? senderName!.trim() : (p.name.isNotEmpty ? p.name : from);
        final r = LiveShareRequest(id: p.id, identity: from, name: name, imageUrl: senderImageUrl, at: _now());
        _requests.add(r);
        _emit(LiveShareRequested(r));
        _changed();
      case LiveShareSignal.cancel:
        final before = _requests.length;
        _requests.removeWhere((r) => r.identity == from && r.id == p.id);
        final wasRequest = _requests.length != before;
        final wasAccepted = _approvals.containsKey(from) && !_approvalsUsed.contains(from);
        if (wasAccepted) _dropApproval(from, revoke: true);
        if (wasRequest || wasAccepted) {
          if (isHost()) _emit(LiveShareWithdrawn(from, wasAccepted: wasAccepted));
          _changed();
        }
      case LiveShareSignal.accept || LiveShareSignal.reject:
        if (!senderIsHost) return true;
        final accept = p.signal == LiveShareSignal.accept;
        if (accept) _approve(p.to);
        final r = _requests.where((x) => x.id == p.id).firstOrNull;
        if (r != null) {
          _requests.remove(r);
          _answering.remove(r.id);
          _emit(LiveShareAnswered(r, accepted: accept, byMe: false, byName: p.name));
        }
        if (p.to == me && p.id == _pendingId) {
          _pendingId = null;
          _pendingAt = null;
          if (accept) {
            _acceptedId = p.id;
            _everAccepted = true;
            _emit(LiveShareMyRequestAccepted(p.id, byName: p.name));
          } else {
            _emit(LiveShareMyRequestRejected(byName: p.name));
          }
        } else if (accept && p.to == me) {
          // An accept for a request I no longer wait for (it lapsed here first): the hosts take the grant back.
          unawaited(_send(LiveSharePacket(signal: LiveShareSignal.cancel, id: p.id)));
        } else if (accept && p.to != me && _presenters.containsKey(me)) {
          // A hand-over: the accepted requester presents next, my share ends.
          _emit(LiveShareStopAsked(byName: p.name, keep: p.to));
        }
        _changed();
      case LiveShareSignal.stop:
        if (!senderIsHost) return true;
        if (p.to == kLiveShareEveryone) {
          _approvals.clear();
          _approvalsUsed.clear();
          if (_presenters.containsKey(me)) _emit(LiveShareStopAsked(byName: p.name, keep: from, takeover: true));
          _changed();
        } else if (p.to == me) {
          _acceptedId = null;
          _approvals.remove(me);
          _emit(LiveShareStopAsked(byName: p.name));
          _changed();
        } else {
          _dropApproval(p.to, revoke: false);
          _changed();
        }
    }
    return true;
  }

  /// Who presents now (the room's re-layout). Approved presenters who stopped end their approval; a temporary
  /// grant ends with it ([LiveShareGrantEnded]).
  void setPresenters(Iterable<String> identities) {
    final now = _now();
    final next = identities.where((i) => i.isNotEmpty).toSet();
    var changed = false;
    for (final gone in _presenters.keys.where((k) => !next.contains(k)).toList()) {
      _presenters.remove(gone);
      changed = true;
      if (_approvalsUsed.contains(gone) || _grants.contains(gone)) _dropApproval(gone, revoke: true);
    }
    for (final id in next) {
      if (_presenters.containsKey(id)) continue;
      _presenters[id] = now;
      changed = true;
      if (_approvals.containsKey(id)) _approvalsUsed.add(id);
      if (id == localIdentity()) _acceptedId = null; // my accepted share started
    }
    if (changed) _changed();
  }

  /// A participant left: their request, approval and grant go.
  void participantLeft(String identity) {
    final before = _requests.length;
    _requests.removeWhere((r) => r.identity == identity);
    final had = before != _requests.length || _approvals.containsKey(identity) || _grants.contains(identity) ||
        _presenters.containsKey(identity);
    _approvals.remove(identity);
    _approvalsUsed.remove(identity);
    _grants.remove(identity);
    _presenters.remove(identity);
    if (had) _changed();
  }

  /// The shares that must stop so one remains (the lead host's enforcement). [hostCheck]: is that identity a host.
  List<String> sharesToStop(bool Function(String identity) hostCheck) => liveSharesToStop([
        for (final e in _presenters.entries)
          LiveSharer(identity: e.key, since: e.value, isHost: hostCheck(e.key), approvedAt: _approvals[e.key]),
      ]);

  /// The order shares go on the stage: the one that wins first, then the newest.
  List<String> stageOrder(bool Function(String identity) hostCheck) {
    final stops = sharesToStop(hostCheck).toSet();
    final ids = _presenters.keys.toList()
      ..sort((a, b) {
        final sa = stops.contains(a), sb = stops.contains(b);
        if (sa != sb) return sa ? 1 : -1;
        return _presenters[b]!.compareTo(_presenters[a]!);
      });
    return ids;
  }

  /// Expires requests (both sides) and unused approvals. The timer calls it every second while needed.
  void tick() {
    final now = _now();
    var changed = false;
    for (final r in _requests.where((r) => !now.isBefore(r.expiresAt)).toList()) {
      _requests.remove(r);
      _answering.remove(r.id);
      _emit(LiveShareRequestExpired(r));
      changed = true;
    }
    final at = _pendingAt;
    if (_pendingId != null && at != null && !now.isBefore(at.add(kLiveShareRequestTtl + kLiveShareRequestGrace))) {
      _pendingId = null;
      _pendingAt = null;
      _emit(const LiveShareMyRequestExpired());
      changed = true;
    }
    for (final e in _approvals.entries.toList()) {
      if (_approvalsUsed.contains(e.key)) continue;
      if (!now.isBefore(e.value.add(kLiveShareApprovalTtl))) {
        _dropApproval(e.key, revoke: true);
        changed = true;
      }
    }
    if (changed) _changed();
  }

  void _approve(String identity) {
    if (identity.isEmpty) return;
    _approvals[identity] = _now();
    _approvalsUsed.remove(identity);
    if (_presenters.containsKey(identity)) _approvalsUsed.add(identity);
  }

  void _dropApproval(String identity, {required bool revoke}) {
    _approvals.remove(identity);
    _approvalsUsed.remove(identity);
    if (revoke && _grants.remove(identity)) _emit(LiveShareGrantEnded(identity));
  }

  bool get _needsTick => _requests.isNotEmpty || _pendingId != null || _approvals.keys.any((k) => !_approvalsUsed.contains(k));

  void _syncTimer() {
    if (!autoTick || _disposed) return;
    if (_needsTick) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_events.close());
    super.dispose();
  }
}
