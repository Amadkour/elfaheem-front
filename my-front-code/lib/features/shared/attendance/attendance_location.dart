/// features/attendance/attendance_location.dart
///
/// Location evidence for sessions whose teacher set a location policy. The ladder (cheapest
/// available factor first, the server accepts ANY of them):
///   1. GPS fix           — inside the circle the teacher set
///   2. Wi-Fi BSSID       — connected to the classroom access point
/// Both work OFFLINE (GPS needs no internet; the BSSID only needs a Wi-Fi association).
///
/// This is a HURDLE, not proof: a rooted/spoofing phone can fake GPS. It is signed with the
/// student's key so a relay cannot swap it, but the student can still lie about it.
///   pubspec.yaml ->  geolocator: ^13.0.0
///                    network_info_plus: ^6.0.0
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'attendance_models.dart';

class LocationEvidenceService {
  /// Returns {lat, lng, bssid} with whatever could be read, or null when nothing was available.
  Future<Map<String, dynamic>?> collect(OpenWindow w) async {
    if (!w.needsLocation) return null;
    final out = <String, dynamic>{};

    if (w.needsGps) {
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
          );
          out['lat'] = double.parse(pos.latitude.toStringAsFixed(5));
          out['lng'] = double.parse(pos.longitude.toStringAsFixed(5));
        }
      } catch (_) {/* fall through to the next factor */}
    }

    // A browser cannot read the Wi-Fi network; only GPS works on the web.
    if (!kIsWeb && (w.needsWifi || out.isEmpty)) {
      try {
        final b = (await NetworkInfo().getWifiBSSID())?.trim().toLowerCase();
        // Android returns this placeholder when it may not read the real value.
        if (b != null && b.isNotEmpty && b != '02:00:00:00:00:00') out['bssid'] = b;
      } catch (_) {}
    }
    return out.isEmpty ? null : out;
  }

  /// Teacher side: the phone's current position / Wi-Fi, used as the classroom reference.
  Future<({double? lat, double? lng, String? bssid})> here() async {
    double? lat, lng;
    String? bssid;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
        lat = double.parse(pos.latitude.toStringAsFixed(5));
        lng = double.parse(pos.longitude.toStringAsFixed(5));
      }
    } catch (_) {}
    if (!kIsWeb) {
      try {
        final b = (await NetworkInfo().getWifiBSSID())?.trim().toLowerCase();
        if (b != null && b.isNotEmpty && b != '02:00:00:00:00:00') bssid = b;
      } catch (_) {}
    }
    return (lat: lat, lng: lng, bssid: bssid);
  }
}
