/// features/attendance/relay_ble_transport.dart
///
/// Bluetooth LE (GATT) transport for the relay link — what makes iPhones work (iOS has no Nearby
/// Connections) and lets Android and iPhone talk to each other.
///
///   host   (online phone)  = GATT PERIPHERAL: advertises the service, receives a framed request
///                            on the RX characteristic, answers with framed notifications on TX
///   client (offline phone) = GATT CENTRAL:   scans for the service, connects, subscribes to TX,
///                            writes framed requests to RX
///
/// Same JSON messages as the Nearby transport (see relay_transport.dart). Like that link, this one
/// is untrusted and is NOT proof of presence — it only carries signed bytes.
///
/// !! ISOLATED ON PURPOSE !! This file is the ONLY one that imports `bluetooth_low_energy`.
/// It was written from memory of the package's 6.x API (it could not be checked against the
/// package source here). If it does not compile or a method name differs in your version, fix it
/// here only: nothing else in the app depends on the package. To switch iPhone/BLE off entirely,
/// make [BleRelay.supported] return false.
///
/// pubspec.yaml:  bluetooth_low_energy: ^6.0.0
/// iOS Info.plist: NSBluetoothAlwaysUsageDescription (+ UIBackgroundModes bluetooth-central /
///                 bluetooth-peripheral if the app should keep relaying while backgrounded)
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import 'relay_link.dart';

final UUID _kService = UUID.fromString('7b1c0001-5a3d-4f6e-9c1a-2e8f4d6b9a10');
final UUID _kRx = UUID.fromString('7b1c0002-5a3d-4f6e-9c1a-2e8f4d6b9a10'); // central -> peripheral
final UUID _kTx = UUID.fromString('7b1c0003-5a3d-4f6e-9c1a-2e8f4d6b9a10'); // peripheral -> central

class BleRelay {
  BleRelay._();
  static final BleRelay instance = BleRelay._();

  /// Flip to false to disable the BLE transport everywhere.
  bool get supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  String? lastError;

  /// Is Bluetooth switched on? null = unknown / unsupported. Waits briefly for the first state.
  Future<bool?> bluetoothOn() async {
    if (!supported) return null;
    try {
      final cm = _cm ??= CentralManager();
      var st = cm.state;
      if (st == BluetoothLowEnergyState.unknown) {
        st = await cm.stateChanged.map((e) => e.state).first.timeout(const Duration(seconds: 2));
      }
      return st == BluetoothLowEnergyState.poweredOn;
    } catch (_) {
      return null;
    }
  }

  // ── HOST (peripheral) ──────────────────────────────────────────────────
  PeripheralManager? _pm;
  GATTCharacteristic? _tx;
  RelayHandler? _handler;
  final FrameAssembler _hostIn = FrameAssembler();
  final List<StreamSubscription<dynamic>> _hostSubs = [];
  bool _hosting = false;

  Future<bool> startHost(RelayHandler handler) async {
    if (!supported) {
      lastError = 'unsupported';
      return false;
    }
    if (_hosting) {
      _handler = handler;
      return true;
    }
    try {
      final pm = _pm ??= PeripheralManager();
      if (!Platform.isIOS) await pm.authorize(); // iOS asks through Info.plist instead
      if (pm.state != BluetoothLowEnergyState.poweredOn) {
        lastError = 'bluetooth is off';
        return false;
      }
      _handler = handler;

      final rx = GATTCharacteristic.mutable(
        uuid: _kRx,
        properties: [GATTCharacteristicProperty.write, GATTCharacteristicProperty.writeWithoutResponse],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );
      final tx = GATTCharacteristic.mutable(
        uuid: _kTx,
        properties: [GATTCharacteristicProperty.notify, GATTCharacteristicProperty.read],
        permissions: [GATTCharacteristicPermission.read],
        descriptors: [],
      );
      _tx = tx;
      await pm.removeAllServices();
      await pm.addService(GATTService(
        uuid: _kService,
        isPrimary: true,
        includedServices: [],
        characteristics: [rx, tx],
      ));

      _hostSubs.add(pm.characteristicWriteRequested.listen((e) async {
        try {
          await pm.respondWriteRequest(e.request);
        } catch (_) {}
        if (e.characteristic.uuid != _kRx) return;
        final full = _hostIn.add(e.central.uuid.toString(), e.request.value);
        if (full != null) unawaited(_serve(pm, e.central, full));
      }));

      await pm.startAdvertising(Advertisement(name: 'att', serviceUUIDs: [_kService]));
      _hosting = true;
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('ble host failed: $e');
      await stopHost();
      return false;
    }
  }

  Future<void> _serve(PeripheralManager pm, Central central, Uint8List bytes) async {
    final req = decodeMsg(bytes);
    final h = _handler;
    if (req == null || h == null || !isRequest(req)) return;
    Map<String, dynamic> reply;
    try {
      reply = await h(req);
    } catch (e) {
      debugPrint('ble handler failed: $e');
      reply = {'t': 'error', 'code': 'relay_failed', 'message': 'relay failed'};
    }
    final tx = _tx;
    if (tx == null) return;
    try {
      for (final frame in frameMessage(encodeMsg(reply))) {
        await pm.notifyCharacteristic(central, tx, value: frame);
      }
    } catch (e) {
      debugPrint('ble notify failed: $e');
    }
  }

  Future<void> stopHost() async {
    _hosting = false;
    _handler = null;
    for (final s in _hostSubs) {
      await s.cancel();
    }
    _hostSubs.clear();
    try {
      await _pm?.stopAdvertising();
      await _pm?.removeAllServices();
    } catch (_) {}
  }

  // ── CLIENT (central) ───────────────────────────────────────────────────
  CentralManager? _cm;
  final Map<String, _BleLink> _links = {};
  StreamSubscription<dynamic>? _notifySub;
  StreamSubscription<dynamic>? _connSub;

  void _ensureCentralListeners(CentralManager cm) {
    _notifySub ??= cm.characteristicNotified.listen((e) {
      _links[e.peripheral.uuid.toString()]?._onFrame(e.value);
    });
    _connSub ??= cm.connectionStateChanged.listen((e) {
      if (e.state == ConnectionState.disconnected) {
        _links.remove(e.peripheral.uuid.toString())?._onDisconnected();
      }
    });
  }

  /// Scans and connects to phones advertising the service until [c] has enough links or
  /// [timeout] passes. Errors are recorded in [c] (never thrown).
  Future<void> connectMany(RelayCollector c,
      {required Duration timeout, Set<String> skip = const {}}) async {
    if (!supported) return;
    final cm = _cm ??= CentralManager();
    StreamSubscription<DiscoveredEventArgs>? scan;
    final found = StreamController<Peripheral>();
    final seen = <String>{...skip};
    var foundCount = 0, connected = 0;
    final errs = <String>[];
    try {
      if (!Platform.isIOS) await cm.authorize();
      if (cm.state != BluetoothLowEnergyState.poweredOn) {
        c.errors.add(const RelayException(RelayFailure.bluetoothOff, 'ble: bluetooth is off'));
        c.notes.add('ble: bluetooth is off');
        await found.close();
        return;
      }
      _ensureCentralListeners(cm);
      scan = cm.discovered.listen((e) {
        final id = e.peripheral.uuid.toString();
        if (seen.add(id) && !found.isClosed) {
          foundCount++;
          found.add(e.peripheral);
        }
      });
      await cm.startDiscovery(serviceUUIDs: [_kService]);
    } catch (e) {
      c.errors.add(RelayException(RelayFailure.bluetoothOff, 'ble: $e'));
      c.notes.add('ble: $e');
      await scan?.cancel();
      await found.close();
      return;
    }

    final deadline = DateTime.now().add(timeout);
    final it = StreamIterator<Peripheral>(found.stream);
    try {
      while (!c.satisfied) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        bool has;
        try {
          has = await Future.any<bool>([it.moveNext(), c.enough.then((_) => false)]).timeout(left);
        } on TimeoutException {
          break;
        }
        if (!has) break;
        try {
          final l = await _connect(cm, it.current);
          if (c.add(l)) connected++;
        } catch (e) {
          errs.add(e.toString());
        }
      }
    } finally {
      await it.cancel();
      await found.close();
      await scan.cancel();
      try {
        await cm.stopDiscovery();
      } catch (_) {}
    }
    c.notes.add('ble: found=$foundCount; connected=$connected'
        '${errs.isEmpty ? '' : '; errors=${errs.join(', ')}'}');
  }

  Future<_BleLink> _connect(CentralManager cm, Peripheral p) async {
    await cm.connect(p).timeout(const Duration(seconds: 15));
    if (Platform.isAndroid) {
      try {
        await cm.requestMTU(p, mtu: 247);
      } catch (_) {}
    }
    final services = await cm.discoverGATT(p).timeout(const Duration(seconds: 10));
    final svc = services.firstWhere((s) => s.uuid == _kService);
    final rx = svc.characteristics.firstWhere((x) => x.uuid == _kRx);
    final tx = svc.characteristics.firstWhere((x) => x.uuid == _kTx);
    final link = _BleLink._(cm, p, rx, tx);
    _links[p.uuid.toString()] = link;
    await cm.setCharacteristicNotifyState(p, tx, state: true);
    return link;
  }
}

class _BleLink implements RelayLink {
  _BleLink._(this._cm, this._p, this._rx, this._tx);
  final CentralManager _cm;
  final Peripheral _p;
  final GATTCharacteristic _rx;
  // ignore: unused_field
  final GATTCharacteristic _tx;

  final FrameAssembler _in = FrameAssembler();
  Completer<Map<String, dynamic>>? _waiting;
  bool _closed = false;

  @override
  String get endpointId => _p.uuid.toString();

  void _onFrame(Uint8List frame) {
    final full = _in.add('p', frame);
    if (full == null) return;
    final m = decodeMsg(full);
    final w = _waiting;
    if (m != null && isReply(m) && w != null && !w.isCompleted) w.complete(m);
  }

  void _onDisconnected() {
    _closed = true;
    final w = _waiting;
    if (w != null && !w.isCompleted) w.completeError(const RelayException(RelayFailure.linkLost));
  }

  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> msg,
      {Duration timeout = const Duration(seconds: 25)}) async {
    if (_closed) throw const RelayException(RelayFailure.linkLost);
    final w = Completer<Map<String, dynamic>>();
    _waiting = w;
    _in.drop('p');
    try {
      for (final frame in frameMessage(encodeMsg(msg))) {
        await _cm.writeCharacteristic(_p, _rx,
            value: frame, type: GATTCharacteristicWriteType.withResponse);
      }
      return await w.future.timeout(timeout);
    } on TimeoutException {
      throw const RelayException(RelayFailure.timeout);
    } on RelayException {
      rethrow;
    } catch (e) {
      throw RelayException(RelayFailure.linkLost, e.toString());
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    BleRelay.instance._links.remove(endpointId);
    try {
      await _cm.disconnect(_p);
    } catch (_) {}
  }
}
