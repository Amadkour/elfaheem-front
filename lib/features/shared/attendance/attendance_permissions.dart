/// features/attendance/attendance_permissions.dart
///
/// Runtime permissions for the nearby (Bluetooth) relay link. The app can ASK for permissions
/// but cannot switch Bluetooth / Wi-Fi on or off — it can only tell the user to do it.
///
/// Android 12+ : BLUETOOTH_SCAN / BLUETOOTH_ADVERTISE / BLUETOOTH_CONNECT
/// Android 13+ : NEARBY_WIFI_DEVICES
/// Android <=12: ACCESS_FINE_LOCATION (+ Location services ON)
library;

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum PermissionOutcome { granted, denied, permanentlyDenied, unsupported }

/// The relay link uses Google Nearby Connections, which exists on Android only.
/// On other platforms the student can still check in directly while online.
bool get relayLinkSupported => !kIsWeb && Platform.isAndroid;

Future<int> _sdkInt() async {
  try {
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  } catch (_) {
    return 33;
  }
}

/// [advertise] = true for the helping (online) phone, false for the offline student.
Future<PermissionOutcome> ensureNearbyPermissions({required bool advertise}) async {
  if (!relayLinkSupported) return PermissionOutcome.unsupported;
  final sdk = await _sdkInt();

  final wanted = <Permission>[
    if (sdk >= 31) ...[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if (advertise) Permission.bluetoothAdvertise,
    ],
    if (sdk >= 33) Permission.nearbyWifiDevices,
    if (sdk <= 32) Permission.locationWhenInUse,
  ];

  final result = await wanted.request();
  if (result.values.every((s) => s.isGranted || s.isLimited)) return PermissionOutcome.granted;
  if (result.values.any((s) => s.isPermanentlyDenied)) return PermissionOutcome.permanentlyDenied;
  return PermissionOutcome.denied;
}

Future<bool> openSettings() => openAppSettings();
