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
///   client -> relay  {"t":"submit", ...PendingAttendance.toSubmitBody()}
///   relay  -> client {"t":"result", ...AttendanceResult}   | {"t":"error","code":..,"message":..}
///
/// pubspec.yaml:   nearby_connections: ^4.0.0     (Android only; needs Google Play services)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

const String kRelayServiceId = 'com.elfaheem.attendance.relay';
const Strategy _kStrategy = Strategy.P2P_STAR;

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
//  CLIENT (offline student)
// ════════════════════════════════════════════════════════════════════════════

/// An open connection to ONE relay phone.
class RelayLink {
  RelayLink._(this._nearby, this.endpointId);
  final Nearby _nearby;
  final String endpointId;

  Completer<Map<String, dynamic>>? _waiting;
  bool _closed = false;

  void _onPayload(Payload p) {
    final m = _decode(p);
    if (m != null && !(_waiting?.isCompleted ?? true)) _waiting!.complete(m);
  }

  void _onDisconnected() {
    _closed = true;
    if (!(_waiting?.isCompleted ?? true)) {
      _waiting!.completeError(const RelayException(RelayFailure.linkLost));
    }
  }

  /// Sends [msg] and waits for the single reply.
  Future<Map<String, dynamic>> request(Map<String, dynamic> msg,
      {Duration timeout = const Duration(seconds: 25)}) async {
    if (_closed) throw const RelayException(RelayFailure.linkLost);
    _waiting = Completer<Map<String, dynamic>>();
    await _nearby.sendBytesPayload(endpointId, _encode(msg));
    try {
      return await _waiting!.future.timeout(timeout);
    } on TimeoutException {
      throw const RelayException(RelayFailure.timeout);
    }
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
  }
}

class RelayClient {
  final Nearby _nearby = Nearby();

  /// Discovers nearby relays and connects to the first one that accepts.
  /// [skip] lets the caller avoid endpoints that already failed.
  Future<RelayLink> connect({
    Duration timeout = const Duration(seconds: 20),
    Set<String> skip = const {},
    String nickname = 'student',
  }) async {
    final found = Completer<String>();
    RelayLink? link;

    try {
      await _nearby.stopDiscovery();
    } catch (_) {}

    try {
      final ok = await _nearby.startDiscovery(
        nickname,
        _kStrategy,
        serviceId: kRelayServiceId,
        onEndpointFound: (id, name, serviceId) {
          if (!found.isCompleted && !skip.contains(id)) found.complete(id);
        },
        onEndpointLost: (_) {},
      );
      if (!ok) throw const RelayException(RelayFailure.bluetoothOff);
    } on RelayException {
      rethrow;
    } catch (e) {
      // Nearby throws a PlatformException when Bluetooth / Location is off.
      throw RelayException(RelayFailure.bluetoothOff, e.toString());
    }

    String endpointId;
    try {
      endpointId = await found.future.timeout(timeout);
    } on TimeoutException {
      await _safeStopDiscovery();
      throw const RelayException(RelayFailure.noRelay);
    }
    await _safeStopDiscovery();

    final connected = Completer<RelayLink>();
    try {
      await _nearby.requestConnection(
        nickname,
        endpointId,
        onConnectionInitiated: (id, info) async {
          // No token check on purpose: security never depends on this link (see header).
          await _nearby.acceptConnection(
            id,
            onPayLoadRecieved: (eid, payload) => link?._onPayload(payload),
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            final l = RelayLink._(_nearby, id);
            link = l;
            if (!connected.isCompleted) connected.complete(l);
          } else if (!connected.isCompleted) {
            connected.completeError(const RelayException(RelayFailure.linkLost, 'rejected'));
          }
        },
        onDisconnected: (id) => link?._onDisconnected(),
      );
      return await connected.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const RelayException(RelayFailure.timeout);
    } on RelayException {
      rethrow;
    } catch (e) {
      throw RelayException(RelayFailure.unknown, e.toString());
    }
  }

  Future<void> _safeStopDiscovery() async {
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
  }

  Future<void> stop() async {
    await _safeStopDiscovery();
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}
  }

  /// Which endpoint a link talks to (so a retry can skip a relay that failed).
  static String endpointOf(RelayLink l) => l.endpointId;
}

// ════════════════════════════════════════════════════════════════════════════
//  HOST (online student who agreed to help)
// ════════════════════════════════════════════════════════════════════════════

typedef RelayHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class RelayHost {
  final Nearby _nearby = Nearby();
  bool _running = false;
  bool get running => _running;

  Future<bool> start({required RelayHandler handler, String nickname = 'relay'}) async {
    if (_running) return true;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      final ok = await _nearby.startAdvertising(
        nickname,
        _kStrategy,
        serviceId: kRelayServiceId,
        onConnectionInitiated: (id, info) async {
          await _nearby.acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) async {
              final req = _decode(payload);
              if (req == null) return;
              Map<String, dynamic> reply;
              try {
                reply = await handler(req);
              } catch (e) {
                debugPrint('relay handler failed: $e');
                reply = {'t': 'error', 'code': 'relay_failed', 'message': 'relay failed'};
              }
              try {
                await _nearby.sendBytesPayload(endpointId, _encode(reply));
              } catch (_) {}
            },
          );
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
      );
      _running = ok;
      return ok;
    } catch (e) {
      debugPrint('relay advertise failed: $e');
      _running = false;
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}
  }
}
