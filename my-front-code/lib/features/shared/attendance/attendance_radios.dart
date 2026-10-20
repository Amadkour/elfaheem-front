/// features/attendance/attendance_radios.dart
///
/// One tap on the attendance button prepares everything the check-in may need:
///   • permissions     — Bluetooth / nearby devices / location are requested automatically
///   • GPS             — only the system can switch it on: we detect it and open Location settings
///   • Bluetooth, Wi-Fi — same: detected, and the student is sent to the right place to switch them
///
/// No app can silently turn Bluetooth / Wi-Fi / GPS on (Android and iOS forbid it), so this
/// is the closest honest behaviour: ask for permissions, detect what is off, one tap to fix it.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'attendance_permissions.dart';
import 'relay_ble_transport.dart';

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
}

enum RadioKind { gps, wifi, bluetooth }

class AttendanceRadios {
  AttendanceRadios._();

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
    try {
      final r = await Connectivity().checkConnectivity();
      wifi = r.contains(ConnectivityResult.wifi);
    } catch (_) {}
    if (!kIsWeb) bt = await BleRelay.instance.bluetoothOn();
    return RadioStatus(gps: gps, wifi: wifi, bluetooth: bt, permissions: perms);
  }

  /// Takes the student to where [kind] can be switched on. Returns false when the app can only
  /// show a hint (Bluetooth / Wi-Fi have no public "open this screen" call in Flutter's core).
  static Future<bool> fix(RadioKind kind) async {
    switch (kind) {
      case RadioKind.gps:
        try {
          return await Geolocator.openLocationSettings();
        } catch (_) {
          return false;
        }
      case RadioKind.bluetooth:
      case RadioKind.wifi:
        return openSettings(); // app settings; the quick-settings tile is the fast way
    }
  }
}
