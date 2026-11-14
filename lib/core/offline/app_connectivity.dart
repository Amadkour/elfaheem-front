/// core/offline/app_connectivity.dart
///
/// ONE answer to "is the app online?", used by [TopRouteObserver] and the attendance buttons.
///
///   online = (the phone has a network link)  AND  (our server is reachable)
///
/// The link comes from connectivity_plus (instant). Server reachability comes from the
/// existing ThemeConfigProvider.serverUnreachable signal, fed in from main.dart, so a Wi-Fi
/// that has no real internet still counts as OFFLINE. When the link comes back, [serverProbe]
/// re-checks the server before the app is declared online again.
///
/// pubspec.yaml:  connectivity_plus: any   (already pinned in dependency_overrides)
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class AppConnectivity {
  AppConnectivity._();
  static final AppConnectivity instance = AppConnectivity._();

  /// Listen to this. `true` = online.
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// Set from main.dart: re-checks the server and returns true when it answered.
  Future<bool> Function()? serverProbe;

  bool _link = true;
  bool _server = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get isOnline => online.value;

  Future<void> init() async {
    final c = Connectivity();
    try {
      _link = _hasLink(await c.checkConnectivity());
    } catch (_) {}
    _sub ??= c.onConnectivityChanged.listen(_onLink);
    _recompute();
  }

  static bool _hasLink(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);

  Future<void> _onLink(List<ConnectivityResult> r) async {
    final had = _link;
    _link = _hasLink(r);
    if (_link && !had) {
      // Link is back: do NOT trust it yet — ask the server.
      final probe = serverProbe;
      if (probe != null) {
        try {
          _server = await probe();
        } catch (_) {
          _server = false;
        }
      }
    }
    _recompute();
  }

  /// main.dart: pass `!themeConfig.serverUnreachable` whenever it changes.
  void reportServerReachable(bool reachable) {
    _server = reachable;
    _recompute();
  }

  void _recompute() {
    final v = _link && _server;
    if (v != online.value) online.value = v;
  }

  Future<void> dispose() async => _sub?.cancel();
}
