// lib/core/screen_security.dart
//
// The app window's screen protection, owned in ONE place (D-081).
//
// Protected screens (the course video player, the exam screens) call [ScreenSecurity.protect] /
// [ScreenSecurity.release] with themselves as the owner; the window is protected (Android FLAG_SECURE, iOS
// screenshot / recording prevention through screen_protector) while at least one owner holds it. Before, each
// screen switched the flag on and off by itself, so one screen's dispose could switch off another's protection,
// and a flag left on had no owner at all.
//
// A whole-screen share ([beginShare] / [endShare], room_screen_share.dart): MediaProjection (Android) and the
// ReplayKit broadcast (iOS) draw a protected window BLACK — the "NextBrain area is a black screen" in the
// presenter's share. While a share runs:
//   - with no protected screen open, an ownerless protection is cleared (Android: ShareWindowGuard.kt, which also
//     marks the Flutter view not sensitive on Android 15+; iOS: screen_protector switched off);
//   - a protected screen that is open, or opened during the share, keeps its protection: a course video or an
//     exam paper never goes out in a share (its area stays black, by design).
// [endShare] puts back exactly what the share changed.
library;

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';

class ScreenSecurity {
  ScreenSecurity._();

  static final ScreenSecurity instance = ScreenSecurity._();

  static const _channel = MethodChannel('com.example.flutter_education_app/share_window');

  final Set<Object> _owners = <Object>{};
  bool _sharing = false;

  /// Tests: replaces the platform calls (`protect` / `unprotect` / `shareBegin` / `shareEnd`).
  @visibleForTesting
  Future<void> Function(String call, Map<String, Object?> args)? debugPlatform;

  /// Tests: the platform the calls are for (defaults to the real one).
  @visibleForTesting
  TargetPlatform? debugTarget;

  /// At least one protected screen is open.
  bool get isProtected => _owners.isNotEmpty;

  /// A whole-screen share is running.
  bool get sharing => _sharing;

  /// [owner] needs the window protected (idempotent per owner).
  Future<void> protect(Object owner) async {
    if (!_owners.add(owner)) return;
    if (_owners.length == 1) await _apply(true);
  }

  /// [owner] no longer needs it; the protection goes when the last owner releases.
  Future<void> release(Object owner) async {
    if (!_owners.remove(owner)) return;
    if (_owners.isEmpty) await _apply(false);
  }

  /// The presenter starts sharing the whole screen: their own app must not be black in it.
  Future<void> beginShare() async {
    if (_sharing) return;
    _sharing = true;
    if (kIsWeb) return;
    final clear = !isProtected;
    try {
      switch (_target) {
        case TargetPlatform.android:
          await _call('shareBegin', {'clearSecure': clear});
        case TargetPlatform.iOS:
          // An ownerless protection (screen_protector's secure layer) would blank the broadcast.
          if (clear) await _call('unprotect', const {});
        default:
          break;
      }
    } catch (e) {
      log('[SEC] share begin: $e');
    }
  }

  /// The share stopped: the window is as before it (and as the open screens need it).
  Future<void> endShare() async {
    if (!_sharing) return;
    _sharing = false;
    if (kIsWeb) return;
    try {
      switch (_target) {
        case TargetPlatform.android:
          await _call('shareEnd', const {});
        case TargetPlatform.iOS:
          if (isProtected) await _call('protect', const {});
        default:
          break;
      }
    } catch (e) {
      log('[SEC] share end: $e');
    }
  }

  @visibleForTesting
  void debugReset() {
    _owners.clear();
    _sharing = false;
    debugPlatform = null;
    debugTarget = null;
  }

  TargetPlatform get _target => debugTarget ?? defaultTargetPlatform;

  Future<void> _apply(bool on) async {
    if (kIsWeb && debugPlatform == null) return;
    try {
      await _call(on ? 'protect' : 'unprotect', const {});
    } catch (e) {
      log('[SEC] ${on ? 'protect' : 'unprotect'}: $e');
    }
  }

  Future<void> _call(String call, Map<String, Object?> args) async {
    final fake = debugPlatform;
    if (fake != null) return fake(call, args);
    switch (call) {
      case 'protect':
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageWithBlur();
      case 'unprotect':
        await ScreenProtector.preventScreenshotOff();
        await ScreenProtector.protectDataLeakageWithBlurOff();
      case 'shareBegin':
        final r = await _channel.invokeMethod<Object?>('begin', args);
        log('[SEC] share window: $r');
      case 'shareEnd':
        await _channel.invokeMethod<Object?>('end');
    }
  }
}
