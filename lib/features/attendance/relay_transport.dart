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
/// This file is the Nearby Connections (Android) transport and the entry point ([RelayClient],
/// [RelayHost]) that also drives the Bluetooth LE transport (relay_ble_transport.dart) so that
/// iPhones work too. See relay_link.dart for the transport order.
///
/// pubspec.yaml:   nearby_connections: ^4.0.0     (Android only; needs Google Play services)
///                 bluetooth_low_energy: ^6.0.0   (iPhone + Android<->iPhone)
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

import 'package:flutter_education_app/features/attendance/relay_ble_transport.dart';
import 'package:flutter_education_app/features/attendance/relay_link.dart';

export 'package:flutter_education_app/features/attendance/relay_link.dart';

const String kRelayServiceId = 'com.elfaheem.attendance.relay';
// CLUSTER (M-to-N): a phone can advertise AND discover at the same time, and one phone can talk
// to several classmates — both are needed for the classmate-witness signals.
const Strategy _kStrategy = Strategy.P2P_CLUSTER;

bool get _nearbyOk => !kIsWeb && Platform.isAndroid;
bool get _bleOk =>
    !kIsWeb && (Platform.isIOS || (Platform.isAndroid && kAndroidAlsoUsesBle));

Map<String, dynamic>? _decode(Payload p) {
  if (p.type != PayloadType.BYTES || p.bytes == null) return null;
  return decodeMsg(p.bytes!);
}

// ════════════════════════════════════════════════════════════════════════════
//  HUB — the only place that talks to the plugin's global callbacks
// ════════════════════════════════════════════════════════════════════════════

class _Hub {
  _Hub._();
  static final _Hub i = _Hub._();

  final Nearby nearby = Nearby();

  /// Links WE opened (client side), by endpoint id.
  final Map<String, _NearbyLink> links = {};
  final Map<String, Completer<_NearbyLink>> connecting = {};

  /// Set while this phone advertises: answers requests arriving on ANY connection.
  RelayHandler? hostHandler;

  void onPayload(String eid, Payload p) {
    final m = _decode(p);
    if (m == null) return;
    final link = links[eid];
    if (link != null && isReply(m) && link._deliver(m)) return;
    final h = hostHandler;
    if (h != null && isRequest(m)) _serve(eid, m, h);
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
      await nearby.sendBytesPayload(eid, encodeMsg(reply));
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
      final l = _NearbyLink._(nearby, id);
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

/// An open Nearby Connections link to ONE nearby phone.
class _NearbyLink implements RelayLink {
  _NearbyLink._(this._nearby, this.endpointId);
  final Nearby _nearby;
  @override
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

  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> msg,
      {Duration timeout = const Duration(seconds: 25)}) async {
    if (_closed) throw const RelayException(RelayFailure.linkLost);
    final w = Completer<Map<String, dynamic>>();
    _waiting = w;
    await _nearby.sendBytesPayload(endpointId, encodeMsg(msg));
    try {
      return await w.future.timeout(timeout);
    } on TimeoutException {
      throw const RelayException(RelayFailure.timeout);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _Hub.i.links.remove(endpointId);
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
  }
}

class RelayClient {
  final Set<String> _mine = {};
  final List<RelayLink> _bleLinks = [];

  /// Human-readable trace of the last search (shown on failure so a field test is diagnosable).
  String diag = '';

  /// Searches with every transport this phone has and connects to up to [count] phones (as many
  /// as are found before [timeout]). Throws [RelayException] if none could be reached.
  /// [skip] lets the caller avoid endpoints that already failed.
  Future<List<RelayLink>> connectMany({
    required int count,
    Duration timeout = const Duration(seconds: 25),
    Set<String> skip = const {},
    String nickname = 'student',
  }) async {
    final c = RelayCollector(count);
    final jobs = <Future<void>>[
      if (_nearbyOk) _nearbyMany(c, timeout, skip, nickname),
      if (_bleOk) BleRelay.instance.connectMany(c, timeout: timeout, skip: skip),
    ];
    if (jobs.isEmpty) {
      throw const RelayException(RelayFailure.unknown, 'no transport on this device');
    }
    await Future.any([c.enough, Future.wait(jobs)]);
    c.cancel();
    await Future.wait(jobs); // transports stop searching and clean up

    for (final l in c.links) {
      if (l is _NearbyLink) {
        _mine.add(l.endpointId);
      } else {
        _bleLinks.add(l);
      }
    }
    diag = c.notes.join(' | ');
    if (c.links.isEmpty) {
      final off = c.errors.where((e) => e.kind == RelayFailure.bluetoothOff);
      if (off.isNotEmpty && c.errors.length == jobs.length) throw off.first;
      throw RelayException(RelayFailure.noRelay, diag);
    }
    return List.of(c.links);
  }

  /// One relay (used when no witnesses are needed).
  Future<RelayLink> connect({
    Duration timeout = const Duration(seconds: 25),
    Set<String> skip = const {},
    String nickname = 'student',
  }) async =>
      (await connectMany(count: 1, timeout: timeout, skip: skip, nickname: nickname)).first;

  // ── Nearby Connections search (Android) ───────────────────────────────
  Future<void> _nearbyMany(
      RelayCollector c, Duration timeout, Set<String> skip, String nickname) async {
    final nearby = Nearby();
    final found = StreamController<String>();
    final seen = <String>{...skip};
    var foundCount = 0;
    final connectErrors = <String>[];

    try {
      await nearby.stopDiscovery();
    } catch (_) {}

    try {
      final ok = await nearby.startDiscovery(
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
    } on RelayException catch (e) {
      c.errors.add(e);
      c.notes.add('nearby: ${e.detail}');
      await found.close();
      return;
    } catch (e) {
      // Nearby throws a PlatformException when Bluetooth / Location is off or already discovering.
      c.errors.add(RelayException(RelayFailure.bluetoothOff, e.toString()));
      c.notes.add('nearby: $e');
      await found.close();
      return;
    }

    final deadline = DateTime.now().add(timeout);
    final it = StreamIterator<String>(found.stream);
    var connected = 0;
    try {
      while (!c.satisfied) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        bool has;
        try {
          has = await Future.any<bool>([
            it.moveNext(),
            c.enough.then((_) => false),
          ]).timeout(left);
        } on TimeoutException {
          break;
        }
        if (!has) break;
        try {
          final l = await _connectTo(it.current, nickname);
          if (c.add(l)) connected++;
        } on RelayException catch (e) {
          connectErrors.add('${e.kind.name}${e.detail == null ? '' : ':${e.detail}'}');
          continue; // that phone refused / dropped: look for another one
        }
      }
    } finally {
      await it.cancel();
      await found.close();
      try {
        await nearby.stopDiscovery();
      } catch (_) {}
    }
    c.notes.add('nearby: found=$foundCount; connected=$connected'
        '${connectErrors.isEmpty ? '' : '; errors=${connectErrors.join(', ')}'}');
  }

  Future<_NearbyLink> _connectTo(String endpointId, String nickname) async {
    final hub = _Hub.i;
    final nearby = hub.nearby;
    final connected = Completer<_NearbyLink>();
    hub.connecting[endpointId] = connected;
    try {
      // No token check on purpose: security never depends on this link (see header).
      final asked = await nearby.requestConnection(
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

  /// Stops searching and closes only OUR links (never the ones this phone serves as a host).
  Future<void> stop() async {
    if (_nearbyOk) {
      try {
        await _Hub.i.nearby.stopDiscovery();
      } catch (_) {}
      for (final id in _mine.toList()) {
        _Hub.i.links.remove(id);
        try {
          await _Hub.i.nearby.disconnectFromEndpoint(id);
        } catch (_) {}
      }
    }
    _mine.clear();
    for (final l in _bleLinks) {
      await l.close();
    }
    _bleLinks.clear();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HOST (a student phone that is visible to classmates)
// ════════════════════════════════════════════════════════════════════════════

class RelayHost {
  bool _running = false;
  bool get running => _running;

  /// Last advertising error (null when it started fine).
  String? lastError;

  Future<bool> start({required RelayHandler handler, String nickname = 'relay'}) async {
    if (_running) return true;
    final errors = <String>[];
    var ok = false;

    if (_nearbyOk) {
      final nearby = _Hub.i.nearby;
      final hub = _Hub.i;
      hub.hostHandler = handler;
      try {
        await nearby.stopAdvertising();
      } catch (_) {}
      try {
        final r = await nearby.startAdvertising(
          nickname,
          _kStrategy,
          serviceId: kRelayServiceId,
          onConnectionInitiated: hub.adInitiated,
          onConnectionResult: (id, status) {},
          onDisconnected: (id) {},
        );
        if (r) {
          ok = true;
        } else {
          errors.add('nearby: startAdvertising returned false');
          hub.hostHandler = null;
        }
      } catch (e) {
        errors.add('nearby: $e');
        debugPrint('relay advertise failed: $e');
        hub.hostHandler = null;
      }
    }

    if (_bleOk) {
      final r = await BleRelay.instance.startHost(handler);
      if (r) {
        ok = true;
      } else {
        errors.add('ble: ${BleRelay.instance.lastError}');
      }
    }

    _running = ok;
    lastError = ok ? null : errors.join(' | ');
    return ok;
  }

  /// Stops advertising only; connections this phone opened as a client stay alive.
  Future<void> stop() async {
    _running = false;
    if (_nearbyOk) {
      _Hub.i.hostHandler = null;
      try {
        await _Hub.i.nearby.stopAdvertising();
      } catch (_) {}
    }
    if (_bleOk) await BleRelay.instance.stopHost();
  }
}
