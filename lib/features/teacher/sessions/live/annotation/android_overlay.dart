// lib/features/teacher/sessions/live/annotation/android_overlay.dart
//
// The Android whole-screen annotation overlay (D-079): while the presenter shares the WHOLE screen from Android,
// a native floating toolbar and a transparent full-screen canvas are drawn over every app
// (AnnotationOverlay.kt, TYPE_APPLICATION_OVERLAY). MediaProjection captures overlay windows, so the strokes are
// burned into the shared video and every recording; they are NOT also sent as vectors (the room's
// AnnotationController goes into burned-in mode). With drawing off the canvas lets touches through, so the
// presenter uses other apps normally.
//
// Needs "Display over other apps" (SYSTEM_ALERT_WINDOW): [requestPermission] opens the system page and answers
// once the person comes back. Refused → the in-app annotation on the share view is the fallback.
//
// Channel `com.example.flutter_education_app/annotation_overlay`:
//   Dart → native: isPermitted · requestPermission · show {labels, colors, color, thickness, rtl, surface, accent}
//                  · hide · isShowing
//   native → Dart: closed (the overlay's own close button)
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

  /// Called when the presenter closes the overlay from its own toolbar.
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

  static Future<bool> isShowing() => _bool('isShowing');

  /// Shows the toolbar + canvas over other apps. [colors] are ARGB presets (annotPresetColors; the first is also
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
        'collapse': t('تصغير الشريط', 'Collapse toolbar'),
        'expand': t('إظهار أدوات الرسم', 'Show drawing tools'),
        'close': t('إغلاق التعليق التوضيحي', 'Close annotation'),
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
