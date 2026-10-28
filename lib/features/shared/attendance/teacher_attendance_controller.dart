/// features/attendance/teacher_attendance_controller.dart
///
/// App-wide singleton for the teacher's running attendance. Because it lives outside any screen
/// the teacher can leave the sheet and move around the app: the global banner (see
/// attendance_teacher_banner.dart) keeps showing the code, the present counter and the time left.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import 'attendance_location.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';
import 'relay_host_provider.dart';

class TeacherAttendanceController extends ChangeNotifier {
  TeacherAttendanceController._();
  static final TeacherAttendanceController instance = TeacherAttendanceController._();

  final AttendanceRepository _repo = AttendanceRepository();
  final LocationEvidenceService _loc = LocationEvidenceService();

  /// While open, this phone is visible to nearby OFFLINE students and forwards their check-ins.
  RelayHostProvider? host;

  // ── settings (chosen before starting) ───────────────────────────────────
  int? sessionId;
  int minutes = 15;

  /// 'code' | 'witnesses' | 'both'
  String method = 'code';

  /// Classmates each student must collect (used when method != 'code'). Default 0 → starts at 1
  /// as soon as the teacher picks "classmates" or "both".
  int requiredWitnesses = 0;

  /// Seconds the server keeps accepting after the window ends / is closed (default 5).
  int graceSeconds = 5;

  /// May students check in from the web app?
  bool allowWeb = false;

  /// Also require the student to be near the teacher (GPS circle and/or Wi-Fi BSSID).
  bool useLocation = false;
  int radiusM = 100;

  /// Where the classroom point comes from. Mobile: always this phone. Web: 'browser' (this
  /// browser's rough location) or 'mobile' (shared earlier from the teacher's phone).
  String webLocationSource = 'mobile';

  /// Set after a successful "share from mobile" (mobile) or "found shared location" (web).
  bool sharedFromMobile = false;

  static const minRadius = 20;
  static const maxRadius = 1000;

  static const options = [10, 15, 30, 60];
  static const witnessOptions = [1, 2, 3, 4, 5];
  static const graceOptions = [0, 5, 10, 20, 30];
  static const radiusOptions = [50, 100, 200, 500];
  static const methods = ['code', 'witnesses', 'both'];

  // ── running state ───────────────────────────────────────────────────────
  TeacherWindow? window;
  TeacherCode? code;
  int secondsLeft = 0;
  bool loading = false;
  bool closed = false;
  String? error;

  /// Lesson title shown in the global bar (set when the sheet is prepared).
  String? lessonTitle;

  /// MOBILE: a web session asked this phone for the classroom location (silent push).
  bool webLocationRequested = false;

  /// WEB: waiting for the phone to answer.
  bool waitingMobile = false;

  /// After "close": counts down the grace so the teacher sees when nothing more is accepted.
  int closingLeft = 0;

  Timer? _tick;
  int _sinceSync = 0;
  JobWatch? _events;

  /// Seconds between roster / clock resyncs — the FALLBACK: the code itself is re-read when its rotation ends
  /// (secondsLeft == 0), and a check-in arrives as the live event `attendance_roster_updated{session_id}` (or any
  /// `attention_changed`), which resyncs at once. The backend must emit `attendance_roster_updated` from the
  /// check-in path (services/attendance_service.py) — until it does, the roster is 30 s behind at most.
  static const _syncEvery = 30;

  bool get isOpen => window != null && !closed && (code?.isOpen ?? true);
  bool get isClosing => closed && closingLeft > 0;
  /// Time left to register (until the window expires), not the code rotation.
  Duration get registrationLeft {
    final w = window;
    if (w == null || closed) return Duration.zero;
    final end = DateTime.tryParse('${w.expiresAt}Z');
    if (end == null) return Duration.zero;
    final d = end.difference(DateTime.now().toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  bool get usesCode => method != 'witnesses';
  bool get usesWitnesses => method != 'code';

  /// Prepare a fresh setup for [id] (does nothing while another window is running).
  void prepare(int id, RelayHostProvider? h, {String? title}) {
    host = h ?? host;
    if (title != null && !(isOpen && sessionId != id)) lessonTitle = title;
    if (isOpen && sessionId != id) return;
    if (window == null || closed) {
      sessionId = id;
      window = null;
      code = null;
      closed = false;
      error = null;
      closingLeft = 0;
      notifyListeners();
    }
  }

  void setMinutes(int m) => _set(() => minutes = m);
  void setMethod(String m) => _set(() {
        method = m;
        if (m == 'code') {
          requiredWitnesses = 0;
        } else if (requiredWitnesses < 1) {
          requiredWitnesses = 1;
        }
      });
  void setWitnesses(int n) => _set(() => requiredWitnesses = n.clamp(1, 10));
  void setGrace(int s) => _set(() => graceSeconds = s.clamp(0, 60));
  void setAllowWeb(bool v) => _set(() => allowWeb = v);
  void setUseLocation(bool v) => _set(() => useLocation = v);
  void setRadius(int m) => _set(() => radiusM = m.clamp(minRadius, maxRadius));
  void setWebSource(String s) => _set(() => webLocationSource = s);

  /// MOBILE: records this phone's position + Wi-Fi so the web app can use it for 10 minutes.
  Future<bool> shareLocationForWeb() async {
    error = null;
    final here = await _loc.here();
    if (here.lat == null && here.bssid == null) {
      error = locationProblemKey(_loc.lastProblem, teacher: true);   // says WHAT to switch on
      notifyListeners();
      return false;
    }
    try {
      await _repo.shareLocation(lat: here.lat, lng: here.lng, bssid: here.bssid);
      sharedFromMobile = true;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  void markWebRequest(bool v) {
    if (webLocationRequested == v) return;
    webLocationRequested = v;
    notifyListeners();
  }

  /// WEB: ask the phone for its location and wait (up to a minute) for the answer.
  Future<bool> requestFromMobile() async {
    if (waitingMobile) return false;
    waitingMobile = true;
    error = null;
    notifyListeners();
    try {
      final sent = await _repo.requestLocationFromMobile();
      if (!sent) {
        error = 'att_err_no_mobile_device';
        return false;
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (await checkSharedLocation()) return true;
      }
      error = 'att_err_mobile_no_answer';
      return false;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      waitingMobile = false;
      notifyListeners();
    }
  }

  /// WEB: is there a point shared from the phone (last 10 minutes)?
  Future<bool> checkSharedLocation() async {
    try {
      await _repo.sharedLocation();
      sharedFromMobile = true;
    } on ApiException {
      sharedFromMobile = false;
    }
    notifyListeners();
    return sharedFromMobile;
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  Future<void> open({int rotationSeconds = 45}) async {
    final id = sessionId;
    if (loading || id == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      double? lat, lng;
      String? bssid;
      if (useLocation) {
        final here = (kIsWeb && webLocationSource == 'mobile')
            ? await _repo.sharedLocation()
            : await _loc.here();
        lat = here.lat;
        lng = here.lng;
        bssid = here.bssid;
        if (lat == null && bssid == null) {
          error = (kIsWeb && webLocationSource == 'mobile')
              ? 'att_err_teacher_location'
              : locationProblemKey(_loc.lastProblem, teacher: true);
          loading = false;
          notifyListeners();
          return;
        }
      }
      window = await _repo.open(id,
          minutes: minutes,
          rotation: rotationSeconds,
          witnesses: usesWitnesses ? requiredWitnesses : 0,
          method: method,
          allowWeb: allowWeb,
          graceSeconds: graceSeconds,
          geoLat: lat,
          geoLng: lng,
          geoRadiusM: lat == null ? null : radiusM,
          wifiBssid: bssid);
      closed = false;
      closingLeft = 0;
      host?.holdForCheckIn(asTeacher: true);
      await _sync();
      _startTicker();
    } on ApiException catch (e) {
      error = e.code == 'no_shared_location' ? 'att_err_no_shared_location' : e.message;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  /// Closes on the server NOW; the server still accepts late offline relays for [graceSeconds].
  Future<void> close() async {
    final w = window;
    if (w == null || closed) return;
    loading = true;
    notifyListeners();
    try {
      await _repo.close(w.id);
      closed = true;
      closingLeft = graceSeconds;
      // The host stays visible during the grace so in-flight requests still get through.
      if (closingLeft > 0) {
        _startClosingTicker();
      } else {
        _tick?.cancel();
        host?.releaseCheckIn();
      }
    } on ApiException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  /// Forget the finished window (used by the banner's dismiss / when a new lesson is prepared).
  void clear() {
    _tick?.cancel();
    _stopEvents();
    window = null;
    code = null;
    closed = false;
    closingLeft = 0;
    error = null;
    notifyListeners();
  }

  /// Pull-to-refresh on the teacher sheet: the same code / present-count read the ticker does, at once.
  Future<void> refresh() async {
    await _sync();
    notifyListeners();
  }

  Future<void> _sync() async {
    final w = window;
    if (w == null) return;
    try {
      final c = await _repo.code(w.id);
      code = c;
      secondsLeft = c.secondsLeft;
      _sinceSync = 0;
      if (!c.isOpen && !closed) {
        closed = true;
        closingLeft = graceSeconds;
        _startClosingTicker();
      }
    } on ApiException catch (e) {
      error = e.message; // a short network blip must not blank the screen
    }
  }

  void _startTicker() {
    _tick?.cancel();
    _startEvents();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (closed) return;
      secondsLeft = secondsLeft > 0 ? secondsLeft - 1 : 0;
      _sinceSync++;
      if (secondsLeft == 0 || _sinceSync >= _syncEvery) await _sync();
      notifyListeners();
    });
  }

  /// A check-in (or any badge change) on the live bus → the present counter at once.
  void _startEvents() {
    _stopEvents();
    final sid = sessionId;
    _events = JobWatch(
      names: const {LiveEvents.attendanceRosterUpdated, LiveEvents.attentionChanged},
      match: (e) => e.type == LiveEvents.attentionChanged || e.data['session_id'] == null || '${e.data['session_id']}' == '$sid',
      onEvent: (_) async {
        if (closed || window == null) return;
        await _sync();
        notifyListeners();
      },
    );
  }

  void _stopEvents() {
    _events?.dispose();
    _events = null;
  }

  void _startClosingTicker() {
    _tick?.cancel();
    _stopEvents();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (closingLeft > 0) closingLeft--;
      if (closingLeft <= 0) {
        t.cancel();
        host?.releaseCheckIn();
      }
      notifyListeners();
    });
  }
}
