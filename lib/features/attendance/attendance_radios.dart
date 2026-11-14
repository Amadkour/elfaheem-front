/// features/attendance/attendance_radios.dart
///
/// One tap on the attendance button prepares everything the check-in may need:
///   • permissions     — Bluetooth / nearby devices / location are requested automatically
///   • WHAT is needed  — computed for THIS check-in ([requiredRadios]): nothing is asked for that the
///                       teacher's settings and the student's connection do not really need
///   • fixing          — Android: the system "Allow the app to turn on Bluetooth?" dialog, the Wi-Fi quick
///                       panel and the Location settings, one tap each. iPhone: Location settings; Bluetooth
///                       and Wi-Fi only from Control Center (Apple gives apps no API), so we say exactly that.
///
/// No app can silently turn Bluetooth / Wi-Fi / GPS on (Android and iOS forbid it); this is the closest honest
/// behaviour: detect, explain in plain words, one tap to the right switch, and continue by itself on return.
library;

import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_education_app/features/attendance/attendance_permissions.dart';
import 'package:flutter_education_app/features/attendance/relay_ble_transport.dart';

class RadioStatus {
  const RadioStatus({this.gps, this.wifi, this.bluetooth, this.permissions = PermissionOutcome.granted});

  /// null = unknown / not applicable on this device.
  final bool? gps;
  final bool? wifi;
  final bool? bluetooth;
  final PermissionOutcome permissions;

  static const unknown = RadioStatus();

  bool get permissionsBlocked =>
      permissions == PermissionOutcome.denied || permissions == PermissionOutcome.permanentlyDenied;

  bool? of(RadioKind k) => switch (k) {
        RadioKind.gps => gps,
        RadioKind.wifi => wifi,
        RadioKind.bluetooth => bluetooth,
      };
}

enum RadioKind { gps, wifi, bluetooth }

class AttendanceRadios {
  AttendanceRadios._();

  static const _ch = MethodChannel('com.doubley.nextbrain/radios');
  static int? _sdk;

  static bool get _android => !kIsWeb && Platform.isAndroid;
  static bool get _ios => !kIsWeb && Platform.isIOS;

  static Future<int> androidSdk() async {
    if (!_android) return 0;
    try {
      return _sdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      return 33;
    }
  }

  /// What THIS check-in needs switched on.
  ///   online, no classmates  → only the location factors the teacher chose
  ///   offline OR classmates  → Bluetooth (+ Location on Android ≤ 11: BLE scans return nothing without it)
  ///   Wi-Fi factor           → connected to Wi-Fi, and Location on (Android hides the BSSID otherwise)
  static Future<Set<RadioKind>> requiredRadios({
    required bool? online,
    required bool needsGps,
    required bool needsWifi,
    required int witnesses,
  }) async {
    final out = <RadioKind>{};
    if (needsGps) out.add(RadioKind.gps);
    if (needsWifi && !kIsWeb) {
      out.add(RadioKind.wifi);
      if (_android) out.add(RadioKind.gps);
    }
    final nearby = online == false || witnesses > 0;
    if (nearby && relayLinkSupported) {
      out.add(RadioKind.bluetooth);
      if (_android && await androidSdk() <= 30) out.add(RadioKind.gps);
    }
    return out;
  }

  /// The radios among [needed] that are OFF right now (unknown counts as fine: we never block on a guess).
  static Future<List<RadioKind>> missing(Set<RadioKind> needed) async {
    if (needed.isEmpty) return const [];
    final st = await read();
    return [for (final k in RadioKind.values) if (needed.contains(k) && st.of(k) == false) k];
  }

  /// Requests permissions (once, together) and reads the state of the three radios.
  static Future<RadioStatus> prepare({bool askPermissions = true}) async {
    var perms = PermissionOutcome.granted;
    if (askPermissions && !kIsWeb) {
      perms = await ensureNearbyPermissions(advertise: true);
      try {
        // iOS asks for location through the geolocator plugin.
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      } catch (_) {}
    }
    return read(perms);
  }

  /// Only reads (no prompts): used when the app comes back from the system settings.
  static Future<RadioStatus> read([PermissionOutcome perms = PermissionOutcome.granted]) async {
    bool? gps, wifi, bt;
    try {
      gps = await Geolocator.isLocationServiceEnabled();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        final r = await Connectivity().checkConnectivity();
        wifi = r.contains(ConnectivityResult.wifi);
      } catch (_) {}
      bt = await BleRelay.instance.bluetoothOn();
    }
    return RadioStatus(gps: gps, wifi: wifi, bluetooth: bt, permissions: perms);
  }

  /// Takes the student to the switch for [kind]. Returns false when the app can only show a hint
  /// (iPhone Bluetooth / Wi-Fi → Control Center) — show [hintKey] then.
  static Future<bool> fix(RadioKind kind) async {
    switch (kind) {
      case RadioKind.gps:
        try {
          return await Geolocator.openLocationSettings();
        } catch (_) {
          return false;
        }
      case RadioKind.bluetooth:
        if (_android) {
          // Android 12+: needs BLUETOOTH_CONNECT (asked by prepare()); shows the system "turn on?" dialog.
          if (await _native('requestBluetoothOn')) return true;
          if (await _native('openBluetoothSettings')) return true;
        }
        return false;
      case RadioKind.wifi:
        if (_android) {
          if (await _native('openWifiPanel')) return true;   // Android 10+: bottom-sheet panel, else settings
        }
        return false;
    }
  }

  /// What to tell the person when [fix] could not open anything.
  static String hintKey(RadioKind kind) =>
      _ios && kind != RadioKind.gps ? 'att_radio_hint_ios' : 'att_radio_hint';

  static Future<bool> _native(String method) async {
    try {
      return (await _ch.invokeMethod<bool>(method)) ?? false;
    } catch (_) {
      return false; // older app build without the native channel
    }
  }
}
