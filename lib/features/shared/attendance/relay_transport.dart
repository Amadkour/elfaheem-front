/// features/attendance/relay_transport.dart
///
/// Short-range link between an OFFLINE student and an ONLINE classmate (the "relay"),
/// built on Google Nearby Connections (BLE + Wi-Fi Direct, Android, works with no internet).
///
/// IMPORTANT — this link is NOT trusted and NOT a proof of presence:
///   • the code typed by the student proves they saw the teacher's screen in the hall;
///   • the HMAC signature proves the request is from this student's app;
///   • the server's signed result proves the verdict is real.
/// The relay only carries bytes. Even a hostile relay can at worst drop the message.
///
/// Wire format (UTF-8 JSON, one message per payload):
///   client -> relay  {"t":"hello","session_id":12}
///   relay  -> client {"t":"window", ...OpenWindow}         | {"t":"error","code":..,"message":..}
///   client -> mate   {"t":"witness","att":7,"student_id":42}
///   mate   -> client {"t":"witness","user_id":9,"ts":..,"sig":..}   (mate's OWN signature)
///   client -> relay  {"t":"submit", ...PendingAttendance.toSubmitBody()}
///   relay  -> client {"t":"result", ...AttendanceResult}   | {"t":"error","code":..,"message":..}
///
/// NOTE (nearby_connections plugin): it keeps ONE global payload callback and ONE global set of
/// connection callbacks. Registering a second handler (e.g. advertising + discovering on the
/// same phone, or several links at once) silently replaces the first one. So every callback goes
/// through [_Hub] below, which routes by endpoint id.
///
/// pubspec.yaml:   nearby_connections: ^4.0.0     (Android only; needs Google Play services)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

const String kRelayServiceId = 'com.elfaheem.attendance.relay';
// CLUSTER (M-to-N): a phone can advertise AND discover at the same time, and one phone can talk
// to several classmates — both are needed for the classmate-witness signals.
const Strategy _kStrategy = Strategy.P2P_CLUSTER;

enum RelayFailure { bluetoothOff, noRelay, linkLost, timeout, unknown }

class RelayException implements Exception {
  const RelayException(this.kind, [this.detail]);
  final RelayFailure kind;
  final String? detail;
  @override
  String toString() => 'RelayException($kind, $detail)';
}

Uint8List _encode(Map<String, dynamic> m) => Uint8List.fromList(utf8.encode(jsonEncode(m)));

Map<String, dynamic>? _decode(Payload p) {
  if (p.type != PayloadType.BYTES || p.bytes == null) return null;
  try {
    final d = jsonDecode(utf8.decode(p.bytes!));
    return d is Map ? Map<String, dynamic>.from(d) : null;
  } catch (_) {
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HUB — the only place that talks to the plugin's global callbacks
// ════════════════════════════════════════════════════════════════════════════

bool _isReply(Map<String, dynamic> m) {
  final t = m['t'];
  return t == 'window' || t == 'result' || t == 'error' || (t == 'witness' && m.containsKey('sig'));
}

bool _isRequest(Map<String, dynamic> m) {
  final t = m['t'];
  return t == 'hello' || t == 'submit' || (t == 'witness' && m.containsKey('att'));
}

class _Hub {
  _Hub._();
  static final _Hub i = _Hub._();

  final Nearby nearby = Nearby();

  /// Links WE opened (client side), by endpoint id.
  final Map<String, RelayLink> links = {};
  final Map<String, Completer<RelayLink>> connecting = {};

  /// Set while this phone advertises: answers requests arriving on ANY connection.
  RelayHandler? hostHandler;

  void onPayload(String eid, Payload p) {
    final m = _decode(p);
    if (m == null) return;
    final link = links[eid];
    if (link != null && _isReply(m) && link._deliver(m)) return;
    final h = hostHandler;
    if (h != null && _isRequest(m)) _serve(eid, m, h);
  }

  Future<void> _serve(String eid, Map<String, dynamic> req, RelayHandler h) async {
    Map<String, dynamic> reply;
    try {
      reply = await h(req);
    } catch (e) {
      debugPrint('relay handler failed: $e');
      reply = {'t': 'error', 'code': 'relay_failed', 'message': 'relay failed'};
    }
    try {
      await nearby.sendBytesPayload(eid, _encode(reply));
    } catch (_) {}
  }

  // connection established by someone else to us (we advertise)
  void adInitiated(String id, ConnectionInfo info) {
    nearby.acceptConnection(id, onPayLoadRecieved: onPayload);
  }

  // connection WE requested (we discover)
  void disInitiated(String id, ConnectionInfo info) {
    nearby.acceptConnection(id, onPayLoadRecieved: onPayload);
  }

  void disResult(String id, Status st) {
    final c = connecting[id];
    if (st == Status.CONNECTED) {
      final l = RelayLink._(nearby, id);
      links[id] = l;
      if (c != null && !c.isCompleted) c.complete(l);
    } else if (c != null && !c.isCompleted) {
      c.completeError(RelayException(RelayFailure.linkLost, 'status ${st.name}'));
    }
  }

  void disDisconnected(String id) {
    links.remove(id)?._onDisconnected();
    final c = connecting.remove(id);
    if (c != null && !c.isCompleted) {
      c.completeError(const RelayException(RelayFailure.linkLost, 'disconnected'));
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CLIENT (student collecting signals / offline student)
// ════════════════════════════════════════════════════════════════════════════

/// An open connection to ONE nearby phone.
class RelayLink {
  RelayLink._(this._nearby, this.endpointId);
  final Nearby _nearby;
  final String endpointId;

  Completer<Map<String, dynamic>>? _waiting;
  bool _closed = false;

  /// true when a pending request consumed the message.
  bool _deliver(Map<String, dynamic> m) {
    final w = _waiting;
    if (w == null || w.isCompleted) return false;
    w.complete(m);
    return true;
  }

  void _onDisconnected() {
    _closed = true;
    final w = _waiting;
    if (w != null && !w.isCompleted) {
      w.completeError(const RelayException(RelayFailure.linkLost));
    }
  }

  /// Sends [msg] and waits for the single reply.
  Future<Map<String, dynamic>> request(Map<String, dynamic> msg,
      {Duration timeout = const Duration(seconds: 25)}) async {
    if (_closed) throw const RelayException(RelayFailure.linkLost);
    final w = Completer<Map<String, dynamic>>();
    _waiting = w;
    await _nearby.sendBytesPayload(endpointId, _encode(msg));
    try {
      return await w.future.timeout(timeout);
    } on TimeoutException {
      throw const RelayException(RelayFailure.timeout);
    }
  }

  Future<void> close() async {
    _closed = true;
    _Hub.i.links.remove(endpointId);
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
  }
}

class RelayClient {
  final Nearby _nearby = Nearby();
  final Set<String> _mine = {};

  /// Human-readable trace of the last search (shown on failure so a field test is diagnosable).
  String diag = '';

  /// Discovers nearby phones and connects to up to [count] of them (as many as are found before
  /// [timeout]). Throws [RelayException] if none could be reached.
  /// [skip] lets the caller avoid endpoints that already failed.
  Future<List<RelayLink>> connectMany({
    required int count,
    Duration timeout = const Duration(seconds: 25),
    Set<String> skip = const {},
    String nickname = 'student',
  }) async {
    final found = StreamController<String>();
    final seen = <String>{...skip};
    var foundCount = 0;
    final connectErrors = <String>[];
    diag = '';

    try {
      await _nearby.stopDiscovery();
    } catch (_) {}

    try {
      final ok = await _nearby.startDiscovery(
        nickname,
        _kStrategy,
        serviceId: kRelayServiceId,
        onEndpointFound: (id, name, serviceId) {
          if (seen.add(id) && !found.isClosed) {
            foundCount++;
            found.add(id);
          }
        },
        onEndpointLost: (_) {},
      );
      if (!ok) throw const RelayException(RelayFailure.bluetoothOff, 'startDiscovery returned false');
    } on RelayException {
      await found.close();
      rethrow;
    } catch (e) {
      // Nearby throws a PlatformException when Bluetooth / Location is off or already discovering.
      await found.close();
      throw RelayException(RelayFailure.bluetoothOff, e.toString());
    }

    final links = <RelayLink>[];
    final deadline = DateTime.now().add(timeout);
    final it = StreamIterator<String>(found.stream);
    try {
      while (links.length < count) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        bool has;
        try {
          has = await it.moveNext().timeout(left);
        } on TimeoutException {
          break;
        }
        if (!has) break;
        try {
          final l = await _connectTo(it.current, nickname);
          _mine.add(l.endpointId);
          links.add(l);
        } on RelayException catch (e) {
          connectErrors.add('${e.kind.name}${e.detail == null ? '' : ':${e.detail}'}');
          continue; // that phone refused / dropped: look for another one
        }
      }
    } finally {
      await it.cancel();
      await found.close();
      await _safeStopDiscovery();
    }
    diag = 'discovery ok; phones found=$foundCount; connected=${links.length}'
        '${connectErrors.isEmpty ? '' : '; connect errors=${connectErrors.join(', ')}'}';
    if (links.isEmpty) throw RelayException(RelayFailure.noRelay, diag);
    return links;
  }

  /// One relay (used when no witnesses are needed).
  Future<RelayLink> connect({
    Duration timeout = const Duration(seconds: 25),
    Set<String> skip = const {},
    String nickname = 'student',
  }) async =>
      (await connectMany(count: 1, timeout: timeout, skip: skip, nickname: nickname)).first;

  Future<RelayLink> _connectTo(String endpointId, String nickname) async {
    final hub = _Hub.i;
    final connected = Completer<RelayLink>();
    hub.connecting[endpointId] = connected;
    try {
      // No token check on purpose: security never depends on this link (see header).
      final asked = await _nearby.requestConnection(
        nickname,
        endpointId,
        onConnectionInitiated: hub.disInitiated,
        onConnectionResult: hub.disResult,
        onDisconnected: hub.disDisconnected,
      );
      if (!asked) throw const RelayException(RelayFailure.unknown, 'requestConnection false');
      return await connected.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const RelayException(RelayFailure.timeout, 'connect timeout');
    } on RelayException {
      rethrow;
    } catch (e) {
      throw RelayException(RelayFailure.unknown, e.toString());
    } finally {
      hub.connecting.remove(endpointId);
    }
  }

  Future<void> _safeStopDiscovery() async {
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
  }

  /// Stops searching and closes only OUR links (never the ones this phone serves as a host).
  Future<void> stop() async {
    await _safeStopDiscovery();
    for (final id in _mine.toList()) {
      _Hub.i.links.remove(id);
      try {
        await _nearby.disconnectFromEndpoint(id);
      } catch (_) {}
    }
    _mine.clear();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HOST (a student phone that is visible to classmates)
// ════════════════════════════════════════════════════════════════════════════

typedef RelayHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class RelayHost {
  final Nearby _nearby = Nearby();
  bool _running = false;
  bool get running => _running;

  /// Last advertising error (null when it started fine).
  String? lastError;

  Future<bool> start({required RelayHandler handler, String nickname = 'relay'}) async {
    if (_running) return true;
    final hub = _Hub.i;
    hub.hostHandler = handler;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      final ok = await _nearby.startAdvertising(
        nickname,
        _kStrategy,
        serviceId: kRelayServiceId,
        onConnectionInitiated: hub.adInitiated,
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
      );
      _running = ok;
      lastError = ok ? null : 'startAdvertising returned false';
      if (!ok) hub.hostHandler = null;
      return ok;
    } catch (e) {
      lastError = e.toString();
      debugPrint('relay advertise failed: $e');
      _running = false;
      hub.hostHandler = null;
      return false;
    }
  }

  /// Stops advertising only; connections this phone opened as a client stay alive.
  Future<void> stop() async {
    _running = false;
    _Hub.i.hostHandler = null;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
  }
}
