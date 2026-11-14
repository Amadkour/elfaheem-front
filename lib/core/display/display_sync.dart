// lib/core/display/display_sync.dart
//
// Keeps "Display & reading" (DisplaySettings) on the person's account, so a new phone or the web opens with the
// same fonts, size and comfort options:
//
//   GET /api/v1/me/ui-prefs  → {prefs: {...}|null, updated_at: iso|null}
//   PUT /api/v1/me/ui-prefs  {prefs, updated_at}
//
// On sign-in (and once per start while signed in) the app pulls; the NEWER copy wins (`displaySyncDecision`, pure,
// unit-tested): a newer account copy is applied here, a newer device copy is pushed. Every change made on the device
// is pushed 2 s after the last one. A server without the route (bare 404 / 405) turns the sync off for the run and
// the settings simply stay on the device. Skipped for guests and while a super admin views as someone else (the
// reply would be the viewed user's).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import 'display_settings.dart';

enum DisplaySyncAction { none, applyRemote, pushLocal }

/// The server stores naive UTC ("2026-10-28T16:00:00"); an explicit offset or "Z" is kept.
DateTime? parseServerUtc(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// What to do with the account copy [remote] (updated [remoteAt]) and the device copy [local] ([localAt]).
DisplaySyncAction displaySyncDecision({
  required DisplayPrefs local,
  required DateTime? localAt,
  required DisplayPrefs? remote,
  required DateTime? remoteAt,
}) {
  if (remote == null) {
    // nothing on the account yet: publish what this device has, unless it was never touched
    return localAt == null && local.isDefault ? DisplaySyncAction.none : DisplaySyncAction.pushLocal;
  }
  if (remote == local) return DisplaySyncAction.none;
  if (localAt == null) return DisplaySyncAction.applyRemote; // a fresh device takes the account's settings
  if (remoteAt == null || localAt.isAfter(remoteAt)) return DisplaySyncAction.pushLocal;
  return DisplaySyncAction.applyRemote;
}

class DisplaySync {
  DisplaySync._();
  static final DisplaySync instance = DisplaySync._();

  static const path = '/api/v1/me/ui-prefs';

  /// The route answered a bare 404 / 405: an older server — stop trying until the next start.
  bool _unsupported = false;
  Listenable? _auth;
  bool Function()? _signedIn;
  bool Function()? _skip;
  bool _wasSignedIn = false;
  Timer? _debounce;

  /// Follows the auth state: [signedIn] true → pull now (and after every later sign-in); [skip] true (guest, view
  /// as) → no sync at all.
  void bind(Listenable auth, {required bool Function() signedIn, required bool Function() skip}) {
    if (identical(_auth, auth)) return;
    _auth?.removeListener(_onAuth);
    _auth = auth..addListener(_onAuth);
    _signedIn = signedIn;
    _skip = skip;
    DisplaySettings.instance.onLocalChange = _schedulePush;
    _wasSignedIn = false;
    _onAuth();
  }

  bool get _active => !_unsupported && (_signedIn?.call() ?? false) && !(_skip?.call() ?? true);

  void _onAuth() {
    final now = _signedIn?.call() ?? false;
    if (now && !_wasSignedIn) unawaited(pull());
    if (!now) _debounce?.cancel();
    _wasSignedIn = now;
  }

  void _schedulePush() {
    if (!_active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(push()));
  }

  Future<void> pull() async {
    if (!_active) return;
    try {
      final r = await ApiClient().get(path);
      final m = r is Map ? r : const {};
      final raw = m['prefs'];
      final remote = raw is Map ? DisplayPrefs.fromJson(Map<String, dynamic>.from(raw)) : null;
      final remoteAt = parseServerUtc(m['updated_at']);
      final s = DisplaySettings.instance;
      switch (displaySyncDecision(local: s.prefs, localAt: s.updatedAt, remote: remote, remoteAt: remoteAt)) {
        case DisplaySyncAction.applyRemote:
          await s.update(remote!, at: remoteAt ?? DateTime.now());
        case DisplaySyncAction.pushLocal:
          await push();
        case DisplaySyncAction.none:
          break;
      }
    } catch (e) {
      _handle(e);
    }
  }

  Future<void> push() async {
    if (!_active) return;
    final s = DisplaySettings.instance;
    final at = (s.updatedAt ?? DateTime.now()).toUtc();
    try {
      // naive UTC like every other server time
      await ApiClient().put(path, body: {'prefs': s.prefs.toJson(), 'updated_at': at.toIso8601String().replaceAll('Z', '')});
    } catch (e) {
      _handle(e);
    }
  }

  void _handle(Object e) {
    final a = e is ApiException ? e : null;
    final body = a == null ? null : ApiException.asMap(a.body);
    if (a != null && (a.statusCode == 405 || (a.statusCode == 404 && body?['detail'] == 'Not Found'))) {
      _unsupported = true; // the server has no such route yet: the settings stay on this device
      return;
    }
    debugPrint('[DisplaySync] $e');
  }
}
