// lib/features/teacher/sessions/live/annotation/android_overlay.dart
//
// The Android whole-screen annotation overlay (D-079, D-081): while the presenter shares the WHOLE screen from
// Android and has LEFT the app, a floating pen bubble stays over every app; tapping it opens a compact toolbar and
// a transparent full-screen canvas over the app below (AnnotationOverlay.kt, TYPE_APPLICATION_OVERLAY). Nothing
// is drawn over NextBrain itself: back in the app the windows go (the drawings are kept for the next time the
// presenter leaves), and the share stopping clears everything. The ink is AnnotationInk.kt, the same rules as
// annotation_ink.dart. MediaProjection captures overlay windows, so the strokes are
// burned into the shared video and every recording; they are NOT also sent as vectors (the room's
// AnnotationController goes into burned-in mode). With drawing off the canvas lets touches through, so the
// presenter uses other apps normally.
//
// Needs "Display over other apps" (SYSTEM_ALERT_WINDOW): [requestPermission] opens the system page and answers
// once the person comes back. Refused → the in-app annotation on the share view is the fallback.
//
// Channel `com.example.flutter_education_app/annotation_overlay`:
//   Dart → native: isPermitted · requestPermission · openSettings · show {labels, colors, color, thickness, rtl,
//                  surface, accent} (arms it for the share) · hide · isShowing (armed)
//   native → Dart: closed (the overlay could not be shown any more, e.g. the permission was revoked: the room
//                  falls back to in-app annotation)
// Every call is a no-op answering false on other platforms (and on web).
library;

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

class AndroidAnnotationOverlay {
  AndroidAnnotationOverlay._();

  static const _channel = MethodChannel('com.example.flutter_education_app/annotation_overlay');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static VoidCallback? _onClosed;
  static bool _handlerSet = false;

  /// Called when the overlay could not be shown any more (the permission was taken away while sharing).
  static set onClosed(VoidCallback? cb) {
    _onClosed = cb;
    if (!supported || _handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'closed') _onClosed?.call();
      return null;
    });
  }

  /// "Display over other apps" is granted.
  static Future<bool> isPermitted() => _bool('isPermitted');

  /// Opens the system page for "Display over other apps"; answers whether it is granted once the person
  /// returns to the app (true at once when it already was).
  static Future<bool> requestPermission() => _bool('requestPermission');

  /// Opens the system page for "Display over other apps" without waiting for an answer.
  static Future<bool> openSettings() => _bool('openSettings');

  /// Armed for the running share (the bubble shows whenever the presenter is outside the app).
  static Future<bool> isShowing() => _bool('isShowing');

  /// Arms the overlay for the running share: the bubble, toolbar and canvas appear over other apps once the
  /// presenter leaves NextBrain. [colors] are ARGB presets (annotPresetColors; the first is also
  /// the laser's), [color] the starting one, [thickness] 0..2, [surface] / [accent] the toolbar's background and
  /// selection (LivePalette.surfaceHi / accent). False when the permission is missing or the window could not be
  /// added.
  static Future<bool> show({
    required List<int> colors,
    required int color,
    int thickness = 1,
    int? surface,
    int? accent,
  }) =>
      _bool('show', {
        'colors': colors,
        'color': color,
        'thickness': thickness,
        'labels': labels(),
        'rtl': AppConfig.lang == 'ar',
        'surface': ?surface,
        'accent': ?accent,
      });

  static Future<void> hide() async {
    await _bool('hide');
  }

  /// The overlay's spoken labels / tooltips in the app language.
  static Map<String, String> labels() => {
        'pen': t('قلم', 'Pen'),
        'highlighter': t('قلم تظليل', 'Highlighter'),
        'eraser': t('ممحاة', 'Eraser'),
        'laser': t('مؤشر ليزر', 'Laser pointer'),
        'undo': t('تراجع', 'Undo'),
        'clear': t('مسح الكل', 'Clear all'),
        'color': t('اللون', 'Colour'),
        'thickness': t('السُّمك', 'Thickness'),
        'interact': t('استخدام التطبيقات (إيقاف الرسم)', 'Use apps (drawing off)'),
        'draw': t('الرسم', 'Draw'),
        'annotate': t('الرسم على الشاشة', 'Draw on the screen'),
        'minimize': t('إخفاء الأدوات (تبقى الرسوم)', 'Hide tools (drawings stay)'),
        'close': t('إنهاء الرسم ومسحه', 'Stop drawing and clear'),
        'move': t('اسحب لتحريك الشريط', 'Drag to move the toolbar'),
      };

  static Future<bool> _bool(String method, [Object? args]) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      log('[ANNOT] $method: $e');
      return false;
    }
  }
}
