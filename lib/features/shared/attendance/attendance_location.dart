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

/// Why location evidence could not be read — shown to the person with a one-tap fix.
enum LocationProblem { none, serviceOff, denied, deniedForever, noFix }

class LocationEvidenceService {
  /// What went wrong in the last collect() / here() call (none = fine).
  LocationProblem lastProblem = LocationProblem.none;

  /// Permission + service check, asking once when needed. Returns the problem (none = ready).
  static Future<LocationProblem> ensureReady() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationProblem.serviceOff;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return LocationProblem.deniedForever;
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        return LocationProblem.denied;
      }
      return LocationProblem.none;
    } catch (_) {
      return LocationProblem.noFix;
    }
  }

  /// Indoors a high-accuracy fix often times out: try high (10 s) → balanced (8 s) → a fix younger than 5 min.
  static Future<Position?> _position() async {
    for (final acc in const [LocationAccuracy.high, LocationAccuracy.medium]) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
              accuracy: acc, timeLimit: Duration(seconds: acc == LocationAccuracy.high ? 10 : 8)),
        );
      } catch (_) {}
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 5) return last;
    } catch (_) {}
    return null;
  }

  static Future<String?> _bssid() async {
    if (kIsWeb) return null;   // a browser cannot read the Wi-Fi network; only GPS works on the web
    try {
      final b = (await NetworkInfo().getWifiBSSID())?.trim().toLowerCase();
      // Android returns this placeholder when it may not read the real value (needs Location ON + permission).
      if (b != null && b.isNotEmpty && b != '02:00:00:00:00:00') return b;
    } catch (_) {}
    return null;
  }

  /// Returns {lat, lng, bssid} with whatever could be read, or null when nothing was available
  /// ([lastProblem] then says why).
  Future<Map<String, dynamic>?> collect(OpenWindow w) async {
    lastProblem = LocationProblem.none;
    if (!w.needsLocation) return null;
    final out = <String, dynamic>{};
    // Android reveals the Wi-Fi BSSID only with Location permission AND Location switched on,
    // so the same readiness check serves both factors.
    final ready = await ensureReady();
    if (ready == LocationProblem.none) {
      if (w.needsGps) {
        final pos = await _position();
        if (pos != null) {
          out['lat'] = double.parse(pos.latitude.toStringAsFixed(5));
          out['lng'] = double.parse(pos.longitude.toStringAsFixed(5));
        }
      }
      if (w.needsWifi || out.isEmpty) {
        final b = await _bssid();
        if (b != null) out['bssid'] = b;
      }
    }
    if (out.isEmpty) lastProblem = ready == LocationProblem.none ? LocationProblem.noFix : ready;
    return out.isEmpty ? null : out;
  }

  /// Teacher side: the phone's current position / Wi-Fi, used as the classroom reference.
  Future<({double? lat, double? lng, String? bssid})> here() async {
    lastProblem = LocationProblem.none;
    double? lat, lng;
    String? bssid;
    final ready = await ensureReady();
    if (ready == LocationProblem.none) {
      final pos = await _position();
      if (pos != null) {
        lat = double.parse(pos.latitude.toStringAsFixed(5));
        lng = double.parse(pos.longitude.toStringAsFixed(5));
      }
      bssid = await _bssid();
    }
    if (lat == null && bssid == null) lastProblem = ready == LocationProblem.none ? LocationProblem.noFix : ready;
    return (lat: lat, lng: lng, bssid: bssid);
  }
}

/// Translation key for a [LocationProblem] (shared by the student sheet and the teacher panel).
String locationProblemKey(LocationProblem p, {bool teacher = false}) => switch (p) {
      LocationProblem.serviceOff => 'att_err_gps_off',
      LocationProblem.denied => 'att_err_location_denied',
      LocationProblem.deniedForever => 'att_err_location_denied_forever',
      LocationProblem.noFix => teacher ? 'att_err_teacher_location' : 'att_err_no_fix',
      LocationProblem.none => 'att_err_generic',
    };
