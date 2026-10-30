// live_call_service.dart — Android: the live room's microphone keeps working in the background.
//
// Android 14+ cuts the microphone of an app in the background unless a foreground service of type
// "microphone" runs. ScreenCaptureService is one while a recording or a share runs; LiveCallService.kt
// covers everyone else in the room: a low-priority notification "In a live session" whose tap and
// "Leave" action bring the app to the front (nothing is closed natively; "Leave" calls
// [LiveCallService.onLeaveRequested], where the room may ask for a confirmation). The native side
// steps aside by itself while ScreenCaptureService holds the microphone, and comes back after it.
//
// The room calls [LiveCallService.start] once connected with a microphone it publishes or may
// publish, and [LiveCallService.stop] when it leaves. Every call is a no-op on other platforms.
//
// Channel `com.example.flutter_education_app/live_call`:
//   Dart → native: start {title, text, leave, channelName} → bool · stop · isRunning → bool
//   native → Dart: leaveRequested
library;

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/live/live_room_words.dart';

class LiveCallService {
  LiveCallService._();

  static const _channel = MethodChannel('com.example.flutter_education_app/live_call');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static VoidCallback? _onLeaveRequested;
  static bool _handlerSet = false;

  /// The notification's "Leave" was tapped (the app is in front again).
  static set onLeaveRequested(VoidCallback? cb) {
    _onLeaveRequested = cb;
    if (!supported || _handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'leaveRequested') _onLeaveRequested?.call();
      return null;
    });
  }

  /// The notification's texts in the app language, for the open room's kind (D-106).
  static Map<String, String> labels() => {
        'title': liveT(null,
            ar: 'في جلسة مباشرة', en: 'In a live session', meetingAr: 'في اجتماع مباشر', meetingEn: 'In a live meeting'),
        'text': liveT(null,
            ar: 'يبقى الميكروفون يعمل في الخلفية. اضغط للعودة إلى الجلسة.',
            en: 'Your microphone keeps working in the background. Tap to return to the session.',
            meetingAr: 'يبقى الميكروفون يعمل في الخلفية. اضغط للعودة إلى الاجتماع.',
            meetingEn: 'Your microphone keeps working in the background. Tap to return to the meeting.'),
        'leave': t('مغادرة', 'Leave'),
        'channelName': t('الجلسات المباشرة', 'Live sessions'),
      };

  /// The person is in a room with a microphone: keep it alive in the background. True when the mic
  /// is covered (this service or a running share / recording); false without the microphone
  /// permission, when the system refused, or on other platforms.
  static Future<bool> start() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('start', labels()) ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      log('[LIVE] live-call service start: $e');
      return false;
    }
  }

  /// Leaving the room (idempotent).
  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } catch (e) {
      log('[LIVE] live-call service stop: $e');
    }
  }

  static Future<bool> isRunning() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } catch (_) {
      return false;
    }
  }
}
